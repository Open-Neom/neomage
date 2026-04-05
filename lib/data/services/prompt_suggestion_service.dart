// Prompt suggestion service — port of neomage/src/services/PromptSuggestion.
// Predicts what the user would naturally type next.

import '../../domain/models/message.dart';
import '../api/api_provider.dart';

/// Result of a prompt suggestion attempt.
class SuggestionResult {
  final String? suggestion;
  final SuggestionOutcome outcome;
  final String? reason;

  const SuggestionResult({this.suggestion, required this.outcome, this.reason});
}

/// Outcome of a suggestion attempt.
enum SuggestionOutcome { generated, suppressed, filtered, error }

/// Why a suggestion was suppressed.
enum SuppressionReason {
  earlyConversation,
  apiError,
  planMode,
  pendingPermission,
  rateLimited,
  disabled,
}

/// Why a suggestion was filtered.
enum FilterReason {
  done,
  nothingFound,
  silence,
  question,
  neomageVoice,
  tooShort,
  tooLong,
  singleWord,
  formatting,
  multipleSentences,
  looksGood,
}

/// Prompt suggestion service.
class PromptSuggestionService {
  final ApiProvider provider;
  bool enabled;

  PromptSuggestionService({required this.provider, this.enabled = true});

  /// Generate a suggestion based on conversation context.
  Future<SuggestionResult> generateSuggestion({
    required List<Message> messages,
    bool isPlanMode = false,
    bool hasPendingPermission = false,
    bool isRateLimited = false,
  }) async {
    if (!enabled) {
      return const SuggestionResult(
        outcome: SuggestionOutcome.suppressed,
        reason: 'disabled',
      );
    }

    // Suppression checks
    final suppression = _checkSuppression(
      messages: messages,
      isPlanMode: isPlanMode,
      hasPendingPermission: hasPendingPermission,
      isRateLimited: isRateLimited,
    );
    if (suppression != null) {
      return SuggestionResult(
        outcome: SuggestionOutcome.suppressed,
        reason: suppression.name,
      );
    }

    try {
      final response = await provider.createMessage(
        messages: messages,
        systemPrompt: _suggestionSystemPrompt,
        maxTokens: 50,
      );

      final text = response.textContent.trim();
      final filterResult = _filterSuggestion(text);

      if (filterResult != null) {
        return SuggestionResult(
          outcome: SuggestionOutcome.filtered,
          reason: filterResult.name,
        );
      }

      return SuggestionResult(
        suggestion: text,
        outcome: SuggestionOutcome.generated,
      );
    } catch (e) {
      return SuggestionResult(
        outcome: SuggestionOutcome.error,
        reason: e.toString(),
      );
    }
  }

  SuppressionReason? _checkSuppression({
    required List<Message> messages,
    required bool isPlanMode,
    required bool hasPendingPermission,
    required bool isRateLimited,
  }) {
    // Need at least 2 assistant turns
    final assistantCount = messages
        .where((m) => m.role == MessageRole.assistant)
        .length;
    if (assistantCount < 2) return SuppressionReason.earlyConversation;

    if (isPlanMode) return SuppressionReason.planMode;
    if (hasPendingPermission) return SuppressionReason.pendingPermission;
    if (isRateLimited) return SuppressionReason.rateLimited;

    return null;
  }

  FilterReason? _filterSuggestion(String text) {
    final lower = text.toLowerCase();

    // Meta-text filters
    if (lower.contains('done') && text.length < 20) return FilterReason.done;
    if (lower.contains('nothing found')) return FilterReason.nothingFound;
    if (lower.contains('silence')) return FilterReason.silence;

    // Neomage voice
    if (lower.startsWith('let me') || lower.startsWith("i'll")) {
      return FilterReason.neomageVoice;
    }

    // Evaluative
    if (lower.startsWith('looks good')) return FilterReason.looksGood;

    // Questions
    if (text.endsWith('?')) return FilterReason.question;

    // Length checks
    final wordCount = text.split(RegExp(r'\s+')).length;
    if (wordCount < 2) {
      // Allow single words from approved list
      const allowed = {
        'yes',
        'no',
        'push',
        'commit',
        'continue',
        'stop',
        'skip',
        'next',
        'done',
        'exit',
        'help',
        'undo',
        'retry',
        'approve',
        'deny',
        'cancel',
        'run',
        'test',
        'build',
        'deploy',
        'merge',
        'revert',
        'reset',
        'save',
        'delete',
      };
      if (!allowed.contains(lower)) return FilterReason.singleWord;
    }
    if (wordCount > 12) return FilterReason.tooLong;
    if (text.length > 100) return FilterReason.tooLong;

    // Multiple sentences
    if (text.contains('. ') && text.split('. ').length > 2) {
      return FilterReason.multipleSentences;
    }

    return null;
  }

  static const String _suggestionSystemPrompt =
      'Predict what the user would naturally type next. '
      'Return only the prediction (2-12 words). '
      'Do not use Neomage voice ("Let me...", "I\'ll..."). '
      'Do not ask questions. Do not evaluate.';
}
