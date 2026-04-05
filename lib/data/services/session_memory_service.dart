// Session memory service — port of neomage/src/services/SessionMemory/.
// Automatically maintains a markdown file with notes about the current
// conversation. Runs periodically in the background using a forked subagent
// to extract key information without interrupting the main conversation flow.

import 'dart:async';

import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Configuration
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for session memory extraction thresholds.
class SessionMemoryConfig {
  /// Minimum context window tokens before initialising session memory.
  /// Uses the same token counting as autocompact (input + output + cache tokens).
  final int minimumMessageTokensToInit;

  /// Minimum context window growth (in tokens) between session memory updates.
  final int minimumTokensBetweenUpdate;

  /// Number of tool calls between session memory updates.
  final int toolCallsBetweenUpdates;

  const SessionMemoryConfig({
    this.minimumMessageTokensToInit = 10000,
    this.minimumTokensBetweenUpdate = 5000,
    this.toolCallsBetweenUpdates = 3,
  });

  SessionMemoryConfig copyWith({
    int? minimumMessageTokensToInit,
    int? minimumTokensBetweenUpdate,
    int? toolCallsBetweenUpdates,
  }) => SessionMemoryConfig(
    minimumMessageTokensToInit:
        minimumMessageTokensToInit ?? this.minimumMessageTokensToInit,
    minimumTokensBetweenUpdate:
        minimumTokensBetweenUpdate ?? this.minimumTokensBetweenUpdate,
    toolCallsBetweenUpdates:
        toolCallsBetweenUpdates ?? this.toolCallsBetweenUpdates,
  );

  factory SessionMemoryConfig.fromRemote(Map<String, dynamic> json) {
    return SessionMemoryConfig(
      minimumMessageTokensToInit:
          (json['minimumMessageTokensToInit'] as int?) ?? 10000,
      minimumTokensBetweenUpdate:
          (json['minimumTokensBetweenUpdate'] as int?) ?? 5000,
      toolCallsBetweenUpdates: (json['toolCallsBetweenUpdates'] as int?) ?? 3,
    );
  }
}

/// Default session memory configuration.
const defaultSessionMemoryConfig = SessionMemoryConfig();

// ═══════════════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════════════

const _maxSectionLength = 2000;
const _maxTotalSessionMemoryTokens = 12000;
const _extractionWaitTimeoutMs = 15000;
const _extractionStaleThresholdMs = 60000;

// ═══════════════════════════════════════════════════════════════════════════
// Default template
// ═══════════════════════════════════════════════════════════════════════════

/// Default session memory template with sections for structured note-taking.
const defaultSessionMemoryTemplate = '''
# Session Title
_A short and distinctive 5-10 word descriptive title for the session. Super info dense, no filler_

# Current State
_What is actively being worked on right now? Pending tasks not yet completed. Immediate next steps._

# Task specification
_What did the user ask to build? Any design decisions or other explanatory context_

# Files and Functions
_What are the important files? In short, what do they contain and why are they relevant?_

# Workflow
_What bash commands are usually run and in what order? How to interpret their output if not obvious?_

# Errors & Corrections
_Errors encountered and how they were fixed. What did the user correct? What approaches failed and should not be tried again?_

# Codebase and System Documentation
_What are the important system components? How do they work/fit together?_

# Learnings
_What has worked well? What has not? What to avoid? Do not duplicate items from other sections_

# Key results
_If the user asked a specific output such as an answer to a question, a table, or other document, repeat the exact result here_

# Worklog
_Step by step, what was attempted, done? Very terse summary for each step_
''';

// ═══════════════════════════════════════════════════════════════════════════
// Simple message model for the service
// ═══════════════════════════════════════════════════════════════════════════

/// Simplified message for session memory processing.
class SessionMessage {
  final String uuid;
  final String type; // 'user', 'assistant', 'system'
  final List<SessionMessageBlock> content;
  final int? inputTokens;
  final int? outputTokens;
  final int? cacheReadInputTokens;
  final int? cacheCreationInputTokens;

  const SessionMessage({
    required this.uuid,
    required this.type,
    this.content = const [],
    this.inputTokens,
    this.outputTokens,
    this.cacheReadInputTokens,
    this.cacheCreationInputTokens,
  });
}

/// A block within a session message.
class SessionMessageBlock {
  final String type; // 'text', 'tool_use', 'tool_result'
  final String? text;
  final String? toolName;

  const SessionMessageBlock({required this.type, this.text, this.toolName});
}

// ═══════════════════════════════════════════════════════════════════════════
// Token estimation
// ═══════════════════════════════════════════════════════════════════════════

/// Rough token count estimation (same heuristic as TS: length / 4).
int roughTokenCountEstimation(String text) {
  return (text.length / 4).ceil();
}

/// Estimate total token count across messages.
int tokenCountWithEstimation(List<SessionMessage> messages) {
  var total = 0;
  for (final msg in messages) {
    total += msg.inputTokens ?? 0;
    total += msg.outputTokens ?? 0;
    total += msg.cacheReadInputTokens ?? 0;
    total += msg.cacheCreationInputTokens ?? 0;
  }
  // Fallback: if no token info, estimate from content.
  if (total == 0) {
    for (final msg in messages) {
      for (final block in msg.content) {
        if (block.text != null) {
          total += roughTokenCountEstimation(block.text!);
        }
      }
    }
  }
  return total;
}

// ═══════════════════════════════════════════════════════════════════════════
// Section analysis
// ═══════════════════════════════════════════════════════════════════════════

/// Parse the session memory file and analyse section sizes.
Map<String, int> analyzeSectionSizes(String content) {
  final sections = <String, int>{};
  final lines = content.split('\n');
  var currentSection = '';
  final currentContent = <String>[];

  for (final line in lines) {
    if (line.startsWith('# ')) {
      if (currentSection.isNotEmpty && currentContent.isNotEmpty) {
        final sectionContent = currentContent.join('\n').trim();
        sections[currentSection] = roughTokenCountEstimation(sectionContent);
      }
      currentSection = line;
      currentContent.clear();
    } else {
      currentContent.add(line);
    }
  }

  if (currentSection.isNotEmpty && currentContent.isNotEmpty) {
    final sectionContent = currentContent.join('\n').trim();
    sections[currentSection] = roughTokenCountEstimation(sectionContent);
  }

  return sections;
}

/// Generate reminders for sections that are too long.
String generateSectionReminders(
  Map<String, int> sectionSizes,
  int totalTokens,
) {
  final overBudget = totalTokens > _maxTotalSessionMemoryTokens;
  final oversizedSections =
      sectionSizes.entries.where((e) => e.value > _maxSectionLength).toList()
        ..sort((a, b) => b.value.compareTo(a.value));
  final oversizedLines = oversizedSections
      .map(
        (e) => '- "${e.key}" is ~${e.value} tokens (limit: $_maxSectionLength)',
      )
      .toList();

  if (oversizedLines.isEmpty && !overBudget) return '';

  final parts = <String>[];

  if (overBudget) {
    parts.add(
      '\n\nCRITICAL: The session memory file is currently ~$totalTokens tokens, '
      'which exceeds the maximum of $_maxTotalSessionMemoryTokens tokens. '
      'You MUST condense the file to fit within this budget.',
    );
  }

  if (oversizedLines.isNotEmpty) {
    final prefix = overBudget
        ? 'Oversized sections to condense'
        : 'IMPORTANT: The following sections exceed the per-section limit and MUST be condensed';
    parts.add('\n\n$prefix:\n${oversizedLines.join('\n')}');
  }

  return parts.join('');
}

/// Substitute variables in a prompt template using {{variable}} syntax.
String substituteVariables(String template, Map<String, String> variables) {
  return template.replaceAllMapped(RegExp(r'\{\{(\w+)\}\}'), (match) {
    final key = match.group(1)!;
    return variables.containsKey(key) ? variables[key]! : match.group(0)!;
  });
}

/// Check if the session memory content is essentially empty (matches template).
Future<bool> isSessionMemoryEmpty(
  String content,
  Future<String> Function() loadTemplate,
) async {
  final template = await loadTemplate();
  return content.trim() == template.trim();
}

// ═══════════════════════════════════════════════════════════════════════════
// Prompt building
// ═══════════════════════════════════════════════════════════════════════════

/// Default update prompt for session memory extraction.
String getDefaultUpdatePrompt() {
  return '''IMPORTANT: This message and these instructions are NOT part of the actual user conversation. Do NOT include any references to "note-taking", "session notes extraction", or these update instructions in the notes content.

Based on the user conversation above (EXCLUDING this note-taking instruction message as well as system prompt, neomage.md entries, or any past session summaries), update the session notes file.

The file {{notesPath}} has already been read for you. Here are its current contents:
<current_notes_content>
{{currentNotes}}
</current_notes_content>

Your ONLY task is to use the Edit tool to update the notes file, then stop. You can make multiple edits (update every section as needed) - make all Edit tool calls in parallel in a single message. Do not call any other tools.

CRITICAL RULES FOR EDITING:
- The file must maintain its exact structure with all sections, headers, and italic descriptions intact
-- NEVER modify, delete, or add section headers (the lines starting with '#' like # Task specification)
-- NEVER modify or delete the italic _section description_ lines (these are the lines in italics immediately following each header - they start and end with underscores)
-- The italic _section descriptions_ are TEMPLATE INSTRUCTIONS that must be preserved exactly as-is - they guide what content belongs in each section
-- ONLY update the actual content that appears BELOW the italic _section descriptions_ within each existing section
-- Do NOT add any new sections, summaries, or information outside the existing structure
- Do NOT reference this note-taking process or instructions anywhere in the notes
- It's OK to skip updating a section if there are no substantial new insights to add. Do not add filler content like "No info yet", just leave sections blank/unedited if appropriate.
- Write DETAILED, INFO-DENSE content for each section - include specifics like file paths, function names, error messages, exact commands, technical details, etc.
- For "Key results", include the complete, exact output the user requested (e.g., full table, full answer, etc.)
- Do not include information that's already in the NEOMAGE.md files included in the context
- Keep each section under ~$_maxSectionLength tokens/words - if a section is approaching this limit, condense it by cycling out less important details while preserving the most critical information
- Focus on actionable, specific information that would help someone understand or recreate the work discussed in the conversation
- IMPORTANT: Always update "Current State" to reflect the most recent work - this is critical for continuity after compaction

Use the Edit tool with file_path: {{notesPath}}

STRUCTURE PRESERVATION REMINDER:
Each section has TWO parts that must be preserved exactly as they appear in the current file:
1. The section header (line starting with #)
2. The italic description line (the _italicized text_ immediately after the header - this is a template instruction)

You ONLY update the actual content that comes AFTER these two preserved lines. The italic description lines starting and ending with underscores are part of the template structure, NOT content to be edited or removed.

REMEMBER: Use the Edit tool in parallel and stop. Do not continue after the edits. Only include insights from the actual user conversation, never from these note-taking instructions. Do not delete or change section headers or italic _section descriptions_.''';
}

/// Build the session memory update prompt with section analysis.
Future<String> buildSessionMemoryUpdatePrompt(
  String currentNotes,
  String notesPath,
  Future<String> Function() loadPrompt,
) async {
  final promptTemplate = await loadPrompt();
  final sectionSizes = analyzeSectionSizes(currentNotes);
  final totalTokens = roughTokenCountEstimation(currentNotes);
  final sectionReminders = generateSectionReminders(sectionSizes, totalTokens);

  final variables = {'currentNotes': currentNotes, 'notesPath': notesPath};

  final basePrompt = substituteVariables(promptTemplate, variables);
  return basePrompt + sectionReminders;
}

// ═══════════════════════════════════════════════════════════════════════════
// Session section truncation for compact
// ═══════════════════════════════════════════════════════════════════════════

/// Result of truncating session memory for compact.
class TruncationResult {
  final String truncatedContent;
  final bool wasTruncated;

  const TruncationResult({
    required this.truncatedContent,
    required this.wasTruncated,
  });
}

/// Truncate session memory sections that exceed the per-section token limit.
/// Used when inserting session memory into compact messages.
TruncationResult truncateSessionMemoryForCompact(String content) {
  final lines = content.split('\n');
  final maxCharsPerSection = _maxSectionLength * 4;
  final outputLines = <String>[];
  final currentSectionLines = <String>[];
  var currentSectionHeader = '';
  var wasTruncated = false;

  for (final line in lines) {
    if (line.startsWith('# ')) {
      final result = _flushSessionSection(
        currentSectionHeader,
        currentSectionLines,
        maxCharsPerSection,
      );
      outputLines.addAll(result.lines);
      wasTruncated = wasTruncated || result.wasTruncated;
      currentSectionHeader = line;
      currentSectionLines.clear();
    } else {
      currentSectionLines.add(line);
    }
  }

  // Flush the last section.
  final result = _flushSessionSection(
    currentSectionHeader,
    currentSectionLines,
    maxCharsPerSection,
  );
  outputLines.addAll(result.lines);
  wasTruncated = wasTruncated || result.wasTruncated;

  return TruncationResult(
    truncatedContent: outputLines.join('\n'),
    wasTruncated: wasTruncated,
  );
}

class _FlushResult {
  final List<String> lines;
  final bool wasTruncated;
  const _FlushResult({required this.lines, required this.wasTruncated});
}

_FlushResult _flushSessionSection(
  String sectionHeader,
  List<String> sectionLines,
  int maxCharsPerSection,
) {
  if (sectionHeader.isEmpty) {
    return _FlushResult(lines: List.from(sectionLines), wasTruncated: false);
  }

  final sectionContent = sectionLines.join('\n');
  if (sectionContent.length <= maxCharsPerSection) {
    return _FlushResult(
      lines: [sectionHeader, ...sectionLines],
      wasTruncated: false,
    );
  }

  var charCount = 0;
  final keptLines = <String>[sectionHeader];
  for (final line in sectionLines) {
    if (charCount + line.length + 1 > maxCharsPerSection) break;
    keptLines.add(line);
    charCount += line.length + 1;
  }
  keptLines.add('\n[... section truncated for length ...]');
  return _FlushResult(lines: keptLines, wasTruncated: true);
}

// ═══════════════════════════════════════════════════════════════════════════
// Session memory state (utility module)
// ═══════════════════════════════════════════════════════════════════════════

/// Mutable session memory state — tracks extraction lifecycle, thresholds,
/// and the last summarised message.
class SessionMemoryState {
  SessionMemoryConfig config;
  String? lastSummarizedMessageId;
  int tokensAtLastExtraction;
  bool initialized;
  DateTime? _extractionStartedAt;

  SessionMemoryState({
    SessionMemoryConfig? config,
    this.lastSummarizedMessageId,
    this.tokensAtLastExtraction = 0,
    this.initialized = false,
  }) : config = config ?? const SessionMemoryConfig();

  /// Whether an extraction is currently in progress.
  bool get isExtracting => _extractionStartedAt != null;

  /// Mark extraction as started.
  void markExtractionStarted() {
    _extractionStartedAt = DateTime.now();
  }

  /// Mark extraction as completed.
  void markExtractionCompleted() {
    _extractionStartedAt = null;
  }

  /// Record the context size at the time of extraction.
  void recordExtractionTokenCount(int currentTokenCount) {
    tokensAtLastExtraction = currentTokenCount;
  }

  /// Check if session memory has been initialised.
  bool get isSessionMemoryInitialized => initialized;

  /// Mark session memory as initialised.
  void markInitialized() {
    initialized = true;
  }

  /// Check if we've met the threshold to initialise session memory.
  bool hasMetInitializationThreshold(int currentTokenCount) {
    return currentTokenCount >= config.minimumMessageTokensToInit;
  }

  /// Check if we've met the threshold for the next update.
  bool hasMetUpdateThreshold(int currentTokenCount) {
    final tokensSinceLast = currentTokenCount - tokensAtLastExtraction;
    return tokensSinceLast >= config.minimumTokensBetweenUpdate;
  }

  /// Get the configured number of tool calls between updates.
  int get toolCallsBetweenUpdates => config.toolCallsBetweenUpdates;

  /// Reset session memory state (useful for testing).
  void reset() {
    config = const SessionMemoryConfig();
    tokensAtLastExtraction = 0;
    initialized = false;
    lastSummarizedMessageId = null;
    _extractionStartedAt = null;
  }

  /// Wait for any in-progress extraction to complete (with timeout).
  Future<void> waitForExtraction() async {
    final startTime = DateTime.now();
    while (_extractionStartedAt != null) {
      final age = DateTime.now().difference(_extractionStartedAt!);
      if (age.inMilliseconds > _extractionStaleThresholdMs) return;
      if (DateTime.now().difference(startTime).inMilliseconds >
          _extractionWaitTimeoutMs) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Session memory controller
// ═══════════════════════════════════════════════════════════════════════════

/// Check if the last assistant turn in messages has tool calls.
bool hasToolCallsInLastAssistantTurn(List<SessionMessage> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i].type == 'assistant') {
      return messages[i].content.any((b) => b.type == 'tool_use');
    }
  }
  return false;
}

/// Count tool calls since a given message UUID.
int countToolCallsSince(List<SessionMessage> messages, String? sinceUuid) {
  var toolCallCount = 0;
  var foundStart = sinceUuid == null;

  for (final message in messages) {
    if (!foundStart) {
      if (message.uuid == sinceUuid) foundStart = true;
      continue;
    }
    if (message.type == 'assistant') {
      toolCallCount += message.content
          .where((b) => b.type == 'tool_use')
          .length;
    }
  }
  return toolCallCount;
}

/// Main session memory controller — manages the extraction lifecycle.
class SessionMemoryController extends SintController {
  /// The current state of session memory.
  final state = SessionMemoryState().obs;

  /// UUID of the last message used for memory extraction.
  String? _lastMemoryMessageUuid;

  /// Whether the gate check failure has been logged this session.
  bool _hasLoggedGateFailure = false;

  /// Whether config has been initialised from remote.
  bool _configInitialised = false;

  /// Feature gate check.
  final bool Function() isGateEnabled;

  /// Remote config getter.
  final Map<String, dynamic> Function() getRemoteConfig;

  /// Auto-compact enabled check.
  final bool Function() isAutoCompactEnabled;

  /// Remote mode check.
  final bool Function() isRemoteMode;

  /// Analytics event logger.
  final void Function(String eventName, Map<String, Object?> metadata) logEvent;

  /// File system helpers.
  final String Function() getSessionMemoryDir;
  final String Function() getSessionMemoryPath;

  /// Template and prompt loaders.
  final Future<String> Function() loadTemplate;
  final Future<String> Function() loadPrompt;

  /// File read/write helpers.
  final Future<String> Function(String path) readFile;
  final Future<void> Function(String path, String content) writeFile;
  final Future<void> Function(String path) mkdirRecursive;
  final Future<bool> Function(String path) fileExists;

  /// Forked agent runner for extraction.
  final Future<void> Function({
    required String prompt,
    required String memoryPath,
    required List<SessionMessage> contextMessages,
  })
  runExtractionAgent;

  SessionMemoryController({
    required this.isGateEnabled,
    required this.getRemoteConfig,
    required this.isAutoCompactEnabled,
    required this.isRemoteMode,
    required this.logEvent,
    required this.getSessionMemoryDir,
    required this.getSessionMemoryPath,
    required this.loadTemplate,
    required this.loadPrompt,
    required this.readFile,
    required this.writeFile,
    required this.mkdirRecursive,
    required this.fileExists,
    required this.runExtractionAgent,
  });

  /// Determine if session memory should be extracted now.
  bool shouldExtractMemory(List<SessionMessage> messages) {
    final currentTokenCount = tokenCountWithEstimation(messages);
    final s = state.value;

    if (!s.isSessionMemoryInitialized) {
      if (!s.hasMetInitializationThreshold(currentTokenCount)) return false;
      state.value.markInitialized();
    }

    final hasMetTokenThreshold = s.hasMetUpdateThreshold(currentTokenCount);
    final toolCallsSince = countToolCallsSince(
      messages,
      _lastMemoryMessageUuid,
    );
    final hasMetToolCallThreshold = toolCallsSince >= s.toolCallsBetweenUpdates;
    final hasToolCallsInLast = hasToolCallsInLastAssistantTurn(messages);

    final shouldExtract =
        (hasMetTokenThreshold && hasMetToolCallThreshold) ||
        (hasMetTokenThreshold && !hasToolCallsInLast);

    if (shouldExtract) {
      final lastMessage = messages.isNotEmpty ? messages.last : null;
      if (lastMessage?.uuid != null) {
        _lastMemoryMessageUuid = lastMessage!.uuid;
      }
      return true;
    }
    return false;
  }

  /// Initialise config from remote (lazy, only once).
  void _initConfigIfNeeded() {
    if (_configInitialised) return;
    _configInitialised = true;

    final remoteConfig = getRemoteConfig();
    final minimumInit = remoteConfig['minimumMessageTokensToInit'] as int?;
    final minimumUpdate = remoteConfig['minimumTokensBetweenUpdate'] as int?;
    final toolCalls = remoteConfig['toolCallsBetweenUpdates'] as int?;

    state.value.config = SessionMemoryConfig(
      minimumMessageTokensToInit: (minimumInit != null && minimumInit > 0)
          ? minimumInit
          : 10000,
      minimumTokensBetweenUpdate: (minimumUpdate != null && minimumUpdate > 0)
          ? minimumUpdate
          : 5000,
      toolCallsBetweenUpdates: (toolCalls != null && toolCalls > 0)
          ? toolCalls
          : 3,
    );
  }

  /// Set up the session memory file.
  Future<({String memoryPath, String currentMemory})> _setupFile() async {
    final dir = getSessionMemoryDir();
    await mkdirRecursive(dir);
    final memoryPath = getSessionMemoryPath();

    if (!await fileExists(memoryPath)) {
      final template = await loadTemplate();
      await writeFile(memoryPath, template);
    }

    final currentMemory = await readFile(memoryPath);
    logEvent('tengu_session_memory_file_read', {
      'content_length': currentMemory.length,
    });

    return (memoryPath: memoryPath, currentMemory: currentMemory);
  }

  /// Extract session memory — the main hook entry point.
  Future<void> extractSessionMemory(
    List<SessionMessage> messages,
    String querySource,
  ) async {
    // Only run on main REPL thread.
    if (querySource != 'repl_main_thread') return;

    // Check gate lazily.
    if (!isGateEnabled()) {
      if (!_hasLoggedGateFailure) {
        _hasLoggedGateFailure = true;
        logEvent('tengu_session_memory_gate_disabled', {});
      }
      return;
    }

    _initConfigIfNeeded();

    if (!shouldExtractMemory(messages)) return;

    state.value.markExtractionStarted();

    try {
      final setup = await _setupFile();
      final prompt = await buildSessionMemoryUpdatePrompt(
        setup.currentMemory,
        setup.memoryPath,
        loadPrompt,
      );

      await runExtractionAgent(
        prompt: prompt,
        memoryPath: setup.memoryPath,
        contextMessages: messages,
      );

      final lastMessage = messages.isNotEmpty ? messages.last : null;
      logEvent('tengu_session_memory_extraction', {
        'input_tokens': lastMessage?.inputTokens,
        'output_tokens': lastMessage?.outputTokens,
        'cache_read_input_tokens': lastMessage?.cacheReadInputTokens,
        'cache_creation_input_tokens': lastMessage?.cacheCreationInputTokens,
        'config_min_message_tokens_to_init':
            state.value.config.minimumMessageTokensToInit,
        'config_min_tokens_between_update':
            state.value.config.minimumTokensBetweenUpdate,
        'config_tool_calls_between_updates':
            state.value.config.toolCallsBetweenUpdates,
      });

      state.value.recordExtractionTokenCount(
        tokenCountWithEstimation(messages),
      );

      _updateLastSummarizedMessageIdIfSafe(messages);
    } finally {
      state.value.markExtractionCompleted();
    }
  }

  /// Manually trigger session memory extraction, bypassing threshold checks.
  Future<ManualExtractionResult> manuallyExtract(
    List<SessionMessage> messages,
  ) async {
    if (messages.isEmpty) {
      return const ManualExtractionResult(
        success: false,
        error: 'No messages to summarize',
      );
    }

    state.value.markExtractionStarted();

    try {
      final setup = await _setupFile();
      final prompt = await buildSessionMemoryUpdatePrompt(
        setup.currentMemory,
        setup.memoryPath,
        loadPrompt,
      );

      await runExtractionAgent(
        prompt: prompt,
        memoryPath: setup.memoryPath,
        contextMessages: messages,
      );

      logEvent('tengu_session_memory_manual_extraction', {});

      state.value.recordExtractionTokenCount(
        tokenCountWithEstimation(messages),
      );

      _updateLastSummarizedMessageIdIfSafe(messages);

      return ManualExtractionResult(
        success: true,
        memoryPath: setup.memoryPath,
      );
    } catch (e) {
      return ManualExtractionResult(success: false, error: e.toString());
    } finally {
      state.value.markExtractionCompleted();
    }
  }

  /// Initialise session memory by registering as a post-sampling hook.
  void initialize() {
    if (isRemoteMode()) return;
    if (!isAutoCompactEnabled()) return;
    // Hook registration would be done by the caller.
  }

  /// Get the current session memory content.
  Future<String?> getContent() async {
    try {
      final path = getSessionMemoryPath();
      if (!await fileExists(path)) return null;
      final content = await readFile(path);
      logEvent('tengu_session_memory_loaded', {
        'content_length': content.length,
      });
      return content;
    } catch (_) {
      return null;
    }
  }

  /// Reset the last memory message UUID (for testing).
  void resetLastMemoryMessageUuid() {
    _lastMemoryMessageUuid = null;
  }

  void _updateLastSummarizedMessageIdIfSafe(List<SessionMessage> messages) {
    if (!hasToolCallsInLastAssistantTurn(messages)) {
      final lastMessage = messages.isNotEmpty ? messages.last : null;
      if (lastMessage?.uuid != null) {
        state.value.lastSummarizedMessageId = lastMessage!.uuid;
      }
    }
  }
}

/// Result of a manual extraction.
class ManualExtractionResult {
  final bool success;
  final String? memoryPath;
  final String? error;

  const ManualExtractionResult({
    required this.success,
    this.memoryPath,
    this.error,
  });
}
