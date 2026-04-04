/// Voice mode service for the Flutter client.
///
/// Migrated from the OpenClaude TypeScript `voice/` module. Provides:
/// - [VoiceState] enum (idle / recording / processing)
/// - [VoiceMode] toggle state
/// - Language normalization for speech-to-text
/// - Feature-flag and auth gating (simplified — no GrowthBook dependency)
///
/// The service is provider-agnostic: callers supply their own STT/TTS
/// implementation via [VoiceServiceConfig].
library;

/// Current phase of a voice interaction.
enum VoiceState {
  /// No active recording or transcription.
  idle,

  /// Microphone is capturing audio.
  recording,

  /// Audio captured; waiting for STT result.
  processing,
}

/// Result of [normalizeLanguageForSTT].
class SttLanguageResult {
  /// The resolved BCP-47 language code.
  final String code;

  /// If non-null, the original language string that could not be mapped
  /// to a supported code and was replaced with the default.
  final String? fellBackFrom;

  /// Creates an [SttLanguageResult].
  const SttLanguageResult({required this.code, this.fellBackFrom});

  @override
  String toString() =>
      'SttLanguageResult(code: $code'
      '${fellBackFrom != null ? ', fellBackFrom: $fellBackFrom' : ''})';
}

/// Outcome of a voice-mode toggle attempt.
sealed class VoiceToggleResult {
  const VoiceToggleResult();
}

/// Voice mode was successfully toggled.
class VoiceToggleSuccess extends VoiceToggleResult {
  /// Whether voice mode is now enabled.
  final bool enabled;

  /// Human-readable status message.
  final String message;

  /// The resolved STT language (only present when [enabled] is true).
  final SttLanguageResult? sttLanguage;

  const VoiceToggleSuccess({
    required this.enabled,
    required this.message,
    this.sttLanguage,
  });
}

/// Voice mode could not be toggled.
class VoiceToggleError extends VoiceToggleResult {
  /// Human-readable reason.
  final String reason;

  const VoiceToggleError(this.reason);
}

/// Callback signatures for provider-agnostic voice operations.
///
/// Callers inject platform/provider implementations so the service
/// itself carries no hard dependency on a specific STT or TTS SDK.
class VoiceServiceConfig {
  /// Whether the feature flag allows voice mode to be shown / used.
  /// Replaces the GrowthBook kill-switch with a plain boolean.
  final bool featureEnabled;

  /// Whether the user has valid authentication for voice streaming.
  final bool Function() hasAuth;

  /// Check whether recording hardware is available and permitted.
  /// Returns `null` when available, or a human-readable reason string
  /// when not.
  final Future<String?> Function() checkRecordingAvailability;

  /// Request microphone permission from the OS.
  /// Returns `true` if granted.
  final Future<bool> Function() requestMicrophonePermission;

  /// Persist a settings change (e.g. `voiceEnabled: true`).
  final Future<bool> Function(bool enabled) saveVoiceEnabled;

  /// Read the current `voiceEnabled` flag from persisted settings.
  final bool Function() readVoiceEnabled;

  /// Read the current language preference from settings (may be null).
  final String? Function() readLanguagePreference;

  /// Creates a [VoiceServiceConfig].
  const VoiceServiceConfig({
    required this.featureEnabled,
    required this.hasAuth,
    required this.checkRecordingAvailability,
    required this.requestMicrophonePermission,
    required this.saveVoiceEnabled,
    required this.readVoiceEnabled,
    required this.readLanguagePreference,
  });
}

// ---------------------------------------------------------------------------
// Language normalization
// ---------------------------------------------------------------------------

/// Default speech-to-text language when none is configured or the
/// configured value is unsupported.
const _defaultSttLanguage = 'en';

/// Maps language names (English and native) to BCP-47 codes supported by
/// the voice-stream backend. Keys must be lowercase.
const _languageNameToCode = <String, String>{
  'english': 'en',
  'spanish': 'es',
  'español': 'es',
  'espanol': 'es',
  'french': 'fr',
  'français': 'fr',
  'francais': 'fr',
  'japanese': 'ja',
  '日本語': 'ja',
  'german': 'de',
  'deutsch': 'de',
  'portuguese': 'pt',
  'português': 'pt',
  'portugues': 'pt',
  'italian': 'it',
  'italiano': 'it',
  'korean': 'ko',
  '한국어': 'ko',
  'hindi': 'hi',
  'हिन्दी': 'hi',
  'हिंदी': 'hi',
  'indonesian': 'id',
  'bahasa indonesia': 'id',
  'bahasa': 'id',
  'russian': 'ru',
  'русский': 'ru',
  'polish': 'pl',
  'polski': 'pl',
  'turkish': 'tr',
  'türkçe': 'tr',
  'turkce': 'tr',
  'dutch': 'nl',
  'nederlands': 'nl',
  'ukrainian': 'uk',
  'українська': 'uk',
  'greek': 'el',
  'ελληνικά': 'el',
  'czech': 'cs',
  'čeština': 'cs',
  'cestina': 'cs',
  'danish': 'da',
  'dansk': 'da',
  'swedish': 'sv',
  'svenska': 'sv',
  'norwegian': 'no',
  'norsk': 'no',
};

/// BCP-47 codes accepted by the voice-stream STT backend.
const _supportedLanguageCodes = <String>{
  'en', 'es', 'fr', 'ja', 'de', 'pt', 'it', 'ko',
  'hi', 'id', 'ru', 'pl', 'tr', 'nl', 'uk', 'el',
  'cs', 'da', 'sv', 'no',
};

/// Normalize a language preference string to a BCP-47 code supported by
/// the voice-stream STT endpoint.
///
/// Returns the default language (`en`) when [language] is null, empty, or
/// cannot be resolved. When a non-empty but unsupported value is given,
/// [SttLanguageResult.fellBackFrom] carries the original string so callers
/// can surface a warning.
SttLanguageResult normalizeLanguageForSTT(String? language) {
  if (language == null || language.isEmpty) {
    return const SttLanguageResult(code: _defaultSttLanguage);
  }
  final lower = language.toLowerCase().trim();
  if (lower.isEmpty) {
    return const SttLanguageResult(code: _defaultSttLanguage);
  }
  if (_supportedLanguageCodes.contains(lower)) {
    return SttLanguageResult(code: lower);
  }
  final fromName = _languageNameToCode[lower];
  if (fromName != null) {
    return SttLanguageResult(code: fromName);
  }
  final base = lower.split('-').first;
  if (base.isNotEmpty && _supportedLanguageCodes.contains(base)) {
    return SttLanguageResult(code: base);
  }
  return SttLanguageResult(code: _defaultSttLanguage, fellBackFrom: language);
}

// ---------------------------------------------------------------------------
// Voice service
// ---------------------------------------------------------------------------

/// Provider-agnostic voice mode service.
///
/// Manages the enabled/disabled lifecycle, pre-flight checks (auth,
/// feature flag, mic permission), and language resolution. Does **not**
/// embed any specific STT or TTS provider — callers inject those via
/// [VoiceServiceConfig].
class VoiceService {
  /// Configuration injected at construction time.
  final VoiceServiceConfig config;

  /// Current voice interaction state.
  VoiceState state = VoiceState.idle;

  /// Creates a [VoiceService] with the given [config].
  VoiceService(this.config);

  // ---- Feature / auth gating ---------------------------------------------

  /// Whether the feature flag allows voice mode to be visible.
  bool get isFeatureEnabled => config.featureEnabled;

  /// Whether the user has valid voice-streaming auth.
  bool get hasAuth => config.hasAuth();

  /// Full runtime gate: feature flag **and** auth.
  bool get isVoiceModeEnabled => isFeatureEnabled && hasAuth;

  // ---- Toggle -------------------------------------------------------------

  /// Toggle voice mode on or off.
  ///
  /// Runs pre-flight checks (auth, feature flag, recording availability,
  /// mic permission) when enabling. Returns a [VoiceToggleResult]
  /// describing the outcome.
  Future<VoiceToggleResult> toggle() async {
    // Gate: feature + auth
    if (!isVoiceModeEnabled) {
      if (!hasAuth) {
        return const VoiceToggleError(
          'Voice mode requires authentication. Please sign in first.',
        );
      }
      return const VoiceToggleError('Voice mode is not available.');
    }

    final currentlyEnabled = config.readVoiceEnabled();

    // Toggle OFF — no pre-flight needed.
    if (currentlyEnabled) {
      final ok = await config.saveVoiceEnabled(false);
      if (!ok) {
        return const VoiceToggleError(
          'Failed to update settings. Check your settings file for errors.',
        );
      }
      state = VoiceState.idle;
      return const VoiceToggleSuccess(
        enabled: false,
        message: 'Voice mode disabled.',
      );
    }

    // Toggle ON — pre-flight checks.
    final recordingIssue = await config.checkRecordingAvailability();
    if (recordingIssue != null) {
      return VoiceToggleError(recordingIssue);
    }

    final micGranted = await config.requestMicrophonePermission();
    if (!micGranted) {
      return const VoiceToggleError(
        'Microphone access is denied. Please grant microphone permission in '
        'your device settings, then try again.',
      );
    }

    // All checks passed.
    final ok = await config.saveVoiceEnabled(true);
    if (!ok) {
      return const VoiceToggleError(
        'Failed to update settings. Check your settings file for errors.',
      );
    }

    final stt = normalizeLanguageForSTT(config.readLanguagePreference());

    String langNote = '';
    if (stt.fellBackFrom != null) {
      langNote =
          ' Note: "${stt.fellBackFrom}" is not a supported dictation '
          'language; using English. Change it in settings.';
    } else if (stt.code != _defaultSttLanguage) {
      langNote = ' Dictation language: ${stt.code}.';
    }

    return VoiceToggleSuccess(
      enabled: true,
      message: 'Voice mode enabled.$langNote',
      sttLanguage: stt,
    );
  }
}
