// Port of openneomclaw proxy.ts + http.ts + mtls.ts + caCerts.ts +
// caCertsConfig.ts
//
// Proxy configuration, HTTP utilities, mTLS certificate handling,
// and CA certificate management for the neom_claw package.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// caCerts.ts  --  CA certificate loading
// ---------------------------------------------------------------------------

/// Cached CA certificates.
List<String>? _caCertsCache;
bool _caCertsCacheInitialized = false;

/// Load CA certificates for TLS connections.
///
/// Since setting `ca` on an HTTPS agent replaces the default certificate store,
/// we must always include base CAs when returning.
///
/// Returns null when no custom CA configuration is needed, allowing the
/// runtime's default certificate handling to apply.
///
/// Behavior:
/// - Neither NODE_EXTRA_CA_CERTS nor --use-system-ca set: null (runtime defaults)
/// - NODE_EXTRA_CA_CERTS only: extra cert file contents
/// - --use-system-ca: system CAs + extra cert file
List<String>? getCACertificates() {
  if (_caCertsCacheInitialized) return _caCertsCache;
  _caCertsCacheInitialized = true;

  final useSystemCA = _hasNodeOption('--use-system-ca') ||
      _hasNodeOption('--use-openssl-ca');
  final extraCertsPath = Platform.environment['NODE_EXTRA_CA_CERTS'];

  // If neither is set, return null (use runtime defaults)
  if (!useSystemCA && (extraCertsPath == null || extraCertsPath.isEmpty)) {
    return null;
  }

  final certs = <String>[];

  // When useSystemCA is true but we're in Dart, we don't have direct
  // access to system CAs like Node's tls.rootCertificates.
  // In a Flutter/Dart app, the system CA store is used automatically.
  // We only handle the extra certs path.

  if (extraCertsPath != null && extraCertsPath.isNotEmpty) {
    try {
      final extraCert = File(extraCertsPath).readAsStringSync();
      certs.add(extraCert);
    } catch (error) {
      stderr.writeln(
        'CA certs: Failed to read NODE_EXTRA_CA_CERTS file '
        '($extraCertsPath): $error',
      );
    }
  }

  _caCertsCache = certs.isNotEmpty ? certs : null;
  return _caCertsCache;
}

/// Clear the CA certificates cache.
void clearCACertsCache() {
  _caCertsCache = null;
  _caCertsCacheInitialized = false;
}

bool _hasNodeOption(String flag) {
  final nodeOptions = Platform.environment['NODE_OPTIONS'];
  if (nodeOptions == null) return false;
  return nodeOptions.split(RegExp(r'\s+')).contains(flag);
}

// ---------------------------------------------------------------------------
// caCertsConfig.ts  --  settings-backed NODE_EXTRA_CA_CERTS
// ---------------------------------------------------------------------------

/// Apply NODE_EXTRA_CA_CERTS from settings to the environment early in init.
///
/// This is safe to call before the trust dialog because we only read from
/// user-controlled files (~/.neomclaw/settings.json and ~/.neomclaw.json).
void applyExtraCACertsFromConfig({
  required Map<String, String>? Function() getGlobalConfigEnv,
  required Map<String, String>? Function() getUserSettingsEnv,
}) {
  if (Platform.environment['NODE_EXTRA_CA_CERTS'] != null) return;

  final path = _getExtraCertsPathFromConfig(
    getGlobalConfigEnv: getGlobalConfigEnv,
    getUserSettingsEnv: getUserSettingsEnv,
  );
  if (path != null) {
    // In Dart we can't directly set process.env, but we store it for later use
    _appliedExtraCACertsPath = path;
  }
}

String? _appliedExtraCACertsPath;

/// Get the applied extra CA certs path (set by [applyExtraCACertsFromConfig]).
String? get appliedExtraCACertsPath => _appliedExtraCACertsPath;

String? _getExtraCertsPathFromConfig({
  required Map<String, String>? Function() getGlobalConfigEnv,
  required Map<String, String>? Function() getUserSettingsEnv,
}) {
  try {
    final globalEnv = getGlobalConfigEnv();
    final settingsEnv = getUserSettingsEnv();

    // Settings override global config
    final path = settingsEnv?['NODE_EXTRA_CA_CERTS'] ??
        globalEnv?['NODE_EXTRA_CA_CERTS'];
    return path;
  } catch (error) {
    stderr.writeln('CA certs: Config fallback failed: $error');
    return null;
  }
}

// ---------------------------------------------------------------------------
// mtls.ts  --  Mutual TLS configuration
// ---------------------------------------------------------------------------

/// Mutual TLS configuration.
class MTLSConfig {
  const MTLSConfig({
    this.cert,
    this.key,
    this.passphrase,
  });

  final String? cert;
  final String? key;
  final String? passphrase;

  bool get isEmpty => cert == null && key == null && passphrase == null;
  bool get isNotEmpty => !isEmpty;
}

/// TLS configuration (mTLS + CA certs).
class TLSConfig {
  const TLSConfig({
    this.cert,
    this.key,
    this.passphrase,
    this.ca,
  });

  final String? cert;
  final String? key;
  final String? passphrase;
  final List<String>? ca;

  bool get isEmpty => cert == null && key == null && passphrase == null && ca == null;
  bool get isNotEmpty => !isEmpty;
}

/// Cached mTLS configuration.
MTLSConfig? _mtlsConfigCache;
bool _mtlsConfigCacheInitialized = false;

/// Get mTLS configuration from environment variables.
MTLSConfig? getMTLSConfig() {
  if (_mtlsConfigCacheInitialized) return _mtlsConfigCache;
  _mtlsConfigCacheInitialized = true;

  String? cert;
  String? key;
  String? passphrase;

  // Client certificate
  final certPath = Platform.environment['NEOMCLAW_CLIENT_CERT'];
  if (certPath != null && certPath.isNotEmpty) {
    try {
      cert = File(certPath).readAsStringSync();
    } catch (error) {
      stderr.writeln('mTLS: Failed to load client certificate: $error');
    }
  }

  // Client key
  final keyPath = Platform.environment['NEOMCLAW_CLIENT_KEY'];
  if (keyPath != null && keyPath.isNotEmpty) {
    try {
      key = File(keyPath).readAsStringSync();
    } catch (error) {
      stderr.writeln('mTLS: Failed to load client key: $error');
    }
  }

  // Key passphrase
  final passphraseVal =
      Platform.environment['NEOMCLAW_CLIENT_KEY_PASSPHRASE'];
  if (passphraseVal != null && passphraseVal.isNotEmpty) {
    passphrase = passphraseVal;
  }

  if (cert == null && key == null && passphrase == null) {
    _mtlsConfigCache = null;
    return null;
  }

  _mtlsConfigCache = MTLSConfig(
    cert: cert,
    key: key,
    passphrase: passphrase,
  );
  return _mtlsConfigCache;
}

/// Create an HttpClient with mTLS configuration.
HttpClient? getMTLSHttpClient() {
  final mtlsConfig = getMTLSConfig();
  final caCerts = getCACertificates();

  if (mtlsConfig == null && caCerts == null) return null;

  // In Dart, SecurityContext is the equivalent of HTTPS agent options
  final context = SecurityContext(withTrustedRoots: true);

  if (mtlsConfig?.cert != null) {
    try {
      context.useCertificateChainBytes(utf8.encode(mtlsConfig!.cert!));
    } catch (e) {
      stderr.writeln('mTLS: Failed to set client certificate: $e');
    }
  }

  if (mtlsConfig?.key != null) {
    try {
      context.usePrivateKeyBytes(
        utf8.encode(mtlsConfig!.key!),
        password: mtlsConfig.passphrase,
      );
    } catch (e) {
      stderr.writeln('mTLS: Failed to set client key: $e');
    }
  }

  if (caCerts != null) {
    for (final cert in caCerts) {
      try {
        context.setTrustedCertificatesBytes(utf8.encode(cert));
      } catch (e) {
        stderr.writeln('mTLS: Failed to add CA certificate: $e');
      }
    }
  }

  return HttpClient(context: context);
}

/// Get TLS options for WebSocket connections.
SecurityContext? getWebSocketTLSContext() {
  final mtlsConfig = getMTLSConfig();
  final caCerts = getCACertificates();

  if (mtlsConfig == null && caCerts == null) return null;

  final context = SecurityContext(withTrustedRoots: true);

  if (mtlsConfig?.cert != null) {
    try {
      context.useCertificateChainBytes(utf8.encode(mtlsConfig!.cert!));
    } catch (_) {}
  }

  if (mtlsConfig?.key != null) {
    try {
      context.usePrivateKeyBytes(
        utf8.encode(mtlsConfig!.key!),
        password: mtlsConfig.passphrase,
      );
    } catch (_) {}
  }

  if (caCerts != null) {
    for (final cert in caCerts) {
      try {
        context.setTrustedCertificatesBytes(utf8.encode(cert));
      } catch (_) {}
    }
  }

  return context;
}

/// Get TLS configuration for fetch-like operations.
TLSConfig? getTLSConfig() {
  final mtlsConfig = getMTLSConfig();
  final caCerts = getCACertificates();

  if (mtlsConfig == null && caCerts == null) return null;

  return TLSConfig(
    cert: mtlsConfig?.cert,
    key: mtlsConfig?.key,
    passphrase: mtlsConfig?.passphrase,
    ca: caCerts,
  );
}

/// Clear the mTLS configuration cache.
void clearMTLSCache() {
  _mtlsConfigCache = null;
  _mtlsConfigCacheInitialized = false;
}

/// Configure global TLS settings.
void configureGlobalMTLS() {
  final mtlsConfig = getMTLSConfig();
  if (mtlsConfig == null) return;

  if (Platform.environment['NODE_EXTRA_CA_CERTS'] != null) {
    // Logged for debugging; in Dart, the system handles CA certs automatically
  }
}

// ---------------------------------------------------------------------------
// proxy.ts  --  Proxy configuration and management
// ---------------------------------------------------------------------------

/// Whether keep-alive has been disabled due to ECONNRESET.
bool _keepAliveDisabled = false;

/// Disable keep-alive globally (sticky for process lifetime).
void disableKeepAlive() {
  _keepAliveDisabled = true;
}

/// Reset keep-alive for testing.
void resetKeepAliveForTesting() {
  _keepAliveDisabled = false;
}

/// Whether keep-alive is currently disabled.
bool get isKeepAliveDisabled => _keepAliveDisabled;

/// Environment-like map type for dependency injection in tests.
typedef EnvLike = Map<String, String?>;

/// Get the active proxy URL if one is configured.
/// Prefers lowercase variants over uppercase.
String? getProxyUrl([EnvLike? env]) {
  final e = env ?? Platform.environment;
  return e['https_proxy'] ??
      e['HTTPS_PROXY'] ??
      e['http_proxy'] ??
      e['HTTP_PROXY'];
}

/// Get the NO_PROXY environment variable value.
String? getNoProxy([EnvLike? env]) {
  final e = env ?? Platform.environment;
  return e['no_proxy'] ?? e['NO_PROXY'];
}

/// Check if a URL should bypass the proxy based on NO_PROXY.
///
/// Supports:
/// - Exact hostname matches (e.g., "localhost")
/// - Domain suffix matches with leading dot (e.g., ".example.com")
/// - Wildcard "*" to bypass all
/// - Port-specific matches (e.g., "example.com:8080")
/// - IP addresses (e.g., "127.0.0.1")
bool shouldBypassProxy(String urlString, [String? noProxy]) {
  noProxy ??= getNoProxy();
  if (noProxy == null || noProxy.isEmpty) return false;

  // Handle wildcard
  if (noProxy == '*') return true;

  try {
    final uri = Uri.parse(urlString);
    final hostname = uri.host.toLowerCase();
    final port = uri.port != 0
        ? '${uri.port}'
        : (uri.scheme == 'https' || uri.scheme == 'wss' ? '443' : '80');
    final hostWithPort = '$hostname:$port';

    // Split by comma or space and trim
    final noProxyList = noProxy
        .split(RegExp(r'[,\s]+'))
        .where((s) => s.isNotEmpty)
        .toList();

    return noProxyList.any((pattern) {
      final p = pattern.toLowerCase().trim();

      // Port-specific match
      if (p.contains(':')) {
        return hostWithPort == p;
      }

      // Domain suffix match
      if (p.startsWith('.')) {
        return hostname == p.substring(1) || hostname.endsWith(p);
      }

      // Exact hostname match
      return hostname == p;
    });
  } catch (_) {
    return false;
  }
}

/// Convert DNS lookup options family to a numeric address family value.
int getAddressFamily(dynamic family) {
  if (family == null || family == 'IPv4') return 4;
  if (family == 0) return 0;
  if (family == 4) return 4;
  if (family == 6) return 6;
  if (family == 'IPv6') return 6;
  throw ArgumentError('Unsupported address family: $family');
}

/// Create an HttpClient with proxy configuration.
HttpClient createProxiedHttpClient({
  String? proxyUrl,
  SecurityContext? securityContext,
}) {
  final client = securityContext != null
      ? HttpClient(context: securityContext)
      : HttpClient();

  final proxy = proxyUrl ?? getProxyUrl();
  if (proxy != null && proxy.isNotEmpty) {
    client.findProxy = (uri) {
      if (shouldBypassProxy(uri.toString())) {
        return 'DIRECT';
      }
      final proxyUri = Uri.parse(proxy);
      return 'PROXY ${proxyUri.host}:${proxyUri.port}';
    };
  }

  return client;
}

/// Get an HTTP client for WebSocket proxy support.
/// Returns null if no proxy is configured or URL should bypass proxy.
HttpClient? getWebSocketProxyClient(String url) {
  final proxyUrl = getProxyUrl();
  if (proxyUrl == null) return null;
  if (shouldBypassProxy(url)) return null;
  return createProxiedHttpClient(proxyUrl: proxyUrl);
}

/// Get the proxy URL for WebSocket connections.
/// Returns null if no proxy or URL should bypass proxy.
String? getWebSocketProxyUrl(String url) {
  final proxyUrl = getProxyUrl();
  if (proxyUrl == null) return null;
  if (shouldBypassProxy(url)) return null;
  return proxyUrl;
}

/// Proxy fetch options (Dart equivalent of the TS getProxyFetchOptions).
class ProxyFetchOptions {
  const ProxyFetchOptions({
    this.tlsConfig,
    this.proxyUrl,
    this.unixSocket,
    this.keepAlive = true,
  });

  final TLSConfig? tlsConfig;
  final String? proxyUrl;
  final String? unixSocket;
  final bool keepAlive;
}

/// Get fetch options with proxy and mTLS configuration.
ProxyFetchOptions getProxyFetchOptions({bool forAnthropicAPI = false}) {
  final keepAlive = !_keepAliveDisabled;

  // ANTHROPIC_UNIX_SOCKET tunneling (for `neomclaw ssh`)
  if (forAnthropicAPI) {
    final unixSocket = Platform.environment['ANTHROPIC_UNIX_SOCKET'];
    if (unixSocket != null && unixSocket.isNotEmpty) {
      return ProxyFetchOptions(
        unixSocket: unixSocket,
        keepAlive: keepAlive,
      );
    }
  }

  final proxyUrl = getProxyUrl();

  if (proxyUrl != null) {
    return ProxyFetchOptions(
      proxyUrl: proxyUrl,
      tlsConfig: getTLSConfig(),
      keepAlive: keepAlive,
    );
  }

  return ProxyFetchOptions(
    tlsConfig: getTLSConfig(),
    keepAlive: keepAlive,
  );
}

/// Configure global HTTP agents for proxy and mTLS.
///
/// In the Dart port, this sets up the default HttpClient behavior.
/// Callers should use [createProxiedHttpClient] for specific instances.
void configureGlobalAgents() {
  final proxyUrl = getProxyUrl();
  final mtlsClient = getMTLSHttpClient();

  // In Dart, there's no global axios-like interceptor.
  // Configuration is applied per-client. This function is provided
  // for API compatibility and can be used to trigger cache rebuilds.
  if (proxyUrl != null) {
    // Proxy is configured - clients should use createProxiedHttpClient
  } else if (mtlsClient != null) {
    // mTLS without proxy - clients should use getMTLSHttpClient
  }
}

/// Clear proxy agent cache.
void clearProxyCache() {
  // In the Dart port, no memoized proxy agents to clear,
  // but we reset any cached state.
  _keepAliveDisabled = false;
}

// ---------------------------------------------------------------------------
// http.ts  --  HTTP utility functions
// ---------------------------------------------------------------------------

/// Get the user agent string for API requests.
String getUserAgent({
  required String version,
  String? userType,
  String? entrypoint,
  String? agentSdkVersion,
  String? clientApp,
  String? workload,
}) {
  final parts = <String>[];
  if (agentSdkVersion != null) parts.add('agent-sdk/$agentSdkVersion');
  if (clientApp != null) parts.add('client-app/$clientApp');
  if (workload != null) parts.add('workload/$workload');

  final suffix = parts.isNotEmpty ? ', ${parts.join(", ")}' : '';
  return 'neom-claw-cli/$version (${userType ?? "external"}, ${entrypoint ?? "cli"}$suffix)';
}

/// Get the MCP user agent string.
String getMCPUserAgent({
  required String version,
  String? entrypoint,
  String? agentSdkVersion,
  String? clientApp,
}) {
  final parts = <String>[];
  if (entrypoint != null) parts.add(entrypoint);
  if (agentSdkVersion != null) parts.add('agent-sdk/$agentSdkVersion');
  if (clientApp != null) parts.add('client-app/$clientApp');

  final suffix = parts.isNotEmpty ? ' (${parts.join(", ")})' : '';
  return 'neom-claw/$version$suffix';
}

/// Get the WebFetch user agent string.
String getWebFetchUserAgent({required String clawUserAgent}) {
  return 'NeomClaw-User ($clawUserAgent; +https://support.anthropic.com/)';
}

/// Authentication headers result.
class AuthHeaders {
  const AuthHeaders({
    required this.headers,
    this.error,
  });

  final Map<String, String> headers;
  final String? error;

  bool get hasError => error != null;
}

/// Get authentication headers for API requests.
///
/// [isSubscriber]: whether the user is a NeomClaw AI subscriber
/// [getOAuthAccessToken]: callback to get OAuth token
/// [getApiKey]: callback to get the API key
/// [oauthBetaHeader]: the beta header value for OAuth
AuthHeaders getAuthHeaders({
  required bool isSubscriber,
  String? Function()? getOAuthAccessToken,
  String? Function()? getApiKey,
  String oauthBetaHeader = '',
}) {
  if (isSubscriber) {
    final accessToken = getOAuthAccessToken?.call();
    if (accessToken == null || accessToken.isEmpty) {
      return const AuthHeaders(
        headers: {},
        error: 'No OAuth token available',
      );
    }
    return AuthHeaders(
      headers: {
        'Authorization': 'Bearer $accessToken',
        if (oauthBetaHeader.isNotEmpty) 'anthropic-beta': oauthBetaHeader,
      },
    );
  }

  final apiKey = getApiKey?.call();
  if (apiKey == null || apiKey.isEmpty) {
    return const AuthHeaders(
      headers: {},
      error: 'No API key available',
    );
  }
  return AuthHeaders(
    headers: {'x-api-key': apiKey},
  );
}

/// Wrapper that handles OAuth 401 errors by retrying once.
///
/// The [request] closure is called again on retry, so it should re-read auth
/// to pick up the refreshed token.
Future<T> withOAuth401Retry<T>({
  required Future<T> Function() request,
  required Future<void> Function(String failedAccessToken) handleOAuth401Error,
  required String? Function() getAccessToken,
  bool also403Revoked = false,
}) async {
  try {
    return await request();
  } on HttpException catch (e) {
    final statusCode = _extractStatusCode(e);
    final isAuthError = statusCode == 401 ||
        (also403Revoked &&
            statusCode == 403 &&
            e.message.contains('OAuth token has been revoked'));

    if (!isAuthError) rethrow;

    final failedAccessToken = getAccessToken();
    if (failedAccessToken == null) rethrow;

    await handleOAuth401Error(failedAccessToken);
    return await request();
  }
}

int? _extractStatusCode(HttpException e) {
  // HttpException in Dart doesn't have a status code directly.
  // In a real implementation, you'd use the HTTP client's response.
  // This is a simplified extraction attempt.
  final match = RegExp(r'(\d{3})').firstMatch(e.message);
  return match != null ? int.tryParse(match.group(1)!) : null;
}

/// Get AWS SDK client configuration with proxy support.
///
/// Returns a map of configuration that can be applied to AWS service clients.
/// In the Dart port, this returns proxy-related configuration.
Future<Map<String, dynamic>> getAWSClientProxyConfig() async {
  final proxyUrl = getProxyUrl();
  if (proxyUrl == null) return {};

  return {
    'proxyUrl': proxyUrl,
    'useProxy': true,
  };
}

// ---------------------------------------------------------------------------
// Comprehensive proxy configuration manager
// ---------------------------------------------------------------------------

/// Comprehensive proxy configuration holder.
class ProxyConfiguration {
  ProxyConfiguration({
    this.httpsProxy,
    this.httpProxy,
    this.noProxy,
    this.mtlsConfig,
    this.caCertificates,
    this.proxyResolvesHosts = false,
  });

  /// HTTPS proxy URL.
  final String? httpsProxy;

  /// HTTP proxy URL.
  final String? httpProxy;

  /// NO_PROXY comma-separated list.
  final String? noProxy;

  /// mTLS configuration for client certificates.
  final MTLSConfig? mtlsConfig;

  /// CA certificates for TLS verification.
  final List<String>? caCertificates;

  /// Whether the proxy should resolve hostnames (for sandbox environments).
  final bool proxyResolvesHosts;

  /// The effective proxy URL (prefers HTTPS over HTTP).
  String? get effectiveProxy => httpsProxy ?? httpProxy;

  /// Whether any proxy is configured.
  bool get hasProxy => effectiveProxy != null;

  /// Whether mTLS is configured.
  bool get hasMTLS => mtlsConfig != null && mtlsConfig!.isNotEmpty;

  /// Whether custom CA certificates are configured.
  bool get hasCustomCA => caCertificates != null && caCertificates!.isNotEmpty;

  /// Whether any TLS customization is present.
  bool get hasTLSCustomization => hasMTLS || hasCustomCA;

  /// Create from current environment.
  factory ProxyConfiguration.fromEnvironment([EnvLike? env]) {
    final e = env ?? Platform.environment;
    return ProxyConfiguration(
      httpsProxy: e['https_proxy'] ?? e['HTTPS_PROXY'],
      httpProxy: e['http_proxy'] ?? e['HTTP_PROXY'],
      noProxy: e['no_proxy'] ?? e['NO_PROXY'],
      mtlsConfig: getMTLSConfig(),
      caCertificates: getCACertificates(),
      proxyResolvesHosts: _isEnvTruthy(
        e['NEOMCLAW_PROXY_RESOLVES_HOSTS'],
      ),
    );
  }

  /// Check if a URL should bypass this proxy configuration.
  bool shouldBypass(String url) {
    return shouldBypassProxy(url, noProxy);
  }

  /// Create an HttpClient configured with this proxy setup.
  HttpClient createHttpClient() {
    SecurityContext? securityContext;

    if (hasTLSCustomization) {
      securityContext = SecurityContext(withTrustedRoots: true);

      if (mtlsConfig?.cert != null) {
        try {
          securityContext.useCertificateChainBytes(
            utf8.encode(mtlsConfig!.cert!),
          );
        } catch (e) {
          stderr.writeln('ProxyConfiguration: Failed to set client cert: $e');
        }
      }

      if (mtlsConfig?.key != null) {
        try {
          securityContext.usePrivateKeyBytes(
            utf8.encode(mtlsConfig!.key!),
            password: mtlsConfig!.passphrase,
          );
        } catch (e) {
          stderr.writeln('ProxyConfiguration: Failed to set client key: $e');
        }
      }

      if (caCertificates != null) {
        for (final cert in caCertificates!) {
          try {
            securityContext.setTrustedCertificatesBytes(utf8.encode(cert));
          } catch (e) {
            stderr.writeln('ProxyConfiguration: Failed to add CA cert: $e');
          }
        }
      }
    }

    final client = securityContext != null
        ? HttpClient(context: securityContext)
        : HttpClient();

    if (hasProxy) {
      final proxy = effectiveProxy!;
      client.findProxy = (uri) {
        if (shouldBypass(uri.toString())) {
          return 'DIRECT';
        }
        final proxyUri = Uri.parse(proxy);
        return 'PROXY ${proxyUri.host}:${proxyUri.port}';
      };
    }

    return client;
  }

  /// Returns a description of this configuration for debugging.
  String describe() {
    final parts = <String>[];
    if (hasProxy) parts.add('proxy=$effectiveProxy');
    if (noProxy != null) parts.add('noProxy=$noProxy');
    if (hasMTLS) parts.add('mTLS=enabled');
    if (hasCustomCA) parts.add('customCA=${caCertificates!.length} cert(s)');
    if (proxyResolvesHosts) parts.add('proxyResolvesHosts=true');
    return parts.isEmpty ? 'ProxyConfiguration(none)' : 'ProxyConfiguration(${parts.join(", ")})';
  }
}

/// Validates that the proxy URL is well-formed.
bool isValidProxyUrl(String url) {
  try {
    final uri = Uri.parse(url);
    return uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Parse a proxy URL into its components.
class ParsedProxyUrl {
  const ParsedProxyUrl({
    required this.scheme,
    required this.host,
    required this.port,
    this.username,
    this.password,
  });

  final String scheme;
  final String host;
  final int port;
  final String? username;
  final String? password;

  /// Whether this proxy requires authentication.
  bool get requiresAuth => username != null && username!.isNotEmpty;

  /// The full URL without credentials.
  String get urlWithoutCredentials => '$scheme://$host:$port';

  /// The full URL with credentials.
  String get urlWithCredentials {
    if (!requiresAuth) return urlWithoutCredentials;
    final encodedUser = Uri.encodeComponent(username!);
    final encodedPass =
        password != null ? ':${Uri.encodeComponent(password!)}' : '';
    return '$scheme://$encodedUser$encodedPass@$host:$port';
  }
}

/// Parse a proxy URL into structured components.
ParsedProxyUrl? parseProxyUrl(String url) {
  try {
    final uri = Uri.parse(url);
    if (!uri.hasScheme || uri.host.isEmpty) return null;
    return ParsedProxyUrl(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.port != 0
          ? uri.port
          : (uri.scheme == 'https' ? 443 : 80),
      username:
          uri.userInfo.contains(':') ? uri.userInfo.split(':').first : uri.userInfo.isNotEmpty ? uri.userInfo : null,
      password: uri.userInfo.contains(':')
          ? uri.userInfo.split(':').sublist(1).join(':')
          : null,
    );
  } catch (_) {
    return null;
  }
}

/// Check if a hostname matches a NO_PROXY pattern.
bool matchesNoProxyPattern(String hostname, String pattern) {
  final h = hostname.toLowerCase();
  final p = pattern.toLowerCase().trim();

  // Exact match
  if (h == p) return true;

  // Domain suffix with leading dot
  if (p.startsWith('.')) {
    return h == p.substring(1) || h.endsWith(p);
  }

  // Wildcard
  if (p == '*') return true;

  return false;
}

/// Parse NO_PROXY string into a list of patterns.
List<String> parseNoProxy(String? noProxy) {
  if (noProxy == null || noProxy.isEmpty) return [];
  return noProxy
      .split(RegExp(r'[,\s]+'))
      .where((s) => s.isNotEmpty)
      .map((s) => s.trim())
      .toList();
}

/// Check if a URL points to localhost.
bool isLocalhostUrl(String url) {
  try {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase();
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '[::1]' ||
        RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(host);
  } catch (_) {
    return false;
  }
}

/// Merge multiple NO_PROXY values (from different config sources).
String mergeNoProxy(List<String?> values) {
  final patterns = <String>{};
  for (final value in values) {
    if (value == null || value.isEmpty) continue;
    patterns.addAll(parseNoProxy(value));
  }
  return patterns.join(',');
}

/// Certificate PEM parser: extract individual certificates from a PEM bundle.
List<String> parsePemCertificates(String pemBundle) {
  final certs = <String>[];
  const beginMarker = '-----BEGIN CERTIFICATE-----';
  const endMarker = '-----END CERTIFICATE-----';

  var searchStart = 0;
  while (searchStart < pemBundle.length) {
    final beginIdx = pemBundle.indexOf(beginMarker, searchStart);
    if (beginIdx == -1) break;

    final endIdx = pemBundle.indexOf(endMarker, beginIdx);
    if (endIdx == -1) break;

    final certEnd = endIdx + endMarker.length;
    certs.add(pemBundle.substring(beginIdx, certEnd).trim());
    searchStart = certEnd;
  }

  return certs;
}

/// Validate that a string is a valid PEM certificate.
bool isValidPemCertificate(String pem) {
  final trimmed = pem.trim();
  return trimmed.startsWith('-----BEGIN CERTIFICATE-----') &&
      trimmed.endsWith('-----END CERTIFICATE-----');
}

/// Validate that a string is a valid PEM private key.
bool isValidPemPrivateKey(String pem) {
  final trimmed = pem.trim();
  return (trimmed.startsWith('-----BEGIN PRIVATE KEY-----') &&
          trimmed.endsWith('-----END PRIVATE KEY-----')) ||
      (trimmed.startsWith('-----BEGIN RSA PRIVATE KEY-----') &&
          trimmed.endsWith('-----END RSA PRIVATE KEY-----')) ||
      (trimmed.startsWith('-----BEGIN EC PRIVATE KEY-----') &&
          trimmed.endsWith('-----END EC PRIVATE KEY-----'));
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

bool _isEnvTruthy(String? envVar) {
  if (envVar == null || envVar.isEmpty) return false;
  final normalized = envVar.toLowerCase().trim();
  return const ['1', 'true', 'yes', 'on'].contains(normalized);
}
