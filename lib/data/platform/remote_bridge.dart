// RemoteBridge — port of neomage/src/bridge/ + src/remote/ + src/server/.
// Full remote session management: HTTP/WebSocket server, client reconnection,
// session relay, and multi-device synchronization.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

// ─── Types ───

/// Remote session state.
enum RemoteSessionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  suspended,
  expired,
  error,
}

/// Remote connection type.
enum RemoteConnectionType {
  direct, // Direct WebSocket
  relay, // Through relay server
  tunnel, // SSH tunnel
  local, // Local Unix socket
}

/// Authentication method for remote connections.
enum RemoteAuthMethod { token, apiKey, oauth, certificate, none }

/// Remote session info.
class RemoteSessionInfo {
  final String sessionId;
  final String hostId;
  final String? displayName;
  final RemoteSessionState state;
  final RemoteConnectionType connectionType;
  final DateTime connectedAt;
  final DateTime? lastActivity;
  final String? remoteAddress;
  final int? remotePort;
  final String? model;
  final String? workingDirectory;
  final int messageCount;
  final Duration latency;
  final Map<String, dynamic>? metadata;

  const RemoteSessionInfo({
    required this.sessionId,
    required this.hostId,
    this.displayName,
    this.state = RemoteSessionState.disconnected,
    this.connectionType = RemoteConnectionType.direct,
    required this.connectedAt,
    this.lastActivity,
    this.remoteAddress,
    this.remotePort,
    this.model,
    this.workingDirectory,
    this.messageCount = 0,
    this.latency = Duration.zero,
    this.metadata,
  });

  RemoteSessionInfo copyWith({
    RemoteSessionState? state,
    DateTime? lastActivity,
    int? messageCount,
    Duration? latency,
  }) => RemoteSessionInfo(
    sessionId: sessionId,
    hostId: hostId,
    displayName: displayName,
    state: state ?? this.state,
    connectionType: connectionType,
    connectedAt: connectedAt,
    lastActivity: lastActivity ?? this.lastActivity,
    remoteAddress: remoteAddress,
    remotePort: remotePort,
    model: model,
    workingDirectory: workingDirectory,
    messageCount: messageCount ?? this.messageCount,
    latency: latency ?? this.latency,
    metadata: metadata,
  );

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'hostId': hostId,
    'displayName': displayName,
    'state': state.name,
    'connectionType': connectionType.name,
    'connectedAt': connectedAt.toIso8601String(),
    'lastActivity': lastActivity?.toIso8601String(),
    'remoteAddress': remoteAddress,
    'remotePort': remotePort,
    'model': model,
    'workingDirectory': workingDirectory,
    'messageCount': messageCount,
    'latencyMs': latency.inMilliseconds,
  };
}

/// Remote message envelope.
class RemoteMessage {
  final String id;
  final String type; // 'request', 'response', 'event', 'ping', 'pong'
  final String action; // 'chat', 'tool_use', 'tool_result', 'status', etc.
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? replyTo; // For response messages

  const RemoteMessage({
    required this.id,
    required this.type,
    required this.action,
    required this.payload,
    required this.timestamp,
    this.replyTo,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'action': action,
    'payload': payload,
    'timestamp': timestamp.toIso8601String(),
    if (replyTo != null) 'replyTo': replyTo,
  };

  factory RemoteMessage.fromJson(Map<String, dynamic> json) => RemoteMessage(
    id: json['id'] as String,
    type: json['type'] as String,
    action: json['action'] as String,
    payload: json['payload'] as Map<String, dynamic>? ?? {},
    timestamp: DateTime.parse(json['timestamp'] as String),
    replyTo: json['replyTo'] as String?,
  );
}

/// Remote event for state changes.
sealed class RemoteEvent {
  const RemoteEvent();
}

class RemoteConnected extends RemoteEvent {
  final RemoteSessionInfo session;
  const RemoteConnected(this.session);
}

class RemoteDisconnected extends RemoteEvent {
  final String sessionId;
  final String? reason;
  const RemoteDisconnected(this.sessionId, [this.reason]);
}

class RemoteMessageReceived extends RemoteEvent {
  final RemoteMessage message;
  const RemoteMessageReceived(this.message);
}

class RemoteError extends RemoteEvent {
  final String message;
  final Object? error;
  const RemoteError(this.message, [this.error]);
}

class RemoteLatencyUpdated extends RemoteEvent {
  final Duration latency;
  const RemoteLatencyUpdated(this.latency);
}

// ─── Remote Client ───

/// Client for connecting to a remote Neomage session.
class RemoteClient {
  final String _url;
  final String? _authToken;
  final RemoteAuthMethod _authMethod;
  WebSocket? _socket;
  RemoteSessionState _state = RemoteSessionState.disconnected;
  final StreamController<RemoteEvent> _eventController =
      StreamController<RemoteEvent>.broadcast();
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts;
  final Duration _heartbeatInterval;
  final Duration _reconnectDelay;
  RemoteSessionInfo? _sessionInfo;
  final Map<String, Completer<RemoteMessage>> _pendingRequests = {};
  int _messageCounter = 0;
  DateTime? _lastPingSent;

  RemoteClient({
    required String url,
    String? authToken,
    RemoteAuthMethod authMethod = RemoteAuthMethod.token,
    int maxReconnectAttempts = 10,
    Duration heartbeatInterval = const Duration(seconds: 30),
    Duration reconnectDelay = const Duration(seconds: 2),
  }) : _url = url,
       _authToken = authToken,
       _authMethod = authMethod,
       _maxReconnectAttempts = maxReconnectAttempts,
       _heartbeatInterval = heartbeatInterval,
       _reconnectDelay = reconnectDelay;

  /// Current connection state.
  RemoteSessionState get state => _state;

  /// Remote event stream.
  Stream<RemoteEvent> get events => _eventController.stream;

  /// Current session info.
  RemoteSessionInfo? get sessionInfo => _sessionInfo;

  /// Connect to the remote session.
  Future<void> connect() async {
    if (_state == RemoteSessionState.connected) return;

    _setState(RemoteSessionState.connecting);

    try {
      final headers = <String, dynamic>{};
      if (_authToken != null) {
        final cleanToken = NeomageNetworkGuard.sanitizeHeaderValue(_authToken);
        switch (_authMethod) {
          case RemoteAuthMethod.token:
            headers['Authorization'] = 'Bearer $cleanToken';
          case RemoteAuthMethod.apiKey:
            headers['X-Api-Key'] = cleanToken;
          default:
            break;
        }
      }

      _socket = await WebSocket.connect(_url, headers: headers);
      _setState(RemoteSessionState.connected);
      _reconnectAttempts = 0;

      // Create session info.
      final uri = Uri.parse(_url);
      _sessionInfo = RemoteSessionInfo(
        sessionId: 'remote_${DateTime.now().millisecondsSinceEpoch}',
        hostId: uri.host,
        state: RemoteSessionState.connected,
        connectionType: RemoteConnectionType.direct,
        connectedAt: DateTime.now(),
        remoteAddress: uri.host,
        remotePort: uri.port,
      );

      _eventController.add(RemoteConnected(_sessionInfo!));

      // Start heartbeat.
      _startHeartbeat();

      // Listen for messages.
      _socket!.listen(
        (data) {
          if (data is String && data.length <= RemoteServer.maxFrameChars) {
            _handleMessage(data);
          }
        },
        onDone: () => _handleDisconnect('Connection closed'),
        onError: (e) => _handleDisconnect('Connection error: $e'),
      );
    } catch (e) {
      _setState(RemoteSessionState.error);
      _eventController.add(RemoteError('Failed to connect', e));
      _scheduleReconnect();
    }
  }

  /// Disconnect from the remote session.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    await _socket?.close();
    _socket = null;

    _setState(RemoteSessionState.disconnected);

    if (_sessionInfo != null) {
      _eventController.add(
        RemoteDisconnected(_sessionInfo!.sessionId, 'User disconnected'),
      );
    }

    // Cancel pending requests.
    for (final entry in _pendingRequests.entries) {
      entry.value.completeError(StateError('Disconnected'));
    }
    _pendingRequests.clear();
  }

  /// Send a message and wait for a response.
  Future<RemoteMessage> sendRequest(
    String action,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_state != RemoteSessionState.connected) {
      throw StateError('Not connected');
    }

    final id = _nextMessageId();
    final message = RemoteMessage(
      id: id,
      type: 'request',
      action: action,
      payload: payload,
      timestamp: DateTime.now(),
    );

    final completer = Completer<RemoteMessage>();
    _pendingRequests[id] = completer;

    _socket!.add(jsonEncode(message.toJson()));

    // Update session info.
    _sessionInfo = _sessionInfo?.copyWith(
      lastActivity: DateTime.now(),
      messageCount: (_sessionInfo?.messageCount ?? 0) + 1,
    );

    // Timeout.
    return completer.future.timeout(
      timeout,
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('Request timed out', timeout);
      },
    );
  }

  /// Send a fire-and-forget event.
  void sendEvent(String action, Map<String, dynamic> payload) {
    if (_state != RemoteSessionState.connected) return;

    final message = RemoteMessage(
      id: _nextMessageId(),
      type: 'event',
      action: action,
      payload: payload,
      timestamp: DateTime.now(),
    );

    _socket!.add(jsonEncode(message.toJson()));
  }

  /// Send a chat message to the remote session.
  Future<RemoteMessage> sendChatMessage(String content) {
    return sendRequest('chat', {'content': content});
  }

  /// Request remote session status.
  Future<RemoteMessage> getStatus() {
    return sendRequest('status', {});
  }

  // ─── Internal ───

  String _nextMessageId() {
    _messageCounter++;
    return 'msg_${DateTime.now().millisecondsSinceEpoch}_$_messageCounter';
  }

  void _setState(RemoteSessionState newState) {
    _state = newState;
    _sessionInfo = _sessionInfo?.copyWith(state: newState);
  }

  void _handleMessage(String data) {
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      final message = RemoteMessage.fromJson(json);

      // Handle pong (latency measurement).
      if (message.type == 'pong' && _lastPingSent != null) {
        final latency = DateTime.now().difference(_lastPingSent!);
        _sessionInfo = _sessionInfo?.copyWith(latency: latency);
        _eventController.add(RemoteLatencyUpdated(latency));
        return;
      }

      // Handle response to pending request.
      if (message.type == 'response' && message.replyTo != null) {
        final completer = _pendingRequests.remove(message.replyTo);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
          return;
        }
      }

      // Broadcast event.
      _eventController.add(RemoteMessageReceived(message));
    } catch (e) {
      _eventController.add(RemoteError('Failed to parse message', e));
    }
  }

  void _handleDisconnect(String reason) {
    _heartbeatTimer?.cancel();
    _socket = null;

    if (_state != RemoteSessionState.disconnected) {
      _setState(RemoteSessionState.reconnecting);
      _eventController.add(
        RemoteDisconnected(_sessionInfo?.sessionId ?? 'unknown', reason),
      );
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_state == RemoteSessionState.connected && _socket != null) {
        _lastPingSent = DateTime.now();
        _socket!.add(
          jsonEncode({
            'id': _nextMessageId(),
            'type': 'ping',
            'action': 'heartbeat',
            'payload': {},
            'timestamp': DateTime.now().toIso8601String(),
          }),
        );
      }
    });
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _setState(RemoteSessionState.expired);
      _eventController.add(
        const RemoteError('Max reconnection attempts exceeded'),
      );
      return;
    }

    _reconnectAttempts++;
    final delay =
        _reconnectDelay *
        (1 << (_reconnectAttempts - 1).clamp(0, 5)); // Exponential backoff

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => connect());
  }

  /// Dispose resources.
  void dispose() {
    disconnect();
    _eventController.close();
  }
}

// ─── Remote Server ───

/// HTTP/WebSocket server for hosting remote sessions.
class RemoteServer {
  static const int maxFrameChars = 2 * 1024 * 1024;
  static const int maxRelayBodyBytes = 2 * 1024 * 1024;

  final int port;
  final String? host;
  final String? authToken;
  final List<String> allowedOrigins;
  final int maxClients;
  HttpServer? _server;
  final Map<String, WebSocket> _clients = {};
  final StreamController<RemoteEvent> _eventController =
      StreamController<RemoteEvent>.broadcast();
  final Map<String, RemoteSessionInfo> _sessions = {};
  int _clientCounter = 0;

  RemoteServer({
    this.port = 3100,
    this.host,
    this.authToken,
    this.allowedOrigins = const [],
    this.maxClients = 32,
  });

  /// Event stream.
  Stream<RemoteEvent> get events => _eventController.stream;

  /// Connected client count.
  int get clientCount => _clients.length;

  /// Bound TCP port once running (useful when `port == 0`).
  int? get boundPort => _server?.port;

  /// Active sessions.
  List<RemoteSessionInfo> get sessions => _sessions.values.toList();

  /// Start the server.
  Future<void> start() async {
    _server = await HttpServer.bind(host ?? InternetAddress.loopbackIPv4, port);

    _server!.listen(_handleRequest);
  }

  /// Stop the server.
  Future<void> stop() async {
    // Close all client connections.
    for (final socket in _clients.values) {
      await socket.close();
    }
    _clients.clear();
    _sessions.clear();

    await _server?.close();
    _server = null;
  }

  /// Broadcast a message to all connected clients.
  void broadcast(String action, Map<String, dynamic> payload) {
    final message = RemoteMessage(
      id: 'broadcast_${DateTime.now().millisecondsSinceEpoch}',
      type: 'event',
      action: action,
      payload: payload,
      timestamp: DateTime.now(),
    );

    final data = jsonEncode(message.toJson());
    for (final socket in _clients.values) {
      socket.add(data);
    }
  }

  /// Send a message to a specific client.
  void sendTo(String clientId, RemoteMessage message) {
    final socket = _clients[clientId];
    if (socket != null) {
      socket.add(jsonEncode(message.toJson()));
    }
  }

  // ─── Internal ───

  Future<void> _handleRequest(HttpRequest request) async {
    // Reject cross-site browser Origin headers (CSWSH & local CORS defense).
    final origin = request.headers.value('Origin');
    if (!NeomageNetworkGuard.isAllowedLocalServerOrigin(
      origin,
      allowedOrigins: allowedOrigins,
    )) {
      request.response.statusCode = HttpStatus.forbidden;
      request.response.write('Cross-origin request blocked');
      await request.response.close();
      return;
    }

    if (origin != null) {
      request.response.headers
        ..set(
          'Access-Control-Allow-Origin',
          NeomageNetworkGuard.sanitizeHeaderValue(origin),
        )
        ..set('Vary', 'Origin')
        ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        ..set(
          'Access-Control-Allow-Headers',
          'Authorization, Content-Type, X-Api-Key',
        );
    }

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    // Constant-time auth check.
    if (authToken != null && authToken!.isNotEmpty) {
      final cleanExpected = NeomageNetworkGuard.sanitizeHeaderValue(authToken!);
      final auth = request.headers.value('Authorization');
      final apiKey = request.headers.value('X-Api-Key');
      final queryToken = request.uri.queryParameters['token'];
      final authorized =
          NeomageNetworkGuard.constantTimeEquals(auth, 'Bearer $cleanExpected') ||
          NeomageNetworkGuard.constantTimeEquals(apiKey, cleanExpected) ||
          NeomageNetworkGuard.constantTimeEquals(queryToken, cleanExpected);
      if (!authorized) {
        request.response.statusCode = 401;
        request.response.write('Unauthorized');
        await request.response.close();
        return;
      }
    }

    final path = request.uri.path;

    // REST endpoints.
    switch (path) {
      case '/api/status':
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'status': 'running',
            'clients': _clients.length,
            'sessions': _sessions.values.map((s) => s.toJson()).toList(),
            'uptime': _server != null ? DateTime.now().toIso8601String() : null,
          }),
        );
        await request.response.close();

      case '/api/sessions':
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(_sessions.values.map((s) => s.toJson()).toList()),
        );
        await request.response.close();

      case '/ws':
      case '/':
        // WebSocket upgrade (restricted to explicit WS endpoints + maxClients).
        if (!WebSocketTransformer.isUpgradeRequest(request)) {
          request.response.statusCode = 400;
          request.response.write('Expected WebSocket upgrade');
          await request.response.close();
          return;
        }
        if (_clients.length >= maxClients) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('Too many active connections');
          await request.response.close();
          return;
        }
        final socket = await WebSocketTransformer.upgrade(request);
        _handleWebSocket(socket, request);

      default:
        request.response.statusCode = 404;
        request.response.write('Not found');
        await request.response.close();
    }
  }

  void _handleWebSocket(WebSocket socket, HttpRequest request) {
    _clientCounter++;
    final clientId = 'client_$_clientCounter';
    _clients[clientId] = socket;

    final session = RemoteSessionInfo(
      sessionId: clientId,
      hostId: Platform.localHostname,
      state: RemoteSessionState.connected,
      connectionType: RemoteConnectionType.direct,
      connectedAt: DateTime.now(),
      remoteAddress: request.connectionInfo?.remoteAddress.host,
      remotePort: request.connectionInfo?.remotePort,
    );
    _sessions[clientId] = session;

    _eventController.add(RemoteConnected(session));

    // Send welcome message.
    socket.add(
      jsonEncode(
        RemoteMessage(
          id: 'welcome',
          type: 'event',
          action: 'connected',
          payload: {
            'clientId': clientId,
            'serverVersion': '1.0.0',
            'capabilities': ['chat', 'tools', 'streaming', 'status'],
          },
          timestamp: DateTime.now(),
        ).toJson(),
      ),
    );

    socket.listen(
      (data) {
        try {
          if (data is! String || data.length > maxFrameChars) {
            socket.close(WebSocketStatus.messageTooBig, 'Invalid or oversized frame');
            return;
          }
          final message = RemoteMessage.fromJson(
            jsonDecode(data) as Map<String, dynamic>,
          );

          // Handle ping.
          if (message.type == 'ping') {
            socket.add(
              jsonEncode(
                RemoteMessage(
                  id: message.id,
                  type: 'pong',
                  action: 'heartbeat',
                  payload: {},
                  timestamp: DateTime.now(),
                  replyTo: message.id,
                ).toJson(),
              ),
            );
            return;
          }

          // Update session activity.
          _sessions[clientId] = session.copyWith(
            lastActivity: DateTime.now(),
            messageCount: (_sessions[clientId]?.messageCount ?? 0) + 1,
          );

          _eventController.add(RemoteMessageReceived(message));
        } catch (e) {
          _eventController.add(
            RemoteError('Failed to parse client message', e),
          );
        }
      },
      onDone: () {
        _clients.remove(clientId);
        _sessions.remove(clientId);
        _eventController.add(
          RemoteDisconnected(clientId, 'Client disconnected'),
        );
      },
      onError: (e) {
        _clients.remove(clientId);
        _sessions.remove(clientId);
        _eventController.add(RemoteDisconnected(clientId, 'Error: $e'));
      },
    );
  }

  /// Dispose resources.
  void dispose() {
    stop();
    _eventController.close();
  }
}

// ─── Session Relay ───

/// Relay service for connecting remote sessions through an intermediary.
class SessionRelay {
  final String relayUrl;
  final String? relayToken;
  WebSocket? _socket;
  final StreamController<RemoteEvent> _eventController =
      StreamController<RemoteEvent>.broadcast();
  Timer? _heartbeatTimer;

  SessionRelay({required this.relayUrl, this.relayToken});

  /// Event stream.
  Stream<RemoteEvent> get events => _eventController.stream;

  /// Register this host with the relay.
  Future<String> registerHost({
    required String displayName,
    Map<String, dynamic>? capabilities,
  }) async {
    final relayUri = Uri.tryParse(relayUrl.trim());
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      relayUri,
      secureSchemes: const <String>{'wss'},
      insecureSchemes: const <String>{'ws'},
    )) {
      throw ArgumentError.value(
        NeomageNetworkGuard.redactUrlCredentials(relayUrl),
        'relayUrl',
        'Unsafe relay WebSocket URL',
      );
    }
    final cleanToken = relayToken != null
        ? NeomageNetworkGuard.sanitizeHeaderValue(relayToken!)
        : null;

    _socket = await WebSocket.connect(
      relayUri!.toString(),
      headers: {if (cleanToken != null) 'Authorization': 'Bearer $cleanToken'},
    );

    final registrationId = 'host_${DateTime.now().millisecondsSinceEpoch}';

    _socket!.add(
      jsonEncode({
        'type': 'register',
        'hostId': registrationId,
        'displayName': displayName,
        'capabilities': capabilities ?? {},
      }),
    );

    // Start heartbeat.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _socket?.add(jsonEncode({'type': 'heartbeat', 'hostId': registrationId}));
    });

    _socket!.listen(
      (data) {
        try {
          if (data is! String || data.length > RemoteServer.maxFrameChars) {
            return;
          }
          final message = RemoteMessage.fromJson(
            jsonDecode(data) as Map<String, dynamic>,
          );
          _eventController.add(RemoteMessageReceived(message));
        } catch (_) {}
      },
      onDone: () {
        _eventController.add(
          const RemoteDisconnected('relay', 'Relay disconnected'),
        );
      },
    );

    return registrationId;
  }

  /// Connect to a host through the relay.
  Future<void> connectToHost(String hostId) async {
    _socket?.add(jsonEncode({'type': 'connect', 'targetHostId': hostId}));
  }

  /// List available hosts on the relay.
  Future<List<Map<String, dynamic>>> listHosts() async {
    final relayUri = Uri.tryParse(relayUrl.trim());
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      relayUri,
      secureSchemes: const <String>{'wss', 'https'},
      insecureSchemes: const <String>{'ws', 'http'},
    )) {
      throw ArgumentError.value(
        NeomageNetworkGuard.redactUrlCredentials(relayUrl),
        'relayUrl',
        'Unsafe relay URL',
      );
    }
    final httpScheme =
        (relayUri!.scheme == 'wss' || relayUri.scheme == 'https')
        ? 'https'
        : 'http';
    final uri = relayUri.replace(scheme: httpScheme, path: '/api/hosts');

    final client = HttpClient();
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      if (relayToken != null) {
        final cleanToken = NeomageNetworkGuard.sanitizeHeaderValue(relayToken!);
        request.headers.set('Authorization', 'Bearer $cleanToken');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode != 200) {
        await response.drain<void>();
        return const <Map<String, dynamic>>[];
      }
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 15))) {
        if (buffer.length + chunk.length > RemoteServer.maxRelayBodyBytes) {
          throw const FormatException('Relay host list exceeds 2 MiB');
        }
        buffer.add(chunk);
      }
      final decoded = jsonDecode(utf8.decode(buffer.takeBytes()));
      if (decoded is! List) return const <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
    } finally {
      client.close();
    }
  }

  /// Disconnect from relay.
  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    await _socket?.close();
    _socket = null;
  }

  /// Dispose resources.
  void dispose() {
    disconnect();
    _eventController.close();
  }
}

// ─── Discovery ───

/// Discovers remote sessions on the local network.
class RemoteDiscovery {
  static const int maxScanResponseBytes = 256 * 1024;
  static const int maxScannedPorts = 32;

  /// Scan for remote sessions on common ports.
  static Future<List<RemoteSessionInfo>> scan({
    String subnet = '127.0.0.1',
    List<int> ports = const [3100, 3101, 3102, 3103, 3104],
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final cleanSubnet = subnet.trim();
    if (!NeomageNetworkGuard.isSafeLanDiscoveryHost(cleanSubnet)) {
      return const <RemoteSessionInfo>[];
    }
    final results = <RemoteSessionInfo>[];
    final validPorts = ports
        .where((p) => p >= 1 && p <= 65535)
        .take(maxScannedPorts);

    for (final port in validPorts) {
      final client = HttpClient();
      try {
        client.connectionTimeout = timeout;

        final request = await client
            .getUrl(Uri.parse('http://$cleanSubnet:$port/api/status'))
            .timeout(timeout);
        request.followRedirects = false;
        final response = await request.close().timeout(timeout);

        if (response.statusCode == 200) {
          final buffer = BytesBuilder(copy: false);
          await for (final chunk in response.timeout(timeout)) {
            if (buffer.length + chunk.length > maxScanResponseBytes) {
              throw const FormatException('Discovery response too large');
            }
            buffer.add(chunk);
          }
          final decoded = jsonDecode(utf8.decode(buffer.takeBytes()));
          if (decoded is Map<String, dynamic>) {
            results.add(
              RemoteSessionInfo(
                sessionId: 'discovered_${cleanSubnet}_$port',
                hostId: cleanSubnet,
                displayName:
                    decoded['displayName'] as String? ?? '$cleanSubnet:$port',
                state: RemoteSessionState.connected,
                connectionType: RemoteConnectionType.direct,
                connectedAt: DateTime.now(),
                remoteAddress: cleanSubnet,
                remotePort: port,
                model: decoded['model'] as String?,
                metadata: decoded,
              ),
            );
          }
        } else {
          await response.drain<void>();
        }
      } catch (_) {
        // Host/port not available.
      } finally {
        client.close(force: true);
      }
    }

    return results;
  }

  /// Generate a connection URL for sharing.
  static String generateConnectionUrl({
    required String host,
    required int port,
    String? token,
    bool secure = false,
  }) {
    final scheme = secure ? 'wss' : 'ws';
    final uri = Uri(
      scheme: scheme,
      host: host.trim(),
      port: port,
      path: '/ws',
      queryParameters: (token != null && token.isNotEmpty)
          ? <String, String>{'token': token}
          : null,
    );
    return uri.toString();
  }

  /// Parse a connection URL.
  static ({String host, int port, String? token}) parseConnectionUrl(
    String url,
  ) {
    final uri = Uri.parse(url);
    return (
      host: uri.host,
      port: uri.port,
      token: uri.queryParameters['token'],
    );
  }
}
