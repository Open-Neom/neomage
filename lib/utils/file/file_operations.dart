// File operations — port of neom_claw/src/utils/file/.
// Multi-edit, diff apply, notebook operations, file validation, backup.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

// ─── Edit operations ───

/// Single edit operation within a file.
class FileEdit {
  final String oldText;
  final String newText;
  final bool replaceAll;

  const FileEdit({
    required this.oldText,
    required this.newText,
    this.replaceAll = false,
  });
}

/// Result of applying edits.
class EditResult {
  final bool success;
  final String newContent;
  final int editsApplied;
  final List<String> errors;
  final String? backupPath;

  const EditResult({
    required this.success,
    required this.newContent,
    required this.editsApplied,
    this.errors = const [],
    this.backupPath,
  });
}

/// Apply multiple edits to a file atomically.
Future<EditResult> applyMultiEdit(
  String filePath,
  List<FileEdit> edits, {
  bool createBackup = true,
  bool dryRun = false,
}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return EditResult(
      success: false,
      newContent: '',
      editsApplied: 0,
      errors: ['File not found: $filePath'],
    );
  }

  var content = await file.readAsString();
  final errors = <String>[];
  var applied = 0;
  String? backupPath;

  // Create backup before editing
  if (createBackup && !dryRun) {
    backupPath = '$filePath.bak.${DateTime.now().millisecondsSinceEpoch}';
    await File(backupPath).writeAsString(content);
  }

  // Apply edits in order
  for (var i = 0; i < edits.length; i++) {
    final edit = edits[i];
    if (edit.replaceAll) {
      if (content.contains(edit.oldText)) {
        content = content.replaceAll(edit.oldText, edit.newText);
        applied++;
      } else {
        errors.add('Edit $i: old_text not found for replaceAll.');
      }
    } else {
      final index = content.indexOf(edit.oldText);
      if (index == -1) {
        errors.add('Edit $i: old_text not found.');
      } else {
        // Check uniqueness
        final secondIndex =
            content.indexOf(edit.oldText, index + edit.oldText.length);
        if (secondIndex != -1) {
          errors.add(
              'Edit $i: old_text is ambiguous (found at offsets $index and $secondIndex).');
        } else {
          content = content.substring(0, index) +
              edit.newText +
              content.substring(index + edit.oldText.length);
          applied++;
        }
      }
    }
  }

  if (!dryRun && applied > 0) {
    await file.writeAsString(content);
  }

  return EditResult(
    success: errors.isEmpty,
    newContent: content,
    editsApplied: applied,
    errors: errors,
    backupPath: backupPath,
  );
}

// ─── Diff apply ───

/// A single hunk in a unified diff.
class DiffHunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });
}

/// Single line in a diff hunk.
class DiffLine {
  final DiffLineType type;
  final String content;

  const DiffLine(this.type, this.content);
}

enum DiffLineType { context, add, remove }

/// Parse a unified diff string into hunks.
List<DiffHunk> parseUnifiedDiff(String diff) {
  final hunks = <DiffHunk>[];
  final lines = diff.split('\n');
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // Find hunk header: @@ -old,count +new,count @@
    final hunkMatch =
        RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')
            .firstMatch(line);
    if (hunkMatch != null) {
      final oldStart = int.parse(hunkMatch.group(1)!);
      final oldCount = int.parse(hunkMatch.group(2) ?? '1');
      final newStart = int.parse(hunkMatch.group(3)!);
      final newCount = int.parse(hunkMatch.group(4) ?? '1');

      final hunkLines = <DiffLine>[];
      i++;

      while (i < lines.length) {
        final l = lines[i];
        if (l.startsWith('@@') || l.startsWith('diff ') || l.startsWith('---') || l.startsWith('+++')) {
          break;
        }
        if (l.startsWith('+')) {
          hunkLines.add(DiffLine(DiffLineType.add, l.substring(1)));
        } else if (l.startsWith('-')) {
          hunkLines.add(DiffLine(DiffLineType.remove, l.substring(1)));
        } else if (l.startsWith(' ')) {
          hunkLines.add(DiffLine(DiffLineType.context, l.substring(1)));
        } else if (l == '\\ No newline at end of file') {
          // Skip
        } else {
          // Treat as context
          hunkLines.add(DiffLine(DiffLineType.context, l));
        }
        i++;
      }

      hunks.add(DiffHunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        lines: hunkLines,
      ));
    } else {
      i++;
    }
  }

  return hunks;
}

/// Apply a unified diff to file content.
String applyDiff(String content, String diff) {
  final hunks = parseUnifiedDiff(diff);
  if (hunks.isEmpty) return content;

  final originalLines = content.split('\n');
  final result = <String>[];
  var srcLine = 0; // 0-based index into originalLines

  for (final hunk in hunks) {
    final hunkStart = hunk.oldStart - 1; // Convert to 0-based

    // Copy lines before this hunk
    while (srcLine < hunkStart && srcLine < originalLines.length) {
      result.add(originalLines[srcLine]);
      srcLine++;
    }

    // Apply hunk
    for (final line in hunk.lines) {
      switch (line.type) {
        case DiffLineType.context:
          // Advance source, copy to result
          if (srcLine < originalLines.length) {
            result.add(originalLines[srcLine]);
            srcLine++;
          }
          break;
        case DiffLineType.remove:
          // Skip source line
          srcLine++;
          break;
        case DiffLineType.add:
          // Add new line to result
          result.add(line.content);
          break;
      }
    }
  }

  // Copy remaining lines
  while (srcLine < originalLines.length) {
    result.add(originalLines[srcLine]);
    srcLine++;
  }

  return result.join('\n');
}

/// Apply a diff to a file.
Future<EditResult> applyDiffToFile(String filePath, String diff,
    {bool createBackup = true}) async {
  final file = File(filePath);
  if (!await file.exists()) {
    return EditResult(
      success: false,
      newContent: '',
      editsApplied: 0,
      errors: ['File not found: $filePath'],
    );
  }

  final content = await file.readAsString();
  String? backupPath;

  if (createBackup) {
    backupPath = '$filePath.bak.${DateTime.now().millisecondsSinceEpoch}';
    await File(backupPath).writeAsString(content);
  }

  try {
    final newContent = applyDiff(content, diff);
    await file.writeAsString(newContent);
    final hunks = parseUnifiedDiff(diff);
    return EditResult(
      success: true,
      newContent: newContent,
      editsApplied: hunks.length,
      backupPath: backupPath,
    );
  } catch (e) {
    return EditResult(
      success: false,
      newContent: content,
      editsApplied: 0,
      errors: ['Failed to apply diff: $e'],
      backupPath: backupPath,
    );
  }
}

// ─── Notebook operations ───

/// Jupyter notebook cell.
class NotebookCell {
  String cellType; // 'code', 'markdown', 'raw'
  List<String> source;
  Map<String, dynamic>? metadata;
  List<Map<String, dynamic>>? outputs;
  int? executionCount;

  NotebookCell({
    required this.cellType,
    required this.source,
    this.metadata,
    this.outputs,
    this.executionCount,
  });

  Map<String, dynamic> toJson() => {
        'cell_type': cellType,
        'source': source,
        if (metadata != null) 'metadata': metadata,
        if (cellType == 'code') 'outputs': outputs ?? [],
        if (cellType == 'code') 'execution_count': executionCount,
      };

  factory NotebookCell.fromJson(Map<String, dynamic> json) {
    return NotebookCell(
      cellType: json['cell_type'] as String? ?? 'code',
      source: (json['source'] as List?)?.cast<String>() ?? [],
      metadata: json['metadata'] as Map<String, dynamic>?,
      outputs: (json['outputs'] as List?)?.cast<Map<String, dynamic>>(),
      executionCount: json['execution_count'] as int?,
    );
  }

  String get text => source.join();
}

/// Parsed Jupyter notebook.
class Notebook {
  Map<String, dynamic> metadata;
  int nbformat;
  int nbformatMinor;
  List<NotebookCell> cells;

  Notebook({
    required this.metadata,
    required this.nbformat,
    required this.nbformatMinor,
    required this.cells,
  });

  factory Notebook.fromJson(Map<String, dynamic> json) {
    return Notebook(
      metadata: json['metadata'] as Map<String, dynamic>? ?? {},
      nbformat: json['nbformat'] as int? ?? 4,
      nbformatMinor: json['nbformat_minor'] as int? ?? 5,
      cells: (json['cells'] as List?)
              ?.map((c) =>
                  NotebookCell.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'metadata': metadata,
        'nbformat': nbformat,
        'nbformat_minor': nbformatMinor,
        'cells': cells.map((c) => c.toJson()).toList(),
      };

  String toJsonString() =>
      const JsonEncoder.withIndent(' ').convert(toJson());
}

/// Notebook edit command.
enum NotebookCommand { addCell, editCell, deleteCell, moveCell }

/// Perform a notebook edit operation.
Future<({bool success, String message, int cellCount})> editNotebook({
  required String notebookPath,
  required NotebookCommand command,
  int? cellIndex,
  String? content,
  String? cellType,
  int? targetIndex,
}) async {
  final file = File(notebookPath);
  if (!await file.exists()) {
    return (
      success: false,
      message: 'Notebook not found: $notebookPath',
      cellCount: 0,
    );
  }

  final jsonStr = await file.readAsString();
  final notebook = Notebook.fromJson(jsonDecode(jsonStr));

  switch (command) {
    case NotebookCommand.addCell:
      final cell = NotebookCell(
        cellType: cellType ?? 'code',
        source: content != null ? content.split('\n').map((l) => '$l\n').toList() : [''],
      );
      final idx = cellIndex ?? notebook.cells.length;
      if (idx < 0 || idx > notebook.cells.length) {
        return (
          success: false,
          message: 'Invalid index: $idx',
          cellCount: notebook.cells.length,
        );
      }
      notebook.cells.insert(idx, cell);
      break;

    case NotebookCommand.editCell:
      if (cellIndex == null ||
          cellIndex < 0 ||
          cellIndex >= notebook.cells.length) {
        return (
          success: false,
          message: 'Invalid cell index: $cellIndex',
          cellCount: notebook.cells.length,
        );
      }
      if (content != null) {
        notebook.cells[cellIndex].source =
            content.split('\n').map((l) => '$l\n').toList();
      }
      if (cellType != null) {
        notebook.cells[cellIndex].cellType = cellType;
      }
      break;

    case NotebookCommand.deleteCell:
      if (cellIndex == null ||
          cellIndex < 0 ||
          cellIndex >= notebook.cells.length) {
        return (
          success: false,
          message: 'Invalid cell index: $cellIndex',
          cellCount: notebook.cells.length,
        );
      }
      notebook.cells.removeAt(cellIndex);
      break;

    case NotebookCommand.moveCell:
      if (cellIndex == null ||
          targetIndex == null ||
          cellIndex < 0 ||
          cellIndex >= notebook.cells.length ||
          targetIndex < 0 ||
          targetIndex >= notebook.cells.length) {
        return (
          success: false,
          message: 'Invalid indices: $cellIndex → $targetIndex',
          cellCount: notebook.cells.length,
        );
      }
      final cell = notebook.cells.removeAt(cellIndex);
      notebook.cells.insert(targetIndex, cell);
      break;
  }

  await file.writeAsString(notebook.toJsonString());

  return (
    success: true,
    message: '${command.name} succeeded.',
    cellCount: notebook.cells.length,
  );
}

// ─── File validation ───

/// Check if a file is binary (non-text).
Future<bool> isBinaryFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return false;

  // Check extension first
  final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
  const binaryExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico',
    'mp3', 'wav', 'ogg', 'mp4', 'avi', 'mov',
    'zip', 'tar', 'gz', '7z', 'rar',
    'pdf', 'doc', 'docx', 'xls', 'xlsx',
    'exe', 'dll', 'so', 'dylib',
    'woff', 'woff2', 'ttf', 'otf',
    'sqlite', 'db',
  };
  if (binaryExts.contains(ext)) return true;

  // Read first 8KB and check for null bytes
  try {
    final raf = file.openSync();
    try {
      final bytes = raf.readSync(8192);
      return bytes.any((b) => b == 0);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return false;
  }
}

/// Get file info for display.
Future<Map<String, dynamic>> getFileInfo(String path) async {
  final file = File(path);
  final stat = await file.stat();
  final ext = p.extension(path).replaceFirst('.', '');

  return {
    'path': path,
    'name': p.basename(path),
    'extension': ext,
    'size': stat.size,
    'sizeFormatted': _formatBytes(stat.size),
    'modified': stat.modified.toIso8601String(),
    'isDirectory': stat.type == FileSystemEntityType.directory,
    'isBinary': await isBinaryFile(path),
  };
}

/// Undo a file change by restoring from backup.
Future<bool> undoFileChange(String filePath) async {
  // Find the most recent backup
  final dir = File(filePath).parent;
  final baseName = p.basename(filePath);
  final backups = <File>[];

  await for (final entity in dir.list()) {
    if (entity is File) {
      final name = p.basename(entity.path);
      if (name.startsWith('$baseName.bak.')) {
        backups.add(entity);
      }
    }
  }

  if (backups.isEmpty) return false;

  // Sort by timestamp (newest first)
  backups.sort((a, b) => b.path.compareTo(a.path));
  final latest = backups.first;

  // Restore
  await latest.copy(filePath);
  await latest.delete();
  return true;
}

/// Clean old backup files.
Future<int> cleanBackups(String directory, {int maxAge = 86400}) async {
  var cleaned = 0;
  final cutoff =
      DateTime.now().subtract(Duration(seconds: maxAge));

  await for (final entity in Directory(directory).list(recursive: true)) {
    if (entity is File && entity.path.contains('.bak.')) {
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
        cleaned++;
      }
    }
  }
  return cleaned;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
