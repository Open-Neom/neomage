// app_state.dart — Global application state for neomage
// Port of neomage/src/state/ (~1.2K TS LOC) adapted to Sint patterns.

import 'dart:async';

// ---------------------------------------------------------------------------
// State event hierarchy — sealed class for reactive updates
// ---------------------------------------------------------------------------

sealed class StateEvent {
  final DateTime timestamp;
  StateEvent() : timestamp = DateTime.now();
}

class SessionStarted extends StateEvent {
  final String sessionId;
  SessionStarted(this.sessionId);
}

class SessionEnded extends StateEvent {
  final String sessionId;
  final String reason;
  SessionEnded(this.sessionId, {this.reason = 'user'});
}

class ModelChanged extends StateEvent {
  final String previousModel;
  final String newModel;
  ModelChanged({required this.previousModel, required this.newModel});
}

class ProviderChanged extends StateEvent {
  final String previousProvider;
  final String newProvider;
  ProviderChanged({required this.previousProvider, required this.newProvider});
}

class PermissionModeChanged extends StateEvent {
  final PermissionMode previousMode;
  final PermissionMode newMode;
  PermissionModeChanged({required this.previousMode, required this.newMode});
}

class ConnectionStatusChanged extends StateEvent {
  final String service;
  final ConnectionStatus previousStatus;
  final ConnectionStatus newStatus;
  ConnectionStatusChanged({
    required this.service,
    required this.previousStatus,
    required this.newStatus,
  });
}

class NavigationChanged extends StateEvent {
  final String view;
  NavigationChanged(this.view);
}

class FeatureFlagChanged extends StateEvent {
  final String flag;
  final bool enabled;
  FeatureFlagChanged({required this.flag, required this.enabled});
}

class WorkingDirectoryChanged extends StateEvent {
  final String previousDir;
  final String newDir;
  WorkingDirectoryChanged({required this.previousDir, required this.newDir});
}

class McpServerConnected extends StateEvent {
  final String serverName;
  McpServerConnected(this.serverName);
}

class McpServerDisconnected extends StateEvent {
  final String serverName;
  final String reason;
  McpServerDisconnected(this.serverName, {this.reason = ''});
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

enum PermissionMode {
  ask,
  autoAllow,
  deny;

  String get label => switch (this) {
    ask => 'Ask',
    autoAllow => 'Auto-allow',
    deny => 'Deny',
  };
}

enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  reconnecting;

  bool get isActive => this == connected || this == reconnecting;

  String get label => switch (this) {
    disconnected => 'Disconnected',
    connecting => 'Connecting',
    connected => 'Connected',
    error => 'Error',
    reconnecting => 'Reconnecting',
  };
}

// ---------------------------------------------------------------------------
// SessionState — current session state
// ---------------------------------------------------------------------------

class SessionState {
  final String id;
  final DateTime startTime;
  final List<SessionMessage> messages;
  int inputTokens;
  int outputTokens;
  double cost;
  String? activeModel;
  String? activeProvider;
  bool isStreaming;

  SessionState({
    required this.id,
    DateTime? startTime,
    List<SessionMessage>? messages,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0.0,
    this.activeModel,
    this.activeProvider,
    this.isStreaming = false,
  }) : startTime = startTime ?? DateTime.now(),
       messages = messages ?? [];

  int get totalTokens => inputTokens + outputTokens;
  int get messageCount => messages.length;
  Duration get elapsed => DateTime.now().difference(startTime);

  void addMessage(SessionMessage message) {
    messages.add(message);
    inputTokens += message.inputTokens;
    outputTokens += message.outputTokens;
    cost += message.cost;
  }

  void updateTokens({int? input, int? output, double? addCost}) {
    if (input != null) inputTokens += input;
    if (output != null) outputTokens += output;
    if (addCost != null) cost += addCost;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime.toIso8601String(),
    'messageCount': messageCount,
    'inputTokens': inputTokens,
    'outputTokens': outputTokens,
    'totalTokens': totalTokens,
    'cost': cost,
    'activeModel': activeModel,
    'activeProvider': activeProvider,
    'elapsed': elapsed.inSeconds,
  };

  factory SessionState.fromJson(Map<String, dynamic> json) => SessionState(
    id: json['id'] as String,
    startTime: DateTime.parse(json['startTime'] as String),
    inputTokens: json['inputTokens'] as int? ?? 0,
    outputTokens: json['outputTokens'] as int? ?? 0,
    cost: (json['cost'] as num?)?.toDouble() ?? 0.0,
    activeModel: json['activeModel'] as String?,
    activeProvider: json['activeProvider'] as String?,
  );
}

class SessionMessage {
  final String role;
  final String content;
  final DateTime timestamp;
  final int inputTokens;
  final int outputTokens;
  final double cost;
  final Map<String, dynamic>? metadata;

  SessionMessage({
    required this.role,
    required this.content,
    DateTime? timestamp,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cost = 0.0,
    this.metadata,
  }) : timestamp = timestamp ?? DateTime.now();
}

// ---------------------------------------------------------------------------
// NavigationState
// ---------------------------------------------------------------------------

class NavigationState {
  String currentView;
  final List<String> history;
  final List<String> breadcrumbs;
  int _historyIndex;

  NavigationState({
    this.currentView = 'chat',
    List<String>? history,
    List<String>? breadcrumbs,
  }) : history = history ?? ['chat'],
       breadcrumbs = breadcrumbs ?? ['Home'],
       _historyIndex = 0;

  void navigateTo(String view, {String? breadcrumb}) {
    // Trim forward history if we navigated back
    if (_historyIndex < history.length - 1) {
      history.removeRange(_historyIndex + 1, history.length);
    }
    currentView = view;
    history.add(view);
    _historyIndex = history.length - 1;
    if (breadcrumb != null) {
      breadcrumbs.add(breadcrumb);
    }
  }

  bool canGoBack() => _historyIndex > 0;
  bool canGoForward() => _historyIndex < history.length - 1;

  String? goBack() {
    if (!canGoBack()) return null;
    _historyIndex--;
    currentView = history[_historyIndex];
    if (breadcrumbs.length > 1) breadcrumbs.removeLast();
    return currentView;
  }

  String? goForward() {
    if (!canGoForward()) return null;
    _historyIndex++;
    currentView = history[_historyIndex];
    return currentView;
  }

  void reset() {
    currentView = 'chat';
    history
      ..clear()
      ..add('chat');
    breadcrumbs
      ..clear()
      ..add('Home');
    _historyIndex = 0;
  }
}

// ---------------------------------------------------------------------------
// EditorState
// ---------------------------------------------------------------------------

class EditorState {
  bool vimModeEnabled;
  String keybindingScheme; // 'default', 'vim', 'emacs'
  int tabSize;
  bool useSoftTabs;
  bool wordWrap;
  bool lineNumbers;
  bool minimap;
  String theme;
  double fontSize;
  String fontFamily;
  bool bracketMatching;
  bool autoIndent;
  bool highlightCurrentLine;
  final Map<String, String> customKeybindings;

  EditorState({
    this.vimModeEnabled = false,
    this.keybindingScheme = 'default',
    this.tabSize = 2,
    this.useSoftTabs = true,
    this.wordWrap = true,
    this.lineNumbers = true,
    this.minimap = false,
    this.theme = 'dark',
    this.fontSize = 14.0,
    this.fontFamily = 'JetBrains Mono',
    this.bracketMatching = true,
    this.autoIndent = true,
    this.highlightCurrentLine = true,
    Map<String, String>? customKeybindings,
  }) : customKeybindings = customKeybindings ?? {};

  void setKeybinding(String key, String action) {
    customKeybindings[key] = action;
  }

  String? getAction(String key) => customKeybindings[key];

  Map<String, dynamic> toJson() => {
    'vimModeEnabled': vimModeEnabled,
    'keybindingScheme': keybindingScheme,
    'tabSize': tabSize,
    'useSoftTabs': useSoftTabs,
    'wordWrap': wordWrap,
    'lineNumbers': lineNumbers,
    'minimap': minimap,
    'theme': theme,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'bracketMatching': bracketMatching,
    'autoIndent': autoIndent,
    'highlightCurrentLine': highlightCurrentLine,
    'customKeybindings': customKeybindings,
  };

  factory EditorState.fromJson(Map<String, dynamic> json) => EditorState(
    vimModeEnabled: json['vimModeEnabled'] as bool? ?? false,
    keybindingScheme: json['keybindingScheme'] as String? ?? 'default',
    tabSize: json['tabSize'] as int? ?? 2,
    useSoftTabs: json['useSoftTabs'] as bool? ?? true,
    wordWrap: json['wordWrap'] as bool? ?? true,
    lineNumbers: json['lineNumbers'] as bool? ?? true,
    minimap: json['minimap'] as bool? ?? false,
    theme: json['theme'] as String? ?? 'dark',
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14.0,
    fontFamily: json['fontFamily'] as String? ?? 'JetBrains Mono',
    bracketMatching: json['bracketMatching'] as bool? ?? true,
    autoIndent: json['autoIndent'] as bool? ?? true,
    highlightCurrentLine: json['highlightCurrentLine'] as bool? ?? true,
    customKeybindings:
        (json['customKeybindings'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
  );
}

// ---------------------------------------------------------------------------
// ConnectionState — API & MCP connection status
// ---------------------------------------------------------------------------

class AppConnectionState {
  ConnectionStatus apiStatus;
  String? apiError;
  final Map<String, McpServerState> mcpServers;
  final Map<String, IdeConnection> ideConnections;

  AppConnectionState({
    this.apiStatus = ConnectionStatus.disconnected,
    this.apiError,
    Map<String, McpServerState>? mcpServers,
    Map<String, IdeConnection>? ideConnections,
  }) : mcpServers = mcpServers ?? {},
       ideConnections = ideConnections ?? {};

  void setApiStatus(ConnectionStatus status, {String? error}) {
    apiStatus = status;
    apiError = error;
  }

  void addMcpServer(String name, McpServerState server) {
    mcpServers[name] = server;
  }

  void removeMcpServer(String name) {
    mcpServers.remove(name);
  }

  McpServerState? getMcpServer(String name) => mcpServers[name];

  void addIdeConnection(String name, IdeConnection connection) {
    ideConnections[name] = connection;
  }

  void removeIdeConnection(String name) {
    ideConnections.remove(name);
  }

  List<String> get connectedMcpServers => mcpServers.entries
      .where((e) => e.value.status == ConnectionStatus.connected)
      .map((e) => e.key)
      .toList();

  List<String> get connectedIdes => ideConnections.entries
      .where((e) => e.value.status == ConnectionStatus.connected)
      .map((e) => e.key)
      .toList();
}

class McpServerState {
  final String name;
  final String uri;
  ConnectionStatus status;
  String? error;
  final List<String> tools;
  final List<String> resources;
  DateTime? connectedAt;

  McpServerState({
    required this.name,
    required this.uri,
    this.status = ConnectionStatus.disconnected,
    this.error,
    List<String>? tools,
    List<String>? resources,
    this.connectedAt,
  }) : tools = tools ?? [],
       resources = resources ?? [];

  void setConnected(
    List<String> availableTools,
    List<String> availableResources,
  ) {
    status = ConnectionStatus.connected;
    error = null;
    tools
      ..clear()
      ..addAll(availableTools);
    resources
      ..clear()
      ..addAll(availableResources);
    connectedAt = DateTime.now();
  }

  void setDisconnected({String? reason}) {
    status = ConnectionStatus.disconnected;
    error = reason;
    tools.clear();
    resources.clear();
    connectedAt = null;
  }

  void setError(String message) {
    status = ConnectionStatus.error;
    error = message;
  }
}

class IdeConnection {
  final String name;
  final String type; // 'vscode', 'jetbrains', 'neovim', etc.
  ConnectionStatus status;
  String? workspacePath;
  int? pid;

  IdeConnection({
    required this.name,
    required this.type,
    this.status = ConnectionStatus.disconnected,
    this.workspacePath,
    this.pid,
  });
}

// ---------------------------------------------------------------------------
// StateSnapshot — serializable snapshot for session persistence
// ---------------------------------------------------------------------------

class StateSnapshot {
  final DateTime timestamp;
  final Map<String, dynamic> session;
  final Map<String, dynamic> editor;
  final String currentView;
  final Map<String, dynamic> featureFlags;
  final String? workingDirectory;
  final String? model;
  final String? provider;
  final String permissionMode;

  const StateSnapshot({
    required this.timestamp,
    required this.session,
    required this.editor,
    required this.currentView,
    required this.featureFlags,
    this.workingDirectory,
    this.model,
    this.provider,
    required this.permissionMode,
  });

  Map<String, dynamic> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'session': session,
    'editor': editor,
    'currentView': currentView,
    'featureFlags': featureFlags,
    'workingDirectory': workingDirectory,
    'model': model,
    'provider': provider,
    'permissionMode': permissionMode,
  };

  factory StateSnapshot.fromJson(Map<String, dynamic> json) => StateSnapshot(
    timestamp: DateTime.parse(json['timestamp'] as String),
    session: json['session'] as Map<String, dynamic>? ?? {},
    editor: json['editor'] as Map<String, dynamic>? ?? {},
    currentView: json['currentView'] as String? ?? 'chat',
    featureFlags: json['featureFlags'] as Map<String, dynamic>? ?? {},
    workingDirectory: json['workingDirectory'] as String?,
    model: json['model'] as String?,
    provider: json['provider'] as String?,
    permissionMode: json['permissionMode'] as String? ?? 'ask',
  );
}

// ---------------------------------------------------------------------------
// AppStateManager — the main orchestrator
// ---------------------------------------------------------------------------

class AppStateManager {
  // Sub-states
  SessionState? _session;
  final NavigationState navigation = NavigationState();
  final EditorState editor;
  final AppConnectionState connection = AppConnectionState();

  // Top-level state
  String? _activeModel;
  String? _activeProvider;
  PermissionMode _permissionMode;
  final List<String> _workingDirectories;
  final Set<String> _activeAgents;
  final Set<String> _activeTasks;
  final Map<String, bool> _featureFlags;
  bool _telemetryEnabled;
  final Map<String, dynamic> _telemetryState;

  // Event stream
  final StreamController<StateEvent> _eventController =
      StreamController<StateEvent>.broadcast();

  AppStateManager({
    EditorState? editor,
    String? model,
    String? provider,
    PermissionMode permissionMode = PermissionMode.ask,
    List<String>? workingDirectories,
    Map<String, bool>? featureFlags,
    bool telemetryEnabled = false,
  }) : editor = editor ?? EditorState(),
       _activeModel = model,
       _activeProvider = provider,
       _permissionMode = permissionMode,
       _workingDirectories = workingDirectories ?? [],
       _activeAgents = {},
       _activeTasks = {},
       _featureFlags = featureFlags ?? {},
       _telemetryEnabled = telemetryEnabled,
       _telemetryState = {};

  // -- Accessors ------------------------------------------------------------

  Stream<StateEvent> get events => _eventController.stream;
  SessionState? get session => _session;
  String? get activeModel => _activeModel;
  String? get activeProvider => _activeProvider;
  PermissionMode get permissionMode => _permissionMode;
  List<String> get workingDirectories => List.unmodifiable(_workingDirectories);
  String? get primaryWorkingDirectory =>
      _workingDirectories.isNotEmpty ? _workingDirectories.first : null;
  Set<String> get activeAgents => Set.unmodifiable(_activeAgents);
  Set<String> get activeTasks => Set.unmodifiable(_activeTasks);
  bool get telemetryEnabled => _telemetryEnabled;
  Map<String, bool> get featureFlags => Map.unmodifiable(_featureFlags);

  // -- Session management ---------------------------------------------------

  SessionState startSession({String? model, String? provider}) {
    final id = 'session_${DateTime.now().millisecondsSinceEpoch}';
    _session = SessionState(
      id: id,
      activeModel: model ?? _activeModel,
      activeProvider: provider ?? _activeProvider,
    );
    _eventController.add(SessionStarted(id));
    return _session!;
  }

  void endSession({String reason = 'user'}) {
    if (_session != null) {
      final id = _session!.id;
      _session = null;
      _eventController.add(SessionEnded(id, reason: reason));
    }
  }

  // -- Model / Provider -----------------------------------------------------

  void setModel(String model) {
    final prev = _activeModel ?? '';
    _activeModel = model;
    _session?.activeModel = model;
    _eventController.add(ModelChanged(previousModel: prev, newModel: model));
  }

  void setProvider(String provider) {
    final prev = _activeProvider ?? '';
    _activeProvider = provider;
    _session?.activeProvider = provider;
    _eventController.add(
      ProviderChanged(previousProvider: prev, newProvider: provider),
    );
  }

  // -- Permission mode ------------------------------------------------------

  void setPermissionMode(PermissionMode mode) {
    final prev = _permissionMode;
    _permissionMode = mode;
    _eventController.add(
      PermissionModeChanged(previousMode: prev, newMode: mode),
    );
  }

  // -- Working directories --------------------------------------------------

  void addWorkingDirectory(String path) {
    if (!_workingDirectories.contains(path)) {
      _workingDirectories.add(path);
      _eventController.add(
        WorkingDirectoryChanged(
          previousDir: _workingDirectories.length > 1
              ? _workingDirectories[_workingDirectories.length - 2]
              : '',
          newDir: path,
        ),
      );
    }
  }

  void removeWorkingDirectory(String path) {
    _workingDirectories.remove(path);
  }

  void setPrimaryWorkingDirectory(String path) {
    _workingDirectories.remove(path);
    _workingDirectories.insert(0, path);
  }

  // -- Agents & Tasks -------------------------------------------------------

  void registerAgent(String agentId) => _activeAgents.add(agentId);
  void unregisterAgent(String agentId) => _activeAgents.remove(agentId);
  void registerTask(String taskId) => _activeTasks.add(taskId);
  void unregisterTask(String taskId) => _activeTasks.remove(taskId);

  // -- Feature flags --------------------------------------------------------

  bool isFeatureEnabled(String flag) => _featureFlags[flag] ?? false;

  void setFeatureFlag(String flag, bool enabled) {
    _featureFlags[flag] = enabled;
    _eventController.add(FeatureFlagChanged(flag: flag, enabled: enabled));
  }

  void setFeatureFlags(Map<String, bool> flags) {
    for (final entry in flags.entries) {
      setFeatureFlag(entry.key, entry.value);
    }
  }

  // -- Telemetry ------------------------------------------------------------

  void setTelemetryEnabled(bool enabled) => _telemetryEnabled = enabled;

  void updateTelemetryState(String key, dynamic value) {
    _telemetryState[key] = value;
  }

  dynamic getTelemetryState(String key) => _telemetryState[key];

  // -- MCP Servers ----------------------------------------------------------

  void connectMcpServer(
    String name,
    String uri, {
    List<String>? tools,
    List<String>? resources,
  }) {
    final server = McpServerState(name: name, uri: uri);
    server.setConnected(tools ?? [], resources ?? []);
    connection.addMcpServer(name, server);
    _eventController.add(McpServerConnected(name));
  }

  void disconnectMcpServer(String name, {String reason = ''}) {
    connection.getMcpServer(name)?.setDisconnected(reason: reason);
    _eventController.add(McpServerDisconnected(name, reason: reason));
  }

  // -- IDE connections ------------------------------------------------------

  void connectIde(String name, String type, {String? workspacePath, int? pid}) {
    connection.addIdeConnection(
      name,
      IdeConnection(
        name: name,
        type: type,
        status: ConnectionStatus.connected,
        workspacePath: workspacePath,
        pid: pid,
      ),
    );
  }

  void disconnectIde(String name) {
    connection.removeIdeConnection(name);
  }

  // -- Snapshots ------------------------------------------------------------

  StateSnapshot createSnapshot() => StateSnapshot(
    timestamp: DateTime.now(),
    session: _session?.toJson() ?? {},
    editor: editor.toJson(),
    currentView: navigation.currentView,
    featureFlags: _featureFlags.map((k, v) => MapEntry(k, v)),
    workingDirectory: primaryWorkingDirectory,
    model: _activeModel,
    provider: _activeProvider,
    permissionMode: _permissionMode.name,
  );

  void restoreFromSnapshot(StateSnapshot snapshot) {
    if (snapshot.session.isNotEmpty) {
      _session = SessionState.fromJson(snapshot.session);
    }
    navigation.navigateTo(snapshot.currentView);
    if (snapshot.model != null) _activeModel = snapshot.model;
    if (snapshot.provider != null) _activeProvider = snapshot.provider;
    _permissionMode = PermissionMode.values.firstWhere(
      (m) => m.name == snapshot.permissionMode,
      orElse: () => PermissionMode.ask,
    );
    if (snapshot.workingDirectory != null) {
      addWorkingDirectory(snapshot.workingDirectory!);
    }
    for (final entry in snapshot.featureFlags.entries) {
      _featureFlags[entry.key] = entry.value as bool;
    }
  }

  // -- Reactive helpers -----------------------------------------------------

  /// Listen for events of a specific type.
  Stream<T> on<T extends StateEvent>() =>
      _eventController.stream.where((e) => e is T).cast<T>();

  // -- Cleanup --------------------------------------------------------------

  void dispose() {
    _eventController.close();
  }
}
