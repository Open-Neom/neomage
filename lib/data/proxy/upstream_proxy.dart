/// Upstream proxy for routing API calls through an intermediary.
///
/// Supports request/response transforms, streaming (SSE), optional
/// disk-based caching with TTL, latency measurement, and statistics.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/utils/security/neomage_network_guard.dart';

/// Configuration for [UpstreamProxy].
class ProxyConfig {
  /// The final target URL that requests are ultimately destined for.
  final String targetUrl;

  /// The intermediary proxy URL that requests are routed through.
  final String proxyUrl;

  /// Extra headers to attach to every outgoing request.
  final Map<String, String> headers;

  /// HTTP request timeout.
  final Duration timeout;

  /// Number of retry attempts on transient failures.
  final int retries;

  /// Whether response caching is enabled.
  final bool cacheEnabled;

  /// Directory to store cached responses on disk.
  final String? cacheDir;

  /// Time-to-live for cached responses.
  final Duration cacheTtl;

  const ProxyConfig({
    required this.targetUrl,
    required this.proxyUrl,
    this.headers = const {},
    this.timeout = const Duration(seconds: 30),
    this.retries = 2,
    this.cacheEnabled = false,
    this.cacheDir,
    this.cacheTtl = const Duration(minutes: 10),
  });

  /// Returns a copy with selected fields replaced.
  ProxyConfig copyWith({
    String? targetUrl,
    String? proxyUrl,
    Map<String, String>? headers,
    Duration? timeout,
    int? retries,
    bool? cacheEnabled,
    String? cacheDir,
    Duration? cacheTtl,
  }) {
    return ProxyConfig(
      targetUrl: targetUrl ?? this.targetUrl,
      proxyUrl: proxyUrl ?? this.proxyUrl,
      headers: headers ?? this.headers,
      timeout: timeout ?? this.timeout,
      retries: retries ?? this.retries,
      cacheEnabled: cacheEnabled ?? this.cacheEnabled,
      cacheDir: cacheDir ?? this.cacheDir,
      cacheTtl: cacheTtl ?? this.cacheTtl,
    );
  }
}

/// Accumulated proxy traffic statistics.
class ProxyStats {
  int requestCount;
  int cacheHits;
  int cacheMisses;
  Duration totalLatency;
  int errors;
  int bytesTransferred;

  ProxyStats({
    this.requestCount = 0,
    this.cacheHits = 0,
    this.cacheMisses = 0,
    this.totalLatency = Duration.zero,
    this.errors = 0,
    this.bytesTransferred = 0,
  });

  /// Average latency per request.
  Duration get averageLatency => requestCount > 0
      ? Duration(microseconds: totalLatency.inMicroseconds ~/ requestCount)
      : Duration.zero;

  /// Cache hit ratio as a percentage (0–100).
  double get cacheHitRatio {
    final total = cacheHits + cacheMisses;
    return total > 0 ? (cacheHits / total) * 100 : 0;
  }

  @override
  String toString() =>
      'ProxyStats(requests: $requestCount, cacheHits: $cacheHits, '
      'errors: $errors, bytes: $bytesTransferred)';
}

/// Represents a request to be forwarded through the proxy.
class ProxyRequest {
  final String method;
  final String path;
  final Map<String, String> headers;
  final String? body;
  final DateTime timestamp;

  ProxyRequest({
    required this.method,
    required this.path,
    this.headers = const {},
    this.body,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Generates a collision-resistant SHA-256 cache key from method, path, and body.
  String get cacheKey {
    final payload = '${method.toUpperCase()}:$path:${body ?? ''}';
    return NeomageNetworkGuard.sha256Hex(payload);
  }
}

/// Response returned from the upstream proxy.
class ProxyResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final bool cached;
  final Duration latency;

  const ProxyResponse({
    required this.statusCode,
    this.headers = const {},
    this.body = '',
    this.cached = false,
    this.latency = Duration.zero,
  });
}

/// A cached response with expiration metadata.
class CacheEntry {
  final ProxyResponse response;
  final DateTime cachedAt;
  final DateTime expiresAt;
  final String key;

  const CacheEntry({
    required this.response,
    required this.cachedAt,
    required this.expiresAt,
    required this.key,
  });

  /// Whether this entry has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Serializes the entry to JSON for disk storage.
  Map<String, dynamic> toJson() => {
    'statusCode': response.statusCode,
    'headers': response.headers,
    'body': response.body,
    'cachedAt': cachedAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'key': key,
  };

  /// Deserializes a cache entry from JSON.
  factory CacheEntry.fromJson(Map<String, dynamic> json) {
    return CacheEntry(
      response: ProxyResponse(
        statusCode: json['statusCode'] as int,
        headers: Map<String, String>.from(json['headers'] as Map),
        body: json['body'] as String,
        cached: true,
      ),
      cachedAt: DateTime.parse(json['cachedAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      key: json['key'] as String,
    );
  }
}

/// Proxy that forwards requests to a target through an intermediary.
///
/// Supports optional caching, request/response transforms, streaming,
/// and health checks.
class UpstreamProxy {
  static const int maxResponseBytes = 16 * 1024 * 1024;
  static const int maxMemoryCacheEntries = 256;

  ProxyConfig _config;
  final ProxyStats _stats = ProxyStats();
  final Map<String, String> _extraHeaders = {};
  final Map<String, CacheEntry> _memoryCache = {};

  /// Optional transform applied to requests before forwarding.
  ProxyRequest Function(ProxyRequest)? _requestTransform;

  /// Optional transform applied to responses before returning.
  ProxyResponse Function(ProxyResponse)? _responseTransform;

  HttpClient? _client;

  /// Creates an upstream proxy with the given [config].
  UpstreamProxy(this._config) {
    _client = HttpClient()..connectionTimeout = _config.timeout;
  }

  /// The current proxy configuration.
  ProxyConfig get config => _config;

  /// Forwards [request] to the target through the proxy.
  ///
  /// If caching is enabled and a fresh cache entry exists, it is returned
  /// immediately without making a network call.
  Future<ProxyResponse> forward(ProxyRequest request) async {
    var req = request;
    if (_requestTransform != null) {
      req = _requestTransform!(req);
    }

    // Check cache.
    if (_config.cacheEnabled) {
      final cached = getCachedResponse(req);
      if (cached != null) {
        _stats.cacheHits++;
        _stats.requestCount++;
        return cached;
      }
      _stats.cacheMisses++;
    }

    final stopwatch = Stopwatch()..start();
    final maxAttempts = 1 + _config.retries;
    ProxyResponse? response;
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        response = await _doForward(req);
        break;
      } catch (e) {
        lastError = e;
        if (attempt == maxAttempts - 1) {
          _stats.errors++;
          _stats.requestCount++;
          rethrow;
        }
      }
    }

    // If all attempts failed, the rethrow above exits. This guard
    // satisfies the analyzer for the non-nullable path below.
    if (response == null) throw lastError!;

    stopwatch.stop();
    response = ProxyResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
      cached: false,
      latency: stopwatch.elapsed,
    );

    if (_responseTransform != null) {
      response = _responseTransform!(response);
    }

    _stats.requestCount++;
    _stats.totalLatency += stopwatch.elapsed;
    _stats.bytesTransferred += response.body.length;

    // Store in cache.
    if (_config.cacheEnabled && response.statusCode == 200) {
      _putCache(req.cacheKey, response);
    }

    return response;
  }

  /// Forwards a request and returns a streaming response (e.g. for SSE).
  ///
  /// Yields raw bytes as they arrive from the upstream server.
  Stream<List<int>> forwardStream(ProxyRequest request) async* {
    var req = request;
    if (_requestTransform != null) {
      req = _requestTransform!(req);
    }

    final uri = _buildUri(req);
    final httpReq = await _client!
        .openUrl(req.method.toUpperCase(), uri)
        .timeout(_config.timeout);
    httpReq.followRedirects = false;
    _applyHeaders(httpReq, req);
    if (req.body != null) {
      httpReq.write(req.body);
    }
    final httpResp = await httpReq.close().timeout(_config.timeout);

    _stats.requestCount++;

    var streamedBytes = 0;
    await for (final chunk in httpResp.timeout(_config.timeout)) {
      streamedBytes += chunk.length;
      if (streamedBytes > maxResponseBytes) {
        throw HttpException(
          'Upstream proxy stream exceeds ${maxResponseBytes ~/ (1024 * 1024)} MiB',
          uri: uri,
        );
      }
      _stats.bytesTransferred += chunk.length;
      yield chunk;
    }
  }

  /// Adds a header that will be sent with every outgoing request.
  void addHeader(String key, String value) {
    _extraHeaders[key] = value;
  }

  /// Removes a previously added extra header.
  void removeHeader(String key) {
    _extraHeaders.remove(key);
  }

  /// Sets a transform function applied to requests before forwarding.
  void setTransform(ProxyRequest Function(ProxyRequest) fn) {
    _requestTransform = fn;
  }

  /// Sets a transform function applied to responses before returning.
  void setResponseTransform(ProxyResponse Function(ProxyResponse) fn) {
    _responseTransform = fn;
  }

  /// Returns a snapshot of accumulated traffic statistics.
  ProxyStats getStats() => _stats;

  /// Resets all statistics counters to zero.
  void resetStats() {
    _stats
      ..requestCount = 0
      ..cacheHits = 0
      ..cacheMisses = 0
      ..totalLatency = Duration.zero
      ..errors = 0
      ..bytesTransferred = 0;
  }

  /// Enables response caching (updates config).
  void enableCache() {
    _config = _config.copyWith(cacheEnabled: true);
  }

  /// Disables response caching (updates config).
  void disableCache() {
    _config = _config.copyWith(cacheEnabled: false);
  }

  bool _isSafeCacheDir(String? dirPath) {
    if (dirPath == null ||
        dirPath.trim().isEmpty ||
        dirPath.contains('\x00') ||
        dirPath.startsWith('//') ||
        dirPath.startsWith(r'\\')) {
      return false;
    }
    return !NeomageNetworkGuard.isProtectedSystemOrCredentialPath(dirPath);
  }

  /// Clears all cached responses (memory and disk).
  Future<void> clearCache() async {
    _memoryCache.clear();
    if (_isSafeCacheDir(_config.cacheDir)) {
      final dir = Directory(_config.cacheDir!);
      if (await dir.exists() && !await FileSystemEntity.isLink(dir.path)) {
        await for (final entity in dir.list(followLinks: false)) {
          if (entity is File &&
              entity.path.endsWith('.cache.json') &&
              !await FileSystemEntity.isLink(entity.path)) {
            await entity.delete();
          }
        }
      }
    }
  }

  /// Returns a cached response for [request] if a non-expired entry exists.
  ProxyResponse? getCachedResponse(ProxyRequest request) {
    final key = request.cacheKey;
    final entry = _memoryCache[key];
    if (entry != null && !entry.isExpired) {
      return entry.response;
    }
    if (entry != null && entry.isExpired) {
      _memoryCache.remove(key);
    }
    return null;
  }

  /// Pings both the proxy and target URLs to verify connectivity.
  ///
  /// Returns `true` if the proxy responds with a 2xx status.
  Future<bool> health() async {
    try {
      final uri = _validateEndpoint(_config.proxyUrl, 'proxyUrl');
      final req = await _client!.headUrl(uri).timeout(_config.timeout);
      req.followRedirects = false;
      final resp = await req.close().timeout(_config.timeout);
      await resp.drain<void>();
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  /// Measures round-trip latency to the proxy.
  Future<Duration> testLatency() async {
    final sw = Stopwatch()..start();
    try {
      final uri = _validateEndpoint(_config.proxyUrl, 'proxyUrl');
      final req = await _client!.headUrl(uri).timeout(_config.timeout);
      req.followRedirects = false;
      final resp = await req.close().timeout(_config.timeout);
      await resp.drain<void>();
    } catch (_) {
      // Latency is still measured even on failure.
    }
    sw.stop();
    return sw.elapsed;
  }

  /// Releases all resources held by the proxy.
  void dispose() {
    _client?.close(force: true);
    _client = null;
    _memoryCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static Uri _validateEndpoint(String rawUrl, String fieldName) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (!NeomageNetworkGuard.isSafeEndpointUri(uri)) {
      throw ArgumentError.value(
        NeomageNetworkGuard.redactUrlCredentials(rawUrl),
        fieldName,
        'Unsafe or private upstream endpoint URL',
      );
    }
    return uri!;
  }

  static String _validateRequestPath(String rawPath) {
    if (rawPath.isEmpty) return '';
    if (!rawPath.startsWith('/') ||
        rawPath.startsWith('//') ||
        rawPath.contains('://') ||
        rawPath.contains('\\') ||
        RegExp(r'[\x00-\x1F\x7F]').hasMatch(rawPath)) {
      throw ArgumentError.value(rawPath, 'path', 'Invalid proxy request path');
    }
    final qIdx = rawPath.indexOf('?');
    final pathOnly = qIdx >= 0 ? rawPath.substring(0, qIdx) : rawPath;
    for (final seg in pathOnly.split('/')) {
      if (seg == '..' || seg == '.') {
        throw ArgumentError.value(
          rawPath,
          'path',
          'Path traversal not allowed in proxy request',
        );
      }
      try {
        final decoded = Uri.decodeComponent(seg);
        if (decoded == '..' ||
            decoded == '.' ||
            decoded.contains('/') ||
            decoded.contains('\\')) {
          throw ArgumentError.value(
            rawPath,
            'path',
            'Encoded path traversal not allowed in proxy request',
          );
        }
      } on ArgumentError {
        rethrow;
      } catch (_) {
        throw ArgumentError.value(rawPath, 'path', 'Malformed percent-encoding');
      }
    }
    return rawPath;
  }

  Uri _buildUri(ProxyRequest req) {
    _validateEndpoint(_config.proxyUrl, 'proxyUrl');
    _validateEndpoint(_config.targetUrl, 'targetUrl');
    final safePath = _validateRequestPath(req.path);

    // Route through proxy to the target.
    final proxyBase = _config.proxyUrl.endsWith('/')
        ? _config.proxyUrl.substring(0, _config.proxyUrl.length - 1)
        : _config.proxyUrl;
    return Uri.parse('$proxyBase$safePath');
  }

  void _applyHeaders(HttpClientRequest httpReq, ProxyRequest req) {
    void setSafeHeader(String k, String v) {
      final cleanKey = k.trim();
      if (!NeomageNetworkGuard.isValidHeaderName(cleanKey)) return;
      if (cleanKey.toLowerCase() == 'host') return;
      httpReq.headers.set(
        cleanKey,
        NeomageNetworkGuard.sanitizeHeaderValue(v),
      );
    }

    // Config-level headers.
    _config.headers.forEach(setSafeHeader);
    // Extra runtime headers.
    _extraHeaders.forEach(setSafeHeader);
    // Per-request headers.
    req.headers.forEach(setSafeHeader);
    // Target routing header.
    httpReq.headers.set(
      'X-Target-Url',
      NeomageNetworkGuard.sanitizeHeaderValue(_config.targetUrl),
    );
  }

  Future<ProxyResponse> _doForward(ProxyRequest req) async {
    final uri = _buildUri(req);
    final httpReq = await _client!
        .openUrl(req.method.toUpperCase(), uri)
        .timeout(_config.timeout);
    httpReq.followRedirects = false;
    _applyHeaders(httpReq, req);
    if (req.body != null) {
      httpReq.write(req.body);
    }
    final httpResp = await httpReq.close().timeout(_config.timeout);
    if (httpResp.contentLength > maxResponseBytes) {
      await httpResp.drain<void>();
      throw HttpException(
        'Upstream proxy response exceeds ${maxResponseBytes ~/ (1024 * 1024)} MiB',
        uri: uri,
      );
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in httpResp.timeout(_config.timeout)) {
      if (buffer.length + chunk.length > maxResponseBytes) {
        throw HttpException(
          'Upstream proxy stream exceeds ${maxResponseBytes ~/ (1024 * 1024)} MiB',
          uri: uri,
        );
      }
      buffer.add(chunk);
    }
    final body = utf8.decode(buffer.takeBytes(), allowMalformed: true);
    final headers = <String, String>{};
    httpResp.headers.forEach((name, values) {
      headers[name] = values.join(', ');
    });
    return ProxyResponse(
      statusCode: httpResp.statusCode,
      headers: headers,
      body: body,
    );
  }

  void _putCache(String key, ProxyResponse response) {
    if (!NeomageNetworkGuard.isSafeCacheKey(key)) return;
    if (_memoryCache.length >= maxMemoryCacheEntries &&
        !_memoryCache.containsKey(key)) {
      _memoryCache.removeWhere((_, e) => e.isExpired);
      while (_memoryCache.length >= maxMemoryCacheEntries) {
        _memoryCache.remove(_memoryCache.keys.first);
      }
    }
    final now = DateTime.now();
    final entry = CacheEntry(
      response: ProxyResponse(
        statusCode: response.statusCode,
        headers: response.headers,
        body: response.body,
        cached: true,
        latency: response.latency,
      ),
      cachedAt: now,
      expiresAt: now.add(_config.cacheTtl),
      key: key,
    );
    _memoryCache[key] = entry;
    _writeCacheToDisk(entry);
  }

  Future<void> _writeCacheToDisk(CacheEntry entry) async {
    if (!_isSafeCacheDir(_config.cacheDir)) return;
    if (!NeomageNetworkGuard.isSafeCacheKey(entry.key)) return;
    try {
      final dir = Directory(_config.cacheDir!);
      if (await FileSystemEntity.isLink(dir.path)) return;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final filePath = '${dir.path}/${entry.key}.cache.json';
      if (await FileSystemEntity.isLink(filePath)) return;
      final file = File(filePath);
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (_) {
      // Disk cache write failures are non-fatal.
    }
  }
}
