/// Pure-Dart deep link URI parser and builder for `neomage-cli://` links.
///
/// Extracted so URI validation (`parseDeepLink`, `buildDeepLink`) can run on
/// all runtimes (VM, Chrome Web, Wasm) without pulling UI/navigation packages.
library;

import '../security/neomage_network_guard.dart';

/// The custom URI protocol scheme.
const String deepLinkProtocol = 'neomage-cli';

/// macOS bundle ID for the URL handler app.
const String macosBundleId = 'com.neomage-url-handler';

/// Display name for the URL handler app.
const String appName = 'Neomage URL Handler';

/// Desktop file name for Linux registration.
const String desktopFileName = 'neomage-url-handler.desktop';

/// macOS app bundle name.
const String macosAppName = 'Neomage URL Handler.app';

/// Maximum length for pre-filled prompts.
/// 5000 chars — practical ceiling considering Windows cmd.exe limits.
const int maxQueryLength = 5000;

/// Maximum length for cwd parameter.
/// PATH_MAX on Linux is 4096.
const int maxCwdLength = 4096;

/// Stale FETCH_HEAD warning threshold (7 days).
const int staleFetchWarnMs = 7 * 24 * 60 * 60 * 1000;

/// Long prefill threshold for banner warning.
const int longPrefillThreshold = 1000;

/// Failure backoff period (24 hours).
const int failureBackoffMs = 24 * 60 * 60 * 1000;

/// Parsed deep link action.
class DeepLinkAction {
  final String? query;
  final String? cwd;
  final String? repo;

  const DeepLinkAction({this.query, this.cwd, this.repo});

  @override
  String toString() => 'DeepLinkAction(query: $query, cwd: $cwd, repo: $repo)';
}

/// GitHub owner/repo slug pattern (alphanumeric start to prevent CLI option injection).
final RegExp _repoSlugPattern = RegExp(
  r'^[A-Za-z0-9][A-Za-z0-9._\-]{0,99}\/[A-Za-z0-9][A-Za-z0-9._\-]{0,99}$',
);

final RegExp _invisibleOrBidiRegex = RegExp(
  r'[\u061C\u200B-\u200F\u2028-\u202F\u2060-\u206F\uFEFF\uFFF9-\uFFFB]',
);

/// Check if a string contains ASCII C0/DEL or C1 control characters
/// (0x00-0x1F, 0x7F-0x9F).
bool containsDeepLinkControlChars(String s) {
  for (int i = 0; i < s.length; i++) {
    final code = s.codeUnitAt(i);
    if (code <= 0x1f || (code >= 0x7f && code <= 0x9f)) return true;
  }
  return false;
}

/// Partially sanitize Unicode by removing hidden/invisible/BiDi characters.
String _partiallySanitizeUnicode(String input) {
  return input.replaceAll(_invisibleOrBidiRegex, '');
}

/// Parse a neomage-cli:// URI into a structured action.
/// Throws [FormatException] if the URI is malformed or contains dangerous characters.
DeepLinkAction parseDeepLink(String uri) {
  String? normalized;
  if (uri.startsWith('$deepLinkProtocol://')) {
    normalized = uri;
  } else if (uri.startsWith('$deepLinkProtocol:')) {
    normalized = uri.replaceFirst('$deepLinkProtocol:', '$deepLinkProtocol://');
  }

  if (normalized == null) {
    throw FormatException(
      'Invalid deep link: expected $deepLinkProtocol:// scheme, got "$uri"',
    );
  }

  final url = Uri.tryParse(normalized);
  if (url == null) {
    throw FormatException('Invalid deep link URL: "$uri"');
  }

  if (url.host != 'open') {
    throw FormatException('Unknown deep link action: "${url.host}"');
  }

  final cwd = url.queryParameters['cwd'];
  final repo = url.queryParameters['repo'];
  final rawQuery = url.queryParameters['q'];

  // Reject UNC shares (//host/share or \\host\share) and NT device paths (\??\)
  // to prevent SMB/NTLM exfiltration or Win32 device namespace bypasses.
  if (cwd != null &&
      (cwd.startsWith('//') ||
          cwd.startsWith(r'\\') ||
          cwd.startsWith(r'\??\'))) {
    throw FormatException(
      'Invalid cwd in deep link: UNC network shares or NT device paths are not allowed',
    );
  }

  // Validate cwd if present — must be an absolute path
  if (cwd != null &&
      !cwd.startsWith('/') &&
      !RegExp(r'^[a-zA-Z]:[/\\]').hasMatch(cwd)) {
    throw FormatException(
      'Invalid cwd in deep link: must be an absolute path, got "$cwd"',
    );
  }

  // Reject control characters, BiDi/invisible characters, and parent directory traversal in cwd
  if (cwd != null &&
      (containsDeepLinkControlChars(cwd) || _invisibleOrBidiRegex.hasMatch(cwd))) {
    throw FormatException(
      'Deep link cwd contains disallowed control or invisible characters',
    );
  }
  if (cwd != null && cwd.split(RegExp(r'[/\\]')).contains('..')) {
    throw FormatException(
      'Deep link cwd must not contain parent traversal segments ("..")',
    );
  }
  if (cwd != null && cwd.length > maxCwdLength) {
    throw FormatException(
      'Deep link cwd exceeds $maxCwdLength characters (got ${cwd.length})',
    );
  }
  if (cwd != null &&
      NeomageNetworkGuard.isProtectedSystemOrCredentialPath(cwd)) {
    throw FormatException(
      'Deep link cwd targets a protected system or credential directory',
    );
  }

  // Validate repo slug format
  if (repo != null) {
    final repoParts = repo.split('/');
    if (!_repoSlugPattern.hasMatch(repo) ||
        repoParts.length != 2 ||
        repoParts.any((s) => s == '.' || s == '..' || s.contains('..'))) {
      throw FormatException(
        'Invalid repo in deep link: expected "owner/repo", got "$repo"',
      );
    }
  }

  String? query;
  if (rawQuery != null) {
    if (containsDeepLinkControlChars(rawQuery)) {
      throw FormatException(
        'Deep link query contains disallowed control characters',
      );
    }
    if (rawQuery.trim().isNotEmpty) {
      query = _partiallySanitizeUnicode(rawQuery.trim());
      if (containsDeepLinkControlChars(query)) {
        throw FormatException(
          'Deep link query contains disallowed control characters',
        );
      }
      if (query.length > maxQueryLength) {
        throw FormatException(
          'Deep link query exceeds $maxQueryLength characters (got ${query.length})',
        );
      }
    }
  }

  return DeepLinkAction(query: query, cwd: cwd, repo: repo);
}

/// Build a neomage-cli:// deep link URL.
String buildDeepLink(DeepLinkAction action) {
  final params = <String, String>{};
  if (action.query != null) params['q'] = action.query!;
  if (action.cwd != null) params['cwd'] = action.cwd!;
  if (action.repo != null) params['repo'] = action.repo!;

  final uri = Uri(
    scheme: deepLinkProtocol,
    host: 'open',
    queryParameters: params.isEmpty ? null : params,
  );
  return uri.toString();
}
