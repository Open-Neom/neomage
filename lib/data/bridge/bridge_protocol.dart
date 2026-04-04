// Bridge protocol — port of NeomClaw's protocol layer.
// JSON-RPC 2.0 based protocol for IDE <-> NeomClaw communication.
// Handles handshake, request/response, notifications, and capability negotiation.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

// ---------------------------------------------------------------------------
// Protocol version
// ---------------------------------------------------------------------------

/// Semantic version for the bridge protocol.
class BridgeProtocolVersion {
  final int major;
  final int minor;
  final int patch;

  const BridgeProtocolVersion({
    required this.major,
    required this.minor,
    required this.patch,
  });

  /// The current protocol version.
  static const current = BridgeProtocolVersion(major: 1, minor: 0, patch: 0);

  /// Check if [other] is compatible with this version.
  ///
  /// Compatibility rules:
  /// - Major versions must match (breaking changes).
  /// - Minor of [other] must be <= this minor (backward-compatible features).
  /// - Patch is always compatible.
  bool isCompatible(BridgeProtocolVersion other) {
    if (major != other.major) return false;
    if (other.minor > minor) return false;
    return true;
  }

  /// Check if this version is strictly newer than [other].
  bool isNewerThan(BridgeProtocolVersion other) {
    if (major != other.major) return major > other.major;
    if (minor != other.minor) return minor > other.minor;
    return patch > other.patch;
  }

  Map<String, dynamic> toJson() => {
        'major': major,
        'minor': minor,
        'patch': patch,
      };

  factory BridgeProtocolVersion.fromJson(Map<String, dynamic> json) =>
      BridgeProtocolVersion(
        major: json['major'] as int,
        minor: json['minor'] as int,
        patch: json['patch'] as int,
      );

  @override
  String toString() => '$major.$minor.$patch';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BridgeProtocolVersion &&
          major == other.major &&
          minor == other.minor &&
          patch == other.patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);
}

// ---------------------------------------------------------------------------
// Capabilities
// ---------------------------------------------------------------------------

/// Capabilities that a bridge endpoint can advertise.
enum BridgeCapability {
  fileEdit('fileEdit'),
  diagnostics('diagnostics'),
  completion('completion'),
  hover('hover'),
  definition('definition'),
  references('references'),
  rename('rename'),
  codeActions('codeActions'),
  formatting('formatting'),
  terminal('terminal'),
  debug('debug'),
  git('git'),
  tasks('tasks'),
  notifications('notifications'),
  chat('chat'),
  statusBar('statusBar');

  const BridgeCapability(this.wireName);

  /// Wire name used in JSON serialization.
  final String wireName;

  /// Parse from wire name, returns null if unknown.
  static BridgeCapability? fromWireName(String name) {
    for (final cap in values) {
      if (cap.wireName == name) return cap;
    }
    return null;
  }

  /// Parse a list of wire names into capabilities, ignoring unknowns.
  static Set<BridgeCapability> parseList(List<dynamic> names) {
    final result = <BridgeCapability>{};
    for (final name in names) {
      final cap = fromWireName(name as String);
      if (cap != null) result.add(cap);
    }
    return result;
  }
}

// ---------------------------------------------------------------------------
// Handshake
// ---------------------------------------------------------------------------

/// Handshake payload sent during initialization.
class BridgeHandshake {
  final String clientName;
  final BridgeProtocolVersion clientVersion;
  final Set<BridgeCapability> capabilities;
  final List<String> workspacePaths;
  final int pid;
  final String? sessionId;
  final Map<String, dynamic> extensions;

  BridgeHandshake({
    required this.clientName,
    required this.clientVersion,
    required this.capabilities,
    this.workspacePaths = const [],
    required this.pid,
    this.sessionId,
    this.extensions = const {},
  });

  Map<String, dynamic> toJson() => {
        'clientName': clientName,
        'clientVersion': clientVersion.toJson(),
        'capabilities': capabilities.map((c) => c.wireName).toList(),
        'workspacePaths': workspacePaths,
        'pid': pid,
        if (sessionId != null) 'sessionId': sessionId,
        if (extensions.isNotEmpty) 'extensions': extensions,
      };

  factory BridgeHandshake.fromJson(Map<String, dynamic> json) =>
      BridgeHandshake(
        clientName: json['clientName'] as String,
        clientVersion: BridgeProtocolVersion.fromJson(
            json['clientVersion'] as Map<String, dynamic>),
        capabilities: BridgeCapability.parseList(
            json['capabilities'] as List<dynamic>),
        workspacePaths: (json['workspacePaths'] as List<dynamic>?)
                ?.cast<String>() ??
            [],
        pid: json['pid'] as int,
        sessionId: json['sessionId'] as String?,
        extensions:
            (json['extensions'] as Map<String, dynamic>?) ?? const {},
      );

  @override
  String toString() =>
      'BridgeHandshake($clientName v$clientVersion, '
      '${capabilities.length} caps, pid=$pid)';
}

// ---------------------------------------------------------------------------
// Error codes
// ---------------------------------------------------------------------------

/// Standard JSON-RPC 2.0 error codes plus custom protocol codes.
abstract final class ErrorCode {
  // JSON-RPC 2.0 standard errors
  static const int parseError = -32700;
  static const int invalidRequest = -32600;
  static const int methodNotFound = -32601;
  static const int invalidParams = -32602;
  static const int internalError = -32603;

  // Custom protocol errors (-32000 to -32099 reserved for implementation)
  static const int serverNotInitialized = -32002;
  static const int requestCancelled = -32800;
  static const int contentModified = -32801;
  static const int requestFailed = -32803;
  static const int serverCancelled = -32802;

  /// Human-readable description of an error code.
  static String describe(int code) => switch (code) {
        parseError => 'Parse error',
        invalidRequest => 'Invalid request',
        methodNotFound => 'Method not found',
        invalidParams => 'Invalid params',
        internalError => 'Internal error',
        serverNotInitialized => 'Server not initialized',
        requestCancelled => 'Request cancelled',
        contentModified => 'Content modified',
        requestFailed => 'Request failed',
        serverCancelled => 'Server cancelled',
        _ => 'Unknown error ($code)',
      };
}

// ---------------------------------------------------------------------------
// Bridge error
// ---------------------------------------------------------------------------

/// Error object in the bridge protocol (JSON-RPC 2.0 error shape).
class BridgeError implements Exception {
  final int code;
  final String message;
  final dynamic data;

  const BridgeError({
    required this.code,
    required this.message,
    this.data,
  });

  factory BridgeError.parseError([String? detail]) => BridgeError(
        code: ErrorCode.parseError,
        message: detail ?? 'Parse error',
      );

  factory BridgeError.invalidRequest([String? detail]) => BridgeError(
        code: ErrorCode.invalidRequest,
        message: detail ?? 'Invalid request',
      );

  factory BridgeError.methodNotFound(String method) => BridgeError(
        code: ErrorCode.methodNotFound,
        message: 'Method not found: $method',
      );

  factory BridgeError.invalidParams([String? detail]) => BridgeError(
        code: ErrorCode.invalidParams,
        message: detail ?? 'Invalid params',
      );

  factory BridgeError.internalError([String? detail]) => BridgeError(
        code: ErrorCode.internalError,
        message: detail ?? 'Internal error',
      );

  factory BridgeError.serverNotInitialized() => const BridgeError(
        code: ErrorCode.serverNotInitialized,
        message: 'Server not initialized',
      );

  factory BridgeError.requestCancelled() => const BridgeError(
        code: ErrorCode.requestCancelled,
        message: 'Request cancelled',
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'message': message,
        if (data != null) 'data': data,
      };

  factory BridgeError.fromJson(Map<String, dynamic> json) => BridgeError(
        code: json['code'] as int,
        message: json['message'] as String,
        data: json['data'],
      );

  @override
  String toString() => 'BridgeError($code: $message)';
}

// ---------------------------------------------------------------------------
// Request / Response / Notification
// ---------------------------------------------------------------------------

/// A JSON-RPC 2.0 request on the bridge.
class BridgeRequest {
  final String id;
  final String method;
  final dynamic params;
  final Duration? timeout;

  BridgeRequest({
    required this.id,
    required this.method,
    this.params,
    this.timeout,
  });

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        if (params != null) 'params': params,
      };

  factory BridgeRequest.fromJson(Map<String, dynamic> json) => BridgeRequest(
        id: json['id'].toString(),
        method: json['method'] as String,
        params: json['params'],
      );

  @override
  String toString() => 'BridgeRequest($id, $method)';
}

/// A JSON-RPC 2.0 response on the bridge.
class BridgeResponse {
  final String id;
  final dynamic result;
  final BridgeError? error;

  const BridgeResponse({
    required this.id,
    this.result,
    this.error,
  });

  /// Whether this response indicates success.
  bool get isSuccess => error == null;

  /// Whether this response indicates failure.
  bool get isError => error != null;

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'id': id,
        if (result != null) 'result': result,
        if (error != null) 'error': error!.toJson(),
      };

  factory BridgeResponse.fromJson(Map<String, dynamic> json) =>
      BridgeResponse(
        id: json['id'].toString(),
        result: json['result'],
        error: json['error'] != null
            ? BridgeError.fromJson(json['error'] as Map<String, dynamic>)
            : null,
      );

  /// Create a success response.
  factory BridgeResponse.success(String id, [dynamic result]) =>
      BridgeResponse(id: id, result: result ?? {});

  /// Create an error response.
  factory BridgeResponse.error(String id, BridgeError error) =>
      BridgeResponse(id: id, error: error);

  @override
  String toString() => isSuccess
      ? 'BridgeResponse($id, success)'
      : 'BridgeResponse($id, error: $error)';
}

/// A JSON-RPC 2.0 notification (no id, no response expected).
class BridgeNotification {
  final String method;
  final dynamic params;

  const BridgeNotification({
    required this.method,
    this.params,
  });

  Map<String, dynamic> toJson() => {
        'jsonrpc': '2.0',
        'method': method,
        if (params != null) 'params': params,
      };

  factory BridgeNotification.fromJson(Map<String, dynamic> json) =>
      BridgeNotification(
        method: json['method'] as String,
        params: json['params'],
      );

  @override
  String toString() => 'BridgeNotification($method)';
}

// ---------------------------------------------------------------------------
// Message serializer
// ---------------------------------------------------------------------------

/// Handles serialization/deserialization of JSON-RPC 2.0 messages.
class MessageSerializer {
  const MessageSerializer();

  /// Serialize a message to JSON string.
  String serialize(Map<String, dynamic> message) => jsonEncode(message);

  /// Deserialize a raw string into a JSON map.
  ///
  /// Throws [BridgeError] with [ErrorCode.parseError] if the input is invalid.
  Map<String, dynamic> deserialize(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw BridgeError.parseError('Expected JSON object');
      }
      return decoded;
    } on FormatException catch (e) {
      throw BridgeError.parseError('Invalid JSON: ${e.message}');
    }
  }

  /// Determine the type of a parsed message.
  ///
  /// - Has 'id' and 'method' => request
  /// - Has 'id' but no 'method' => response
  /// - Has 'method' but no 'id' => notification
  MessageType classify(Map<String, dynamic> json) {
    final hasId = json.containsKey('id');
    final hasMethod = json.containsKey('method');
    if (hasId && hasMethod) return MessageType.request;
    if (hasId && !hasMethod) return MessageType.response;
    if (!hasId && hasMethod) return MessageType.notification;
    throw BridgeError.invalidRequest('Cannot classify message');
  }

  /// Parse a raw string into a typed protocol object.
  ProtocolMessage parse(String raw) {
    final json = deserialize(raw);
    final type = classify(json);
    return switch (type) {
      MessageType.request => ProtocolMessage.request(
          BridgeRequest.fromJson(json)),
      MessageType.response => ProtocolMessage.response(
          BridgeResponse.fromJson(json)),
      MessageType.notification => ProtocolMessage.notification(
          BridgeNotification.fromJson(json)),
    };
  }

  /// Encode a batch of messages for wire transport.
  String serializeBatch(List<Map<String, dynamic>> messages) =>
      jsonEncode(messages);

  /// Decode a batch response.
  List<Map<String, dynamic>> deserializeBatch(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>();
      }
      throw BridgeError.parseError('Expected JSON array for batch');
    } on FormatException catch (e) {
      throw BridgeError.parseError('Invalid JSON batch: ${e.message}');
    }
  }
}

/// Classification of a JSON-RPC message.
enum MessageType { request, response, notification }

/// A parsed protocol message (tagged union).
class ProtocolMessage {
  final MessageType type;
  final BridgeRequest? request;
  final BridgeResponse? response;
  final BridgeNotification? notification;

  const ProtocolMessage._({
    required this.type,
    this.request,
    this.response,
    this.notification,
  });

  factory ProtocolMessage.request(BridgeRequest req) =>
      ProtocolMessage._(type: MessageType.request, request: req);

  factory ProtocolMessage.response(BridgeResponse resp) =>
      ProtocolMessage._(type: MessageType.response, response: resp);

  factory ProtocolMessage.notification(BridgeNotification notif) =>
      ProtocolMessage._(type: MessageType.notification, notification: notif);
}

// ---------------------------------------------------------------------------
// Request registry
// ---------------------------------------------------------------------------

/// Tracks pending outgoing requests, handles timeouts.
class RequestRegistry {
  final Map<String, _PendingRequest> _pending = {};
  final Duration defaultTimeout;

  RequestRegistry({this.defaultTimeout = const Duration(seconds: 30)});

  /// Number of currently pending requests.
  int get pendingCount => _pending.length;

  /// Whether any requests are pending.
  bool get hasPending => _pending.isNotEmpty;

  /// Register a new outgoing request. Returns a future that completes
  /// with the response (or errors on timeout / cancellation).
  Future<BridgeResponse> register(BridgeRequest request) {
    final completer = Completer<BridgeResponse>();
    final timeout = request.timeout ?? defaultTimeout;

    Timer? timer;
    if (timeout != Duration.zero) {
      timer = Timer(timeout, () {
        if (_pending.containsKey(request.id)) {
          _pending.remove(request.id);
          completer.completeError(BridgeError(
            code: ErrorCode.requestCancelled,
            message: 'Request ${request.id} timed out after $timeout',
          ));
        }
      });
    }

    _pending[request.id] = _PendingRequest(
      request: request,
      completer: completer,
      timer: timer,
      registeredAt: DateTime.now(),
    );

    return completer.future;
  }

  /// Complete a pending request with a response.
  /// Returns true if the request was found and completed.
  bool complete(BridgeResponse response) {
    final pending = _pending.remove(response.id);
    if (pending == null) return false;
    pending.timer?.cancel();
    if (response.isError) {
      pending.completer.completeError(response.error!);
    } else {
      pending.completer.complete(response);
    }
    return true;
  }

  /// Cancel a pending request by id.
  bool cancel(String id, [String? reason]) {
    final pending = _pending.remove(id);
    if (pending == null) return false;
    pending.timer?.cancel();
    pending.completer.completeError(BridgeError(
      code: ErrorCode.requestCancelled,
      message: reason ?? 'Request $id cancelled',
    ));
    return true;
  }

  /// Cancel all pending requests.
  void cancelAll([String? reason]) {
    for (final entry in _pending.values) {
      entry.timer?.cancel();
      entry.completer.completeError(BridgeError(
        code: ErrorCode.requestCancelled,
        message: reason ?? 'All requests cancelled',
      ));
    }
    _pending.clear();
  }

  /// Get info about a pending request.
  BridgeRequest? getPending(String id) => _pending[id]?.request;

  /// Get all pending request IDs.
  List<String> get pendingIds => _pending.keys.toList();

  /// Duration since the oldest pending request was registered.
  Duration? get oldestPendingAge {
    if (_pending.isEmpty) return null;
    final oldest = _pending.values
        .map((p) => p.registeredAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    return DateTime.now().difference(oldest);
  }
}

class _PendingRequest {
  final BridgeRequest request;
  final Completer<BridgeResponse> completer;
  final Timer? timer;
  final DateTime registeredAt;

  _PendingRequest({
    required this.request,
    required this.completer,
    this.timer,
    required this.registeredAt,
  });
}

// ---------------------------------------------------------------------------
// Handler types
// ---------------------------------------------------------------------------

/// Handler for incoming requests. Returns the result to send back.
typedef RequestHandler = Future<dynamic> Function(
    String method, dynamic params);

/// Handler for incoming notifications.
typedef NotificationHandler = void Function(String method, dynamic params);

// ---------------------------------------------------------------------------
// Bridge protocol
// ---------------------------------------------------------------------------

/// The main protocol handler for bridge communication.
///
/// Manages JSON-RPC 2.0 message flow: sending requests/notifications,
/// dispatching incoming messages to registered handlers, and tracking
/// pending request state.
class BridgeProtocol {
  final MessageSerializer _serializer = const MessageSerializer();
  final RequestRegistry _registry;
  final Map<String, RequestHandler> _requestHandlers = {};
  final Map<String, NotificationHandler> _notificationHandlers = {};

  bool _initialized = false;
  BridgeHandshake? _remoteHandshake;
  Set<BridgeCapability> _remoteCapabilities = {};

  int _nextId = 1;

  final StreamController<String> _outgoing = StreamController.broadcast();
  final StreamController<BridgeError> _errors = StreamController.broadcast();
  final StreamController<BridgeNotification> _notifications =
      StreamController.broadcast();

  BridgeProtocol({
    Duration defaultTimeout = const Duration(seconds: 30),
  }) : _registry = RequestRegistry(defaultTimeout: defaultTimeout);

  // ---- State ----

  /// Whether the protocol has completed initialization handshake.
  bool get isInitialized => _initialized;

  /// Remote side handshake info (available after initialization).
  BridgeHandshake? get remoteHandshake => _remoteHandshake;

  /// Capabilities reported by the remote side.
  Set<BridgeCapability> get remoteCapabilities => _remoteCapabilities;

  /// Whether the remote side supports a given capability.
  bool hasCapability(BridgeCapability cap) => _remoteCapabilities.contains(cap);

  /// Number of pending outgoing requests.
  int get pendingRequestCount => _registry.pendingCount;

  // ---- Streams ----

  /// Outgoing serialized messages to be sent on the transport.
  Stream<String> get outgoing => _outgoing.stream;

  /// Protocol-level errors.
  Stream<BridgeError> get errors => _errors.stream;

  /// Incoming notifications (after dispatch).
  Stream<BridgeNotification> get incomingNotifications =>
      _notifications.stream;

  // ---- Message handling ----

  /// Handle a raw incoming message string from the transport layer.
  void handleMessage(String raw) {
    try {
      final msg = _serializer.parse(raw);
      switch (msg.type) {
        case MessageType.request:
          _handleRequest(msg.request!);
        case MessageType.response:
          _handleResponse(msg.response!);
        case MessageType.notification:
          _handleNotification(msg.notification!);
      }
    } on BridgeError catch (e) {
      _errors.add(e);
    } catch (e) {
      _errors.add(BridgeError.internalError(e.toString()));
    }
  }

  void _handleRequest(BridgeRequest request) async {
    if (!_initialized && request.method != 'initialize') {
      _send(BridgeResponse.error(
        request.id,
        BridgeError.serverNotInitialized(),
      ).toJson());
      return;
    }

    final handler = _requestHandlers[request.method];
    if (handler == null) {
      _send(BridgeResponse.error(
        request.id,
        BridgeError.methodNotFound(request.method),
      ).toJson());
      return;
    }

    try {
      final result = await handler(request.method, request.params);
      _send(BridgeResponse.success(request.id, result).toJson());
    } on BridgeError catch (e) {
      _send(BridgeResponse.error(request.id, e).toJson());
    } catch (e) {
      _send(BridgeResponse.error(
        request.id,
        BridgeError.internalError(e.toString()),
      ).toJson());
    }
  }

  void _handleResponse(BridgeResponse response) {
    if (!_registry.complete(response)) {
      _errors.add(BridgeError(
        code: ErrorCode.invalidRequest,
        message: 'No pending request for response id: ${response.id}',
      ));
    }
  }

  void _handleNotification(BridgeNotification notification) {
    _notifications.add(notification);
    final handler = _notificationHandlers[notification.method];
    handler?.call(notification.method, notification.params);
  }

  // ---- Sending ----

  /// Send a request and return a future for the response.
  Future<BridgeResponse> sendRequest(
    String method,
    dynamic params, {
    Duration? timeout,
  }) {
    final id = (_nextId++).toString();
    final request = BridgeRequest(
      id: id,
      method: method,
      params: params,
      timeout: timeout,
    );
    final future = _registry.register(request);
    _send(request.toJson());
    return future;
  }

  /// Send a notification (fire-and-forget, no response expected).
  void sendNotification(String method, [dynamic params]) {
    final notification = BridgeNotification(method: method, params: params);
    _send(notification.toJson());
  }

  void _send(Map<String, dynamic> message) {
    if (!_outgoing.isClosed) {
      _outgoing.add(_serializer.serialize(message));
    }
  }

  // ---- Handler registration ----

  /// Register a handler for incoming requests with a specific method.
  void registerHandler(String method, RequestHandler handler) {
    _requestHandlers[method] = handler;
  }

  /// Unregister a request handler.
  void unregisterHandler(String method) {
    _requestHandlers.remove(method);
  }

  /// Register a handler for incoming notifications with a specific method.
  void registerNotificationHandler(
      String method, NotificationHandler handler) {
    _notificationHandlers[method] = handler;
  }

  /// Unregister a notification handler.
  void unregisterNotificationHandler(String method) {
    _notificationHandlers.remove(method);
  }

  // ---- Protocol lifecycle methods ----

  /// Initialize the protocol with a handshake.
  Future<BridgeResponse> initialize(BridgeHandshake handshake) async {
    final response = await sendRequest('initialize', handshake.toJson());
    if (response.isSuccess && response.result is Map<String, dynamic>) {
      final result = response.result as Map<String, dynamic>;
      if (result.containsKey('capabilities')) {
        _remoteCapabilities = BridgeCapability.parseList(
            result['capabilities'] as List<dynamic>);
      }
      if (result.containsKey('clientName')) {
        _remoteHandshake =
            BridgeHandshake.fromJson(result);
      }
    }
    _initialized = true;
    sendNotification('initialized');
    return response;
  }

  /// Shutdown the protocol cleanly.
  Future<BridgeResponse> shutdown() async {
    final response = await sendRequest('shutdown', null);
    return response;
  }

  /// Send exit notification.
  void exit() {
    sendNotification('exit');
  }

  // ---- Text document methods ----

  /// Notify that a text document was opened.
  void textDocumentDidOpen({
    required String uri,
    required String languageId,
    required int version,
    required String text,
  }) {
    sendNotification('textDocument/didOpen', {
      'textDocument': {
        'uri': uri,
        'languageId': languageId,
        'version': version,
        'text': text,
      },
    });
  }

  /// Notify that a text document was changed.
  void textDocumentDidChange({
    required String uri,
    required int version,
    required List<Map<String, dynamic>> contentChanges,
  }) {
    sendNotification('textDocument/didChange', {
      'textDocument': {'uri': uri, 'version': version},
      'contentChanges': contentChanges,
    });
  }

  /// Notify that a text document was closed.
  void textDocumentDidClose({required String uri}) {
    sendNotification('textDocument/didClose', {
      'textDocument': {'uri': uri},
    });
  }

  /// Notify that a text document was saved.
  void textDocumentDidSave({
    required String uri,
    String? text,
  }) {
    sendNotification('textDocument/didSave', {
      'textDocument': {'uri': uri},
      if (text != null) 'text': text,
    });
  }

  /// Request completion at a position.
  Future<BridgeResponse> textDocumentCompletion({
    required String uri,
    required int line,
    required int character,
    Map<String, dynamic>? context,
  }) {
    return sendRequest('textDocument/completion', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
      if (context != null) 'context': context,
    });
  }

  /// Request hover info at a position.
  Future<BridgeResponse> textDocumentHover({
    required String uri,
    required int line,
    required int character,
  }) {
    return sendRequest('textDocument/hover', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
    });
  }

  /// Request definition of a symbol at a position.
  Future<BridgeResponse> textDocumentDefinition({
    required String uri,
    required int line,
    required int character,
  }) {
    return sendRequest('textDocument/definition', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
    });
  }

  /// Request references to a symbol at a position.
  Future<BridgeResponse> textDocumentReferences({
    required String uri,
    required int line,
    required int character,
    bool includeDeclaration = false,
  }) {
    return sendRequest('textDocument/references', {
      'textDocument': {'uri': uri},
      'position': {'line': line, 'character': character},
      'context': {'includeDeclaration': includeDeclaration},
    });
  }

  /// Request document formatting.
  Future<BridgeResponse> textDocumentFormatting({
    required String uri,
    int tabSize = 2,
    bool insertSpaces = true,
    Map<String, dynamic>? options,
  }) {
    return sendRequest('textDocument/formatting', {
      'textDocument': {'uri': uri},
      'options': {
        'tabSize': tabSize,
        'insertSpaces': insertSpaces,
        ...?options,
      },
    });
  }

  // ---- Workspace methods ----

  /// Request to apply a workspace edit.
  Future<BridgeResponse> workspaceApplyEdit({
    required Map<String, dynamic> edit,
    String? label,
  }) {
    return sendRequest('workspace/applyEdit', {
      'edit': edit,
      if (label != null) 'label': label,
    });
  }

  /// Request workspace configuration.
  Future<BridgeResponse> workspaceConfiguration({
    required List<Map<String, dynamic>> items,
  }) {
    return sendRequest('workspace/configuration', {
      'items': items,
    });
  }

  // ---- Window methods ----

  /// Show a message to the user.
  Future<BridgeResponse> windowShowMessage({
    required int type,
    required String message,
    List<String>? actions,
  }) {
    return sendRequest('window/showMessage', {
      'type': type,
      'message': message,
      if (actions != null) 'actions': actions,
    });
  }

  // ---- NeomClaw-specific methods ----

  /// Send a chat message to NeomClaw.
  Future<BridgeResponse> neomClawChat({
    required String message,
    String? conversationId,
    Map<String, dynamic>? options,
  }) {
    return sendRequest('neomclaw/chat', {
      'message': message,
      if (conversationId != null) 'conversationId': conversationId,
      if (options != null) 'options': options,
    });
  }

  /// Abort a running NeomClaw request.
  Future<BridgeResponse> neomClawAbort({String? conversationId}) {
    return sendRequest('neomclaw/abort', {
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  /// Get NeomClaw status.
  Future<BridgeResponse> neomClawStatus() {
    return sendRequest('neomclaw/status', null);
  }

  /// Invoke a NeomClaw tool.
  Future<BridgeResponse> neomClawTools({
    required String toolName,
    required Map<String, dynamic> toolInput,
    String? conversationId,
  }) {
    return sendRequest('neomclaw/tools', {
      'toolName': toolName,
      'toolInput': toolInput,
      if (conversationId != null) 'conversationId': conversationId,
    });
  }

  // ---- Progress / cancellation ----

  /// Send a progress notification.
  void progress({
    required String token,
    required Map<String, dynamic> value,
  }) {
    sendNotification(r'$/progress', {
      'token': token,
      'value': value,
    });
  }

  /// Cancel a pending request on the remote side.
  void cancelRequest(String id) {
    sendNotification(r'$/cancelRequest', {'id': id});
  }

  // ---- Cleanup ----

  /// Dispose the protocol, cancelling all pending requests.
  void dispose() {
    _registry.cancelAll('Protocol disposed');
    _outgoing.close();
    _errors.close();
    _notifications.close();
    _requestHandlers.clear();
    _notificationHandlers.clear();
  }
}
