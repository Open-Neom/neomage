// LSPTool — port of neomage/src/tools/LSPTool/.
// Language Server Protocol integration: go-to-definition, find-references,
// hover, document/workspace symbols, call hierarchy, with formatters and
// schema validation.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'tool.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const String lspToolName = 'LSP';

const String lspToolDescription =
    'Query a Language Server for code intelligence '
    '(definitions, references, symbols, hover)';

/// Maximum file size accepted for LSP analysis (10 MB).
const int maxLspFileSizeBytes = 10000000;

// ─── LSP Operations ──────────────────────────────────────────────────────────

/// All supported LSP operations.
enum LspOperation {
  goToDefinition,
  findReferences,
  hover,
  documentSymbol,
  workspaceSymbol,
  goToImplementation,
  prepareCallHierarchy,
  incomingCalls,
  outgoingCalls;

  /// Convert to the LSP method string.
  String get method {
    switch (this) {
      case LspOperation.goToDefinition:
        return 'textDocument/definition';
      case LspOperation.findReferences:
        return 'textDocument/references';
      case LspOperation.hover:
        return 'textDocument/hover';
      case LspOperation.documentSymbol:
        return 'textDocument/documentSymbol';
      case LspOperation.workspaceSymbol:
        return 'workspace/symbol';
      case LspOperation.goToImplementation:
        return 'textDocument/implementation';
      case LspOperation.prepareCallHierarchy:
        return 'textDocument/prepareCallHierarchy';
      case LspOperation.incomingCalls:
        return 'textDocument/prepareCallHierarchy';
      case LspOperation.outgoingCalls:
        return 'textDocument/prepareCallHierarchy';
    }
  }

  /// Parse from string.
  static LspOperation? fromString(String s) {
    for (final op in values) {
      if (op.name == s) return op;
    }
    return null;
  }
}

/// Check if a string is a valid LSP operation name.
bool isValidLspOperation(String operation) {
  return LspOperation.fromString(operation) != null;
}

// ─── Symbol Kind ─────────────────────────────────────────────────────────────

/// Maps LSP SymbolKind enum values to readable strings.
String symbolKindToString(int kind) {
  const kinds = <int, String>{
    1: 'File',
    2: 'Module',
    3: 'Namespace',
    4: 'Package',
    5: 'Class',
    6: 'Method',
    7: 'Property',
    8: 'Field',
    9: 'Constructor',
    10: 'Enum',
    11: 'Interface',
    12: 'Function',
    13: 'Variable',
    14: 'Constant',
    15: 'String',
    16: 'Number',
    17: 'Boolean',
    18: 'Array',
    19: 'Object',
    20: 'Key',
    21: 'Null',
    22: 'EnumMember',
    23: 'Struct',
    24: 'Event',
    25: 'Operator',
    26: 'TypeParameter',
  };
  return kinds[kind] ?? 'Unknown';
}

// ─── LSP Data Models ─────────────────────────────────────────────────────────

/// LSP Position (0-based).
class LspPosition {
  final int line;
  final int character;

  const LspPosition({required this.line, required this.character});

  factory LspPosition.fromJson(Map<String, dynamic> json) => LspPosition(
    line: json['line'] as int,
    character: json['character'] as int,
  );

  Map<String, dynamic> toJson() => {'line': line, 'character': character};
}

/// LSP Range.
class LspRange {
  final LspPosition start;
  final LspPosition end;

  const LspRange({required this.start, required this.end});

  factory LspRange.fromJson(Map<String, dynamic> json) => LspRange(
    start: LspPosition.fromJson(json['start'] as Map<String, dynamic>),
    end: LspPosition.fromJson(json['end'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {
    'start': start.toJson(),
    'end': end.toJson(),
  };
}

/// LSP Location.
class LspLocation {
  final String uri;
  final LspRange range;

  const LspLocation({required this.uri, required this.range});

  factory LspLocation.fromJson(Map<String, dynamic> json) => LspLocation(
    uri: json['uri'] as String,
    range: LspRange.fromJson(json['range'] as Map<String, dynamic>),
  );

  Map<String, dynamic> toJson() => {'uri': uri, 'range': range.toJson()};
}

/// LSP LocationLink.
class LspLocationLink {
  final String targetUri;
  final LspRange targetRange;
  final LspRange targetSelectionRange;
  final LspRange? originSelectionRange;

  const LspLocationLink({
    required this.targetUri,
    required this.targetRange,
    required this.targetSelectionRange,
    this.originSelectionRange,
  });

  factory LspLocationLink.fromJson(Map<String, dynamic> json) =>
      LspLocationLink(
        targetUri: json['targetUri'] as String,
        targetRange: LspRange.fromJson(
          json['targetRange'] as Map<String, dynamic>,
        ),
        targetSelectionRange: LspRange.fromJson(
          json['targetSelectionRange'] as Map<String, dynamic>,
        ),
        originSelectionRange: json['originSelectionRange'] != null
            ? LspRange.fromJson(
                json['originSelectionRange'] as Map<String, dynamic>,
              )
            : null,
      );

  /// Convert to a Location for uniform handling.
  LspLocation toLocation() =>
      LspLocation(uri: targetUri, range: targetSelectionRange);
}

/// LSP DocumentSymbol (hierarchical).
class LspDocumentSymbol {
  final String name;
  final int kind;
  final String? detail;
  final LspRange range;
  final LspRange selectionRange;
  final List<LspDocumentSymbol> children;

  const LspDocumentSymbol({
    required this.name,
    required this.kind,
    this.detail,
    required this.range,
    required this.selectionRange,
    this.children = const [],
  });

  factory LspDocumentSymbol.fromJson(Map<String, dynamic> json) =>
      LspDocumentSymbol(
        name: json['name'] as String,
        kind: json['kind'] as int,
        detail: json['detail'] as String?,
        range: LspRange.fromJson(json['range'] as Map<String, dynamic>),
        selectionRange: LspRange.fromJson(
          json['selectionRange'] as Map<String, dynamic>,
        ),
        children:
            (json['children'] as List<dynamic>?)
                ?.map(
                  (e) => LspDocumentSymbol.fromJson(e as Map<String, dynamic>),
                )
                .toList() ??
            const [],
      );
}

/// LSP SymbolInformation (flat).
class LspSymbolInformation {
  final String name;
  final int kind;
  final LspLocation location;
  final String? containerName;

  const LspSymbolInformation({
    required this.name,
    required this.kind,
    required this.location,
    this.containerName,
  });

  factory LspSymbolInformation.fromJson(Map<String, dynamic> json) =>
      LspSymbolInformation(
        name: json['name'] as String,
        kind: json['kind'] as int,
        location: LspLocation.fromJson(
          json['location'] as Map<String, dynamic>,
        ),
        containerName: json['containerName'] as String?,
      );
}

/// LSP Hover result.
class LspHover {
  final dynamic contents; // MarkupContent | MarkedString | MarkedString[]
  final LspRange? range;

  const LspHover({required this.contents, this.range});

  factory LspHover.fromJson(Map<String, dynamic> json) => LspHover(
    contents: json['contents'],
    range: json['range'] != null
        ? LspRange.fromJson(json['range'] as Map<String, dynamic>)
        : null,
  );
}

/// LSP CallHierarchyItem.
class LspCallHierarchyItem {
  final String name;
  final int kind;
  final String uri;
  final LspRange range;
  final LspRange selectionRange;
  final String? detail;

  const LspCallHierarchyItem({
    required this.name,
    required this.kind,
    required this.uri,
    required this.range,
    required this.selectionRange,
    this.detail,
  });

  factory LspCallHierarchyItem.fromJson(Map<String, dynamic> json) =>
      LspCallHierarchyItem(
        name: json['name'] as String,
        kind: json['kind'] as int,
        uri: json['uri'] as String,
        range: LspRange.fromJson(json['range'] as Map<String, dynamic>),
        selectionRange: LspRange.fromJson(
          json['selectionRange'] as Map<String, dynamic>,
        ),
        detail: json['detail'] as String?,
      );
}

/// LSP CallHierarchyIncomingCall.
class LspIncomingCall {
  final LspCallHierarchyItem from;
  final List<LspRange> fromRanges;

  const LspIncomingCall({required this.from, required this.fromRanges});

  factory LspIncomingCall.fromJson(Map<String, dynamic> json) =>
      LspIncomingCall(
        from: LspCallHierarchyItem.fromJson(
          json['from'] as Map<String, dynamic>,
        ),
        fromRanges: (json['fromRanges'] as List<dynamic>)
            .map((e) => LspRange.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// LSP CallHierarchyOutgoingCall.
class LspOutgoingCall {
  final LspCallHierarchyItem to;
  final List<LspRange> fromRanges;

  const LspOutgoingCall({required this.to, required this.fromRanges});

  factory LspOutgoingCall.fromJson(Map<String, dynamic> json) =>
      LspOutgoingCall(
        to: LspCallHierarchyItem.fromJson(json['to'] as Map<String, dynamic>),
        fromRanges: (json['fromRanges'] as List<dynamic>)
            .map((e) => LspRange.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

// ─── LSP Tool Input / Output ─────────────────────────────────────────────────

/// Input for the LSP tool.
class LspToolInput {
  final LspOperation operation;
  final String filePath;
  final int line; // 1-based
  final int character; // 1-based

  const LspToolInput({
    required this.operation,
    required this.filePath,
    required this.line,
    required this.character,
  });

  factory LspToolInput.fromJson(Map<String, dynamic> json) {
    final opStr = json['operation'] as String;
    final op = LspOperation.fromString(opStr);
    if (op == null) {
      throw ArgumentError('Invalid LSP operation: $opStr');
    }
    return LspToolInput(
      operation: op,
      filePath: json['filePath'] as String,
      line: json['line'] as int,
      character: json['character'] as int,
    );
  }

  /// Get 0-based position for the LSP protocol.
  LspPosition get lspPosition =>
      LspPosition(line: line - 1, character: character - 1);
}

/// Output of an LSP tool operation.
class LspToolOutput {
  final String operation;
  final String result;
  final String filePath;
  final int? resultCount;
  final int? fileCount;

  const LspToolOutput({
    required this.operation,
    required this.result,
    required this.filePath,
    this.resultCount,
    this.fileCount,
  });

  Map<String, dynamic> toJson() => {
    'operation': operation,
    'result': result,
    'filePath': filePath,
    if (resultCount != null) 'resultCount': resultCount,
    if (fileCount != null) 'fileCount': fileCount,
  };
}

// ─── Formatters ──────────────────────────────────────────────────────────────

/// Format a URI to a relative path if possible.
String formatUri(String? uri, {String? cwd}) {
  if (uri == null || uri.isEmpty) {
    return '<unknown location>';
  }

  var filePath = uri.replaceFirst(RegExp(r'^file://'), '');
  // Windows drive-letter paths: /C:/path → C:/path
  if (RegExp(r'^/[A-Za-z]:').hasMatch(filePath)) {
    filePath = filePath.substring(1);
  }

  // Decode URI encoding.
  try {
    filePath = Uri.decodeFull(filePath);
  } catch (_) {
    // Use un-decoded path on failure.
  }

  // Convert to relative path if cwd provided.
  if (cwd != null && cwd.isNotEmpty) {
    if (filePath.startsWith(cwd)) {
      var relative = filePath.substring(cwd.length);
      if (relative.startsWith('/') || relative.startsWith('\\')) {
        relative = relative.substring(1);
      }
      // Normalize separators.
      relative = relative.replaceAll('\\', '/');
      if (relative.length < filePath.length && !relative.startsWith('../../')) {
        return relative;
      }
    }
  }

  return filePath.replaceAll('\\', '/');
}

/// Format a Location as "file:line:char".
String formatLocation(LspLocation location, {String? cwd}) {
  final filePath = formatUri(location.uri, cwd: cwd);
  final line = location.range.start.line + 1;
  final character = location.range.start.character + 1;
  return '$filePath:$line:$character';
}

/// Group items by their file URI.
Map<String, List<T>> groupByFile<T>(
  List<T> items,
  String Function(T) getUri, {
  String? cwd,
}) {
  final byFile = <String, List<T>>{};
  for (final item in items) {
    final filePath = formatUri(getUri(item), cwd: cwd);
    byFile.putIfAbsent(filePath, () => []).add(item);
  }
  return byFile;
}

/// Format goToDefinition result.
String formatGoToDefinitionResult(List<LspLocation>? locations, {String? cwd}) {
  if (locations == null || locations.isEmpty) {
    return 'No definition found. This may occur if the cursor is not on a '
        'symbol, or if the definition is in an external library not indexed '
        'by the LSP server.';
  }

  final valid = locations.where((l) => l.uri.isNotEmpty).toList();
  if (valid.isEmpty) {
    return 'No definition found. This may occur if the cursor is not on a '
        'symbol, or if the definition is in an external library not indexed '
        'by the LSP server.';
  }

  if (valid.length == 1) {
    return 'Defined in ${formatLocation(valid[0], cwd: cwd)}';
  }

  final locationList = valid
      .map((loc) => '  ${formatLocation(loc, cwd: cwd)}')
      .join('\n');
  return 'Found ${valid.length} definitions:\n$locationList';
}

/// Format findReferences result.
String formatFindReferencesResult(List<LspLocation>? locations, {String? cwd}) {
  if (locations == null || locations.isEmpty) {
    return 'No references found. This may occur if the symbol has no usages, '
        'or if the LSP server has not fully indexed the workspace.';
  }

  final valid = locations.where((l) => l.uri.isNotEmpty).toList();
  if (valid.isEmpty) {
    return 'No references found. This may occur if the symbol has no usages, '
        'or if the LSP server has not fully indexed the workspace.';
  }

  if (valid.length == 1) {
    return 'Found 1 reference:\n  ${formatLocation(valid[0], cwd: cwd)}';
  }

  final byFile = groupByFile(valid, (l) => l.uri, cwd: cwd);
  final lines = <String>[
    'Found ${valid.length} references across ${byFile.length} files:',
  ];

  for (final entry in byFile.entries) {
    lines.add('\n${entry.key}:');
    for (final loc in entry.value) {
      final line = loc.range.start.line + 1;
      final character = loc.range.start.character + 1;
      lines.add('  Line $line:$character');
    }
  }

  return lines.join('\n');
}

/// Extract text content from MarkupContent or MarkedString.
String extractMarkupText(dynamic contents) {
  if (contents is List) {
    return contents
        .map((item) {
          if (item is String) return item;
          if (item is Map) return item['value'] as String? ?? '';
          return '';
        })
        .join('\n\n');
  }
  if (contents is String) return contents;
  if (contents is Map) {
    return contents['value'] as String? ?? '';
  }
  return '';
}

/// Format hover result.
String formatHoverResult(LspHover? hover, {String? cwd}) {
  if (hover == null) {
    return 'No hover information available. This may occur if the cursor is '
        'not on a symbol, or if the LSP server has not fully indexed the file.';
  }
  final content = extractMarkupText(hover.contents);
  if (hover.range != null) {
    final line = hover.range!.start.line + 1;
    final character = hover.range!.start.character + 1;
    return 'Hover info at $line:$character:\n\n$content';
  }
  return content;
}

/// Format a single DocumentSymbol with indentation.
List<String> _formatDocumentSymbolNode(
  LspDocumentSymbol symbol, {
  int indent = 0,
}) {
  final lines = <String>[];
  final prefix = '  ' * indent;
  final kind = symbolKindToString(symbol.kind);
  var line = '$prefix${symbol.name} ($kind)';
  if (symbol.detail != null) line += ' ${symbol.detail}';
  line += ' - Line ${symbol.range.start.line + 1}';
  lines.add(line);

  for (final child in symbol.children) {
    lines.addAll(_formatDocumentSymbolNode(child, indent: indent + 1));
  }
  return lines;
}

/// Format documentSymbol result (hierarchical outline).
String formatDocumentSymbolResult(
  List<LspDocumentSymbol>? symbols, {
  String? cwd,
}) {
  if (symbols == null || symbols.isEmpty) {
    return 'No symbols found in document. This may occur if the file is empty, '
        'not supported by the LSP server, or if the server has not fully '
        'indexed the file.';
  }
  final lines = <String>['Document symbols:'];
  for (final symbol in symbols) {
    lines.addAll(_formatDocumentSymbolNode(symbol));
  }
  return lines.join('\n');
}

/// Format workspaceSymbol result (flat list).
String formatWorkspaceSymbolResult(
  List<LspSymbolInformation>? symbols, {
  String? cwd,
}) {
  if (symbols == null || symbols.isEmpty) {
    return 'No symbols found in workspace. This may occur if the workspace is '
        'empty, or if the LSP server has not finished indexing the project.';
  }

  final valid = symbols.where((s) => s.location.uri.isNotEmpty).toList();
  if (valid.isEmpty) {
    return 'No symbols found in workspace. This may occur if the workspace is '
        'empty, or if the LSP server has not finished indexing the project.';
  }

  final plural = valid.length == 1 ? 'symbol' : 'symbols';
  final lines = <String>['Found ${valid.length} $plural in workspace:'];

  final byFile = groupByFile(valid, (s) => s.location.uri, cwd: cwd);
  for (final entry in byFile.entries) {
    lines.add('\n${entry.key}:');
    for (final symbol in entry.value) {
      final kind = symbolKindToString(symbol.kind);
      final line = symbol.location.range.start.line + 1;
      var symbolLine = '  ${symbol.name} ($kind) - Line $line';
      if (symbol.containerName != null) {
        symbolLine += ' in ${symbol.containerName}';
      }
      lines.add(symbolLine);
    }
  }

  return lines.join('\n');
}

/// Format a CallHierarchyItem with its location.
String _formatCallHierarchyItem(LspCallHierarchyItem item, {String? cwd}) {
  if (item.uri.isEmpty) {
    return '${item.name} (${symbolKindToString(item.kind)}) - <unknown location>';
  }
  final filePath = formatUri(item.uri, cwd: cwd);
  final line = item.range.start.line + 1;
  final kind = symbolKindToString(item.kind);
  var result = '${item.name} ($kind) - $filePath:$line';
  if (item.detail != null) result += ' [${item.detail}]';
  return result;
}

/// Format prepareCallHierarchy result.
String formatPrepareCallHierarchyResult(
  List<LspCallHierarchyItem>? items, {
  String? cwd,
}) {
  if (items == null || items.isEmpty) {
    return 'No call hierarchy item found at this position';
  }
  if (items.length == 1) {
    return 'Call hierarchy item: ${_formatCallHierarchyItem(items[0], cwd: cwd)}';
  }
  final lines = ['Found ${items.length} call hierarchy items:'];
  for (final item in items) {
    lines.add('  ${_formatCallHierarchyItem(item, cwd: cwd)}');
  }
  return lines.join('\n');
}

/// Format incomingCalls result.
String formatIncomingCallsResult(List<LspIncomingCall>? calls, {String? cwd}) {
  if (calls == null || calls.isEmpty) {
    return 'No incoming calls found (nothing calls this function)';
  }

  final plural = calls.length == 1 ? 'call' : 'calls';
  final lines = <String>['Found ${calls.length} incoming $plural:'];

  final byFile = groupByFile(calls, (c) => c.from.uri, cwd: cwd);
  for (final entry in byFile.entries) {
    lines.add('\n${entry.key}:');
    for (final call in entry.value) {
      final kind = symbolKindToString(call.from.kind);
      final line = call.from.range.start.line + 1;
      var callLine = '  ${call.from.name} ($kind) - Line $line';
      if (call.fromRanges.isNotEmpty) {
        final callSites = call.fromRanges
            .map((r) => '${r.start.line + 1}:${r.start.character + 1}')
            .join(', ');
        callLine += ' [calls at: $callSites]';
      }
      lines.add(callLine);
    }
  }

  return lines.join('\n');
}

/// Format outgoingCalls result.
String formatOutgoingCallsResult(List<LspOutgoingCall>? calls, {String? cwd}) {
  if (calls == null || calls.isEmpty) {
    return 'No outgoing calls found (this function calls nothing)';
  }

  final plural = calls.length == 1 ? 'call' : 'calls';
  final lines = <String>['Found ${calls.length} outgoing $plural:'];

  final byFile = groupByFile(calls, (c) => c.to.uri, cwd: cwd);
  for (final entry in byFile.entries) {
    lines.add('\n${entry.key}:');
    for (final call in entry.value) {
      final kind = symbolKindToString(call.to.kind);
      final line = call.to.range.start.line + 1;
      var callLine = '  ${call.to.name} ($kind) - Line $line';
      if (call.fromRanges.isNotEmpty) {
        final callSites = call.fromRanges
            .map((r) => '${r.start.line + 1}:${r.start.character + 1}')
            .join(', ');
        callLine += ' [called from: $callSites]';
      }
      lines.add(callLine);
    }
  }

  return lines.join('\n');
}

// ─── LSP Server Manager Interface ───────────────────────────────────────────

/// Initialization status of the LSP server.
enum LspInitStatus { pending, ready, failed }

/// Abstract LSP server manager interface.
abstract class LspServerManager {
  /// Whether the manager is connected and ready.
  bool get isConnected;

  /// Current initialization status.
  LspInitStatus get initStatus;

  /// Wait for initialization to complete.
  Future<void> waitForInitialization();

  /// Whether a file is already open in the server.
  bool isFileOpen(String absolutePath);

  /// Open a file with the given content.
  Future<void> openFile(String absolutePath, String content);

  /// Send a request to the LSP server.
  Future<dynamic> sendRequest(
    String absolutePath,
    String method,
    dynamic params,
  );
}

// ─── LSP Tool ────────────────────────────────────────────────────────────────

/// The LSPTool — code intelligence via Language Server Protocol.
class LspTool extends Tool with ReadOnlyToolMixin {
  LspServerManager? _manager;

  LspTool({LspServerManager? manager}) : _manager = manager;

  /// Set the LSP server manager.
  set manager(LspServerManager? m) => _manager = m;

  @override
  String get name => lspToolName;

  @override
  String get description => lspToolDescription;

  @override
  String get userFacingName => 'LSP';

  @override
  bool get shouldDefer => true;

  @override
  bool get isEnabled => _manager?.isConnected ?? false;

  @override
  int? get maxResultSizeChars => 100000;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'operation': {
        'type': 'string',
        'enum': LspOperation.values.map((e) => e.name).toList(),
        'description': 'The LSP operation to perform',
      },
      'filePath': {
        'type': 'string',
        'description': 'The absolute or relative path to the file',
      },
      'line': {
        'type': 'integer',
        'minimum': 1,
        'description': 'The line number (1-based, as shown in editors)',
      },
      'character': {
        'type': 'integer',
        'minimum': 1,
        'description': 'The character offset (1-based, as shown in editors)',
      },
    },
    'required': ['operation', 'filePath', 'line', 'character'],
    'additionalProperties': false,
  };

  /// Expand a file path, resolving ~ and relative paths.
  String _expandPath(String filePath) {
    if (filePath.startsWith('~/')) {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      return '$home${filePath.substring(1)}';
    }
    return filePath;
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    // Validate operation.
    final opStr = input['operation'] as String?;
    if (opStr == null || !isValidLspOperation(opStr)) {
      return ValidationResult.invalid('Invalid operation: $opStr');
    }

    // Validate file path.
    final filePath = input['filePath'] as String?;
    if (filePath == null || filePath.isEmpty) {
      return const ValidationResult.invalid('filePath is required');
    }

    final absolutePath = _expandPath(filePath);

    // SECURITY: Skip filesystem checks for UNC paths.
    if (absolutePath.startsWith('\\\\') || absolutePath.startsWith('//')) {
      return const ValidationResult.valid();
    }

    // Check file exists.
    final file = File(absolutePath);
    if (!file.existsSync()) {
      return ValidationResult.invalid('File does not exist: $filePath');
    }

    if (!file.statSync().type.toString().contains('file')) {
      return ValidationResult.invalid('Path is not a file: $filePath');
    }

    // Validate line/character are positive integers.
    final line = input['line'];
    if (line is! int || line < 1) {
      return const ValidationResult.invalid('line must be a positive integer');
    }

    final character = input['character'];
    if (character is! int || character < 1) {
      return const ValidationResult.invalid(
        'character must be a positive integer',
      );
    }

    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = LspToolInput.fromJson(input);
    final absolutePath = _expandPath(parsed.filePath);

    // Wait for initialization.
    final manager = _manager;
    if (manager == null) {
      return ToolResult.success(
        'LSP server manager not initialized. This may indicate a startup issue.',
        metadata: LspToolOutput(
          operation: parsed.operation.name,
          result: 'LSP server manager not initialized.',
          filePath: parsed.filePath,
        ).toJson(),
      );
    }

    if (manager.initStatus == LspInitStatus.pending) {
      await manager.waitForInitialization();
    }

    try {
      // Ensure file is open.
      if (!manager.isFileOpen(absolutePath)) {
        final file = File(absolutePath);
        final stat = await file.stat();
        if (stat.size > maxLspFileSizeBytes) {
          final sizeMb = (stat.size / 1000000).ceil();
          return ToolResult.success(
            'File too large for LSP analysis (${sizeMb}MB exceeds 10MB limit)',
            metadata: LspToolOutput(
              operation: parsed.operation.name,
              result:
                  'File too large for LSP analysis (${sizeMb}MB exceeds 10MB limit)',
              filePath: parsed.filePath,
            ).toJson(),
          );
        }
        final content = await file.readAsString();
        await manager.openFile(absolutePath, content);
      }

      // Build params.
      final uri = Uri.file(absolutePath).toString();
      final position = parsed.lspPosition;
      final method = parsed.operation.method;
      final params = _buildParams(parsed.operation, uri, position);

      // Send request.
      var result = await manager.sendRequest(absolutePath, method, params);

      if (result == null) {
        final ext = absolutePath.split('.').last;
        return ToolResult.success(
          'No LSP server available for file type: .$ext',
          metadata: LspToolOutput(
            operation: parsed.operation.name,
            result: 'No LSP server available for file type: .$ext',
            filePath: parsed.filePath,
          ).toJson(),
        );
      }

      // For call hierarchy, do the two-step process.
      if (parsed.operation == LspOperation.incomingCalls ||
          parsed.operation == LspOperation.outgoingCalls) {
        if (result is! List || result.isEmpty) {
          return ToolResult.success(
            'No call hierarchy item found at this position',
            metadata: LspToolOutput(
              operation: parsed.operation.name,
              result: 'No call hierarchy item found at this position',
              filePath: parsed.filePath,
              resultCount: 0,
              fileCount: 0,
            ).toJson(),
          );
        }

        final callMethod = parsed.operation == LspOperation.incomingCalls
            ? 'callHierarchy/incomingCalls'
            : 'callHierarchy/outgoingCalls';

        result = await manager.sendRequest(absolutePath, callMethod, {
          'item': result[0],
        });
      }

      // Format result string.
      final formatted = _formatResult(parsed.operation, result);
      return ToolResult.success(
        formatted,
        metadata: LspToolOutput(
          operation: parsed.operation.name,
          result: formatted,
          filePath: parsed.filePath,
        ).toJson(),
      );
    } catch (e) {
      final errorMsg = 'Error performing ${parsed.operation.name}: $e';
      return ToolResult.success(
        errorMsg,
        metadata: LspToolOutput(
          operation: parsed.operation.name,
          result: errorMsg,
          filePath: parsed.filePath,
        ).toJson(),
      );
    }
  }

  /// Build LSP request parameters.
  Map<String, dynamic> _buildParams(
    LspOperation op,
    String uri,
    LspPosition position,
  ) {
    switch (op) {
      case LspOperation.goToDefinition:
      case LspOperation.goToImplementation:
      case LspOperation.hover:
      case LspOperation.prepareCallHierarchy:
      case LspOperation.incomingCalls:
      case LspOperation.outgoingCalls:
        return {
          'textDocument': {'uri': uri},
          'position': position.toJson(),
        };
      case LspOperation.findReferences:
        return {
          'textDocument': {'uri': uri},
          'position': position.toJson(),
          'context': {'includeDeclaration': true},
        };
      case LspOperation.documentSymbol:
        return {
          'textDocument': {'uri': uri},
        };
      case LspOperation.workspaceSymbol:
        return {'query': ''};
    }
  }

  /// Format a result based on the operation.
  String _formatResult(LspOperation op, dynamic result) {
    // In a full implementation this would parse the LSP JSON response into
    // the typed models and call the appropriate formatter. For now we
    // delegate to a generic string representation.
    if (result is String) return result;
    return 'Result: $result';
  }
}
