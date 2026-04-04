// RemoteBridge — port of neom_claw/src/bridge/ + src/remote/ + src/server/.
// Full remote session management: HTTP/WebSocket server, client reconnection,
// session relay, and multi-device synchronization.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

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

/// Client for connecting to a remote NeomClaw session.
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
        switch (_authMethod) {
          case RemoteAuthMethod.token:
            headers['Authorization'] = 'Bearer $_authToken';
          case RemoteAuthMethod.apiKey:
            headers['X-Api-Key'] = _authToken;
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
        (data) => _handleMessage(data as String),
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
  final int port;
  final String? host;
  final String? authToken;
  HttpServer? _server;
  final Map<String, WebSocket> _clients = {};
  final StreamController<RemoteEvent> _eventController =
      StreamController<RemoteEvent>.broadcast();
  final Map<String, RemoteSessionInfo> _sessions = {};
  int _clientCounter = 0;

  RemoteServer({this.port = 3100, this.host, this.authToken});

  /// Event stream.
  Stream<RemoteEvent> get events => _eventController.stream;

  /// Connected client count.
  int get clientCount => _clients.length;

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
    // CORS headers.
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add(
      'Access-Control-Allow-Methods',
      'GET, POST, OPTIONS',
    );
    request.response.headers.add(
      'Access-Control-Allow-Headers',
      'Authorization, Content-Type, X-Api-Key',
    );

    if (request.method == 'OPTIONS') {
      request.response.statusCode = 204;
      await request.response.close();
      return;
    }

    // Auth check.
    if (authToken != null) {
      final auth = request.headers.value('Authorization');
      final apiKey = request.headers.value('X-Api-Key');
      if (auth != 'Bearer $authToken' && apiKey != authToken) {
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
        // WebSocket upgrade.
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocket(socket, request);
        } else {
          request.response.statusCode = 400;
          request.response.write('Expected WebSocket upgrade');
          await request.response.close();
        }

      default:
        // Try WebSocket upgrade on any path.
        if (WebSocketTransformer.isUpgradeRequest(request)) {
          final socket = await WebSocketTransformer.upgrade(request);
          _handleWebSocket(socket, request);
        } else {
          request.response.statusCode = 404;
          request.response.write('Not found');
          await request.response.close();
        }
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
          final message = RemoteMessage.fromJson(
            jsonDecode(data as String) as Map<String, dynamic>,
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
    _socket = await WebSocket.connect(
      relayUrl,
      headers: {if (relayToken != null) 'Authorization': 'Bearer $relayToken'},
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
          final message = RemoteMessage.fromJson(
            jsonDecode(data as String) as Map<String, dynamic>,
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
    final client = HttpClient();
    try {
      final uri = Uri.parse(relayUrl.replaceFirst('ws', 'http'));
      final request = await client.getUrl(uri.replace(path: '/api/hosts'));
      if (relayToken != null) {
        request.headers.set('Authorization', 'Bearer $relayToken');
      }
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return (jsonDecode(body) as List<dynamic>).cast<Map<String, dynamic>>();
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
  /// Scan for remote sessions on common ports.
  static Future<List<RemoteSessionInfo>> scan({
    String subnet = '127.0.0.1',
    List<int> ports = const [3100, 3101, 3102, 3103, 3104],
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final results = <RemoteSessionInfo>[];

    for (final port in ports) {
      try {
        final client = HttpClient();
        client.connectionTimeout = timeout;

        final request = await client.getUrl(
          Uri.parse('http://$subnet:$port/api/status'),
        );
        final response = await request.close();

        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final json = jsonDecode(body) as Map<String, dynamic>;

          results.add(
            RemoteSessionInfo(
              sessionId: 'discovered_${subnet}_$port',
              hostId: subnet,
              displayName: json['displayName'] as String? ?? '$subnet:$port',
              state: RemoteSessionState.connected,
              connectionType: RemoteConnectionType.direct,
              connectedAt: DateTime.now(),
              remoteAddress: subnet,
              remotePort: port,
              model: json['model'] as String?,
              metadata: json,
            ),
          );
        }

        client.close();
      } catch (_) {
        // Host/port not available.
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
    final url = '$scheme://$host:$port/ws';
    if (token != null) {
      return '$url?token=$token';
    }
    return url;
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
