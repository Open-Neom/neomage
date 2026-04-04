// MCP transport layer — port of neom_claw/src/services/mcp/ transports.
// Stdio, SSE, HTTP, WebSocket transports, JSON-RPC protocol, server lifecycle.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'mcp_types.dart';

// ════════════════════════════════════════════════════════════════════════════
// JSON-RPC 2.0 message types
// ════════════════════════════════════════════════════════════════════════════

/// Base class for all JSON-RPC 2.0 messages.
sealed class JsonRpcMessage {
  const JsonRpcMessage();

  Map<String, dynamic> toJson();

  static JsonRpcMessage fromJson(Map<String, dynamic> json) {
    if (json.containsKey('method')) {
      if (json.containsKey('id') && json['id'] != null) {
        return JsonRpcRequest(
          id: json['id'],
          method: json['method'] as String,
          params: json['params'] as Map<String, dynamic>?,
        );
      }
      return JsonRpcNotification(
        method: json['method'] as String,
        params: json['params'] as Map<String, dynamic>?,
      );
    }
    if (json.containsKey('result') || json.containsKey('error')) {
      return JsonRpcResponse(
        id: json['id'],
        result: json['result'],
        error: json['error'] != null
            ? JsonRpcError.fromJson(json['error'] as Map<String, dynamic>)
            : null,
      );
    }
    throw FormatException('Invalid JSON-RPC message: ${jsonEncode(json)}');
  }
}

/// JSON-RPC 2.0 request (has method, params, and id).
class JsonRpcRequest extends JsonRpcMessage {
  final dynamic id;
  final String method;
  final Map<String, dynamic>? params;

  const JsonRpcRequest({required this.id, required this.method, this.params});

  @override
  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  };
}

/// JSON-RPC 2.0 response (has result or error, and id).
class JsonRpcResponse extends JsonRpcMessage {
  final dynamic id;
  final dynamic result;
  final JsonRpcError? error;

  const JsonRpcResponse({required this.id, this.result, this.error});

  bool get isError => error != null;

  @override
  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'id': id,
    if (error != null) 'error': error!.toJson(),
    if (error == null) 'result': result,
  };
}

/// JSON-RPC 2.0 notification (has method and params, but no id).
class JsonRpcNotification extends JsonRpcMessage {
  final String method;
  final Map<String, dynamic>? params;

  const JsonRpcNotification({required this.method, this.params});

  @override
  Map<String, dynamic> toJson() => {
    'jsonrpc': '2.0',
    'method': method,
    if (params != null) 'params': params,
  };
}

/// JSON-RPC 2.0 error object.
class JsonRpcError {
  final int code;
  final String message;
  final dynamic data;

  const JsonRpcError({required this.code, required this.message, this.data});

  factory JsonRpcError.fromJson(Map<String, dynamic> json) => JsonRpcError(
    code: json['code'] as int,
    message: json['message'] as String? ?? '',
    data: json['data'],
  );

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (data != null) 'data': data,
  };

  @override
  String toString() => 'JsonRpcError($code: $message)';
}

/// Standard JSON-RPC error codes.
abstract class JsonRpcErrorCodes {
  static const parseError = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internalError = -32603;
  // MCP-specific codes
  static const serverNotInitialized = -32002;
  static const requestCancelled = -32800;
}

// ════════════════════════════════════════════════════════════════════════════
// Transport abstraction
// ════════════════════════════════════════════════════════════════════════════

/// Transport type enum for identifying the underlying wire protocol.
enum TransportType { stdio, sse, http, websocket }

/// Abstract transport layer for MCP communication.
abstract class McpTransport {
  /// Stream of incoming JSON-RPC messages from the server.
  Stream<JsonRpcMessage> get messages;

  /// Send a JSON-RPC message to the server.
  Future<void> send(JsonRpcMessage message);

  /// Establish the connection.
  Future<void> connect();

  /// Close the connection and release resources.
  Future<void> close();

  /// Whether the transport is currently connected.
  bool get isConnected;

  /// The transport type.
  TransportType get type;
}

// ════════════════════════════════════════════════════════════════════════════
// Content-Length framing codec for stdio transport
// ════════════════════════════════════════════════════════════════════════════

/// Encodes and decodes Content-Length framed JSON-RPC messages,
/// matching the LSP base protocol used by MCP over stdio.
class ContentLengthCodec {
  static const _headerSeparator = '\r\n\r\n';
  static const _contentLengthPrefix = 'Content-Length: ';

  final _buffer = BytesBuilder(copy: false);

  /// Encode a JSON-RPC message into a Content-Length framed byte sequence.
  List<int> encode(JsonRpcMessage message) {
    final body = utf8.encode(jsonEncode(message.toJson()));
    final header = utf8.encode(
      '$_contentLengthPrefix${body.length}$_headerSeparator',
    );
    return [...header, ...body];
  }

  /// Feed raw bytes from stdout and yield complete messages.
  /// Handles partial reads and multiple messages in a single chunk.
  Iterable<JsonRpcMessage> decode(List<int> chunk) sync* {
    _buffer.add(chunk);
    final bytes = _buffer.toBytes();

    var offset = 0;
    while (offset < bytes.length) {
      // Find header separator
      final headerEnd = _indexOf(bytes, _headerSeparator, offset);
      if (headerEnd < 0) break;

      // Parse Content-Length from header block
      final headerStr = utf8.decode(bytes.sublist(offset, headerEnd));
      final contentLength = _parseContentLength(headerStr);
      if (contentLength == null) break;

      final bodyStart = headerEnd + _headerSeparator.length;
      final bodyEnd = bodyStart + contentLength;
      if (bodyEnd > bytes.length) break; // incomplete body

      final bodyStr = utf8.decode(bytes.sublist(bodyStart, bodyEnd));
      offset = bodyEnd;

      try {
        final json = jsonDecode(bodyStr) as Map<String, dynamic>;
        yield JsonRpcMessage.fromJson(json);
      } on FormatException {
        // Skip malformed messages
      }
    }

    // Keep unconsumed bytes in buffer
    _buffer.clear();
    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
  }

  /// Reset internal buffer state.
  void reset() => _buffer.clear();

  int _indexOf(List<int> haystack, String needle, int start) {
    final needleBytes = utf8.encode(needle);
    outer:
    for (var i = start; i <= haystack.length - needleBytes.length; i++) {
      for (var j = 0; j < needleBytes.length; j++) {
        if (haystack[i + j] != needleBytes[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  int? _parseContentLength(String header) {
    for (final line in header.split('\r\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith(_contentLengthPrefix)) {
        return int.tryParse(trimmed.substring(_contentLengthPrefix.length));
      }
      // Also handle lowercase per spec tolerance
      if (trimmed.toLowerCase().startsWith('content-length:')) {
        return int.tryParse(trimmed.split(':').last.trim());
      }
    }
    return null;
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Stdio transport
// ════════════════════════════════════════════════════════════════════════════

/// Stdio transport -- spawns a child process and communicates via
/// Content-Length framed JSON-RPC over stdin/stdout.
class StdioTransport extends McpTransport {
  final String command;
  final List<String> args;
  final Map<String, String>? environment;
  final String? workingDirectory;

  Process? _process;
  final _codec = ContentLengthCodec();
  final _controller = StreamController<JsonRpcMessage>.broadcast();
  StreamSubscription<List<int>>? _stdoutSub;
  StreamSubscription<List<int>>? _stderrSub;
  bool _connected = false;
  final List<String> _stderrLog = [];

  StdioTransport({
    required this.command,
    required this.args,
    this.environment,
    this.workingDirectory,
  });

  @override
  Stream<JsonRpcMessage> get messages => _controller.stream;

  @override
  TransportType get type => TransportType.stdio;

  @override
  bool get isConnected => _connected;

  /// Recent stderr output from the child process (for diagnostics).
  List<String> get stderrLog => List.unmodifiable(_stderrLog);

  @override
  Future<void> connect() async {
    if (_connected) return;

    _process = await Process.start(
      command,
      args,
      environment: environment,
      workingDirectory: workingDirectory,
    );

    _connected = true;

    // Listen to stdout, decode Content-Length framed messages.
    _stdoutSub = _process!.stdout.listen(
      (chunk) {
        for (final msg in _codec.decode(chunk)) {
          _controller.add(msg);
        }
      },
      onError: (Object e) {
        _controller.addError(McpTransportException('Stdout error: $e'));
      },
      onDone: () {
        _connected = false;
        _controller.addError(
          const McpTransportException('Server process stdout closed'),
        );
      },
    );

    // Capture stderr for diagnostics (not JSON-RPC, just logging).
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map((line) {
          // Keep last 200 lines
          _stderrLog.add(line);
          if (_stderrLog.length > 200) _stderrLog.removeAt(0);
          return utf8.encode(line);
        })
        .listen(null);

    // Detect process exit.
    _process!.exitCode.then((code) {
      _connected = false;
      if (!_controller.isClosed) {
        _controller.addError(
          McpTransportException('Server process exited with code $code'),
        );
      }
    });
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    final process = _process;
    if (process == null || !_connected) {
      throw const McpTransportException('Transport not connected');
    }
    final bytes = _codec.encode(message);
    process.stdin.add(bytes);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    _connected = false;
    _codec.reset();
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();

    final process = _process;
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      // Wait briefly for graceful exit, then force-kill.
      final exitCode = await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      _stderrLog.add('[transport] Process exited: $exitCode');
    }

    _process = null;
    await _controller.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// SSE transport
// ════════════════════════════════════════════════════════════════════════════

/// SSE (Server-Sent Events) transport.
/// Receives messages via an SSE stream and sends messages via HTTP POST
/// to an endpoint provided by the server.
class SseTransport extends McpTransport {
  final Uri endpoint;
  final Map<String, String>? headers;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;

  HttpClient? _httpClient;
  final _controller = StreamController<JsonRpcMessage>.broadcast();
  StreamSubscription<String>? _sseSub;
  bool _connected = false;
  String? _postEndpoint;
  String? _lastEventId;
  int _reconnectAttempts = 0;
  bool _closing = false;

  SseTransport({
    required this.endpoint,
    this.headers,
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectAttempts = 10,
  });

  @override
  Stream<JsonRpcMessage> get messages => _controller.stream;

  @override
  TransportType get type => TransportType.sse;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _closing = false;
    _httpClient = HttpClient();

    await _connectSse();
  }

  Future<void> _connectSse() async {
    final client = _httpClient;
    if (client == null || _closing) return;

    try {
      final request = await client.getUrl(endpoint);
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');
      if (_lastEventId != null) {
        request.headers.set('Last-Event-ID', _lastEventId!);
      }
      headers?.forEach((k, v) => request.headers.set(k, v));

      final response = await request.close();
      if (response.statusCode != 200) {
        throw McpTransportException(
          'SSE connection failed: HTTP ${response.statusCode}',
        );
      }

      _connected = true;
      _reconnectAttempts = 0;

      // Parse the SSE stream.
      _sseSub = response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) => _processSseLine(line),
            onError: (Object e) {
              _connected = false;
              _scheduleReconnect();
            },
            onDone: () {
              _connected = false;
              _scheduleReconnect();
            },
          );
    } catch (e) {
      _connected = false;
      if (!_closing) _scheduleReconnect();
    }
  }

  // SSE line parsing state
  String _sseEventType = 'message';
  final _sseDataBuffer = StringBuffer();

  void _processSseLine(String line) {
    if (line.isEmpty) {
      // Empty line = dispatch event
      _dispatchSseEvent(_sseEventType, _sseDataBuffer.toString().trimRight());
      _sseEventType = 'message';
      _sseDataBuffer.clear();
      return;
    }

    if (line.startsWith(':')) return; // comment

    String field;
    String value;
    final colonIdx = line.indexOf(':');
    if (colonIdx < 0) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colonIdx);
      value = line.substring(colonIdx + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }

    switch (field) {
      case 'event':
        _sseEventType = value;
      case 'data':
        if (_sseDataBuffer.isNotEmpty) _sseDataBuffer.write('\n');
        _sseDataBuffer.write(value);
      case 'id':
        if (!value.contains('0')) _lastEventId = value;
      case 'retry':
        // Could adjust reconnect delay here; ignored for simplicity.
        break;
    }
  }

  void _dispatchSseEvent(String type, String data) {
    if (data.isEmpty) return;

    switch (type) {
      case 'endpoint':
        // Server tells us where to POST messages.
        _postEndpoint = _resolveEndpoint(data.trim());
      case 'message':
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          _controller.add(JsonRpcMessage.fromJson(json));
        } on FormatException {
          // Ignore malformed messages.
        }
    }
  }

  String _resolveEndpoint(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    // Relative path: resolve against the SSE endpoint.
    return endpoint.resolve(path).toString();
  }

  void _scheduleReconnect() {
    if (_closing) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _controller.addError(
        const McpTransportException('SSE max reconnect attempts exceeded'),
      );
      return;
    }
    _reconnectAttempts++;
    final delay = reconnectDelay * pow(2, _reconnectAttempts - 1);
    final clamped = delay > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : delay;
    Future.delayed(clamped, _connectSse);
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    final postUrl = _postEndpoint;
    if (postUrl == null || !_connected) {
      throw const McpTransportException(
        'SSE transport: no POST endpoint available',
      );
    }

    final client = _httpClient;
    if (client == null) {
      throw const McpTransportException('SSE transport not connected');
    }

    final request = await client.postUrl(Uri.parse(postUrl));
    request.headers.set('Content-Type', 'application/json');
    headers?.forEach((k, v) => request.headers.set(k, v));
    request.write(jsonEncode(message.toJson()));

    final response = await request.close();
    await response.drain<void>();

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw McpTransportException(
        'SSE POST failed: HTTP ${response.statusCode}',
      );
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _connected = false;
    await _sseSub?.cancel();
    _httpClient?.close(force: true);
    _httpClient = null;
    _postEndpoint = null;
    _lastEventId = null;
    _sseDataBuffer.clear();
    await _controller.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// HTTP transport (Streamable HTTP)
// ════════════════════════════════════════════════════════════════════════════

/// HTTP transport -- sends each JSON-RPC message as an HTTP POST and
/// receives the response in the reply body. Optionally supports session
/// management via Mcp-Session-Id headers.
class HttpTransport extends McpTransport {
  final Uri endpoint;
  final Map<String, String>? headers;
  final Duration requestTimeout;

  HttpClient? _httpClient;
  final _controller = StreamController<JsonRpcMessage>.broadcast();
  bool _connected = false;
  String? _sessionId;

  HttpTransport({
    required this.endpoint,
    this.headers,
    this.requestTimeout = const Duration(seconds: 30),
  });

  @override
  Stream<JsonRpcMessage> get messages => _controller.stream;

  @override
  TransportType get type => TransportType.http;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _httpClient = HttpClient();
    _connected = true;
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    final client = _httpClient;
    if (client == null || !_connected) {
      throw const McpTransportException('HTTP transport not connected');
    }

    final request = await client.postUrl(endpoint);
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Accept', 'application/json, text/event-stream');
    if (_sessionId != null) {
      request.headers.set('Mcp-Session-Id', _sessionId!);
    }
    headers?.forEach((k, v) => request.headers.set(k, v));
    request.write(jsonEncode(message.toJson()));

    final response = await request.close().timeout(requestTimeout);

    // Capture session id from response headers.
    final sid = response.headers.value('Mcp-Session-Id');
    if (sid != null) _sessionId = sid;

    final contentType = response.headers.contentType;

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.transform(utf8.decoder).join();
      throw McpTransportException(
        'HTTP POST failed: ${response.statusCode} — $body',
      );
    }

    // The response may be JSON or SSE (streamed).
    if (contentType?.mimeType == 'text/event-stream') {
      // Stream SSE events from the response body.
      await _readSseResponse(response);
    } else {
      // Single JSON response.
      final body = await response.transform(utf8.decoder).join();
      if (body.isEmpty) return;

      try {
        // Could be a single message or a batch (array).
        final decoded = jsonDecode(body);
        if (decoded is List) {
          for (final item in decoded) {
            _controller.add(
              JsonRpcMessage.fromJson(item as Map<String, dynamic>),
            );
          }
        } else if (decoded is Map<String, dynamic>) {
          _controller.add(JsonRpcMessage.fromJson(decoded));
        }
      } on FormatException {
        // Ignore malformed responses.
      }
    }
  }

  Future<void> _readSseResponse(HttpClientResponse response) async {
    String eventType = 'message';
    final dataBuf = StringBuffer();

    await for (final line
        in response.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.isEmpty) {
        // Dispatch event.
        if (dataBuf.isNotEmpty) {
          final data = dataBuf.toString().trimRight();
          dataBuf.clear();
          if (eventType == 'message' && data.isNotEmpty) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              _controller.add(JsonRpcMessage.fromJson(json));
            } on FormatException {
              // skip
            }
          }
        }
        eventType = 'message';
        continue;
      }
      if (line.startsWith(':')) continue;
      final colonIdx = line.indexOf(':');
      if (colonIdx < 0) continue;
      final field = line.substring(0, colonIdx);
      var value = line.substring(colonIdx + 1);
      if (value.startsWith(' ')) value = value.substring(1);

      switch (field) {
        case 'event':
          eventType = value;
        case 'data':
          if (dataBuf.isNotEmpty) dataBuf.write('\n');
          dataBuf.write(value);
      }
    }
  }

  @override
  Future<void> close() async {
    _connected = false;

    // Send session termination via DELETE if we have a session.
    if (_sessionId != null) {
      try {
        final client = _httpClient;
        if (client != null) {
          final request = await client.deleteUrl(endpoint);
          request.headers.set('Mcp-Session-Id', _sessionId!);
          headers?.forEach((k, v) => request.headers.set(k, v));
          final response = await request.close().timeout(
            const Duration(seconds: 5),
          );
          await response.drain<void>();
        }
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    _httpClient?.close(force: true);
    _httpClient = null;
    _sessionId = null;
    await _controller.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// WebSocket transport
// ════════════════════════════════════════════════════════════════════════════

/// WebSocket transport -- persistent bidirectional connection.
class WebSocketTransport extends McpTransport {
  final Uri endpoint;
  final Map<String, String>? headers;
  final Duration pingInterval;
  final Duration reconnectDelay;
  final int maxReconnectAttempts;

  WebSocket? _socket;
  final _controller = StreamController<JsonRpcMessage>.broadcast();
  StreamSubscription<dynamic>? _socketSub;
  Timer? _pingTimer;
  bool _connected = false;
  bool _closing = false;
  int _reconnectAttempts = 0;

  WebSocketTransport({
    required this.endpoint,
    this.headers,
    this.pingInterval = const Duration(seconds: 30),
    this.reconnectDelay = const Duration(seconds: 1),
    this.maxReconnectAttempts = 10,
  });

  @override
  Stream<JsonRpcMessage> get messages => _controller.stream;

  @override
  TransportType get type => TransportType.websocket;

  @override
  bool get isConnected => _connected;

  @override
  Future<void> connect() async {
    if (_connected) return;
    _closing = false;
    await _connectWs();
  }

  Future<void> _connectWs() async {
    if (_closing) return;

    try {
      _socket = await WebSocket.connect(endpoint.toString(), headers: headers);
      _connected = true;
      _reconnectAttempts = 0;

      _startPing();

      _socketSub = _socket!.listen(
        (dynamic data) {
          if (data is! String) return; // ignore binary frames
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            _controller.add(JsonRpcMessage.fromJson(json));
          } on FormatException {
            // skip
          }
        },
        onError: (Object e) {
          _connected = false;
          _stopPing();
          _scheduleReconnect();
        },
        onDone: () {
          _connected = false;
          _stopPing();
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _connected = false;
      if (!_closing) _scheduleReconnect();
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) {
      try {
        _socket?.add(''); // WebSocket ping (empty text frame as keepalive)
      } catch (_) {}
    });
  }

  void _stopPing() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  void _scheduleReconnect() {
    if (_closing) return;
    if (_reconnectAttempts >= maxReconnectAttempts) {
      _controller.addError(
        const McpTransportException(
          'WebSocket max reconnect attempts exceeded',
        ),
      );
      return;
    }
    _reconnectAttempts++;
    final delay = reconnectDelay * pow(2, _reconnectAttempts - 1);
    final clamped = delay > const Duration(seconds: 30)
        ? const Duration(seconds: 30)
        : delay;
    Future.delayed(clamped, _connectWs);
  }

  @override
  Future<void> send(JsonRpcMessage message) async {
    final socket = _socket;
    if (socket == null || !_connected) {
      throw const McpTransportException('WebSocket transport not connected');
    }
    socket.add(jsonEncode(message.toJson()));
  }

  @override
  Future<void> close() async {
    _closing = true;
    _connected = false;
    _stopPing();
    await _socketSub?.cancel();
    await _socket?.close(WebSocketStatus.normalClosure);
    _socket = null;
    await _controller.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// Transport exception
// ════════════════════════════════════════════════════════════════════════════

class McpTransportException implements Exception {
  final String message;
  const McpTransportException(this.message);

  @override
  String toString() => 'McpTransportException: $message';
}

// ════════════════════════════════════════════════════════════════════════════
// MCP protocol handler
// ════════════════════════════════════════════════════════════════════════════

/// Sits on top of an [McpTransport], providing request-response correlation,
/// timeout handling, notification dispatch, and the initialize handshake.
class McpProtocolHandler {
  final McpTransport transport;
  final Duration defaultTimeout;

  int _nextId = 1;
  final _pending = <dynamic, Completer<JsonRpcResponse>>{};
  final _notificationController =
      StreamController<JsonRpcNotification>.broadcast();
  final _requestController = StreamController<JsonRpcRequest>.broadcast();
  StreamSubscription<JsonRpcMessage>? _messageSub;

  McpProtocolHandler({
    required this.transport,
    this.defaultTimeout = const Duration(seconds: 30),
  });

  /// Stream of notifications received from the server.
  Stream<JsonRpcNotification> get notifications =>
      _notificationController.stream;

  /// Stream of requests received from the server (e.g. sampling).
  Stream<JsonRpcRequest> get serverRequests => _requestController.stream;

  /// Start listening on the transport for incoming messages.
  void listen() {
    _messageSub = transport.messages.listen(
      _handleMessage,
      onError: (Object e) {
        // Fail all pending requests on transport error.
        _failAll(e.toString());
      },
    );
  }

  void _handleMessage(JsonRpcMessage message) {
    switch (message) {
      case JsonRpcResponse():
        final completer = _pending.remove(message.id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message);
        }
      case JsonRpcNotification():
        _notificationController.add(message);
      case JsonRpcRequest():
        // Server-initiated request (e.g. sampling/createMessage).
        _requestController.add(message);
    }
  }

  /// Send a JSON-RPC request and wait for the correlated response.
  Future<JsonRpcResponse> sendRequest(
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    final id = _nextId++;
    final request = JsonRpcRequest(id: id, method: method, params: params);
    final completer = Completer<JsonRpcResponse>();
    _pending[id] = completer;

    try {
      await transport.send(request);
    } catch (e) {
      _pending.remove(id);
      rethrow;
    }

    final effectiveTimeout = timeout ?? defaultTimeout;
    try {
      return await completer.future.timeout(effectiveTimeout);
    } on TimeoutException {
      _pending.remove(id);
      throw McpTransportException(
        'Request "$method" (id=$id) timed out after $effectiveTimeout',
      );
    }
  }

  /// Send a notification (no response expected).
  Future<void> sendNotification(
    String method, {
    Map<String, dynamic>? params,
  }) async {
    final notification = JsonRpcNotification(method: method, params: params);
    await transport.send(notification);
  }

  /// Respond to a server-initiated request.
  Future<void> respondToRequest(dynamic id, dynamic result) async {
    final response = JsonRpcResponse(id: id, result: result);
    await transport.send(response);
  }

  /// Respond to a server-initiated request with an error.
  Future<void> respondToRequestWithError(
    dynamic id,
    int code,
    String message, {
    dynamic data,
  }) async {
    final response = JsonRpcResponse(
      id: id,
      error: JsonRpcError(code: code, message: message, data: data),
    );
    await transport.send(response);
  }

  void _failAll(String reason) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(McpTransportException(reason));
      }
    }
    _pending.clear();
  }

  /// Cancel a pending request.
  Future<void> cancelRequest(dynamic id) async {
    final completer = _pending.remove(id);
    if (completer != null && !completer.isCompleted) {
      completer.completeError(const McpTransportException('Request cancelled'));
    }
    // Notify the server.
    await sendNotification(
      'notifications/cancelled',
      params: {'requestId': id},
    );
  }

  /// Dispose the handler and release resources.
  Future<void> dispose() async {
    _failAll('Protocol handler disposed');
    await _messageSub?.cancel();
    await _notificationController.close();
    await _requestController.close();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MCP capability negotiation
// ════════════════════════════════════════════════════════════════════════════

/// Capabilities negotiated during the MCP initialize handshake.
class McpCapabilities {
  final bool supportsTools;
  final bool supportsResources;
  final bool supportsPrompts;
  final bool supportsLogging;
  final bool supportsSampling;
  final String? protocolVersion;
  final Map<String, dynamic> raw;

  const McpCapabilities({
    this.supportsTools = false,
    this.supportsResources = false,
    this.supportsPrompts = false,
    this.supportsLogging = false,
    this.supportsSampling = false,
    this.protocolVersion,
    this.raw = const {},
  });

  /// Parse capabilities from a server's initialize response.
  factory McpCapabilities.fromInitializeResult(Map<String, dynamic> result) {
    final caps = result['capabilities'] as Map<String, dynamic>? ?? {};
    final _info = result['serverInfo'] as Map<String, dynamic>?;
    return McpCapabilities(
      supportsTools: caps.containsKey('tools'),
      supportsResources: caps.containsKey('resources'),
      supportsPrompts: caps.containsKey('prompts'),
      supportsLogging: caps.containsKey('logging'),
      supportsSampling: caps.containsKey('sampling'),
      protocolVersion: result['protocolVersion'] as String?,
      raw: caps,
    );
  }
}

/// Information about a connected MCP server.
class McpServerInfo {
  final String name;
  final String? version;
  final McpCapabilities capabilities;

  const McpServerInfo({
    required this.name,
    this.version,
    required this.capabilities,
  });

  factory McpServerInfo.fromInitializeResult(Map<String, dynamic> result) {
    final info = result['serverInfo'] as Map<String, dynamic>? ?? {};
    return McpServerInfo(
      name: info['name'] as String? ?? 'unknown',
      version: info['version'] as String?,
      capabilities: McpCapabilities.fromInitializeResult(result),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// MCP prompt types
// ════════════════════════════════════════════════════════════════════════════

/// An MCP prompt template.
class McpPrompt {
  final String name;
  final String? description;
  final List<McpPromptArgument> arguments;

  const McpPrompt({
    required this.name,
    this.description,
    this.arguments = const [],
  });

  factory McpPrompt.fromJson(Map<String, dynamic> json) => McpPrompt(
    name: json['name'] as String,
    description: json['description'] as String?,
    arguments:
        (json['arguments'] as List<dynamic>?)
            ?.map((a) => McpPromptArgument.fromJson(a as Map<String, dynamic>))
            .toList() ??
        const [],
  );
}

/// An argument to an MCP prompt template.
class McpPromptArgument {
  final String name;
  final String? description;
  final bool required;

  const McpPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });

  factory McpPromptArgument.fromJson(Map<String, dynamic> json) =>
      McpPromptArgument(
        name: json['name'] as String,
        description: json['description'] as String?,
        required: json['required'] as bool? ?? false,
      );
}

// ════════════════════════════════════════════════════════════════════════════
// MCP resource content
// ════════════════════════════════════════════════════════════════════════════

/// Content returned when reading an MCP resource.
class McpResourceContent {
  final String uri;
  final String? text;
  final String? blob; // base64 encoded binary
  final String? mimeType;

  const McpResourceContent({
    required this.uri,
    this.text,
    this.blob,
    this.mimeType,
  });

  factory McpResourceContent.fromJson(Map<String, dynamic> json) =>
      McpResourceContent(
        uri: json['uri'] as String,
        text: json['text'] as String?,
        blob: json['blob'] as String?,
        mimeType: json['mimeType'] as String?,
      );
}

// ════════════════════════════════════════════════════════════════════════════
// MCP sampling request
// ════════════════════════════════════════════════════════════════════════════

/// A sampling/createMessage request from the server asking the client
/// to invoke an LLM.
class McpSamplingRequest {
  final List<Map<String, dynamic>> messages;
  final String? modelPreferences;
  final String? systemPrompt;
  final int? maxTokens;
  final double? temperature;
  final List<String>? stopSequences;
  final Map<String, dynamic>? metadata;

  const McpSamplingRequest({
    required this.messages,
    this.modelPreferences,
    this.systemPrompt,
    this.maxTokens,
    this.temperature,
    this.stopSequences,
    this.metadata,
  });

  factory McpSamplingRequest.fromJson(
    Map<String, dynamic> json,
  ) => McpSamplingRequest(
    messages: (json['messages'] as List<dynamic>).cast<Map<String, dynamic>>(),
    modelPreferences: json['modelPreferences'] as String?,
    systemPrompt: json['systemPrompt'] as String?,
    maxTokens: json['maxTokens'] as int?,
    temperature: (json['temperature'] as num?)?.toDouble(),
    stopSequences: (json['stopSequences'] as List<dynamic>?)?.cast<String>(),
    metadata: json['metadata'] as Map<String, dynamic>?,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// MCP server lifecycle manager
// ════════════════════════════════════════════════════════════════════════════

/// Manages the full lifecycle of an MCP server: starting, initialization
/// handshake, health monitoring, restart on crash, and graceful shutdown.
class McpServerLifecycle {
  final McpServerConfig config;
  final int maxRestartAttempts;
  final Duration healthCheckInterval;
  final Duration initializeTimeout;
  final String clientName;
  final String clientVersion;
  final String protocolVersion;

  McpTransport? _transport;
  McpProtocolHandler? _protocol;
  McpServerInfo? _serverInfo;
  Timer? _healthTimer;
  int _restartCount = 0;
  bool _stopping = false;
  McpLifecycleState _state = McpLifecycleState.stopped;

  final _stateController = StreamController<McpLifecycleState>.broadcast();

  McpServerLifecycle({
    required this.config,
    this.maxRestartAttempts = 5,
    this.healthCheckInterval = const Duration(seconds: 30),
    this.initializeTimeout = const Duration(seconds: 30),
    this.clientName = 'flutter_claw',
    this.clientVersion = '0.1.0',
    this.protocolVersion = '2024-11-05',
  });

  /// Current lifecycle state.
  McpLifecycleState get state => _state;

  /// Stream of lifecycle state changes.
  Stream<McpLifecycleState> get stateChanges => _stateController.stream;

  /// The server info from the initialize handshake.
  McpServerInfo? get serverInfo => _serverInfo;

  /// The protocol handler (available after successful start).
  McpProtocolHandler? get protocol => _protocol;

  /// The underlying transport (available after successful start).
  McpTransport? get transport => _transport;

  /// Start the server: create transport, connect, run initialize handshake.
  Future<void> start() async {
    if (_state == McpLifecycleState.running) return;
    _stopping = false;
    _setState(McpLifecycleState.starting);

    try {
      _transport = createTransport(config);
      await _transport!.connect();

      _protocol = McpProtocolHandler(
        transport: _transport!,
        defaultTimeout: initializeTimeout,
      );
      _protocol!.listen();

      // Run the MCP initialize handshake.
      _setState(McpLifecycleState.initializing);
      final response = await _protocol!.sendRequest(
        'initialize',
        params: {
          'protocolVersion': protocolVersion,
          'capabilities': {'sampling': {}},
          'clientInfo': {'name': clientName, 'version': clientVersion},
        },
        timeout: initializeTimeout,
      );

      if (response.isError) {
        throw McpTransportException('Initialize failed: ${response.error}');
      }

      _serverInfo = McpServerInfo.fromInitializeResult(
        response.result as Map<String, dynamic>,
      );

      // Send initialized notification.
      await _protocol!.sendNotification('notifications/initialized');

      _restartCount = 0;
      _setState(McpLifecycleState.running);

      // Start health monitoring.
      _startHealthMonitor();

      // Listen for transport errors to trigger restart.
      _transport!.messages.listen(null, onError: (_) => _handleCrash());
    } catch (e) {
      _setState(McpLifecycleState.failed);
      rethrow;
    }
  }

  /// Gracefully shut down the server.
  Future<void> stop() async {
    _stopping = true;
    _stopHealthMonitor();
    _setState(McpLifecycleState.stopping);

    try {
      // Send shutdown request, but don't wait too long.
      if (_protocol != null && (_transport?.isConnected ?? false)) {
        try {
          await _protocol!.sendRequest(
            'shutdown',
            timeout: const Duration(seconds: 5),
          );
        } catch (_) {
          // Best effort.
        }
        // Send exit notification.
        try {
          await _protocol!.sendNotification('exit');
        } catch (_) {}
      }
    } finally {
      await _protocol?.dispose();
      await _transport?.close();
      _protocol = null;
      _transport = null;
      _serverInfo = null;
      _setState(McpLifecycleState.stopped);
    }
  }

  /// Force-restart the server.
  Future<void> restart() async {
    await stop();
    _stopping = false;
    _restartCount = 0;
    await start();
  }

  void _startHealthMonitor() {
    _stopHealthMonitor();
    _healthTimer = Timer.periodic(healthCheckInterval, (_) async {
      if (_state != McpLifecycleState.running) return;
      try {
        await _protocol!.sendRequest(
          'ping',
          timeout: const Duration(seconds: 10),
        );
      } catch (_) {
        _handleCrash();
      }
    });
  }

  void _stopHealthMonitor() {
    _healthTimer?.cancel();
    _healthTimer = null;
  }

  void _handleCrash() {
    if (_stopping || _state == McpLifecycleState.restarting) return;

    _stopHealthMonitor();
    _setState(McpLifecycleState.restarting);

    if (_restartCount >= maxRestartAttempts) {
      _setState(McpLifecycleState.failed);
      return;
    }

    _restartCount++;
    final delay = Duration(
      milliseconds: min(1000 * pow(2, _restartCount - 1).toInt(), 30000),
    );

    Future.delayed(delay, () async {
      if (_stopping) return;
      try {
        await _protocol?.dispose();
        await _transport?.close();
      } catch (_) {}
      try {
        await start();
      } catch (_) {
        _handleCrash();
      }
    });
  }

  void _setState(McpLifecycleState newState) {
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Dispose the lifecycle manager permanently.
  Future<void> dispose() async {
    await stop();
    await _stateController.close();
  }
}

/// Lifecycle states for an MCP server.
enum McpLifecycleState {
  stopped,
  starting,
  initializing,
  running,
  stopping,
  restarting,
  failed,
}

// ════════════════════════════════════════════════════════════════════════════
// Transport factory
// ════════════════════════════════════════════════════════════════════════════

/// Create the appropriate [McpTransport] for a given [McpServerConfig].
McpTransport createTransport(McpServerConfig config) => switch (config) {
  McpStdioConfig(:final command, :final args, :final env) => StdioTransport(
    command: command,
    args: args,
    environment: env.isNotEmpty ? env : null,
  ),
  McpSseConfig(:final url, :final headers, :final env) => SseTransport(
    endpoint: Uri.parse(url),
    headers: {...headers, ...env},
  ),
  McpHttpConfig(:final url, :final headers, :final env) => HttpTransport(
    endpoint: Uri.parse(url),
    headers: {...headers, ...env},
  ),
  McpWebSocketConfig(:final url, :final headers, :final env) =>
    WebSocketTransport(endpoint: Uri.parse(url), headers: {...headers, ...env}),
  McpSdkConfig() => throw UnsupportedError(
    'SDK transport is not supported in the Flutter runtime',
  ),
};

// ════════════════════════════════════════════════════════════════════════════
// Connection pool
// ════════════════════════════════════════════════════════════════════════════

/// Manages multiple MCP server connections, routing tool calls to the
/// correct server and providing aggregate health monitoring.
class McpConnectionPool {
  final Map<String, McpServerLifecycle> _servers = {};
  final _stateController = StreamController<McpPoolEvent>.broadcast();

  /// Stream of pool-level events.
  Stream<McpPoolEvent> get events => _stateController.stream;

  /// All managed server names.
  Iterable<String> get serverNames => _servers.keys;

  /// Get a specific server lifecycle manager.
  McpServerLifecycle? operator [](String name) => _servers[name];

  /// Add and start a server.
  Future<McpServerLifecycle> addServer(
    McpServerConfig config, {
    int maxRestartAttempts = 5,
  }) async {
    final name = config.name;

    // Stop existing server if present.
    await removeServer(name);

    final lifecycle = McpServerLifecycle(
      config: config,
      maxRestartAttempts: maxRestartAttempts,
    );

    _servers[name] = lifecycle;

    // Forward lifecycle state changes as pool events.
    lifecycle.stateChanges.listen((state) {
      if (!_stateController.isClosed) {
        _stateController.add(McpPoolEvent(serverName: name, state: state));
      }
    });

    await lifecycle.start();
    return lifecycle;
  }

  /// Stop and remove a server from the pool.
  Future<void> removeServer(String name) async {
    final lifecycle = _servers.remove(name);
    if (lifecycle != null) {
      await lifecycle.dispose();
    }
  }

  /// Send a JSON-RPC request to a specific server.
  Future<JsonRpcResponse> sendRequest(
    String serverName,
    String method, {
    Map<String, dynamic>? params,
    Duration? timeout,
  }) async {
    final lifecycle = _servers[serverName];
    if (lifecycle == null) {
      throw McpTransportException('Server "$serverName" not in pool');
    }
    final protocol = lifecycle.protocol;
    if (protocol == null || lifecycle.state != McpLifecycleState.running) {
      throw McpTransportException('Server "$serverName" is not running');
    }
    return protocol.sendRequest(method, params: params, timeout: timeout);
  }

  /// List tools from a specific server.
  Future<List<McpToolInfo>> listTools(String serverName) async {
    final response = await sendRequest(serverName, 'tools/list');
    if (response.isError) return [];

    final result = response.result as Map<String, dynamic>? ?? {};
    final toolsList = result['tools'] as List<dynamic>? ?? [];

    return toolsList.map((t) {
      final tool = t as Map<String, dynamic>;
      final annotations = tool['annotations'] as Map<String, dynamic>?;
      return McpToolInfo(
        name: tool['name'] as String,
        description: tool['description'] as String? ?? '',
        inputSchema: tool['inputSchema'] as Map<String, dynamic>? ?? {},
        serverName: serverName,
        readOnly: annotations?['readOnlyHint'] as bool? ?? false,
        destructive: annotations?['destructiveHint'] as bool? ?? false,
      );
    }).toList();
  }

  /// Call a tool on a specific server.
  Future<JsonRpcResponse> callTool(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments, {
    Duration? timeout,
  }) async {
    return sendRequest(
      serverName,
      'tools/call',
      params: {'name': toolName, 'arguments': arguments},
      timeout: timeout ?? const Duration(hours: 1),
    );
  }

  /// List resources from a specific server.
  Future<List<McpResource>> listResources(String serverName) async {
    final response = await sendRequest(serverName, 'resources/list');
    if (response.isError) return [];

    final result = response.result as Map<String, dynamic>? ?? {};
    final list = result['resources'] as List<dynamic>? ?? [];

    return list.map((r) {
      final res = r as Map<String, dynamic>;
      return McpResource(
        uri: res['uri'] as String,
        name: res['name'] as String,
        description: res['description'] as String?,
        mimeType: res['mimeType'] as String?,
        serverName: serverName,
      );
    }).toList();
  }

  /// Read a resource from a specific server.
  Future<List<McpResourceContent>> readResource(
    String serverName,
    String uri,
  ) async {
    final response = await sendRequest(
      serverName,
      'resources/read',
      params: {'uri': uri},
    );
    if (response.isError) return [];

    final result = response.result as Map<String, dynamic>? ?? {};
    final contents = result['contents'] as List<dynamic>? ?? [];

    return contents
        .map((c) => McpResourceContent.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  /// List prompts from a specific server.
  Future<List<McpPrompt>> listPrompts(String serverName) async {
    final response = await sendRequest(serverName, 'prompts/list');
    if (response.isError) return [];

    final result = response.result as Map<String, dynamic>? ?? {};
    final list = result['prompts'] as List<dynamic>? ?? [];

    return list
        .map((p) => McpPrompt.fromJson(p as Map<String, dynamic>))
        .toList();
  }

  /// Get a prompt from a specific server.
  Future<Map<String, dynamic>?> getPrompt(
    String serverName,
    String promptName, {
    Map<String, String>? arguments,
  }) async {
    final response = await sendRequest(
      serverName,
      'prompts/get',
      params: {'name': promptName, 'arguments': ?arguments},
    );
    if (response.isError) return null;
    return response.result as Map<String, dynamic>?;
  }

  /// Set the log level for a specific server.
  Future<void> setLogLevel(String serverName, String level) async {
    await sendRequest(serverName, 'logging/setLevel', params: {'level': level});
  }

  /// Get all running servers and their info.
  Map<String, McpServerInfo?> get serverInfo => {
    for (final entry in _servers.entries) entry.key: entry.value.serverInfo,
  };

  /// Get the health status of all servers.
  Map<String, McpLifecycleState> get healthStatus => {
    for (final entry in _servers.entries) entry.key: entry.value.state,
  };

  /// Stop all servers and dispose the pool.
  Future<void> dispose() async {
    final futures = _servers.values.map((lc) => lc.dispose());
    await Future.wait(futures);
    _servers.clear();
    await _stateController.close();
  }
}

/// An event emitted by [McpConnectionPool] when a server state changes.
class McpPoolEvent {
  final String serverName;
  final McpLifecycleState state;

  const McpPoolEvent({required this.serverName, required this.state});

  @override
  String toString() => 'McpPoolEvent($serverName: $state)';
}
