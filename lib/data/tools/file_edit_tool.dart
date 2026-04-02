import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'tool.dart';

/// Input parameters for the FileEditTool.
class FileEditInput {
  final String filePath;
  final String oldString;
  final String newString;
  final bool replaceAll;

  const FileEditInput({
    required this.filePath,
    required this.oldString,
    required this.newString,
    this.replaceAll = false,
  });

  factory FileEditInput.fromMap(Map<String, dynamic> map) {
    return FileEditInput(
      filePath: map['file_path'] as String? ?? '',
      oldString: map['old_string'] as String? ?? '',
      newString: map['new_string'] as String? ?? '',
      replaceAll: map['replace_all'] as bool? ?? false,
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (filePath.isEmpty) {
      errors.add('Missing required parameter: file_path');
    } else if (!p.isAbsolute(filePath)) {
      errors.add('file_path must be an absolute path, got: $filePath');
    }
    if (oldString.isEmpty) {
      errors.add('Missing required parameter: old_string');
    }
    // new_string can be empty (deletion)
    if (oldString.isNotEmpty && oldString == newString) {
      errors.add('old_string and new_string must be different');
    }
    return errors;
  }
}

/// Output data from a file edit operation.
class FileEditOutput {
  final bool success;
  final String message;
  final int linesChanged;
  final String? backupPath;
  final int occurrencesReplaced;
  final String? diff;

  const FileEditOutput({
    required this.success,
    required this.message,
    this.linesChanged = 0,
    this.backupPath,
    this.occurrencesReplaced = 0,
    this.diff,
  });

  Map<String, dynamic> toMetadata() => {
        'success': success,
        'linesChanged': linesChanged,
        if (backupPath != null) 'backupPath': backupPath,
        'occurrencesReplaced': occurrencesReplaced,
      };
}

/// Edit file with exact string replacement — full port of
/// openclaude/src/tools/FileEditTool.
///
/// Features:
/// - Exact string replacement (oldString -> newString)
/// - Uniqueness validation (oldString must appear exactly once unless
///   replaceAll=true)
/// - replaceAll mode for bulk replacements
/// - Whitespace-sensitive matching
/// - Backup creation before editing
/// - Binary file rejection
/// - Diff display in output
/// - Encoding preservation
/// - Newline normalization preservation
/// - Post-edit validation
/// - Undo support via backup
class FileEditTool extends Tool with FileWriteToolMixin {
  /// Maximum file size for in-memory editing (50MB).
  static const int maxEditFileSize = 50 * 1024 * 1024;

  /// Number of context lines to show in diff output.
  static const int diffContextLines = 3;

  @override
  String get name => 'Edit';

  @override
  String get description =>
      'Performs exact string replacements in files. The edit will fail if '
      'old_string is not unique in the file unless replace_all is true.';

  @override
  String get prompt =>
      'Performs exact string replacements in files.\n\n'
      'Usage:\n'
      '- You must use your Read tool at least once before editing. This tool '
      'will error if you attempt an edit without reading the file.\n'
      '- When editing text from Read tool output, ensure you preserve the '
      'exact indentation (tabs/spaces) as it appears AFTER the line number '
      'prefix.\n'
      '- ALWAYS prefer editing existing files in the codebase. NEVER write '
      'new files unless explicitly required.\n'
      '- The edit will FAIL if old_string is not unique in the file. Either '
      'provide a larger string with more surrounding context to make it '
      'unique or use replace_all to change every instance of old_string.\n'
      '- Use replace_all for replacing and renaming strings across the file.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'The absolute path to the file to modify',
          },
          'old_string': {
            'type': 'string',
            'description': 'The text to replace',
          },
          'new_string': {
            'type': 'string',
            'description':
                'The text to replace it with (must be different from '
                    'old_string)',
          },
          'replace_all': {
            'default': false,
            'type': 'boolean',
            'description':
                'Replace all occurrences of old_string (default false)',
          },
        },
        'required': ['file_path', 'old_string', 'new_string'],
      };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Edit ${p.basename(filePath)}';
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Editing ${p.basename(filePath)}';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = FileEditInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ValidationResult.invalid(errors.first);
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final filePath = input['file_path'] as String?;
    final oldString = input['old_string'] as String?;
    final newString = input['new_string'] as String?;
    final replaceAll = input['replace_all'] as bool? ?? false;

    // Validate required parameters
    if (filePath == null || filePath.isEmpty) {
      return ToolResult.error('Missing required parameter: file_path');
    }
    if (!p.isAbsolute(filePath)) {
      return ToolResult.error(
          'file_path must be an absolute path, got: $filePath');
    }
    if (oldString == null || oldString.isEmpty) {
      return ToolResult.error('Missing required parameter: old_string');
    }
    if (newString == null) {
      return ToolResult.error('Missing required parameter: new_string');
    }
    if (oldString == newString) {
      return ToolResult.error('old_string and new_string must be different');
    }

    final file = File(filePath);

    // Check file exists
    if (!await file.exists()) {
      return ToolResult.error('File not found: $filePath');
    }

    // Check file is not a directory
    final stat = await file.stat();
    if (stat.type == FileSystemEntityType.directory) {
      return ToolResult.error('$filePath is a directory, not a file');
    }

    // Check file size
    if (stat.size > maxEditFileSize) {
      return ToolResult.error(
        'File too large for editing: '
        '${(stat.size / (1024 * 1024)).toStringAsFixed(1)} MB '
        '(max ${maxEditFileSize ~/ (1024 * 1024)} MB)',
      );
    }

    // Check for binary file
    if (await _isBinaryFile(file)) {
      return ToolResult.error(
        'Cannot edit binary file: $filePath. '
        'Use the Write tool to overwrite it entirely.',
      );
    }

    // Check write permission
    try {
      // Try opening for write to check permission
      final raf = await file.open(mode: FileMode.append);
      await raf.close();
    } on FileSystemException catch (e) {
      return ToolResult.error(
        'Permission denied: Cannot write to $filePath: ${e.message}',
      );
    }

    try {
      // Read file content preserving encoding
      final (content, encoding) = await _readWithEncoding(file);

      // Detect newline style
      final newlineStyle = _detectNewlineStyle(content);

      // Check if oldString exists
      if (!content.contains(oldString)) {
        // Provide helpful error with suggestions
        return _buildNotFoundError(filePath, oldString, content);
      }

      // Check uniqueness (unless replaceAll)
      final occurrences = oldString.allMatches(content).length;
      if (!replaceAll && occurrences > 1) {
        return ToolResult.error(
          'old_string appears $occurrences times in file. '
          'Provide more surrounding context to make it unique, '
          'or set replace_all to true.',
        );
      }

      // Create backup
      final backupPath = await _createBackup(file);

      // Perform replacement
      final newContent = replaceAll
          ? content.replaceAll(oldString, newString)
          : content.replaceFirst(oldString, newString);

      // Count line changes
      final oldLineCount = '\n'.allMatches(content).length + 1;
      final newLineCount = '\n'.allMatches(newContent).length + 1;
      final linesChanged = (newLineCount - oldLineCount).abs();

      // Preserve newline style
      final finalContent = _preserveNewlineStyle(newContent, newlineStyle);

      // Write using same encoding
      await _writeWithEncoding(file, finalContent, encoding);

      // Post-edit validation: verify file is not corrupted
      final verifyContent = await file.readAsString();
      if (verifyContent != finalContent) {
        // Restore from backup
        if (backupPath != null) {
          await File(backupPath).copy(filePath);
        }
        return ToolResult.error(
          'Post-edit validation failed: file content mismatch. '
          'Backup restored.',
        );
      }

      // Build diff output
      final diff = _buildDiff(content, newContent, filePath);

      final replacedCount = replaceAll ? occurrences : 1;

      final output = FileEditOutput(
        success: true,
        message: 'File edited successfully: $filePath',
        linesChanged: linesChanged,
        backupPath: backupPath,
        occurrencesReplaced: replacedCount,
        diff: diff,
      );

      final resultBuf = StringBuffer();
      resultBuf.writeln(output.message);
      resultBuf.writeln(
        'Replaced $replacedCount occurrence${replacedCount > 1 ? 's' : ''}.',
      );
      if (linesChanged > 0) {
        final direction = newLineCount > oldLineCount ? 'added' : 'removed';
        resultBuf.writeln('$linesChanged line(s) $direction.');
      }
      if (diff != null) {
        resultBuf.writeln();
        resultBuf.writeln(diff);
      }

      return ToolResult.success(
        resultBuf.toString(),
        metadata: output.toMetadata(),
      );
    } catch (e) {
      return ToolResult.error('Error editing file: $e');
    }
  }

  /// Check if a file is binary by reading first bytes.
  Future<bool> _isBinaryFile(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final bytes = await raf.read(512);
        if (bytes.isEmpty) return false;

        // Check for null bytes
        for (final byte in bytes) {
          if (byte == 0) return true;
        }

        // Check magic bytes for known binary formats
        if (bytes.length >= 4) {
          if (bytes[0] == 0x89 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x4E &&
              bytes[3] == 0x47) return true;
          if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
            return true;
          }
          if (bytes[0] == 0x25 &&
              bytes[1] == 0x50 &&
              bytes[2] == 0x44 &&
              bytes[3] == 0x46) return true;
          if (bytes[0] == 0x50 &&
              bytes[1] == 0x4B &&
              bytes[2] == 0x03 &&
              bytes[3] == 0x04) return true;
        }

        return false;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  /// Read file trying UTF-8 first, then Latin1.
  Future<(String, String)> _readWithEncoding(File file) async {
    try {
      final content = await file.readAsString(encoding: utf8);
      if (!content.contains('\uFFFD')) {
        return (content, 'utf-8');
      }
    } catch (_) {}

    try {
      final content = await file.readAsString(encoding: latin1);
      return (content, 'latin1');
    } catch (_) {}

    final bytes = await file.readAsBytes();
    return (String.fromCharCodes(bytes), 'binary');
  }

  /// Write file with the specified encoding.
  Future<void> _writeWithEncoding(
    File file,
    String content,
    String encoding,
  ) async {
    switch (encoding) {
      case 'utf-8':
        await file.writeAsString(content, encoding: utf8);
        break;
      case 'latin1':
        await file.writeAsString(content, encoding: latin1);
        break;
      default:
        await file.writeAsString(content, encoding: utf8);
    }
  }

  /// Detect the newline style used in the file (\n, \r\n, or \r).
  String _detectNewlineStyle(String content) {
    final crlf = '\r\n'.allMatches(content).length;
    final lf =
        '\n'.allMatches(content).length - crlf; // subtract CRLF matches
    final cr =
        '\r'.allMatches(content).length - crlf; // subtract CRLF matches

    if (crlf > lf && crlf > cr) return '\r\n';
    if (cr > lf) return '\r';
    return '\n';
  }

  /// Preserve the original newline style after replacement.
  String _preserveNewlineStyle(String content, String style) {
    if (style == '\r\n') {
      // Convert any lone \n to \r\n (but not already \r\n)
      return content
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .replaceAll('\n', '\r\n');
    }
    if (style == '\r') {
      return content.replaceAll('\r\n', '\r').replaceAll('\n', '\r');
    }
    return content;
  }

  /// Create a backup of the file before editing.
  Future<String?> _createBackup(File file) async {
    try {
      final backupPath = '${file.path}.bak';
      await file.copy(backupPath);
      return backupPath;
    } catch (_) {
      // Non-fatal: continue without backup
      return null;
    }
  }

  /// Build a helpful error message when old_string is not found.
  ToolResult _buildNotFoundError(
    String filePath,
    String oldString,
    String content,
  ) {
    final buf = StringBuffer();
    buf.writeln(
      'old_string not found in file. Make sure it matches exactly, '
      'including whitespace and indentation.',
    );

    // Check for common issues
    if (oldString.contains('\t') && !content.contains('\t')) {
      buf.writeln(
        'Hint: old_string contains tabs but the file uses spaces.',
      );
    }
    if (oldString.contains('  ') && content.contains('\t')) {
      buf.writeln(
        'Hint: old_string uses spaces but the file may use tabs.',
      );
    }

    // Check for case-insensitive match
    final lowerOld = oldString.toLowerCase();
    if (content.toLowerCase().contains(lowerOld)) {
      buf.writeln(
        'Hint: A case-insensitive match was found. Check capitalization.',
      );
    }

    // Check for match with trimmed whitespace
    final trimmedOld = oldString.trim();
    if (trimmedOld != oldString && content.contains(trimmedOld)) {
      buf.writeln(
        'Hint: Match found when ignoring leading/trailing whitespace.',
      );
    }

    return ToolResult.error(buf.toString());
  }

  /// Build a unified diff showing the changes.
  String? _buildDiff(
    String oldContent,
    String newContent,
    String filePath,
  ) {
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');

    // Find first difference
    var firstDiff = 0;
    while (firstDiff < oldLines.length &&
        firstDiff < newLines.length &&
        oldLines[firstDiff] == newLines[firstDiff]) {
      firstDiff++;
    }

    // Find last difference (from end)
    var oldEnd = oldLines.length - 1;
    var newEnd = newLines.length - 1;
    while (oldEnd > firstDiff &&
        newEnd > firstDiff &&
        oldLines[oldEnd] == newLines[newEnd]) {
      oldEnd--;
      newEnd--;
    }

    // Build diff with context
    final contextStart = (firstDiff - diffContextLines).clamp(0, oldLines.length);
    final oldContextEnd =
        (oldEnd + diffContextLines + 1).clamp(0, oldLines.length);
    final newContextEnd =
        (newEnd + diffContextLines + 1).clamp(0, newLines.length);

    final buf = StringBuffer();
    buf.writeln('--- a/${p.basename(filePath)}');
    buf.writeln('+++ b/${p.basename(filePath)}');
    buf.writeln(
      '@@ -${contextStart + 1},${oldContextEnd - contextStart} '
      '+${contextStart + 1},${newContextEnd - contextStart} @@',
    );

    // Context before
    for (var i = contextStart; i < firstDiff; i++) {
      buf.writeln(' ${oldLines[i]}');
    }

    // Removed lines
    for (var i = firstDiff; i <= oldEnd && i < oldLines.length; i++) {
      buf.writeln('-${oldLines[i]}');
    }

    // Added lines
    for (var i = firstDiff; i <= newEnd && i < newLines.length; i++) {
      buf.writeln('+${newLines[i]}');
    }

    // Context after
    for (var i = oldEnd + 1; i < oldContextEnd; i++) {
      if (i < oldLines.length) buf.writeln(' ${oldLines[i]}');
    }

    return buf.toString();
  }
}
