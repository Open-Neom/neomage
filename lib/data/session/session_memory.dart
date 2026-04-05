// Session memory service — port of neomage/src/services/SessionMemory.
// Periodic background extraction of conversation notes into structured
// markdown, enabling context-aware compaction and session resume.

import 'package:neomage/core/platform/neomage_io.dart';

import '../../domain/models/message.dart';

/// Configuration for session memory extraction thresholds.
class SessionMemoryConfig {
  /// Minimum token count before first extraction.
  final int initThresholdTokens;

  /// Minimum tokens between subsequent extractions.
  final int updateThresholdTokens;

  /// Minimum tool calls between extractions.
  final int toolCallThreshold;

  /// Maximum tokens for extracted summary per section.
  final int maxSectionTokens;

  /// Maximum total tokens for the full summary.
  final int maxTotalTokens;

  const SessionMemoryConfig({
    this.initThresholdTokens = 10000,
    this.updateThresholdTokens = 5000,
    this.toolCallThreshold = 3,
    this.maxSectionTokens = 2000,
    this.maxTotalTokens = 12000,
  });
}

/// State tracking for session memory extraction.
class SessionMemoryState {
  /// ID of last message that was summarized.
  String? lastSummarizedMessageId;

  /// Whether extraction has been initialized.
  bool initialized = false;

  /// Whether an extraction is currently running.
  bool extractionInProgress = false;

  /// Total tokens seen since last extraction.
  int tokensSinceLastExtraction = 0;

  /// Total tool calls since last extraction.
  int toolCallsSinceLastExtraction = 0;

  /// Number of extractions completed this session.
  int extractionCount = 0;
}

/// Default session memory template sections.
const List<String> defaultTemplateSections = [
  'Task',
  'Current State',
  'Key Files',
  'Workflow',
  'Errors & Fixes',
  'Technical Decisions',
  'User Preferences',
  'Pending Items',
  'Dependencies',
  'Notes',
];

/// Session memory service — manages background extraction of conversation
/// notes into a structured summary file.
class SessionMemoryService {
  final SessionMemoryConfig config;
  final SessionMemoryState _state = SessionMemoryState();
  final String sessionId;
  final String projectDir;

  SessionMemoryService({
    required this.sessionId,
    required this.projectDir,
    this.config = const SessionMemoryConfig(),
  });

  /// Path to the session memory file.
  String get summaryPath => '$projectDir/$sessionId/session-memory/summary.md';

  /// Whether extraction should be triggered based on current state.
  bool shouldExtract() {
    if (_state.extractionInProgress) return false;

    if (!_state.initialized) {
      return _state.tokensSinceLastExtraction >= config.initThresholdTokens;
    }

    return _state.tokensSinceLastExtraction >= config.updateThresholdTokens &&
        _state.toolCallsSinceLastExtraction >= config.toolCallThreshold;
  }

  /// Track a new message for extraction threshold tracking.
  void trackMessage(Message message) {
    // Rough token estimate
    final tokens = message.content.fold<int>(0, (sum, block) {
      return sum +
          switch (block) {
            TextBlock(text: final t) => (t.length / 4).ceil(),
            ToolUseBlock(name: final n, input: final i) =>
              (n.length / 4).ceil() + (i.toString().length / 4).ceil(),
            ToolResultBlock(content: final c) => (c.length / 4).ceil(),
            ImageBlock() => 2000,
          };
    });

    _state.tokensSinceLastExtraction += tokens;

    // Count tool calls
    final toolUses = message.toolUses.length;
    _state.toolCallsSinceLastExtraction += toolUses;
  }

  /// Extract session memory from conversation messages.
  /// Returns the extracted markdown summary.
  Future<String> extract(List<Message> messages) async {
    _state.extractionInProgress = true;

    try {
      final summary = _buildSummary(messages);

      // Write to disk
      final file = File(summaryPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(summary);

      // Update state
      if (messages.isNotEmpty) {
        _state.lastSummarizedMessageId = messages.last.id;
      }
      _state.initialized = true;
      _state.tokensSinceLastExtraction = 0;
      _state.toolCallsSinceLastExtraction = 0;
      _state.extractionCount++;

      return summary;
    } finally {
      _state.extractionInProgress = false;
    }
  }

  /// Load existing session memory from disk.
  Future<String?> load() async {
    final file = File(summaryPath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Get the index of the last summarized message in a list.
  /// Returns -1 if no message has been summarized.
  int getLastSummarizedIndex(List<Message> messages) {
    final id = _state.lastSummarizedMessageId;
    if (id == null) return -1;
    return messages.indexWhere((m) => m.id == id);
  }

  /// Get unsummarized messages (those after lastSummarizedMessageId).
  List<Message> getUnsummarizedMessages(List<Message> messages) {
    final idx = getLastSummarizedIndex(messages);
    if (idx == -1) return messages;
    return messages.sublist(idx + 1);
  }

  /// Current extraction state (read-only).
  ({
    bool initialized,
    bool inProgress,
    int tokensSinceLast,
    int toolCallsSinceLast,
    int extractionCount,
    String? lastSummarizedId,
  })
  get state => (
    initialized: _state.initialized,
    inProgress: _state.extractionInProgress,
    tokensSinceLast: _state.tokensSinceLastExtraction,
    toolCallsSinceLast: _state.toolCallsSinceLastExtraction,
    extractionCount: _state.extractionCount,
    lastSummarizedId: _state.lastSummarizedMessageId,
  );

  // ── Private ──

  String _buildSummary(List<Message> messages) {
    final buffer = StringBuffer();
    buffer.writeln('# Session Memory');
    buffer.writeln();
    buffer.writeln('Session: $sessionId');
    buffer.writeln('Updated: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Messages: ${messages.length}');
    buffer.writeln();

    // Build sections from conversation analysis
    for (final section in defaultTemplateSections) {
      buffer.writeln('## $section');
      buffer.writeln();
      final content = _extractSectionContent(section, messages);
      if (content.isNotEmpty) {
        buffer.writeln(content);
      } else {
        buffer.writeln('(no data)');
      }
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _extractSectionContent(String section, List<Message> messages) {
    // Simple extraction — for full LLM-powered extraction, this would
    // call the API with a specialized prompt. This is the local fallback.
    switch (section) {
      case 'Key Files':
        return _extractFileReferences(messages);
      case 'Errors & Fixes':
        return _extractErrors(messages);
      default:
        return '';
    }
  }

  String _extractFileReferences(List<Message> messages) {
    final files = <String>{};
    final filePattern = RegExp(r'(?:^|[\s"])([/~]\S+\.\w+)');

    for (final msg in messages) {
      final text = msg.textContent;
      for (final match in filePattern.allMatches(text)) {
        files.add(match.group(1)!);
      }
    }

    if (files.isEmpty) return '';
    return files.take(20).map((f) => '- `$f`').join('\n');
  }

  String _extractErrors(List<Message> messages) {
    final errors = <String>[];

    for (final msg in messages) {
      for (final block in msg.content) {
        if (block is ToolResultBlock && block.isError) {
          final preview = block.content.length > 200
              ? '${block.content.substring(0, 200)}...'
              : block.content;
          errors.add('- $preview');
        }
      }
    }

    if (errors.isEmpty) return '';
    return errors.take(10).join('\n');
  }
}
