// OAuth service — faithful port of openneomclaw/src/services/oauth/.
// Covers: client.ts, index.ts (OAuthService class), auth-code-listener.ts,
//         getOauthProfile.ts, crypto.ts, types.ts.
//
// All classes, methods, types, and validation logic are ported.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:crypto/crypto.dart';

// ---------------------------------------------------------------------------
// OAuth types (types.ts)
// ---------------------------------------------------------------------------

/// Subscription type for OAuth accounts.
enum SubscriptionType { max, pro, enterprise, team }

/// Billing type for OAuth accounts.
enum BillingType { stripe, aws }

/// Rate limit tier information.
class RateLimitTier {
  final String name;
  final int? requestsPerMinute;
  final int? tokensPerMinute;

  const RateLimitTier({
    required this.name,
    this.requestsPerMinute,
    this.tokensPerMinute,
  });

  factory RateLimitTier.fromJson(Map<String, dynamic> json) {
    return RateLimitTier(
      name: json['name'] as String? ?? '',
      requestsPerMinute: json['requests_per_minute'] as int?,
      tokensPerMinute: json['tokens_per_minute'] as int?,
    );
  }
}

/// OAuth token exchange response from the token endpoint.
class OAuthTokenExchangeResponse {
  final String accessToken;
  final String refreshToken;
  final int expiresIn;
  final String? scope;
  final OAuthTokenAccount? account;
  final OAuthTokenOrganization? organization;

  const OAuthTokenExchangeResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    this.scope,
    this.account,
    this.organization,
  });

  factory OAuthTokenExchangeResponse.fromJson(Map<String, dynamic> json) {
    return OAuthTokenExchangeResponse(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String,
      expiresIn: json['expires_in'] as int,
      scope: json['scope'] as String?,
      account: json['account'] != null
          ? OAuthTokenAccount.fromJson(
              json['account'] as Map<String, dynamic>)
          : null,
      organization: json['organization'] != null
          ? OAuthTokenOrganization.fromJson(
              json['organization'] as Map<String, dynamic>)
          : null,
    );
  }
}

/// Account info from token exchange.
class OAuthTokenAccount {
  final String uuid;
  final String emailAddress;

  const OAuthTokenAccount({
    required this.uuid,
    required this.emailAddress,
  });

  factory OAuthTokenAccount.fromJson(Map<String, dynamic> json) {
    return OAuthTokenAccount(
      uuid: json['uuid'] as String,
      emailAddress: json['email_address'] as String,
    );
  }
}

/// Organization info from token exchange.
class OAuthTokenOrganization {
  final String? uuid;

  const OAuthTokenOrganization({this.uuid});

  factory OAuthTokenOrganization.fromJson(Map<String, dynamic> json) {
    return OAuthTokenOrganization(uuid: json['uuid'] as String?);
  }
}

/// Full OAuth tokens (client-side representation).
class OAuthTokens {
  final String accessToken;
  final String refreshToken;
  final int expiresAt; // milliseconds since epoch
  final List<String> scopes;
  final SubscriptionType? subscriptionType;
  final RateLimitTier? rateLimitTier;
  final OAuthProfileResponse? profile;
  final OAuthTokenAccountInfo? tokenAccount;

  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.scopes = const [],
    this.subscriptionType,
    this.rateLimitTier,
    this.profile,
    this.tokenAccount,
  });
}

/// Account info stored alongside tokens.
class OAuthTokenAccountInfo {
  final String uuid;
  final String emailAddress;
  final String? organizationUuid;

  const OAuthTokenAccountInfo({
    required this.uuid,
    required this.emailAddress,
    this.organizationUuid,
  });
}

/// User roles response from the roles endpoint.
class UserRolesResponse {
  final String? organizationRole;
  final String? workspaceRole;
  final String? organizationName;

  const UserRolesResponse({
    this.organizationRole,
    this.workspaceRole,
    this.organizationName,
  });

  factory UserRolesResponse.fromJson(Map<String, dynamic> json) {
    return UserRolesResponse(
      organizationRole: json['organization_role'] as String?,
      workspaceRole: json['workspace_role'] as String?,
      organizationName: json['organization_name'] as String?,
    );
  }
}

/// Profile response from the OAuth profile endpoint.
class OAuthProfileResponse {
  final OAuthProfileAccount account;
  final OAuthProfileOrganization organization;

  const OAuthProfileResponse({
    required this.account,
    required this.organization,
  });

  factory OAuthProfileResponse.fromJson(Map<String, dynamic> json) {
    return OAuthProfileResponse(
      account: OAuthProfileAccount.fromJson(
          json['account'] as Map<String, dynamic>),
      organization: OAuthProfileOrganization.fromJson(
          json['organization'] as Map<String, dynamic>),
    );
  }
}

/// Account details in the profile response.
class OAuthProfileAccount {
  final String uuid;
  final String email;
  final String? displayName;
  final String? createdAt;

  const OAuthProfileAccount({
    required this.uuid,
    required this.email,
    this.displayName,
    this.createdAt,
  });

  factory OAuthProfileAccount.fromJson(Map<String, dynamic> json) {
    return OAuthProfileAccount(
      uuid: json['uuid'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}

/// Organization details in the profile response.
class OAuthProfileOrganization {
  final String uuid;
  final String? organizationType;
  final RateLimitTier? rateLimitTier;
  final bool? hasExtraUsageEnabled;
  final String? billingType;
  final String? subscriptionCreatedAt;

  const OAuthProfileOrganization({
    required this.uuid,
    this.organizationType,
    this.rateLimitTier,
    this.hasExtraUsageEnabled,
    this.billingType,
    this.subscriptionCreatedAt,
  });

  factory OAuthProfileOrganization.fromJson(Map<String, dynamic> json) {
    return OAuthProfileOrganization(
      uuid: json['uuid'] as String,
      organizationType: json['organization_type'] as String?,
      rateLimitTier: json['rate_limit_tier'] != null
          ? RateLimitTier.fromJson(
              json['rate_limit_tier'] as Map<String, dynamic>)
          : null,
      hasExtraUsageEnabled: json['has_extra_usage_enabled'] as bool?,
      billingType: json['billing_type'] as String?,
      subscriptionCreatedAt: json['subscription_created_at'] as String?,
    );
  }
}

/// Account info persisted in global config.
class AccountInfo {
  final String accountUuid;
  final String emailAddress;
  final String? organizationUuid;
  final String? displayName;
  final bool? hasExtraUsageEnabled;
  final String? billingType;
  final String? accountCreatedAt;
  final String? subscriptionCreatedAt;
  final String? organizationRole;
  final String? workspaceRole;
  final String? organizationName;

  const AccountInfo({
    required this.accountUuid,
    required this.emailAddress,
    this.organizationUuid,
    this.displayName,
    this.hasExtraUsageEnabled,
    this.billingType,
    this.accountCreatedAt,
    this.subscriptionCreatedAt,
    this.organizationRole,
    this.workspaceRole,
    this.organizationName,
  });
}

// ---------------------------------------------------------------------------
// OAuth configuration
// ---------------------------------------------------------------------------

/// OAuth configuration URLs and client IDs.
class OAuthConfig {
  final String clientId;
  final String consoleAuthorizeUrl;
  final String neomClawAiAuthorizeUrl;
  final String tokenUrl;
  final String rolesUrl;
  final String apiKeyUrl;
  final String manualRedirectUrl;
  final String consoleSuccessUrl;
  final String neomClawAiSuccessUrl;
  final String profileUrl;

  const OAuthConfig({
    required this.clientId,
    required this.consoleAuthorizeUrl,
    required this.neomClawAiAuthorizeUrl,
    required this.tokenUrl,
    required this.rolesUrl,
    required this.apiKeyUrl,
    required this.manualRedirectUrl,
    required this.consoleSuccessUrl,
    required this.neomClawAiSuccessUrl,
    required this.profileUrl,
  });
}

/// Default OAuth config (can be overridden).
OAuthConfig _oauthConfig = const OAuthConfig(
  clientId: 'neom-claw',
  consoleAuthorizeUrl: 'https://console.anthropic.com/oauth/authorize',
  neomClawAiAuthorizeUrl: 'https://neomclaw.ai/oauth/authorize',
  tokenUrl: 'https://console.anthropic.com/v1/oauth/token',
  rolesUrl: 'https://api.anthropic.com/v1/oauth/roles',
  apiKeyUrl: 'https://api.anthropic.com/v1/oauth/api-key',
  manualRedirectUrl: 'https://console.anthropic.com/oauth/code',
  consoleSuccessUrl: 'https://console.anthropic.com/oauth/success',
  neomClawAiSuccessUrl: 'https://neomclaw.ai/oauth/success',
  profileUrl: 'https://api.anthropic.com/v1/oauth/profile',
);

OAuthConfig getOauthConfig() => _oauthConfig;

void setOauthConfig(OAuthConfig config) {
  _oauthConfig = config;
}

/// NeomClaw AI inference scope.
const neomClawAiInferenceScope = 'claude:inference';

/// All OAuth scopes.
const allOAuthScopes = [
  'user:profile',
  'user:inference',
  'org:create_api_key',
  neomClawAiInferenceScope,
];

/// NeomClaw AI OAuth scopes.
const neomClawAiOAuthScopes = [
  'user:profile',
  'user:inference',
  neomClawAiInferenceScope,
];

// ---------------------------------------------------------------------------
// PKCE crypto helpers (crypto.ts)
// ---------------------------------------------------------------------------

/// Generate a random code verifier for PKCE.
String generateCodeVerifier() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// Generate the code challenge from the verifier (S256).
String generateCodeChallenge(String codeVerifier) {
  final digest = sha256.convert(utf8.encode(codeVerifier));
  return base64Url.encode(digest.bytes).replaceAll('=', '');
}

/// Generate a random state parameter for CSRF protection.
String generateState() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

// ---------------------------------------------------------------------------
// OAuth client functions (client.ts)
// ---------------------------------------------------------------------------

/// Check if the user has NeomClaw.ai authentication scope.
bool shouldUseNeomClawAIAuth(List<String>? scopes) {
  return scopes?.contains(neomClawAiInferenceScope) ?? false;
}

/// Parse a space-separated scope string into a list.
List<String> parseScopes(String? scopeString) {
  return scopeString?.split(' ').where((s) => s.isNotEmpty).toList() ?? [];
}

/// Build the OAuth authorization URL.
String buildAuthUrl({
  required String codeChallenge,
  required String state,
  required int port,
  required bool isManual,
  bool loginWithNeomClawAi = false,
  bool inferenceOnly = false,
  String? orgUUID,
  String? loginHint,
  String? loginMethod,
}) {
  final config = getOauthConfig();
  final authUrlBase = loginWithNeomClawAi
      ? config.neomClawAiAuthorizeUrl
      : config.consoleAuthorizeUrl;

  final uri = Uri.parse(authUrlBase);
  final params = <String, String>{
    'code': 'true',
    'client_id': config.clientId,
    'response_type': 'code',
    'redirect_uri': isManual
        ? config.manualRedirectUrl
        : 'http://localhost:$port/callback',
    'scope': (inferenceOnly ? [neomClawAiInferenceScope] : allOAuthScopes)
        .join(' '),
    'code_challenge': codeChallenge,
    'code_challenge_method': 'S256',
    'state': state,
  };

  if (orgUUID != null) params['orgUUID'] = orgUUID;
  if (loginHint != null) params['login_hint'] = loginHint;
  if (loginMethod != null) params['login_method'] = loginMethod;

  return uri.replace(queryParameters: params).toString();
}

/// Exchange authorization code for tokens.
Future<OAuthTokenExchangeResponse> exchangeCodeForTokens({
  required String authorizationCode,
  required String state,
  required String codeVerifier,
  required int port,
  bool useManualRedirect = false,
  int? expiresIn,
  HttpClient? httpClient,
}) async {
  final config = getOauthConfig();
  final body = <String, dynamic>{
    'grant_type': 'authorization_code',
    'code': authorizationCode,
    'redirect_uri': useManualRedirect
        ? config.manualRedirectUrl
        : 'http://localhost:$port/callback',
    'client_id': config.clientId,
    'code_verifier': codeVerifier,
    'state': state,
  };

  if (expiresIn != null) body['expires_in'] = expiresIn;

  final client = httpClient ?? HttpClient();
  try {
    final request =
        await client.postUrl(Uri.parse(config.tokenUrl));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    final responseBody =
        await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception(
        response.statusCode == 401
            ? 'Authentication failed: Invalid authorization code'
            : 'Token exchange failed (${response.statusCode}): $responseBody',
      );
    }

    return OAuthTokenExchangeResponse.fromJson(
      jsonDecode(responseBody) as Map<String, dynamic>,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

/// Refresh an OAuth token.
Future<OAuthTokens> refreshOAuthToken({
  required String refreshToken,
  List<String>? requestedScopes,
  HttpClient? httpClient,
}) async {
  final config = getOauthConfig();
  final body = {
    'grant_type': 'refresh_token',
    'refresh_token': refreshToken,
    'client_id': config.clientId,
    'scope':
        (requestedScopes?.isNotEmpty == true
                ? requestedScopes!
                : neomClawAiOAuthScopes)
            .join(' '),
  };

  final client = httpClient ?? HttpClient();
  try {
    final request =
        await client.postUrl(Uri.parse(config.tokenUrl));
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    final responseBody =
        await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw Exception('Token refresh failed: $responseBody');
    }

    final data = OAuthTokenExchangeResponse.fromJson(
      jsonDecode(responseBody) as Map<String, dynamic>,
    );

    final expiresAt =
        DateTime.now().millisecondsSinceEpoch + data.expiresIn * 1000;
    final scopes = parseScopes(data.scope);

    return OAuthTokens(
      accessToken: data.accessToken,
      refreshToken: data.refreshToken,
      expiresAt: expiresAt,
      scopes: scopes,
      tokenAccount: data.account != null
          ? OAuthTokenAccountInfo(
              uuid: data.account!.uuid,
              emailAddress: data.account!.emailAddress,
              organizationUuid: data.organization?.uuid,
            )
          : null,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

/// Fetch profile info from the OAuth profile endpoint.
Future<OAuthProfileResponse?> fetchOAuthProfile({
  required String accessToken,
  HttpClient? httpClient,
}) async {
  final config = getOauthConfig();
  final client = httpClient ?? HttpClient();
  try {
    final request =
        await client.getUrl(Uri.parse(config.profileUrl));
    request.headers.set('Authorization', 'Bearer $accessToken');
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) return null;

    final responseBody =
        await response.transform(utf8.decoder).join();
    return OAuthProfileResponse.fromJson(
      jsonDecode(responseBody) as Map<String, dynamic>,
    );
  } catch (_) {
    return null;
  } finally {
    if (httpClient == null) client.close();
  }
}

/// Determine subscription type from organization type string.
SubscriptionType? subscriptionTypeFromOrgType(String? orgType) {
  switch (orgType) {
    case 'neomclaw_max':
      return SubscriptionType.max;
    case 'neomclaw_pro':
      return SubscriptionType.pro;
    case 'neomclaw_enterprise':
      return SubscriptionType.enterprise;
    case 'neomclaw_team':
      return SubscriptionType.team;
    default:
      return null;
  }
}

/// Fetch profile info and extract subscription details.
Future<({
  SubscriptionType? subscriptionType,
  String? displayName,
  RateLimitTier? rateLimitTier,
  bool? hasExtraUsageEnabled,
  String? billingType,
  String? accountCreatedAt,
  String? subscriptionCreatedAt,
  OAuthProfileResponse? rawProfile,
})?> fetchProfileInfo({
  required String accessToken,
  HttpClient? httpClient,
}) async {
  final profile = await fetchOAuthProfile(
    accessToken: accessToken,
    httpClient: httpClient,
  );
  if (profile == null) return null;

  final orgType = profile.organization.organizationType;
  final subscriptionType = subscriptionTypeFromOrgType(orgType);

  return (
    subscriptionType: subscriptionType,
    displayName: profile.account.displayName,
    rateLimitTier: profile.organization.rateLimitTier,
    hasExtraUsageEnabled: profile.organization.hasExtraUsageEnabled,
    billingType: profile.organization.billingType,
    accountCreatedAt: profile.account.createdAt,
    subscriptionCreatedAt: profile.organization.subscriptionCreatedAt,
    rawProfile: profile,
  );
}

/// Check if an OAuth token is expired (with 5 minute buffer).
bool isOAuthTokenExpired(int? expiresAt) {
  if (expiresAt == null) return false;
  const bufferTime = 5 * 60 * 1000; // 5 minutes in ms
  final now = DateTime.now().millisecondsSinceEpoch;
  return (now + bufferTime) >= expiresAt;
}

/// Fetch and store user roles.
Future<UserRolesResponse> fetchUserRoles({
  required String accessToken,
  HttpClient? httpClient,
}) async {
  final config = getOauthConfig();
  final client = httpClient ?? HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(config.rolesUrl));
    request.headers.set('Authorization', 'Bearer $accessToken');
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    if (response.statusCode != 200) {
      throw Exception(
          'Failed to fetch user roles: ${response.statusCode}');
    }

    final responseBody =
        await response.transform(utf8.decoder).join();
    return UserRolesResponse.fromJson(
      jsonDecode(responseBody) as Map<String, dynamic>,
    );
  } finally {
    if (httpClient == null) client.close();
  }
}

/// Create and store an API key.
Future<String?> createApiKey({
  required String accessToken,
  HttpClient? httpClient,
}) async {
  final config = getOauthConfig();
  final client = httpClient ?? HttpClient();
  try {
    final request =
        await client.postUrl(Uri.parse(config.apiKeyUrl));
    request.headers.set('Authorization', 'Bearer $accessToken');
    request.headers.contentLength = 0;
    final response = await request.close().timeout(
          const Duration(seconds: 15),
        );

    final responseBody =
        await response.transform(utf8.decoder).join();
    final data = jsonDecode(responseBody) as Map<String, dynamic>;
    return data['raw_key'] as String?;
  } finally {
    if (httpClient == null) client.close();
  }
}

// ---------------------------------------------------------------------------
// Auth code listener (auth-code-listener.ts)
// ---------------------------------------------------------------------------

/// Temporary localhost HTTP server that listens for OAuth authorization code
/// redirects.
class AuthCodeListener {
  HttpServer? _server;
  int _port = 0;
  Completer<String>? _codeCompleter;
  String? _expectedState;
  HttpResponse? _pendingResponse;
  final String _callbackPath;

  AuthCodeListener({String callbackPath = '/callback'})
      : _callbackPath = callbackPath;

  /// Start listening on an OS-assigned port and return the port number.
  Future<int> start({int? port}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port ?? 0);
    _port = _server!.port;
    return _port;
  }

  int get serverPort => _port;

  bool get hasPendingResponse => _pendingResponse != null;

  /// Wait for an authorization code redirect.
  Future<String> waitForAuthorization(
    String state,
    Future<void> Function() onReady,
  ) async {
    _expectedState = state;
    _codeCompleter = Completer<String>();

    // Start listening for requests
    _server!.listen(_handleRequest);

    // Server is ready — call onReady
    await onReady();

    return _codeCompleter!.future;
  }

  void _handleRequest(HttpRequest request) {
    final path = request.uri.path;
    if (path != _callbackPath) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
      return;
    }

    final authCode = request.uri.queryParameters['code'];
    final state = request.uri.queryParameters['state'];

    if (authCode == null || authCode.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Authorization code not found');
      request.response.close();
      _codeCompleter?.completeError(
          Exception('No authorization code received'));
      return;
    }

    if (state != _expectedState) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Invalid state parameter');
      request.response.close();
      _codeCompleter?.completeError(
          Exception('Invalid state parameter'));
      return;
    }

    // Store the response for later redirect
    _pendingResponse = request.response;
    _codeCompleter?.complete(authCode);
  }

  /// Redirect the user's browser to a success page.
  void handleSuccessRedirect(List<String> scopes) {
    if (_pendingResponse == null) return;

    final config = getOauthConfig();
    final successUrl = shouldUseNeomClawAIAuth(scopes)
        ? config.neomClawAiSuccessUrl
        : config.consoleSuccessUrl;

    _pendingResponse!.statusCode = HttpStatus.movedTemporarily;
    _pendingResponse!.headers.set('Location', successUrl);
    _pendingResponse!.close();
    _pendingResponse = null;
  }

  /// Handle error by sending a redirect.
  void handleErrorRedirect() {
    if (_pendingResponse == null) return;

    final config = getOauthConfig();
    _pendingResponse!.statusCode = HttpStatus.movedTemporarily;
    _pendingResponse!.headers.set('Location', config.neomClawAiSuccessUrl);
    _pendingResponse!.close();
    _pendingResponse = null;
  }

  /// Close the server and clean up.
  void close() {
    if (_pendingResponse != null) {
      handleErrorRedirect();
    }
    _server?.close(force: true);
    _server = null;
  }
}

// ---------------------------------------------------------------------------
// OAuthService — main OAuth 2.0 PKCE flow (index.ts)
// ---------------------------------------------------------------------------

/// OAuth service that handles the OAuth 2.0 authorization code flow with PKCE.
///
/// Supports two ways to get authorization codes:
/// 1. Automatic: Opens browser, redirects to localhost where we capture the code
/// 2. Manual: User manually copies and pastes the code
class OAuthService {
  String _codeVerifier;
  AuthCodeListener? _authCodeListener;
  int? _port;
  Completer<String>? _manualAuthCodeCompleter;

  OAuthService() : _codeVerifier = generateCodeVerifier();

  /// Start the OAuth flow.
  Future<OAuthTokens> startOAuthFlow({
    required Future<void> Function(String manualUrl, [String? automaticUrl])
        authURLHandler,
    Future<void> Function(String url)? openBrowser,
    bool loginWithNeomClawAi = false,
    bool inferenceOnly = false,
    int? expiresIn,
    String? orgUUID,
    String? loginHint,
    String? loginMethod,
    bool skipBrowserOpen = false,
  }) async {
    _authCodeListener = AuthCodeListener();
    _port = await _authCodeListener!.start();

    final codeChallenge = generateCodeChallenge(_codeVerifier);
    final state = generateState();

    final commonOpts = (
      codeChallenge: codeChallenge,
      state: state,
      port: _port!,
      loginWithNeomClawAi: loginWithNeomClawAi,
      inferenceOnly: inferenceOnly,
      orgUUID: orgUUID,
      loginHint: loginHint,
      loginMethod: loginMethod,
    );

    final manualFlowUrl = buildAuthUrl(
      codeChallenge: commonOpts.codeChallenge,
      state: commonOpts.state,
      port: commonOpts.port,
      isManual: true,
      loginWithNeomClawAi: commonOpts.loginWithNeomClawAi,
      inferenceOnly: commonOpts.inferenceOnly,
      orgUUID: commonOpts.orgUUID,
      loginHint: commonOpts.loginHint,
      loginMethod: commonOpts.loginMethod,
    );

    final automaticFlowUrl = buildAuthUrl(
      codeChallenge: commonOpts.codeChallenge,
      state: commonOpts.state,
      port: commonOpts.port,
      isManual: false,
      loginWithNeomClawAi: commonOpts.loginWithNeomClawAi,
      inferenceOnly: commonOpts.inferenceOnly,
      orgUUID: commonOpts.orgUUID,
      loginHint: commonOpts.loginHint,
      loginMethod: commonOpts.loginMethod,
    );

    // Wait for either automatic or manual auth code
    final authorizationCode = await _waitForAuthorizationCode(
      state,
      () async {
        if (skipBrowserOpen) {
          await authURLHandler(manualFlowUrl, automaticFlowUrl);
        } else {
          await authURLHandler(manualFlowUrl);
          if (openBrowser != null) await openBrowser(automaticFlowUrl);
        }
      },
    );

    final isAutomaticFlow = _authCodeListener?.hasPendingResponse ?? false;

    try {
      final tokenResponse = await exchangeCodeForTokens(
        authorizationCode: authorizationCode,
        state: state,
        codeVerifier: _codeVerifier,
        port: _port!,
        useManualRedirect: !isAutomaticFlow,
        expiresIn: expiresIn,
      );

      final profileInfo = await fetchProfileInfo(
        accessToken: tokenResponse.accessToken,
      );

      if (isAutomaticFlow) {
        final scopes = parseScopes(tokenResponse.scope);
        _authCodeListener?.handleSuccessRedirect(scopes);
      }

      return _formatTokens(
        tokenResponse,
        profileInfo?.subscriptionType,
        profileInfo?.rateLimitTier,
        profileInfo?.rawProfile,
      );
    } catch (error) {
      if (isAutomaticFlow) {
        _authCodeListener?.handleErrorRedirect();
      }
      rethrow;
    } finally {
      _authCodeListener?.close();
    }
  }

  Future<String> _waitForAuthorizationCode(
    String state,
    Future<void> Function() onReady,
  ) async {
    _manualAuthCodeCompleter = Completer<String>();

    // Start automatic flow
    final automaticFuture =
        _authCodeListener!.waitForAuthorization(state, onReady);

    // Return whichever completes first
    return Future.any([
      automaticFuture,
      _manualAuthCodeCompleter!.future,
    ]);
  }

  /// Handle manual flow callback when user pastes the auth code.
  void handleManualAuthCodeInput({
    required String authorizationCode,
    required String state,
  }) {
    if (_manualAuthCodeCompleter != null &&
        !_manualAuthCodeCompleter!.isCompleted) {
      _manualAuthCodeCompleter!.complete(authorizationCode);
      _authCodeListener?.close();
    }
  }

  OAuthTokens _formatTokens(
    OAuthTokenExchangeResponse response,
    SubscriptionType? subscriptionType,
    RateLimitTier? rateLimitTier,
    OAuthProfileResponse? profile,
  ) {
    return OAuthTokens(
      accessToken: response.accessToken,
      refreshToken: response.refreshToken,
      expiresAt: DateTime.now().millisecondsSinceEpoch +
          response.expiresIn * 1000,
      scopes: parseScopes(response.scope),
      subscriptionType: subscriptionType,
      rateLimitTier: rateLimitTier,
      profile: profile,
      tokenAccount: response.account != null
          ? OAuthTokenAccountInfo(
              uuid: response.account!.uuid,
              emailAddress: response.account!.emailAddress,
              organizationUuid: response.organization?.uuid,
            )
          : null,
    );
  }

  /// Clean up any resources.
  void cleanup() {
    _authCodeListener?.close();
    _manualAuthCodeCompleter = null;
  }
}
