// JetBrains bridge — port of Neomage's JetBrains plugin bridge.
// Provides typed APIs for interacting with JetBrains IDE features:
// editor, project, inspections, refactoring, VCS, and events.

import 'dart:async';

import 'bridge_protocol.dart';

// ---------------------------------------------------------------------------
// JetBrains IDE type
// ---------------------------------------------------------------------------

/// Supported JetBrains IDE products.
enum JetbrainsIdeType {
  intellij('IntelliJ IDEA', 'idea'),
  webstorm('WebStorm', 'webstorm'),
  pycharm('PyCharm', 'pycharm'),
  goland('GoLand', 'goland'),
  rider('Rider', 'rider'),
  clion('CLion', 'clion'),
  phpstorm('PhpStorm', 'phpstorm'),
  rubymine('RubyMine', 'rubymine'),
  androidStudio('Android Studio', 'studio');

  const JetbrainsIdeType(this.displayName, this.productCode);

  /// Human-readable product name.
  final String displayName;

  /// Short product code used in paths and configs.
  final String productCode;

  /// Parse from a product code or display name.
  static JetbrainsIdeType fromString(String s) {
    final lower = s.toLowerCase();
    for (final ide in values) {
      if (ide.productCode == lower || ide.displayName.toLowerCase() == lower) {
        return ide;
      }
    }
    // Fallback heuristics.
    if (lower.contains('intellij') || lower.contains('idea')) {
      return intellij;
    }
    if (lower.contains('android')) return androidStudio;
    if (lower.contains('pycharm')) return pycharm;
    if (lower.contains('webstorm')) return webstorm;
    return intellij;
  }
}

// ---------------------------------------------------------------------------
// JetBrains project structures
// ---------------------------------------------------------------------------

/// A JetBrains project module.
class JetbrainsModule {
  final String name;
  final String path;
  final String? type;
  final List<String> sourceRoots;
  final List<String> testRoots;
  final List<String> resourceRoots;
  final List<JetbrainsDependency> dependencies;

  const JetbrainsModule({
    required this.name,
    required this.path,
    this.type,
    this.sourceRoots = const [],
    this.testRoots = const [],
    this.resourceRoots = const [],
    this.dependencies = const [],
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    if (type != null) 'type': type,
    'sourceRoots': sourceRoots,
    'testRoots': testRoots,
    'resourceRoots': resourceRoots,
    'dependencies': dependencies.map((d) => d.toJson()).toList(),
  };

  factory JetbrainsModule.fromJson(Map<String, dynamic> json) =>
      JetbrainsModule(
        name: json['name'] as String,
        path: json['path'] as String,
        type: json['type'] as String?,
        sourceRoots:
            (json['sourceRoots'] as List<dynamic>?)?.cast<String>() ?? [],
        testRoots: (json['testRoots'] as List<dynamic>?)?.cast<String>() ?? [],
        resourceRoots:
            (json['resourceRoots'] as List<dynamic>?)?.cast<String>() ?? [],
        dependencies:
            (json['dependencies'] as List<dynamic>?)
                ?.map(
                  (d) =>
                      JetbrainsDependency.fromJson(d as Map<String, dynamic>),
                )
                .toList() ??
            [],
      );
}

/// A module dependency.
class JetbrainsDependency {
  final String name;
  final String? version;
  final String scope;

  const JetbrainsDependency({
    required this.name,
    this.version,
    this.scope = 'compile',
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    if (version != null) 'version': version,
    'scope': scope,
  };

  factory JetbrainsDependency.fromJson(Map<String, dynamic> json) =>
      JetbrainsDependency(
        name: json['name'] as String,
        version: json['version'] as String?,
        scope: json['scope'] as String? ?? 'compile',
      );
}

/// A run/debug configuration.
class JetbrainsRunConfiguration {
  final String name;
  final String type;
  final String? mainClass;
  final String? module;
  final String? workingDirectory;
  final List<String> programArgs;
  final Map<String, String> envVars;

  const JetbrainsRunConfiguration({
    required this.name,
    required this.type,
    this.mainClass,
    this.module,
    this.workingDirectory,
    this.programArgs = const [],
    this.envVars = const {},
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    if (mainClass != null) 'mainClass': mainClass,
    if (module != null) 'module': module,
    if (workingDirectory != null) 'workingDirectory': workingDirectory,
    'programArgs': programArgs,
    'envVars': envVars,
  };

  factory JetbrainsRunConfiguration.fromJson(Map<String, dynamic> json) =>
      JetbrainsRunConfiguration(
        name: json['name'] as String,
        type: json['type'] as String,
        mainClass: json['mainClass'] as String?,
        module: json['module'] as String?,
        workingDirectory: json['workingDirectory'] as String?,
        programArgs:
            (json['programArgs'] as List<dynamic>?)?.cast<String>() ?? [],
        envVars:
            (json['envVars'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(k, v.toString()),
            ) ??
            {},
      );
}

// ---------------------------------------------------------------------------
// Inspection result
// ---------------------------------------------------------------------------

/// Result from a JetBrains inspection run.
class JetbrainsInspectionResult {
  final String inspectionName;
  final String severity;
  final String description;
  final String filePath;
  final int line;
  final int column;
  final String? quickFixDescription;

  const JetbrainsInspectionResult({
    required this.inspectionName,
    required this.severity,
    required this.description,
    required this.filePath,
    required this.line,
    this.column = 0,
    this.quickFixDescription,
  });

  Map<String, dynamic> toJson() => {
    'inspectionName': inspectionName,
    'severity': severity,
    'description': description,
    'filePath': filePath,
    'line': line,
    'column': column,
    if (quickFixDescription != null) 'quickFixDescription': quickFixDescription,
  };

  factory JetbrainsInspectionResult.fromJson(Map<String, dynamic> json) =>
      JetbrainsInspectionResult(
        inspectionName: json['inspectionName'] as String,
        severity: json['severity'] as String,
        description: json['description'] as String,
        filePath: json['filePath'] as String,
        line: json['line'] as int,
        column: json['column'] as int? ?? 0,
        quickFixDescription: json['quickFixDescription'] as String?,
      );
}

// ---------------------------------------------------------------------------
// VCS types
// ---------------------------------------------------------------------------

/// VCS file status.
enum JetbrainsVcsStatus {
  unmodified('unmodified'),
  modified('modified'),
  added('added'),
  deleted('deleted'),
  renamed('renamed'),
  copied('copied'),
  untracked('untracked'),
  ignored('ignored'),
  conflicting('conflicting');

  const JetbrainsVcsStatus(this.value);
  final String value;

  static JetbrainsVcsStatus fromValue(String v) {
    for (final s in values) {
      if (s.value == v) return s;
    }
    return unmodified;
  }
}

/// VCS status of a single file.
class JetbrainsVcsFileStatus {
  final String filePath;
  final JetbrainsVcsStatus status;
  final String? originalPath;

  const JetbrainsVcsFileStatus({
    required this.filePath,
    required this.status,
    this.originalPath,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'status': status.value,
    if (originalPath != null) 'originalPath': originalPath,
  };

  factory JetbrainsVcsFileStatus.fromJson(Map<String, dynamic> json) =>
      JetbrainsVcsFileStatus(
        filePath: json['filePath'] as String,
        status: JetbrainsVcsStatus.fromValue(json['status'] as String),
        originalPath: json['originalPath'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Action
// ---------------------------------------------------------------------------

/// A registered JetBrains action (similar to VS Code commands).
class JetbrainsAction {
  final String id;
  final String text;
  final String? description;
  final String? shortcut;
  final Future<dynamic> Function(Map<String, dynamic>? context) handler;

  JetbrainsAction({
    required this.id,
    required this.text,
    this.description,
    this.shortcut,
    required this.handler,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (description != null) 'description': description,
    if (shortcut != null) 'shortcut': shortcut,
  };
}

// ---------------------------------------------------------------------------
// JetbrainsBridge
// ---------------------------------------------------------------------------

/// High-level bridge to a JetBrains IDE plugin.
///
/// Wraps [BridgeProtocol] with typed methods for all JetBrains interactions:
/// editor, project, inspections, refactoring, VCS, actions, and events.
class JetbrainsBridge {
  final BridgeProtocol _protocol;
  final Map<String, JetbrainsAction> _actions = {};

  JetbrainsIdeType? _ideType;
  String? _projectPath;
  bool _connected = false;

  // Event controllers
  final StreamController<String> _onFileEdited = StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _onBuildCompleted =
      StreamController.broadcast();
  final StreamController<List<JetbrainsInspectionResult>>
  _onInspectionCompleted = StreamController.broadcast();
  final StreamController<JetbrainsVcsFileStatus> _onVcsFileChanged =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _onRunConfigurationFinished =
      StreamController.broadcast();

  JetbrainsBridge({BridgeProtocol? protocol})
    : _protocol = protocol ?? BridgeProtocol() {
    _registerNotificationHandlers();
  }

  // ---- State ----

  bool get isConnected => _connected;
  String? get projectPath => _projectPath;
  JetbrainsIdeType? get ideType => _ideType;
  BridgeProtocol get protocol => _protocol;

  // ---- Event streams ----

  /// Fires when a file is edited. Emits the file path.
  Stream<String> get onFileEdited => _onFileEdited.stream;

  /// Fires when a build completes. Emits build result info.
  Stream<Map<String, dynamic>> get onBuildCompleted => _onBuildCompleted.stream;

  /// Fires when an inspection run completes.
  Stream<List<JetbrainsInspectionResult>> get onInspectionCompleted =>
      _onInspectionCompleted.stream;

  /// Fires when a VCS file status changes.
  Stream<JetbrainsVcsFileStatus> get onVcsFileChanged =>
      _onVcsFileChanged.stream;

  /// Fires when a run configuration finishes.
  Stream<Map<String, dynamic>> get onRunConfigurationFinished =>
      _onRunConfigurationFinished.stream;

  // ---- Connection ----

  /// Connect to a JetBrains IDE plugin for the given project.
  Future<void> connect(String projectPath, {JetbrainsIdeType? ideType}) async {
    _projectPath = projectPath;
    _ideType = ideType;

    final handshake = BridgeHandshake(
      clientName: 'neomage',
      clientVersion: BridgeProtocolVersion.current,
      capabilities: {
        BridgeCapability.fileEdit,
        BridgeCapability.diagnostics,
        BridgeCapability.completion,
        BridgeCapability.definition,
        BridgeCapability.references,
        BridgeCapability.rename,
        BridgeCapability.codeActions,
        BridgeCapability.formatting,
        BridgeCapability.terminal,
        BridgeCapability.debug,
        BridgeCapability.git,
        BridgeCapability.notifications,
        BridgeCapability.chat,
      },
      workspacePaths: [projectPath],
      pid: 0,
      extensions: {if (ideType != null) 'ideType': ideType.productCode},
    );

    final response = await _protocol.initialize(handshake);
    if (response.isError) {
      throw response.error!;
    }

    // Detect IDE type from server response if not provided.
    if (_ideType == null &&
        response.result is Map<String, dynamic> &&
        (response.result as Map<String, dynamic>).containsKey('ideType')) {
      _ideType = JetbrainsIdeType.fromString(
        (response.result as Map<String, dynamic>)['ideType'] as String,
      );
    }

    _connected = true;
  }

  // ---- Editor operations ----

  /// Open a file in the editor.
  Future<BridgeResponse> openFile(
    String filePath, {
    int? line,
    int? column,
    bool focusEditor = true,
  }) {
    return _protocol.sendRequest('jetbrains/openFile', {
      'filePath': filePath,
      'line': ?line,
      'column': ?column,
      'focusEditor': focusEditor,
    });
  }

  /// Close a file tab.
  Future<BridgeResponse> closeFile(String filePath) {
    return _protocol.sendRequest('jetbrains/closeFile', {'filePath': filePath});
  }

  /// Get the active editor file path.
  Future<String?> getActiveFile() async {
    final resp = await _protocol.sendRequest('jetbrains/getActiveFile', null);
    if (resp.isSuccess) return resp.result as String?;
    return null;
  }

  /// Get all open file paths.
  Future<List<String>> getOpenFiles() async {
    final resp = await _protocol.sendRequest('jetbrains/getOpenFiles', null);
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List).cast<String>();
    }
    return [];
  }

  /// Get the current selection text and range.
  Future<Map<String, dynamic>?> getSelection() async {
    final resp = await _protocol.sendRequest('jetbrains/getSelection', null);
    if (resp.isSuccess && resp.result is Map<String, dynamic>) {
      return resp.result as Map<String, dynamic>;
    }
    return null;
  }

  /// Insert text at the current caret position.
  Future<BridgeResponse> insertText(String text) {
    return _protocol.sendRequest('jetbrains/insertText', {'text': text});
  }

  /// Replace a range of text in the active editor.
  Future<BridgeResponse> replaceRange({
    required int startOffset,
    required int endOffset,
    required String newText,
  }) {
    return _protocol.sendRequest('jetbrains/replaceRange', {
      'startOffset': startOffset,
      'endOffset': endOffset,
      'text': newText,
    });
  }

  /// Navigate to a symbol by fully qualified name.
  Future<BridgeResponse> navigateToSymbol(String qualifiedName) {
    return _protocol.sendRequest('jetbrains/navigateToSymbol', {
      'qualifiedName': qualifiedName,
    });
  }

  /// Find usages of a symbol at the current caret position.
  Future<List<Map<String, dynamic>>> findUsages({
    String? filePath,
    int? offset,
  }) async {
    final resp = await _protocol.sendRequest('jetbrains/findUsages', {
      'filePath': ?filePath,
      'offset': ?offset,
    });
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List).cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ---- Project ----

  /// Get the project file/directory structure.
  Future<Map<String, dynamic>> getProjectStructure() async {
    final resp = await _protocol.sendRequest(
      'jetbrains/getProjectStructure',
      null,
    );
    if (resp.isSuccess && resp.result is Map<String, dynamic>) {
      return resp.result as Map<String, dynamic>;
    }
    return {};
  }

  /// Get project modules.
  Future<List<JetbrainsModule>> getModules() async {
    final resp = await _protocol.sendRequest('jetbrains/getModules', null);
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map((m) => JetbrainsModule.fromJson(m as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Get available run/debug configurations.
  Future<List<JetbrainsRunConfiguration>> getRunConfigurations() async {
    final resp = await _protocol.sendRequest(
      'jetbrains/getRunConfigurations',
      null,
    );
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map(
            (c) =>
                JetbrainsRunConfiguration.fromJson(c as Map<String, dynamic>),
          )
          .toList();
    }
    return [];
  }

  /// Run a named run/debug configuration.
  Future<BridgeResponse> runConfiguration(String name, {bool debug = false}) {
    return _protocol.sendRequest('jetbrains/runConfiguration', {
      'name': name,
      'debug': debug,
    });
  }

  // ---- Inspections ----

  /// Run a specific inspection on a file or scope.
  Future<List<JetbrainsInspectionResult>> runInspection({
    required String inspectionId,
    String? filePath,
    String? scope,
  }) async {
    final resp = await _protocol.sendRequest('jetbrains/runInspection', {
      'inspectionId': inspectionId,
      'filePath': ?filePath,
      'scope': ?scope,
    });
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map(
            (r) =>
                JetbrainsInspectionResult.fromJson(r as Map<String, dynamic>),
          )
          .toList();
    }
    return [];
  }

  /// Get available inspection profiles.
  Future<List<String>> getInspectionProfiles() async {
    final resp = await _protocol.sendRequest(
      'jetbrains/getInspectionProfiles',
      null,
    );
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List).cast<String>();
    }
    return [];
  }

  /// Suppress an inspection at a specific location.
  Future<BridgeResponse> suppressInspection({
    required String inspectionId,
    required String filePath,
    required int line,
    String suppressionType = 'line',
  }) {
    return _protocol.sendRequest('jetbrains/suppressInspection', {
      'inspectionId': inspectionId,
      'filePath': filePath,
      'line': line,
      'suppressionType': suppressionType,
    });
  }

  // ---- Refactoring ----

  /// Rename a symbol at a given location.
  Future<BridgeResponse> rename({
    required String filePath,
    required int offset,
    required String newName,
  }) {
    return _protocol.sendRequest('jetbrains/rename', {
      'filePath': filePath,
      'offset': offset,
      'newName': newName,
    });
  }

  /// Extract a method from a selected range.
  Future<BridgeResponse> extractMethod({
    required String filePath,
    required int startOffset,
    required int endOffset,
    required String methodName,
    String visibility = 'private',
  }) {
    return _protocol.sendRequest('jetbrains/extractMethod', {
      'filePath': filePath,
      'startOffset': startOffset,
      'endOffset': endOffset,
      'methodName': methodName,
      'visibility': visibility,
    });
  }

  /// Inline a variable at the caret position.
  Future<BridgeResponse> inlineVariable({
    required String filePath,
    required int offset,
  }) {
    return _protocol.sendRequest('jetbrains/inlineVariable', {
      'filePath': filePath,
      'offset': offset,
    });
  }

  /// Move a file to a new location with refactoring.
  Future<BridgeResponse> moveFile({
    required String sourcePath,
    required String targetDirectory,
  }) {
    return _protocol.sendRequest('jetbrains/moveFile', {
      'sourcePath': sourcePath,
      'targetDirectory': targetDirectory,
    });
  }

  // ---- VCS ----

  /// Get VCS status for all changed files.
  Future<List<JetbrainsVcsFileStatus>> getVcsStatus() async {
    final resp = await _protocol.sendRequest('jetbrains/getVcsStatus', null);
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map(
            (s) => JetbrainsVcsFileStatus.fromJson(s as Map<String, dynamic>),
          )
          .toList();
    }
    return [];
  }

  /// Commit changes with a message.
  Future<BridgeResponse> commitChanges({
    required String message,
    List<String>? filePaths,
    bool amend = false,
  }) {
    return _protocol.sendRequest('jetbrains/commitChanges', {
      'message': message,
      'filePaths': ?filePaths,
      'amend': amend,
    });
  }

  /// Show diff for a file (or all changes if no path given).
  Future<BridgeResponse> showDiff({String? filePath}) {
    return _protocol.sendRequest('jetbrains/showDiff', {'filePath': ?filePath});
  }

  // ---- Actions ----

  /// Register an action that the IDE can invoke.
  void registerAction(JetbrainsAction action) {
    _actions[action.id] = action;
    _protocol.registerHandler('jetbrains/action/${action.id}', (
      method,
      params,
    ) async {
      final context = params is Map<String, dynamic> ? params : null;
      return await action.handler(context);
    });
    _protocol.sendNotification('jetbrains/registerAction', action.toJson());
  }

  /// Unregister an action.
  void unregisterAction(String actionId) {
    _actions.remove(actionId);
    _protocol.unregisterHandler('jetbrains/action/$actionId');
    _protocol.sendNotification('jetbrains/unregisterAction', {'id': actionId});
  }

  // ---- Internal notification handlers ----

  void _registerNotificationHandlers() {
    _protocol.registerNotificationHandler('jetbrains/fileEdited', (_, params) {
      if (params is Map && params.containsKey('filePath')) {
        _onFileEdited.add(params['filePath'] as String);
      }
    });

    _protocol.registerNotificationHandler('jetbrains/buildCompleted', (
      _,
      params,
    ) {
      if (params is Map<String, dynamic>) {
        _onBuildCompleted.add(params);
      }
    });

    _protocol.registerNotificationHandler('jetbrains/inspectionCompleted', (
      _,
      params,
    ) {
      if (params is Map && params.containsKey('results')) {
        final results = (params['results'] as List)
            .map(
              (r) =>
                  JetbrainsInspectionResult.fromJson(r as Map<String, dynamic>),
            )
            .toList();
        _onInspectionCompleted.add(results);
      }
    });

    _protocol.registerNotificationHandler('jetbrains/vcsFileChanged', (
      _,
      params,
    ) {
      if (params is Map<String, dynamic>) {
        _onVcsFileChanged.add(JetbrainsVcsFileStatus.fromJson(params));
      }
    });

    _protocol.registerNotificationHandler(
      'jetbrains/runConfigurationFinished',
      (_, params) {
        if (params is Map<String, dynamic>) {
          _onRunConfigurationFinished.add(params);
        }
      },
    );
  }

  // ---- Cleanup ----

  /// Disconnect from the JetBrains IDE.
  Future<void> disconnect() async {
    if (!_connected) return;
    try {
      await _protocol.shutdown();
      _protocol.exit();
    } catch (_) {
      // Best-effort shutdown.
    }
    _connected = false;
  }

  /// Dispose all resources.
  void dispose() {
    _onFileEdited.close();
    _onBuildCompleted.close();
    _onInspectionCompleted.close();
    _onVcsFileChanged.close();
    _onRunConfigurationFinished.close();
    _actions.clear();
    _protocol.dispose();
  }
}
