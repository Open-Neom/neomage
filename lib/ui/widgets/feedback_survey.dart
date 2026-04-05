// FeedbackSurvey — port of neomage/src/components/FeedbackSurvey/
// Ports: FeedbackSurvey.tsx, FeedbackSurveyView.tsx, useFeedbackSurvey.tsx,
// useSurveyState.tsx, TranscriptSharePrompt.tsx, submitTranscriptShare.ts,
// useDebouncedDigitInput.ts, useMemorySurvey.tsx, usePostCompactSurvey.tsx
//
// Provides an inline feedback survey that appears periodically during a session.
// Users can rate the session as Bad (1), Fine (2), Good (3), or Dismiss (0).
// Optionally prompts to share the transcript for improvement.
// Handles survey state transitions, analytics events, debounced input,
// cross-session pacing, probability gating, and transcript sharing.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ─── Feedback response types ───

enum FeedbackSurveyResponse { dismissed, bad, fine, good }

enum TranscriptShareResponse { share, skip, dontAskAgain }

enum FeedbackSurveyType { session, memory, postCompact }

// ─── Survey state enum ───

enum FeedbackSurveyState {
  closed,
  open,
  thanks,
  transcriptPrompt,
  submitting,
  submitted,
}

// ─── Survey configuration (mirrors DEFAULT_FEEDBACK_SURVEY_CONFIG) ───

class FeedbackSurveyConfig {
  final Duration minTimeBeforeFeedback;
  final Duration minTimeBetweenFeedback;
  final Duration minTimeBetweenGlobalFeedback;
  final int minUserTurnsBeforeFeedback;
  final int minUserTurnsBetweenFeedback;
  final Duration hideThanksAfter;
  final List<String> onForModels;
  final double probability;

  const FeedbackSurveyConfig({
    this.minTimeBeforeFeedback = const Duration(minutes: 10),
    this.minTimeBetweenFeedback = const Duration(hours: 1),
    this.minTimeBetweenGlobalFeedback = const Duration(days: 1),
    this.minUserTurnsBeforeFeedback = 5,
    this.minUserTurnsBetweenFeedback = 10,
    this.hideThanksAfter = const Duration(seconds: 3),
    this.onForModels = const ['*'],
    this.probability = 0.005,
  });
}

class TranscriptAskConfig {
  final double probability;

  const TranscriptAskConfig({this.probability = 0.0});
}

// ─── FeedbackSurveyController (SintController) ───

class FeedbackSurveyController extends SintController {
  // Configuration
  final config = const FeedbackSurveyConfig().obs;
  final badTranscriptAskConfig = const TranscriptAskConfig().obs;
  final goodTranscriptAskConfig = const TranscriptAskConfig().obs;

  // Observable state
  final state = FeedbackSurveyState.closed.obs;
  final lastResponse = Rxn<FeedbackSurveyResponse>();
  final inputValue = ''.obs;

  // Survey type
  final surveyType = FeedbackSurveyType.session.obs;
  final message = Rxn<String>();

  // Pacing state
  DateTime? _timeLastShown;
  int? _submitCountAtLastAppearance;
  final DateTime _sessionStartTime = DateTime.now();
  final int _submitCountAtSessionStart = 0;

  // Probability gate: roll once when eligible, not on every check
  bool _probabilityPassed = false;
  int? _lastEligibleSubmitCount;

  // Appearance tracking
  // ignore: unused_field
  String? _currentAppearanceId;

  // Thanks timer
  Timer? _thanksTimer;

  // Transcript dismissed flag
  bool _transcriptShareDismissed = false;

  // Random for probability gating
  final _random = Random();

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    _thanksTimer?.cancel();
    super.onClose();
  }

  /// Check if the survey should be shown given current session state.
  bool shouldShowSurvey({
    required int submitCount,
    required bool isLoading,
    required bool hasActivePrompt,
  }) {
    // Don't show while loading or with active prompt
    if (isLoading || hasActivePrompt) return false;

    // Already showing or recently dismissed
    if (state.value != FeedbackSurveyState.closed) return false;

    final now = DateTime.now();
    final cfg = config.value;

    // Minimum time since session start
    if (now.difference(_sessionStartTime) < cfg.minTimeBeforeFeedback) {
      return false;
    }

    // Minimum turns since session start
    final turnsSinceStart = submitCount - _submitCountAtSessionStart;
    if (turnsSinceStart < cfg.minUserTurnsBeforeFeedback) return false;

    // Minimum time since last shown
    if (_timeLastShown != null) {
      if (now.difference(_timeLastShown!) < cfg.minTimeBetweenFeedback) {
        return false;
      }
    }

    // Minimum turns since last shown
    if (_submitCountAtLastAppearance != null) {
      final turnsSinceLastShown = submitCount - _submitCountAtLastAppearance!;
      if (turnsSinceLastShown < cfg.minUserTurnsBetweenFeedback) {
        return false;
      }
    }

    // Probability gate: roll once when first eligible at this submit count
    if (_lastEligibleSubmitCount != submitCount) {
      _lastEligibleSubmitCount = submitCount;
      _probabilityPassed = _random.nextDouble() <= cfg.probability;
    }

    return _probabilityPassed;
  }

  /// Open the survey.
  void open() {
    _currentAppearanceId =
        '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(100000)}';
    state.value = FeedbackSurveyState.open;
    inputValue.value = '';
    _updateLastShownTime();

    // Log appearance event
    _logEvent('appeared');
  }

  /// Handle user selecting a response.
  bool handleSelect(FeedbackSurveyResponse selected) {
    lastResponse.value = selected;
    _updateLastShownTime();

    // Log response event
    _logEvent('responded', response: selected.name);

    if (selected == FeedbackSurveyResponse.dismissed) {
      _showThanksAndClose();
      return true;
    }

    // Check if we should show transcript prompt
    if (_shouldShowTranscriptPrompt(selected)) {
      state.value = FeedbackSurveyState.transcriptPrompt;
      inputValue.value = '';
      _logEvent('transcript_prompt_appeared');
      return true;
    }

    _showThanksAndClose();
    return true;
  }

  /// Handle transcript share response.
  void handleTranscriptSelect(TranscriptShareResponse selected) {
    switch (selected) {
      case TranscriptShareResponse.share:
        state.value = FeedbackSurveyState.submitting;
        _logEvent('transcript_shared');
        // Simulate submission
        Future.delayed(const Duration(seconds: 1), () {
          state.value = FeedbackSurveyState.submitted;
          _scheduleClose();
        });
      case TranscriptShareResponse.skip:
        _showThanksAndClose();
      case TranscriptShareResponse.dontAskAgain:
        _transcriptShareDismissed = true;
        _showThanksAndClose();
    }
  }

  /// Request feedback (follow-up after good rating).
  void requestFeedback() {
    _logEvent('followup_accepted');
  }

  bool _shouldShowTranscriptPrompt(FeedbackSurveyResponse selected) {
    if (selected != FeedbackSurveyResponse.bad &&
        selected != FeedbackSurveyResponse.good) {
      return false;
    }

    if (_transcriptShareDismissed) return false;

    final probability = selected == FeedbackSurveyResponse.bad
        ? badTranscriptAskConfig.value.probability
        : goodTranscriptAskConfig.value.probability;

    return _random.nextDouble() <= probability;
  }

  void _showThanksAndClose() {
    state.value = FeedbackSurveyState.thanks;
    inputValue.value = '';
    _scheduleClose();
  }

  void _scheduleClose() {
    _thanksTimer?.cancel();
    _thanksTimer = Timer(config.value.hideThanksAfter, () {
      state.value = FeedbackSurveyState.closed;
      _probabilityPassed = false;
    });
  }

  void _updateLastShownTime() {
    _timeLastShown = DateTime.now();
    // In real implementation, would also persist to global config
  }

  void _logEvent(String eventType, {String? response}) {
    // In real implementation, this would log analytics events
    // logEvent('tengu_feedback_survey_event', { event_type: eventType, ... })
  }
}

// ─── Valid response inputs (mirrors FeedbackSurveyView.tsx) ───

const _responseInputs = ['0', '1', '2', '3'];

bool isValidResponseInput(String input) => _responseInputs.contains(input);

// ─── FeedbackSurvey widget (mirrors FeedbackSurvey.tsx) ───

class FeedbackSurvey extends StatelessWidget {
  const FeedbackSurvey({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<FeedbackSurveyController>();

    return Obx(() {
      switch (controller.state.value) {
        case FeedbackSurveyState.closed:
          return const SizedBox.shrink();

        case FeedbackSurveyState.open:
          return FeedbackSurveyView(
            onSelect: controller.handleSelect,
            message: controller.message.value,
          );

        case FeedbackSurveyState.thanks:
          return _FeedbackSurveyThanks(
            lastResponse: controller.lastResponse.value,
            onRequestFeedback:
                controller.lastResponse.value == FeedbackSurveyResponse.good
                ? controller.requestFeedback
                : null,
          );

        case FeedbackSurveyState.transcriptPrompt:
          return TranscriptSharePrompt(
            onSelect: controller.handleTranscriptSelect,
          );

        case FeedbackSurveyState.submitting:
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Sharing transcript...',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          );

        case FeedbackSurveyState.submitted:
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  'Thanks for sharing your transcript!',
                  style: TextStyle(color: Colors.green[700], fontSize: 13),
                ),
              ],
            ),
          );
      }
    });
  }
}

// ─── FeedbackSurveyView (mirrors FeedbackSurveyView.tsx) ───

class FeedbackSurveyView extends StatelessWidget {
  final bool Function(FeedbackSurveyResponse) onSelect;
  final String? message;

  static const _defaultMessage =
      'How is Neomage doing this session? (optional)';

  const FeedbackSurveyView({super.key, required this.onSelect, this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayMessage = message ?? _defaultMessage;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Question row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\u25CF ',
                style: TextStyle(color: Colors.cyan[400], fontSize: 14),
              ),
              Text(
                displayMessage,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Options row
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SurveyOption(
                  digit: '1',
                  label: NeomageTranslationConstants.bad.tr,
                  onTap: () => onSelect(FeedbackSurveyResponse.bad),
                ),
                const SizedBox(width: 16),
                _SurveyOption(
                  digit: '2',
                  label: NeomageTranslationConstants.fine.tr,
                  onTap: () => onSelect(FeedbackSurveyResponse.fine),
                ),
                const SizedBox(width: 16),
                _SurveyOption(
                  digit: '3',
                  label: NeomageTranslationConstants.good.tr,
                  onTap: () => onSelect(FeedbackSurveyResponse.good),
                ),
                const SizedBox(width: 16),
                _SurveyOption(
                  digit: '0',
                  label: NeomageTranslationConstants.dismiss.tr,
                  onTap: () => onSelect(FeedbackSurveyResponse.dismissed),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Survey option button ───

class _SurveyOption extends StatelessWidget {
  final String digit;
  final String label;
  final VoidCallback onTap;

  const _SurveyOption({
    required this.digit,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: digit,
                style: TextStyle(color: Colors.cyan[400], fontSize: 13),
              ),
              TextSpan(
                text: ': $label',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Thanks state (mirrors FeedbackSurveyThanks in FeedbackSurvey.tsx) ───

class _FeedbackSurveyThanks extends StatelessWidget {
  final FeedbackSurveyResponse? lastResponse;
  final VoidCallback? onRequestFeedback;

  const _FeedbackSurveyThanks({this.lastResponse, this.onRequestFeedback});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showFollowUp =
        onRequestFeedback != null &&
        lastResponse == FeedbackSurveyResponse.good;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'Thanks for your feedback!',
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (showFollowUp) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: InkWell(
                onTap: onRequestFeedback,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: '1',
                          style: TextStyle(
                            color: Colors.cyan[400],
                            fontSize: 12,
                          ),
                        ),
                        TextSpan(
                          text: ': Share more details',
                          style: TextStyle(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── TranscriptSharePrompt (mirrors TranscriptSharePrompt.tsx) ───

class TranscriptSharePrompt extends StatelessWidget {
  final void Function(TranscriptShareResponse) onSelect;

  const TranscriptSharePrompt({super.key, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\u25CF ',
                style: TextStyle(color: Colors.cyan[400], fontSize: 14),
              ),
              Flexible(
                child: Text(
                  'Would you like to share this transcript to help improve Neomage?',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 2),

          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(
              'Your transcript will be used to improve Neomage. '
              'It may be reviewed by Anthropic employees.',
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ),

          const SizedBox(height: 4),

          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SurveyOption(
                  digit: '1',
                  label: NeomageTranslationConstants.share.tr,
                  onTap: () => onSelect(TranscriptShareResponse.share),
                ),
                const SizedBox(width: 16),
                _SurveyOption(
                  digit: '2',
                  label: NeomageTranslationConstants.skip.tr,
                  onTap: () => onSelect(TranscriptShareResponse.skip),
                ),
                const SizedBox(width: 16),
                _SurveyOption(
                  digit: '3',
                  label: NeomageTranslationConstants.dontAskAgain.tr,
                  onTap: () => onSelect(TranscriptShareResponse.dontAskAgain),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── DebouncedDigitInput helper (mirrors useDebouncedDigitInput.ts) ───
// In Flutter, this is implemented as a mixin or simple utility
// rather than a hook.

class DebouncedDigitInput {
  final bool Function(String) isValidDigit;
  final void Function(String) onDigit;
  final Duration debounceDelay;
  final bool once;

  Timer? _timer;
  String _pendingDigit = '';
  bool _hasFired = false;

  DebouncedDigitInput({
    required this.isValidDigit,
    required this.onDigit,
    this.debounceDelay = const Duration(milliseconds: 500),
    this.once = false,
  });

  /// Call when user types a character.
  void handleInput(String char) {
    if (once && _hasFired) return;

    if (!isValidDigit(char)) return;

    _pendingDigit = char;
    _timer?.cancel();
    _timer = Timer(debounceDelay, () {
      if (_pendingDigit.isNotEmpty) {
        onDigit(_pendingDigit);
        _hasFired = true;
        _pendingDigit = '';
      }
    });
  }

  void dispose() {
    _timer?.cancel();
  }
}
