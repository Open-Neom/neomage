// WebFetchTool — port of neom_claw/src/tools/WebFetchTool/.
// Fetches URL content, converts HTML to markdown, applies prompt via secondary model.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'tool.dart';

/// Maximum markdown content length before truncation.
const maxMarkdownLength = 100000;

/// Maximum HTTP content size (10MB).
const maxHttpContentLength = 10 * 1024 * 1024;

/// Maximum URL length.
const maxUrlLength = 2000;

/// Maximum redirect hops.
const maxRedirects = 10;

/// Fetch timeout.
const fetchTimeout = Duration(seconds: 60);

/// Domain check timeout.
const domainCheckTimeout = Duration(seconds: 10);

/// Cache TTL for fetched content.
const cacheTtl = Duration(minutes: 15);

/// Maximum cache size in bytes.
const maxCacheSize = 50 * 1024 * 1024; // 50MB

/// Web fetch input.
class WebFetchInput {
  final String url;
  final String prompt;

  const WebFetchInput({required this.url, required this.prompt});

  factory WebFetchInput.fromJson(Map<String, dynamic> json) => WebFetchInput(
        url: json['url'] as String,
        prompt: json['prompt'] as String,
      );
}

/// Web fetch output.
class WebFetchOutput {
  final int bytes;
  final int code;
  final String codeText;
  final String result;
  final int durationMs;
  final String url;
  final String? persistedPath;
  final int? persistedSize;

  const WebFetchOutput({
    required this.bytes,
    required this.code,
    required this.codeText,
    required this.result,
    required this.durationMs,
    required this.url,
    this.persistedPath,
    this.persistedSize,
  });

  Map<String, dynamic> toJson() => {
        'bytes': bytes,
        'code': code,
        'codeText': codeText,
        'result': result,
        'durationMs': durationMs,
        'url': url,
        if (persistedPath != null) 'persistedPath': persistedPath,
        if (persistedSize != null) 'persistedSize': persistedSize,
      };
}

/// URL validation result.
sealed class UrlValidation {
  const UrlValidation();
}

class ValidUrl extends UrlValidation {
  final Uri uri;
  const ValidUrl(this.uri);
}

class InvalidUrl extends UrlValidation {
  final String reason;
  const InvalidUrl(this.reason);
}

/// Validate a URL for fetching.
UrlValidation validateUrl(String urlString) {
  if (urlString.length > maxUrlLength) {
    return InvalidUrl('URL exceeds maximum length of $maxUrlLength characters');
  }

  Uri uri;
  try {
    uri = Uri.parse(urlString);
  } catch (_) {
    return const InvalidUrl('Invalid URL format');
  }

  if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return const InvalidUrl('URL must use http or https scheme');
  }

  if (uri.host.isEmpty) {
    return const InvalidUrl('URL must have a hostname');
  }

  // Require at least 2 parts in hostname
  if (!uri.host.contains('.')) {
    return const InvalidUrl('Single-label hostname not allowed');
  }

  // Block embedded credentials
  if (uri.userInfo.isNotEmpty) {
    return const InvalidUrl('URLs with embedded credentials not allowed');
  }

  return ValidUrl(uri);
}

/// Check if a redirect is permitted.
bool isPermittedRedirect(Uri original, Uri redirect) {
  // Must maintain same protocol
  if (original.scheme != redirect.scheme) return false;

  // No credentials in redirect
  if (redirect.userInfo.isNotEmpty) return false;

  // Same port
  if (original.port != redirect.port) return false;

  // Hostname can only differ by www prefix
  final origHost = original.host.toLowerCase();
  final redirHost = redirect.host.toLowerCase();
  if (origHost != redirHost) {
    final origWithoutWww =
        origHost.startsWith('www.') ? origHost.substring(4) : origHost;
    final redirWithoutWww =
        redirHost.startsWith('www.') ? redirHost.substring(4) : redirHost;
    if (origWithoutWww != redirWithoutWww) return false;
  }

  return true;
}

// ── Preapproved Hosts ──

/// Preapproved hosts for web fetching (no copyright restrictions).
const preapprovedHosts = {
  // Anthropic
  'docs.anthropic.com',
  'platform.neomclaw.com',
  'code.neomclaw.com',
  'modelcontextprotocol.io',

  // Python
  'docs.python.org',
  'pypi.org',
  'peps.python.org',
  'packaging.python.org',

  // JavaScript/TypeScript
  'developer.mozilla.org',
  'nodejs.org',
  'docs.npmjs.com',
  'tc39.es',
  'typescriptlang.org',

  // Frameworks
  'react.dev',
  'nextjs.org',
  'expressjs.com',
  'vuejs.org',
  'angular.dev',
  'svelte.dev',
  'nuxt.com',
  'remix.run',
  'astro.build',

  // Go
  'go.dev',
  'pkg.go.dev',

  // Rust
  'doc.rust-lang.org',
  'docs.rs',
  'crates.io',

  // Ruby
  'ruby-doc.org',
  'rubygems.org',
  'guides.rubyonrails.org',

  // Java/Kotlin
  'docs.oracle.com',
  'kotlinlang.org',
  'spring.io',
  'maven.apache.org',

  // Dart/Flutter
  'dart.dev',
  'api.dart.dev',
  'pub.dev',
  'flutter.dev',
  'docs.flutter.dev',

  // Cloud
  'docs.aws.amazon.com',
  'learn.microsoft.com',
  'cloud.google.com',

  // Databases
  'dev.mysql.com',
  'www.postgresql.org',
  'redis.io',
  'www.mongodb.com',

  // ML/AI
  'tensorflow.org',
  'pytorch.org',
  'huggingface.co',
  'kaggle.com',
  'scikit-learn.org',

  // DevOps
  'docs.docker.com',
  'kubernetes.io',
  'docs.github.com',
  'git-scm.com',

  // Other
  'en.wikipedia.org',
  'stackoverflow.com',
  'www.w3.org',
  'datatracker.ietf.org',
  'json-schema.org',
  'graphql.org',
  'www.openapis.org',
  'spec.graphql.org',
};

/// Check if a URL is preapproved.
bool isPreapprovedUrl(Uri uri) {
  final host = uri.host.toLowerCase();
  return preapprovedHosts.contains(host);
}

// ── HTML to Markdown Conversion ──

/// Convert HTML content to clean markdown.
String htmlToMarkdown(String html) {
  var text = html;

  // Remove scripts and styles
  text = text.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  // Convert headers
  for (var i = 6; i >= 1; i--) {
    text = text.replaceAllMapped(
      RegExp('<h$i[^>]*>(.*?)</h$i>', caseSensitive: false, dotAll: true),
      (m) => '\n${'#' * i} ${_stripTags(m.group(1) ?? '')}\n',
    );
  }

  // Convert links
  text = text.replaceAllMapped(
    RegExp(r'<a\s+[^>]*href="([^"]*)"[^>]*>(.*?)</a>', caseSensitive: false, dotAll: true),
    (m) => '[${_stripTags(m.group(2) ?? '')}](${m.group(1)})',
  );

  // Convert bold/italic
  text = text.replaceAllMapped(
    RegExp(r'<(strong|b)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
    (m) => '**${m.group(2)}**',
  );
  text = text.replaceAllMapped(
    RegExp(r'<(em|i)[^>]*>(.*?)</\1>', caseSensitive: false, dotAll: true),
    (m) => '*${m.group(2)}*',
  );

  // Convert code blocks
  text = text.replaceAllMapped(
    RegExp(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>', caseSensitive: false, dotAll: true),
    (m) => '\n```\n${_decodeHtmlEntities(m.group(1) ?? '')}\n```\n',
  );
  text = text.replaceAllMapped(
    RegExp(r'<code[^>]*>(.*?)</code>', caseSensitive: false, dotAll: true),
    (m) => '`${m.group(1)}`',
  );

  // Convert lists
  text = text.replaceAllMapped(
    RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false, dotAll: true),
    (m) => '- ${_stripTags(m.group(1) ?? '').trim()}\n',
  );

  // Convert paragraphs and line breaks
  text = text.replaceAll(RegExp(r'<br\s*/?\s*>', caseSensitive: false), '\n');
  text = text.replaceAllMapped(
    RegExp(r'<p[^>]*>(.*?)</p>', caseSensitive: false, dotAll: true),
    (m) => '\n${_stripTags(m.group(1) ?? '').trim()}\n',
  );

  // Convert blockquotes
  text = text.replaceAllMapped(
    RegExp(r'<blockquote[^>]*>(.*?)</blockquote>', caseSensitive: false, dotAll: true),
    (m) {
      final content = _stripTags(m.group(1) ?? '').trim();
      return content.split('\n').map((l) => '> $l').join('\n');
    },
  );

  // Convert tables (basic)
  text = text.replaceAllMapped(
    RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true),
    (m) {
      final cells = RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true)
          .allMatches(m.group(1) ?? '')
          .map((c) => _stripTags(c.group(1) ?? '').trim())
          .toList();
      return '| ${cells.join(' | ')} |\n';
    },
  );

  // Remove remaining HTML tags
  text = _stripTags(text);

  // Decode HTML entities
  text = _decodeHtmlEntities(text);

  // Clean up whitespace
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  text = text.trim();

  return text;
}

String _stripTags(String html) {
  return html.replaceAll(RegExp(r'<[^>]*>'), '');
}

String _decodeHtmlEntities(String text) {
  return text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#x2F;', '/')
      .replaceAll('&hellip;', '...')
      .replaceAll('&mdash;', '—')
      .replaceAll('&ndash;', '–');
}

// ── Content Type Detection ──

/// Check if a content type is binary.
bool isBinaryContentType(String contentType) {
  final lower = contentType.toLowerCase();
  if (lower.startsWith('text/')) return false;
  if (lower.contains('json')) return false;
  if (lower.contains('xml')) return false;
  if (lower.contains('javascript')) return false;
  if (lower.contains('css')) return false;
  if (lower.contains('html')) return false;
  return true;
}

// ── LRU Cache ──

/// Simple LRU cache for fetched content.
class _FetchCache {
  final int maxSizeBytes;
  final Duration ttl;
  final Map<String, _CacheEntry> _entries = {};
  int _currentSize = 0;

  _FetchCache({this.maxSizeBytes = maxCacheSize, this.ttl = cacheTtl});

  String? get(String url) {
    final entry = _entries[url];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.cachedAt) > ttl) {
      _entries.remove(url);
      _currentSize -= entry.size;
      return null;
    }
    return entry.content;
  }

  void put(String url, String content) {
    final size = content.length;

    // Evict if needed
    while (_currentSize + size > maxSizeBytes && _entries.isNotEmpty) {
      final oldest = _entries.entries.first;
      _currentSize -= oldest.value.size;
      _entries.remove(oldest.key);
    }

    _entries[url] = _CacheEntry(content: content, size: size);
    _currentSize += size;
  }
}

class _CacheEntry {
  final String content;
  final int size;
  final DateTime cachedAt;
  _CacheEntry({required this.content, required this.size})
      : cachedAt = DateTime.now();
}

/// Global fetch cache.
final _cache = _FetchCache();

// ── Prompt Templates ──

/// Prompt for preapproved domains (allows full extraction).
String preapprovedPrompt(String markdown, String userPrompt) => '''
Here is the content from a documentation page:

<content>
$markdown
</content>

User request: $userPrompt

Extract the relevant information from the content above. You may include code examples, API signatures, and technical details as needed.''';

/// Prompt for non-preapproved domains (copyright restrictions).
String copyrightPrompt(String markdown, String userPrompt) => '''
Here is the content from a web page:

<content>
$markdown
</content>

User request: $userPrompt

IMPORTANT COPYRIGHT GUIDELINES:
- Maximum 125-character quotes from the source
- Must use quotation marks for exact language
- Do not reproduce word-for-word content
- Do not reproduce song lyrics, poems, or similar creative works
- Summarize and paraphrase instead of copying
- Note: This is not legal advice''';

// ── Fetch Execution ──

/// Fetch and process a URL with the WebFetchTool semantics.
Future<WebFetchOutput> fetchUrl(
  WebFetchInput input, {
  Future<String> Function(String systemPrompt, String userPrompt)?
      applyPrompt,
  HttpClient? httpClient,
}) async {
  final sw = Stopwatch()..start();

  // Validate URL
  final validation = validateUrl(input.url);
  if (validation is InvalidUrl) {
    return WebFetchOutput(
      bytes: 0,
      code: 0,
      codeText: 'invalid_url',
      result: 'Error: ${validation.reason}',
      durationMs: sw.elapsedMilliseconds,
      url: input.url,
    );
  }

  var uri = (validation as ValidUrl).uri;

  // Upgrade HTTP to HTTPS
  if (uri.isScheme('http')) {
    uri = uri.replace(scheme: 'https');
  }

  // Check cache
  final cached = _cache.get(uri.toString());
  if (cached != null) {
    final result = await _processContent(cached, input.prompt, uri, applyPrompt);
    sw.stop();
    return WebFetchOutput(
      bytes: cached.length,
      code: 200,
      codeText: 'OK (cached)',
      result: result,
      durationMs: sw.elapsedMilliseconds,
      url: uri.toString(),
    );
  }

  // Fetch
  final client = httpClient ?? HttpClient();
  try {
    final request = await client.getUrl(uri).timeout(fetchTimeout);
    request.headers.set('User-Agent', 'FlutterClaw/1.0 (AI Coding Assistant)');
    request.headers.set('Accept', 'text/markdown, text/html, */*');

    final response = await request.close().timeout(fetchTimeout);

    // Check content length
    final contentLength = response.contentLength;
    if (contentLength > maxHttpContentLength) {
      return WebFetchOutput(
        bytes: contentLength,
        code: response.statusCode,
        codeText: 'content_too_large',
        result: 'Content exceeds maximum size of ${maxHttpContentLength ~/ (1024 * 1024)}MB',
        durationMs: sw.elapsedMilliseconds,
        url: uri.toString(),
      );
    }

    // Handle redirects
    if (response.isRedirect || (response.statusCode >= 300 && response.statusCode < 400)) {
      final location = response.headers.value('location');
      if (location != null) {
        final redirectUri = Uri.parse(location);
        if (!isPermittedRedirect(uri, redirectUri)) {
          return WebFetchOutput(
            bytes: 0,
            code: response.statusCode,
            codeText: 'cross_origin_redirect',
            result: 'Redirect to different domain not followed: $location',
            durationMs: sw.elapsedMilliseconds,
            url: uri.toString(),
          );
        }
      }
    }

    // Read response body
    final bytes = await response
        .fold<List<int>>([], (prev, chunk) {
          if (prev.length + chunk.length > maxHttpContentLength) {
            throw Exception('Response body exceeds maximum size');
          }
          return [...prev, ...chunk];
        })
        .timeout(fetchTimeout);

    final contentType =
        response.headers.contentType?.mimeType ?? 'text/html';

    // Handle binary content
    if (isBinaryContentType(contentType)) {
      return WebFetchOutput(
        bytes: bytes.length,
        code: response.statusCode,
        codeText: response.reasonPhrase,
        result: 'Binary content ($contentType, ${bytes.length} bytes)',
        durationMs: sw.elapsedMilliseconds,
        url: uri.toString(),
      );
    }

    // Decode text
    var text = utf8.decode(bytes, allowMalformed: true);

    // Convert HTML to markdown
    if (contentType.contains('html')) {
      text = htmlToMarkdown(text);
    }

    // Cache
    _cache.put(uri.toString(), text);

    // Truncate if needed
    if (text.length > maxMarkdownLength) {
      text = '${text.substring(0, maxMarkdownLength)}\n\n[Content truncated due to length...]';
    }

    // Apply prompt
    final result = await _processContent(text, input.prompt, uri, applyPrompt);

    sw.stop();
    return WebFetchOutput(
      bytes: bytes.length,
      code: response.statusCode,
      codeText: response.reasonPhrase,
      result: result,
      durationMs: sw.elapsedMilliseconds,
      url: uri.toString(),
    );
  } on TimeoutException {
    return WebFetchOutput(
      bytes: 0,
      code: 0,
      codeText: 'timeout',
      result: 'Request timed out after ${fetchTimeout.inSeconds}s',
      durationMs: sw.elapsedMilliseconds,
      url: uri.toString(),
    );
  } catch (e) {
    return WebFetchOutput(
      bytes: 0,
      code: 0,
      codeText: 'error',
      result: 'Fetch error: $e',
      durationMs: sw.elapsedMilliseconds,
      url: uri.toString(),
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

Future<String> _processContent(
  String markdown,
  String userPrompt,
  Uri uri,
  Future<String> Function(String, String)? applyPrompt,
) async {
  if (applyPrompt == null) return markdown;

  final preapproved = isPreapprovedUrl(uri);
  final prompt = preapproved
      ? preapprovedPrompt(markdown, userPrompt)
      : copyrightPrompt(markdown, userPrompt);

  return applyPrompt('You are an AI assistant extracting information from web content.', prompt);
}
