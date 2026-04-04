// SessionsWebSocket — ported from openclaude src/remote/SessionsWebSocket.ts.
// WebSocket client for subscribing to CCR sessions with automatic reconnection,
// ping keep-alive, and permanent/transient close-code handling.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Delay between reconnection attempts.
const _reconnectDelayMs = 2000;

/// Maximum number of generic reconnection attempts before giving up.
const _maxReconnectAttempts = 5;

/// Interval for WebSocket ping keep-alive.
const _pingIntervalMs = 30000;

/// Maximum retries for 4001 (session not found). During compaction the server
/// may briefly consider the session stale; a short retry window lets the
/// client recover without giving up permanently.
const _maxSessionNotFoundRetries = 3;

/// WebSocket close codes that indicate a permanent server-side rejection.
/// The client stops reconnecting immediately.
/// Note: 4001 (session not found) is handled separately with limited retries
/// since it can be transient during compaction.
const _permanentCloseCodes = {4003}; // unauthorized

// ---------------------------------------------------------------------------
// WebSocket state
// ---------------------------------------------------------------------------

/// Connection state of a [SessionsWebSocket].
enum WebSocketState {
  /// A connection attempt is in progress.
  connecting,

  /// The WebSocket is open and authenticated.
  connected,

  /// The WebSocket is closed (either cleanly or after exhausting retries).
  closed,
}

// ---------------------------------------------------------------------------
// Messages — SDK + control types carried over the sessions WS
// ---------------------------------------------------------------------------

/// A message received or sent over the sessions WebSocket.
///
/// This is a thin JSON wrapper; the downstream [RemoteSessionManager] and
/// [convertSDKMessage] decide how to interpret each `type`.
class SessionsMessage {
  /// The message type discriminator (e.g. `assistant`, `control_request`).
  final String type;

  /// The full decoded JSON payload.
  final Map<String, dynamic> raw;

  /// Create a [SessionsMessage] from a decoded JSON map.
  const SessionsMessage({required this.type, required this.raw});

  /// Convenience accessors for common fields.
  String? get requestId => raw['request_id'] as String?;

  /// Returns the nested `request` object for control_request messages.
  Map<String, dynamic>? get request =>
      raw['request'] as Map<String, dynamic>?;

  /// Returns the nested `response` object for control_response messages.
  Map<String, dynamic>? get response =>
      raw['response'] as Map<String, dynamic>?;

  /// Returns the nested `message` object for assistant/user messages.
  Map<String, dynamic>? get message =>
      raw['message'] as Map<String, dynamic>?;

  /// Serialize back to JSON string.
  String toJsonString() => jsonEncode(raw);
}

/// Validates that a decoded JSON value looks like a [SessionsMessage].
///
/// Accepts any object with a string `type` field. Downstream handlers decide
/// what to do with unknown types. A hardcoded allowlist here would silently
/// drop new message types the backend starts sending before the client is
/// updated.
bool _isSessionsMessage(dynamic value) {
  if (value is! Map<String, dynamic>) return false;
  return value['type'] is String;
}

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

/// Callbacks for [SessionsWebSocket] lifecycle events.
class SessionsWebSocketCallbacks {
  /// Called when a valid [SessionsMessage] is received.
  final void Function(SessionsMessage message) onMessage;

  /// Called when the connection is permanently closed (server ended or
  /// reconnection attempts exhausted).
  final void Function()? onClose;

  /// Called when a WebSocket error occurs.
  final void Function(Object error)? onError;

  /// Called when the connection is established (or re-established).
  final void Function()? onConnected;

  /// Fired when a transient close is detected and a reconnect is scheduled.
  /// [onClose] fires only for permanent close.
  final void Function()? onReconnecting;

  /// Create callbacks for [SessionsWebSocket].
  const SessionsWebSocketCallbacks({
    required this.onMessage,
    this.onClose,
    this.onError,
    this.onConnected,
    this.onReconnecting,
  });
}

// ---------------------------------------------------------------------------
// SessionsWebSocket
// ---------------------------------------------------------------------------

/// WebSocket client for connecting to CCR sessions.
///
/// Protocol:
/// 1. Connect to `wss://api.anthropic.com/v1/sessions/ws/{sessionId}/subscribe`
/// 2. Authenticate via Bearer token in headers
/// 3. Receive [SessionsMessage] stream from the session
/// 4. Send control responses / requests back through the same connection
class SessionsWebSocket {
  final String _sessionId;
  final String _orgUuid;
  final String Function() _getAccessToken;
  final SessionsWebSocketCallbacks _callbacks;

  /// The base API URL used to build the WebSocket endpoint.
  /// Defaults to `wss://api.anthropic.com` if not overridden.
  final String _baseWsUrl;

  WebSocket? _ws;
  WebSocketState _state = WebSocketState.closed;
  int _reconnectAttempts = 0;
  int _sessionNotFoundRetries = 0;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  StreamSubscription<dynamic>? _wsSubscription;

  static const _uuid = Uuid();

  /// Create a new [SessionsWebSocket].
  ///
  /// [sessionId] identifies the remote CCR session.
  /// [orgUuid] is the Anthropic organization UUID.
  /// [getAccessToken] returns a fresh OAuth token for each connection attempt.
  /// [callbacks] receives lifecycle events.
  /// [baseWsUrl] overrides the default WebSocket base URL (useful for testing).
  SessionsWebSocket(
    this._sessionId,
    this._orgUuid,
    this._getAccessToken,
    this._callbacks, {
    String baseWsUrl = 'wss://api.anthropic.com',
  }) : _baseWsUrl = baseWsUrl;

  // ── Public API ──

  /// Connect to the sessions WebSocket endpoint.
  Future<void> connect() async {
    if (_state == WebSocketState.connecting) return;

    _state = WebSocketState.connecting;

    final url =
        '$_baseWsUrl/v1/sessions/ws/$_sessionId/subscribe'
        '?organization_uuid=$_orgUuid';

    final accessToken = _getAccessToken();
    final headers = <String, dynamic>{
      'Authorization': 'Bearer $accessToken',
      'anthropic-version': '2023-06-01',
    };

    try {
      _ws = await WebSocket.connect(url, headers: headers);
      _state = WebSocketState.connected;
      _reconnectAttempts = 0;
      _sessionNotFoundRetries = 0;
      _startPingInterval();
      _callbacks.onConnected?.call();

      _wsSubscription = _ws!.listen(
        (data) => _handleMessage(data is String ? data : data.toString()),
        onDone: () => _handleClose(_ws?.closeCode ?? 1006),
        onError: (Object error) {
          _callbacks.onError?.call(error);
        },
      );
    } catch (e) {
      _callbacks.onError?.call(e);
      _handleClose(1006); // abnormal closure
    }
  }

  /// Send a control response back to the session.
  void sendControlResponse(Map<String, dynamic> response) {
    if (_ws == null || _state != WebSocketState.connected) return;
    _ws!.add(jsonEncode(response));
  }

  /// Send a control request to the session (e.g. interrupt).
  void sendControlRequest(Map<String, dynamic> requestInner) {
    if (_ws == null || _state != WebSocketState.connected) return;

    final controlRequest = <String, dynamic>{
      'type': 'control_request',
      'request_id': _uuid.v4(),
      'request': requestInner,
    };
    _ws!.add(jsonEncode(controlRequest));
  }

  /// Whether the WebSocket is currently connected.
  bool isConnected() => _state == WebSocketState.connected;

  /// Close the WebSocket connection permanently.
  void close() {
    _state = WebSocketState.closed;
    _stopPingInterval();
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _ws?.close();
    _ws = null;
  }

  /// Force reconnect -- closes the existing connection and starts a new one.
  ///
  /// Useful when the subscription becomes stale (e.g. after container
  /// shutdown).
  void reconnect() {
    _reconnectAttempts = 0;
    _sessionNotFoundRetries = 0;
    close();
    // Small delay before reconnecting (stored so it can be cancelled).
    _reconnectTimer = Timer(
      const Duration(milliseconds: 500),
      () {
        _reconnectTimer = null;
        connect();
      },
    );
  }

  // ── Internal ──

  void _handleMessage(String data) {
    try {
      final decoded = jsonDecode(data);
      if (_isSessionsMessage(decoded)) {
        final map = decoded as Map<String, dynamic>;
        _callbacks.onMessage(
          SessionsMessage(type: map['type'] as String, raw: map),
        );
      }
    } catch (e) {
      _callbacks.onError?.call(e);
    }
  }

  void _handleClose(int closeCode) {
    _stopPingInterval();

    if (_state == WebSocketState.closed) return;

    _wsSubscription?.cancel();
    _wsSubscription = null;
    _ws = null;

    final previousState = _state;
    _state = WebSocketState.closed;

    // Permanent codes: stop reconnecting.
    if (_permanentCloseCodes.contains(closeCode)) {
      _callbacks.onClose?.call();
      return;
    }

    // 4001 (session not found) can be transient during compaction.
    if (closeCode == 4001) {
      _sessionNotFoundRetries++;
      if (_sessionNotFoundRetries > _maxSessionNotFoundRetries) {
        _callbacks.onClose?.call();
        return;
      }
      _scheduleReconnect(
        Duration(milliseconds: _reconnectDelayMs * _sessionNotFoundRetries),
      );
      return;
    }

    // Attempt reconnection if we were previously connected.
    if (previousState == WebSocketState.connected &&
        _reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _scheduleReconnect(const Duration(milliseconds: _reconnectDelayMs));
    } else {
      _callbacks.onClose?.call();
    }
  }

  void _scheduleReconnect(Duration delay) {
    _callbacks.onReconnecting?.call();
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      connect();
    });
  }

  void _startPingInterval() {
    _stopPingInterval();
    _pingTimer = Timer.periodic(
      const Duration(milliseconds: _pingIntervalMs),
      (_) {
        if (_ws != null && _state == WebSocketState.connected) {
          try {
            // dart:io WebSocket supports ping frames natively.
            _ws!.add('ping');
          } catch (_) {
            // Ignore ping errors; the close handler deals with connection
            // issues.
          }
        }
      },
    );
  }

  void _stopPingInterval() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }
}
