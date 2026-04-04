// RemoteSessionManager — ported from openclaude src/remote/RemoteSessionManager.ts.
// Coordinates WebSocket subscription, HTTP POST for user messages, and the
// permission request/response flow for a remote CCR session.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:neom_claw/data/remote/sessions_websocket.dart';

// ---------------------------------------------------------------------------
// Remote permission response
// ---------------------------------------------------------------------------

/// Simple permission response for remote sessions.
///
/// This is a simplified version of `PermissionResult` for CCR communication.
sealed class RemotePermissionResponse {
  const RemotePermissionResponse();
}

/// Permission was granted with (possibly modified) input.
class RemotePermissionAllow extends RemotePermissionResponse {
  /// The (possibly updated) tool input to use.
  final Map<String, dynamic> updatedInput;
  const RemotePermissionAllow({required this.updatedInput});
}

/// Permission was denied with a reason.
class RemotePermissionDeny extends RemotePermissionResponse {
  /// Human-readable denial message.
  final String message;
  const RemotePermissionDeny({required this.message});
}

// ---------------------------------------------------------------------------
// Remote session config
// ---------------------------------------------------------------------------

/// Configuration for a remote CCR session.
class RemoteSessionConfig {
  /// The CCR session identifier.
  final String sessionId;

  /// Returns a fresh OAuth access token.
  final String Function() getAccessToken;

  /// Anthropic organization UUID.
  final String orgUuid;

  /// True if the session was created with an initial prompt that is being
  /// processed.
  final bool hasInitialPrompt;

  /// When true this client is a pure viewer. Ctrl+C / Escape do NOT send
  /// interrupt to the remote agent; 60 s reconnect timeout is disabled;
  /// session title is never updated. Used by `claude assistant`.
  final bool viewerOnly;

  /// Create a [RemoteSessionConfig].
  const RemoteSessionConfig({
    required this.sessionId,
    required this.getAccessToken,
    required this.orgUuid,
    this.hasInitialPrompt = false,
    this.viewerOnly = false,
  });
}

// ---------------------------------------------------------------------------
// Remote session callbacks
// ---------------------------------------------------------------------------

/// Callbacks for [RemoteSessionManager] lifecycle events.
class RemoteSessionCallbacks {
  /// Called when an SDK message is received from the session.
  final void Function(SessionsMessage message) onMessage;

  /// Called when a permission request is received from CCR.
  final void Function(
    Map<String, dynamic> request,
    String requestId,
  ) onPermissionRequest;

  /// Called when the server cancels a pending permission request.
  final void Function(String requestId, String? toolUseId)?
      onPermissionCancelled;

  /// Called when connection is established.
  final void Function()? onConnected;

  /// Called when connection is lost and cannot be restored.
  final void Function()? onDisconnected;

  /// Called on transient WS drop while reconnect backoff is in progress.
  final void Function()? onReconnecting;

  /// Called on error.
  final void Function(Object error)? onError;

  /// Create callbacks for [RemoteSessionManager].
  const RemoteSessionCallbacks({
    required this.onMessage,
    required this.onPermissionRequest,
    this.onPermissionCancelled,
    this.onConnected,
    this.onDisconnected,
    this.onReconnecting,
    this.onError,
  });
}

// ---------------------------------------------------------------------------
// Remote message content (for HTTP POST)
// ---------------------------------------------------------------------------

/// Content payload sent to the remote session via HTTP POST.
///
/// Mirrors the `RemoteMessageContent` union from the TS teleport API.
/// In practice this is either a text prompt or a list of content blocks.
typedef RemoteMessageContent = Object;

// ---------------------------------------------------------------------------
// RemoteSessionManager
// ---------------------------------------------------------------------------

/// Manages a remote CCR session.
///
/// Coordinates:
/// - WebSocket subscription for receiving messages from CCR
/// - HTTP POST for sending user messages to CCR
/// - Permission request / response flow
class RemoteSessionManager {
  final RemoteSessionConfig _config;
  final RemoteSessionCallbacks _callbacks;

  SessionsWebSocket? _websocket;
  final Map<String, Map<String, dynamic>> _pendingPermissionRequests = {};

  /// Create a [RemoteSessionManager].
  RemoteSessionManager({
    required RemoteSessionConfig config,
    required RemoteSessionCallbacks callbacks,
  })  : _config = config,
        _callbacks = callbacks;

  /// Connect to the remote session via WebSocket.
  void connect() {
    developer.log(
      'Connecting to session ${_config.sessionId}',
      name: 'RemoteSessionManager',
    );

    final wsCallbacks = SessionsWebSocketCallbacks(
      onMessage: _handleMessage,
      onConnected: () {
        developer.log('Connected', name: 'RemoteSessionManager');
        _callbacks.onConnected?.call();
      },
      onClose: () {
        developer.log('Disconnected', name: 'RemoteSessionManager');
        _callbacks.onDisconnected?.call();
      },
      onReconnecting: () {
        developer.log('Reconnecting', name: 'RemoteSessionManager');
        _callbacks.onReconnecting?.call();
      },
      onError: (error) {
        developer.log('Error: $error', name: 'RemoteSessionManager');
        _callbacks.onError?.call(error);
      },
    );

    _websocket = SessionsWebSocket(
      _config.sessionId,
      _config.orgUuid,
      _config.getAccessToken,
      wsCallbacks,
    );

    _websocket!.connect();
  }

  /// Send a user message to the remote session via HTTP POST.
  ///
  /// Returns `true` if the server acknowledged the message successfully.
  Future<bool> sendMessage(
    RemoteMessageContent content, {
    String? uuid,
  }) async {
    developer.log(
      'Sending message to session ${_config.sessionId}',
      name: 'RemoteSessionManager',
    );

    try {
      final client = HttpClient();
      // POST to the teleport API endpoint.
      final uri = Uri.parse(
        'https://api.anthropic.com/v1/sessions/${_config.sessionId}/events',
      );
      final request = await client.postUrl(uri);
      request.headers.set(
        'Authorization',
        'Bearer ${_config.getAccessToken()}',
      );
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('anthropic-version', '2023-06-01');

      final body = <String, dynamic>{'content': content};
      if (uuid != null) body['uuid'] = uuid;
      request.add(utf8.encode(jsonEncode(body)));

      final response = await request.close();
      client.close(force: false);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      developer.log(
        'Failed to send message: HTTP ${response.statusCode}',
        name: 'RemoteSessionManager',
      );
      return false;
    } catch (e) {
      developer.log(
        'Failed to send message: $e',
        name: 'RemoteSessionManager',
      );
      return false;
    }
  }

  /// Respond to a permission request from CCR.
  void respondToPermissionRequest(
    String requestId,
    RemotePermissionResponse result,
  ) {
    final pendingRequest = _pendingPermissionRequests[requestId];
    if (pendingRequest == null) {
      developer.log(
        'No pending permission request with ID: $requestId',
        name: 'RemoteSessionManager',
      );
      return;
    }

    _pendingPermissionRequests.remove(requestId);

    final Map<String, dynamic> responsePayload;
    switch (result) {
      case RemotePermissionAllow(:final updatedInput):
        responsePayload = {
          'behavior': 'allow',
          'updatedInput': updatedInput,
        };
      case RemotePermissionDeny(:final message):
        responsePayload = {
          'behavior': 'deny',
          'message': message,
        };
    }

    final controlResponse = <String, dynamic>{
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': responsePayload,
      },
    };

    developer.log(
      'Sending permission response: ${responsePayload['behavior']}',
      name: 'RemoteSessionManager',
    );
    _websocket?.sendControlResponse(controlResponse);
  }

  /// Whether the WebSocket is currently connected.
  bool isConnected() => _websocket?.isConnected() ?? false;

  /// Send an interrupt signal to cancel the current request on the remote
  /// session.
  void cancelSession() {
    developer.log('Sending interrupt signal', name: 'RemoteSessionManager');
    _websocket?.sendControlRequest({'subtype': 'interrupt'});
  }

  /// The CCR session identifier.
  String get sessionId => _config.sessionId;

  /// Disconnect from the remote session.
  void disconnect() {
    developer.log('Disconnecting', name: 'RemoteSessionManager');
    _websocket?.close();
    _websocket = null;
    _pendingPermissionRequests.clear();
  }

  /// Force reconnect the WebSocket.
  ///
  /// Useful when the subscription becomes stale after container shutdown.
  void reconnect() {
    developer.log('Reconnecting WebSocket', name: 'RemoteSessionManager');
    _websocket?.reconnect();
  }

  // ── Internal ──

  void _handleMessage(SessionsMessage message) {
    switch (message.type) {
      case 'control_request':
        _handleControlRequest(message);

      case 'control_cancel_request':
        final requestId = message.requestId;
        if (requestId == null) return;
        final pending = _pendingPermissionRequests[requestId];
        developer.log(
          'Permission request cancelled: $requestId',
          name: 'RemoteSessionManager',
        );
        _pendingPermissionRequests.remove(requestId);
        _callbacks.onPermissionCancelled?.call(
          requestId,
          pending?['tool_use_id'] as String?,
        );

      case 'control_response':
        developer.log(
          'Received control response',
          name: 'RemoteSessionManager',
        );

      default:
        // Forward SDK messages to callback.
        _callbacks.onMessage(message);
    }
  }

  void _handleControlRequest(SessionsMessage message) {
    final requestId = message.requestId;
    final inner = message.request;
    if (requestId == null || inner == null) return;

    final subtype = inner['subtype'] as String?;

    if (subtype == 'can_use_tool') {
      developer.log(
        'Permission request for tool: ${inner['tool_name']}',
        name: 'RemoteSessionManager',
      );
      _pendingPermissionRequests[requestId] = inner;
      _callbacks.onPermissionRequest(inner, requestId);
    } else {
      // Send an error response for unrecognized subtypes so the server
      // doesn't hang waiting for a reply that never comes.
      developer.log(
        'Unsupported control request subtype: $subtype',
        name: 'RemoteSessionManager',
      );
      final response = <String, dynamic>{
        'type': 'control_response',
        'response': {
          'subtype': 'error',
          'request_id': requestId,
          'error': 'Unsupported control request subtype: $subtype',
        },
      };
      _websocket?.sendControlResponse(response);
    }
  }
}

/// Create a [RemoteSessionConfig] from OAuth tokens.
RemoteSessionConfig createRemoteSessionConfig(
  String sessionId,
  String Function() getAccessToken,
  String orgUuid, {
  bool hasInitialPrompt = false,
  bool viewerOnly = false,
}) {
  return RemoteSessionConfig(
    sessionId: sessionId,
    getAccessToken: getAccessToken,
    orgUuid: orgUuid,
    hasInitialPrompt: hasInitialPrompt,
    viewerOnly: viewerOnly,
  );
}
