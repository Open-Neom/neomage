// NotebookEditTool — full port of NeomClaw's NotebookEdit tool.
// Parse, validate, and modify Jupyter notebook (.ipynb) cells.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

import 'tool.dart';

// ─── Input ───────────────────────────────────────────────────────────────────

/// Parsed input for NotebookEdit operations.
class NotebookEditInput {
  final String notebookPath;

  /// One of: add, edit, delete, move.
  final String command;

  /// Zero-based index of the target cell.
  final int cellIndex;

  /// Cell type: code, markdown, or raw.
  final String? cellType;

  /// New source content for add/edit.
  final String? source;

  /// Destination index for move operations.
  final int? newIndex;

  const NotebookEditInput({
    required this.notebookPath,
    required this.command,
    required this.cellIndex,
    this.cellType,
    this.source,
    this.newIndex,
  });

  factory NotebookEditInput.fromMap(Map<String, dynamic> map) {
    return NotebookEditInput(
      notebookPath: map['notebook_path'] as String? ?? '',
      command: map['command'] as String? ?? '',
      cellIndex: (map['cell_index'] as num?)?.toInt() ?? 0,
      cellType: map['cell_type'] as String?,
      source: map['source'] as String? ?? map['content'] as String?,
      newIndex:
          (map['new_index'] as num?)?.toInt() ??
          (map['target_index'] as num?)?.toInt(),
    );
  }

  /// Validate this input, returning a list of error messages (empty = valid).
  List<String> validate() {
    final errors = <String>[];

    if (notebookPath.isEmpty) {
      errors.add('Missing required parameter: notebook_path');
    } else if (!p.isAbsolute(notebookPath)) {
      errors.add('notebook_path must be an absolute path');
    } else if (!notebookPath.endsWith('.ipynb')) {
      errors.add('File must be a .ipynb notebook');
    }

    const validCommands = ['add', 'edit', 'delete', 'move'];
    if (command.isEmpty) {
      errors.add('Missing required parameter: command');
    } else if (!validCommands.contains(command)) {
      errors.add('command must be one of: ${validCommands.join(", ")}');
    }

    if ((command == 'add' || command == 'edit') &&
        (source == null || source!.isEmpty)) {
      errors.add('source/content is required for $command');
    }

    if (command == 'move' && newIndex == null) {
      errors.add('new_index/target_index is required for move');
    }

    if (cellType != null && !['code', 'markdown', 'raw'].contains(cellType)) {
      errors.add('cell_type must be one of: code, markdown, raw');
    }

    return errors;
  }
}

// ─── Output ──────────────────────────────────────────────────────────────────

/// Result data from a notebook edit operation.
class NotebookEditOutput {
  final bool success;
  final String message;
  final int cellCount;

  const NotebookEditOutput({
    required this.success,
    required this.message,
    required this.cellCount,
  });

  Map<String, dynamic> toMetadata() => {
    'success': success,
    'cellCount': cellCount,
  };

  @override
  String toString() =>
      success ? '$message (cells: $cellCount)' : 'Error: $message';
}

// ─── Tool ────────────────────────────────────────────────────────────────────

/// Edit Jupyter notebooks — add, edit, delete, or move cells.
///
/// Features:
/// - Parse and validate .ipynb JSON structure
/// - Add cells at any position (code, markdown, raw)
/// - Edit existing cell content and type
/// - Delete cells by index
/// - Move cells to a new position
/// - Validate cell indices before operations
/// - Preserve notebook metadata and kernel info
/// - Optionally preserve cell outputs
/// - Create backup before editing
/// - Full JSON Schema definition
class NotebookEditTool extends Tool with FileWriteToolMixin {
  /// Whether to preserve cell outputs when editing. Default true.
  final bool preserveOutputs;

  /// Maximum notebook file size (20 MB).
  static const int maxNotebookSize = 20 * 1024 * 1024;

  NotebookEditTool({this.preserveOutputs = true});

  @override
  String get name => 'NotebookEdit';

  @override
  String get description =>
      'Completely replaces the contents of a specific cell in a Jupyter '
      'notebook (.ipynb file) with new source. Supports add, edit, delete, '
      'and move operations on individual cells.';

  @override
  String get prompt =>
      'Edit Jupyter notebook (.ipynb) cells.\n\n'
      'Operations:\n'
      '- add: Insert a new cell at cell_index with the given source and '
      'cell_type (default: code).\n'
      '- edit: Replace the source of the cell at cell_index. Optionally '
      'change cell_type.\n'
      '- delete: Remove the cell at cell_index.\n'
      '- move: Move the cell at cell_index to new_index.\n\n'
      'The notebook_path must be an absolute path to a .ipynb file. '
      'Cell indices are 0-based.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'notebook_path': {
        'type': 'string',
        'description': 'The absolute path to the Jupyter notebook file to edit',
      },
      'command': {
        'type': 'string',
        'enum': ['add', 'edit', 'delete', 'move'],
        'description': 'The operation to perform on the cell',
      },
      'cell_index': {
        'type': 'integer',
        'description':
            'The 0-indexed cell number to operate on. For add, '
            'the new cell is inserted at this position.',
      },
      'cell_type': {
        'type': 'string',
        'enum': ['code', 'markdown', 'raw'],
        'description':
            'The type of the cell. Defaults to code for add. '
            'For edit, changes the cell type if provided.',
      },
      'source': {
        'type': 'string',
        'description': 'The new source content for the cell',
      },
      'new_index': {
        'type': 'integer',
        'description': 'Destination index for move operations',
      },
    },
    'required': ['notebook_path', 'command'],
    'additionalProperties': false,
  };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final path = input['notebook_path'] as String? ?? '';
    final cmd = input['command'] as String? ?? '';
    return 'NotebookEdit $cmd ${p.basename(path)}';
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final cmd = input['command'] as String? ?? 'editing';
    return '${cmd[0].toUpperCase()}${cmd.substring(1)}ing notebook cell';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = NotebookEditInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ValidationResult.invalid(errors.first);
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final validation = validateInput(input);
    if (!validation.isValid) return ToolResult.error(validation.error!);

    final parsed = NotebookEditInput.fromMap(input);
    final file = File(parsed.notebookPath);

    // Check existence.
    if (!await file.exists()) {
      return ToolResult.error('Notebook not found: ${parsed.notebookPath}');
    }

    // Check size.
    final stat = await file.stat();
    if (stat.size > maxNotebookSize) {
      return ToolResult.error(
        'Notebook too large: '
        '${(stat.size / (1024 * 1024)).toStringAsFixed(1)} MB '
        '(max ${maxNotebookSize ~/ (1024 * 1024)} MB)',
      );
    }

    // Parse notebook JSON.
    final Map<String, dynamic> notebook;
    try {
      final raw = await file.readAsString();
      notebook = jsonDecode(raw) as Map<String, dynamic>;
    } catch (e) {
      return ToolResult.error('Failed to parse notebook JSON: $e');
    }

    // Validate notebook structure.
    if (!notebook.containsKey('cells') || notebook['cells'] is! List) {
      return ToolResult.error(
        'Invalid notebook: missing or malformed "cells" array',
      );
    }

    final cells = (notebook['cells'] as List).cast<Map<String, dynamic>>();

    // Create backup before modifying.
    await _createBackup(file);

    try {
      final result = switch (parsed.command) {
        'add' => _addCell(cells, parsed),
        'edit' => _editCell(cells, parsed),
        'delete' => _deleteCell(cells, parsed),
        'move' => _moveCell(cells, parsed),
        _ => NotebookEditOutput(
          success: false,
          message: 'Unknown command: ${parsed.command}',
          cellCount: cells.length,
        ),
      };

      if (!result.success) {
        return ToolResult.error(result.message);
      }

      // Write updated notebook, preserving metadata and kernel info.
      notebook['cells'] = cells;
      final encoder = const JsonEncoder.withIndent(' ');
      await file.writeAsString(encoder.convert(notebook));

      return ToolResult.success(
        result.toString(),
        metadata: result.toMetadata(),
      );
    } catch (e) {
      return ToolResult.error('Error editing notebook: $e');
    }
  }

  // ── Cell Operations ──────────────────────────────────────────────────────

  NotebookEditOutput _addCell(
    List<Map<String, dynamic>> cells,
    NotebookEditInput input,
  ) {
    final index = input.cellIndex.clamp(0, cells.length);
    final type = input.cellType ?? 'code';

    final newCell = _buildCell(type, input.source!);
    cells.insert(index, newCell);

    return NotebookEditOutput(
      success: true,
      message: 'Added $type cell at index $index',
      cellCount: cells.length,
    );
  }

  NotebookEditOutput _editCell(
    List<Map<String, dynamic>> cells,
    NotebookEditInput input,
  ) {
    if (!_isValidIndex(input.cellIndex, cells.length)) {
      return NotebookEditOutput(
        success: false,
        message:
            'Cell index ${input.cellIndex} out of range '
            '(0..${cells.length - 1})',
        cellCount: cells.length,
      );
    }

    final cell = cells[input.cellIndex];

    // Update source.
    cell['source'] = _splitSource(input.source!);

    // Optionally change cell type.
    if (input.cellType != null) {
      cell['cell_type'] = input.cellType;
      // Clear outputs if switching away from code.
      if (input.cellType != 'code') {
        cell.remove('outputs');
        cell.remove('execution_count');
      } else if (!cell.containsKey('outputs')) {
        cell['outputs'] = <dynamic>[];
        cell['execution_count'] = null;
      }
    }

    // Optionally clear outputs on edit.
    if (!preserveOutputs && cell['cell_type'] == 'code') {
      cell['outputs'] = <dynamic>[];
      cell['execution_count'] = null;
    }

    return NotebookEditOutput(
      success: true,
      message: 'Edited cell at index ${input.cellIndex}',
      cellCount: cells.length,
    );
  }

  NotebookEditOutput _deleteCell(
    List<Map<String, dynamic>> cells,
    NotebookEditInput input,
  ) {
    if (!_isValidIndex(input.cellIndex, cells.length)) {
      return NotebookEditOutput(
        success: false,
        message:
            'Cell index ${input.cellIndex} out of range '
            '(0..${cells.length - 1})',
        cellCount: cells.length,
      );
    }

    cells.removeAt(input.cellIndex);

    return NotebookEditOutput(
      success: true,
      message: 'Deleted cell at index ${input.cellIndex}',
      cellCount: cells.length,
    );
  }

  NotebookEditOutput _moveCell(
    List<Map<String, dynamic>> cells,
    NotebookEditInput input,
  ) {
    if (!_isValidIndex(input.cellIndex, cells.length)) {
      return NotebookEditOutput(
        success: false,
        message:
            'Source index ${input.cellIndex} out of range '
            '(0..${cells.length - 1})',
        cellCount: cells.length,
      );
    }

    final target = input.newIndex!;
    if (target < 0 || target >= cells.length) {
      return NotebookEditOutput(
        success: false,
        message: 'Target index $target out of range (0..${cells.length - 1})',
        cellCount: cells.length,
      );
    }

    if (input.cellIndex == target) {
      return NotebookEditOutput(
        success: true,
        message: 'Cell already at index $target',
        cellCount: cells.length,
      );
    }

    final cell = cells.removeAt(input.cellIndex);
    cells.insert(target, cell);

    return NotebookEditOutput(
      success: true,
      message: 'Moved cell from index ${input.cellIndex} to $target',
      cellCount: cells.length,
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool _isValidIndex(int index, int length) => index >= 0 && index < length;

  /// Build a new notebook cell structure.
  Map<String, dynamic> _buildCell(String type, String source) {
    final cell = <String, dynamic>{
      'cell_type': type,
      'metadata': <String, dynamic>{},
      'source': _splitSource(source),
    };
    if (type == 'code') {
      cell['outputs'] = <dynamic>[];
      cell['execution_count'] = null;
    }
    return cell;
  }

  /// Split source text into lines as Jupyter expects (list of strings).
  List<String> _splitSource(String source) {
    if (source.isEmpty) return <String>[];
    final lines = source.split('\n');
    return [
      for (var i = 0; i < lines.length; i++)
        i < lines.length - 1 ? '${lines[i]}\n' : lines[i],
    ];
  }

  /// Create a backup of the notebook before editing.
  Future<void> _createBackup(File file) async {
    try {
      final backupPath = '${file.path}.bak';
      await file.copy(backupPath);
    } catch (_) {
      // Non-fatal: continue without backup.
    }
  }
}
