// IDE bridge — port of neom_claw/src/bridge/.
// Protocol for VS Code, JetBrains, and other IDE integrations.
// Communication via WebSocket or stdin/stdout with JSON-RPC-like messages.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

// ---------------------------------------------------------------------------
// IDE types
// ---------------------------------------------------------------------------

/// IDE types supported by the bridge.
enum IdeType {
  vscode,
  jetbrains,
  neovim,
  emacs,
  sublime,
  custom;

  /// Human-readable display name.
  String get displayName => switch (this) {
        vscode => 'VS Code',
        jetbrains => 'JetBrains',
        neovim => 'Neovim',
        emacs => 'Emacs',
        sublime => 'Sublime Text',
        custom => 'Custom',
      };

  /// Parse from string identifier.
  static IdeType fromString(String s) => switch (s.toLowerCase()) {
        'vscode' || 'code' || 'vs code' => vscode,
        'jetbrains' || 'intellij' || 'idea' || 'webstorm' || 'pycharm' =>
          jetbrains,
        'neovim' || 'nvim' || 'vim' => neovim,
        'emacs' => emacs,
        'sublime' || 'sublimetext' || 'subl' => sublime,
        _ => custom,
      };
}

// ---------------------------------------------------------------------------
// Bridge message types
// ---------------------------------------------------------------------------

/// Bridge message types (IDE <-> NeomClaw).
enum BridgeMessageType {
  // IDE -> NeomClaw: requests
  openFile,
  showDiff,
  applyEdit,
  runCommand,
  getSelection,
  getOpenFiles,
  getDiagnostics,
  navigate,

  // NeomClaw -> IDE: notifications/responses
  fileOpened,
  editApplied,
  selectionResponse,
  diagnosticsResponse,
  openFilesResponse,
  commandResult,
  navigateResult,

  // Bidirectional
  ping,
  pong,
  error,
  status,

  // Lifecycle
  handshake,
  handshakeAck,
  disconnect;

  /// Wire name used in JSON serialization.
  String get wireName => switch (this) {
        openFile => 'open_file',
        showDiff => 'show_diff',
        applyEdit => 'apply_edit',
        runCommand => 'run_command',
        getSelection => 'get_selection',
        getOpenFiles => 'get_open_files',
        getDiagnostics => 'get_diagnostics',
        navigate => 'navigate',
        fileOpened => 'file_opened',
        editApplied => 'edit_applied',
        selectionResponse => 'selection_response',
        diagnosticsResponse => 'diagnostics_response',
        openFilesResponse => 'open_files_response',
        commandResult => 'command_result',
        navigateResult => 'navigate_result',
        ping => 'ping',
        pong => 'pong',
        error => 'error',
        status => 'status',
        handshake => 'handshake',
        handshakeAck => 'handshake_ack',
        disconnect => 'disconnect',
      };

  /// Parse from wire name.
  static BridgeMessageType? fromWireName(String name) {
    for (final type in values) {
      if (type.wireName == name) return type;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Bridge message
// ---------------------------------------------------------------------------

/// A single message on the bridge protocol.
class BridgeMessage {
  final String id;
  final BridgeMessageType type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? correlationId;

  BridgeMessage({
    String? id,
    required this.type,
    this.payload = const {},
    DateTime? timestamp,
    this.correlationId,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  /// Create a response message correlated to this request.
  BridgeMessage respond(BridgeMessageType responseType,
          [Map<String, dynamic> responsePayload = const {}]) =>
      BridgeMessage(
        type: responseType,
        payload: responsePayload,
        correlationId: id,
      );

  /// Serialize to JSON map for wire transport.
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.wireName,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
        if (correlationId != null) 'correlationId': correlationId,
      };

  /// Deserialize from JSON map.
  factory BridgeMessage.fromJson(Map<String, dynamic> json) {
    final type = BridgeMessageType.fromWireName(json['type'] as String);
    if (type == null) {
      throw FormatException('Unknown bridge message type: ${json['type']}');
    }
    return BridgeMessage(
      id: json['id'] as String?,
      type: type,
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      correlationId: json['correlationId'] as String?,
    );
  }

  /// Serialize to JSON string for sending over the wire.
  String encode() => jsonEncode(toJson());

  /// Deserialize from JSON string.
  factory BridgeMessage.decode(String raw) =>
      BridgeMessage.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  @override
  String toString() =>
      'BridgeMessage(${type.wireName}, id=${id.substring(0, 8)})';
}

// ---------------------------------------------------------------------------
// Data model classes
// ---------------------------------------------------------------------------

/// File edit request — describes a text replacement in a file.
class EditRequest {
  final String filePath;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;
  final String newText;
  final String? description;

  const EditRequest({
    required this.filePath,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
    required this.newText,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'startLine': startLine,
        'startColumn': startColumn,
        'endLine': endLine,
        'endColumn': endColumn,
        'newText': newText,
        if (description != null) 'description': description,
      };

  factory EditRequest.fromJson(Map<String, dynamic> json) => EditRequest(
        filePath: json['filePath'] as String,
        startLine: json['startLine'] as int,
        startColumn: json['startColumn'] as int,
        endLine: json['endLine'] as int,
        endColumn: json['endColumn'] as int,
        newText: json['newText'] as String,
        description: json['description'] as String?,
      );

  /// Convenience: create a full-line replacement.
  factory EditRequest.replaceLine(String filePath, int line, String newText) =>
      EditRequest(
        filePath: filePath,
        startLine: line,
        startColumn: 0,
        endLine: line,
        endColumn: 999999, // End of line.
        newText: newText,
      );

  /// Convenience: create an insertion at a position.
  factory EditRequest.insert(
          String filePath, int line, int column, String text) =>
      EditRequest(
        filePath: filePath,
        startLine: line,
        startColumn: column,
        endLine: line,
        endColumn: column,
        newText: text,
      );
}

/// Diff display request — show a before/after diff in the IDE.
class DiffRequest {
  final String filePath;
  final String originalContent;
  final String modifiedContent;
  final String? title;
  final bool? readOnly;

  const DiffRequest({
    required this.filePath,
    required this.originalContent,
    required this.modifiedContent,
    this.title,
    this.readOnly,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'originalContent': originalContent,
        'modifiedContent': modifiedContent,
        if (title != null) 'title': title,
        if (readOnly != null) 'readOnly': readOnly,
      };

  factory DiffRequest.fromJson(Map<String, dynamic> json) => DiffRequest(
        filePath: json['filePath'] as String,
        originalContent: json['originalContent'] as String,
        modifiedContent: json['modifiedContent'] as String,
        title: json['title'] as String?,
        readOnly: json['readOnly'] as bool?,
      );
}

/// Current editor selection.
class EditorSelection {
  final String filePath;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;
  final String selectedText;

  const EditorSelection({
    required this.filePath,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
    required this.selectedText,
  });

  bool get isEmpty => selectedText.isEmpty;
  bool get isMultiLine => startLine != endLine;

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'startLine': startLine,
        'startColumn': startColumn,
        'endLine': endLine,
        'endColumn': endColumn,
        'selectedText': selectedText,
      };

  factory EditorSelection.fromJson(Map<String, dynamic> json) =>
      EditorSelection(
        filePath: json['filePath'] as String,
        startLine: json['startLine'] as int,
        startColumn: json['startColumn'] as int,
        endLine: json['endLine'] as int,
        endColumn: json['endColumn'] as int,
        selectedText: json['selectedText'] as String,
      );
}

/// A diagnostic (error, warning, info) from the IDE.
class IdeDiagnostic {
  final String filePath;
  final int line;
  final int column;
  final String message;
  final DiagnosticSeverity severity;
  final String? source;
  final String? code;

  const IdeDiagnostic({
    required this.filePath,
    required this.line,
    required this.column,
    required this.message,
    required this.severity,
    this.source,
    this.code,
  });

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'line': line,
        'column': column,
        'message': message,
        'severity': severity.name,
        if (source != null) 'source': source,
        if (code != null) 'code': code,
      };

  factory IdeDiagnostic.fromJson(Map<String, dynamic> json) => IdeDiagnostic(
        filePath: json['filePath'] as String,
        line: json['line'] as int,
        column: json['column'] as int,
        message: json['message'] as String,
        severity: DiagnosticSeverity.values.firstWhere(
          (s) => s.name == json['severity'],
          orElse: () => DiagnosticSeverity.info,
        ),
        source: json['source'] as String?,
        code: json['code'] as String?,
      );
}

/// Severity levels for diagnostics.
enum DiagnosticSeverity { error, warning, info, hint }

/// IDE capabilities — what the connected IDE supports.
class IdeCapabilities {
  final bool supportsDiff;
  final bool supportsInlineEdit;
  final bool supportsTerminal;
  final bool supportsDiagnostics;
  final bool supportsSymbolNavigation;
  final bool supportsMultiRoot;
  final bool supportsFileWatcher;
  final bool supportsCodeLens;
  final String? ideVersion;
  final String? extensionVersion;

  const IdeCapabilities({
    this.supportsDiff = false,
    this.supportsInlineEdit = false,
    this.supportsTerminal = false,
    this.supportsDiagnostics = false,
    this.supportsSymbolNavigation = false,
    this.supportsMultiRoot = false,
    this.supportsFileWatcher = false,
    this.supportsCodeLens = false,
    this.ideVersion,
    this.extensionVersion,
  });

  /// All capabilities enabled (VS Code full extension).
  static const full = IdeCapabilities(
    supportsDiff: true,
    supportsInlineEdit: true,
    supportsTerminal: true,
    supportsDiagnostics: true,
    supportsSymbolNavigation: true,
    supportsMultiRoot: true,
    supportsFileWatcher: true,
    supportsCodeLens: true,
  );

  /// Minimal capabilities (basic terminal-only integration).
  static const minimal = IdeCapabilities(supportsTerminal: true);

  Map<String, dynamic> toJson() => {
        'supportsDiff': supportsDiff,
        'supportsInlineEdit': supportsInlineEdit,
        'supportsTerminal': supportsTerminal,
        'supportsDiagnostics': supportsDiagnostics,
        'supportsSymbolNavigation': supportsSymbolNavigation,
        'supportsMultiRoot': supportsMultiRoot,
        'supportsFileWatcher': supportsFileWatcher,
        'supportsCodeLens': supportsCodeLens,
        if (ideVersion != null) 'ideVersion': ideVersion,
        if (extensionVersion != null) 'extensionVersion': extensionVersion,
      };

  factory IdeCapabilities.fromJson(Map<String, dynamic> json) =>
      IdeCapabilities(
        supportsDiff: json['supportsDiff'] as bool? ?? false,
        supportsInlineEdit: json['supportsInlineEdit'] as bool? ?? false,
        supportsTerminal: json['supportsTerminal'] as bool? ?? false,
        supportsDiagnostics: json['supportsDiagnostics'] as bool? ?? false,
        supportsSymbolNavigation:
            json['supportsSymbolNavigation'] as bool? ?? false,
        supportsMultiRoot: json['supportsMultiRoot'] as bool? ?? false,
        supportsFileWatcher: json['supportsFileWatcher'] as bool? ?? false,
        supportsCodeLens: json['supportsCodeLens'] as bool? ?? false,
        ideVersion: json['ideVersion'] as String?,
        extensionVersion: json['extensionVersion'] as String?,
      );
}

// ---------------------------------------------------------------------------
// IDE Bridge connection
// ---------------------------------------------------------------------------

/// State of a bridge connection.
enum BridgeConnectionState { disconnected, connecting, connected, error }

/// A single IDE bridge connection.
///
/// Manages the WebSocket or stdin/stdout transport to an IDE extension,
/// handles message serialization, request-response correlation, and
/// keepalive heartbeats.
class IdeBridge {
  final String connectionId;
  final IdeType ideType;
  IdeCapabilities capabilities;
  BridgeConnectionState _state = BridgeConnectionState.disconnected;

  WebSocket? _webSocket;
  StreamSubscription<dynamic>? _socketSubscription;
  Timer? _heartbeatTimer;
  DateTime? _lastPong;

  /// Pending request completers, keyed by message id.
  final Map<String, Completer<BridgeMessage>> _pendingRequests = {};

  /// Incoming message stream for listeners.
  final StreamController<BridgeMessage> _incomingController =
      StreamController<BridgeMessage>.broadcast();

  /// State change stream.
  final StreamController<BridgeConnectionState> _stateController =
      StreamController<BridgeConnectionState>.broadcast();

  /// Heartbeat interval.
  final Duration heartbeatInterval;

  /// Request timeout.
  final Duration requestTimeout;

  IdeBridge({
    String? connectionId,
    required this.ideType,
    this.capabilities = const IdeCapabilities(),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.requestTimeout = const Duration(seconds: 10),
  }) : connectionId = connectionId ?? _uuid.v4();

  BridgeConnectionState get state => _state;
  Stream<BridgeMessage> get messages => _incomingController.stream;
  Stream<BridgeConnectionState> get stateChanges => _stateController.stream;
  bool get isConnected => _state == BridgeConnectionState.connected;

  void _setState(BridgeConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// Connect to an IDE extension via WebSocket.
  Future<void> connectWebSocket(String url) async {
    _setState(BridgeConnectionState.connecting);
    try {
      _webSocket = await WebSocket.connect(url);
      _setupSocketListeners();
      _startHeartbeat();
      await _performHandshake();
      _setState(BridgeConnectionState.connected);
    } catch (e) {
      _setState(BridgeConnectionState.error);
      rethrow;
    }
  }

  /// Attach to an existing WebSocket (from server accepting a connection).
  void attachWebSocket(WebSocket socket) {
    _webSocket = socket;
    _setupSocketListeners();
    _startHeartbeat();
    _setState(BridgeConnectionState.connected);
  }

  void _setupSocketListeners() {
    _socketSubscription = _webSocket!.listen(
      (data) {
        if (data is String) {
          _handleRawMessage(data);
        }
      },
      onError: (Object error) {
        _setState(BridgeConnectionState.error);
      },
      onDone: () {
        _setState(BridgeConnectionState.disconnected);
        _cleanup();
      },
    );
  }

  void _handleRawMessage(String raw) {
    BridgeMessage message;
    try {
      message = BridgeMessage.decode(raw);
    } catch (e) {
      // Malformed message — ignore.
      return;
    }

    // Handle pong responses for heartbeat.
    if (message.type == BridgeMessageType.pong) {
      _lastPong = DateTime.now();
      return;
    }

    // Handle ping — respond with pong.
    if (message.type == BridgeMessageType.ping) {
      send(message.respond(BridgeMessageType.pong));
      return;
    }

    // Handle handshake acknowledgement.
    if (message.type == BridgeMessageType.handshakeAck) {
      final caps = message.payload['capabilities'] as Map<String, dynamic>?;
      if (caps != null) {
        capabilities = IdeCapabilities.fromJson(caps);
      }
    }

    // Resolve pending request if this is a correlated response.
    if (message.correlationId != null) {
      final completer = _pendingRequests.remove(message.correlationId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
        return;
      }
    }

    // Emit to general listeners.
    if (!_incomingController.isClosed) {
      _incomingController.add(message);
    }
  }

  /// Send a message to the IDE.
  void send(BridgeMessage message) {
    if (_webSocket == null) return;
    _webSocket!.add(message.encode());
  }

  /// Send a request and await a correlated response.
  Future<BridgeMessage> request(BridgeMessage message) {
    final completer = Completer<BridgeMessage>();
    _pendingRequests[message.id] = completer;

    send(message);

    // Apply timeout.
    return completer.future.timeout(
      requestTimeout,
      onTimeout: () {
        _pendingRequests.remove(message.id);
        throw TimeoutException(
          'Bridge request timed out: ${message.type.wireName}',
          requestTimeout,
        );
      },
    );
  }

  Future<void> _performHandshake() async {
    final handshake = BridgeMessage(
      type: BridgeMessageType.handshake,
      payload: {
        'protocolVersion': '1.0',
        'clientType': 'neom-claw',
        'ideType': ideType.name,
      },
    );
    try {
      final response = await request(handshake);
      if (response.type == BridgeMessageType.handshakeAck) {
        final caps = response.payload['capabilities'] as Map<String, dynamic>?;
        if (caps != null) {
          capabilities = IdeCapabilities.fromJson(caps);
        }
      }
    } on TimeoutException {
      // Handshake timeout — proceed with default capabilities.
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_webSocket == null) return;

      // Check if last pong was too long ago.
      if (_lastPong != null) {
        final elapsed = DateTime.now().difference(_lastPong!);
        if (elapsed > heartbeatInterval * 3) {
          _setState(BridgeConnectionState.error);
          disconnect();
          return;
        }
      }

      send(BridgeMessage(type: BridgeMessageType.ping));
    });
  }

  // -- High-level IDE operations --

  /// Open a file in the IDE editor.
  Future<BridgeMessage> openFile(String filePath, {int? line, int? column}) =>
      request(BridgeMessage(
        type: BridgeMessageType.openFile,
        payload: {
          'filePath': filePath,
          if (line != null) 'line': line,
          if (column != null) 'column': column,
        },
      ));

  /// Show a diff in the IDE.
  Future<BridgeMessage> showDiff(DiffRequest diff) =>
      request(BridgeMessage(
        type: BridgeMessageType.showDiff,
        payload: diff.toJson(),
      ));

  /// Apply a text edit in the IDE.
  Future<BridgeMessage> applyEdit(EditRequest edit) =>
      request(BridgeMessage(
        type: BridgeMessageType.applyEdit,
        payload: edit.toJson(),
      ));

  /// Apply multiple edits atomically (if the IDE supports it).
  Future<List<BridgeMessage>> applyEdits(List<EditRequest> edits) async {
    final futures = edits.map((e) => applyEdit(e));
    return Future.wait(futures);
  }

  /// Run a terminal command in the IDE.
  Future<BridgeMessage> runCommand(String command, {String? cwd}) =>
      request(BridgeMessage(
        type: BridgeMessageType.runCommand,
        payload: {
          'command': command,
          if (cwd != null) 'cwd': cwd,
        },
      ));

  /// Get the current editor selection.
  Future<EditorSelection?> getSelection() async {
    final response = await request(
      BridgeMessage(type: BridgeMessageType.getSelection),
    );
    if (response.type == BridgeMessageType.selectionResponse &&
        response.payload.isNotEmpty) {
      return EditorSelection.fromJson(response.payload);
    }
    return null;
  }

  /// Get the list of currently open files.
  Future<List<String>> getOpenFiles() async {
    final response = await request(
      BridgeMessage(type: BridgeMessageType.getOpenFiles),
    );
    if (response.type == BridgeMessageType.openFilesResponse) {
      final files = response.payload['files'] as List<dynamic>?;
      return files?.cast<String>() ?? [];
    }
    return [];
  }

  /// Get diagnostics (errors, warnings) from the IDE.
  Future<List<IdeDiagnostic>> getDiagnostics({String? filePath}) async {
    final response = await request(BridgeMessage(
      type: BridgeMessageType.getDiagnostics,
      payload: {if (filePath != null) 'filePath': filePath},
    ));
    if (response.type == BridgeMessageType.diagnosticsResponse) {
      final diagnostics = response.payload['diagnostics'] as List<dynamic>?;
      return diagnostics
              ?.map((d) =>
                  IdeDiagnostic.fromJson(d as Map<String, dynamic>))
              .toList() ??
          [];
    }
    return [];
  }

  /// Navigate to a symbol or position in the IDE.
  Future<BridgeMessage> navigate({
    required String filePath,
    int? line,
    int? column,
    String? symbol,
  }) =>
      request(BridgeMessage(
        type: BridgeMessageType.navigate,
        payload: {
          'filePath': filePath,
          if (line != null) 'line': line,
          if (column != null) 'column': column,
          if (symbol != null) 'symbol': symbol,
        },
      ));

  /// Disconnect from the IDE.
  Future<void> disconnect() async {
    send(BridgeMessage(type: BridgeMessageType.disconnect));
    await _cleanup();
    _setState(BridgeConnectionState.disconnected);
  }

  Future<void> _cleanup() async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    await _webSocket?.close();
    _webSocket = null;
    // Complete all pending requests with an error.
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Bridge connection closed'),
        );
      }
    }
    _pendingRequests.clear();
  }

  /// Dispose of all resources.
  Future<void> dispose() async {
    await disconnect();
    await _incomingController.close();
    await _stateController.close();
  }
}

// ---------------------------------------------------------------------------
// IDE Bridge server
// ---------------------------------------------------------------------------

/// IDE Bridge server — listens for incoming IDE extension connections.
///
/// Runs a local WebSocket server on a configurable port or Unix socket.
/// Multiple IDE connections can be active simultaneously.
class IdeBridgeServer {
  final int port;
  final String host;
  HttpServer? _httpServer;
  final Map<String, IdeBridge> _connections = {};
  final StreamController<IdeBridge> _connectionController =
      StreamController<IdeBridge>.broadcast();

  /// Handler for incoming messages that aren't correlated responses.
  void Function(IdeBridge bridge, BridgeMessage message)? onMessage;

  IdeBridgeServer({this.port = 19836, this.host = 'localhost'});

  /// All active connections.
  Iterable<IdeBridge> get connections => _connections.values;

  /// Stream of new connections.
  Stream<IdeBridge> get onConnection => _connectionController.stream;

  /// Number of active connections.
  int get connectionCount => _connections.length;

  /// Start listening for IDE connections.
  Future<void> start() async {
    _httpServer = await HttpServer.bind(host, port);
    _httpServer!.listen(_handleHttpRequest);
  }

  void _handleHttpRequest(HttpRequest request) {
    // Only accept WebSocket upgrade requests.
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('WebSocket upgrade required');
      request.response.close();
      return;
    }

    WebSocketTransformer.upgrade(request).then((socket) {
      _handleNewConnection(socket, request);
    }).catchError((Object e) {
      // Upgrade failed — nothing to do.
    });
  }

  void _handleNewConnection(WebSocket socket, HttpRequest request) {
    // Determine IDE type from query parameters or headers.
    final ideTypeStr =
        request.uri.queryParameters['ide'] ?? request.headers.value('x-ide-type') ?? 'custom';
    final ideType = IdeType.fromString(ideTypeStr);

    final bridge = IdeBridge(ideType: ideType);
    bridge.attachWebSocket(socket);

    _connections[bridge.connectionId] = bridge;

    // Listen for state changes to clean up on disconnect.
    bridge.stateChanges.listen((state) {
      if (state == BridgeConnectionState.disconnected) {
        _connections.remove(bridge.connectionId);
      }
    });

    // Forward messages to the server handler.
    if (onMessage != null) {
      bridge.messages.listen((msg) => onMessage!(bridge, msg));
    }

    if (!_connectionController.isClosed) {
      _connectionController.add(bridge);
    }
  }

  /// Send a message to all connected IDEs.
  void broadcast(BridgeMessage message) {
    for (final bridge in _connections.values) {
      if (bridge.isConnected) bridge.send(message);
    }
  }

  /// Find a connection by IDE type.
  IdeBridge? findByIdeType(IdeType type) {
    for (final bridge in _connections.values) {
      if (bridge.ideType == type && bridge.isConnected) return bridge;
    }
    return null;
  }

  /// Find a connection by connection ID.
  IdeBridge? findById(String connectionId) => _connections[connectionId];

  /// Get the first connected bridge, if any.
  IdeBridge? get firstConnected {
    for (final bridge in _connections.values) {
      if (bridge.isConnected) return bridge;
    }
    return null;
  }

  /// Stop the server and disconnect all clients.
  Future<void> stop() async {
    for (final bridge in _connections.values) {
      await bridge.dispose();
    }
    _connections.clear();
    await _httpServer?.close();
    _httpServer = null;
    await _connectionController.close();
  }

  /// The URL clients should connect to.
  String get connectUrl => 'ws://$host:$port';
}

// ---------------------------------------------------------------------------
// Stdio bridge (for processes that communicate over stdin/stdout)
// ---------------------------------------------------------------------------

/// A bridge connection over stdin/stdout, used for IDE extensions that
/// launch NeomClaw as a subprocess.
class StdioBridge {
  final IdeBridge bridge;
  final Stream<List<int>> _stdin;
  final IOSink _stdout;
  StreamSubscription<String>? _stdinSubscription;

  StdioBridge({
    required IdeType ideType,
    Stream<List<int>>? stdinStream,
    IOSink? stdoutSink,
  })  : bridge = IdeBridge(ideType: ideType),
        _stdin = stdinStream ?? stdin,
        _stdout = stdoutSink ?? stdout;

  /// Start reading from stdin and writing responses to stdout.
  void start() {
    bridge._setState(BridgeConnectionState.connected);

    _stdinSubscription = _stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        bridge._handleRawMessage(line);
      },
      onError: (Object e) {
        bridge._setState(BridgeConnectionState.error);
      },
      onDone: () {
        bridge._setState(BridgeConnectionState.disconnected);
      },
    );

    // Intercept outgoing messages and write them to stdout.
    bridge.messages.listen((msg) {
      _writeLine(msg.encode());
    });
  }

  void _writeLine(String data) {
    _stdout.writeln(data);
  }

  /// Send a message to the IDE (via stdout).
  void send(BridgeMessage message) {
    _writeLine(message.encode());
  }

  /// Stop the stdio bridge.
  Future<void> stop() async {
    await _stdinSubscription?.cancel();
    await bridge.dispose();
  }
}

// ---------------------------------------------------------------------------
// IDE manifest generation
// ---------------------------------------------------------------------------

/// Generate a VS Code extension manifest (package.json) for the NeomClaw
/// bridge extension.
Map<String, dynamic> generateVscodeManifest({
  String name = 'neom-claw-bridge',
  String displayName = 'NeomClaw Bridge',
  String version = '1.0.0',
  String description = 'Bridge extension connecting VS Code to NeomClaw',
  int port = 19836,
}) {
  return {
    'name': name,
    'displayName': displayName,
    'version': version,
    'description': description,
    'publisher': 'anthropic',
    'engines': {'vscode': '^1.80.0'},
    'categories': ['Other'],
    'activationEvents': ['onStartupFinished'],
    'main': './out/extension.js',
    'contributes': {
      'commands': [
        {
          'command': 'neom-claw.connect',
          'title': 'NeomClaw: Connect',
        },
        {
          'command': 'neom-claw.disconnect',
          'title': 'NeomClaw: Disconnect',
        },
        {
          'command': 'neom-claw.showDiff',
          'title': 'NeomClaw: Show Diff',
        },
        {
          'command': 'neom-claw.sendSelection',
          'title': 'NeomClaw: Send Selection',
        },
      ],
      'configuration': {
        'title': 'NeomClaw Bridge',
        'properties': {
          'neomClawCode.port': {
            'type': 'number',
            'default': port,
            'description': 'Port for the NeomClaw bridge server',
          },
          'neomClawCode.autoConnect': {
            'type': 'boolean',
            'default': true,
            'description': 'Automatically connect on startup',
          },
        },
      },
      'menus': {
        'editor/context': [
          {
            'command': 'neom-claw.sendSelection',
            'when': 'editorHasSelection',
            'group': 'neom-claw',
          },
        ],
      },
    },
    'scripts': {
      'vscode:prepublish': 'npm run compile',
      'compile': 'tsc -p ./',
      'watch': 'tsc -watch -p ./',
    },
    'devDependencies': {
      '@types/vscode': '^1.80.0',
      '@types/node': '^18.0.0',
      'typescript': '^5.0.0',
    },
    'dependencies': {
      'ws': '^8.0.0',
    },
  };
}

/// Generate a JetBrains plugin descriptor (plugin.xml content as a map).
Map<String, dynamic> generateJetbrainsConfig({
  String id = 'com.anthropic.neom-claw-bridge',
  String name = 'NeomClaw Bridge',
  String version = '1.0.0',
  String description = 'Bridge plugin connecting JetBrains IDEs to NeomClaw',
  int port = 19836,
}) {
  return {
    'id': id,
    'name': name,
    'version': version,
    'description': description,
    'vendor': {
      'name': 'Anthropic',
      'url': 'https://anthropic.com',
      'email': 'support@anthropic.com',
    },
    'ideaVersion': {
      'sinceBuild': '231.0',
      'untilBuild': '243.*',
    },
    'depends': [
      'com.intellij.modules.platform',
      'com.intellij.modules.lang',
    ],
    'extensions': {
      'defaultExtensionNs': 'com.intellij',
      'applicationService': {
        'serviceImplementation':
            'com.anthropic.claudecode.bridge.BridgeService',
      },
      'postStartupActivity': {
        'implementation':
            'com.anthropic.claudecode.bridge.BridgeStartupActivity',
      },
      'notificationGroup': {
        'id': 'NeomClaw',
        'displayType': 'BALLOON',
      },
    },
    'actions': {
      'group': {
        'id': 'NeomClawCode.Menu',
        'text': 'NeomClaw',
        'popup': true,
        'addToGroup': {'groupId': 'ToolsMenu', 'anchor': 'last'},
        'actions': [
          {
            'id': 'NeomClawCode.Connect',
            'text': 'Connect to NeomClaw',
            'description': 'Establish connection to NeomClaw bridge',
          },
          {
            'id': 'NeomClawCode.Disconnect',
            'text': 'Disconnect',
            'description': 'Disconnect from NeomClaw bridge',
          },
          {
            'id': 'NeomClawCode.SendSelection',
            'text': 'Send Selection to NeomClaw',
            'description': 'Send the current editor selection to NeomClaw',
          },
        ],
      },
    },
    'settings': {
      'port': port,
      'autoConnect': true,
      'reconnectIntervalMs': 5000,
      'maxReconnectAttempts': 10,
    },
  };
}

// ---------------------------------------------------------------------------
// Bridge discovery
// ---------------------------------------------------------------------------

/// Discover running bridge servers on common ports.
///
/// Attempts to connect to a range of ports and returns any that respond
/// with a valid handshake.
Future<List<BridgeServerInfo>> discoverBridgeServers({
  String host = 'localhost',
  List<int> ports = const [19836, 19837, 19838, 19839, 19840],
  Duration timeout = const Duration(seconds: 2),
}) async {
  final results = <BridgeServerInfo>[];
  final futures = <Future<void>>[];

  for (final port in ports) {
    futures.add(_probePort(host, port, timeout).then((info) {
      if (info != null) results.add(info);
    }).catchError((Object _) {
      // Port not available — skip.
    }));
  }

  await Future.wait(futures);
  return results;
}

Future<BridgeServerInfo?> _probePort(
    String host, int port, Duration timeout) async {
  try {
    final socket = await WebSocket.connect(
      'ws://$host:$port',
    ).timeout(timeout);

    final completer = Completer<BridgeServerInfo?>();

    socket.listen(
      (data) {
        if (data is String && !completer.isCompleted) {
          try {
            final msg = BridgeMessage.decode(data);
            if (msg.type == BridgeMessageType.handshakeAck ||
                msg.type == BridgeMessageType.pong) {
              completer.complete(BridgeServerInfo(
                host: host,
                port: port,
                ideType: msg.payload['ideType'] as String?,
                protocolVersion: msg.payload['protocolVersion'] as String?,
              ));
            }
          } catch (_) {
            // Not a valid bridge message.
          }
        }
      },
      onDone: () {
        if (!completer.isCompleted) completer.complete(null);
      },
      onError: (Object _) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    // Send a ping to elicit a response.
    socket.add(BridgeMessage(type: BridgeMessageType.ping).encode());

    final info = await completer.future.timeout(timeout, onTimeout: () => null);
    await socket.close();
    return info;
  } catch (_) {
    return null;
  }
}

/// Information about a discovered bridge server.
class BridgeServerInfo {
  final String host;
  final int port;
  final String? ideType;
  final String? protocolVersion;

  const BridgeServerInfo({
    required this.host,
    required this.port,
    this.ideType,
    this.protocolVersion,
  });

  String get connectUrl => 'ws://$host:$port';

  @override
  String toString() =>
      'BridgeServer($connectUrl, ide=$ideType, protocol=$protocolVersion)';
}

// ---------------------------------------------------------------------------
// Utility: message builders
// ---------------------------------------------------------------------------

/// Build a status message.
BridgeMessage statusMessage(String status, {Map<String, dynamic>? extra}) =>
    BridgeMessage(
      type: BridgeMessageType.status,
      payload: {'status': status, ...?extra},
    );

/// Build an error message.
BridgeMessage errorMessage(String message, {String? code}) =>
    BridgeMessage(
      type: BridgeMessageType.error,
      payload: {'message': message, if (code != null) 'code': code},
    );

/// Build an open-file request.
BridgeMessage openFileMessage(String filePath, {int? line, int? column}) =>
    BridgeMessage(
      type: BridgeMessageType.openFile,
      payload: {
        'filePath': filePath,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
      },
    );

/// Build a show-diff request.
BridgeMessage showDiffMessage(DiffRequest diff) =>
    BridgeMessage(type: BridgeMessageType.showDiff, payload: diff.toJson());

/// Build an apply-edit request.
BridgeMessage applyEditMessage(EditRequest edit) =>
    BridgeMessage(type: BridgeMessageType.applyEdit, payload: edit.toJson());
