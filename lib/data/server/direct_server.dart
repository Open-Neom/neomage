/// Direct connect HTTP/WebSocket server for headless and API mode.
///
/// Exposes a REST API for chat, session management, tool execution, and
/// configuration. Supports CORS, bearer-token authentication, request
/// logging, and per-client rate limiting.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

/// Server lifecycle status.
enum ServerStatus { stopped, starting, running, stopping, error }

/// HTTP method constants.
enum HttpMethod { get, post, put, delete }

/// Configuration for starting a [DirectServer].
class ServerConfig {
  /// Hostname or IP to bind to.
  final String host;

  /// TCP port to listen on.
  final int port;

  /// Bearer token required for authenticated endpoints.
  final String? authToken;

  /// Maximum concurrent connections.
  final int maxConnections;

  /// Allowed CORS origins. An empty list disables CORS headers.
  final List<String> corsOrigins;

  /// Path to a TLS certificate file (PEM).
  final String? tlsCert;

  /// Path to a TLS private key file (PEM).
  final String? tlsKey;

  /// Duration after which an idle connection is closed.
  final Duration idleTimeout;

  const ServerConfig({
    this.host = '127.0.0.1',
    this.port = 8080,
    this.authToken,
    this.maxConnections = 100,
    this.corsOrigins = const ['*'],
    this.tlsCert,
    this.tlsKey,
    this.idleTimeout = const Duration(minutes: 5),
  });
}

/// Describes a single API endpoint.
class ServerEndpoint {
  /// URL path pattern (e.g. `/api/chat`).
  final String path;

  /// HTTP method.
  final HttpMethod method;

  /// Human-readable description of what this endpoint does.
  final String description;

  const ServerEndpoint({
    required this.path,
    required this.method,
    required this.description,
  });

  @override
  String toString() => '${method.name.toUpperCase()} $path — $description';
}

/// Lightweight record of an incoming request for the monitoring stream.
class RequestLog {
  final DateTime timestamp;
  final String method;
  final String path;
  final int statusCode;
  final Duration latency;
  final String? clientIp;

  const RequestLog({
    required this.timestamp,
    required this.method,
    required this.path,
    required this.statusCode,
    required this.latency,
    this.clientIp,
  });

  @override
  String toString() =>
      '[$timestamp] $method $path $statusCode (${latency.inMilliseconds}ms)';
}

/// Rate-limiter state per client IP.
class _RateLimit {
  int count = 0;
  DateTime windowStart = DateTime.now();
}

/// HTTP server that exposes a REST/WebSocket API for headless usage.
///
/// Usage:
/// ```dart
/// final server = DirectServer();
/// await server.start(ServerConfig(port: 9000, authToken: 'secret'));
/// // ... server is running ...
/// await server.stop();
/// ```
class DirectServer {
  HttpServer? _httpServer;
  ServerStatus _status = ServerStatus.stopped;
  ServerConfig? _config;

  /// Active session IDs tracked by the server.
  final Map<String, Map<String, dynamic>> _sessions = {};

  /// Per-client rate limiting state.
  final Map<String, _RateLimit> _rateLimits = {};

  /// Maximum requests per client per minute.
  static const int _rateWindowRequests = 60;
  static const Duration _rateWindow = Duration(minutes: 1);

  final StreamController<RequestLog> _requestController =
      StreamController.broadcast();

  /// The current server status.
  ServerStatus get status => _status;

  /// Stream of request log entries for monitoring.
  Stream<RequestLog> get onRequest => _requestController.stream;

  /// Returns the list of registered API endpoints.
  List<ServerEndpoint> getEndpoints() => const [
    ServerEndpoint(
      path: '/api/chat',
      method: HttpMethod.post,
      description: 'Send a message and receive a streaming response.',
    ),
    ServerEndpoint(
      path: '/api/status',
      method: HttpMethod.get,
      description: 'Server health and session info.',
    ),
    ServerEndpoint(
      path: '/api/sessions',
      method: HttpMethod.get,
      description: 'List active sessions.',
    ),
    ServerEndpoint(
      path: '/api/sessions',
      method: HttpMethod.post,
      description: 'Create a new session.',
    ),
    ServerEndpoint(
      path: '/api/sessions/:id',
      method: HttpMethod.delete,
      description: 'End an active session.',
    ),
    ServerEndpoint(
      path: '/api/tools',
      method: HttpMethod.get,
      description: 'List available tools.',
    ),
    ServerEndpoint(
      path: '/api/tools/:name',
      method: HttpMethod.post,
      description: 'Execute a tool directly.',
    ),
    ServerEndpoint(
      path: '/api/config',
      method: HttpMethod.get,
      description: 'Get current configuration.',
    ),
    ServerEndpoint(
      path: '/api/config',
      method: HttpMethod.put,
      description: 'Update configuration.',
    ),
    ServerEndpoint(
      path: '/api/ws',
      method: HttpMethod.get,
      description: 'WebSocket upgrade for streaming.',
    ),
  ];

  /// Starts the server with the given [config].
  ///
  /// Binds an HTTP server (or HTTPS if TLS is configured) and begins
  /// accepting connections.
  Future<void> start(ServerConfig config) async {
    if (_status == ServerStatus.running) return;
    _status = ServerStatus.starting;
    _config = config;

    try {
      if (config.tlsCert != null && config.tlsKey != null) {
        final context = SecurityContext()
          ..useCertificateChain(config.tlsCert!)
          ..usePrivateKey(config.tlsKey!);
        _httpServer = await HttpServer.bindSecure(
          config.host,
          config.port,
          context,
        );
      } else {
        _httpServer = await HttpServer.bind(config.host, config.port);
      }

      _httpServer!.idleTimeout = config.idleTimeout;
      _status = ServerStatus.running;

      _httpServer!.listen(
        _handleRequest,
        onError: (Object error) {
          _status = ServerStatus.error;
        },
      );
    } catch (_) {
      _status = ServerStatus.error;
      rethrow;
    }
  }

  /// Gracefully shuts down the server.
  Future<void> stop() async {
    if (_status != ServerStatus.running) return;
    _status = ServerStatus.stopping;
    await _httpServer?.close();
    _httpServer = null;
    _sessions.clear();
    _rateLimits.clear();
    _status = ServerStatus.stopped;
  }

  /// Releases resources.
  void dispose() {
    _requestController.close();
    _httpServer?.close();
  }

  // ---------------------------------------------------------------------------
  // Request handling
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest request) async {
    final stopwatch = Stopwatch()..start();
    final clientIp = request.connectionInfo?.remoteAddress.address;

    // CORS preflight.
    if (_handleCors(request)) {
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }
    }

    // Rate limiting.
    if (clientIp != null && !_checkRateLimit(clientIp)) {
      await _sendJson(request, HttpStatus.tooManyRequests, {
        'error': 'Rate limit exceeded. Try again later.',
      });
      _logRequest(
        request,
        HttpStatus.tooManyRequests,
        stopwatch.elapsed,
        clientIp,
      );
      return;
    }

    // Auth check (skip for status and OPTIONS).
    if (!_checkAuth(request)) {
      await _sendJson(request, HttpStatus.unauthorized, {
        'error': 'Invalid or missing authorization token.',
      });
      _logRequest(
        request,
        HttpStatus.unauthorized,
        stopwatch.elapsed,
        clientIp,
      );
      return;
    }

    final path = request.uri.path;
    final method = request.method.toUpperCase();

    try {
      if (path == '/api/chat' && method == 'POST') {
        await _handleChat(request);
      } else if (path == '/api/status' && method == 'GET') {
        await _handleStatus(request);
      } else if (path == '/api/sessions' && method == 'GET') {
        await _handleListSessions(request);
      } else if (path == '/api/sessions' && method == 'POST') {
        await _handleCreateSession(request);
      } else if (path.startsWith('/api/sessions/') && method == 'DELETE') {
        await _handleDeleteSession(request);
      } else if (path == '/api/tools' && method == 'GET') {
        await _handleListTools(request);
      } else if (path.startsWith('/api/tools/') && method == 'POST') {
        await _handleExecuteTool(request);
      } else if (path == '/api/config' && method == 'GET') {
        await _handleGetConfig(request);
      } else if (path == '/api/config' && method == 'PUT') {
        await _handlePutConfig(request);
      } else if (path == '/api/ws' && method == 'GET') {
        await _handleWebSocket(request);
      } else {
        await _sendJson(request, HttpStatus.notFound, {
          'error': 'Not found: $method $path',
        });
      }
    } catch (e) {
      await _sendJson(request, HttpStatus.internalServerError, {
        'error': e.toString(),
      });
    }

    stopwatch.stop();
    _logRequest(
      request,
      request.response.statusCode,
      stopwatch.elapsed,
      clientIp,
    );
  }

  // ---------------------------------------------------------------------------
  // Endpoint handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleChat(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final message = body?['message'] as String?;
    if (message == null || message.isEmpty) {
      await _sendJson(request, HttpStatus.badRequest, {
        'error': 'Missing "message" field.',
      });
      return;
    }
    // Placeholder: real implementation would invoke the chat engine.
    await _sendJson(request, HttpStatus.ok, {
      'response': 'Echo: $message',
      'sessionId': body?['sessionId'],
    });
  }

  Future<void> _handleStatus(HttpRequest request) async {
    await _sendJson(request, HttpStatus.ok, {
      'status': _status.name,
      'activeSessions': _sessions.length,
      'uptime': _httpServer != null ? 'running' : 'stopped',
    });
  }

  Future<void> _handleListSessions(HttpRequest request) async {
    await _sendJson(request, HttpStatus.ok, {
      'sessions': _sessions.keys.toList(),
    });
  }

  Future<void> _handleCreateSession(HttpRequest request) async {
    final id = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _sessions[id] = {'createdAt': DateTime.now().toIso8601String()};
    await _sendJson(request, HttpStatus.created, {'sessionId': id});
  }

  Future<void> _handleDeleteSession(HttpRequest request) async {
    final id = request.uri.pathSegments.last;
    if (_sessions.remove(id) == null) {
      await _sendJson(request, HttpStatus.notFound, {
        'error': 'Session $id not found.',
      });
      return;
    }
    await _sendJson(request, HttpStatus.ok, {'deleted': id});
  }

  Future<void> _handleListTools(HttpRequest request) async {
    // Placeholder: real implementation provides tool registry.
    await _sendJson(request, HttpStatus.ok, {'tools': <String>[]});
  }

  Future<void> _handleExecuteTool(HttpRequest request) async {
    final toolName = request.uri.pathSegments.last;
    final body = await _readJsonBody(request);
    // Placeholder: real implementation dispatches to tool runner.
    await _sendJson(request, HttpStatus.ok, {
      'tool': toolName,
      'input': body,
      'output': null,
    });
  }

  Future<void> _handleGetConfig(HttpRequest request) async {
    await _sendJson(request, HttpStatus.ok, {
      'host': _config?.host,
      'port': _config?.port,
      'maxConnections': _config?.maxConnections,
    });
  }

  Future<void> _handlePutConfig(HttpRequest request) async {
    // Placeholder: real implementation merges config updates.
    final body = await _readJsonBody(request);
    await _sendJson(request, HttpStatus.ok, {'updated': body?.keys.toList()});
  }

  Future<void> _handleWebSocket(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((data) {
      // Echo for now; real implementation pipes to chat engine.
      socket.add(data);
    }, onDone: () => socket.close());
  }

  // ---------------------------------------------------------------------------
  // Middleware helpers
  // ---------------------------------------------------------------------------

  /// Applies CORS headers. Returns `true` if CORS headers were set.
  bool _handleCors(HttpRequest request) {
    final origins = _config?.corsOrigins ?? [];
    if (origins.isEmpty) return false;
    final origin = request.headers.value('origin') ?? '*';
    final allowed = origins.contains('*') || origins.contains(origin);
    if (!allowed) return false;

    request.response.headers
      ..set('Access-Control-Allow-Origin', origin)
      ..set('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type, Authorization')
      ..set('Access-Control-Max-Age', '86400');
    return true;
  }

  /// Validates the bearer token if one is configured.
  bool _checkAuth(HttpRequest request) {
    final token = _config?.authToken;
    if (token == null || token.isEmpty) return true;
    // Allow unauthenticated status checks.
    if (request.uri.path == '/api/status') return true;

    final authHeader = request.headers.value('authorization');
    if (authHeader == null) return false;
    return authHeader == 'Bearer $token';
  }

  /// Returns `false` if the client has exceeded the rate limit.
  bool _checkRateLimit(String clientIp) {
    final now = DateTime.now();
    final limit = _rateLimits.putIfAbsent(clientIp, _RateLimit.new);
    if (now.difference(limit.windowStart) > _rateWindow) {
      limit.count = 0;
      limit.windowStart = now;
    }
    limit.count++;
    return limit.count <= _rateWindowRequests;
  }

  // ---------------------------------------------------------------------------
  // I/O helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>?> _readJsonBody(HttpRequest request) async {
    try {
      final raw = await utf8.decoder.bind(request).join();
      if (raw.isEmpty) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _sendJson(
    HttpRequest request,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  void _logRequest(
    HttpRequest request,
    int statusCode,
    Duration latency,
    String? clientIp,
  ) {
    if (_requestController.isClosed) return;
    _requestController.add(
      RequestLog(
        timestamp: DateTime.now(),
        method: request.method,
        path: request.uri.path,
        statusCode: statusCode,
        latency: latency,
        clientIp: clientIp,
      ),
    );
  }
}
