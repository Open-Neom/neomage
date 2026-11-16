// WebSearchTool — port of neomage/src/tools/WebSearchTool/.
// Performs web searches via API, returns structured results with links.

import 'package:neomage/utils/security/neomage_network_guard.dart';

import '../api/api_provider.dart';

/// Web search input.
class WebSearchInput {
  final String query;
  final List<String>? allowedDomains;
  final List<String>? blockedDomains;

  const WebSearchInput({
    required this.query,
    this.allowedDomains,
    this.blockedDomains,
  });

  factory WebSearchInput.fromJson(Map<String, dynamic> json) => WebSearchInput(
    query: json['query'] as String,
    allowedDomains: (json['allowed_domains'] as List?)?.cast<String>(),
    blockedDomains: (json['blocked_domains'] as List?)?.cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'query': query,
    if (allowedDomains != null) 'allowed_domains': allowedDomains,
    if (blockedDomains != null) 'blocked_domains': blockedDomains,
  };
}

/// A single search result.
class SearchResult {
  final String title;
  final String url;
  final String? displayUrl;
  final String? snippet;

  const SearchResult({
    required this.title,
    required this.url,
    this.displayUrl,
    this.snippet,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    displayUrl: json['display_url'] as String?,
    snippet: json['snippet'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'url': url,
    if (displayUrl != null) 'display_url': displayUrl,
    if (snippet != null) 'snippet': snippet,
  };
}

/// Web search output.
class WebSearchOutput {
  final String query;
  final List<dynamic>
  results; // Mix of SearchResult and String (text summaries)
  final double durationSeconds;
  final int searchCount;

  const WebSearchOutput({
    required this.query,
    required this.results,
    required this.durationSeconds,
    this.searchCount = 1,
  });

  /// Format for display with Markdown/URL/ChatML injection neutralization.
  String format() {
    final safeQuery = _sanitizeSearchText(query).replaceAll('\n', ' ').trim();
    final buf = StringBuffer()
      ..writeln('Web search results for query: "$safeQuery"\n');

    for (final result in results) {
      if (result is String) {
        buf.writeln(_sanitizeSearchText(result));
      } else if (result is SearchResult) {
        buf.writeln(_formatSearchResultLine(result));
        if (result.snippet != null) {
          buf.writeln(
            '  ${_sanitizeSearchText(result.snippet!).replaceAll('\n', ' ')}',
          );
        }
      } else if (result is List<SearchResult>) {
        for (final r in result) {
          buf.writeln(_formatSearchResultLine(r));
        }
      }
    }

    buf.writeln();
    buf.writeln(
      'REMINDER: You MUST include the sources above in your response '
      'to the user using markdown hyperlinks.',
    );

    return buf.toString();
  }
}

final RegExp _searchControlChars = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);

final RegExp _searchChatTokens = RegExp(
  r'<\|channel>\s*thought\b[\s\S]*?<channel\|>|<\|channel>\s*thought\b[\s\S]*$|<\|(?:im_start|im_end|endoftext|eot_id|start_header_id|end_header_id|/?turn)\|>|<\|channel>|<channel\|>|<(?:start|end)_of_turn>',
  caseSensitive: false,
);

String _sanitizeSearchText(String raw) =>
    raw.replaceAll(_searchChatTokens, '').replaceAll(_searchControlChars, ' ');

String _sanitizeMarkdownTitle(String rawTitle) {
  final stripped = _sanitizeSearchText(rawTitle).trim();
  if (stripped.isEmpty) return 'Untitled';
  return stripped
      .replaceAll(r'\', r'\\')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
}

String? _sanitizeSearchUrl(String rawUrl) {
  if (_searchControlChars.hasMatch(rawUrl)) return null;
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty ||
      trimmed.contains(r'\') ||
      trimmed.toLowerCase().contains('%5c')) {
    return null;
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;
  if (NeomageNetworkGuard.isPrivateOrReservedHost(
    uri.host,
    allowLoopback: false,
  )) {
    return null;
  }
  return uri
      .toString()
      .replaceAll('(', '%28')
      .replaceAll(')', '%29')
      .replaceAll(' ', '%20');
}

String _formatSearchResultLine(SearchResult result) {
  final safeTitle = _sanitizeMarkdownTitle(result.title);
  final safeUrl = _sanitizeSearchUrl(result.url);
  if (safeUrl == null) {
    return '- $safeTitle';
  }
  return '- [$safeTitle]($safeUrl)';
}

/// Maximum result output length.
const maxSearchOutputLength = 100000;

/// Maximum search query length.
const maxSearchQueryLength = 2000;

/// Maximum searches per query.
const maxSearchesPerQuery = 8;

/// Validate web search input.
String? validateSearchInput(WebSearchInput input) {
  if (input.query.contains('\x00')) {
    return 'Search query must not contain NUL bytes';
  }
  if (input.query.trim().length < 2) {
    return 'Search query must be at least 2 characters';
  }
  if (input.query.length > maxSearchQueryLength) {
    return 'Search query must not exceed $maxSearchQueryLength characters';
  }
  if (input.allowedDomains != null && input.blockedDomains != null) {
    return 'Cannot specify both allowed_domains and blocked_domains';
  }
  for (final d in <String>[
    ...?input.allowedDomains,
    ...?input.blockedDomains,
  ]) {
    if (d.trim().isEmpty || _searchControlChars.hasMatch(d) || d.contains(' ')) {
      return 'Invalid domain filter: $d';
    }
  }
  return null;
}

/// Web search tool schema for API providers that support native search.
Map<String, dynamic> makeSearchToolSchema({
  List<String>? allowedDomains,
  List<String>? blockedDomains,
}) => {
  'type': 'web_search_20250305',
  'name': 'web_search',
  'max_uses': maxSearchesPerQuery,
  'allowed_domains': ?allowedDomains,
  'blocked_domains': ?blockedDomains,
};

/// Search progress event.
sealed class SearchProgress {
  const SearchProgress();
}

class SearchQueryUpdate extends SearchProgress {
  final String query;
  const SearchQueryUpdate(this.query);
}

class SearchResultsReceived extends SearchProgress {
  final int resultCount;
  final String query;
  const SearchResultsReceived({required this.resultCount, required this.query});
}

/// Process search results from an API response containing web_search_tool_result blocks.
WebSearchOutput processSearchResponse(
  String originalQuery,
  List<Map<String, dynamic>> contentBlocks,
  double durationSeconds,
) {
  final results = <dynamic>[];
  var searchCount = 0;

  var currentText = StringBuffer();
  var inText = true;

  for (final block in contentBlocks) {
    final type = block['type'] as String?;

    if (type == 'text') {
      final text = block['text'] as String? ?? '';
      if (!inText && currentText.isNotEmpty) {
        results.add(currentText.toString());
        currentText = StringBuffer();
      }
      inText = true;
      currentText.write(text);
    } else if (type == 'web_search_tool_result') {
      if (inText && currentText.isNotEmpty) {
        results.add(currentText.toString());
        currentText = StringBuffer();
        inText = false;
      }

      searchCount++;
      final content = block['content'] as List?;
      if (content != null) {
        final searchResults = content
            .whereType<Map<String, dynamic>>()
            .where((r) => r.containsKey('url'))
            .map((r) => SearchResult.fromJson(r))
            .toList();
        if (searchResults.isNotEmpty) {
          results.add(searchResults);
        }
      }

      // Check for errors
      final errorCode = block['error_code'] as String?;
      if (errorCode != null) {
        results.add('Search error: $errorCode');
      }
    }
  }

  // Flush remaining text
  if (currentText.isNotEmpty) {
    results.add(currentText.toString());
  }

  return WebSearchOutput(
    query: originalQuery,
    results: results,
    durationSeconds: durationSeconds,
    searchCount: searchCount,
  );
}

/// Check if web search is enabled for a given API provider.
bool isWebSearchEnabled(ApiProviderType provider, String modelName) {
  return switch (provider) {
    ApiProviderType.anthropic => true,
    ApiProviderType.vertex => modelName.contains('4'),
    ApiProviderType.bedrock => true,
    ApiProviderType.gemini => true,
    ApiProviderType.openai => false,
    ApiProviderType.qwen => false,
    ApiProviderType.deepseek => false,
    ApiProviderType.ollama => false,
    ApiProviderType.custom => false,
  };
}

/// System prompt for web search.
String webSearchSystemPrompt() {
  final now = DateTime.now();
  final months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  final currentMonth = months[now.month - 1];
  final currentYear = now.year;

  return '''
You are an assistant for performing web searches.

When searching:
- Use specific, targeted queries
- Include relevant technical terms
- Try different phrasings if initial search doesn't yield results
- The current date is $currentMonth $currentYear — use current year when searching
- Web search is available globally

After searching, you MUST include a Sources section with markdown hyperlinks to the pages you referenced.''';
}
