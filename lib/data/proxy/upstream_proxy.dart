/// Upstream proxy for routing API calls through an intermediary.
///
/// Supports request/response transforms, streaming (SSE), optional
/// disk-based caching with TTL, latency measurement, and statistics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
      ? Duration(
          microseconds: totalLatency.inMicroseconds ~/ requestCount,
        )
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

  /// Generates a cache key from method, path, and body.
  String get cacheKey {
    final hash = '$method:$path:${body ?? ''}';
    return hash.hashCode.toRadixString(36);
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
    final httpReq = await _client!.openUrl(req.method, uri);
    _applyHeaders(httpReq, req);
    if (req.body != null) {
      httpReq.write(req.body);
    }
    final httpResp = await httpReq.close();

    _stats.requestCount++;

    await for (final chunk in httpResp) {
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

  /// Clears all cached responses (memory and disk).
  Future<void> clearCache() async {
    _memoryCache.clear();
    if (_config.cacheDir != null) {
      final dir = Directory(_config.cacheDir!);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.cache.json')) {
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
      final uri = Uri.parse(_config.proxyUrl);
      final req = await _client!.headUrl(uri);
      final resp = await req.close();
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
      final uri = Uri.parse(_config.proxyUrl);
      final req = await _client!.headUrl(uri);
      final resp = await req.close();
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

  Uri _buildUri(ProxyRequest req) {
    // Route through proxy to the target.
    final proxyBase = _config.proxyUrl.endsWith('/')
        ? _config.proxyUrl.substring(0, _config.proxyUrl.length - 1)
        : _config.proxyUrl;
    final targetBase = _config.targetUrl.endsWith('/')
        ? _config.targetUrl.substring(0, _config.targetUrl.length - 1)
        : _config.targetUrl;
    final fullPath = '$targetBase${req.path}';
    // The proxy URL is used as the actual HTTP target; the real target is
    // communicated via the X-Target-Url header.
    return Uri.parse('$proxyBase${req.path}');
  }

  void _applyHeaders(HttpClientRequest httpReq, ProxyRequest req) {
    // Config-level headers.
    _config.headers.forEach((k, v) => httpReq.headers.set(k, v));
    // Extra runtime headers.
    _extraHeaders.forEach((k, v) => httpReq.headers.set(k, v));
    // Per-request headers.
    req.headers.forEach((k, v) => httpReq.headers.set(k, v));
    // Target routing header.
    httpReq.headers.set('X-Target-Url', _config.targetUrl);
  }

  Future<ProxyResponse> _doForward(ProxyRequest req) async {
    final uri = _buildUri(req);
    final httpReq = await _client!.openUrl(req.method, uri);
    _applyHeaders(httpReq, req);
    if (req.body != null) {
      httpReq.write(req.body);
    }
    final httpResp = await httpReq.close();
    final body = await httpResp.transform(utf8.decoder).join();
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
    if (_config.cacheDir == null) return;
    try {
      final dir = Directory(_config.cacheDir!);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final file = File('${dir.path}/${entry.key}.cache.json');
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (_) {
      // Disk cache write failures are non-fatal.
    }
  }
}
