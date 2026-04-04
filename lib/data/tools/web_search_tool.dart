// WebSearchTool — port of neom_claw/src/tools/WebSearchTool/.
// Performs web searches via API, returns structured results with links.

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
  final List<dynamic> results; // Mix of SearchResult and String (text summaries)
  final double durationSeconds;
  final int searchCount;

  const WebSearchOutput({
    required this.query,
    required this.results,
    required this.durationSeconds,
    this.searchCount = 1,
  });

  /// Format for display.
  String format() {
    final buf = StringBuffer()
      ..writeln('Web search results for query: "$query"\n');

    for (final result in results) {
      if (result is String) {
        buf.writeln(result);
      } else if (result is SearchResult) {
        buf.writeln('- [${result.title}](${result.url})');
        if (result.snippet != null) {
          buf.writeln('  ${result.snippet}');
        }
      } else if (result is List<SearchResult>) {
        for (final r in result) {
          buf.writeln('- [${r.title}](${r.url})');
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

/// Maximum result output length.
const maxSearchOutputLength = 100000;

/// Maximum searches per query.
const maxSearchesPerQuery = 8;

/// Validate web search input.
String? validateSearchInput(WebSearchInput input) {
  if (input.query.length < 2) {
    return 'Search query must be at least 2 characters';
  }
  if (input.allowedDomains != null && input.blockedDomains != null) {
    return 'Cannot specify both allowed_domains and blocked_domains';
  }
  return null;
}

/// Web search tool schema for API providers that support native search.
Map<String, dynamic> makeSearchToolSchema({
  List<String>? allowedDomains,
  List<String>? blockedDomains,
}) =>
    {
      'type': 'web_search_20250305',
      'name': 'web_search',
      'max_uses': maxSearchesPerQuery,
      if (allowedDomains != null) 'allowed_domains': allowedDomains,
      if (blockedDomains != null) 'blocked_domains': blockedDomains,
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
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
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
