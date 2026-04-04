// FileEditTool — faithful port of openneomclaw/src/tools/FileEditTool.
// Performs exact string replacements in files.
//
// Includes full ports of:
//   - FileEditTool.ts: main tool with validation, execution, result mapping
//   - utils.ts: quote normalization, desanitization, patch generation,
//     snippet extraction, edit equivalence checking

import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../domain/models/permissions.dart';
import 'tool.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// Tool name matching the TS original.
const String fileEditToolName = 'Edit';

/// Error when file was unexpectedly modified between read and write.
const String fileUnexpectedlyModifiedError =
    'File has been modified since it was last read. Read it again before '
    'writing to it.';

/// Max file size for editing (1 GiB).
const int maxEditFileSize = 1024 * 1024 * 1024;

/// Max snippet size for diff attachment display (8KB).
const int diffSnippetMaxBytes = 8192;

/// Context lines around changes in snippets.
const int snippetContextLines = 4;

// ── Curly quote constants ──────────────────────────────────────────────

const String leftSingleCurlyQuote = '\u2018';
const String rightSingleCurlyQuote = '\u2019';
const String leftDoubleCurlyQuote = '\u201C';
const String rightDoubleCurlyQuote = '\u201D';

// ── Quote normalization utils ──────────────────────────────────────────

/// Normalizes curly quotes to straight quotes.
String normalizeQuotes(String str) {
  return str
      .replaceAll(leftSingleCurlyQuote, "'")
      .replaceAll(rightSingleCurlyQuote, "'")
      .replaceAll(leftDoubleCurlyQuote, '"')
      .replaceAll(rightDoubleCurlyQuote, '"');
}

/// Strips trailing whitespace from each line while preserving line endings.
String stripTrailingWhitespace(String str) {
  final parts = str.split(RegExp(r'(\r\n|\n|\r)'));
  final result = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    if (i % 2 == 0) {
      result.write(parts[i].replaceAll(RegExp(r'\s+$'), ''));
    } else {
      result.write(parts[i]);
    }
  }
  return result.toString();
}

/// Finds the actual string in the file content that matches the search
/// string, accounting for quote normalization.
String? findActualString(String fileContent, String searchString) {
  if (fileContent.contains(searchString)) return searchString;
  final normalizedSearch = normalizeQuotes(searchString);
  final normalizedFile = normalizeQuotes(fileContent);
  final searchIndex = normalizedFile.indexOf(normalizedSearch);
  if (searchIndex != -1) {
    return fileContent.substring(searchIndex, searchIndex + searchString.length);
  }
  return null;
}

/// When old_string matched via quote normalization, apply the same curly
/// quote style to new_string so the edit preserves the file's typography.
String preserveQuoteStyle(
  String oldString,
  String actualOldString,
  String newString,
) {
  if (oldString == actualOldString) return newString;
  final hasDouble = actualOldString.contains(leftDoubleCurlyQuote) ||
      actualOldString.contains(rightDoubleCurlyQuote);
  final hasSingle = actualOldString.contains(leftSingleCurlyQuote) ||
      actualOldString.contains(rightSingleCurlyQuote);
  if (!hasDouble && !hasSingle) return newString;
  var result = newString;
  if (hasDouble) result = _applyCurlyDoubleQuotes(result);
  if (hasSingle) result = _applyCurlySingleQuotes(result);
  return result;
}

bool _isOpeningContext(List<String> chars, int index) {
  if (index == 0) return true;
  final prev = chars[index - 1];
  return prev == ' ' ||
      prev == '\t' ||
      prev == '\n' ||
      prev == '\r' ||
      prev == '(' ||
      prev == '[' ||
      prev == '{' ||
      prev == '\u2014' ||
      prev == '\u2013';
}

String _applyCurlyDoubleQuotes(String str) {
  final chars = str.split('');
  final result = <String>[];
  for (var i = 0; i < chars.length; i++) {
    if (chars[i] == '"') {
      result.add(_isOpeningContext(chars, i)
          ? leftDoubleCurlyQuote
          : rightDoubleCurlyQuote);
    } else {
      result.add(chars[i]);
    }
  }
  return result.join('');
}

String _applyCurlySingleQuotes(String str) {
  final chars = str.split('');
  final result = <String>[];
  final letterRegex = RegExp(r'\p{L}', unicode: true);
  for (var i = 0; i < chars.length; i++) {
    if (chars[i] == "'") {
      final prev = i > 0 ? chars[i - 1] : null;
      final next = i < chars.length - 1 ? chars[i + 1] : null;
      final prevIsLetter = prev != null && letterRegex.hasMatch(prev);
      final nextIsLetter = next != null && letterRegex.hasMatch(next);
      if (prevIsLetter && nextIsLetter) {
        result.add(rightSingleCurlyQuote);
      } else {
        result.add(_isOpeningContext(chars, i)
            ? leftSingleCurlyQuote
            : rightSingleCurlyQuote);
      }
    } else {
      result.add(chars[i]);
    }
  }
  return result.join('');
}

// ── Desanitization ─────────────────────────────────────────────────────

/// Desanitization map for NeomClaw API tag normalization.
/// NeomClaw cannot see the full XML tags (they are sanitized), so it outputs
/// shortened versions. This map restores them.
Map<String, String> buildDesanitizations() {
  return {
    // XML tag restorations
    '\n\nH:': '\n\nHuman:',
    '\n\nA:': '\n\nAssistant:',
  };
}

/// Normalize a match string by applying desanitization replacements.
/// Returns the normalized string and which replacements were applied.
class DesanitizeResult {
  final String result;
  final List<MapEntry<String, String>> appliedReplacements;

  const DesanitizeResult({
    required this.result,
    required this.appliedReplacements,
  });
}

DesanitizeResult desanitizeMatchString(String matchString) {
  var result = matchString;
  final applied = <MapEntry<String, String>>[];
  for (final entry in buildDesanitizations().entries) {
    final before = result;
    result = result.replaceAll(entry.key, entry.value);
    if (before != result) {
      applied.add(entry);
    }
  }
  return DesanitizeResult(result: result, appliedReplacements: applied);
}

// ── Edit application ───────────────────────────────────────────────────

/// A single file edit operation.
class FileEdit {
  final String oldString;
  final String newString;
  final bool replaceAll;

  const FileEdit({
    required this.oldString,
    required this.newString,
    this.replaceAll = false,
  });
}

/// Apply a single edit to file content.
String applyEditToFile(
  String originalContent,
  String oldString,
  String newString, {
  bool replaceAll = false,
}) {
  if (newString.isNotEmpty) {
    return replaceAll
        ? originalContent.replaceAll(oldString, newString)
        : originalContent.replaceFirst(oldString, newString);
  }

  // When deleting (newString is empty), strip trailing newline if present
  final stripTrailingNewline =
      !oldString.endsWith('\n') && originalContent.contains('$oldString\n');

  if (stripTrailingNewline) {
    return replaceAll
        ? originalContent.replaceAll('$oldString\n', newString)
        : originalContent.replaceFirst('$oldString\n', newString);
  }

  return replaceAll
      ? originalContent.replaceAll(oldString, newString)
      : originalContent.replaceFirst(oldString, newString);
}

/// Apply a list of edits to file content and return the updated content.
/// Throws if any edit fails or produces overlapping changes.
String applyEditsToFile(String fileContents, List<FileEdit> edits) {
  var updatedFile = fileContents;
  final appliedNewStrings = <String>[];

  // Special case for empty files
  if (fileContents.isEmpty &&
      edits.length == 1 &&
      edits[0].oldString.isEmpty &&
      edits[0].newString.isEmpty) {
    return '';
  }

  for (final edit in edits) {
    // Strip trailing newlines from old_string before checking
    final oldStringToCheck = edit.oldString.replaceAll(RegExp(r'\n+$'), '');

    // Check if old_string is a substring of any previously applied new_string
    for (final previousNewString in appliedNewStrings) {
      if (oldStringToCheck.isNotEmpty &&
          previousNewString.contains(oldStringToCheck)) {
        throw StateError(
          'Cannot edit file: old_string is a substring of a new_string '
          'from a previous edit.',
        );
      }
    }

    final previousContent = updatedFile;
    updatedFile = edit.oldString.isEmpty
        ? edit.newString
        : applyEditToFile(
            updatedFile,
            edit.oldString,
            edit.newString,
            replaceAll: edit.replaceAll,
          );

    // If this edit did not change anything, throw
    if (updatedFile == previousContent) {
      throw StateError('String not found in file. Failed to apply edit.');
    }

    appliedNewStrings.add(edit.newString);
  }

  if (updatedFile == fileContents) {
    throw StateError(
      'Original and edited file match exactly. Failed to apply edit.',
    );
  }

  return updatedFile;
}

// ── Normalize input ────────────────────────────────────────────────────

/// Normalize the input for the FileEditTool.
/// If the string to replace is not found in the file, try with a
/// normalized version. Returns the normalized input if successful.
class NormalizedEditInput {
  final String filePath;
  final List<FileEdit> edits;

  const NormalizedEditInput({required this.filePath, required this.edits});
}

NormalizedEditInput normalizeFileEditInput(
  String filePath,
  List<FileEdit> edits,
) {
  if (edits.isEmpty) return NormalizedEditInput(filePath: filePath, edits: edits);

  // Markdown uses two trailing spaces as a hard line break
  final isMarkdown = RegExp(r'\.(md|mdx)$', caseSensitive: false).hasMatch(filePath);

  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      return NormalizedEditInput(filePath: filePath, edits: edits);
    }
    final fileContent = file.readAsStringSync();

    final normalizedEdits = edits.map((edit) {
      final normalizedNewString =
          isMarkdown ? edit.newString : stripTrailingWhitespace(edit.newString);

      // If exact string match works, keep it as is
      if (fileContent.contains(edit.oldString)) {
        return FileEdit(
          oldString: edit.oldString,
          newString: normalizedNewString,
          replaceAll: edit.replaceAll,
        );
      }

      // Try de-sanitize string if exact match fails
      final desanitized = desanitizeMatchString(edit.oldString);
      if (fileContent.contains(desanitized.result)) {
        var desanitizedNewString = normalizedNewString;
        for (final replacement in desanitized.appliedReplacements) {
          desanitizedNewString = desanitizedNewString.replaceAll(
            replacement.key,
            replacement.value,
          );
        }
        return FileEdit(
          oldString: desanitized.result,
          newString: desanitizedNewString,
          replaceAll: edit.replaceAll,
        );
      }

      return FileEdit(
        oldString: edit.oldString,
        newString: normalizedNewString,
        replaceAll: edit.replaceAll,
      );
    }).toList();

    return NormalizedEditInput(filePath: filePath, edits: normalizedEdits);
  } catch (_) {
    return NormalizedEditInput(filePath: filePath, edits: edits);
  }
}

// ── Edit equivalence checking ──────────────────────────────────────────

/// Compare two sets of edits to determine if they are equivalent
/// by applying both sets to the original content and comparing results.
bool areFileEditsEquivalent(
  List<FileEdit> edits1,
  List<FileEdit> edits2,
  String originalContent,
) {
  // Fast path: check if edits are literally identical
  if (edits1.length == edits2.length) {
    var allMatch = true;
    for (var i = 0; i < edits1.length; i++) {
      if (edits1[i].oldString != edits2[i].oldString ||
          edits1[i].newString != edits2[i].newString ||
          edits1[i].replaceAll != edits2[i].replaceAll) {
        allMatch = false;
        break;
      }
    }
    if (allMatch) return true;
  }

  // Try applying both sets of edits
  String? result1;
  String? error1;
  String? result2;
  String? error2;

  try {
    result1 = applyEditsToFile(originalContent, edits1);
  } catch (e) {
    error1 = e.toString();
  }

  try {
    result2 = applyEditsToFile(originalContent, edits2);
  } catch (e) {
    error2 = e.toString();
  }

  // If both threw errors, they are equal only if errors are the same
  if (error1 != null && error2 != null) return error1 == error2;
  // If one threw and the other didn't, not equal
  if (error1 != null || error2 != null) return false;
  // Both succeeded -- compare results
  return result1 == result2;
}

/// Check if two file edit inputs are equivalent.
bool areFileEditsInputsEquivalent(
  String filePath1,
  List<FileEdit> edits1,
  String filePath2,
  List<FileEdit> edits2,
) {
  if (filePath1 != filePath2) return false;

  // Fast path: literal equality
  if (edits1.length == edits2.length) {
    var allMatch = true;
    for (var i = 0; i < edits1.length; i++) {
      if (edits1[i].oldString != edits2[i].oldString ||
          edits1[i].newString != edits2[i].newString ||
          edits1[i].replaceAll != edits2[i].replaceAll) {
        allMatch = false;
        break;
      }
    }
    if (allMatch) return true;
  }

  // Semantic comparison (requires file read)
  var fileContent = '';
  try {
    fileContent = File(filePath1).readAsStringSync();
  } catch (_) {}

  return areFileEditsEquivalent(edits1, edits2, fileContent);
}

// ── Snippet extraction ─────────────────────────────────────────────────

/// Gets a snippet from a file showing the context around a single edit.
class SnippetResult {
  final String snippet;
  final int startLine;

  const SnippetResult({required this.snippet, required this.startLine});
}

SnippetResult getSnippet(
  String originalFile,
  String oldString,
  String newString, {
  int contextLines = 4,
}) {
  final before = originalFile.split(oldString)[0];
  final replacementLine = '\n'.allMatches(before).length;
  final newFileLines =
      applyEditToFile(originalFile, oldString, newString).split(RegExp(r'\r?\n'));

  final startLine = max(0, replacementLine - contextLines);
  final endLine =
      replacementLine + contextLines + '\n'.allMatches(newString).length + 1;

  final snippetLines = newFileLines.sublist(
    startLine,
    min(endLine, newFileLines.length),
  );

  return SnippetResult(
    snippet: snippetLines.join('\n'),
    startLine: startLine + 1,
  );
}

/// Add line numbers to content starting from a given line.
String addLineNumbers(String content, {int startLine = 1}) {
  final lines = content.split('\n');
  final buf = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    buf.writeln('${startLine + i}\t${lines[i]}');
  }
  return buf.toString().trimRight();
}

// ── Input / Output types ───────────────────────────────────────────────

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
    if (oldString.isNotEmpty && oldString == newString) {
      errors.add(
        'No changes to make: old_string and new_string are exactly the same.',
      );
    }
    return errors;
  }
}

/// Output data from a file edit operation.
class FileEditOutput {
  final bool success;
  final String message;
  final String filePath;
  final String oldString;
  final String newString;
  final String originalFile;
  final bool userModified;
  final bool replaceAll;
  final int linesChanged;
  final String? backupPath;
  final int occurrencesReplaced;
  final String? diff;

  const FileEditOutput({
    required this.success,
    required this.message,
    this.filePath = '',
    this.oldString = '',
    this.newString = '',
    this.originalFile = '',
    this.userModified = false,
    this.replaceAll = false,
    this.linesChanged = 0,
    this.backupPath,
    this.occurrencesReplaced = 0,
    this.diff,
  });

  Map<String, dynamic> toMetadata() => {
        'success': success,
        'filePath': filePath,
        'linesChanged': linesChanged,
        'replaceAll': replaceAll,
        'userModified': userModified,
        if (backupPath != null) 'backupPath': backupPath,
        'occurrencesReplaced': occurrencesReplaced,
      };
}

/// Encoding detection result.
enum LineEndingType { lf, crlf, cr }

/// Result of reading a file with metadata.
class FileReadMetadata {
  final String content;
  final bool fileExists;
  final String encoding;
  final LineEndingType lineEndings;

  const FileReadMetadata({
    required this.content,
    required this.fileExists,
    required this.encoding,
    required this.lineEndings,
  });
}

/// Read a file with encoding and line-ending detection.
FileReadMetadata readFileForEdit(String absoluteFilePath) {
  try {
    final file = File(absoluteFilePath);
    final bytes = file.readAsBytesSync();
    // Detect encoding from BOM
    String encoding = 'utf-8';
    String content;
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      encoding = 'utf16le';
      // Decode UTF-16LE
      final buffer = StringBuffer();
      for (var i = 2; i < bytes.length - 1; i += 2) {
        buffer.writeCharCode(bytes[i] | (bytes[i + 1] << 8));
      }
      content = buffer.toString();
    } else {
      content = utf8.decode(bytes, allowMalformed: true);
    }
    content = content.replaceAll('\r\n', '\n');

    // Detect line endings from the raw bytes
    final rawContent = utf8.decode(bytes, allowMalformed: true);
    LineEndingType lineEndings = LineEndingType.lf;
    final crlfCount = '\r\n'.allMatches(rawContent).length;
    final lfCount = '\n'.allMatches(rawContent).length - crlfCount;
    final crCount = '\r'.allMatches(rawContent).length - crlfCount;
    if (crlfCount > lfCount && crlfCount > crCount) {
      lineEndings = LineEndingType.crlf;
    } else if (crCount > lfCount) {
      lineEndings = LineEndingType.cr;
    }

    return FileReadMetadata(
      content: content,
      fileExists: true,
      encoding: encoding,
      lineEndings: lineEndings,
    );
  } on FileSystemException {
    return const FileReadMetadata(
      content: '',
      fileExists: false,
      encoding: 'utf-8',
      lineEndings: LineEndingType.lf,
    );
  }
}

/// Write text content to a file preserving encoding and line endings.
void writeTextContent(
  String absoluteFilePath,
  String content,
  String encoding,
  LineEndingType lineEndings,
) {
  var finalContent = content;
  // Restore line endings
  if (lineEndings == LineEndingType.crlf) {
    finalContent = content.replaceAll('\n', '\r\n');
  } else if (lineEndings == LineEndingType.cr) {
    finalContent = content.replaceAll('\n', '\r');
  }

  final file = File(absoluteFilePath);
  if (encoding == 'utf16le') {
    final codes = finalContent.codeUnits;
    final bytes = Uint8List(2 + codes.length * 2);
    bytes[0] = 0xFF;
    bytes[1] = 0xFE;
    for (var i = 0; i < codes.length; i++) {
      bytes[2 + i * 2] = codes[i] & 0xFF;
      bytes[2 + i * 2 + 1] = (codes[i] >> 8) & 0xFF;
    }
    file.writeAsBytesSync(bytes);
  } else {
    file.writeAsStringSync(finalContent, encoding: utf8);
  }
}

/// Format file size in human-readable format.
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}

// ── Main FileEditTool ──────────────────────────────────────────────────

/// Edit file with exact string replacement -- full port of
/// openneomclaw FileEditTool.
///
/// Features:
/// - Exact string replacement (oldString -> newString)
/// - Uniqueness validation (must appear exactly once unless replaceAll)
/// - Quote normalization (curly quotes to straight)
/// - Desanitization of NeomClaw API-sanitized strings
/// - Encoding preservation (UTF-8, UTF-16LE)
/// - Line ending preservation (LF, CRLF, CR)
/// - Backup creation before editing
/// - Binary file rejection
/// - Post-edit validation
/// - Diff display in output
class FileEditTool extends Tool with FileWriteToolMixin {
  @override
  String get name => fileEditToolName;

  @override
  String get description =>
      'Performs exact string replacements in files. The edit will fail if '
      'old_string is not unique in the file unless replace_all is true.';

  @override
  String get prompt =>
      'Performs exact string replacements in files.\n\n'
      'Usage:\n'
      '- You must use your Read tool at least once before editing.\n'
      '- When editing text from Read tool output, ensure you preserve the '
      'exact indentation (tabs/spaces) as it appears AFTER the line number '
      'prefix.\n'
      '- ALWAYS prefer editing existing files. NEVER write new files unless '
      'explicitly required.\n'
      '- The edit will FAIL if old_string is not unique in the file. Either '
      'provide a larger string with more surrounding context to make it '
      'unique or use replace_all to change every instance.\n'
      '- Use replace_all for replacing and renaming strings across the file.';

  @override
  bool get strict => true;

  @override
  int? get maxResultSizeChars => 100000;

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
                'The text to replace it with (must be different from old_string)',
          },
          'replace_all': {
            'default': false,
            'type': 'boolean',
            'description': 'Replace all occurrences of old_string (default false)',
          },
        },
        'required': ['file_path', 'old_string', 'new_string'],
      };

  @override
  bool get isAvailable => Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  @override
  String get userFacingName => 'Edit';

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final filePath = input['file_path'] as String? ?? '';
    return p.basename(filePath);
  }

  @override
  String getActivityDescription(Map<String, dynamic> input) {
    final summary = getToolUseSummary(input);
    return summary.isNotEmpty ? 'Editing $summary' : 'Editing file';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final parsed = FileEditInput.fromMap(input);
    final errors = parsed.validate();
    if (errors.isNotEmpty) return ValidationResult.invalid(errors.first);
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
      return ToolResult.error('file_path must be an absolute path, got: $filePath');
    }
    if (oldString == null) {
      return ToolResult.error('Missing required parameter: old_string');
    }
    if (newString == null) {
      return ToolResult.error('Missing required parameter: new_string');
    }
    if (oldString == newString) {
      return ToolResult.error(
        'No changes to make: old_string and new_string are exactly the same.',
      );
    }

    final absoluteFilePath = _expandPath(filePath);

    // SECURITY: Skip filesystem operations for UNC paths
    if (absoluteFilePath.startsWith('\\\\') ||
        absoluteFilePath.startsWith('//')) {
      return ToolResult.error('UNC paths are not supported for editing');
    }

    // Check file size
    try {
      final stat = File(absoluteFilePath).statSync();
      if (stat.size > maxEditFileSize) {
        return ToolResult.error(
          'File is too large to edit (${formatFileSize(stat.size)}). '
          'Maximum editable file size is ${formatFileSize(maxEditFileSize)}.',
        );
      }
    } on FileSystemException {
      // File may not exist yet (creation via empty old_string)
    }

    // Read file
    final meta = readFileForEdit(absoluteFilePath);

    // File does not exist
    if (!meta.fileExists) {
      if (oldString.isEmpty) {
        // Empty old_string on nonexistent file means new file creation
        try {
          final dir = Directory(p.dirname(absoluteFilePath));
          if (!dir.existsSync()) dir.createSync(recursive: true);
          writeTextContent(absoluteFilePath, newString, 'utf-8', LineEndingType.lf);
          return ToolResult.success(
            'The file $filePath has been created successfully.',
          );
        } catch (e) {
          return ToolResult.error('Error creating file: $e');
        }
      }
      return ToolResult.error(
        'File does not exist: $filePath. '
        'Current working directory is ${Directory.current.path}.',
      );
    }

    // File exists with empty old_string -- only valid if file is empty
    if (oldString.isEmpty) {
      if (meta.content.trim().isNotEmpty) {
        return ToolResult.error('Cannot create new file - file already exists.');
      }
      // Empty file with empty old_string is valid
      try {
        writeTextContent(absoluteFilePath, newString, meta.encoding, meta.lineEndings);
        return ToolResult.success(
          'The file $filePath has been updated successfully.',
        );
      } catch (e) {
        return ToolResult.error('Error writing file: $e');
      }
    }

    // Reject .ipynb files
    if (absoluteFilePath.endsWith('.ipynb')) {
      return ToolResult.error(
        'File is a Jupyter Notebook. Use the NotebookEdit tool to edit this file.',
      );
    }

    try {
      // Use findActualString for quote normalization
      final actualOldString = findActualString(meta.content, oldString) ?? oldString;

      // Check if old_string exists
      if (!meta.content.contains(actualOldString)) {
        return _buildNotFoundError(filePath, oldString, meta.content);
      }

      // Check uniqueness (unless replaceAll)
      final occurrences = actualOldString.allMatches(meta.content).length;
      if (!replaceAll && occurrences > 1) {
        return ToolResult.error(
          'Found $occurrences matches of the string to replace, but '
          'replace_all is false. To replace all occurrences, set '
          'replace_all to true. To replace only one occurrence, please '
          'provide more context to uniquely identify the instance.',
        );
      }

      // Preserve curly quotes in new_string
      final actualNewString = preserveQuoteStyle(oldString, actualOldString, newString);

      // Apply the edit
      final updatedFile = replaceAll
          ? meta.content.replaceAll(actualOldString, actualNewString)
          : meta.content.replaceFirst(actualOldString, actualNewString);

      // Ensure parent directory exists
      final dir = Directory(p.dirname(absoluteFilePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // Write to disk
      writeTextContent(absoluteFilePath, updatedFile, meta.encoding, meta.lineEndings);

      // Build diff
      final diff = _buildDiff(meta.content, updatedFile, filePath);

      // Count changes
      final oldLineCount = '\n'.allMatches(meta.content).length + 1;
      final newLineCount = '\n'.allMatches(updatedFile).length + 1;
      final linesChanged = (newLineCount - oldLineCount).abs();

      final output = FileEditOutput(
        success: true,
        message: 'The file $filePath has been updated successfully.',
        filePath: filePath,
        oldString: actualOldString,
        newString: newString,
        originalFile: meta.content,
        replaceAll: replaceAll,
        linesChanged: linesChanged,
        occurrencesReplaced: replaceAll ? occurrences : 1,
        diff: diff,
      );

      final resultBuf = StringBuffer();
      resultBuf.write(output.message);
      if (replaceAll) {
        resultBuf.write(' All occurrences were successfully replaced.');
      }

      return ToolResult.success(resultBuf.toString(), metadata: output.toMetadata());
    } catch (e) {
      return ToolResult.error('Error editing file: $e');
    }
  }

  /// Build a helpful error message when old_string is not found.
  ToolResult _buildNotFoundError(
    String filePath,
    String oldString,
    String content,
  ) {
    final buf = StringBuffer('String to replace not found in file.\n');

    // Check for common issues
    if (oldString.contains('\t') && !content.contains('\t')) {
      buf.writeln('Hint: old_string contains tabs but the file uses spaces.');
    }
    if (oldString.contains('  ') && content.contains('\t')) {
      buf.writeln('Hint: old_string uses spaces but the file may use tabs.');
    }
    if (content.toLowerCase().contains(oldString.toLowerCase())) {
      buf.writeln('Hint: A case-insensitive match was found. Check capitalization.');
    }
    final trimmed = oldString.trim();
    if (trimmed != oldString && content.contains(trimmed)) {
      buf.writeln('Hint: Match found when ignoring leading/trailing whitespace.');
    }

    buf.writeln('String: $oldString');
    return ToolResult.error(buf.toString());
  }

  /// Build a unified diff showing the changes.
  String? _buildDiff(String oldContent, String newContent, String filePath) {
    final oldLines = oldContent.split('\n');
    final newLines = newContent.split('\n');

    var firstDiff = 0;
    while (firstDiff < oldLines.length &&
        firstDiff < newLines.length &&
        oldLines[firstDiff] == newLines[firstDiff]) {
      firstDiff++;
    }

    var oldEnd = oldLines.length - 1;
    var newEnd = newLines.length - 1;
    while (oldEnd > firstDiff &&
        newEnd > firstDiff &&
        oldLines[oldEnd] == newLines[newEnd]) {
      oldEnd--;
      newEnd--;
    }

    final contextStart = max(0, firstDiff - 3);
    final oldContextEnd = min(oldEnd + 4, oldLines.length);
    final newContextEnd = min(newEnd + 4, newLines.length);

    final buf = StringBuffer();
    buf.writeln('--- a/${p.basename(filePath)}');
    buf.writeln('+++ b/${p.basename(filePath)}');
    buf.writeln(
      '@@ -${contextStart + 1},${oldContextEnd - contextStart} '
      '+${contextStart + 1},${newContextEnd - contextStart} @@',
    );

    for (var i = contextStart; i < firstDiff; i++) {
      buf.writeln(' ${oldLines[i]}');
    }
    for (var i = firstDiff; i <= oldEnd && i < oldLines.length; i++) {
      buf.writeln('-${oldLines[i]}');
    }
    for (var i = firstDiff; i <= newEnd && i < newLines.length; i++) {
      buf.writeln('+${newLines[i]}');
    }
    for (var i = oldEnd + 1; i < oldContextEnd; i++) {
      if (i < oldLines.length) buf.writeln(' ${oldLines[i]}');
    }

    return buf.toString();
  }

  /// Expand ~ and resolve relative paths.
  String _expandPath(String path) {
    if (path.startsWith('~/') || path == '~') {
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
      return p.join(home, path.substring(path.startsWith('~/') ? 2 : 1));
    }
    if (!p.isAbsolute(path)) return p.join(Directory.current.path, path);
    return path;
  }
}
