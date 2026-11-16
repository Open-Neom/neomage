// WebFetchTool — port of neomage/src/tools/WebFetchTool/.
// Fetches URL content, converts HTML to markdown, applies prompt via secondary model.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

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

final RegExp _unsafeFetchUrlChars = RegExp(
  r'[\x00-\x1F\x7F-\x9F\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
);

final RegExp _webPromptInjectionTokens = RegExp(
  r'<\s*(think|thinking|thought|memory_recall|auto_memory|system_context)\b[^>]*>[\s\S]*?<\s*/\s*\1\s*>|<\s*(?:think|thinking|thought|memory_recall|auto_memory|system_context)\b[^>]*>[\s\S]*$|<\|channel>\s*thought\b[\s\S]*?<channel\|>|<\|channel>\s*thought\b[\s\S]*$|<\|(?:im_start|im_end|endoftext|eot_id|start_header_id|end_header_id|/?turn)\|>|<\|channel>|<channel\|>|<(?:start|end)_of_turn>',
  caseSensitive: false,
);

final RegExp _webUnsafeTextControls = RegExp(
  r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u061C\u202A-\u202E\u2066-\u2069]',
);

String _truncateUtf16Safe(String input, int maxChars) {
  if (input.length <= maxChars) return input;
  var end = maxChars;
  if (end > 0) {
    final prev = input.codeUnitAt(end - 1);
    if (prev >= 0xD800 && prev <= 0xDBFF) {
      end -= 1;
    }
  }
  return input.substring(0, end);
}

String _sanitizePromptContentBlock(String raw) {
  return raw
      .replaceAll(_webPromptInjectionTokens, '')
      .replaceAll(_webUnsafeTextControls, '')
      .replaceAllMapped(
        RegExp(r'<\s*/?\s*content\b', caseSensitive: false),
        (m) => m.group(0)!.replaceFirst('<', '<\u200B'),
      );
}

/// Validate a URL for fetching.
UrlValidation validateUrl(String urlString) {
  if (_unsafeFetchUrlChars.hasMatch(urlString)) {
    return const InvalidUrl('URL contains disallowed control characters');
  }
  final trimmed = urlString.trim();
  if (trimmed.isEmpty) {
    return const InvalidUrl('URL cannot be empty');
  }
  if (trimmed.length > maxUrlLength) {
    return InvalidUrl('URL exceeds maximum length of $maxUrlLength characters');
  }
  if (trimmed.contains(r'\') || trimmed.toLowerCase().contains('%5c')) {
    return const InvalidUrl('URL contains disallowed backslash separator');
  }

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return const InvalidUrl('Invalid URL format');
  }

  if (!uri.hasScheme || (!uri.isScheme('http') && !uri.isScheme('https'))) {
    return const InvalidUrl('URL must use http or https scheme');
  }

  if (uri.host.isEmpty) {
    return const InvalidUrl('URL must have a hostname');
  }

  // Block embedded credentials
  if (uri.userInfo.isNotEmpty) {
    return const InvalidUrl('URLs with embedded credentials not allowed');
  }

  // Block loopback, RFC1918 private LAN, CGNAT, link-local cloud metadata
  // (169.254.169.254 / 100.100.100.200 / metadata.google.internal), IPv6 ULA,
  // and decimal/hex/octal IP obfuscations.
  if (NeomageNetworkGuard.isPrivateOrReservedHost(
    uri.host,
    allowLoopback: false,
  )) {
    return const InvalidUrl(
      'Private, loopback, link-local, or reserved host not allowed',
    );
  }

  // Require at least 2 parts in hostname (or valid public IPv6 literal)
  if (!uri.host.contains('.') && !uri.host.contains(':')) {
    return const InvalidUrl('Single-label hostname not allowed');
  }

  return ValidUrl(uri);
}

/// Check if a redirect is permitted.
bool isPermittedRedirect(Uri original, Uri redirect) {
  // Must maintain same protocol
  if (original.scheme != redirect.scheme) return false;

  // No credentials in redirect
  if (redirect.userInfo.isNotEmpty) return false;

  // Target host must also pass full SSRF validation
  if (NeomageNetworkGuard.isPrivateOrReservedHost(
    redirect.host,
    allowLoopback: false,
  )) {
    return false;
  }

  // Same port
  if (original.port != redirect.port) return false;

  // Hostname can only differ by www prefix
  final origHost = original.host.toLowerCase();
  final redirHost = redirect.host.toLowerCase();
  if (origHost != redirHost) {
    final origWithoutWww = origHost.startsWith('www.')
        ? origHost.substring(4)
        : origHost;
    final redirWithoutWww = redirHost.startsWith('www.')
        ? redirHost.substring(4)
        : redirHost;
    if (origWithoutWww != redirWithoutWww) return false;
  }

  return true;
}

// ── Preapproved Hosts ──

/// Preapproved hosts for web fetching (no copyright restrictions).
const preapprovedHosts = {
  // Anthropic
  'docs.anthropic.com',
  'platform.neomage.com',
  'code.neomage.com',
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
  text = text.replaceAll(
    RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(
    RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
    '',
  );
  text = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');

  // Strip raw Gemma-4 / reasoning / chat control blocks BEFORE generic HTML
  // tag stripping so `<|channel>` delimiters are not stripped while leaving
  // their hidden payload intact.
  text = text.replaceAll(_webPromptInjectionTokens, '');

  // Convert headers
  for (var i = 6; i >= 1; i--) {
    text = text.replaceAllMapped(
      RegExp('<h$i[^>]*>(.*?)</h$i>', caseSensitive: false, dotAll: true),
      (m) => '\n${'#' * i} ${_stripTags(m.group(1) ?? '')}\n',
    );
  }

  // Convert links
  text = text.replaceAllMapped(
    RegExp(
      r'<a\s+[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
      caseSensitive: false,
      dotAll: true,
    ),
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
    RegExp(
      r'<pre[^>]*><code[^>]*>(.*?)</code></pre>',
      caseSensitive: false,
      dotAll: true,
    ),
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
    RegExp(
      r'<blockquote[^>]*>(.*?)</blockquote>',
      caseSensitive: false,
      dotAll: true,
    ),
    (m) {
      final content = _stripTags(m.group(1) ?? '').trim();
      return content.split('\n').map((l) => '> $l').join('\n');
    },
  );

  // Convert tables (basic)
  text = text.replaceAllMapped(
    RegExp(r'<tr[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true),
    (m) {
      final cells =
          RegExp(
                r'<t[dh][^>]*>(.*?)</t[dh]>',
                caseSensitive: false,
                dotAll: true,
              )
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

  // Strip leaked chat control tokens and BiDi/C0/C1 controls
  text = text
      .replaceAll(_webPromptInjectionTokens, '')
      .replaceAll(_webUnsafeTextControls, '');

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

  _FetchCache({
    this.maxSizeBytes = 10 * 1024 * 1024,
    this.ttl = const Duration(minutes: 5),
  });

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
String preapprovedPrompt(String markdown, String userPrompt) {
  final safeMd = _sanitizePromptContentBlock(markdown);
  final safePrompt = _sanitizePromptContentBlock(userPrompt);
  return '''
Here is the content from a documentation page:

<content>
$safeMd
</content>

User request: $safePrompt

Extract the relevant information from the content above. You may include code examples, API signatures, and technical details as needed.''';
}

/// Prompt for non-preapproved domains (copyright restrictions).
String copyrightPrompt(String markdown, String userPrompt) {
  final safeMd = _sanitizePromptContentBlock(markdown);
  final safePrompt = _sanitizePromptContentBlock(userPrompt);
  return '''
Here is the content from a web page:

<content>
$safeMd
</content>

User request: $safePrompt

IMPORTANT COPYRIGHT GUIDELINES:
- Maximum 125-character quotes from the source
- Must use quotation marks for exact language
- Do not reproduce word-for-word content
- Do not reproduce song lyrics, poems, or similar creative works
- Summarize and paraphrase instead of copying
- Note: This is not legal advice''';
}

// ── Fetch Execution ──

/// Fetch and process a URL with the WebFetchTool semantics.
Future<WebFetchOutput> fetchUrl(
  WebFetchInput input, {
  Future<String> Function(String systemPrompt, String userPrompt)? applyPrompt,
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
    final result = await _processContent(
      cached,
      input.prompt,
      uri,
      applyPrompt,
    );
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

  // Fetch with manual redirect validation (HttpClient defaults to
  // followRedirects = true, which would otherwise follow 30x redirects to
  // internal/metadata hosts before isPermittedRedirect runs).
  final client = httpClient ?? HttpClient();
  try {
    HttpClientResponse? finalResponse;
    var currentUri = uri;

    for (var hop = 0; hop <= maxRedirects; hop++) {
      final request = await client.getUrl(currentUri).timeout(fetchTimeout);
      request.followRedirects = false;
      request.maxRedirects = 0;
      request.headers.set('User-Agent', 'Neomage/1.0 (AI Coding Assistant)');
      request.headers.set('Accept', 'text/markdown, text/html, */*');

      final response = await request.close().timeout(fetchTimeout);

      final isRedirectStatus =
          response.isRedirect ||
          (response.statusCode >= 300 && response.statusCode < 400);
      if (isRedirectStatus) {
        final location = response.headers.value('location');
        await response.drain<void>().timeout(fetchTimeout);
        if (location == null || location.trim().isEmpty) {
          finalResponse = response;
          break;
        }
        if (hop == maxRedirects) {
          return WebFetchOutput(
            bytes: 0,
            code: response.statusCode,
            codeText: 'too_many_redirects',
            result: 'Exceeded maximum redirect limit ($maxRedirects)',
            durationMs: sw.elapsedMilliseconds,
            url: currentUri.toString(),
          );
        }

        Uri redirectUri;
        try {
          redirectUri = currentUri.resolve(location.trim());
        } catch (_) {
          return WebFetchOutput(
            bytes: 0,
            code: response.statusCode,
            codeText: 'invalid_redirect',
            result: 'Malformed redirect Location header',
            durationMs: sw.elapsedMilliseconds,
            url: currentUri.toString(),
          );
        }

        if (!isPermittedRedirect(uri, redirectUri) ||
            validateUrl(redirectUri.toString()) is! ValidUrl) {
          final redactedLoc = NeomageNetworkGuard.redactUrlCredentials(
            location,
          );
          return WebFetchOutput(
            bytes: 0,
            code: response.statusCode,
            codeText: 'cross_origin_redirect',
            result: 'Redirect to different domain not followed: $redactedLoc',
            durationMs: sw.elapsedMilliseconds,
            url: currentUri.toString(),
          );
        }

        currentUri = redirectUri;
        continue;
      }

      finalResponse = response;
      break;
    }

    final response = finalResponse!;
    uri = currentUri;

    // Check content length
    final contentLength = response.contentLength;
    if (contentLength > maxHttpContentLength) {
      await response.drain<void>().timeout(fetchTimeout);
      return WebFetchOutput(
        bytes: contentLength,
        code: response.statusCode,
        codeText: 'content_too_large',
        result:
            'Content exceeds maximum size of ${maxHttpContentLength ~/ (1024 * 1024)}MB',
        durationMs: sw.elapsedMilliseconds,
        url: uri.toString(),
      );
    }

    // Stream response body in O(N) via BytesBuilder with hard byte cap.
    final byteBuffer = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(fetchTimeout)) {
      if (byteBuffer.length + chunk.length > maxHttpContentLength) {
        throw Exception('Response body exceeds maximum size');
      }
      byteBuffer.add(chunk);
    }
    final bytes = byteBuffer.takeBytes();

    final contentType = response.headers.contentType?.mimeType ?? 'text/html';

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

    // Truncate if needed (UTF-16 surrogate-safe)
    if (text.length > maxMarkdownLength) {
      final slice = _truncateUtf16Safe(text, maxMarkdownLength);
      text = '$slice\n\n[Content truncated due to length...]';
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
    final safeErr = NeomageNetworkGuard.redactTransportError(e.toString());
    return WebFetchOutput(
      bytes: 0,
      code: 0,
      codeText: 'error',
      result: 'Fetch error: $safeErr',
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

  return applyPrompt(
    'You are an AI assistant extracting information from web content.',
    prompt,
  );
}
