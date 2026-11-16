import 'dart:convert';

import 'package:crypto/crypto.dart' show sha256;
import 'package:neomage/core/platform/neomage_io.dart' as io;

/// Pure-Dart security utilities for `neomage` network transports, local HTTP/WS
/// bridges, OAuth clients, proxies, and plugin loaders.
///
/// Contains zero `dart:io` imports so all helpers execute identically on
/// Desktop/Mobile VM and Chrome Web (JS/Wasm).
class NeomageNetworkGuard {
  const NeomageNetworkGuard._();

  static final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F-\x9F]');
  static final RegExp _bidiAndInvisibleChars = RegExp(
    r'[\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
  );
  static final RegExp _idnDotHomoglyphs = RegExp(r'[\u3002\uFF0E\uFF61]');
  static final RegExp _headerNamePattern = RegExp(
    r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]{1,128}$",
  );
  static final RegExp _safeCacheKeyPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');
  static final RegExp _inlineSecrets = RegExp(
    r'(?:Bearer\s+[A-Za-z0-9._\-~+/]+=*|sk-[A-Za-z0-9_\-]{12,}|AIza[0-9A-Za-z_\-]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9\-]{10,})',
    caseSensitive: false,
  );
  static const Set<String> _sensitiveQueryKeys = <String>{
    'token',
    'access_token',
    'refresh_token',
    'api_key',
    'apikey',
    'key',
    'secret',
    'password',
    'code',
    'state',
    'client_secret',
  };

  /// Constant-time string comparison over UTF-8 bytes to prevent timing
  /// side-channel attacks on bearer tokens, API keys, and OAuth `state`.
  static bool constantTimeEquals(String? a, String? b) {
    if (a == null || b == null) return false;
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    var diff = aBytes.length ^ bBytes.length;
    final maxLen = aBytes.length > bBytes.length ? aBytes.length : bBytes.length;
    for (var i = 0; i < maxLen; i++) {
      final av = i < aBytes.length ? aBytes[i] : 0;
      final bv = i < bBytes.length ? bBytes[i] : 0;
      diff |= av ^ bv;
    }
    return diff == 0 && aBytes.isNotEmpty;
  }

  /// Strips CR, LF, and NUL characters to prevent HTTP header / CRLF injection.
  static String sanitizeHeaderValue(String value, {int maxChars = 8192}) {
    final safeMax = (maxChars.isFinite && maxChars > 0) ? maxChars : 8192;
    final cleaned = value.replaceAll(RegExp(r'[\r\n\x00]'), '').trim();
    if (cleaned.length <= safeMax) return cleaned;
    return cleaned.substring(0, safeMax);
  }

  /// Validates an RFC 7230 HTTP header field-name token.
  static bool isValidHeaderName(String name) =>
      _headerNamePattern.hasMatch(name);

  /// Validates a disk cache filename stem (`[A-Za-z0-9_-]{1,128}`).
  static bool isSafeCacheKey(String key) => _safeCacheKeyPattern.hasMatch(key);

  /// Computes a collision-resistant SHA-256 hex digest.
  static String sha256Hex(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  /// Returns `true` when [rawHost] resolves to a loopback, link-local,
  /// cloud-metadata, RFC1918, CGNAT, multicast, IPv6 ULA, or obfuscated IP
  /// host. When [allowLoopback] is `true`, strict loopback literals
  /// (`localhost`, `127.0.0.1`, `::1`) are permitted for local dev bridges.
  static bool isPrivateOrReservedHost(
    String rawHost, {
    bool allowLoopback = false,
  }) {
    if (_controlChars.hasMatch(rawHost) ||
        _bidiAndInvisibleChars.hasMatch(rawHost)) {
      return true;
    }
    var host = rawHost
        .trim()
        .toLowerCase()
        .replaceAll(_idnDotHomoglyphs, '.');
    if (host.isEmpty || host.contains(r'\')) return true;

    if (host.startsWith('[') && host.endsWith(']')) {
      host = host.substring(1, host.length - 1);
    }
    while (host.endsWith('.')) {
      host = host.substring(0, host.length - 1);
    }
    if (host.isEmpty) return true;

    final pctIdx = host.indexOf('%');
    if (pctIdx >= 0) {
      if (!allowLoopback) return true;
      host = host.substring(0, pctIdx);
      if (host.isEmpty) return true;
    }

    // Strict loopback literals.
    if (host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0:0:0:0:0:0:0:1') {
      return !allowLoopback;
    }
    if (host.endsWith('.localhost')) {
      return !allowLoopback;
    }

    // Unspecified & cloud metadata / mDNS / internal / RFC 2606 .invalid suffixes.
    if (host == '0.0.0.0' ||
        host == '::' ||
        host == '0:0:0:0:0:0:0:0' ||
        host == 'metadata' ||
        host == 'instance-data' ||
        host == 'invalid' ||
        host == 'metadata.google.internal' ||
        host == 'metadata.goog' ||
        host == 'metadata.azure.com' ||
        host.endsWith('.internal') ||
        host.endsWith('.local') ||
        host.endsWith('.corp') ||
        host.endsWith('.lan') ||
        host.endsWith('.home.arpa') ||
        host.endsWith('.invalid')) {
      return true;
    }

    // IPv6 literals (including NAT64 64:ff9b::/96, 6to4 2002::/16, Teredo 2001:0::/32).
    if (host.contains(':')) {
      if (host.startsWith('fe8') ||
          host.startsWith('fe9') ||
          host.startsWith('fea') ||
          host.startsWith('feb') ||
          host.startsWith('fc') ||
          host.startsWith('fd') ||
          host.startsWith('ff') ||
          host.startsWith('64:ff9b:') ||
          host.startsWith('2002:') ||
          host.startsWith('2001:0:') ||
          host.startsWith('2001:0000:') ||
          host.contains('::ffff:') ||
          host.startsWith('0:0:0:0:0:ffff:')) {
        return true;
      }
      return false;
    }

    // Obfuscated integer/hex/octal or shorthand IPv4 literals (JS-safe: zero
    // `<< 24` / `>> 24` bit-shifts so negative receivers or >=128 octets never
    // throw `ArgumentError` or overflow signed 32-bit ints on Chrome Web).
    final octets = _tryParseIpv4Octets(host);
    if (octets != null) {
      if (octets.length != 4) return true; // overflow numeric/IPv4 literal
      final a = octets[0];
      final b = octets[1];
      if (a == 0) return true; // 0.0.0.0/8
      if (a == 10) return true; // 10.0.0.0/8
      if (a == 100 && (b >= 64 && b <= 127)) {
        return true; // 100.64.0.0/10 (CGNAT + Alibaba IMDS 100.100.100.200)
      }
      if (a == 127) return true; // non-127.0.0.1 loopback
      if (a == 169 && b == 254) return true; // 169.254.0.0/16 (IMDS)
      if (a == 172 && (b >= 16 && b <= 31)) return true; // 172.16.0.0/12
      if (a == 192 && b == 0) return true; // 192.0.0.0/24
      if (a == 192 && b == 168) return true; // 192.168.0.0/16
      if (a == 198 && (b == 18 || b == 19)) return true; // 198.18.0.0/15
      if (a >= 224) return true; // Multicast & reserved
      return false;
    }

    // Reject single-label intranet hostnames and numeric/hex-only TLDs.
    final labels = host.split('.');
    if (labels.length < 2 || labels.any((l) => l.isEmpty)) {
      return true;
    }
    final tld = labels.last;
    if (RegExp(r'^(?:\d+|0x[0-9a-f]+)$').hasMatch(tld)) {
      return true;
    }

    return false;
  }

  static const List<int> _invalidIpv4Sentinel = <int>[-1];

  static List<int> _uint32ToOctets(int value) => <int>[
    (value ~/ 0x1000000) & 0xFF,
    (value ~/ 0x10000) & 0xFF,
    (value ~/ 0x100) & 0xFF,
    value & 0xFF,
  ];

  static List<int>? _tryParseIpv4Octets(String host) {
    // Pure integer (e.g. 2130706433 or 2852039166) or hex (0x7f000001).
    if (RegExp(r'^\d+$').hasMatch(host)) {
      final v = int.tryParse(host);
      if (v != null && v >= 0 && v <= 0xFFFFFFFF) return _uint32ToOctets(v);
      return _invalidIpv4Sentinel; // overflow numeric host -> treat as reserved
    }
    if (RegExp(r'^0x[0-9a-f]+$').hasMatch(host)) {
      final v = int.tryParse(host.substring(2), radix: 16);
      if (v != null && v >= 0 && v <= 0xFFFFFFFF) return _uint32ToOctets(v);
      return _invalidIpv4Sentinel;
    }

    final parts = host.split('.');
    if (parts.length < 2 || parts.length > 4) return null;
    final nums = <int>[];
    for (final p in parts) {
      if (p.isEmpty) return null;
      int? parsed;
      if (p.startsWith('0x')) {
        parsed = int.tryParse(p.substring(2), radix: 16);
      } else if (p.length > 1 &&
          p.startsWith('0') &&
          RegExp(r'^[0-7]+$').hasMatch(p)) {
        parsed = int.tryParse(p, radix: 8);
      } else if (RegExp(r'^\d+$').hasMatch(p)) {
        parsed = int.tryParse(p);
      }
      if (parsed == null || parsed < 0) return null;
      nums.add(parsed);
    }

    if (nums.length == 4) {
      if (nums.any((n) => n > 255)) return _invalidIpv4Sentinel;
      return nums;
    }
    if (nums.length == 3) {
      if (nums[0] > 255 || nums[1] > 255 || nums[2] > 0xFFFF) {
        return _invalidIpv4Sentinel;
      }
      return <int>[
        nums[0],
        nums[1],
        (nums[2] ~/ 0x100) & 0xFF,
        nums[2] & 0xFF,
      ];
    }
    if (nums.length == 2) {
      if (nums[0] > 255 || nums[1] > 0xFFFFFF) return _invalidIpv4Sentinel;
      return <int>[
        nums[0],
        (nums[1] ~/ 0x10000) & 0xFF,
        (nums[1] ~/ 0x100) & 0xFF,
        nums[1] & 0xFF,
      ];
    }
    return null;
  }

  /// Validates an endpoint URI (`https`/`wss` for public hosts, or optional
  /// `http`/`ws` strictly on `localhost` / `127.0.0.1` / `[::1]` or RFC1918 LAN
  /// when [allowPrivateLanHttp] is `true`).
  static bool isSafeEndpointUri(
    Uri? uri, {
    bool allowLoopbackInsecure = true,
    bool? allowLoopbackHttp,
    bool allowPrivateLanHttp = false,
    bool allowPublicInsecure = false,
    Set<String> secureSchemes = const <String>{'https', 'wss'},
    Set<String> insecureSchemes = const <String>{'http', 'ws'},
  }) {
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty) return false;
    final rawUri = uri.toString();
    if (_controlChars.hasMatch(rawUri) ||
        _bidiAndInvisibleChars.hasMatch(rawUri) ||
        rawUri.contains(r'\') ||
        rawUri.toLowerCase().contains('%5c')) {
      return false;
    }

    final scheme = uri.scheme.toLowerCase();
    final isSecure = secureSchemes.contains(scheme);
    final isInsecure = insecureSchemes.contains(scheme);
    if (!isSecure && !isInsecure) return false;

    final effectiveAllowLoopbackInsecure =
        allowLoopbackHttp ?? allowLoopbackInsecure;

    final hostLower = uri.host.toLowerCase();
    final cleanHost = hostLower.startsWith('[') && hostLower.endsWith(']')
        ? hostLower.substring(1, hostLower.length - 1)
        : hostLower;
    final isStrictLoopback =
        cleanHost == 'localhost' ||
        cleanHost == '127.0.0.1' ||
        cleanHost == '::1' ||
        cleanHost == '0:0:0:0:0:0:0:1';

    if (isStrictLoopback) {
      return isSecure || effectiveAllowLoopbackInsecure;
    }

    if (allowPrivateLanHttp && isSafeLanDiscoveryHost(cleanHost)) {
      return isSecure || isInsecure;
    }

    if (isInsecure && !allowPublicInsecure) return false;
    return !isPrivateOrReservedHost(uri.host, allowLoopback: false);
  }

  /// Validates whether a target IPv4 literal is safe for local LAN discovery
  /// (`127.0.0.1` or RFC1918 private IPv4 literal only — blocks public hosts,
  /// cloud metadata `169.254.169.254`, and URL injection).
  static bool isSafeLanDiscoveryHost(String rawHost) {
    final trimmed = rawHost.trim().toLowerCase();
    if (trimmed == 'localhost' || trimmed == '127.0.0.1') return true;
    final parts = trimmed.split('.');
    if (parts.length != 4) return false;
    final octets = <int>[];
    for (final p in parts) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(p)) return false;
      final v = int.tryParse(p);
      if (v == null || v < 0 || v > 255) return false;
      octets.add(v);
    }
    final a = octets[0];
    final b = octets[1];
    if (a == 10) return true;
    if (a == 172 && b >= 16 && b <= 31) return true;
    if (a == 192 && b == 168) return true;
    return false;
  }

  /// Evaluates browser `Origin` headers for local HTTP / WebSocket servers to
  /// prevent Cross-Site WebSocket Hijacking (CSWSH) and cross-origin probing.
  ///
  /// - Non-browser CLI/native clients omit `Origin` (`origin == null`): allowed.
  /// - Sandboxed/opaque `'null'` origin: rejected unless explicitly in
  ///   [allowedOrigins].
  /// - Wildcard `'*'` in [allowedOrigins] is intentionally NOT treated as a
  ///   blanket pass for cross-site browser origins unless
  ///   [allowWildcardBrowserOrigin] is explicitly `true`.
  static bool isAllowedLocalServerOrigin(
    String? origin, {
    List<String> allowedOrigins = const <String>[],
    bool allowIdeSchemes = false,
    bool allowWildcardBrowserOrigin = false,
  }) {
    if (origin == null) return true;
    final trimmed = origin.trim();
    if (trimmed.isEmpty || _controlChars.hasMatch(trimmed)) return false;

    if (trimmed.toLowerCase() == 'null') {
      return allowedOrigins.contains('null');
    }

    if (allowWildcardBrowserOrigin && allowedOrigins.contains('*')) {
      return true;
    }

    for (final candidate in allowedOrigins) {
      if (candidate != '*' && candidate.trim() == trimmed) {
        return true;
      }
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme) return false;
    final scheme = uri.scheme.toLowerCase();

    if (allowIdeSchemes &&
        (scheme == 'vscode-webview' ||
            scheme == 'vscode-file' ||
            scheme == 'jetbrains')) {
      return true;
    }

    if (scheme != 'http' && scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    final cleanHost = host.startsWith('[') && host.endsWith(']')
        ? host.substring(1, host.length - 1)
        : host;
    return cleanHost == 'localhost' ||
        cleanHost == '127.0.0.1' ||
        cleanHost == '::1' ||
        cleanHost == '0:0:0:0:0:0:0:1';
  }

  /// Redacts embedded `userInfo` and sensitive query parameters from a URL
  /// before logging or surfacing error messages.
  static String redactUrlCredentials(String rawUrl) {
    final cleaned = rawUrl.replaceAll(_controlChars, '').trim();
    final uri = Uri.tryParse(cleaned);
    if (uri == null) {
      return cleaned.replaceAll(_inlineSecrets, '[REDACTED]');
    }

    Map<String, String>? sanitizedQuery;
    if (uri.queryParameters.isNotEmpty) {
      sanitizedQuery = <String, String>{};
      uri.queryParameters.forEach((k, v) {
        if (_sensitiveQueryKeys.contains(k.toLowerCase())) {
          sanitizedQuery![k] = '[REDACTED]';
        } else {
          sanitizedQuery![k] = v.replaceAll(_inlineSecrets, '[REDACTED]');
        }
      });
    }

    var rebuilt = uri.replace(
      userInfo: uri.userInfo.isNotEmpty ? 'REDACTED' : null,
      queryParameters: sanitizedQuery,
    );
    return rebuilt.toString().replaceAll(_inlineSecrets, '[REDACTED]');
  }

  /// Extracts a safe, bounded OAuth error summary without dumping raw HTTP
  /// bodies (which could echo tokens, HTML debug pages, or internal traces).
  static String sanitizeOAuthErrorBody(String rawBody, {int maxChars = 200}) {
    final safeMax = (maxChars.isFinite && maxChars > 0) ? maxChars : 200;
    if (rawBody.trim().isEmpty) return 'empty error response';
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        final err = decoded['error']?.toString() ?? '';
        final desc = decoded['error_description']?.toString() ?? '';
        final combined = [
          if (err.isNotEmpty) err,
          if (desc.isNotEmpty) desc,
        ].join(': ');
        if (combined.isNotEmpty) {
          final redacted = combined
              .replaceAll(_inlineSecrets, '[REDACTED]')
              .replaceAll(_controlChars, ' ')
              .trim();
          return redacted.length <= safeMax
              ? redacted
              : '${redacted.substring(0, safeMax)}...';
        }
      }
    } catch (_) {
      // Non-JSON error body: do not echo raw payload.
    }
    return 'upstream error payload redacted';
  }

  /// Safely masks an API key for debug logging without throwing `RangeError`
  /// on short keys (`< 4` chars) or leaking short keys (`< 12` chars).
  static String maskApiKey(String? apiKey) {
    if (apiKey == null) return 'none';
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) return 'empty';
    if (trimmed.length < 12) return '***';
    return '${trimmed.substring(0, 4)}...${trimmed.substring(trimmed.length - 4)}';
  }

  /// Extracts a safe, bounded LLM API error summary from JSON (`OpenAI` /
  /// `Anthropic` format) while redacting secrets and dropping raw HTML dumps.
  static String sanitizeApiErrorBody(String rawBody, {int maxChars = 240}) {
    if (rawBody.trim().isEmpty) return 'empty error response';
    try {
      final decoded = jsonDecode(rawBody);
      if (decoded is Map) {
        String? extracted;
        final errObj = decoded['error'];
        if (errObj is Map) {
          final type = errObj['type']?.toString() ?? '';
          final msg = errObj['message']?.toString() ?? '';
          extracted = [
            if (type.isNotEmpty) type,
            if (msg.isNotEmpty) msg,
          ].join(': ');
        } else if (errObj is String && errObj.isNotEmpty) {
          extracted = errObj;
        } else if (decoded['message'] is String) {
          extracted = decoded['message'] as String;
        }
        if (extracted != null && extracted.trim().isNotEmpty) {
          final clean = redactTransportError(extracted, maxChars: maxChars);
          if (clean.isNotEmpty) return clean;
        }
      }
    } catch (_) {
      // Non-JSON body: avoid echoing raw upstream HTML/proxies.
    }
    return 'upstream error payload redacted';
  }

  /// Redacts URL query secrets (`?key=...`, `access_token=...`, `userInfo`)
  /// and inline API keys/tokens from transport error strings.
  static String redactTransportError(String rawMessage, {int maxChars = 300}) {
    final safeMax = (maxChars.isFinite && maxChars > 0) ? maxChars : 300;
    final urlPattern = RegExp(r'(?:https?|wss?)://[^\s"<>]+', caseSensitive: false);
    var sanitized = rawMessage.replaceAllMapped(
      urlPattern,
      (m) => redactUrlCredentials(m.group(0)!),
    );
    sanitized = sanitized.replaceAllMapped(
      RegExp(
        r'([?&](?:key|api_key|apikey|token|access_token|refresh_token|secret|password|client_secret)=)([^&\s"<>]+)',
        caseSensitive: false,
      ),
      (m) => '${m.group(1)}[REDACTED]',
    );
    sanitized = sanitized
        .replaceAll(_inlineSecrets, '[REDACTED]')
        .replaceAll(_controlChars, ' ')
        .trim();
    if (sanitized.length <= safeMax) return sanitized;
    return '${sanitized.substring(0, safeMax)}...';
  }

  /// Validates an opaque identifier (session ID, org UUID, request ID) used in
  /// URL path segments or query parameters (`[A-Za-z0-9._-]`, no `..`).
  static bool isSafeIdentifier(String value, {int maxLength = 128}) {
    final safeMax = (maxLength.isFinite && maxLength > 0) ? maxLength : 128;
    if (value.isEmpty || value.length > safeMax) return false;
    if (value.contains('..')) return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
  }

  static final RegExp _safeModelIdPattern = RegExp(
    r'^[A-Za-z0-9._:@/\-]{1,128}$',
  );

  /// Validates an LLM model identifier to prevent URL path/query smuggling.
  static bool isSafeModelIdentifier(String rawModel) {
    final trimmed = rawModel.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('/') ||
        trimmed.endsWith('/') ||
        trimmed.contains('..') ||
        trimmed.contains(r'\')) {
      return false;
    }
    return _safeModelIdPattern.hasMatch(trimmed);
  }

  /// Validates a provider base URL before transmitting prompts or API keys:
  /// - Cloud providers (`allowLocalHttp: false`) MUST use `https://` on a
  ///   non-private host.
  /// - Local/custom providers (`allowLocalHttp: true`) may use `http://`
  ///   strictly on loopback (or RFC1918 LAN only when `!hasApiKey`), blocking
  ///   cloud metadata IMDS and cleartext public internet API-key leakage.
  static Uri? validateProviderBaseUri(
    String rawBaseUrl, {
    required bool allowLocalHttp,
    bool hasApiKey = false,
  }) {
    var trimmed = rawBaseUrl.trim();
    if (trimmed.isEmpty || trimmed.contains(r'\')) return null;
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.hasQuery || uri.hasFragment) return null;
    if (uri.pathSegments.contains('..')) return null;

    final ok = isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: allowLocalHttp,
      allowPrivateLanHttp: allowLocalHttp && !hasApiKey,
      allowPublicInsecure: false,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{'http'},
    );
    return ok ? uri : null;
  }

  /// Validates a strict semantic version slug without path separators or `..`.
  static bool isSafeSemverSlug(String value) {
    if (value.isEmpty || value.length > 64) return false;
    if (value.contains('..') || value.contains('/') || value.contains(r'\')) {
      return false;
    }
    return RegExp(
      r'^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?$',
    ).hasMatch(value);
  }

  /// Validates a WebSocket (`wss://`, or `ws://` strictly on loopback / LAN) URI.
  static bool isSafeWebSocketEndpointUri(
    Uri? uri, {
    bool allowLoopbackInsecure = true,
    bool? allowLoopbackWs,
    bool allowPrivateLanWs = false,
  }) {
    if (uri == null || uri.hasFragment) return false;
    return isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: allowLoopbackWs ?? allowLoopbackInsecure,
      allowPrivateLanHttp: allowPrivateLanWs,
      allowPublicInsecure: false,
      secureSchemes: const <String>{'wss'},
      insecureSchemes: const <String>{'ws'},
    );
  }

  static const Set<String> _blockedSubprocessEnvKeys = <String>{
    'ld_preload',
    'ld_library_path',
    'ld_audit',
    'dyld_insert_libraries',
    'dyld_library_path',
    'dyld_framework_path',
    'dyld_fallback_library_path',
    'bash_env',
    'env',
    'prompt_command',
    'zdotdir',
    'node_options',
    'pythonstartup',
    'pythonpath',
    'perl5opt',
    'rubyopt',
    'java_tool_options',
    '_java_options',
  };

  /// Filters dangerous dynamic-linker and interpreter startup environment
  /// variables when spawning MCP / hook / system subprocesses.
  ///
  /// When [env] is omitted, defaults to `Platform.environment` so essential
  /// lookup variables (`PATH`, `HOME`, `TMPDIR`) are preserved while loader
  /// hijacks (`DYLD_INSERT_LIBRARIES`, `LD_PRELOAD`, `BASH_ENV`, etc.) are
  /// stripped. Optional [extra] overrides are merged and filtered identically.
  static Map<String, String> sanitizeSubprocessEnv([
    Map<String, String>? env,
    Map<String, String>? extra,
  ]) {
    final base = env ?? io.Platform.environment;
    final out = <String, String>{};
    void addFiltered(Map<String, String> source) {
      for (final entry in source.entries) {
        final k = entry.key.trim();
        if (k.isEmpty || _controlChars.hasMatch(k) || k.contains('=')) continue;
        final lower = k.toLowerCase();
        if (_blockedSubprocessEnvKeys.contains(lower) ||
            lower.startsWith('bash_func_')) {
          continue;
        }
        final v = entry.value.replaceAll('\x00', '');
        if (v.length > 16384) continue;
        out[k] = v;
      }
    }

    if (base.isNotEmpty) addFiltered(base);
    if (extra != null && extra.isNotEmpty) addFiltered(extra);
    return out;
  }

  /// Validates an MCP stdio executable path or binary name.
  static bool isSafeMcpCommand(String command) {
    if (_controlChars.hasMatch(command) ||
        _bidiAndInvisibleChars.hasMatch(command)) {
      return false;
    }
    final trimmed = command.trim();
    if (trimmed.isEmpty || trimmed.length > 512) return false;
    if (trimmed.startsWith('-') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith(r'\??\')) {
      return false;
    }
    if (RegExp(r'[;|`$&<>()]').hasMatch(trimmed)) return false;
    final segments = trimmed.split(RegExp(r'[/\\]'));
    if (segments.contains('..')) return false;
    return true;
  }

  static const List<String> _protectedSystemPrefixes = <String>[
    '/etc',
    '/private/etc',
    '/usr',
    '/bin',
    '/sbin',
    '/boot',
    '/dev',
    '/proc',
    '/sys',
    '/var/run',
    '/private/var/run',
    '/System',
    '/Library/System',
  ];

  static const Set<String> _protectedCredentialSegments = <String>{
    '.ssh',
    '.gnupg',
    '.aws',
    '.kube',
    '.docker',
    'gcloud',
  };

  /// Returns a human-readable block reason when [filePath] targets a protected
  /// OS system tree or credential directory/file, using strict segment boundaries
  /// (so `/developer/app` is NOT falsely matched by `/dev`).
  static String? checkProtectedFilesystemPath(String filePath) {
    if (_controlChars.hasMatch(filePath) ||
        _bidiAndInvisibleChars.hasMatch(filePath)) {
      return 'Disallowed control or BiDi character in file path';
    }
    final trimmed = filePath.trim();
    if (trimmed.startsWith('//') ||
        trimmed.startsWith(r'\\') ||
        trimmed.startsWith(r'\??\')) {
      return 'UNC network share or NT device path is not allowed';
    }
    var normalized = trimmed.replaceAll(r'\', '/');
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    for (final protected in _protectedSystemPrefixes) {
      if (normalized == protected || normalized.startsWith('$protected/')) {
        return 'Cannot modify protected system path: $protected';
      }
    }
    final segments = normalized.split('/');
    for (final seg in segments) {
      final lowerSeg = seg.toLowerCase();
      if (_protectedCredentialSegments.contains(lowerSeg)) {
        return 'Cannot modify protected credential directory: $seg';
      }
    }
    final baseName = segments.isEmpty ? '' : segments.last.toLowerCase();
    if (baseName == '.env' ||
        baseName.startsWith('.env.') ||
        baseName == '.secret.local' ||
        baseName == '.netrc' ||
        baseName == '.npmrc' ||
        baseName == '.pypirc' ||
        baseName == '.git-credentials' ||
        baseName == 'application_default_credentials.json' ||
        baseName == 'id_rsa' ||
        baseName == 'id_ed25519' ||
        baseName == 'authorized_keys' ||
        baseName.endsWith('.pem') ||
        baseName.endsWith('.key') ||
        baseName.endsWith('.p12') ||
        baseName.endsWith('.pfx') ||
        baseName.endsWith('.kdbx')) {
      return 'Cannot access protected credential file: $baseName';
    }
    return null;
  }

  /// Boolean convenience wrapper around [checkProtectedFilesystemPath].
  static bool isProtectedSystemOrCredentialPath(String filePath) =>
      checkProtectedFilesystemPath(filePath) != null;

  static const Set<String> _allowedChatRoles = <String>{
    'system',
    'user',
    'assistant',
    'tool',
  };

  static final RegExp _chatMlSpecialTokens = RegExp(
    r'<\|(?:im_start|im_end|endoftext|eot_id|start_header_id|end_header_id|/?turn)\|>|<\|channel>|<channel\|>|<(?:start|end)_of_turn>',
    caseSensitive: false,
  );

  /// Formats messages into ChatML while neutralizing ChatML/Llama control-token
  /// injection (`<|im_start|>`, `<|im_end|>`, `<|endoftext|>`) and enforcing
  /// a strict role allowlist (`system`, `user`, `assistant`, `tool`).
  static String formatChatMlSafe(List<Map<String, String>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final rawRole = (msg['role'] ?? 'user').trim().toLowerCase();
      final role = _allowedChatRoles.contains(rawRole) ? rawRole : 'user';
      final rawContent = msg['content'] ?? '';
      final sanitizedContent = rawContent
          .replaceAll('\x00', '')
          .replaceAll(_chatMlSpecialTokens, '');
      buffer.write('<|im_start|>$role\n$sanitizedContent<|im_end|>\n');
    }
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }
}
