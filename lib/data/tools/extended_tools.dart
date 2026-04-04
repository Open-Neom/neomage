// Extended tools — port of remaining neom_claw/src/tools/.
// All tools not already ported individually.
//
// Already ported: Bash, FileRead, FileWrite, FileEdit, Grep, Glob,
//   AgentTool, SendMessage, TaskOutput, TodoWrite, ToolSearch, WebFetch,
//   WebSearch.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import '../../domain/models/tool_definition.dart';
import 'tool.dart';

// ═══════════════════════════════════════════════════════════════════════════
// NotebookEditTool — edit Jupyter notebooks (.ipynb)
// ═══════════════════════════════════════════════════════════════════════════

class NotebookEditInput {
  final String notebookPath;
  final String command; // add, edit, delete, move
  final int cellIndex;
  final String? content;
  final String? cellType; // code, markdown, raw
  final int? targetIndex; // for move

  NotebookEditInput({
    required this.notebookPath,
    required this.command,
    required this.cellIndex,
    this.content,
    this.cellType,
    this.targetIndex,
  });

  factory NotebookEditInput.fromJson(Map<String, dynamic> json) =>
      NotebookEditInput(
        notebookPath: json['notebook_path'] as String,
        command: json['command'] as String,
        cellIndex: json['cell_index'] as int? ?? 0,
        content: json['content'] as String?,
        cellType: json['cell_type'] as String?,
        targetIndex: json['target_index'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'notebook_path': notebookPath,
        'command': command,
        'cell_index': cellIndex,
        if (content != null) 'content': content,
        if (cellType != null) 'cell_type': cellType,
        if (targetIndex != null) 'target_index': targetIndex,
      };
}

class NotebookEditOutput {
  final bool success;
  final String message;
  final int cellCount;

  const NotebookEditOutput({
    required this.success,
    required this.message,
    required this.cellCount,
  });

  @override
  String toString() =>
      success ? '$message (cells: $cellCount)' : 'Error: $message';
}

class NotebookEditTool extends Tool with FileWriteToolMixin {
  @override
  String get name => 'NotebookEdit';

  @override
  String get description =>
      'Edit Jupyter notebook (.ipynb) cells. Supports add, edit, delete, '
      'and move operations on individual cells.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'notebook_path': {
            'type': 'string',
            'description': 'Absolute path to the .ipynb file',
          },
          'command': {
            'type': 'string',
            'enum': ['add', 'edit', 'delete', 'move'],
            'description': 'Operation to perform on the cell',
          },
          'cell_index': {
            'type': 'integer',
            'description': 'Zero-based index of the target cell',
          },
          'content': {
            'type': 'string',
            'description': 'New cell content (for add/edit)',
          },
          'cell_type': {
            'type': 'string',
            'enum': ['code', 'markdown', 'raw'],
            'description': 'Cell type (for add/edit, default: code)',
          },
          'target_index': {
            'type': 'integer',
            'description': 'Destination index (for move)',
          },
        },
        'required': ['notebook_path', 'command'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final path = input['notebook_path'] as String?;
    if (path == null || path.isEmpty) {
      return const ValidationResult.invalid('notebook_path is required');
    }
    if (!path.endsWith('.ipynb')) {
      return const ValidationResult.invalid('File must be a .ipynb notebook');
    }
    final cmd = input['command'] as String?;
    if (cmd == null || !['add', 'edit', 'delete', 'move'].contains(cmd)) {
      return const ValidationResult.invalid(
          'command must be one of: add, edit, delete, move');
    }
    if ((cmd == 'add' || cmd == 'edit') && input['content'] == null) {
      return ValidationResult.invalid('content is required for $cmd');
    }
    if (cmd == 'move' && input['target_index'] == null) {
      return const ValidationResult.invalid(
          'target_index is required for move');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = NotebookEditInput.fromJson(input);
    final file = File(parsed.notebookPath);

    if (!await file.exists()) {
      return ToolResult.error('Notebook not found: ${parsed.notebookPath}');
    }

    try {
      final raw = await file.readAsString();
      final notebook = jsonDecode(raw) as Map<String, dynamic>;
      final cells = (notebook['cells'] as List).cast<Map<String, dynamic>>();
      final cellType = parsed.cellType ?? 'code';

      switch (parsed.command) {
        case 'add':
          final newCell = _makeCell(cellType, parsed.content!);
          final idx = parsed.cellIndex.clamp(0, cells.length);
          cells.insert(idx, newCell);

        case 'edit':
          if (parsed.cellIndex < 0 || parsed.cellIndex >= cells.length) {
            return ToolResult.error(
                'cell_index ${parsed.cellIndex} out of range (0..${cells.length - 1})');
          }
          cells[parsed.cellIndex]['source'] = _splitSource(parsed.content!);
          if (parsed.cellType != null) {
            cells[parsed.cellIndex]['cell_type'] = parsed.cellType;
          }

        case 'delete':
          if (parsed.cellIndex < 0 || parsed.cellIndex >= cells.length) {
            return ToolResult.error(
                'cell_index ${parsed.cellIndex} out of range (0..${cells.length - 1})');
          }
          cells.removeAt(parsed.cellIndex);

        case 'move':
          if (parsed.cellIndex < 0 || parsed.cellIndex >= cells.length) {
            return ToolResult.error(
                'cell_index ${parsed.cellIndex} out of range');
          }
          final target = parsed.targetIndex!.clamp(0, cells.length - 1);
          final cell = cells.removeAt(parsed.cellIndex);
          cells.insert(target, cell);
      }

      notebook['cells'] = cells;
      final encoder = const JsonEncoder.withIndent(' ');
      await file.writeAsString(encoder.convert(notebook));

      final out = NotebookEditOutput(
        success: true,
        message: '${parsed.command} cell at index ${parsed.cellIndex}',
        cellCount: cells.length,
      );
      return ToolResult.success(out.toString());
    } catch (e) {
      return ToolResult.error('Error editing notebook: $e');
    }
  }

  Map<String, dynamic> _makeCell(String type, String content) => {
        'cell_type': type,
        'metadata': <String, dynamic>{},
        'source': _splitSource(content),
        if (type == 'code') 'execution_count': null,
        if (type == 'code') 'outputs': <dynamic>[],
      };

  List<String> _splitSource(String content) {
    final lines = content.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        i < lines.length - 1 ? '${lines[i]}\n' : lines[i],
    ];
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ExitPlanModeTool — signal completion of planning phase
// ═══════════════════════════════════════════════════════════════════════════

class ExitPlanModeInput {
  final String planSummary;

  ExitPlanModeInput({required this.planSummary});

  factory ExitPlanModeInput.fromJson(Map<String, dynamic> json) =>
      ExitPlanModeInput(planSummary: json['plan_summary'] as String);

  Map<String, dynamic> toJson() => {'plan_summary': planSummary};
}

class ExitPlanModeOutput {
  final bool success;
  final String plan;

  const ExitPlanModeOutput({required this.success, required this.plan});

  @override
  String toString() => success ? 'Plan accepted:\n$plan' : 'Plan rejected';
}

class ExitPlanModeTool extends Tool {
  @override
  String get name => 'ExitPlanMode';

  @override
  String get description =>
      'Exit plan mode and begin executing the plan. Provide a summary '
      'of the plan that was developed during planning.';

  @override
  bool get isReadOnly => true;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'plan_summary': {
            'type': 'string',
            'description': 'Summary of the plan to execute',
          },
        },
        'required': ['plan_summary'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final summary = input['plan_summary'] as String?;
    if (summary == null || summary.trim().isEmpty) {
      return const ValidationResult.invalid('plan_summary is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = ExitPlanModeInput.fromJson(input);
    final out = ExitPlanModeOutput(success: true, plan: parsed.planSummary);
    return ToolResult.success(
      out.toString(),
      metadata: {'plan_summary': parsed.planSummary, 'exit_plan_mode': true},
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PowerShellTool — execute PowerShell commands on Windows
// ═══════════════════════════════════════════════════════════════════════════

class PowerShellInput {
  final String command;
  final int? timeoutMs;

  PowerShellInput({required this.command, this.timeoutMs});

  factory PowerShellInput.fromJson(Map<String, dynamic> json) =>
      PowerShellInput(
        command: json['command'] as String,
        timeoutMs: json['timeout_ms'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'command': command,
        if (timeoutMs != null) 'timeout_ms': timeoutMs,
      };
}

class PowerShellOutput {
  final String stdout;
  final String stderr;
  final int exitCode;
  final int durationMs;

  const PowerShellOutput({
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.durationMs,
  });

  @override
  String toString() {
    final parts = <String>[];
    if (stdout.isNotEmpty) parts.add(stdout);
    if (stderr.isNotEmpty) parts.add('STDERR: $stderr');
    parts.add('Exit code: $exitCode (${durationMs}ms)');
    return parts.join('\n');
  }
}

class PowerShellTool extends Tool with ShellToolMixin {
  final Duration defaultTimeout;

  PowerShellTool({this.defaultTimeout = const Duration(minutes: 2)});

  @override
  String get name => 'PowerShell';

  @override
  String get description =>
      'Execute PowerShell commands on Windows. '
      'Returns stdout, stderr, and exit code.';

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'The PowerShell command to execute',
          },
          'timeout_ms': {
            'type': 'integer',
            'description': 'Timeout in milliseconds (default: 120000)',
          },
        },
        'required': ['command'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final cmd = input['command'] as String?;
    if (cmd == null || cmd.trim().isEmpty) {
      return const ValidationResult.invalid('command is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = PowerShellInput.fromJson(input);
    final timeout = parsed.timeoutMs != null
        ? Duration(milliseconds: parsed.timeoutMs!)
        : defaultTimeout;

    final sw = Stopwatch()..start();
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', parsed.command],
      ).timeout(timeout);
      sw.stop();

      final out = PowerShellOutput(
        stdout: (result.stdout as String).trim(),
        stderr: (result.stderr as String).trim(),
        exitCode: result.exitCode,
        durationMs: sw.elapsedMilliseconds,
      );

      return result.exitCode != 0
          ? ToolResult(content: out.toString(), isError: true)
          : ToolResult.success(out.toString());
    } on ProcessException catch (e) {
      return ToolResult.error('PowerShell error: ${e.message}');
    } catch (e) {
      return ToolResult.error('Command timed out after ${timeout.inSeconds}s');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SkillTool — load and execute a skill / slash command
// ═══════════════════════════════════════════════════════════════════════════

class SkillInput {
  final String skillName;
  final String? args;

  SkillInput({required this.skillName, this.args});

  factory SkillInput.fromJson(Map<String, dynamic> json) => SkillInput(
        skillName: json['skill_name'] as String,
        args: json['args'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'skill_name': skillName,
        if (args != null) 'args': args,
      };
}

class SkillOutput {
  final String result;
  final bool skillLoaded;

  const SkillOutput({required this.result, required this.skillLoaded});

  @override
  String toString() =>
      skillLoaded ? result : 'Skill not found: $result';
}

class SkillTool extends Tool {
  /// Callback to resolve and execute skills. Injected by the host.
  final Future<ToolResult> Function(String skillName, String? args)? resolver;

  SkillTool({this.resolver});

  @override
  String get name => 'Skill';

  @override
  String get description =>
      'Load and execute a skill or slash command by name. '
      'Skills provide specialized capabilities and domain knowledge.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'skill_name': {
            'type': 'string',
            'description': 'The skill name to execute (e.g. "commit", "pdf")',
          },
          'args': {
            'type': 'string',
            'description': 'Optional arguments for the skill',
          },
        },
        'required': ['skill_name'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final name = input['skill_name'] as String?;
    if (name == null || name.trim().isEmpty) {
      return const ValidationResult.invalid('skill_name is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = SkillInput.fromJson(input);
    if (resolver != null) {
      return resolver!(parsed.skillName, parsed.args);
    }
    // Default stub when no resolver is wired up.
    return ToolResult.success(
      'Skill "${parsed.skillName}" dispatched'
      '${parsed.args != null ? " with args: ${parsed.args}" : ""}',
      metadata: {
        'skill_name': parsed.skillName,
        'skill_loaded': true,
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// McpTool — execute a tool from an MCP server
// ═══════════════════════════════════════════════════════════════════════════

class McpToolInput {
  final String serverName;
  final String toolName;
  final Map<String, dynamic> arguments;

  McpToolInput({
    required this.serverName,
    required this.toolName,
    required this.arguments,
  });

  factory McpToolInput.fromJson(Map<String, dynamic> json) => McpToolInput(
        serverName: json['server_name'] as String,
        toolName: json['tool_name'] as String,
        arguments:
            (json['arguments'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      );

  Map<String, dynamic> toJson() => {
        'server_name': serverName,
        'tool_name': toolName,
        'arguments': arguments,
      };
}

class McpToolOutput {
  final dynamic result;
  final bool isError;

  const McpToolOutput({required this.result, this.isError = false});

  @override
  String toString() {
    if (result is String) return result as String;
    return const JsonEncoder.withIndent('  ').convert(result);
  }
}

class McpTool extends Tool {
  /// Callback to dispatch to the actual MCP server. Injected by the host.
  final Future<ToolResult> Function(
      String serverName, String toolName, Map<String, dynamic> args)? dispatch;

  McpTool({this.dispatch});

  @override
  String get name => 'McpTool';

  @override
  String get description =>
      'Execute a tool exposed by an MCP (Model Context Protocol) server. '
      'Requires server_name, tool_name, and arguments.';

  @override
  bool get isMcp => true;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'server_name': {
            'type': 'string',
            'description': 'Name of the MCP server',
          },
          'tool_name': {
            'type': 'string',
            'description': 'Name of the tool on the server',
          },
          'arguments': {
            'type': 'object',
            'description': 'Arguments to pass to the tool',
          },
        },
        'required': ['server_name', 'tool_name'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    if (input['server_name'] == null ||
        (input['server_name'] as String).isEmpty) {
      return const ValidationResult.invalid('server_name is required');
    }
    if (input['tool_name'] == null ||
        (input['tool_name'] as String).isEmpty) {
      return const ValidationResult.invalid('tool_name is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = McpToolInput.fromJson(input);
    if (dispatch != null) {
      return dispatch!(parsed.serverName, parsed.toolName, parsed.arguments);
    }
    return ToolResult.error(
      'No MCP dispatch configured for '
      '${parsed.serverName}/${parsed.toolName}',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// LspTool — query Language Server Protocol
// ═══════════════════════════════════════════════════════════════════════════

class LspToolInput {
  final String action; // diagnostics, hover, definition, references, completions
  final String filePath;
  final int? line;
  final int? column;

  LspToolInput({
    required this.action,
    required this.filePath,
    this.line,
    this.column,
  });

  factory LspToolInput.fromJson(Map<String, dynamic> json) => LspToolInput(
        action: json['action'] as String,
        filePath: json['file_path'] as String,
        line: json['line'] as int?,
        column: json['column'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'file_path': filePath,
        if (line != null) 'line': line,
        if (column != null) 'column': column,
      };
}

class LspToolOutput {
  final List<Map<String, dynamic>>? results;
  final List<Map<String, dynamic>>? diagnostics;
  final String? hoverInfo;

  const LspToolOutput({this.results, this.diagnostics, this.hoverInfo});

  @override
  String toString() {
    if (hoverInfo != null) return hoverInfo!;
    if (diagnostics != null && diagnostics!.isNotEmpty) {
      return diagnostics!
          .map((d) =>
              '${d['severity']}: ${d['message']} (${d['line']}:${d['column']})')
          .join('\n');
    }
    if (results != null && results!.isNotEmpty) {
      return const JsonEncoder.withIndent('  ').convert(results);
    }
    return 'No results';
  }
}

class LspTool extends Tool with ReadOnlyToolMixin {
  /// LSP client callback. Injected by the host.
  final Future<ToolResult> Function(LspToolInput input)? lspClient;

  LspTool({this.lspClient});

  @override
  String get name => 'LSP';

  @override
  String get description =>
      'Query a Language Server Protocol server for diagnostics, hover info, '
      'go-to-definition, find references, and completions.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': [
              'diagnostics',
              'hover',
              'definition',
              'references',
              'completions'
            ],
            'description': 'LSP action to perform',
          },
          'file_path': {
            'type': 'string',
            'description': 'Absolute path to the source file',
          },
          'line': {
            'type': 'integer',
            'description': 'Line number (1-based)',
          },
          'column': {
            'type': 'integer',
            'description': 'Column number (1-based)',
          },
        },
        'required': ['action', 'file_path'],
      };

  static const _positionActions = {
    'hover',
    'definition',
    'references',
    'completions'
  };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final action = input['action'] as String?;
    if (action == null) {
      return const ValidationResult.invalid('action is required');
    }
    if (!['diagnostics', 'hover', 'definition', 'references', 'completions']
        .contains(action)) {
      return const ValidationResult.invalid(
          'action must be diagnostics, hover, definition, references, or completions');
    }
    if (input['file_path'] == null) {
      return const ValidationResult.invalid('file_path is required');
    }
    if (_positionActions.contains(action)) {
      if (input['line'] == null || input['column'] == null) {
        return ValidationResult.invalid(
            'line and column are required for $action');
      }
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = LspToolInput.fromJson(input);
    if (lspClient != null) {
      return lspClient!(parsed);
    }
    return ToolResult.error(
        'No LSP client configured. Wire up an LSP server to use this tool.');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ConfigTool — read/write configuration values
// ═══════════════════════════════════════════════════════════════════════════

class ConfigToolInput {
  final String action; // get, set, list, reset
  final String? key;
  final dynamic value;
  final String scope; // user, project, local

  ConfigToolInput({
    required this.action,
    this.key,
    this.value,
    this.scope = 'user',
  });

  factory ConfigToolInput.fromJson(Map<String, dynamic> json) =>
      ConfigToolInput(
        action: json['action'] as String,
        key: json['key'] as String?,
        value: json['value'],
        scope: json['scope'] as String? ?? 'user',
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        if (key != null) 'key': key,
        if (value != null) 'value': value,
        'scope': scope,
      };
}

class ConfigToolOutput {
  final dynamic value;
  final Map<String, dynamic>? allValues;
  final bool success;

  const ConfigToolOutput({this.value, this.allValues, required this.success});

  @override
  String toString() {
    if (allValues != null) {
      return const JsonEncoder.withIndent('  ').convert(allValues);
    }
    return value?.toString() ?? (success ? 'OK' : 'Failed');
  }
}

class ConfigTool extends Tool {
  final Map<String, Map<String, dynamic>> _stores = {
    'user': <String, dynamic>{},
    'project': <String, dynamic>{},
    'local': <String, dynamic>{},
  };

  /// Optional external config provider. Injected by host.
  final Future<ToolResult> Function(ConfigToolInput input)? provider;

  ConfigTool({this.provider});

  @override
  String get name => 'Config';

  @override
  String get description =>
      'Read or write configuration values. Supports user, project, '
      'and local scopes.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['get', 'set', 'list', 'reset'],
            'description': 'Config operation to perform',
          },
          'key': {
            'type': 'string',
            'description': 'Configuration key (dot-notation supported)',
          },
          'value': {
            'description': 'Value to set (for set action)',
          },
          'scope': {
            'type': 'string',
            'enum': ['user', 'project', 'local'],
            'description': 'Configuration scope (default: user)',
          },
        },
        'required': ['action'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final action = input['action'] as String?;
    if (action == null ||
        !['get', 'set', 'list', 'reset'].contains(action)) {
      return const ValidationResult.invalid(
          'action must be get, set, list, or reset');
    }
    if ((action == 'get' || action == 'set' || action == 'reset') &&
        input['key'] == null) {
      return ValidationResult.invalid('key is required for $action');
    }
    if (action == 'set' && input['value'] == null) {
      return const ValidationResult.invalid('value is required for set');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = ConfigToolInput.fromJson(input);
    if (provider != null) return provider!(parsed);

    final store = _stores[parsed.scope] ?? _stores['user']!;

    switch (parsed.action) {
      case 'get':
        final val = store[parsed.key];
        return val != null
            ? ToolResult.success(val.toString())
            : ToolResult.error('Key not found: ${parsed.key}');

      case 'set':
        store[parsed.key!] = parsed.value;
        return ToolResult.success('Set ${parsed.key} = ${parsed.value}');

      case 'list':
        final out = ConfigToolOutput(allValues: store, success: true);
        return ToolResult.success(out.toString());

      case 'reset':
        final existed = store.containsKey(parsed.key);
        store.remove(parsed.key);
        return existed
            ? ToolResult.success('Reset ${parsed.key}')
            : ToolResult.error('Key not found: ${parsed.key}');

      default:
        return ToolResult.error('Unknown action: ${parsed.action}');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// MemoryTool — read/write to NEOMCLAW.md memory files
// ═══════════════════════════════════════════════════════════════════════════

class MemoryToolInput {
  final String action; // read, write, append, list
  final String? path;
  final String? content;

  MemoryToolInput({required this.action, this.path, this.content});

  factory MemoryToolInput.fromJson(Map<String, dynamic> json) =>
      MemoryToolInput(
        action: json['action'] as String,
        path: json['path'] as String?,
        content: json['content'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        if (path != null) 'path': path,
        if (content != null) 'content': content,
      };
}

class MemoryToolOutput {
  final String? content;
  final List<String>? memories;
  final bool success;

  const MemoryToolOutput({this.content, this.memories, required this.success});

  @override
  String toString() {
    if (content != null) return content!;
    if (memories != null) return memories!.join('\n');
    return success ? 'OK' : 'Failed';
  }
}

class MemoryTool extends Tool with FileWriteToolMixin {
  @override
  String get name => 'Memory';

  @override
  String get description =>
      'Read, write, or append to NEOMCLAW.md memory files. '
      'Memory files persist context across sessions.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': ['read', 'write', 'append', 'list'],
            'description': 'Memory operation to perform',
          },
          'path': {
            'type': 'string',
            'description':
                'Path to the memory file (relative to project root)',
          },
          'content': {
            'type': 'string',
            'description': 'Content to write or append',
          },
        },
        'required': ['action'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final action = input['action'] as String?;
    if (action == null ||
        !['read', 'write', 'append', 'list'].contains(action)) {
      return const ValidationResult.invalid(
          'action must be read, write, append, or list');
    }
    if (action != 'list' && (input['path'] == null)) {
      return ValidationResult.invalid('path is required for $action');
    }
    if ((action == 'write' || action == 'append') &&
        input['content'] == null) {
      return ValidationResult.invalid('content is required for $action');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = MemoryToolInput.fromJson(input);

    switch (parsed.action) {
      case 'read':
        final file = File(parsed.path!);
        if (!await file.exists()) {
          return ToolResult.error('Memory file not found: ${parsed.path}');
        }
        final content = await file.readAsString();
        return ToolResult.success(content);

      case 'write':
        final file = File(parsed.path!);
        await file.parent.create(recursive: true);
        await file.writeAsString(parsed.content!);
        return ToolResult.success('Memory written to ${parsed.path}');

      case 'append':
        final file = File(parsed.path!);
        await file.parent.create(recursive: true);
        await file.writeAsString(
          parsed.content!,
          mode: FileMode.append,
        );
        return ToolResult.success('Appended to ${parsed.path}');

      case 'list':
        // List NEOMCLAW.md files in common locations.
        final candidates = [
          'NEOMCLAW.md',
          '.neomclaw/NEOMCLAW.md',
          '.neomclaw/memory/',
        ];
        final found = <String>[];
        for (final c in candidates) {
          final entity = FileSystemEntity.typeSync(c);
          if (entity == FileSystemEntityType.file) {
            found.add(c);
          } else if (entity == FileSystemEntityType.directory) {
            await for (final f in Directory(c).list()) {
              if (f is File && f.path.endsWith('.md')) {
                found.add(f.path);
              }
            }
          }
        }
        return found.isEmpty
            ? ToolResult.success('No memory files found')
            : ToolResult.success(found.join('\n'));

      default:
        return ToolResult.error('Unknown action: ${parsed.action}');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DiffApplyTool — apply a unified diff to a file
// ═══════════════════════════════════════════════════════════════════════════

class DiffApplyInput {
  final String filePath;
  final String diffContent;

  DiffApplyInput({required this.filePath, required this.diffContent});

  factory DiffApplyInput.fromJson(Map<String, dynamic> json) => DiffApplyInput(
        filePath: json['file_path'] as String,
        diffContent: json['diff_content'] as String,
      );

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
        'diff_content': diffContent,
      };
}

class DiffApplyOutput {
  final bool success;
  final int linesChanged;
  final String newContent;

  const DiffApplyOutput({
    required this.success,
    required this.linesChanged,
    required this.newContent,
  });

  @override
  String toString() => success
      ? 'Applied diff: $linesChanged lines changed'
      : 'Diff apply failed';
}

class DiffApplyTool extends Tool with FileWriteToolMixin {
  @override
  String get name => 'DiffApply';

  @override
  String get description =>
      'Apply a unified diff to a file. The diff should be in standard '
      'unified diff format (output of diff -u or git diff).';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'Absolute path to the file to patch',
          },
          'diff_content': {
            'type': 'string',
            'description': 'Unified diff content to apply',
          },
        },
        'required': ['file_path', 'diff_content'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    if (input['file_path'] == null ||
        (input['file_path'] as String).isEmpty) {
      return const ValidationResult.invalid('file_path is required');
    }
    if (input['diff_content'] == null ||
        (input['diff_content'] as String).isEmpty) {
      return const ValidationResult.invalid('diff_content is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = DiffApplyInput.fromJson(input);
    final file = File(parsed.filePath);

    if (!await file.exists()) {
      return ToolResult.error('File not found: ${parsed.filePath}');
    }

    try {
      final originalLines = await file.readAsLines();
      final patchedLines = _applyUnifiedDiff(originalLines, parsed.diffContent);
      final newContent = patchedLines.join('\n');
      await file.writeAsString(
          newContent.endsWith('\n') ? newContent : '$newContent\n');

      final changed = (patchedLines.length - originalLines.length).abs() +
          _countChangedLines(originalLines, patchedLines);

      final out =
          DiffApplyOutput(success: true, linesChanged: changed, newContent: newContent);
      return ToolResult.success(out.toString());
    } catch (e) {
      return ToolResult.error('Error applying diff: $e');
    }
  }

  List<String> _applyUnifiedDiff(List<String> original, String diff) {
    final result = List<String>.from(original);
    final hunks = _parseHunks(diff);
    var offset = 0;

    for (final hunk in hunks) {
      final startLine = hunk.originalStart - 1 + offset;
      var pos = startLine;

      for (final line in hunk.lines) {
        if (line.startsWith('-')) {
          if (pos < result.length) {
            result.removeAt(pos);
            offset--;
          }
        } else if (line.startsWith('+')) {
          result.insert(pos, line.substring(1));
          pos++;
          offset++;
        } else {
          // context line
          pos++;
        }
      }
    }

    return result;
  }

  List<_DiffHunk> _parseHunks(String diff) {
    final hunks = <_DiffHunk>[];
    final lines = diff.split('\n');
    _DiffHunk? current;

    for (final line in lines) {
      final hunkMatch =
          RegExp(r'^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@').firstMatch(line);
      if (hunkMatch != null) {
        current = _DiffHunk(
          originalStart: int.parse(hunkMatch.group(1)!),
          newStart: int.parse(hunkMatch.group(2)!),
        );
        hunks.add(current);
        continue;
      }
      if (current != null &&
          (line.startsWith('+') ||
              line.startsWith('-') ||
              line.startsWith(' '))) {
        current.lines.add(line);
      }
    }
    return hunks;
  }

  int _countChangedLines(List<String> a, List<String> b) {
    var changes = 0;
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      if (a[i] != b[i]) changes++;
    }
    return changes;
  }
}

class _DiffHunk {
  final int originalStart;
  final int newStart;
  final List<String> lines = [];

  _DiffHunk({required this.originalStart, required this.newStart});
}

// ═══════════════════════════════════════════════════════════════════════════
// MultiEditTool — apply multiple edits to a file atomically
// ═══════════════════════════════════════════════════════════════════════════

class MultiEditEntry {
  final String oldText;
  final String newText;

  const MultiEditEntry({required this.oldText, required this.newText});

  factory MultiEditEntry.fromJson(Map<String, dynamic> json) => MultiEditEntry(
        oldText: json['old_text'] as String,
        newText: json['new_text'] as String,
      );

  Map<String, dynamic> toJson() => {'old_text': oldText, 'new_text': newText};
}

class MultiEditInput {
  final String filePath;
  final List<MultiEditEntry> edits;

  MultiEditInput({required this.filePath, required this.edits});

  factory MultiEditInput.fromJson(Map<String, dynamic> json) => MultiEditInput(
        filePath: json['file_path'] as String,
        edits: (json['edits'] as List)
            .map((e) => MultiEditEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'file_path': filePath,
        'edits': edits.map((e) => e.toJson()).toList(),
      };
}

class MultiEditOutput {
  final bool success;
  final int editsApplied;
  final String newContent;

  const MultiEditOutput({
    required this.success,
    required this.editsApplied,
    required this.newContent,
  });

  @override
  String toString() => success
      ? 'Applied $editsApplied edits successfully'
      : 'Multi-edit failed';
}

class MultiEditTool extends Tool with FileWriteToolMixin {
  @override
  String get name => 'MultiEdit';

  @override
  String get description =>
      'Apply multiple string replacements to a file atomically. '
      'All edits succeed or none are applied.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'Absolute path to the file to edit',
          },
          'edits': {
            'type': 'array',
            'description': 'List of {old_text, new_text} replacements',
            'items': {
              'type': 'object',
              'properties': {
                'old_text': {
                  'type': 'string',
                  'description': 'Text to find',
                },
                'new_text': {
                  'type': 'string',
                  'description': 'Replacement text',
                },
              },
              'required': ['old_text', 'new_text'],
            },
          },
        },
        'required': ['file_path', 'edits'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    if (input['file_path'] == null) {
      return const ValidationResult.invalid('file_path is required');
    }
    final edits = input['edits'];
    if (edits == null || edits is! List || edits.isEmpty) {
      return const ValidationResult.invalid(
          'edits must be a non-empty array');
    }
    for (var i = 0; i < edits.length; i++) {
      final e = edits[i] as Map<String, dynamic>;
      if (e['old_text'] == null || e['new_text'] == null) {
        return ValidationResult.invalid(
            'Edit $i missing old_text or new_text');
      }
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = MultiEditInput.fromJson(input);
    final file = File(parsed.filePath);

    if (!await file.exists()) {
      return ToolResult.error('File not found: ${parsed.filePath}');
    }

    try {
      var content = await file.readAsString();
      final original = content;

      // Verify all edits can be applied before making changes.
      for (var i = 0; i < parsed.edits.length; i++) {
        if (!content.contains(parsed.edits[i].oldText)) {
          return ToolResult.error(
              'Edit $i: old_text not found in file. '
              'No edits were applied (atomic).');
        }
      }

      // Apply edits sequentially.
      var applied = 0;
      for (final edit in parsed.edits) {
        content = content.replaceFirst(edit.oldText, edit.newText);
        applied++;
      }

      if (content == original) {
        return ToolResult.success('No changes made (all edits were no-ops)');
      }

      await file.writeAsString(content);
      final out = MultiEditOutput(
        success: true,
        editsApplied: applied,
        newContent: content,
      );
      return ToolResult.success(out.toString());
    } catch (e) {
      return ToolResult.error('Error during multi-edit: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// SubagentTool — create and manage sub-agents
// ═══════════════════════════════════════════════════════════════════════════

class SubagentInput {
  final String name;
  final String role;
  final String? model;
  final String? systemPrompt;
  final List<String>? tools;
  final String task;

  SubagentInput({
    required this.name,
    required this.role,
    this.model,
    this.systemPrompt,
    this.tools,
    required this.task,
  });

  factory SubagentInput.fromJson(Map<String, dynamic> json) => SubagentInput(
        name: json['name'] as String,
        role: json['role'] as String,
        model: json['model'] as String?,
        systemPrompt: json['system_prompt'] as String?,
        tools: (json['tools'] as List?)?.cast<String>(),
        task: json['task'] as String,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'role': role,
        if (model != null) 'model': model,
        if (systemPrompt != null) 'system_prompt': systemPrompt,
        if (tools != null) 'tools': tools,
        'task': task,
      };
}

class SubagentOutput {
  final String agentId;
  final String result;
  final String status; // running, completed, failed

  const SubagentOutput({
    required this.agentId,
    required this.result,
    required this.status,
  });

  @override
  String toString() => '[$status] Agent "$agentId": $result';
}

class SubagentTool extends Tool {
  /// Callback to spawn sub-agents. Injected by the host.
  final Future<ToolResult> Function(SubagentInput input)? spawner;

  SubagentTool({this.spawner});

  @override
  String get name => 'Subagent';

  @override
  String get description =>
      'Create a sub-agent with a specific role and set of tools to '
      'execute a task. Sub-agents run in their own context.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'name': {
            'type': 'string',
            'description': 'A short name for the sub-agent',
          },
          'role': {
            'type': 'string',
            'description':
                'The role of the agent (e.g. "code_reviewer", "test_writer")',
          },
          'model': {
            'type': 'string',
            'description': 'Model to use (default: same as parent)',
          },
          'system_prompt': {
            'type': 'string',
            'description': 'System prompt for the sub-agent',
          },
          'tools': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Tool names available to the sub-agent',
          },
          'task': {
            'type': 'string',
            'description': 'The task for the sub-agent to perform',
          },
        },
        'required': ['name', 'role', 'task'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    if (input['name'] == null || (input['name'] as String).isEmpty) {
      return const ValidationResult.invalid('name is required');
    }
    if (input['role'] == null || (input['role'] as String).isEmpty) {
      return const ValidationResult.invalid('role is required');
    }
    if (input['task'] == null || (input['task'] as String).isEmpty) {
      return const ValidationResult.invalid('task is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = SubagentInput.fromJson(input);
    if (spawner != null) return spawner!(parsed);

    // Stub: real implementation would spawn an agent session.
    final agentId = '${parsed.name}_${DateTime.now().millisecondsSinceEpoch}';
    return ToolResult.success(
      'Sub-agent "$agentId" created with role "${parsed.role}". '
      'Task queued: ${parsed.task}',
      metadata: {
        'agent_id': agentId,
        'status': 'queued',
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ScreenshotTool — take a screenshot of a running application
// ═══════════════════════════════════════════════════════════════════════════

class ScreenshotInput {
  final String? url;
  final String? selector;
  final int viewportWidth;
  final int viewportHeight;

  ScreenshotInput({
    this.url,
    this.selector,
    this.viewportWidth = 1280,
    this.viewportHeight = 800,
  });

  factory ScreenshotInput.fromJson(Map<String, dynamic> json) =>
      ScreenshotInput(
        url: json['url'] as String?,
        selector: json['selector'] as String?,
        viewportWidth: json['viewport_width'] as int? ?? 1280,
        viewportHeight: json['viewport_height'] as int? ?? 800,
      );

  Map<String, dynamic> toJson() => {
        if (url != null) 'url': url,
        if (selector != null) 'selector': selector,
        'viewport_width': viewportWidth,
        'viewport_height': viewportHeight,
      };
}

class ScreenshotOutput {
  final String imageData; // base64
  final String format;
  final Map<String, int> dimensions;

  const ScreenshotOutput({
    required this.imageData,
    required this.format,
    required this.dimensions,
  });

  @override
  String toString() =>
      'Screenshot captured: ${dimensions['width']}x${dimensions['height']} ($format)';
}

class ScreenshotTool extends Tool with ReadOnlyToolMixin {
  /// Screenshot capture callback. Injected by the host.
  final Future<ToolResult> Function(ScreenshotInput input)? capturer;

  ScreenshotTool({this.capturer});

  @override
  String get name => 'Screenshot';

  @override
  String get description =>
      'Take a screenshot of a running application or web page. '
      'Returns a base64-encoded image.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'url': {
            'type': 'string',
            'description': 'URL to capture',
          },
          'selector': {
            'type': 'string',
            'description': 'CSS selector to capture a specific element',
          },
          'viewport_width': {
            'type': 'integer',
            'description': 'Viewport width in pixels (default: 1280)',
          },
          'viewport_height': {
            'type': 'integer',
            'description': 'Viewport height in pixels (default: 800)',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = ScreenshotInput.fromJson(input);
    if (capturer != null) return capturer!(parsed);

    return ToolResult.error(
      'No screenshot capturer configured. '
      'Wire up a browser/preview engine to use this tool.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ComputerUseTool — GUI automation via mouse/keyboard
// ═══════════════════════════════════════════════════════════════════════════

class ComputerUseInput {
  final String action; // click, type, scroll, screenshot, key, double_click, drag
  final List<int>? coordinates; // [x, y]
  final String? text;
  final String? key;
  final String? scrollDirection; // up, down, left, right
  final int? scrollAmount;

  ComputerUseInput({
    required this.action,
    this.coordinates,
    this.text,
    this.key,
    this.scrollDirection,
    this.scrollAmount,
  });

  factory ComputerUseInput.fromJson(Map<String, dynamic> json) =>
      ComputerUseInput(
        action: json['action'] as String,
        coordinates: (json['coordinates'] as List?)?.cast<int>(),
        text: json['text'] as String?,
        key: json['key'] as String?,
        scrollDirection: json['scroll_direction'] as String?,
        scrollAmount: json['scroll_amount'] as int?,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        if (coordinates != null) 'coordinates': coordinates,
        if (text != null) 'text': text,
        if (key != null) 'key': key,
        if (scrollDirection != null) 'scroll_direction': scrollDirection,
        if (scrollAmount != null) 'scroll_amount': scrollAmount,
      };
}

class ComputerUseOutput {
  final bool success;
  final String? screenshotData; // base64

  const ComputerUseOutput({required this.success, this.screenshotData});

  @override
  String toString() {
    if (screenshotData != null) {
      return 'Action completed. Screenshot captured '
          '(${screenshotData!.length} chars base64)';
    }
    return success ? 'Action completed' : 'Action failed';
  }
}

class ComputerUseTool extends Tool {
  /// GUI automation callback. Injected by the host.
  final Future<ToolResult> Function(ComputerUseInput input)? automator;

  ComputerUseTool({this.automator});

  @override
  String get name => 'ComputerUse';

  @override
  String get description =>
      'Interact with a graphical user interface via mouse clicks, '
      'keyboard input, scrolling, and screenshots.';

  @override
  bool get isDestructive => true;

  @override
  bool get requiresUserInteraction => true;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'action': {
            'type': 'string',
            'enum': [
              'click',
              'double_click',
              'type',
              'scroll',
              'screenshot',
              'key',
              'drag'
            ],
            'description': 'GUI action to perform',
          },
          'coordinates': {
            'type': 'array',
            'items': {'type': 'integer'},
            'description': '[x, y] pixel coordinates for click/drag',
          },
          'text': {
            'type': 'string',
            'description': 'Text to type',
          },
          'key': {
            'type': 'string',
            'description': 'Key or shortcut to press (e.g. "Enter", "ctrl+c")',
          },
          'scroll_direction': {
            'type': 'string',
            'enum': ['up', 'down', 'left', 'right'],
            'description': 'Scroll direction',
          },
          'scroll_amount': {
            'type': 'integer',
            'description': 'Number of scroll ticks (default: 3)',
          },
        },
        'required': ['action'],
      };

  static const _coordActions = {'click', 'double_click', 'drag'};

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final action = input['action'] as String?;
    if (action == null) {
      return const ValidationResult.invalid('action is required');
    }
    if (_coordActions.contains(action) && input['coordinates'] == null) {
      return ValidationResult.invalid(
          'coordinates [x, y] required for $action');
    }
    if (action == 'type' && input['text'] == null) {
      return const ValidationResult.invalid('text is required for type');
    }
    if (action == 'key' && input['key'] == null) {
      return const ValidationResult.invalid('key is required for key action');
    }
    if (action == 'scroll' && input['scroll_direction'] == null) {
      return const ValidationResult.invalid(
          'scroll_direction required for scroll');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = ComputerUseInput.fromJson(input);
    if (automator != null) return automator!(parsed);

    return ToolResult.error(
      'No GUI automator configured. '
      'Wire up a computer-use backend to use this tool.',
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ValidateTool — validate code, configs, and schemas
// ═══════════════════════════════════════════════════════════════════════════

class ValidateInput {
  final String? filePath;
  final String? content;
  final String validatorType; // json, yaml, toml, xml, schema

  ValidateInput({this.filePath, this.content, required this.validatorType});

  factory ValidateInput.fromJson(Map<String, dynamic> json) => ValidateInput(
        filePath: json['file_path'] as String?,
        content: json['content'] as String?,
        validatorType: json['validator_type'] as String,
      );

  Map<String, dynamic> toJson() => {
        if (filePath != null) 'file_path': filePath,
        if (content != null) 'content': content,
        'validator_type': validatorType,
      };
}

class ValidateOutput {
  final bool valid;
  final List<String> errors;
  final List<String> warnings;

  const ValidateOutput({
    required this.valid,
    this.errors = const [],
    this.warnings = const [],
  });

  @override
  String toString() {
    final parts = <String>[];
    parts.add(valid ? 'Valid' : 'Invalid');
    for (final e in errors) {
      parts.add('  ERROR: $e');
    }
    for (final w in warnings) {
      parts.add('  WARN: $w');
    }
    return parts.join('\n');
  }
}

class ValidateTool extends Tool with ReadOnlyToolMixin {
  @override
  String get name => 'Validate';

  @override
  String get description =>
      'Validate code or configuration content. Supports JSON, YAML, '
      'TOML, XML, and JSON Schema validation.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'Path to file to validate (alternative to content)',
          },
          'content': {
            'type': 'string',
            'description': 'Inline content to validate',
          },
          'validator_type': {
            'type': 'string',
            'enum': ['json', 'yaml', 'toml', 'xml', 'schema'],
            'description': 'Type of validation to perform',
          },
        },
        'required': ['validator_type'],
      };

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final vt = input['validator_type'] as String?;
    if (vt == null ||
        !['json', 'yaml', 'toml', 'xml', 'schema'].contains(vt)) {
      return const ValidationResult.invalid(
          'validator_type must be json, yaml, toml, xml, or schema');
    }
    if (input['file_path'] == null && input['content'] == null) {
      return const ValidationResult.invalid(
          'Either file_path or content is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = ValidateInput.fromJson(input);
    String content;

    if (parsed.content != null) {
      content = parsed.content!;
    } else {
      final file = File(parsed.filePath!);
      if (!await file.exists()) {
        return ToolResult.error('File not found: ${parsed.filePath}');
      }
      content = await file.readAsString();
    }

    switch (parsed.validatorType) {
      case 'json':
        return _validateJson(content);
      case 'yaml':
        return _validateYaml(content);
      case 'toml':
        return _validateToml(content);
      case 'xml':
        return _validateXml(content);
      case 'schema':
        return _validateSchema(content);
      default:
        return ToolResult.error(
            'Unsupported validator: ${parsed.validatorType}');
    }
  }

  ToolResult _validateJson(String content) {
    try {
      jsonDecode(content);
      return ToolResult.success(
          const ValidateOutput(valid: true).toString());
    } on FormatException catch (e) {
      return ToolResult.success(
        ValidateOutput(
          valid: false,
          errors: ['JSON parse error: ${e.message} at offset ${e.offset}'],
        ).toString(),
      );
    }
  }

  ToolResult _validateYaml(String content) {
    // Basic YAML structural checks without importing a YAML package.
    final errors = <String>[];
    final warnings = <String>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.contains('\t')) {
        errors.add('Line ${i + 1}: tabs are not allowed in YAML');
      }
      // Check for inconsistent indentation (basic heuristic).
      if (line.trimLeft() != line &&
          line.indexOf(RegExp(r'\S')) % 2 != 0 &&
          !line.trimLeft().startsWith('-') &&
          !line.trimLeft().startsWith('#')) {
        warnings.add('Line ${i + 1}: odd indentation level');
      }
    }

    return ToolResult.success(
      ValidateOutput(
        valid: errors.isEmpty,
        errors: errors,
        warnings: warnings,
      ).toString(),
    );
  }

  ToolResult _validateToml(String content) {
    // Basic TOML structural validation.
    final errors = <String>[];
    final lines = content.split('\n');

    for (var i = 0; i < lines.length; i++) {
      final trimmed = lines[i].trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

      // Check table headers.
      if (trimmed.startsWith('[')) {
        if (!trimmed.endsWith(']')) {
          errors.add('Line ${i + 1}: unclosed table header');
        }
        continue;
      }

      // Check key-value pairs.
      if (!trimmed.contains('=') && !trimmed.startsWith('[')) {
        errors.add('Line ${i + 1}: expected key = value or table header');
      }
    }

    return ToolResult.success(
      ValidateOutput(valid: errors.isEmpty, errors: errors).toString(),
    );
  }

  ToolResult _validateXml(String content) {
    final errors = <String>[];
    final tagStack = <String>[];
    final tagPattern = RegExp(r'<(/?)(\w[\w\-.]*)([^>]*?)(/?)>');

    for (final match in tagPattern.allMatches(content)) {
      final isClosing = match.group(1) == '/';
      final tagName = match.group(2)!;
      final isSelfClosing = match.group(4) == '/';

      if (isSelfClosing) continue;

      if (isClosing) {
        if (tagStack.isEmpty) {
          errors.add('Unexpected closing tag: </$tagName>');
        } else if (tagStack.last != tagName) {
          errors.add(
              'Mismatched tag: expected </${tagStack.last}>, found </$tagName>');
          tagStack.removeLast();
        } else {
          tagStack.removeLast();
        }
      } else {
        tagStack.add(tagName);
      }
    }

    for (final tag in tagStack) {
      errors.add('Unclosed tag: <$tag>');
    }

    return ToolResult.success(
      ValidateOutput(valid: errors.isEmpty, errors: errors).toString(),
    );
  }

  ToolResult _validateSchema(String content) {
    // Validate that content is valid JSON Schema.
    try {
      final schema = jsonDecode(content) as Map<String, dynamic>;
      final warnings = <String>[];

      if (!schema.containsKey('type') && !schema.containsKey('\$ref')) {
        warnings.add('Schema has no "type" or "\$ref" at root level');
      }
      if (schema.containsKey('properties') && schema['type'] != 'object') {
        warnings.add('"properties" defined but type is not "object"');
      }
      if (schema.containsKey('items') && schema['type'] != 'array') {
        warnings.add('"items" defined but type is not "array"');
      }

      return ToolResult.success(
        ValidateOutput(valid: true, warnings: warnings).toString(),
      );
    } on FormatException catch (e) {
      return ToolResult.success(
        ValidateOutput(
          valid: false,
          errors: ['Not valid JSON: ${e.message}'],
        ).toString(),
      );
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tool Schema Generator
// ═══════════════════════════════════════════════════════════════════════════

/// Get the JSON schema for any extended tool by name.
Map<String, dynamic> getToolSchema(String toolName) {
  final tool = _allExtendedTools[toolName];
  if (tool == null) {
    return {'error': 'Unknown tool: $toolName'};
  }
  return {
    'name': tool.name,
    'description': tool.description,
    'input_schema': tool.inputSchema,
  };
}

final Map<String, Tool> _allExtendedTools = {
  for (final t in _createAllExtendedTools()) t.name: t,
};

List<Tool> _createAllExtendedTools() => [
      NotebookEditTool(),
      ExitPlanModeTool(),
      PowerShellTool(),
      SkillTool(),
      McpTool(),
      LspTool(),
      ConfigTool(),
      MemoryTool(),
      DiffApplyTool(),
      MultiEditTool(),
      SubagentTool(),
      ScreenshotTool(),
      ComputerUseTool(),
      ValidateTool(),
    ];

// ═══════════════════════════════════════════════════════════════════════════
// Tool Registry Helper
// ═══════════════════════════════════════════════════════════════════════════

/// Get all extended tool definitions for API registration.
List<ToolDefinition> getAllExtendedToolDefinitions() =>
    _createAllExtendedTools()
        .where((t) => t.isAvailable)
        .map((t) => t.definition)
        .toList();

/// Register all extended tools into a ToolRegistry.
void registerAllExtendedTools(dynamic registry) {
  for (final tool in _createAllExtendedTools()) {
    if (tool.isAvailable) {
      // Uses duck-typed register(Tool) to avoid circular import.
      (registry as dynamic).register(tool);
    }
  }
}
