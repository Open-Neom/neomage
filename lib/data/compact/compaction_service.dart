// Context compaction service — ported from OpenClaude src/services/compact/.
// Three-phase system: microcompact → auto-compact → full compaction.

import '../../domain/models/message.dart';
import '../api/api_provider.dart';

/// Tools whose results can be safely cleared during microcompaction.
const Set<String> compactableTools = {
  'Read', 'Bash', 'Grep', 'Glob', 'WebSearch', 'WebFetch', 'Edit', 'Write',
};

/// Cleared content replacement marker.
const String clearedMessage = '[Old tool result content cleared]';

/// Flat token estimate for images.
const int imageMaxTokenSize = 2000;

/// Buffer tokens subtracted from context window for auto-compact threshold.
const int autocompactBufferTokens = 13000;

/// Max output tokens for summary generation.
const int maxOutputTokensForSummary = 20000;

/// Max prompt-too-long retries.
const int maxPtlRetries = 3;

/// Max consecutive compact failures before circuit breaker.
const int maxConsecutiveFailures = 3;

/// Result of a compaction operation.
class CompactionResult {
  final List<Message> compactedMessages;
  final String? summary;
  final int preCompactTokenCount;
  final int postCompactTokenCount;

  const CompactionResult({
    required this.compactedMessages,
    this.summary,
    required this.preCompactTokenCount,
    required this.postCompactTokenCount,
  });
}

/// Context compaction service.
class CompactionService {
  final ApiProvider provider;
  int _consecutiveFailures = 0;

  CompactionService({required this.provider});

  // ── Phase 1: Microcompaction ──

  /// Lightweight pre-API clearing of old tool results.
  /// Keeps the last [keepRecent] tool results intact.
  List<Message> microcompact(List<Message> messages, {int keepRecent = 5}) {
    final result = List<Message>.from(messages);
    final toolResultIndices = <int>[];

    // Find all tool result blocks across messages
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

    // Clear all but the last keepRecent tool result messages
    if (toolResultIndices.length <= keepRecent) return result;

    final toClear = toolResultIndices.sublist(
      0,
      toolResultIndices.length - keepRecent,
    );

    for (final idx in toClear) {
      final msg = result[idx];
      final clearedContent = msg.content.map((block) {
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

  bool _isCompactable(ToolResultBlock block) {
    // All tool results are compactable for now
    return true;
  }

  // ── Phase 2: Auto-compact trigger ──

  /// Check if messages exceed the auto-compact threshold.
  bool shouldAutoCompact(List<Message> messages, {int contextWindow = 200000}) {
    if (_consecutiveFailures >= maxConsecutiveFailures) return false;

    final threshold = contextWindow - autocompactBufferTokens;
    final estimated = estimateTokenCount(messages);
    return estimated >= threshold;
  }

  /// Estimate token count for a list of messages.
  int estimateTokenCount(List<Message> messages) {
    int total = 0;
    for (final msg in messages) {
      for (final block in msg.content) {
        total += _estimateBlockTokens(block);
      }
    }
    // Conservative 4/3 padding factor
    return (total * 4 / 3).ceil();
  }

  int _estimateBlockTokens(ContentBlock block) => switch (block) {
        TextBlock(text: final t) => _roughTokenCount(t),
        ToolUseBlock(name: final n, input: final i) =>
          _roughTokenCount(n) + _roughTokenCount(i.toString()),
        ToolResultBlock(content: final c) => _roughTokenCount(c),
        ImageBlock() => imageMaxTokenSize,
      };

  /// Rough token estimate: ~4 chars per token.
  int _roughTokenCount(String text) => (text.length / 4).ceil();

  // ── Phase 3: Full compaction ──

  /// Run full conversation compaction via summarization.
  Future<CompactionResult> compactConversation({
    required List<Message> messages,
    required String systemPrompt,
    int contextWindow = 200000,
  }) async {
    final preTokenCount = estimateTokenCount(messages);

    try {
      final summary = await _generateSummary(
        messages: messages,
        systemPrompt: systemPrompt,
      );

      final compactedMessages = [
        Message.user(_formatCompactSummary(summary)),
      ];

      _consecutiveFailures = 0;

      return CompactionResult(
        compactedMessages: compactedMessages,
        summary: summary,
        preCompactTokenCount: preTokenCount,
        postCompactTokenCount: estimateTokenCount(compactedMessages),
      );
    } catch (e) {
      _consecutiveFailures++;
      rethrow;
    }
  }

  /// Auto-compact if needed. Returns null if no compaction was needed.
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
    );
  }

  Future<String> _generateSummary({
    required List<Message> messages,
    required String systemPrompt,
  }) async {
    final compactPrompt = _buildCompactPrompt(messages);

    final response = await provider.createMessage(
      messages: [Message.user(compactPrompt)],
      systemPrompt: _compactSystemPrompt,
      maxTokens: maxOutputTokensForSummary,
    );

    return response.textContent;
  }

  String _buildCompactPrompt(List<Message> messages) {
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
              final preview = content.length > 500
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

  String _formatCompactSummary(String summary) {
    return '[Conversation compacted. Summary of prior context:]\n\n$summary';
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
}
