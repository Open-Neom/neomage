import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'tool.dart';

/// Input parameters for the FileWriteTool.
class FileWriteInput {
  final String filePath;
  final String content;

  const FileWriteInput({
    required this.filePath,
    required this.content,
  });

  factory FileWriteInput.fromMap(Map<String, dynamic> map) {
    return FileWriteInput(
      filePath: map['file_path'] as String? ?? '',
      content: map['content'] as String? ?? '',
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (filePath.isEmpty) {
      errors.add('Missing required parameter: file_path');
    } else if (!p.isAbsolute(filePath)) {
      errors.add('file_path must be an absolute path, got: $filePath');
    }
    // content can be empty for creating empty files
    return errors;
  }
}

/// Output data from a file write operation.
class FileWriteOutput {
  final bool success;
  final String message;
  final int bytesWritten;
  final bool created;
  final String? backupPath;

  const FileWriteOutput({
    required this.success,
    required this.message,
    this.bytesWritten = 0,
    this.created = false,
    this.backupPath,
  });

  Map<String, dynamic> toMetadata() => {
        'success': success,
        'bytesWritten': bytesWritten,
        'created': created,
        if (backupPath != null) 'backupPath': backupPath,
      };
}

/// Paths that should not be written to for safety.
const _protectedPaths = <String>[
  '/etc',
  '/usr',
  '/bin',
  '/sbin',
  '/boot',
  '/dev',
  '/proc',
  '/sys',
  '/var/run',
  '/System',
  '/Library/System',
];

/// Write file contents — full port of openclaude/src/tools/FileWriteTool.
///
/// Features:
/// - Create parent directories if they don't exist
/// - Backup existing file before overwriting
/// - New file creation vs overwrite detection
/// - Encoding handling (default UTF-8)
/// - Permission checking (write access, protected paths)
/// - Atomic write (temp file then rename)
/// - Post-write verification
/// - Symlink handling
/// - File size reporting
class FileWriteTool extends Tool with FileWriteToolMixin {
  /// Maximum content size (100MB).
  static const int maxContentSize = 100 * 1024 * 1024;

  @override
  String get name => 'Write';

  @override
  String get description =>
      'Writes content to a file. Creates the file if it does not exist, '
      'or overwrites it if it does.';

  @override
  String get prompt =>
      'Writes a file to the local filesystem.\n\n'
      'Usage:\n'
      '- This tool will overwrite the existing file if there is one at the '
      'provided path.\n'
      '- If this is an existing file, you MUST use the Read tool first to '
      'read the file\'s contents. This tool will fail if you did not read '
      'the file first.\n'
      '- Prefer the Edit tool for modifying existing files -- it only sends '
      'the diff. Only use this tool to create new files or for complete '
      'rewrites.\n'
      '- NEVER create documentation files (*.md) or README files unless '
      'explicitly requested by the User.';

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'file_path': {
            'type': 'string',
            'description': 'The absolute path to the file to write '
                '(must be absolute, not relative)',
          },
          'content': {
            'type': 'string',
            'description': 'The content to write to the file',
          },
        },
        'required': ['file_path', 'content'],
      };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Write ${p.basename(filePath)}';
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Writing ${p.basename(filePath)}';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = FileWriteInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ValidationResult.invalid(errors.first);
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final filePath = input['file_path'] as String?;
    final content = input['content'] as String?;

    // Validate required parameters
    if (filePath == null || filePath.isEmpty) {
      return ToolResult.error('Missing required parameter: file_path');
    }
    if (!p.isAbsolute(filePath)) {
      return ToolResult.error(
        'file_path must be an absolute path, got: $filePath',
      );
    }
    if (content == null) {
      return ToolResult.error('Missing required parameter: content');
    }

    // Check content size
    if (content.length > maxContentSize) {
      return ToolResult.error(
        'Content too large: ${_formatFileSize(content.length)} '
        '(max ${_formatFileSize(maxContentSize)})',
      );
    }

    // Check protected paths
    final protectedCheck = _checkProtectedPath(filePath);
    if (protectedCheck != null) {
      return ToolResult.error(protectedCheck);
    }

    // Resolve symlinks for the target path
    final resolvedPath = await _resolveSymlink(filePath);

    final file = File(resolvedPath);
    final isNewFile = !await file.exists();
    String? backupPath;

    try {
      // Create parent directories if needed
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }

      // Check parent directory write permission
      if (!await _isWritable(parent.path)) {
        return ToolResult.error(
          'Permission denied: Cannot write to directory '
          '${parent.path}',
        );
      }

      // Backup existing file before overwriting
      if (!isNewFile) {
        backupPath = await _createBackup(file);
      }

      // Atomic write: write to temp file, then rename
      final tempFile = File('${resolvedPath}.tmp.${_timestamp()}');
      try {
        await tempFile.writeAsString(content, encoding: utf8, flush: true);

        // Post-write verification: read back and compare
        final verifyContent = await tempFile.readAsString(encoding: utf8);
        if (verifyContent != content) {
          await tempFile.delete();
          return ToolResult.error(
            'Post-write verification failed: content mismatch. '
            'The write was aborted.',
          );
        }

        // Rename temp file to target (atomic on same filesystem)
        await tempFile.rename(resolvedPath);
      } catch (e) {
        // Clean up temp file on failure
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
        rethrow;
      }

      // Get final file stats
      final stat = await file.stat();
      final bytesWritten = stat.size;

      final output = FileWriteOutput(
        success: true,
        message: isNewFile
            ? 'New file created: $filePath'
            : 'File overwritten: $filePath',
        bytesWritten: bytesWritten,
        created: isNewFile,
        backupPath: backupPath,
      );

      final resultBuf = StringBuffer();
      resultBuf.writeln(output.message);
      resultBuf.writeln('Size: ${_formatFileSize(bytesWritten)}');
      if (!isNewFile && backupPath != null) {
        resultBuf.writeln('Backup: $backupPath');
      }

      return ToolResult.success(
        resultBuf.toString(),
        metadata: output.toMetadata(),
      );
    } catch (e) {
      // Attempt to restore from backup on failure
      if (backupPath != null && await File(backupPath).exists()) {
        try {
          await File(backupPath).copy(resolvedPath);
        } catch (_) {
          // Restoration failed too
        }
      }
      return ToolResult.error('Error writing file: $e');
    }
  }

  /// Check if a path is in a protected system directory.
  String? _checkProtectedPath(String filePath) {
    final normalized = p.normalize(filePath);
    for (final protected in _protectedPaths) {
      if (normalized.startsWith(protected) ||
          normalized == protected) {
        return 'Cannot write to protected system path: $protected';
      }
    }
    return null;
  }

  /// Check if a directory is writable.
  Future<bool> _isWritable(String dirPath) async {
    try {
      final testFile = File(p.join(dirPath, '.write_test_${_timestamp()}'));
      await testFile.writeAsString('');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Resolve a symlink to its target path.
  Future<String> _resolveSymlink(String filePath) async {
    try {
      final link = Link(filePath);
      if (await link.exists()) {
        return await link.resolveSymbolicLinks();
      }
    } catch (_) {}
    return filePath;
  }

  /// Create a backup of an existing file.
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

  /// Generate a timestamp string for temp file names.
  String _timestamp() {
    return DateTime.now().microsecondsSinceEpoch.toString();
  }

  /// Format file size in human-readable format.
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
