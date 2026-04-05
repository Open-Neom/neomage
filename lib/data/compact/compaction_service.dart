// Context compaction service — ported from neomagent src/services/compact/compact.ts.
// Three-phase system: microcompact → auto-compact → full compaction.
// Supports three strategies: auto, manual, and micro.

import 'dart:math';

import '../../domain/models/message.dart';
import '../api/api_provider.dart';

// ============================================================================
// Constants
// ============================================================================

/// Tools whose results can be safely cleared during microcompaction.
const Set<String> compactableToolNames = {
  'Read',
  'Bash',
  'Grep',
  'Glob',
  'WebSearch',
  'WebFetch',
  'Edit',
  'Write',
};

/// Cleared content replacement marker.
const String clearedMessage = '[Old tool result content cleared]';

/// Flat token estimate for images.
const int imageMaxTokenSize = 2000;

/// Buffer tokens subtracted from context window for auto-compact threshold.
const int autocompactBufferTokens = 13000;

/// Max output tokens for summary generation.
const int compactMaxOutputTokens = 20000;

/// Max prompt-too-long retries before giving up.
const int maxPtlRetries = 3;

/// Max consecutive compact failures before circuit breaker trips.
const int maxConsecutiveFailures = 3;

/// Max files to re-inject after compaction for context continuity.
const int postCompactMaxFilesToRestore = 5;

/// Token budget for post-compact file attachments.
const int postCompactTokenBudget = 50000;

/// Max tokens per individual file in post-compact restore.
const int postCompactMaxTokensPerFile = 5000;

/// Max tokens per skill in post-compact restore.
const int postCompactMaxTokensPerSkill = 5000;

/// Total token budget for all skills in post-compact restore.
const int postCompactSkillsTokenBudget = 25000;

/// Max streaming retries for compact API calls.
const int maxCompactStreamingRetries = 2;

/// Prompt-too-long retry marker prepended to truncated messages.
const String ptlRetryMarker =
    '[earlier conversation truncated for compaction retry]';

// ============================================================================
// Error messages
// ============================================================================

/// Error when there are not enough messages to compact.
const String errorNotEnoughMessages = 'Not enough messages to compact.';

/// Error when the conversation is too long even for compact.
const String errorPromptTooLong =
    'Conversation too long. Press esc twice to go up a few messages and try again.';

/// Error when the user aborts the compact request.
const String errorUserAbort = 'API Error: Request was aborted.';

/// Error when streaming was interrupted mid-compact.
const String errorIncompleteResponse =
    'Compaction interrupted \u00b7 This may be due to network issues \u2014 please try again.';

// ============================================================================
// Enums
// ============================================================================

/// Strategy that triggered the compaction.
enum CompactionStrategy {
  /// Triggered automatically when token usage crosses the threshold.
  auto,

  /// Triggered explicitly by the user via `/compact`.
  manual,

  /// Lightweight clearing of old tool results without summarization.
  micro,
}

/// Direction for partial compaction around a selected message.
enum PartialCompactDirection {
  /// Summarize messages *after* the pivot; keep earlier ones.
  from,

  /// Summarize messages *before* the pivot; keep later ones.
  upTo,
}

/// Progress event types emitted during compaction.
enum CompactProgressType {
  /// Hooks are being executed.
  hooksStart,

  /// Compaction has started.
  compactStart,

  /// Compaction has ended.
  compactEnd,
}

/// Hook type for progress reporting.
enum CompactHookType {
  preCompact,
  postCompact,
  sessionStart,
}

// ============================================================================
// Data classes
// ============================================================================

/// Progress event emitted during compaction.
class CompactProgressEvent {
  /// The type of progress event.
  final CompactProgressType type;

  /// Which hook phase this event relates to (only for [hooksStart]).
  final CompactHookType? hookType;

  const CompactProgressEvent({required this.type, this.hookType});
}

/// Result of a compaction operation.
class CompactionResult {
  /// The compacted message list to replace the conversation.
  final List<Message> compactedMessages;

  /// The generated summary text (null for micro-compaction).
  final String? summary;

  /// Token count before compaction.
  final int preCompactTokenCount;

  /// Token count after compaction.
  final int postCompactTokenCount;

  /// The strategy that was used.
  final CompactionStrategy strategy;

  /// User-facing display message from hooks.
  final String? userDisplayMessage;

  /// Messages preserved from partial compaction.
  final List<Message>? messagesToKeep;

  const CompactionResult({
    required this.compactedMessages,
    this.summary,
    required this.preCompactTokenCount,
    required this.postCompactTokenCount,
    this.strategy = CompactionStrategy.auto,
    this.userDisplayMessage,
    this.messagesToKeep,
  });
}

/// Diagnosis context for recompaction tracking.
class RecompactionInfo {
  /// Whether this is a recompaction within the same chain.
  final bool isRecompactionInChain;

  /// Turns since the previous compaction.
  final int turnsSincePreviousCompact;

  /// Turn ID of the previous compaction boundary.
  final String? previousCompactTurnId;

  /// Token threshold that triggered auto-compact.
  final int autoCompactThreshold;

  const RecompactionInfo({
    required this.isRecompactionInChain,
    required this.turnsSincePreviousCompact,
    this.previousCompactTurnId,
    required this.autoCompactThreshold,
  });
}

/// Callback signature for compaction progress events.
typedef OnCompactProgress = void Function(CompactProgressEvent event);

// ============================================================================
// Service
// ============================================================================

/// Context compaction service.
///
/// Manages the three-phase compaction pipeline:
///
/// 1. **Microcompaction** — lightweight clearing of old tool results to
///    free tokens without an API call.
/// 2. **Auto-compact trigger** — checks whether token usage has crossed
///    the threshold requiring full compaction.
/// 3. **Full compaction** — summarizes the conversation via an LLM call
///    and replaces messages with the summary.
///
/// Supports both full and partial compaction, system prompt preservation,
/// and prompt-too-long retry logic.
class CompactionService {
  /// The API provider used for summary generation.
  final ApiProvider provider;

  /// Running count of consecutive compaction failures (circuit breaker).
  int _consecutiveFailures = 0;

  /// Create a [CompactionService] backed by the given [provider].
  CompactionService({required this.provider});

  // ── Phase 1: Microcompaction ──────────────────────────────────────────

  /// Lightweight pre-API clearing of old tool results.
  ///
  /// Keeps the last [keepRecent] tool-result-bearing messages intact and
  /// replaces older compactable tool results with [clearedMessage].
  /// This is a cheap way to reclaim tokens without an API round-trip.
  List<Message> microcompact(List<Message> messages, {int keepRecent = 5}) {
    final result = List<Message>.from(messages);
    final toolResultIndices = <int>[];

    for (int i = 0; i < result.length; i++) {
      final msg = result[i];
      if (msg.role != MessageRole.user) continue;
      for (final block in msg.content) {
        if (block is ToolResultBlock) {
          toolResultIndices.add(i);
          break;
        }
      }
    }

    if (toolResultIndices.length <= keepRecent) return result;

    final toClear = toolResultIndices.sublist(
      0,
      toolResultIndices.length - keepRecent,
    );

    for (final idx in toClear) {
      final msg = result[idx];
      final clearedContent =
          msg.content.map((block) {
            if (block is ToolResultBlock && _isCompactable(block)) {
              return ToolResultBlock(
                toolUseId: block.toolUseId,
                content: clearedMessage,
                isError: block.isError,
              );
            }
            return block;
          }).toList();

      result[idx] = Message(
        id: msg.id,
        role: msg.role,
        content: clearedContent,
        stopReason: msg.stopReason,
        usage: msg.usage,
      );
    }

    return result;
  }

  /// Whether a tool result block can be safely cleared.
  bool _isCompactable(ToolResultBlock block) {
    // All tool results are compactable for now; could filter by tool name.
    return true;
  }

  // ── Phase 2: Auto-compact trigger ─────────────────────────────────────

  /// Returns `true` when [messages] exceed the auto-compact threshold.
  ///
  /// The threshold is [contextWindow] minus [autocompactBufferTokens].
  /// The circuit breaker trips after [maxConsecutiveFailures] consecutive
  /// failures to prevent infinite retry loops.
  bool shouldAutoCompact(
    List<Message> messages, {
    int contextWindow = 200000,
  }) {
    if (_consecutiveFailures >= maxConsecutiveFailures) return false;

    final threshold = contextWindow - autocompactBufferTokens;
    final estimated = estimateTokenCount(messages);
    return estimated >= threshold;
  }

  /// Estimate token count for a list of [messages].
  ///
  /// Applies a conservative 4/3 padding factor to the raw estimate.
  int estimateTokenCount(List<Message> messages) {
    int total = 0;
    for (final msg in messages) {
      for (final block in msg.content) {
        total += _estimateBlockTokens(block);
      }
    }
    return (total * 4 / 3).ceil();
  }

  int _estimateBlockTokens(ContentBlock block) => switch (block) {
    TextBlock(text: final t) => _roughTokenCount(t),
    ToolUseBlock(name: final n, input: final i) =>
      _roughTokenCount(n) + _roughTokenCount(i.toString()),
    ToolResultBlock(content: final c) => _roughTokenCount(c),
    ImageBlock() => imageMaxTokenSize,
  };

  /// Rough token estimate: ~4 characters per token.
  int _roughTokenCount(String text) => (text.length / 4).ceil();

  // ── Phase 3: Full compaction ──────────────────────────────────────────

  /// Run full conversation compaction via summarization.
  ///
  /// Sends the conversation transcript to the LLM for summarization,
  /// then replaces messages with a compact summary message.
  /// Resets the failure counter on success; increments on failure.
  Future<CompactionResult> compactConversation({
    required List<Message> messages,
    required String systemPrompt,
    int contextWindow = 200000,
    bool isAutoCompact = false,
    String? customInstructions,
    bool suppressFollowUpQuestions = false,
    OnCompactProgress? onProgress,
  }) async {
    if (messages.isEmpty) {
      throw CompactionException(errorNotEnoughMessages);
    }

    final preTokenCount = estimateTokenCount(messages);
    final strategy =
        isAutoCompact ? CompactionStrategy.auto : CompactionStrategy.manual;

    onProgress?.call(
      const CompactProgressEvent(
        type: CompactProgressType.hooksStart,
        hookType: CompactHookType.preCompact,
      ),
    );

    onProgress?.call(
      const CompactProgressEvent(type: CompactProgressType.compactStart),
    );

    try {
      // Strip images from messages before summarization — images are not
      // needed for generating a summary and can cause prompt-too-long errors.
      final stripped = stripImagesFromMessages(messages);

      final summary = await _generateSummary(
        messages: stripped,
        systemPrompt: systemPrompt,
        customInstructions: customInstructions,
      );

      if (summary.isEmpty) {
        throw CompactionException(
          'Failed to generate conversation summary — response did not '
          'contain valid text content',
        );
      }

      final compactedMessages = [
        Message.user(
          _formatCompactSummary(summary, suppressFollowUpQuestions),
        ),
      ];

      _consecutiveFailures = 0;

      onProgress?.call(
        const CompactProgressEvent(
          type: CompactProgressType.hooksStart,
          hookType: CompactHookType.postCompact,
        ),
      );

      return CompactionResult(
        compactedMessages: compactedMessages,
        summary: summary,
        preCompactTokenCount: preTokenCount,
        postCompactTokenCount: estimateTokenCount(compactedMessages),
        strategy: strategy,
      );
    } catch (e) {
      _consecutiveFailures++;
      rethrow;
    } finally {
      onProgress?.call(
        const CompactProgressEvent(type: CompactProgressType.compactEnd),
      );
    }
  }

  /// Partial compaction around a selected message index.
  ///
  /// [direction] controls which side of the pivot is summarized:
  /// - [PartialCompactDirection.from]: summarizes *after* the pivot,
  ///   preserving earlier messages (preserves prompt cache).
  /// - [PartialCompactDirection.upTo]: summarizes *before* the pivot,
  ///   keeping later messages (invalidates prompt cache).
  Future<CompactionResult> partialCompactConversation({
    required List<Message> allMessages,
    required int pivotIndex,
    required String systemPrompt,
    String? userFeedback,
    PartialCompactDirection direction = PartialCompactDirection.from,
    OnCompactProgress? onProgress,
  }) async {
    final messagesToSummarize =
        direction == PartialCompactDirection.upTo
            ? allMessages.sublist(0, pivotIndex)
            : allMessages.sublist(pivotIndex);

    final messagesToKeep =
        direction == PartialCompactDirection.upTo
            ? allMessages.sublist(pivotIndex)
            : allMessages.sublist(0, pivotIndex);

    if (messagesToSummarize.isEmpty) {
      final desc =
          direction == PartialCompactDirection.upTo ? 'before' : 'after';
      throw CompactionException(
        'Nothing to summarize $desc the selected message.',
      );
    }

    final preTokenCount = estimateTokenCount(allMessages);

    onProgress?.call(
      const CompactProgressEvent(
        type: CompactProgressType.hooksStart,
        hookType: CompactHookType.preCompact,
      ),
    );
    onProgress?.call(
      const CompactProgressEvent(type: CompactProgressType.compactStart),
    );

    try {
      final stripped = stripImagesFromMessages(messagesToSummarize);

      final String? customInstructions =
          userFeedback != null ? 'User context: $userFeedback' : null;

      final summary = await _generateSummary(
        messages: stripped,
        systemPrompt: systemPrompt,
        customInstructions: customInstructions,
      );

      if (summary.isEmpty) {
        throw CompactionException(
          'Failed to generate conversation summary — response did not '
          'contain valid text content',
        );
      }

      final summaryMsg = Message.user(
        _formatCompactSummary(summary, false),
      );

      // Build the compacted messages in the correct order.
      final List<Message> compactedMessages;
      if (direction == PartialCompactDirection.upTo) {
        compactedMessages = [summaryMsg, ...messagesToKeep];
      } else {
        compactedMessages = [...messagesToKeep, summaryMsg];
      }

      _consecutiveFailures = 0;

      onProgress?.call(
        const CompactProgressEvent(
          type: CompactProgressType.hooksStart,
          hookType: CompactHookType.postCompact,
        ),
      );

      return CompactionResult(
        compactedMessages: compactedMessages,
        summary: summary,
        preCompactTokenCount: preTokenCount,
        postCompactTokenCount: estimateTokenCount(compactedMessages),
        strategy: CompactionStrategy.manual,
        messagesToKeep: messagesToKeep,
      );
    } catch (e) {
      _consecutiveFailures++;
      rethrow;
    } finally {
      onProgress?.call(
        const CompactProgressEvent(type: CompactProgressType.compactEnd),
      );
    }
  }

  /// Auto-compact if needed. Returns `null` when no compaction was needed.
  Future<CompactionResult?> autoCompactIfNeeded({
    required List<Message> messages,
    required String systemPrompt,
    int contextWindow = 200000,
  }) async {
    if (!shouldAutoCompact(messages, contextWindow: contextWindow)) {
      return null;
    }

    return compactConversation(
      messages: messages,
      systemPrompt: systemPrompt,
      contextWindow: contextWindow,
      isAutoCompact: true,
    );
  }

  // ── Summary generation ────────────────────────────────────────────────

  Future<String> _generateSummary({
    required List<Message> messages,
    required String systemPrompt,
    String? customInstructions,
  }) async {
    final compactPrompt = _buildCompactPrompt(messages, customInstructions);

    final response = await provider.createMessage(
      messages: [Message.user(compactPrompt)],
      systemPrompt: _compactSystemPrompt,
      maxTokens: compactMaxOutputTokens,
    );

    return response.textContent;
  }

  String _buildCompactPrompt(
    List<Message> messages,
    String? customInstructions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('Summarize this conversation transcript concisely.');
    buffer.writeln('Focus on:');
    buffer.writeln('1. User intent and goals');
    buffer.writeln('2. Key technical concepts and decisions');
    buffer.writeln('3. Important files and code discussed');
    buffer.writeln('4. Errors encountered and how they were resolved');
    buffer.writeln('5. Current problem-solving approach');
    buffer.writeln('6. Key user messages and preferences');
    buffer.writeln('7. Pending tasks and next steps');

    if (customInstructions != null && customInstructions.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('Additional instructions:');
      buffer.writeln(customInstructions);
    }

    buffer.writeln();
    buffer.writeln('Transcript:');
    buffer.writeln();

    for (final msg in messages) {
      final role = msg.role == MessageRole.user ? 'User' : 'Assistant';
      final text = msg.textContent;
      if (text.isNotEmpty) {
        buffer.writeln('$role: $text');
        buffer.writeln();
      }

      for (final block in msg.content) {
        switch (block) {
          case ToolUseBlock(name: final name):
            buffer.writeln('[$role used tool: $name]');
          case ToolResultBlock(content: final content, isError: final err):
            if (content != clearedMessage) {
              final preview =
                  content.length > 500
                      ? '${content.substring(0, 500)}...'
                      : content;
              buffer.writeln('[Tool result${err ? ' (ERROR)' : ''}: $preview]');
            }
          default:
            break;
        }
      }
    }

    return buffer.toString();
  }

  String _formatCompactSummary(
    String summary,
    bool suppressFollowUpQuestions,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('[Conversation compacted. Summary of prior context:]');
    buffer.writeln();
    buffer.write(summary);

    if (suppressFollowUpQuestions) {
      buffer.writeln();
      buffer.writeln();
      buffer.write(
        'Do not ask follow-up questions — continue with the current task.',
      );
    }

    return buffer.toString();
  }

  static const String _compactSystemPrompt = '''
You are a conversation summarizer. Your task is to create a concise but comprehensive summary of a coding conversation.

IMPORTANT: Respond with ONLY the summary text. Do NOT use any tools. Do NOT include any XML tags.

Your summary should preserve:
- The user's original intent and goals
- Key technical decisions made
- Important file paths and code structures discussed
- Any errors and their resolutions
- The current approach being taken
- Pending work and next steps

Be concise but thorough. The summary will replace the full conversation to free up context space.''';

  // ── Prompt-too-long retry helpers ─────────────────────────────────────

  /// Drops the oldest API-round groups from [messages] until [tokenGap]
  /// is covered. Returns `null` when nothing can be dropped without
  /// leaving an empty summarize set.
  ///
  /// This is the last-resort escape hatch when the compact request itself
  /// hits prompt-too-long — dropping the oldest context is lossy but
  /// unblocks the user.
  static List<Message>? truncateHeadForPtlRetry(
    List<Message> messages,
    int? tokenGap,
  ) {
    if (messages.length < 2) return null;

    // Group messages into API round pairs (user + assistant).
    final groups = _groupMessagesByApiRound(messages);
    if (groups.length < 2) return null;

    int dropCount;
    if (tokenGap != null && tokenGap > 0) {
      int acc = 0;
      dropCount = 0;
      for (final group in groups) {
        acc += _roughTokenCountForMessages(group);
        dropCount++;
        if (acc >= tokenGap) break;
      }
    } else {
      dropCount = max(1, (groups.length * 0.2).floor());
    }

    // Keep at least one group so there is something to summarize.
    dropCount = min(dropCount, groups.length - 1);
    if (dropCount < 1) return null;

    final sliced = groups.sublist(dropCount).expand((g) => g).toList();

    // If the first remaining message is an assistant message, prepend a
    // synthetic user marker so the API does not reject it.
    if (sliced.isNotEmpty && sliced.first.role == MessageRole.assistant) {
      return [Message.user(ptlRetryMarker), ...sliced];
    }
    return sliced;
  }

  /// Groups messages into API round pairs for truncation.
  static List<List<Message>> _groupMessagesByApiRound(List<Message> messages) {
    final groups = <List<Message>>[];
    List<Message> current = [];

    for (final msg in messages) {
      if (msg.role == MessageRole.user && current.isNotEmpty) {
        groups.add(current);
        current = [];
      }
      current.add(msg);
    }
    if (current.isNotEmpty) groups.add(current);

    return groups;
  }

  static int _roughTokenCountForMessages(List<Message> messages) {
    int total = 0;
    for (final msg in messages) {
      for (final block in msg.content) {
        total += switch (block) {
          TextBlock(text: final t) => (t.length / 4).ceil(),
          ToolUseBlock(name: final n, input: final i) =>
            (n.length / 4).ceil() + (i.toString().length / 4).ceil(),
          ToolResultBlock(content: final c) => (c.length / 4).ceil(),
          ImageBlock() => imageMaxTokenSize,
        };
      }
    }
    return total;
  }
}

// ============================================================================
// Utility functions
// ============================================================================

/// Strip image and document blocks from user messages before compaction.
///
/// Images are not needed for generating a conversation summary and can
/// cause the compaction API call itself to hit the prompt-too-long limit.
/// Replaces image blocks with a text marker so the summary still notes
/// that an image was shared.
List<Message> stripImagesFromMessages(List<Message> messages) {
  return messages.map((message) {
    if (message.role != MessageRole.user) return message;

    bool hasMediaBlock = false;
    final newContent = <ContentBlock>[];

    for (final block in message.content) {
      if (block is ImageBlock) {
        hasMediaBlock = true;
        newContent.add(const TextBlock('[image]'));
      } else if (block is ToolResultBlock) {
        // Tool results are text-only in our model, so pass through.
        newContent.add(block);
      } else {
        newContent.add(block);
      }
    }

    if (!hasMediaBlock) return message;

    return Message(
      id: message.id,
      role: message.role,
      content: newContent,
      stopReason: message.stopReason,
      usage: message.usage,
    );
  }).toList();
}

/// Strip attachment types that are re-injected post-compaction anyway.
///
/// Skill discovery/listing attachments are re-surfaced on the next turn,
/// so feeding them to the summarizer wastes tokens and pollutes the
/// summary with stale skill suggestions.
List<Message> stripReinjectedAttachments(List<Message> messages) {
  // In the current Dart model, attachment messages are not a distinct
  // type; this is a placeholder for future expansion.
  return messages;
}

/// Merge user-supplied custom instructions with hook-provided instructions.
///
/// User instructions come first; hook instructions are appended.
/// Empty strings normalize to `null`.
String? mergeHookInstructions(
  String? userInstructions,
  String? hookInstructions,
) {
  final user = (userInstructions?.isNotEmpty ?? false) ? userInstructions : null;
  final hook = (hookInstructions?.isNotEmpty ?? false) ? hookInstructions : null;

  if (hook == null) return user;
  if (user == null) return hook;
  return '$user\n\n$hook';
}

/// Build the ordered post-compact messages from a [CompactionResult].
///
/// Ensures consistent ordering across all compaction paths:
/// summary messages, then preserved messages.
List<Message> buildPostCompactMessages(CompactionResult result) {
  return [
    ...result.compactedMessages,
    if (result.messagesToKeep != null) ...result.messagesToKeep!,
  ];
}

// ============================================================================
// Exceptions
// ============================================================================

/// Exception thrown when compaction fails.
class CompactionException implements Exception {
  /// Human-readable error description.
  final String message;

  const CompactionException(this.message);

  @override
  String toString() => 'CompactionException: $message';
}
