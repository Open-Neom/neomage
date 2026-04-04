// VS Code bridge — port of NeomClaw's VS Code extension bridge.
// Provides typed APIs for interacting with VS Code editor features,
// diagnostics, UI, terminals, and theme integration.

import 'dart:async';

import 'bridge_protocol.dart';

// ---------------------------------------------------------------------------
// VS Code theme
// ---------------------------------------------------------------------------

/// Represents a VS Code color theme, usable for syncing the NeomClaw UI
/// with the editor theme.
class VscodeTheme {
  final String name;
  final VscodeThemeKind kind;
  final Map<String, String> colors;
  // ignore: library_private_types_in_public_api
  final Map<String, _TokenColor> tokenColors;

  VscodeTheme({
    required this.name,
    required this.kind,
    this.colors = const {},
    this.tokenColors = const {},
  });

  // ---- Convenience color accessors ----

  String? get editorBackground => colors['editor.background'];
  String? get editorForeground => colors['editor.foreground'];
  String? get sideBarBackground => colors['sideBar.background'];
  String? get sideBarForeground => colors['sideBar.foreground'];
  String? get activityBarBackground => colors['activityBar.background'];
  String? get statusBarBackground => colors['statusBar.background'];
  String? get statusBarForeground => colors['statusBar.foreground'];
  String? get titleBarBackground => colors['titleBar.activeBackground'];
  String? get inputBackground => colors['input.background'];
  String? get inputForeground => colors['input.foreground'];
  String? get inputBorder => colors['input.border'];
  String? get buttonBackground => colors['button.background'];
  String? get buttonForeground => colors['button.foreground'];
  String? get errorForeground => colors['errorForeground'];
  String? get focusBorder => colors['focusBorder'];
  String? get selectionBackground => colors['editor.selectionBackground'];
  String? get lineHighlightBackground =>
      colors['editor.lineHighlightBackground'];
  String? get panelBackground => colors['panel.background'];
  String? get panelBorder => colors['panel.border'];
  String? get tabActiveBackground => colors['tab.activeBackground'];
  String? get tabInactiveBackground => colors['tab.inactiveBackground'];
  String? get terminalBackground => colors['terminal.background'];
  String? get terminalForeground => colors['terminal.foreground'];

  /// Whether this is a dark theme.
  bool get isDark =>
      kind == VscodeThemeKind.dark || kind == VscodeThemeKind.highContrastDark;

  /// Whether this is a high-contrast theme.
  bool get isHighContrast =>
      kind == VscodeThemeKind.highContrastLight ||
      kind == VscodeThemeKind.highContrastDark;

  /// Parse a CSS hex color string (#RRGGBB or #RRGGBBAA) to an int.
  static int? parseHexColor(String? hex) {
    if (hex == null || !hex.startsWith('#')) return null;
    final clean = hex.substring(1);
    if (clean.length == 6) {
      return int.tryParse('FF$clean', radix: 16);
    } else if (clean.length == 8) {
      // RRGGBBAA -> AARRGGBB
      final aa = clean.substring(6, 8);
      final rrggbb = clean.substring(0, 6);
      return int.tryParse('$aa$rrggbb', radix: 16);
    }
    return null;
  }

  /// Convert this theme to a map of color values (int ARGB).
  Map<String, int> toColorMap() {
    final result = <String, int>{};
    for (final entry in colors.entries) {
      final parsed = parseHexColor(entry.value);
      if (parsed != null) result[entry.key] = parsed;
    }
    return result;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'kind': kind.index,
    'colors': colors,
    'tokenColors': tokenColors.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory VscodeTheme.fromJson(Map<String, dynamic> json) => VscodeTheme(
    name: json['name'] as String? ?? 'Unknown',
    kind: VscodeThemeKind.fromIndex(json['kind'] as int? ?? 1),
    colors:
        (json['colors'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ) ??
        {},
    tokenColors:
        (json['tokenColors'] as Map<String, dynamic>?)?.map(
          (k, v) =>
              MapEntry(k, _TokenColor.fromJson(v as Map<String, dynamic>)),
        ) ??
        {},
  );
}

/// VS Code theme kind.
enum VscodeThemeKind {
  light,
  dark,
  highContrastLight,
  highContrastDark;

  static VscodeThemeKind fromIndex(int index) => switch (index) {
    0 => light,
    1 => dark,
    2 => highContrastLight,
    3 => highContrastDark,
    _ => dark,
  };
}

class _TokenColor {
  final String? foreground;
  final String? background;
  final String? fontStyle;

  const _TokenColor({this.foreground, this.background, this.fontStyle});

  Map<String, dynamic> toJson() => {
    if (foreground != null) 'foreground': foreground,
    if (background != null) 'background': background,
    if (fontStyle != null) 'fontStyle': fontStyle,
  };

  factory _TokenColor.fromJson(Map<String, dynamic> json) => _TokenColor(
    foreground: json['foreground'] as String?,
    background: json['background'] as String?,
    fontStyle: json['fontStyle'] as String?,
  );
}

// ---------------------------------------------------------------------------
// VS Code command
// ---------------------------------------------------------------------------

/// A registered VS Code command.
class VscodeCommand {
  final String id;
  final String title;
  final String? keybinding;
  final String? category;
  final Future<dynamic> Function(List<dynamic>? args) handler;

  VscodeCommand({
    required this.id,
    required this.title,
    this.keybinding,
    this.category,
    required this.handler,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    if (keybinding != null) 'keybinding': keybinding,
    if (category != null) 'category': category,
  };
}

// ---------------------------------------------------------------------------
// Diagnostic types
// ---------------------------------------------------------------------------

/// VS Code diagnostic severity.
enum VscodeDiagnosticSeverity {
  error(0),
  warning(1),
  information(2),
  hint(3);

  const VscodeDiagnosticSeverity(this.value);
  final int value;

  static VscodeDiagnosticSeverity fromValue(int v) => switch (v) {
    0 => error,
    1 => warning,
    2 => information,
    3 => hint,
    _ => information,
  };
}

/// A single diagnostic entry.
class VscodeDiagnostic {
  final String uri;
  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;
  final String message;
  final VscodeDiagnosticSeverity severity;
  final String? source;
  final String? code;

  const VscodeDiagnostic({
    required this.uri,
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
    required this.message,
    this.severity = VscodeDiagnosticSeverity.error,
    this.source,
    this.code,
  });

  Map<String, dynamic> toJson() => {
    'uri': uri,
    'range': {
      'start': {'line': startLine, 'character': startCharacter},
      'end': {'line': endLine, 'character': endCharacter},
    },
    'message': message,
    'severity': severity.value,
    if (source != null) 'source': source,
    if (code != null) 'code': code,
  };

  factory VscodeDiagnostic.fromJson(Map<String, dynamic> json) {
    final range = json['range'] as Map<String, dynamic>;
    final start = range['start'] as Map<String, dynamic>;
    final end = range['end'] as Map<String, dynamic>;
    return VscodeDiagnostic(
      uri: json['uri'] as String,
      startLine: start['line'] as int,
      startCharacter: start['character'] as int,
      endLine: end['line'] as int,
      endCharacter: end['character'] as int,
      message: json['message'] as String,
      severity: VscodeDiagnosticSeverity.fromValue(
        json['severity'] as int? ?? 0,
      ),
      source: json['source'] as String?,
      code: json['code']?.toString(),
    );
  }
}

// ---------------------------------------------------------------------------
// Text selection / range
// ---------------------------------------------------------------------------

/// A text range (start/end position).
class VscodeRange {
  final int startLine;
  final int startCharacter;
  final int endLine;
  final int endCharacter;

  const VscodeRange({
    required this.startLine,
    required this.startCharacter,
    required this.endLine,
    required this.endCharacter,
  });

  bool get isEmpty => startLine == endLine && startCharacter == endCharacter;

  Map<String, dynamic> toJson() => {
    'start': {'line': startLine, 'character': startCharacter},
    'end': {'line': endLine, 'character': endCharacter},
  };

  factory VscodeRange.fromJson(Map<String, dynamic> json) {
    final start = json['start'] as Map<String, dynamic>;
    final end = json['end'] as Map<String, dynamic>;
    return VscodeRange(
      startLine: start['line'] as int,
      startCharacter: start['character'] as int,
      endLine: end['line'] as int,
      endCharacter: end['character'] as int,
    );
  }
}

/// A text selection with active/anchor positions.
class VscodeSelection extends VscodeRange {
  final int anchorLine;
  final int anchorCharacter;
  final int activeLine;
  final int activeCharacter;

  VscodeSelection({
    required this.anchorLine,
    required this.anchorCharacter,
    required this.activeLine,
    required this.activeCharacter,
  }) : super(
         startLine:
             anchorLine < activeLine ||
                 (anchorLine == activeLine &&
                     anchorCharacter <= activeCharacter)
             ? anchorLine
             : activeLine,
         startCharacter:
             anchorLine < activeLine ||
                 (anchorLine == activeLine &&
                     anchorCharacter <= activeCharacter)
             ? anchorCharacter
             : activeCharacter,
         endLine:
             anchorLine > activeLine ||
                 (anchorLine == activeLine && anchorCharacter > activeCharacter)
             ? anchorLine
             : activeLine,
         endCharacter:
             anchorLine > activeLine ||
                 (anchorLine == activeLine && anchorCharacter > activeCharacter)
             ? anchorCharacter
             : activeCharacter,
       );

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'anchor': {'line': anchorLine, 'character': anchorCharacter},
    'active': {'line': activeLine, 'character': activeCharacter},
  };

  factory VscodeSelection.fromJson(Map<String, dynamic> json) {
    final anchor = json['anchor'] as Map<String, dynamic>;
    final active = json['active'] as Map<String, dynamic>;
    return VscodeSelection(
      anchorLine: anchor['line'] as int,
      anchorCharacter: anchor['character'] as int,
      activeLine: active['line'] as int,
      activeCharacter: active['character'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// Status bar item
// ---------------------------------------------------------------------------

/// A VS Code status bar item configuration.
class VscodeStatusBarItem {
  final String id;
  final String text;
  final String? tooltip;
  final String? command;
  final int? priority;
  final VscodeStatusBarAlignment alignment;
  final String? color;
  final String? backgroundColor;

  const VscodeStatusBarItem({
    required this.id,
    required this.text,
    this.tooltip,
    this.command,
    this.priority,
    this.alignment = VscodeStatusBarAlignment.left,
    this.color,
    this.backgroundColor,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    if (tooltip != null) 'tooltip': tooltip,
    if (command != null) 'command': command,
    if (priority != null) 'priority': priority,
    'alignment': alignment.value,
    if (color != null) 'color': color,
    if (backgroundColor != null) 'backgroundColor': backgroundColor,
  };
}

enum VscodeStatusBarAlignment {
  left(1),
  right(2);

  const VscodeStatusBarAlignment(this.value);
  final int value;
}

// ---------------------------------------------------------------------------
// Quick pick item
// ---------------------------------------------------------------------------

/// A quick pick item for VS Code UI.
class VscodeQuickPickItem {
  final String label;
  final String? description;
  final String? detail;
  final bool picked;
  final String? value;

  const VscodeQuickPickItem({
    required this.label,
    this.description,
    this.detail,
    this.picked = false,
    this.value,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    if (description != null) 'description': description,
    if (detail != null) 'detail': detail,
    'picked': picked,
    if (value != null) 'value': value,
  };

  factory VscodeQuickPickItem.fromJson(Map<String, dynamic> json) =>
      VscodeQuickPickItem(
        label: json['label'] as String,
        description: json['description'] as String?,
        detail: json['detail'] as String?,
        picked: json['picked'] as bool? ?? false,
        value: json['value'] as String?,
      );
}

// ---------------------------------------------------------------------------
// VscodeBridge
// ---------------------------------------------------------------------------

/// High-level bridge to a VS Code extension host.
///
/// Wraps [BridgeProtocol] with typed methods for all VS Code interactions:
/// editor, diagnostics, UI, terminals, commands, and events.
class VscodeBridge {
  final BridgeProtocol _protocol;
  final Map<String, VscodeCommand> _commands = {};
  final Map<String, VscodeStatusBarItem> _statusBarItems = {};

  VscodeTheme? _currentTheme;
  String? _workspacePath;
  bool _connected = false;

  // Event controllers
  final StreamController<String> _onDidChangeActiveEditor =
      StreamController.broadcast();
  final StreamController<String> _onDidSaveDocument =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _onDidChangeConfiguration =
      StreamController.broadcast();
  final StreamController<VscodeTheme> _onDidChangeTheme =
      StreamController.broadcast();
  final StreamController<List<VscodeDiagnostic>> _onDidChangeDiagnostics =
      StreamController.broadcast();

  VscodeBridge({BridgeProtocol? protocol})
    : _protocol = protocol ?? BridgeProtocol() {
    _registerNotificationHandlers();
  }

  // ---- State ----

  bool get isConnected => _connected;
  String? get workspacePath => _workspacePath;
  VscodeTheme? get currentTheme => _currentTheme;
  BridgeProtocol get protocol => _protocol;

  // ---- Event streams ----

  /// Fires when the active editor changes. Emits the document URI.
  Stream<String> get onDidChangeActiveEditor => _onDidChangeActiveEditor.stream;

  /// Fires when a document is saved. Emits the document URI.
  Stream<String> get onDidSaveDocument => _onDidSaveDocument.stream;

  /// Fires when workspace configuration changes.
  Stream<Map<String, dynamic>> get onDidChangeConfiguration =>
      _onDidChangeConfiguration.stream;

  /// Fires when the color theme changes.
  Stream<VscodeTheme> get onDidChangeTheme => _onDidChangeTheme.stream;

  /// Fires when diagnostics change.
  Stream<List<VscodeDiagnostic>> get onDidChangeDiagnostics =>
      _onDidChangeDiagnostics.stream;

  // ---- Connection ----

  /// Connect to VS Code extension host for the given workspace.
  Future<void> connect(String workspacePath) async {
    _workspacePath = workspacePath;

    final handshake = BridgeHandshake(
      clientName: 'neom_claw',
      clientVersion: BridgeProtocolVersion.current,
      capabilities: {
        BridgeCapability.fileEdit,
        BridgeCapability.diagnostics,
        BridgeCapability.completion,
        BridgeCapability.hover,
        BridgeCapability.definition,
        BridgeCapability.references,
        BridgeCapability.formatting,
        BridgeCapability.terminal,
        BridgeCapability.notifications,
        BridgeCapability.chat,
        BridgeCapability.statusBar,
        BridgeCapability.codeActions,
      },
      workspacePaths: [workspacePath],
      pid: 0, // Dart does not expose pid easily; filled by caller if needed.
    );

    final response = await _protocol.initialize(handshake);
    if (response.isError) {
      throw response.error!;
    }

    // Request initial theme if available.
    if (_protocol.hasCapability(BridgeCapability.statusBar)) {
      _requestTheme();
    }

    _connected = true;
  }

  Future<void> _requestTheme() async {
    try {
      final resp = await _protocol.sendRequest('vscode/getTheme', null);
      if (resp.isSuccess && resp.result is Map<String, dynamic>) {
        _currentTheme = VscodeTheme.fromJson(
          resp.result as Map<String, dynamic>,
        );
        _onDidChangeTheme.add(_currentTheme!);
      }
    } catch (_) {
      // Theme request is best-effort.
    }
  }

  // ---- Editor operations ----

  /// Open a file in the editor.
  Future<BridgeResponse> openFile(
    String uri, {
    int? line,
    int? character,
    bool? preview,
  }) {
    return _protocol.sendRequest('vscode/openFile', {
      'uri': uri,
      'line': ?line,
      'character': ?character,
      'preview': ?preview,
    });
  }

  /// Close a file tab.
  Future<BridgeResponse> closeFile(String uri) {
    return _protocol.sendRequest('vscode/closeFile', {'uri': uri});
  }

  /// Get the active editor file URI.
  Future<String?> getActiveFile() async {
    final resp = await _protocol.sendRequest('vscode/getActiveFile', null);
    if (resp.isSuccess) return resp.result as String?;
    return null;
  }

  /// Get all currently open file URIs.
  Future<List<String>> getOpenFiles() async {
    final resp = await _protocol.sendRequest('vscode/getOpenFiles', null);
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List).cast<String>();
    }
    return [];
  }

  /// Get the current selection in the active editor.
  Future<VscodeSelection?> getSelection() async {
    final resp = await _protocol.sendRequest('vscode/getSelection', null);
    if (resp.isSuccess && resp.result is Map<String, dynamic>) {
      return VscodeSelection.fromJson(resp.result as Map<String, dynamic>);
    }
    return null;
  }

  /// Set the selection in the active editor.
  Future<BridgeResponse> setSelection(VscodeSelection selection) {
    return _protocol.sendRequest('vscode/setSelection', selection.toJson());
  }

  /// Insert text at the current cursor position.
  Future<BridgeResponse> insertText(String text) {
    return _protocol.sendRequest('vscode/insertText', {'text': text});
  }

  /// Replace a range in the active editor.
  Future<BridgeResponse> replaceRange(VscodeRange range, String newText) {
    return _protocol.sendRequest('vscode/replaceRange', {
      'range': range.toJson(),
      'text': newText,
    });
  }

  /// Apply a workspace edit (multi-file).
  Future<BridgeResponse> applyWorkspaceEdit(
    Map<String, dynamic> edit, {
    String? label,
  }) {
    return _protocol.workspaceApplyEdit(edit: edit, label: label);
  }

  // ---- Diagnostics ----

  /// Publish diagnostics for a URI.
  void publishDiagnostics(String uri, List<VscodeDiagnostic> diagnostics) {
    _protocol.sendNotification('vscode/publishDiagnostics', {
      'uri': uri,
      'diagnostics': diagnostics.map((d) => d.toJson()).toList(),
    });
  }

  /// Clear all diagnostics for a URI.
  void clearDiagnostics(String uri) {
    _protocol.sendNotification('vscode/publishDiagnostics', {
      'uri': uri,
      'diagnostics': [],
    });
  }

  /// Get all diagnostics for a URI.
  Future<List<VscodeDiagnostic>> getDiagnostics(String uri) async {
    final resp = await _protocol.sendRequest('vscode/getDiagnostics', {
      'uri': uri,
    });
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map((d) => VscodeDiagnostic.fromJson(d as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  // ---- UI ----

  /// Show an information message.
  Future<String?> showInfoMessage(
    String message, {
    List<String>? actions,
  }) async {
    final resp = await _protocol.windowShowMessage(
      type: 3,
      message: message,
      actions: actions,
    );
    return resp.result as String?;
  }

  /// Show a warning message.
  Future<String?> showWarningMessage(
    String message, {
    List<String>? actions,
  }) async {
    final resp = await _protocol.windowShowMessage(
      type: 2,
      message: message,
      actions: actions,
    );
    return resp.result as String?;
  }

  /// Show an error message.
  Future<String?> showErrorMessage(
    String message, {
    List<String>? actions,
  }) async {
    final resp = await _protocol.windowShowMessage(
      type: 1,
      message: message,
      actions: actions,
    );
    return resp.result as String?;
  }

  /// Show an input box and return user input.
  Future<String?> showInputBox({
    String? prompt,
    String? placeholder,
    String? value,
    bool password = false,
  }) async {
    final resp = await _protocol.sendRequest('vscode/showInputBox', {
      'prompt': ?prompt,
      'placeholder': ?placeholder,
      'value': ?value,
      'password': password,
    });
    if (resp.isSuccess) return resp.result as String?;
    return null;
  }

  /// Show a quick pick menu and return selected items.
  Future<List<VscodeQuickPickItem>?> showQuickPick(
    List<VscodeQuickPickItem> items, {
    String? placeholder,
    bool canPickMany = false,
  }) async {
    final resp = await _protocol.sendRequest('vscode/showQuickPick', {
      'items': items.map((i) => i.toJson()).toList(),
      'placeholder': ?placeholder,
      'canPickMany': canPickMany,
    });
    if (resp.isSuccess && resp.result is List) {
      return (resp.result as List)
          .map((i) => VscodeQuickPickItem.fromJson(i as Map<String, dynamic>))
          .toList();
    }
    return null;
  }

  /// Show a progress notification.
  Future<BridgeResponse> showProgress({
    required String title,
    String? message,
    int? percentage,
    bool cancellable = false,
  }) {
    return _protocol.sendRequest('vscode/showProgress', {
      'title': title,
      'message': ?message,
      'percentage': ?percentage,
      'cancellable': cancellable,
    });
  }

  /// Update a status bar item.
  void updateStatusBarItem(VscodeStatusBarItem item) {
    _statusBarItems[item.id] = item;
    _protocol.sendNotification('vscode/updateStatusBarItem', item.toJson());
  }

  /// Remove a status bar item.
  void removeStatusBarItem(String id) {
    _statusBarItems.remove(id);
    _protocol.sendNotification('vscode/removeStatusBarItem', {'id': id});
  }

  // ---- Terminal ----

  /// Create a new terminal.
  Future<String?> createTerminal({
    String? name,
    String? shellPath,
    List<String>? shellArgs,
    String? cwd,
    Map<String, String>? env,
  }) async {
    final resp = await _protocol.sendRequest('vscode/createTerminal', {
      'name': ?name,
      'shellPath': ?shellPath,
      'shellArgs': ?shellArgs,
      'cwd': ?cwd,
      'env': ?env,
    });
    if (resp.isSuccess) return resp.result as String?;
    return null;
  }

  /// Send text to a terminal.
  Future<BridgeResponse> sendTerminalText(
    String terminalId,
    String text, {
    bool addNewLine = true,
  }) {
    return _protocol.sendRequest('vscode/sendTerminalText', {
      'terminalId': terminalId,
      'text': text,
      'addNewLine': addNewLine,
    });
  }

  /// Close a terminal.
  Future<BridgeResponse> closeTerminal(String terminalId) {
    return _protocol.sendRequest('vscode/closeTerminal', {
      'terminalId': terminalId,
    });
  }

  // ---- Commands ----

  /// Register a command that the IDE can invoke.
  void registerCommand(VscodeCommand command) {
    _commands[command.id] = command;
    _protocol.registerHandler('vscode/command/${command.id}', (
      method,
      params,
    ) async {
      final args = params is Map && params.containsKey('args')
          ? params['args'] as List<dynamic>?
          : null;
      return await command.handler(args);
    });
    _protocol.sendNotification('vscode/registerCommand', command.toJson());
  }

  /// Unregister a command.
  void unregisterCommand(String commandId) {
    _commands.remove(commandId);
    _protocol.unregisterHandler('vscode/command/$commandId');
    _protocol.sendNotification('vscode/unregisterCommand', {'id': commandId});
  }

  // ---- Internal notification handlers ----

  void _registerNotificationHandlers() {
    _protocol.registerNotificationHandler('vscode/didChangeActiveEditor', (
      _,
      params,
    ) {
      if (params is Map && params.containsKey('uri')) {
        _onDidChangeActiveEditor.add(params['uri'] as String);
      }
    });

    _protocol.registerNotificationHandler('vscode/didSaveDocument', (
      _,
      params,
    ) {
      if (params is Map && params.containsKey('uri')) {
        _onDidSaveDocument.add(params['uri'] as String);
      }
    });

    _protocol.registerNotificationHandler('vscode/didChangeConfiguration', (
      _,
      params,
    ) {
      if (params is Map<String, dynamic>) {
        _onDidChangeConfiguration.add(params);
      }
    });

    _protocol.registerNotificationHandler('vscode/didChangeTheme', (_, params) {
      if (params is Map<String, dynamic>) {
        _currentTheme = VscodeTheme.fromJson(params);
        _onDidChangeTheme.add(_currentTheme!);
      }
    });

    _protocol.registerNotificationHandler('vscode/didChangeDiagnostics', (
      _,
      params,
    ) {
      if (params is Map && params.containsKey('diagnostics')) {
        final diagnostics = (params['diagnostics'] as List)
            .map((d) => VscodeDiagnostic.fromJson(d as Map<String, dynamic>))
            .toList();
        _onDidChangeDiagnostics.add(diagnostics);
      }
    });
  }

  // ---- Cleanup ----

  /// Disconnect from VS Code.
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
    _onDidChangeActiveEditor.close();
    _onDidSaveDocument.close();
    _onDidChangeConfiguration.close();
    _onDidChangeTheme.close();
    _onDidChangeDiagnostics.close();
    _commands.clear();
    _statusBarItems.clear();
    _protocol.dispose();
  }
}
