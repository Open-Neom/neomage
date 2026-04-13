import '../../domain/models/compaction_policy.dart';

/// Static utility that marks identifiers for preservation during compaction.
///
/// Uses regex-based detection to find file paths, tool names, UUIDs, and URLs,
/// then wraps them in `<preserve>...</preserve>` tags so the compaction engine
/// knows to keep them intact.
class IdentifierPreserver {
  IdentifierPreserver._();

  /// Regex for Unix/Windows file paths.
  static final _filePathRegex = RegExp(
    r'(?:/[a-zA-Z0-9._\-]+)+\.[a-zA-Z0-9]+',
  );

  /// Regex for backtick-wrapped tool names (e.g. `Read`, `Bash`).
  static final _toolNameRegex = RegExp(r'`([a-zA-Z_][a-zA-Z0-9_]*)`');

  /// Regex for UUIDs (v4 and similar).
  static final _uuidRegex = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
  );

  /// Regex for URLs (http/https).
  static final _urlRegex = RegExp(
    r'https?://[^\s<>\])"]+',
  );

  /// Marks identifiers in [text] for preservation based on the given [policy].
  ///
  /// - [CompactionPolicy.strict]: preserves only file paths and UUIDs.
  /// - [CompactionPolicy.lenient]: preserves file paths, UUIDs, tool names,
  ///   and URLs.
  /// - [CompactionPolicy.custom]: same as lenient (caller can post-process).
  ///
  /// Returns text with matched sections wrapped in `<preserve>...</preserve>`.
  static String preserve(String text, CompactionPolicy policy) {
    if (text.isEmpty) return text;

    final patterns = <RegExp>[];

    switch (policy) {
      case CompactionPolicy.strict:
        patterns.addAll([_filePathRegex, _uuidRegex]);
        break;
      case CompactionPolicy.lenient:
      case CompactionPolicy.custom:
        patterns.addAll([_filePathRegex, _toolNameRegex, _uuidRegex, _urlRegex]);
        break;
    }

    var result = text;
    for (final pattern in patterns) {
      result = result.replaceAllMapped(pattern, (match) {
        final matched = match.group(0)!;
        // Avoid double-wrapping.
        if (_isAlreadyPreserved(result, match.start)) return matched;
        return '<preserve>$matched</preserve>';
      });
    }

    return result;
  }

  /// Checks if the match position is already inside a `<preserve>` tag.
  static bool _isAlreadyPreserved(String text, int position) {
    final before = text.substring(0, position);
    final openCount = '<preserve>'.allMatches(before).length;
    final closeCount = '</preserve>'.allMatches(before).length;
    return openCount > closeCount;
  }
}
