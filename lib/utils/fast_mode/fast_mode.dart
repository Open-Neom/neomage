// Fast mode — port of neom_claw/src/utils/fastMode.ts.
// Fast mode configuration, availability checks, runtime state management,
// cooldown handling, org-level status prefetch, and overage rejection.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ─── Types ───────────────────────────────────────────────────────────────────

/// Auth types for fast mode.
enum AuthType { oauth, apiKey }

/// Reason why fast mode was disabled by the API.
enum FastModeDisabledReason {
  free,
  preference,
  extraUsageDisabled,
  networkError,
  unknown,
}

/// Reason for entering cooldown.
enum CooldownReason { rateLimit, overloaded }

/// Fast mode runtime state.
sealed class FastModeRuntimeState {
  const FastModeRuntimeState();
}

/// Fast mode is active and available.
class FastModeActive extends FastModeRuntimeState {
  const FastModeActive();
}

/// Fast mode is in cooldown after a rate limit or overload.
class FastModeCooldown extends FastModeRuntimeState {
  final int resetAt;
  final CooldownReason reason;

  const FastModeCooldown({required this.resetAt, required this.reason});
}

/// Org-level fast mode status from the API.
sealed class FastModeOrgStatus {
  const FastModeOrgStatus();
}

/// Status is pending (not yet fetched from API).
class FastModeOrgPending extends FastModeOrgStatus {
  const FastModeOrgPending();
}

/// Fast mode is enabled at the org level.
class FastModeOrgEnabled extends FastModeOrgStatus {
  const FastModeOrgEnabled();
}

/// Fast mode is disabled at the org level.
class FastModeOrgDisabled extends FastModeOrgStatus {
  final FastModeDisabledReason reason;

  const FastModeOrgDisabled({required this.reason});
}

/// Fast mode overall state.
enum FastModeState { off, cooldown, on }

/// Response from the fast mode API endpoint.
class FastModeResponse {
  final bool enabled;
  final FastModeDisabledReason? disabledReason;

  const FastModeResponse({required this.enabled, this.disabledReason});

  factory FastModeResponse.fromJson(Map<String, dynamic> json) {
    FastModeDisabledReason? reason;
    final reasonStr = json['disabled_reason'] as String?;
    if (reasonStr != null) {
      reason = _parseDisabledReason(reasonStr);
    }
    return FastModeResponse(
      enabled: json['enabled'] as bool,
      disabledReason: reason,
    );
  }
}

/// Model setting type alias.
typedef ModelSetting = String?;

// ─── Signal pattern ──────────────────────────────────────────────────────────

/// Simple signal/event emitter pattern (port of createSignal from signal.ts).
class Signal<T> {
  final List<void Function(T)> _listeners = [];

  void Function() subscribe(void Function(T) listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void emit(T value) {
    for (final listener in List.of(_listeners)) {
      listener(value);
    }
  }
}

/// Void signal (no payload).
class VoidSignal {
  final List<void Function()> _listeners = [];

  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void emit() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

// ─── Configuration callbacks ─────────────────────────────────────────────────

/// Configuration for the fast mode manager. Provides hooks to external
/// systems (auth, settings, config) without hard dependencies.
class FastModeConfig {
  /// Get the current API provider name.
  final String Function() getApiProvider;

  /// Check if the environment variable is truthy.
  final bool Function(String name) isEnvTruthy;

  /// Check if running in bundled/native mode.
  final bool Function() isInBundledMode;

  /// Check if this is a non-interactive session.
  final bool Function() isNonInteractiveSession;

  /// Check if Kairos is active.
  final bool Function() isKairosActive;

  /// Check if the user prefers third-party authentication.
  final bool Function() preferThirdPartyAuth;

  /// Get a cached feature value from remote config.
  final T Function<T>(String key, T defaultValue) getFeatureValue;

  /// Get the fast mode setting from flag settings.
  final bool? Function() getFlagFastMode;

  /// Get the default main loop model setting.
  final String Function() getDefaultMainLoopModel;

  /// Parse a user-specified model string.
  final String Function(String model) parseUserSpecifiedModel;

  /// Get initial settings.
  final Map<String, dynamic> Function() getInitialSettings;

  /// Get settings for a specific source.
  final Map<String, dynamic>? Function(String source) getSettingsForSource;

  /// Update settings for a specific source.
  final void Function(String source, Map<String, dynamic> updates)
  updateSettingsForSource;

  /// Get global config value.
  final Map<String, dynamic> Function() getGlobalConfig;

  /// Save global config.
  final void Function(
    Map<String, dynamic> Function(Map<String, dynamic> current),
  )
  saveGlobalConfig;

  /// Get OAuth tokens.
  final Map<String, String>? Function() getOAuthTokens;

  /// Get the Anthropic API key.
  final String? Function() getApiKey;

  /// Check if the user has profile scope.
  final bool Function() hasProfileScope;

  /// Handle OAuth 401 error.
  final Future<void> Function(String accessToken) handleOAuth401Error;

  /// Get the OAuth base API URL.
  final String Function() getBaseApiUrl;

  /// Get the OAuth beta header.
  final String Function() getOAuthBetaHeader;

  /// Check if essential traffic only mode is active.
  final bool Function() isEssentialTrafficOnly;

  /// Get the user type from environment.
  final String? Function() getUserType;

  /// Check if Opus 1M merge is enabled.
  final bool Function() isOpus1mMergeEnabled;

  const FastModeConfig({
    required this.getApiProvider,
    required this.isEnvTruthy,
    required this.isInBundledMode,
    required this.isNonInteractiveSession,
    required this.isKairosActive,
    required this.preferThirdPartyAuth,
    required this.getFeatureValue,
    required this.getFlagFastMode,
    required this.getDefaultMainLoopModel,
    required this.parseUserSpecifiedModel,
    required this.getInitialSettings,
    required this.getSettingsForSource,
    required this.updateSettingsForSource,
    required this.getGlobalConfig,
    required this.saveGlobalConfig,
    required this.getOAuthTokens,
    required this.getApiKey,
    required this.hasProfileScope,
    required this.handleOAuth401Error,
    required this.getBaseApiUrl,
    required this.getOAuthBetaHeader,
    required this.isEssentialTrafficOnly,
    required this.getUserType,
    required this.isOpus1mMergeEnabled,
  });
}

// ─── Fast mode manager ───────────────────────────────────────────────────────

/// Manages fast mode state, availability, cooldown, and org-level status.
class FastModeManager {
  final FastModeConfig _config;

  FastModeRuntimeState _runtimeState = const FastModeActive();
  bool _hasLoggedCooldownExpiry = false;
  FastModeOrgStatus _orgStatus = const FastModeOrgPending();
  int _lastPrefetchAt = 0;
  Future<void>? _inflightPrefetch;

  /// Display name for the fast mode model.
  static const String fastModeModelDisplay = 'Opus 4.6';

  /// Minimum interval between prefetch calls.
  static const int prefetchMinIntervalMs = 30000;

  // Signals
  final Signal<({int resetAt, CooldownReason reason})> cooldownTriggered =
      Signal();
  final VoidSignal cooldownExpired = VoidSignal();
  final Signal<bool> orgFastModeChanged = Signal();
  final Signal<String> overageRejection = Signal();

  FastModeManager(this._config);

  /// Check if fast mode is enabled (not disabled by environment).
  bool get isFastModeEnabled {
    if (_config.getApiProvider() != 'firstParty') return false;
    return !_config.isEnvTruthy('NEOMCLAW_DISABLE_FAST_MODE');
  }

  /// Check if fast mode is available (enabled + no blocking reason).
  bool get isFastModeAvailable {
    if (!isFastModeEnabled) return false;
    return fastModeUnavailableReason == null;
  }

  /// Get the model string for fast mode.
  String get fastModeModel {
    return 'opus${_config.isOpus1mMergeEnabled() ? '[1m]' : ''}';
  }

  /// Get the reason fast mode is unavailable, or null if it's available.
  String? get fastModeUnavailableReason {
    if (_config.getApiProvider() != 'firstParty') {
      return 'Fast mode is not available on third-party providers';
    }

    if (!isFastModeEnabled) {
      return 'Fast mode is not available';
    }

    // Check remote config killswitch.
    final statsigReason = _config.getFeatureValue<String?>(
      'tengu_penguins_off',
      null,
    );
    if (statsigReason != null) {
      return statsigReason;
    }

    // Previously, fast mode required the native binary. Keep behind a flag.
    if (!_config.isInBundledMode() &&
        _config.getFeatureValue<bool>('tengu_marble_sandcastle', false)) {
      return 'Fast mode requires the native binary';
    }

    // Not available in the SDK unless explicitly opted in.
    if (_config.isNonInteractiveSession() &&
        _config.preferThirdPartyAuth() &&
        !_config.isKairosActive()) {
      final flagFastMode = _config.getFlagFastMode();
      if (flagFastMode != true) {
        return 'Fast mode is not available in the Agent SDK';
      }
    }

    // Check org-level status.
    if (_orgStatus is FastModeOrgDisabled) {
      final disabled = _orgStatus as FastModeOrgDisabled;
      if (disabled.reason == FastModeDisabledReason.networkError ||
          disabled.reason == FastModeDisabledReason.unknown) {
        if (_config.isEnvTruthy('NEOMCLAW_SKIP_FAST_MODE_NETWORK_ERRORS')) {
          return null;
        }
      }
      final oauthTokens = _config.getOAuthTokens();
      final authType = oauthTokens != null ? AuthType.oauth : AuthType.apiKey;
      return _getDisabledReasonMessage(disabled.reason, authType);
    }

    return null;
  }

  /// Get a human-readable message for a disabled reason.
  String _getDisabledReasonMessage(
    FastModeDisabledReason reason,
    AuthType authType,
  ) {
    switch (reason) {
      case FastModeDisabledReason.free:
        return authType == AuthType.oauth
            ? 'Fast mode requires a paid subscription'
            : 'Fast mode unavailable during evaluation. Please purchase credits.';
      case FastModeDisabledReason.preference:
        return 'Fast mode has been disabled by your organization';
      case FastModeDisabledReason.extraUsageDisabled:
        return 'Fast mode requires extra usage billing';
      case FastModeDisabledReason.networkError:
        return 'Fast mode unavailable due to network connectivity issues';
      case FastModeDisabledReason.unknown:
        return 'Fast mode is currently unavailable';
    }
  }

  /// Get the initial fast mode setting based on availability and settings.
  bool getInitialFastModeSetting(ModelSetting model) {
    if (!isFastModeEnabled) return false;
    if (!isFastModeAvailable) return false;
    if (!isFastModeSupportedByModel(model)) return false;
    final settings = _config.getInitialSettings();
    if (settings['fastModePerSessionOptIn'] == true) return false;
    return settings['fastMode'] == true;
  }

  /// Check if a model supports fast mode.
  bool isFastModeSupportedByModel(ModelSetting modelSetting) {
    if (!isFastModeEnabled) return false;
    final model = modelSetting ?? _config.getDefaultMainLoopModel();
    final parsedModel = _config.parseUserSpecifiedModel(model);
    return parsedModel.toLowerCase().contains('opus-4-6');
  }

  // ─── Runtime state ─────────────────────────────────────────────────────

  /// Get the current fast mode runtime state, checking for cooldown expiry.
  FastModeRuntimeState get runtimeState {
    if (_runtimeState is FastModeCooldown) {
      final cooldown = _runtimeState as FastModeCooldown;
      if (DateTime.now().millisecondsSinceEpoch >= cooldown.resetAt) {
        if (isFastModeEnabled && !_hasLoggedCooldownExpiry) {
          _hasLoggedCooldownExpiry = true;
          cooldownExpired.emit();
        }
        _runtimeState = const FastModeActive();
      }
    }
    return _runtimeState;
  }

  /// Trigger a cooldown period for fast mode.
  void triggerCooldown(int resetTimestamp, CooldownReason reason) {
    if (!isFastModeEnabled) return;
    _runtimeState = FastModeCooldown(resetAt: resetTimestamp, reason: reason);
    _hasLoggedCooldownExpiry = false;
    cooldownTriggered.emit((resetAt: resetTimestamp, reason: reason));
  }

  /// Clear the cooldown state.
  void clearCooldown() {
    _runtimeState = const FastModeActive();
  }

  /// Check if currently in cooldown.
  bool get isCooldown => runtimeState is FastModeCooldown;

  /// Called when the API rejects a fast mode request. Permanently disables
  /// fast mode using the same flow as when the prefetch discovers the org
  /// has it disabled.
  void handleRejectedByApi() {
    if (_orgStatus is FastModeOrgDisabled) return;
    _orgStatus = const FastModeOrgDisabled(
      reason: FastModeDisabledReason.preference,
    );
    _config.updateSettingsForSource('userSettings', {'fastMode': null});
    _config.saveGlobalConfig(
      (current) => {...current, 'penguinModeOrgEnabled': false},
    );
    orgFastModeChanged.emit(false);
  }

  /// Get the overall fast mode state.
  FastModeState getFastModeState(
    ModelSetting model,
    bool? fastModeUserEnabled,
  ) {
    final enabled =
        isFastModeEnabled &&
        isFastModeAvailable &&
        (fastModeUserEnabled == true) &&
        isFastModeSupportedByModel(model);
    if (enabled && isCooldown) return FastModeState.cooldown;
    if (enabled) return FastModeState.on;
    return FastModeState.off;
  }

  // ─── Overage rejection ─────────────────────────────────────────────────

  /// Get a message for an overage disabled reason.
  String _getOverageDisabledMessage(String? reason) {
    switch (reason) {
      case 'out_of_credits':
        return 'Fast mode disabled -- extra usage credits exhausted';
      case 'org_level_disabled':
      case 'org_service_level_disabled':
        return 'Fast mode disabled -- extra usage disabled by your organization';
      case 'org_level_disabled_until':
        return 'Fast mode disabled -- extra usage spending cap reached';
      case 'member_level_disabled':
        return 'Fast mode disabled -- extra usage disabled for your account';
      case 'seat_tier_level_disabled':
      case 'seat_tier_zero_credit_limit':
      case 'member_zero_credit_limit':
        return 'Fast mode disabled -- extra usage not available for your plan';
      case 'overage_not_provisioned':
      case 'no_limits_configured':
        return 'Fast mode requires extra usage billing';
      default:
        return 'Fast mode disabled -- extra usage not available';
    }
  }

  /// Check if a reason indicates the user ran out of credits.
  bool _isOutOfCreditsReason(String? reason) {
    return reason == 'org_level_disabled_until' || reason == 'out_of_credits';
  }

  /// Called when a 429 indicates fast mode was rejected because extra usage
  /// is not available.
  void handleOverageRejection(String? reason) {
    final message = _getOverageDisabledMessage(reason);
    // Disable fast mode permanently unless the user has ran out of credits.
    if (!_isOutOfCreditsReason(reason)) {
      _config.updateSettingsForSource('userSettings', {'fastMode': null});
      _config.saveGlobalConfig(
        (current) => {...current, 'penguinModeOrgEnabled': false},
      );
    }
    overageRejection.emit(message);
  }

  // ─── Org status prefetch ───────────────────────────────────────────────

  /// Resolve orgStatus from the persisted cache without making any API calls.
  void resolveFastModeStatusFromCache() {
    if (!isFastModeEnabled) return;
    if (_orgStatus is! FastModeOrgPending) return;
    final isAnt = _config.getUserType() == 'ant';
    final cachedEnabled =
        _config.getGlobalConfig()['penguinModeOrgEnabled'] == true;
    _orgStatus = isAnt || cachedEnabled
        ? const FastModeOrgEnabled()
        : const FastModeOrgDisabled(reason: FastModeDisabledReason.unknown);
  }

  /// Prefetch fast mode status from the API.
  Future<void> prefetchFastModeStatus() async {
    // Skip network requests if nonessential traffic is disabled.
    if (_config.isEssentialTrafficOnly()) return;
    if (!isFastModeEnabled) return;

    if (_inflightPrefetch != null) {
      return _inflightPrefetch;
    }

    // Service key OAuth sessions lack user:profile scope.
    final apiKey = _config.getApiKey();
    final oauthTokens = _config.getOAuthTokens();
    final hasUsableOAuth =
        oauthTokens != null &&
        oauthTokens['accessToken'] != null &&
        _config.hasProfileScope();
    if (!hasUsableOAuth && apiKey == null) {
      final isAnt = _config.getUserType() == 'ant';
      final cachedEnabled =
          _config.getGlobalConfig()['penguinModeOrgEnabled'] == true;
      _orgStatus = isAnt || cachedEnabled
          ? const FastModeOrgEnabled()
          : const FastModeOrgDisabled(
              reason: FastModeDisabledReason.preference,
            );
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPrefetchAt < prefetchMinIntervalMs) return;
    _lastPrefetchAt = now;

    _inflightPrefetch = _doFetch(apiKey, oauthTokens);
    return _inflightPrefetch;
  }

  Future<void> _doFetch(
    String? apiKey,
    Map<String, String>? oauthTokens,
  ) async {
    try {
      FastModeResponse status;
      try {
        status = await _fetchFastModeStatus(apiKey, oauthTokens);
      } catch (err) {
        // Try to handle auth errors.
        final accessToken = oauthTokens?['accessToken'];
        if (accessToken != null && _isAuthError(err)) {
          await _config.handleOAuth401Error(accessToken);
          status = await _fetchFastModeStatus(apiKey, _config.getOAuthTokens());
        } else {
          rethrow;
        }
      }

      final previousEnabled = _orgStatus is! FastModeOrgPending
          ? _orgStatus is FastModeOrgEnabled
          : _config.getGlobalConfig()['penguinModeOrgEnabled'] == true;

      _orgStatus = status.enabled
          ? const FastModeOrgEnabled()
          : FastModeOrgDisabled(
              reason:
                  status.disabledReason ?? FastModeDisabledReason.preference,
            );

      if (previousEnabled != status.enabled) {
        if (!status.enabled) {
          _config.updateSettingsForSource('userSettings', {'fastMode': null});
        }
        _config.saveGlobalConfig(
          (current) => {...current, 'penguinModeOrgEnabled': status.enabled},
        );
        orgFastModeChanged.emit(status.enabled);
      }
    } catch (_) {
      // On failure: ants default to enabled.
      // External users: fall back to cached value.
      final isAnt = _config.getUserType() == 'ant';
      final cachedEnabled =
          _config.getGlobalConfig()['penguinModeOrgEnabled'] == true;
      _orgStatus = isAnt || cachedEnabled
          ? const FastModeOrgEnabled()
          : const FastModeOrgDisabled(
              reason: FastModeDisabledReason.networkError,
            );
    } finally {
      _inflightPrefetch = null;
    }
  }

  Future<FastModeResponse> _fetchFastModeStatus(
    String? apiKey,
    Map<String, String>? oauthTokens,
  ) async {
    final endpoint = '${_config.getBaseApiUrl()}/api/neomclaw_penguin_mode';
    final accessToken = oauthTokens?['accessToken'];
    final hasOAuth = accessToken != null && _config.hasProfileScope();

    final client = HttpClient();
    try {
      final uri = Uri.parse(endpoint);
      final request = await client.getUrl(uri);

      if (hasOAuth) {
        request.headers.set('Authorization', 'Bearer $accessToken');
        request.headers.set('anthropic-beta', _config.getOAuthBetaHeader());
      } else if (apiKey != null) {
        request.headers.set('x-api-key', apiKey);
      } else {
        throw Exception('No auth available');
      }

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw HttpException(
          'Fast mode status fetch failed: ${response.statusCode}',
          uri: uri,
        );
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      return FastModeResponse.fromJson(data);
    } finally {
      client.close();
    }
  }

  bool _isAuthError(Object err) {
    if (err is HttpException) {
      final msg = err.message;
      return msg.contains('401') ||
          (msg.contains('403') && msg.contains('revoked'));
    }
    return false;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Parse a disabled reason string from the API.
FastModeDisabledReason _parseDisabledReason(String reason) {
  switch (reason) {
    case 'free':
      return FastModeDisabledReason.free;
    case 'preference':
      return FastModeDisabledReason.preference;
    case 'extra_usage_disabled':
      return FastModeDisabledReason.extraUsageDisabled;
    case 'network_error':
      return FastModeDisabledReason.networkError;
    default:
      return FastModeDisabledReason.unknown;
  }
}
