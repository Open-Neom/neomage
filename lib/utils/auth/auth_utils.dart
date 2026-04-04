/// Authentication utilities ported from neom_claw/src/utils/auth.ts.
///
/// Token management, API key validation, credential storage, OAuth handling,
/// subscription checks, and cloud provider auth refresh flows.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Default TTL for API key helper cache in milliseconds (5 minutes).
const int defaultApiKeyHelperTtl = 5 * 60 * 1000;

/// Default STS credentials TTL - one hour.
const int defaultAwsStsTtl = 60 * 60 * 1000;

/// Default GCP credential TTL - 1 hour to match typical ADC token lifetime.
const int defaultGcpCredentialTtl = 60 * 60 * 1000;

/// Timeout for AWS auth refresh command (3 minutes).
const int awsAuthRefreshTimeoutMs = 3 * 60 * 1000;

/// Timeout for GCP auth refresh command (3 minutes).
const int gcpAuthRefreshTimeoutMs = 3 * 60 * 1000;

/// Short timeout for GCP credentials probe.
const int gcpCredentialsCheckTimeoutMs = 5000;

/// Default debounce for otel headers helper (29 minutes).
const int defaultOtelHeadersDebounceMs = 29 * 60 * 1000;

/// NeomClaw AI profile scope constant.
const String neomClawAiProfileScope = 'user:profile';

// ---------------------------------------------------------------------------
// Type definitions
// ---------------------------------------------------------------------------

/// Source of the API key.
enum ApiKeySource {
  anthropicApiKey('ANTHROPIC_API_KEY'),
  apiKeyHelper('apiKeyHelper'),
  loginManagedKey('/login managed key'),
  none('none');

  const ApiKeySource(this.label);
  final String label;
}

/// Source of the auth token.
enum AuthTokenSourceKind {
  anthropicAuthToken,
  neomClawOauthToken,
  neomClawOauthTokenFileDescriptor,
  ccrOauthTokenFile,
  apiKeyHelper,
  neomClawAi,
  none,
}

/// Result of [getAuthTokenSource].
class AuthTokenSourceResult {
  final AuthTokenSourceKind source;
  final bool hasToken;

  const AuthTokenSourceResult({required this.source, required this.hasToken});
}

/// Result of [getAnthropicApiKeyWithSource].
class ApiKeyWithSource {
  final String? key;
  final ApiKeySource source;

  const ApiKeyWithSource({required this.key, required this.source});
}

/// OAuth tokens representation.
class OAuthTokens {
  final String accessToken;
  final String? refreshToken;
  final int? expiresAt;
  final List<String> scopes;
  final String? subscriptionType;
  final String? rateLimitTier;

  const OAuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
    this.scopes = const ['user:inference'],
    this.subscriptionType,
    this.rateLimitTier,
  });

  OAuthTokens copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresAt,
    List<String>? scopes,
    String? subscriptionType,
    String? rateLimitTier,
  }) {
    return OAuthTokens(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      scopes: scopes ?? this.scopes,
      subscriptionType: subscriptionType ?? this.subscriptionType,
      rateLimitTier: rateLimitTier ?? this.rateLimitTier,
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt,
    'scopes': scopes,
    'subscriptionType': subscriptionType,
    'rateLimitTier': rateLimitTier,
  };

  factory OAuthTokens.fromJson(Map<String, dynamic> json) {
    return OAuthTokens(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String?,
      expiresAt: json['expiresAt'] as int?,
      scopes:
          (json['scopes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const ['user:inference'],
      subscriptionType: json['subscriptionType'] as String?,
      rateLimitTier: json['rateLimitTier'] as String?,
    );
  }
}

/// Subscription type enum matching OpenNeomClaw.
enum SubscriptionType { pro, max, team, enterprise }

/// Account information from OAuth profile.
class AccountInfo {
  final String accountUuid;
  final String emailAddress;
  final String? organizationUuid;
  final String? organizationName;
  final String? organizationRole;
  final String? workspaceRole;
  final String? displayName;
  final bool? hasExtraUsageEnabled;
  final String? billingType;
  final String? accountCreatedAt;
  final String? subscriptionCreatedAt;

  const AccountInfo({
    required this.accountUuid,
    required this.emailAddress,
    this.organizationUuid,
    this.organizationName,
    this.organizationRole,
    this.workspaceRole,
    this.displayName,
    this.hasExtraUsageEnabled,
    this.billingType,
    this.accountCreatedAt,
    this.subscriptionCreatedAt,
  });

  Map<String, dynamic> toJson() => {
    'accountUuid': accountUuid,
    'emailAddress': emailAddress,
    if (organizationUuid != null) 'organizationUuid': organizationUuid,
    if (organizationName != null) 'organizationName': organizationName,
    if (organizationRole != null) 'organizationRole': organizationRole,
    if (workspaceRole != null) 'workspaceRole': workspaceRole,
    if (displayName != null) 'displayName': displayName,
    if (hasExtraUsageEnabled != null)
      'hasExtraUsageEnabled': hasExtraUsageEnabled,
    if (billingType != null) 'billingType': billingType,
    if (accountCreatedAt != null) 'accountCreatedAt': accountCreatedAt,
    if (subscriptionCreatedAt != null)
      'subscriptionCreatedAt': subscriptionCreatedAt,
  };

  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    return AccountInfo(
      accountUuid: json['accountUuid'] as String,
      emailAddress: json['emailAddress'] as String,
      organizationUuid: json['organizationUuid'] as String?,
      organizationName: json['organizationName'] as String?,
      organizationRole: json['organizationRole'] as String?,
      workspaceRole: json['workspaceRole'] as String?,
      displayName: json['displayName'] as String?,
      hasExtraUsageEnabled: json['hasExtraUsageEnabled'] as bool?,
      billingType: json['billingType'] as String?,
      accountCreatedAt: json['accountCreatedAt'] as String?,
      subscriptionCreatedAt: json['subscriptionCreatedAt'] as String?,
    );
  }
}

/// User account info result.
class UserAccountInfo {
  final String? subscription;
  final String? tokenSource;
  final ApiKeySource? apiKeySource;
  final String? organization;
  final String? email;

  const UserAccountInfo({
    this.subscription,
    this.tokenSource,
    this.apiKeySource,
    this.organization,
    this.email,
  });
}

/// Org validation result.
class OrgValidationResult {
  final bool valid;
  final String? message;

  const OrgValidationResult.success() : valid = true, message = null;

  const OrgValidationResult.failure(String this.message) : valid = false;
}

// ---------------------------------------------------------------------------
// API Key Helper cache
// ---------------------------------------------------------------------------

/// Cache entry for the API key helper.
class _ApiKeyHelperCacheEntry {
  final String value;
  final int timestamp;

  _ApiKeyHelperCacheEntry({required this.value, required this.timestamp});
}

/// In-flight entry for the API key helper.
class _ApiKeyHelperInflight {
  final Future<String?> promise;
  final int? startedAt;

  _ApiKeyHelperInflight({required this.promise, this.startedAt});
}

_ApiKeyHelperCacheEntry? _apiKeyHelperCache;
_ApiKeyHelperInflight? _apiKeyHelperInflight;
int _apiKeyHelperEpoch = 0;

/// Returns how long the in-flight API key helper has been running.
int getApiKeyHelperElapsedMs() {
  final startedAt = _apiKeyHelperInflight?.startedAt;
  return startedAt != null
      ? DateTime.now().millisecondsSinceEpoch - startedAt
      : 0;
}

/// Clear the API key helper cache and bump epoch.
void clearApiKeyHelperCache() {
  _apiKeyHelperEpoch++;
  _apiKeyHelperCache = null;
  _apiKeyHelperInflight = null;
}

/// Sync cache reader for the API key helper.
String? getApiKeyFromApiKeyHelperCached() {
  return _apiKeyHelperCache?.value;
}

// ---------------------------------------------------------------------------
// Environment helpers
// ---------------------------------------------------------------------------

/// Check if an environment variable is truthy.
bool _isEnvTruthy(String? value) {
  if (value == null) return false;
  final lower = value.toLowerCase().trim();
  return lower == '1' || lower == 'true' || lower == 'yes';
}

/// Check if running in bare mode (no OAuth, no keychain).
bool isBareMode() {
  return _isEnvTruthy(Platform.environment['NEOMCLAW_BARE_MODE']);
}

/// Check if running on homespace.
bool isRunningOnHomespace() {
  return _isEnvTruthy(Platform.environment['NEOMCLAW_HOMESPACE']);
}

// ---------------------------------------------------------------------------
// Managed OAuth context
// ---------------------------------------------------------------------------

/// Whether we are in a managed OAuth context (CCR or NeomClaw Desktop).
bool isManagedOAuthContext() {
  return _isEnvTruthy(Platform.environment['NEOMCLAW_REMOTE']) ||
      Platform.environment['NEOMCLAW_ENTRYPOINT'] == 'claude-desktop';
}

// ---------------------------------------------------------------------------
// 3P service checks
// ---------------------------------------------------------------------------

/// Check if using third-party services (Bedrock, Vertex, Foundry, OpenAI, Gemini).
bool isUsing3PServices() {
  return _isEnvTruthy(Platform.environment['NEOMCLAW_USE_BEDROCK']) ||
      _isEnvTruthy(Platform.environment['NEOMCLAW_USE_VERTEX']) ||
      _isEnvTruthy(Platform.environment['NEOMCLAW_USE_FOUNDRY']) ||
      _isEnvTruthy(Platform.environment['NEOMCLAW_USE_OPENAI']) ||
      _isEnvTruthy(Platform.environment['NEOMCLAW_USE_GEMINI']);
}

// ---------------------------------------------------------------------------
// Anthropic auth enabled
// ---------------------------------------------------------------------------

/// Whether direct 1P auth (OAuth) is enabled.
bool isAnthropicAuthEnabled() {
  if (isBareMode()) return false;

  if (Platform.environment['ANTHROPIC_UNIX_SOCKET'] != null) {
    return Platform.environment['NEOMCLAW_OAUTH_TOKEN'] != null;
  }

  final is3P = isUsing3PServices();

  final hasExternalAuthToken =
      Platform.environment['ANTHROPIC_AUTH_TOKEN'] != null ||
      getConfiguredApiKeyHelper() != null ||
      Platform.environment['NEOMCLAW_API_KEY_FILE_DESCRIPTOR'] != null;

  final apiKeyResult = getAnthropicApiKeyWithSource(
    skipRetrievingKeyFromApiKeyHelper: true,
  );
  final hasExternalApiKey =
      apiKeyResult.source == ApiKeySource.anthropicApiKey ||
      apiKeyResult.source == ApiKeySource.apiKeyHelper;

  final shouldDisableAuth =
      is3P ||
      (hasExternalAuthToken && !isManagedOAuthContext()) ||
      (hasExternalApiKey && !isManagedOAuthContext());

  return !shouldDisableAuth;
}

// ---------------------------------------------------------------------------
// Auth token source
// ---------------------------------------------------------------------------

/// Determine where the auth token is sourced from.
AuthTokenSourceResult getAuthTokenSource() {
  if (isBareMode()) {
    if (getConfiguredApiKeyHelper() != null) {
      return const AuthTokenSourceResult(
        source: AuthTokenSourceKind.apiKeyHelper,
        hasToken: true,
      );
    }
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.none,
      hasToken: false,
    );
  }

  if (Platform.environment['ANTHROPIC_AUTH_TOKEN'] != null &&
      !isManagedOAuthContext()) {
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.anthropicAuthToken,
      hasToken: true,
    );
  }

  if (Platform.environment['NEOMCLAW_OAUTH_TOKEN'] != null) {
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.neomClawOauthToken,
      hasToken: true,
    );
  }

  final oauthTokenFromFd = getOAuthTokenFromFileDescriptor();
  if (oauthTokenFromFd != null) {
    if (Platform.environment['NEOMCLAW_OAUTH_TOKEN_FILE_DESCRIPTOR'] != null) {
      return const AuthTokenSourceResult(
        source: AuthTokenSourceKind.neomClawOauthTokenFileDescriptor,
        hasToken: true,
      );
    }
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.ccrOauthTokenFile,
      hasToken: true,
    );
  }

  final apiKeyHelper = getConfiguredApiKeyHelper();
  if (apiKeyHelper != null && !isManagedOAuthContext()) {
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.apiKeyHelper,
      hasToken: true,
    );
  }

  final oauthTokens = getNeomClawAIOAuthTokens();
  if (oauthTokens != null &&
      _shouldUseNeomClawAIAuth(oauthTokens.scopes) &&
      oauthTokens.accessToken.isNotEmpty) {
    return const AuthTokenSourceResult(
      source: AuthTokenSourceKind.neomClawAi,
      hasToken: true,
    );
  }

  return const AuthTokenSourceResult(
    source: AuthTokenSourceKind.none,
    hasToken: false,
  );
}

// ---------------------------------------------------------------------------
// API key retrieval
// ---------------------------------------------------------------------------

/// Get the Anthropic API key (convenience wrapper).
String? getAnthropicApiKey() {
  return getAnthropicApiKeyWithSource().key;
}

/// Check if there is Anthropic API key auth available.
bool hasAnthropicApiKeyAuth() {
  final result = getAnthropicApiKeyWithSource(
    skipRetrievingKeyFromApiKeyHelper: true,
  );
  return result.key != null && result.source != ApiKeySource.none;
}

/// Get the Anthropic API key along with its source.
ApiKeyWithSource getAnthropicApiKeyWithSource({
  bool skipRetrievingKeyFromApiKeyHelper = false,
}) {
  if (isBareMode()) {
    final envKey = Platform.environment['ANTHROPIC_API_KEY'];
    if (envKey != null) {
      return ApiKeyWithSource(
        key: envKey,
        source: ApiKeySource.anthropicApiKey,
      );
    }
    if (getConfiguredApiKeyHelper() != null) {
      return ApiKeyWithSource(
        key: skipRetrievingKeyFromApiKeyHelper
            ? null
            : getApiKeyFromApiKeyHelperCached(),
        source: ApiKeySource.apiKeyHelper,
      );
    }
    return const ApiKeyWithSource(key: null, source: ApiKeySource.none);
  }

  final apiKeyEnv = isRunningOnHomespace()
      ? null
      : Platform.environment['ANTHROPIC_API_KEY'];

  // Always check direct env var for non-interactive (--print) mode.
  if (apiKeyEnv != null &&
      _isEnvTruthy(Platform.environment['NEOMCLAW_PREFER_3P_AUTH'])) {
    return ApiKeyWithSource(
      key: apiKeyEnv,
      source: ApiKeySource.anthropicApiKey,
    );
  }

  // CI / test mode.
  if (_isEnvTruthy(Platform.environment['CI']) ||
      Platform.environment['NODE_ENV'] == 'test') {
    final apiKeyFromFd = getApiKeyFromFileDescriptor();
    if (apiKeyFromFd != null) {
      return ApiKeyWithSource(
        key: apiKeyFromFd,
        source: ApiKeySource.anthropicApiKey,
      );
    }
    if (apiKeyEnv != null) {
      return ApiKeyWithSource(
        key: apiKeyEnv,
        source: ApiKeySource.anthropicApiKey,
      );
    }
    return const ApiKeyWithSource(key: null, source: ApiKeySource.none);
  }

  // Check ANTHROPIC_API_KEY against approved list.
  if (apiKeyEnv != null) {
    // Simplified: in the full implementation this checks config approval list.
    return ApiKeyWithSource(
      key: apiKeyEnv,
      source: ApiKeySource.anthropicApiKey,
    );
  }

  // Check file descriptor.
  final apiKeyFromFd = getApiKeyFromFileDescriptor();
  if (apiKeyFromFd != null) {
    return ApiKeyWithSource(
      key: apiKeyFromFd,
      source: ApiKeySource.anthropicApiKey,
    );
  }

  // Check apiKeyHelper.
  final apiKeyHelperCommand = getConfiguredApiKeyHelper();
  if (apiKeyHelperCommand != null) {
    if (skipRetrievingKeyFromApiKeyHelper) {
      return const ApiKeyWithSource(
        key: null,
        source: ApiKeySource.apiKeyHelper,
      );
    }
    return ApiKeyWithSource(
      key: getApiKeyFromApiKeyHelperCached(),
      source: ApiKeySource.apiKeyHelper,
    );
  }

  // Check config or platform keychain.
  final fromConfig = getApiKeyFromConfigOrKeychain();
  if (fromConfig != null) {
    return fromConfig;
  }

  return const ApiKeyWithSource(key: null, source: ApiKeySource.none);
}

// ---------------------------------------------------------------------------
// Configured helper commands
// ---------------------------------------------------------------------------

/// Get the configured apiKeyHelper from settings.
String? getConfiguredApiKeyHelper() {
  // In a full implementation this reads from settings.
  return Platform.environment['NEOMCLAW_API_KEY_HELPER'];
}

/// Get the configured awsAuthRefresh from settings.
String? getConfiguredAwsAuthRefresh() {
  return Platform.environment['NEOMCLAW_AWS_AUTH_REFRESH'];
}

/// Get the configured awsCredentialExport from settings.
String? getConfiguredAwsCredentialExport() {
  return Platform.environment['NEOMCLAW_AWS_CREDENTIAL_EXPORT'];
}

/// Get the configured gcpAuthRefresh from settings.
String? getConfiguredGcpAuthRefresh() {
  return Platform.environment['NEOMCLAW_GCP_AUTH_REFRESH'];
}

/// Get the configured otelHeadersHelper from settings.
String? getConfiguredOtelHeadersHelper() {
  return Platform.environment['NEOMCLAW_OTEL_HEADERS_HELPER'];
}

// ---------------------------------------------------------------------------
// Project/local settings helper checks
// ---------------------------------------------------------------------------

/// Check if the apiKeyHelper comes from project or local settings.
bool isApiKeyHelperFromProjectOrLocalSettings() {
  // Simplified: in the full implementation this checks settings sources.
  return false;
}

/// Check if awsAuthRefresh comes from project settings.
bool isAwsAuthRefreshFromProjectSettings() {
  return false;
}

/// Check if awsCredentialExport comes from project settings.
bool isAwsCredentialExportFromProjectSettings() {
  return false;
}

/// Check if gcpAuthRefresh comes from project settings.
bool isGcpAuthRefreshFromProjectSettings() {
  return false;
}

/// Check if otelHeadersHelper comes from project or local settings.
bool isOtelHeadersHelperFromProjectOrLocalSettings() {
  return false;
}

// ---------------------------------------------------------------------------
// File descriptor helpers
// ---------------------------------------------------------------------------

/// Get API key from file descriptor.
String? getApiKeyFromFileDescriptor() {
  // Placeholder: in full implementation reads from FD.
  return null;
}

/// Get OAuth token from file descriptor.
String? getOAuthTokenFromFileDescriptor() {
  // Placeholder: in full implementation reads from FD.
  return null;
}

// ---------------------------------------------------------------------------
// Config or Keychain helpers
// ---------------------------------------------------------------------------

/// Get API key from config or platform keychain.
ApiKeyWithSource? getApiKeyFromConfigOrKeychain() {
  if (isBareMode()) return null;
  // Placeholder: in full implementation reads from platform keychain or config.
  return null;
}

// ---------------------------------------------------------------------------
// API key helper TTL
// ---------------------------------------------------------------------------

/// Calculate TTL in milliseconds for the API key helper cache.
int calculateApiKeyHelperTtl() {
  final envTtl = Platform.environment['NEOMCLAW_API_KEY_HELPER_TTL_MS'];
  if (envTtl != null) {
    final parsed = int.tryParse(envTtl);
    if (parsed != null && parsed >= 0) {
      return parsed;
    }
  }
  return defaultApiKeyHelperTtl;
}

// ---------------------------------------------------------------------------
// API key helper async execution
// ---------------------------------------------------------------------------

/// Async fetch of API key from the configured helper command.
Future<String?> getApiKeyFromApiKeyHelper(bool isNonInteractiveSession) async {
  if (getConfiguredApiKeyHelper() == null) return null;

  final ttl = calculateApiKeyHelperTtl();
  if (_apiKeyHelperCache != null) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _apiKeyHelperCache!.timestamp < ttl) {
      return _apiKeyHelperCache!.value;
    }
    // Stale: return stale value, refresh in background.
    _apiKeyHelperInflight ??= _ApiKeyHelperInflight(
      promise: _runAndCacheApiKeyHelper(
        isNonInteractiveSession,
        false,
        _apiKeyHelperEpoch,
      ),
      startedAt: null,
    );
    return _apiKeyHelperCache!.value;
  }

  // Cold cache: deduplicate concurrent calls.
  if (_apiKeyHelperInflight != null) return _apiKeyHelperInflight!.promise;
  _apiKeyHelperInflight = _ApiKeyHelperInflight(
    promise: _runAndCacheApiKeyHelper(
      isNonInteractiveSession,
      true,
      _apiKeyHelperEpoch,
    ),
    startedAt: DateTime.now().millisecondsSinceEpoch,
  );
  return _apiKeyHelperInflight!.promise;
}

Future<String?> _runAndCacheApiKeyHelper(
  bool isNonInteractiveSession,
  bool isCold,
  int epoch,
) async {
  try {
    final value = await _executeApiKeyHelper(isNonInteractiveSession);
    if (epoch != _apiKeyHelperEpoch) return value;
    if (value != null) {
      _apiKeyHelperCache = _ApiKeyHelperCacheEntry(
        value: value,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
    }
    return value;
  } catch (e) {
    if (epoch != _apiKeyHelperEpoch) return ' ';
    stderr.writeln('apiKeyHelper failed: $e');

    if (!isCold &&
        _apiKeyHelperCache != null &&
        _apiKeyHelperCache!.value != ' ') {
      _apiKeyHelperCache = _ApiKeyHelperCacheEntry(
        value: _apiKeyHelperCache!.value,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      return _apiKeyHelperCache!.value;
    }
    _apiKeyHelperCache = _ApiKeyHelperCacheEntry(
      value: ' ',
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    return ' ';
  } finally {
    if (epoch == _apiKeyHelperEpoch) {
      _apiKeyHelperInflight = null;
    }
  }
}

Future<String?> _executeApiKeyHelper(bool isNonInteractiveSession) async {
  final apiKeyHelper = getConfiguredApiKeyHelper();
  if (apiKeyHelper == null) return null;

  final result = await Process.run(
    Platform.isWindows ? 'cmd' : 'sh',
    Platform.isWindows ? ['/c', apiKeyHelper] : ['-c', apiKeyHelper],
  );

  if (result.exitCode != 0) {
    final why = 'exited ${result.exitCode}';
    final stderrStr = (result.stderr as String).trim();
    throw Exception(stderrStr.isNotEmpty ? '$why: $stderrStr' : why);
  }

  final stdout = (result.stdout as String).trim();
  if (stdout.isEmpty) {
    throw Exception('did not return a value');
  }
  return stdout;
}

/// Prefetch API key from helper if safe (trust already established).
void prefetchApiKeyFromApiKeyHelperIfSafe(bool isNonInteractiveSession) {
  if (isApiKeyHelperFromProjectOrLocalSettings()) {
    return;
  }
  getApiKeyFromApiKeyHelper(isNonInteractiveSession);
}

// ---------------------------------------------------------------------------
// API key validation and storage
// ---------------------------------------------------------------------------

/// Validate that an API key has the correct format.
bool isValidApiKey(String apiKey) {
  return RegExp(r'^[a-zA-Z0-9\-_]+$').hasMatch(apiKey);
}

/// Normalize an API key for config storage (truncated form).
String normalizeApiKeyForConfig(String apiKey) {
  if (apiKey.length <= 8) return apiKey;
  return '${apiKey.substring(0, 4)}...${apiKey.substring(apiKey.length - 4)}';
}

/// Save an API key to secure storage and config.
Future<void> saveApiKey(String apiKey) async {
  if (!isValidApiKey(apiKey)) {
    throw ArgumentError(
      'Invalid API key format. API key must contain only '
      'alphanumeric characters, dashes, and underscores.',
    );
  }
  // Placeholder: full implementation stores in platform keychain or config.
}

/// Check if a custom API key has been approved.
bool isCustomApiKeyApproved(String apiKey) {
  // Placeholder: checks global config approved list.
  return false;
}

/// Remove the stored API key.
Future<void> removeApiKey() async {
  // Placeholder: removes from keychain and config.
}

// ---------------------------------------------------------------------------
// OAuth tokens
// ---------------------------------------------------------------------------

bool _shouldUseNeomClawAIAuth(List<String>? scopes) {
  if (scopes == null) return false;
  return scopes.contains('user:inference');
}

OAuthTokens? _cachedOAuthTokens;

/// Get NeomClaw AI OAuth tokens (sync, memoized).
OAuthTokens? getNeomClawAIOAuthTokens() {
  if (isBareMode()) return null;

  if (Platform.environment['NEOMCLAW_OAUTH_TOKEN'] != null) {
    return OAuthTokens(
      accessToken: Platform.environment['NEOMCLAW_OAUTH_TOKEN']!,
      refreshToken: null,
      expiresAt: null,
      scopes: const ['user:inference'],
      subscriptionType: null,
      rateLimitTier: null,
    );
  }

  final oauthTokenFromFd = getOAuthTokenFromFileDescriptor();
  if (oauthTokenFromFd != null) {
    return OAuthTokens(
      accessToken: oauthTokenFromFd,
      refreshToken: null,
      expiresAt: null,
      scopes: const ['user:inference'],
      subscriptionType: null,
      rateLimitTier: null,
    );
  }

  // Return cached or read from secure storage.
  return _cachedOAuthTokens;
}

/// Clear OAuth token cache.
void clearOAuthTokenCache() {
  _cachedOAuthTokens = null;
}

/// Save OAuth tokens if needed.
({bool success, String? warning}) saveOAuthTokensIfNeeded(OAuthTokens tokens) {
  if (!_shouldUseNeomClawAIAuth(tokens.scopes)) {
    return (success: true, warning: null);
  }
  if (tokens.refreshToken == null || tokens.expiresAt == null) {
    return (success: true, warning: null);
  }
  // Placeholder: full implementation writes to secure storage.
  _cachedOAuthTokens = tokens;
  return (success: true, warning: null);
}

/// Async OAuth token reader.
Future<OAuthTokens?> getNeomClawAIOAuthTokensAsync() async {
  if (isBareMode()) return null;
  if (Platform.environment['NEOMCLAW_OAUTH_TOKEN'] != null ||
      getOAuthTokenFromFileDescriptor() != null) {
    return getNeomClawAIOAuthTokens();
  }
  // Placeholder: reads from secure storage async.
  return _cachedOAuthTokens;
}

// ---------------------------------------------------------------------------
// OAuth token refresh
// ---------------------------------------------------------------------------

Future<bool>? _pendingRefreshCheck;

/// Check and refresh OAuth token if expired.
Future<bool> checkAndRefreshOAuthTokenIfNeeded({
  int retryCount = 0,
  bool force = false,
}) async {
  if (retryCount == 0 && !force) {
    if (_pendingRefreshCheck != null) return _pendingRefreshCheck!;
    _pendingRefreshCheck = _checkAndRefreshOAuthTokenIfNeededImpl(
      retryCount,
      force,
    ).whenComplete(() => _pendingRefreshCheck = null);
    return _pendingRefreshCheck!;
  }
  return _checkAndRefreshOAuthTokenIfNeededImpl(retryCount, force);
}

Future<bool> _checkAndRefreshOAuthTokenIfNeededImpl(
  int retryCount,
  bool force,
) async {
  const maxRetries = 5;
  final tokens = getNeomClawAIOAuthTokens();
  if (!force) {
    if (tokens?.refreshToken == null ||
        !_isOAuthTokenExpired(tokens?.expiresAt)) {
      return false;
    }
  }
  if (tokens?.refreshToken == null) return false;
  if (!_shouldUseNeomClawAIAuth(tokens?.scopes)) return false;

  // Re-read tokens to check if still expired.
  clearOAuthTokenCache();
  final freshTokens = await getNeomClawAIOAuthTokensAsync();
  if (freshTokens?.refreshToken == null ||
      !_isOAuthTokenExpired(freshTokens?.expiresAt)) {
    return false;
  }

  // Placeholder: in full implementation acquires lock, refreshes token,
  // and saves. Retries up to maxRetries on lock contention.
  if (retryCount >= maxRetries) return false;

  return false;
}

bool _isOAuthTokenExpired(int? expiresAt) {
  if (expiresAt == null) return false;
  return DateTime.now().millisecondsSinceEpoch >= expiresAt;
}

/// Handle a 401 OAuth error.
Future<bool> handleOAuth401Error(String failedAccessToken) async {
  clearOAuthTokenCache();
  final currentTokens = await getNeomClawAIOAuthTokensAsync();
  if (currentTokens?.refreshToken == null) return false;
  if (currentTokens!.accessToken != failedAccessToken) return true;
  return checkAndRefreshOAuthTokenIfNeeded(force: true);
}

// ---------------------------------------------------------------------------
// Subscription checks
// ---------------------------------------------------------------------------

/// Whether the current user is a NeomClaw AI subscriber.
bool isNeomClawAISubscriber() {
  if (!isAnthropicAuthEnabled()) return false;
  final tokens = getNeomClawAIOAuthTokens();
  return _shouldUseNeomClawAIAuth(tokens?.scopes);
}

/// Check if OAuth token has the user:profile scope.
bool hasProfileScope() {
  return getNeomClawAIOAuthTokens()?.scopes.contains(neomClawAiProfileScope) ??
      false;
}

/// Whether the user is a 1P API customer (not subscriber, not 3P).
bool is1PApiCustomer() {
  if (isUsing3PServices()) return false;
  if (isNeomClawAISubscriber()) return false;
  return true;
}

/// Get the current subscription type.
SubscriptionType? getSubscriptionType() {
  if (!isAnthropicAuthEnabled()) return null;
  final oauthTokens = getNeomClawAIOAuthTokens();
  if (oauthTokens == null) return null;
  return _parseSubscriptionType(oauthTokens.subscriptionType);
}

SubscriptionType? _parseSubscriptionType(String? raw) {
  if (raw == null) return null;
  switch (raw) {
    case 'pro':
      return SubscriptionType.pro;
    case 'max':
      return SubscriptionType.max;
    case 'team':
      return SubscriptionType.team;
    case 'enterprise':
      return SubscriptionType.enterprise;
    default:
      return null;
  }
}

/// Whether the user is a Max subscriber.
bool isMaxSubscriber() => getSubscriptionType() == SubscriptionType.max;

/// Whether the user is a Team subscriber.
bool isTeamSubscriber() => getSubscriptionType() == SubscriptionType.team;

/// Whether the user is an Enterprise subscriber.
bool isEnterpriseSubscriber() =>
    getSubscriptionType() == SubscriptionType.enterprise;

/// Whether the user is a Pro subscriber.
bool isProSubscriber() => getSubscriptionType() == SubscriptionType.pro;

/// Whether the user is a Team Premium subscriber.
bool isTeamPremiumSubscriber() {
  return getSubscriptionType() == SubscriptionType.team &&
      getRateLimitTier() == 'default_neomclaw_max_5x';
}

/// Get the rate limit tier.
String? getRateLimitTier() {
  if (!isAnthropicAuthEnabled()) return null;
  return getNeomClawAIOAuthTokens()?.rateLimitTier;
}

/// Get a human-readable subscription name.
String getSubscriptionName() {
  switch (getSubscriptionType()) {
    case SubscriptionType.enterprise:
      return 'NeomClaw Enterprise';
    case SubscriptionType.team:
      return 'NeomClaw Team';
    case SubscriptionType.max:
      return 'NeomClaw Max';
    case SubscriptionType.pro:
      return 'NeomClaw Pro';
    default:
      return 'NeomClaw API';
  }
}

/// Whether the user has Opus access.
bool hasOpusAccess() {
  final subscriptionType = getSubscriptionType();
  return subscriptionType == SubscriptionType.max ||
      subscriptionType == SubscriptionType.enterprise ||
      subscriptionType == SubscriptionType.team ||
      subscriptionType == SubscriptionType.pro ||
      subscriptionType == null;
}

/// Check if the user is a consumer subscriber (pro or max).
bool isConsumerSubscriber() {
  final subType = getSubscriptionType();
  return isNeomClawAISubscriber() &&
      subType != null &&
      (subType == SubscriptionType.max || subType == SubscriptionType.pro);
}

/// Check if overage provisioning is allowed.
bool isOverageProvisioningAllowed() {
  if (!isNeomClawAISubscriber()) return false;
  // Placeholder: full implementation checks billingType from account info.
  return false;
}

// ---------------------------------------------------------------------------
// Account information
// ---------------------------------------------------------------------------

/// Get OAuth account info (only for 1P Anthropic API).
AccountInfo? getOauthAccountInfo() {
  return isAnthropicAuthEnabled() ? _storedAccountInfo : null;
}

AccountInfo? _storedAccountInfo;

/// Get account information for display.
UserAccountInfo? getAccountInformation() {
  final authResult = getAuthTokenSource();
  final accountInfo = UserAccountInfo(tokenSource: authResult.source.name);

  if (isNeomClawAISubscriber()) {
    return UserAccountInfo(
      subscription: getSubscriptionName(),
      tokenSource: authResult.source.name,
      organization: getOauthAccountInfo()?.organizationName,
      email: getOauthAccountInfo()?.emailAddress,
    );
  }

  return accountInfo;
}

// ---------------------------------------------------------------------------
// AWS credentials
// ---------------------------------------------------------------------------

({String accessKeyId, String secretAccessKey, String sessionToken})?
_awsCredentialsCache;
DateTime? _awsCredentialsCacheTime;

/// Refresh and get AWS credentials with caching.
Future<({String accessKeyId, String secretAccessKey, String sessionToken})?>
refreshAndGetAwsCredentials() async {
  if (_awsCredentialsCache != null && _awsCredentialsCacheTime != null) {
    final elapsed = DateTime.now().difference(_awsCredentialsCacheTime!);
    if (elapsed.inMilliseconds < defaultAwsStsTtl) {
      return _awsCredentialsCache;
    }
  }

  final _refreshed = await _runAwsAuthRefresh();
  final credentials = await _getAwsCredsFromCredentialExport();

  if (credentials != null) {
    _awsCredentialsCache = credentials;
    _awsCredentialsCacheTime = DateTime.now();
  }

  return credentials;
}

/// Clear AWS credentials cache.
void clearAwsCredentialsCache() {
  _awsCredentialsCache = null;
  _awsCredentialsCacheTime = null;
}

Future<bool> _runAwsAuthRefresh() async {
  final awsAuthRefresh = getConfiguredAwsAuthRefresh();
  if (awsAuthRefresh == null) return false;
  // Placeholder: in full implementation runs the command.
  return false;
}

Future<({String accessKeyId, String secretAccessKey, String sessionToken})?>
_getAwsCredsFromCredentialExport() async {
  final command = getConfiguredAwsCredentialExport();
  if (command == null) return null;
  // Placeholder: in full implementation runs the command and parses JSON.
  return null;
}

/// Refresh AWS auth (exposed for direct use).
Future<bool> refreshAwsAuth(String awsAuthRefresh) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows ? ['/c', awsAuthRefresh] : ['-c', awsAuthRefresh],
    );
    return result.exitCode == 0;
  } catch (e) {
    stderr.writeln('Error running awsAuthRefresh: $e');
    return false;
  }
}

/// Prefetch AWS credentials if safe (trust already established).
void prefetchAwsCredentialsAndBedrockInfoIfSafe() {
  final awsAuthRefresh = getConfiguredAwsAuthRefresh();
  final awsCredentialExport = getConfiguredAwsCredentialExport();
  if (awsAuthRefresh == null && awsCredentialExport == null) return;

  if (isAwsAuthRefreshFromProjectSettings() ||
      isAwsCredentialExportFromProjectSettings()) {
    return;
  }
  refreshAndGetAwsCredentials();
}

// ---------------------------------------------------------------------------
// GCP credentials
// ---------------------------------------------------------------------------

bool? _gcpCredentialsRefreshed;
DateTime? _gcpCredentialsCacheTime;

/// Refresh GCP credentials if needed.
Future<bool> refreshGcpCredentialsIfNeeded() async {
  if (_gcpCredentialsRefreshed != null && _gcpCredentialsCacheTime != null) {
    final elapsed = DateTime.now().difference(_gcpCredentialsCacheTime!);
    if (elapsed.inMilliseconds < defaultGcpCredentialTtl) {
      return _gcpCredentialsRefreshed!;
    }
  }

  final refreshed = await _runGcpAuthRefresh();
  _gcpCredentialsRefreshed = refreshed;
  _gcpCredentialsCacheTime = DateTime.now();
  return refreshed;
}

/// Clear GCP credentials cache.
void clearGcpCredentialsCache() {
  _gcpCredentialsRefreshed = null;
  _gcpCredentialsCacheTime = null;
}

Future<bool> _runGcpAuthRefresh() async {
  final gcpAuthRefresh = getConfiguredGcpAuthRefresh();
  if (gcpAuthRefresh == null) return false;
  // Placeholder: check credentials validity first, then refresh if needed.
  return false;
}

/// Refresh GCP auth (exposed for direct use).
Future<bool> refreshGcpAuth(String gcpAuthRefresh) async {
  try {
    final result = await Process.run(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows ? ['/c', gcpAuthRefresh] : ['-c', gcpAuthRefresh],
    );
    return result.exitCode == 0;
  } catch (e) {
    stderr.writeln('Error running gcpAuthRefresh: $e');
    return false;
  }
}

/// Prefetch GCP credentials if safe.
void prefetchGcpCredentialsIfSafe() {
  final gcpAuthRefresh = getConfiguredGcpAuthRefresh();
  if (gcpAuthRefresh == null) return;
  if (isGcpAuthRefreshFromProjectSettings()) return;
  refreshGcpCredentialsIfNeeded();
}

// ---------------------------------------------------------------------------
// OTel headers
// ---------------------------------------------------------------------------

Map<String, String>? _cachedOtelHeaders;
int _cachedOtelHeadersTimestamp = 0;

/// Get OTel headers from the configured helper.
Map<String, String> getOtelHeadersFromHelper() {
  final otelHeadersHelper = getConfiguredOtelHeadersHelper();
  if (otelHeadersHelper == null) return {};

  final debounceMs =
      int.tryParse(
        Platform.environment['NEOMCLAW_OTEL_HEADERS_HELPER_DEBOUNCE_MS'] ?? '',
      ) ??
      defaultOtelHeadersDebounceMs;

  if (_cachedOtelHeaders != null &&
      DateTime.now().millisecondsSinceEpoch - _cachedOtelHeadersTimestamp <
          debounceMs) {
    return _cachedOtelHeaders!;
  }

  if (isOtelHeadersHelperFromProjectOrLocalSettings()) {
    return {};
  }

  try {
    final result = Process.runSync(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows
          ? ['/c', otelHeadersHelper]
          : ['-c', otelHeadersHelper],
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) {
      throw Exception('otelHeadersHelper did not return a valid value');
    }

    final headers = json.decode(output);
    if (headers is! Map<String, dynamic>) {
      throw Exception(
        'otelHeadersHelper must return a JSON object with string key-value pairs',
      );
    }

    final validated = <String, String>{};
    for (final entry in headers.entries) {
      if (entry.value is! String) {
        throw Exception(
          'otelHeadersHelper returned non-string value for key "${entry.key}"',
        );
      }
      validated[entry.key] = entry.value as String;
    }

    _cachedOtelHeaders = validated;
    _cachedOtelHeadersTimestamp = DateTime.now().millisecondsSinceEpoch;
    return validated;
  } catch (e) {
    rethrow;
  }
}

// ---------------------------------------------------------------------------
// Org validation
// ---------------------------------------------------------------------------

/// Validate that the active OAuth token belongs to the required org.
Future<OrgValidationResult> validateForceLoginOrg() async {
  if (Platform.environment['ANTHROPIC_UNIX_SOCKET'] != null) {
    return const OrgValidationResult.success();
  }
  if (!isAnthropicAuthEnabled()) {
    return const OrgValidationResult.success();
  }
  // Placeholder: full implementation checks forceLoginOrgUUID from policy settings.
  return const OrgValidationResult.success();
}
