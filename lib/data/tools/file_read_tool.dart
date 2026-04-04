import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'tool.dart';

/// Input parameters for the FileReadTool.
class FileReadInput {
  final String filePath;
  final int? offset;
  final int? limit;
  final String? pages;

  const FileReadInput({
    required this.filePath,
    this.offset,
    this.limit,
    this.pages,
  });

  factory FileReadInput.fromMap(Map<String, dynamic> map) {
    return FileReadInput(
      filePath: map['file_path'] as String? ?? '',
      offset: map['offset'] as int?,
      limit: map['limit'] as int?,
      pages: map['pages'] as String?,
    );
  }

  List<String> validate() {
    final errors = <String>[];
    if (filePath.isEmpty) {
      errors.add('Missing required parameter: file_path');
    } else if (!p.isAbsolute(filePath)) {
      errors.add('file_path must be an absolute path, got: $filePath');
    }
    if (offset != null && offset! < 1) {
      errors.add('offset must be >= 1 (1-based line number)');
    }
    if (limit != null && limit! < 1) {
      errors.add('limit must be >= 1');
    }
    return errors;
  }
}

/// Output data from a file read operation.
class FileReadOutput {
  final String content;
  final int lineCount;
  final bool truncated;
  final bool binary;
  final String encoding;
  final int size;
  final DateTime? modified;

  const FileReadOutput({
    required this.content,
    this.lineCount = 0,
    this.truncated = false,
    this.binary = false,
    this.encoding = 'utf-8',
    this.size = 0,
    this.modified,
  });

  Map<String, dynamic> toMetadata() => {
    'lineCount': lineCount,
    'truncated': truncated,
    'binary': binary,
    'encoding': encoding,
    'size': size,
    if (modified != null) 'modified': modified!.toIso8601String(),
  };
}

/// Magic byte signatures for binary file detection.
class _MagicBytes {
  static const png = [0x89, 0x50, 0x4E, 0x47];
  static const jpg = [0xFF, 0xD8, 0xFF];
  static const gif87 = [0x47, 0x49, 0x46, 0x38, 0x37, 0x61];
  static const gif89 = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61];
  static const pdf = [0x25, 0x50, 0x44, 0x46];
  static const zip = [0x50, 0x4B, 0x03, 0x04];
  static const gzip = [0x1F, 0x8B];
  static const bmp = [0x42, 0x4D];
  static const webp = [0x52, 0x49, 0x46, 0x46]; // RIFF header
  static const exe = [0x4D, 0x5A];
  static const elf = [0x7F, 0x45, 0x4C, 0x46];
  static const classFile = [0xCA, 0xFE, 0xBA, 0xBE];
  static const tiff1 = [0x49, 0x49, 0x2A, 0x00];
  static const tiff2 = [0x4D, 0x4D, 0x00, 0x2A];
  static const ico = [0x00, 0x00, 0x01, 0x00];
  static const wasm = [0x00, 0x61, 0x73, 0x6D];
}

/// Read file contents — full port of neom_claw/src/tools/FileReadTool.
///
/// Features:
/// - Binary file detection via magic bytes
/// - Encoding detection (UTF-8, Latin1, ASCII)
/// - Line-number prefixed output (cat -n format)
/// - Offset/limit for reading specific ranges
/// - PDF page extraction support
/// - Image metadata extraction
/// - Notebook (.ipynb) parsing
/// - Large file protection
/// - Symlink resolution
/// - Permission checking
class FileReadTool extends Tool with ReadOnlyToolMixin {
  /// Default line limit when none specified.
  static const int defaultLimit = 2000;

  /// Warning threshold for large files.
  static const int largeFileLineThreshold = 10000;

  /// Maximum bytes to read for binary detection.
  static const int magicBytesReadSize = 16;

  /// Maximum output size before truncation (chars).
  static const int maxOutputChars = 500000;

  @override
  String get name => 'Read';

  @override
  String get description =>
      'Reads a file from the local filesystem. Returns file contents with '
      'line numbers in cat -n format. Supports text files, images (returns '
      'metadata), PDFs (with page selection), and Jupyter notebooks.';

  @override
  String get prompt =>
      'Reads a file from the local filesystem. You can access any file '
      'directly by using this tool.\n'
      'Assume this tool is able to read all files on the machine. If the User '
      'provides a path to a file assume that path is valid.\n\n'
      'Usage:\n'
      '- The file_path parameter must be an absolute path, not a relative path\n'
      '- By default, it reads up to $defaultLimit lines from the beginning\n'
      '- When you already know which part of the file you need, only read that '
      'part. This can be important for larger files.\n'
      '- Results are returned using cat -n format, with line numbers starting '
      'at 1\n'
      '- This tool can read images (PNG, JPG, etc). When reading an image '
      'file the contents are presented visually.\n'
      '- This tool can read PDF files (.pdf). For large PDFs (more than 10 '
      'pages), you MUST provide the pages parameter to read specific page '
      'ranges (e.g., pages: "1-5").\n'
      '- This tool can read Jupyter notebooks (.ipynb files) and returns all '
      'cells with their outputs.\n'
      '- This tool can only read files, not directories.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'file_path': {
        'type': 'string',
        'description': 'The absolute path to the file to read',
      },
      'offset': {
        'type': 'integer',
        'description':
            'The line number to start reading from (1-based). '
            'Only provide if the file is too large to read at once.',
      },
      'limit': {
        'type': 'integer',
        'description':
            'The number of lines to read. Only provide if the file '
            'is too large to read at once.',
      },
      'pages': {
        'type': 'string',
        'description':
            'Page range for PDF files (e.g., "1-5", "3", "10-20"). '
            'Only applicable to PDF files. Maximum 20 pages per request.',
      },
    },
    'required': ['file_path'],
  };

  @override
  bool get isAvailable =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Read ${p.basename(filePath)}';
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return 'Reading ${p.basename(filePath)}';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = FileReadInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ValidationResult.invalid(errors.first);
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = FileReadInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) {
      return ToolResult.error(errors.first);
    }

    // Resolve symlinks
    final resolvedPath = await _resolveSymlinks(parsed.filePath);

    // Check existence
    final fileType = await FileSystemEntity.type(resolvedPath);
    if (fileType == FileSystemEntityType.notFound) {
      return ToolResult.error('File not found: ${parsed.filePath}');
    }
    if (fileType == FileSystemEntityType.directory) {
      return ToolResult.error(
        '${parsed.filePath} is a directory, not a file. '
        'Use the Bash tool with ls to list directory contents.',
      );
    }

    final file = File(resolvedPath);

    // Permission check
    try {
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return ToolResult.error('File not found: ${parsed.filePath}');
      }
    } on FileSystemException catch (e) {
      return ToolResult.error('Permission denied: ${e.message}');
    }

    final stat = await file.stat();
    final fileSize = stat.size;
    final modified = stat.modified;

    // Check for binary file
    final binaryInfo = await _detectBinaryFile(file);
    if (binaryInfo != null) {
      return _handleBinaryFile(file, parsed, binaryInfo, fileSize, modified);
    }

    // Handle special file types by extension
    final ext = p.extension(parsed.filePath).toLowerCase();

    if (ext == '.ipynb') {
      return _handleNotebook(file, fileSize, modified);
    }

    if (ext == '.pdf') {
      return _handlePdf(file, parsed, fileSize, modified);
    }

    // Read as text
    return _readTextFile(file, parsed, fileSize, modified);
  }

  /// Resolve symlinks to their actual path.
  Future<String> _resolveSymlinks(String filePath) async {
    try {
      final link = Link(filePath);
      if (await link.exists()) {
        return await link.resolveSymbolicLinks();
      }
    } catch (_) {
      // Not a symlink or can't resolve, use original
    }
    return filePath;
  }

  /// Detect binary files by reading magic bytes.
  /// Returns a description string if binary, null if text.
  Future<String?> _detectBinaryFile(File file) async {
    try {
      final raf = await file.open(mode: FileMode.read);
      try {
        final bytes = await raf.read(magicBytesReadSize);
        if (bytes.isEmpty) return null;

        final format = _identifyFormat(bytes);
        if (format != null) return format;

        // Check for null bytes (common binary indicator)
        for (final byte in bytes) {
          if (byte == 0) return 'binary';
        }

        return null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  /// Identify file format from magic bytes.
  String? _identifyFormat(Uint8List bytes) {
    if (bytes.length < 2) return null;

    if (_matchBytes(bytes, _MagicBytes.png)) return 'image/png';
    if (_matchBytes(bytes, _MagicBytes.jpg)) return 'image/jpeg';
    if (_matchBytes(bytes, _MagicBytes.gif87)) return 'image/gif';
    if (_matchBytes(bytes, _MagicBytes.gif89)) return 'image/gif';
    if (_matchBytes(bytes, _MagicBytes.pdf)) return 'application/pdf';
    if (_matchBytes(bytes, _MagicBytes.zip)) return 'application/zip';
    if (_matchBytes(bytes, _MagicBytes.gzip)) return 'application/gzip';
    if (_matchBytes(bytes, _MagicBytes.bmp)) return 'image/bmp';
    if (_matchBytes(bytes, _MagicBytes.tiff1)) return 'image/tiff';
    if (_matchBytes(bytes, _MagicBytes.tiff2)) return 'image/tiff';
    if (_matchBytes(bytes, _MagicBytes.ico)) return 'image/x-icon';
    if (_matchBytes(bytes, _MagicBytes.exe)) return 'application/x-executable';
    if (_matchBytes(bytes, _MagicBytes.elf)) return 'application/x-elf';
    if (_matchBytes(bytes, _MagicBytes.classFile)) {
      return 'application/java-class';
    }
    if (_matchBytes(bytes, _MagicBytes.wasm)) return 'application/wasm';

    // WebP: RIFF header + WEBP at offset 8
    if (_matchBytes(bytes, _MagicBytes.webp) && bytes.length >= 12) {
      if (bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'image/webp';
      }
    }

    return null;
  }

  /// Check if file bytes start with the given signature.
  bool _matchBytes(Uint8List fileBytes, List<int> signature) {
    if (fileBytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (fileBytes[i] != signature[i]) return false;
    }
    return true;
  }

  /// Handle binary files (images, archives, etc.).
  Future<ToolResult> _handleBinaryFile(
    File file,
    FileReadInput input,
    String format,
    int fileSize,
    DateTime modified,
  ) async {
    if (format.startsWith('image/')) {
      return _handleImageFile(file, format, fileSize, modified);
    }

    if (format == 'application/pdf') {
      return _handlePdf(file, input, fileSize, modified);
    }

    final sizeStr = _formatFileSize(fileSize);
    final output = FileReadOutput(
      content:
          'Binary file: ${p.basename(file.path)}\n'
          'Format: $format\n'
          'Size: $sizeStr\n'
          'Modified: ${modified.toIso8601String()}\n\n'
          'This is a binary file and cannot be displayed as text.',
      binary: true,
      size: fileSize,
      modified: modified,
    );

    return ToolResult.success(output.content, metadata: output.toMetadata());
  }

  /// Handle image files — return metadata.
  Future<ToolResult> _handleImageFile(
    File file,
    String format,
    int fileSize,
    DateTime modified,
  ) async {
    final sizeStr = _formatFileSize(fileSize);
    final dimensions = await _getImageDimensions(file, format);

    final buf = StringBuffer();
    buf.writeln('Image file: ${p.basename(file.path)}');
    buf.writeln('Format: $format');
    buf.writeln('Size: $sizeStr');
    if (dimensions != null) {
      buf.writeln('Dimensions: ${dimensions.$1}x${dimensions.$2}');
    }
    buf.writeln('Modified: ${modified.toIso8601String()}');
    buf.writeln();
    buf.writeln(
      'This is an image file. When reading an image file the contents '
      'are presented visually as NeomClaw is a multimodal LLM.',
    );

    final output = FileReadOutput(
      content: buf.toString(),
      binary: true,
      encoding: format,
      size: fileSize,
      modified: modified,
    );

    return ToolResult.success(
      output.content,
      metadata: {
        ...output.toMetadata(),
        'format': format,
        if (dimensions != null)
          'dimensions': {'width': dimensions.$1, 'height': dimensions.$2},
      },
    );
  }

  /// Try to extract image dimensions from file header.
  Future<(int, int)?> _getImageDimensions(File file, String format) async {
    try {
      final bytes = await file
          .openRead(0, 32)
          .fold<List<int>>([], (prev, chunk) => prev..addAll(chunk));
      final data = Uint8List.fromList(bytes);

      if (format == 'image/png' && data.length >= 24) {
        final width =
            (data[16] << 24) | (data[17] << 16) | (data[18] << 8) | data[19];
        final height =
            (data[20] << 24) | (data[21] << 16) | (data[22] << 8) | data[23];
        return (width, height);
      }

      if (format == 'image/gif' && data.length >= 10) {
        final width = data[6] | (data[7] << 8);
        final height = data[8] | (data[9] << 8);
        return (width, height);
      }

      if (format == 'image/bmp' && data.length >= 26) {
        final width =
            data[18] | (data[19] << 8) | (data[20] << 16) | (data[21] << 24);
        final height =
            data[22] | (data[23] << 8) | (data[24] << 16) | (data[25] << 24);
        return (width, height.abs());
      }
    } catch (_) {
      // Dimension extraction is best-effort
    }
    return null;
  }

  /// Handle PDF files.
  Future<ToolResult> _handlePdf(
    File file,
    FileReadInput input,
    int fileSize,
    DateTime modified,
  ) async {
    final sizeStr = _formatFileSize(fileSize);

    // Try to use pdftotext if available
    final pageRange = input.pages;
    try {
      final args = <String>['-layout'];
      if (pageRange != null) {
        final parsed = _parsePageRange(pageRange);
        if (parsed != null) {
          args.addAll(['-f', '${parsed.$1}', '-l', '${parsed.$2}']);
        }
      }
      args.addAll([file.path, '-']);

      final result = await Process.run('pdftotext', args);
      if (result.exitCode == 0) {
        final text = (result.stdout as String).trim();
        if (text.isNotEmpty) {
          final lines = text.split('\n');
          final buf = StringBuffer();
          buf.writeln(
            'PDF: ${p.basename(file.path)} | Size: $sizeStr'
            '${pageRange != null ? ' | Pages: $pageRange' : ''}',
          );
          buf.writeln();
          for (var i = 0; i < lines.length; i++) {
            buf.writeln('${i + 1}\t${lines[i]}');
          }

          return ToolResult.success(
            buf.toString(),
            metadata: {
              'format': 'application/pdf',
              'size': fileSize,
              'lineCount': lines.length,
              'modified': modified.toIso8601String(),
              'pages': ?pageRange,
            },
          );
        }
      }
    } catch (_) {
      // pdftotext not available, fall through
    }

    // Fallback: return metadata only
    return ToolResult.success(
      'PDF file: ${p.basename(file.path)}\n'
      'Size: $sizeStr\n'
      'Modified: ${modified.toIso8601String()}\n'
      '${pageRange != null ? 'Requested pages: $pageRange\n' : ''}\n'
      'Note: pdftotext is not available. Install poppler-utils to enable '
      'PDF text extraction.',
      metadata: {
        'format': 'application/pdf',
        'size': fileSize,
        'binary': true,
        'modified': modified.toIso8601String(),
      },
    );
  }

  /// Parse a page range string like "1-5", "3", "10-20".
  (int, int)? _parsePageRange(String range) {
    final trimmed = range.trim();
    if (trimmed.contains('-')) {
      final parts = trimmed.split('-');
      if (parts.length == 2) {
        final first = int.tryParse(parts[0].trim());
        final last = int.tryParse(parts[1].trim());
        if (first != null && last != null && first > 0 && last >= first) {
          // Enforce max 20 pages per request
          final clampedLast = (last - first > 19) ? first + 19 : last;
          return (first, clampedLast);
        }
      }
    } else {
      final page = int.tryParse(trimmed);
      if (page != null && page > 0) {
        return (page, page);
      }
    }
    return null;
  }

  /// Handle Jupyter notebook (.ipynb) files.
  Future<ToolResult> _handleNotebook(
    File file,
    int fileSize,
    DateTime modified,
  ) async {
    try {
      final content = await file.readAsString(encoding: utf8);
      final notebook = json.decode(content) as Map<String, dynamic>;

      final cells = notebook['cells'] as List<dynamic>? ?? [];
      final metadata = notebook['metadata'] as Map<String, dynamic>? ?? {};
      final kernelSpec = metadata['kernelspec'] as Map<String, dynamic>? ?? {};
      final language =
          kernelSpec['language'] as String? ??
          (metadata['language_info'] as Map<String, dynamic>?)?['name']
              as String? ??
          'unknown';

      final buf = StringBuffer();
      buf.writeln(
        'Jupyter Notebook: ${p.basename(file.path)} '
        '| Language: $language | Cells: ${cells.length}',
      );
      buf.writeln();

      for (var i = 0; i < cells.length; i++) {
        final cell = cells[i] as Map<String, dynamic>;
        final cellType = cell['cell_type'] as String? ?? 'unknown';
        final source = _extractCellSource(cell);
        final outputs = cell['outputs'] as List<dynamic>? ?? [];

        buf.writeln('--- Cell $i [$cellType] ---');
        buf.writeln(source);

        if (outputs.isNotEmpty) {
          buf.writeln('--- Output ---');
          for (final output in outputs) {
            if (output is Map<String, dynamic>) {
              final outputText = _extractNotebookOutput(output);
              if (outputText.isNotEmpty) {
                buf.writeln(outputText);
              }
            }
          }
        }

        buf.writeln();
      }

      return ToolResult.success(
        buf.toString(),
        metadata: {
          'format': 'notebook',
          'size': fileSize,
          'cellCount': cells.length,
          'language': language,
          'modified': modified.toIso8601String(),
        },
      );
    } catch (e) {
      return ToolResult.error('Error parsing notebook: $e');
    }
  }

  /// Extract source text from a notebook cell.
  String _extractCellSource(Map<String, dynamic> cell) {
    final source = cell['source'];
    if (source is String) return source;
    if (source is List) return source.map((s) => s.toString()).join('');
    return '';
  }

  /// Extract text output from a notebook output object.
  String _extractNotebookOutput(Map<String, dynamic> output) {
    final outputType = output['output_type'] as String? ?? '';

    switch (outputType) {
      case 'stream':
        final text = output['text'];
        if (text is String) return text;
        if (text is List) return text.join('');
        return '';

      case 'execute_result':
      case 'display_data':
        final data = output['data'] as Map<String, dynamic>? ?? {};
        // Prefer text/plain representation
        final textPlain = data['text/plain'];
        if (textPlain is String) return textPlain;
        if (textPlain is List) return textPlain.join('');
        // Fallback: indicate non-text output
        final types = data.keys.toList();
        return '[Output: ${types.join(', ')}]';

      case 'error':
        final ename = output['ename'] as String? ?? 'Error';
        final evalue = output['evalue'] as String? ?? '';
        final traceback = output['traceback'] as List<dynamic>? ?? [];
        final tb = traceback.map(_stripAnsi).join('\n');
        return '$ename: $evalue\n$tb';

      default:
        return '';
    }
  }

  /// Strip ANSI escape codes from a string.
  String _stripAnsi(dynamic s) {
    return s.toString().replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');
  }

  /// Read a text file with line numbers.
  Future<ToolResult> _readTextFile(
    File file,
    FileReadInput input,
    int fileSize,
    DateTime modified,
  ) async {
    // Detect encoding and read content
    final (content, encoding) = await _readWithEncoding(file);

    final lines = content.split('\n');
    // Remove trailing empty line from split if file doesn't end with newline
    // Actually keep it for accurate line counting.

    final totalLines = lines.length;

    // Large file warning
    if (totalLines > largeFileLineThreshold &&
        input.limit == null &&
        input.offset == null) {
      return ToolResult.success(
        'Warning: File has $totalLines lines. '
        'Specify offset and limit to read specific portions.\n\n'
        'File: ${p.basename(file.path)}\n'
        'Size: ${_formatFileSize(fileSize)}\n'
        'Lines: $totalLines\n'
        'Encoding: $encoding\n'
        'Modified: ${modified.toIso8601String()}\n\n'
        'Reading first $defaultLimit lines:\n\n'
        '${_formatLines(lines, 0, defaultLimit)}',
        metadata: {
          'lineCount': totalLines,
          'truncated': true,
          'encoding': encoding,
          'size': fileSize,
          'modified': modified.toIso8601String(),
        },
      );
    }

    // Apply offset and limit
    final offset = ((input.offset ?? 1) - 1).clamp(0, totalLines);
    final limit = input.limit ?? defaultLimit;
    final end = (offset + limit).clamp(0, totalLines);

    final truncated = end < totalLines;

    var result = _formatLines(lines, offset, end);

    // Check if content is empty
    if (content.isEmpty) {
      result =
          'File exists but has empty contents: ${p.basename(file.path)}\n'
          'Size: ${_formatFileSize(fileSize)}';
    }

    // Truncate extremely long output
    if (result.length > maxOutputChars) {
      result =
          '${result.substring(0, maxOutputChars)}\n\n'
          '... output truncated (exceeded $maxOutputChars chars). '
          'Use offset/limit to read specific sections.';
    }

    final output = FileReadOutput(
      content: result,
      lineCount: end - offset,
      truncated: truncated,
      encoding: encoding,
      size: fileSize,
      modified: modified,
    );

    return ToolResult.success(output.content, metadata: output.toMetadata());
  }

  /// Format lines with line numbers in cat -n format.
  String _formatLines(List<String> lines, int start, int end) {
    final buf = StringBuffer();
    for (var i = start; i < end && i < lines.length; i++) {
      buf.writeln('${i + 1}\t${lines[i]}');
    }
    return buf.toString();
  }

  /// Read file content trying UTF-8 first, then Latin1 as fallback.
  Future<(String, String)> _readWithEncoding(File file) async {
    // Try UTF-8 first
    try {
      final content = await file.readAsString(encoding: utf8);
      // Verify it's valid UTF-8 by checking for replacement chars
      if (!content.contains('\uFFFD')) {
        return (content, 'utf-8');
      }
    } catch (_) {
      // UTF-8 failed
    }

    // Try Latin1 (always succeeds for any byte sequence)
    try {
      final content = await file.readAsString(encoding: latin1);
      return (content, 'latin1');
    } catch (_) {
      // Should not happen with latin1
    }

    // Final fallback: read as bytes and convert
    try {
      final bytes = await file.readAsBytes();
      final content = String.fromCharCodes(bytes);
      return (content, 'binary');
    } catch (e) {
      throw FileSystemException('Cannot read file: $e', file.path);
    }
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
