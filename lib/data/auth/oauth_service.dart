// OAuth service — ported from NeomClaw src/services/oauth/.
// PKCE authorization code flow for Anthropic's OAuth endpoints.

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

/// OAuth configuration for Anthropic endpoints.
class OAuthConfig {
  final String authorizeUrl;
  final String tokenUrl;
  final String clientId;
  final String redirectUrl;
  final List<String> scopes;

  const OAuthConfig({
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.redirectUrl,
    required this.scopes,
  });

  /// Production NeomClaw.ai OAuth config.
  static const OAuthConfig neomClawAi = OAuthConfig(
    authorizeUrl: 'https://neomclaw.com/cai/oauth/authorize',
    tokenUrl: 'https://platform.neomclaw.com/v1/oauth/token',
    clientId: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
    redirectUrl: 'https://platform.neomclaw.com/oauth/code/callback',
    scopes: [
      'user:profile',
      'user:inference',
      'user:sessions:neomclaw',
      'user:mcp_servers',
      'user:file_upload',
    ],
  );

  /// Production Console OAuth config.
  static const OAuthConfig console = OAuthConfig(
    authorizeUrl: 'https://platform.neomclaw.com/oauth/authorize',
    tokenUrl: 'https://platform.neomclaw.com/v1/oauth/token',
    clientId: '9d1c250a-e61b-44d9-88ed-5944d1962f5e',
    redirectUrl: 'https://platform.neomclaw.com/oauth/code/callback',
    scopes: ['org:create_api_key', 'user:profile'],
  );
}

/// OAuth tokens with expiration metadata.
class OAuthTokens {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final List<String> scopes;
  final String? subscriptionType;
  final String? rateLimitTier;

  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
    this.subscriptionType,
    this.rateLimitTier,
  });

  /// Check if token is expired (with 5-minute buffer).
  bool get isExpired {
    final buffer = const Duration(minutes: 5);
    return DateTime.now().add(buffer).isAfter(expiresAt);
  }
}

/// PKCE (Proof Key for Code Exchange) utilities.
class Pkce {
  /// Generate a random code verifier (43+ chars, base64url-encoded).
  static String generateCodeVerifier() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return _base64UrlEncode(bytes);
  }

  /// Generate code challenge from verifier (SHA256 hash, base64url-encoded).
  static String generateCodeChallenge(String verifier) {
    final hash = sha256.convert(utf8.encode(verifier));
    return _base64UrlEncode(hash.bytes);
  }

  /// Generate CSRF state parameter.
  static String generateState() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return _base64UrlEncode(bytes);
  }

  static String _base64UrlEncode(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

/// OAuth client for Anthropic authorization flows.
class OAuthClient {
  final OAuthConfig config;
  final http.Client _httpClient;

  OAuthClient({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Build the authorization URL for browser redirect.
  Uri buildAuthUrl({
    required String codeChallenge,
    required String state,
    String? redirectUri,
    String? orgUuid,
    String? loginHint,
  }) {
    return Uri.parse(config.authorizeUrl).replace(
      queryParameters: {
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': redirectUri ?? config.redirectUrl,
        'scope': config.scopes.join(' '),
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
        if (orgUuid case final uuid?) 'org_uuid': uuid,
        if (loginHint case final hint?) 'login_hint': hint,
      },
    );
  }

  /// Exchange authorization code for tokens.
  Future<OAuthTokens> exchangeCode({
    required String code,
    required String codeVerifier,
    required String state,
    String? redirectUri,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(config.tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': redirectUri ?? config.redirectUrl,
        'client_id': config.clientId,
        'code_verifier': codeVerifier,
        'state': state,
      },
    );

    if (response.statusCode != 200) {
      throw OAuthException(
        'Token exchange failed (${response.statusCode}): ${response.body}',
      );
    }

    return _parseTokenResponse(response.body);
  }

  /// Refresh an expired access token.
  Future<OAuthTokens> refreshToken({
    required String refreshToken,
    List<String>? scopes,
  }) async {
    final response = await _httpClient.post(
      Uri.parse(config.tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': config.clientId,
        'scope': (scopes ?? config.scopes).join(' '),
      },
    );

    if (response.statusCode != 200) {
      throw OAuthException(
        'Token refresh failed (${response.statusCode}): ${response.body}',
      );
    }

    return _parseTokenResponse(response.body);
  }

  OAuthTokens _parseTokenResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;

    final expiresIn = json['expires_in'] as int? ?? 3600;
    final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
    final scopeStr = json['scope'] as String? ?? '';

    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresAt: expiresAt,
      scopes: scopeStr.split(' ').where((s) => s.isNotEmpty).toList(),
      subscriptionType: json['subscription_type'] as String?,
      rateLimitTier: json['rate_limit_tier'] as String?,
    );
  }

  void dispose() => _httpClient.close();
}

/// OAuth-specific exception.
class OAuthException implements Exception {
  final String message;
  const OAuthException(this.message);

  @override
  String toString() => 'OAuthException: $message';
}
