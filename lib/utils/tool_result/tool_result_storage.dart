/// Utility for persisting large tool results to disk instead of truncating them.
///
/// Ported from neom_claw/src/utils/toolResultStorage.ts (1040 LOC).
///
/// Manages tool result persistence, content replacement budgets, and
/// per-message aggregate enforcement to keep prompt sizes manageable.
library;

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Subdirectory name for tool results within a session.
const String toolResultsSubdir = 'tool-results';

/// XML tag used to wrap persisted output messages.
const String persistedOutputTag = '<persisted-output>';
const String persistedOutputClosingTag = '</persisted-output>';

/// Message used when tool result content was cleared without persisting to file.
const String toolResultClearedMessage = '[Old tool result content cleared]';

/// Approximate bytes per token for size estimation.
const int bytesPerToken = 4;

/// Default maximum result size in characters.
const int defaultMaxResultSizeChars = 50000;

/// Maximum tool result bytes (global limit).
const int maxToolResultBytes = 200000;

/// Maximum tool results per message in characters.
const int maxToolResultsPerMessageChars = 200000;

/// Preview size in bytes for the reference message.
const int previewSizeBytes = 2000;

// ---------------------------------------------------------------------------
// Types — PersistedToolResult
// ---------------------------------------------------------------------------

/// Result of persisting a tool result to disk.
class PersistedToolResult {
  const PersistedToolResult({
    required this.filepath,
    required this.originalSize,
    required this.isJson,
    required this.preview,
    required this.hasMore,
  });

  final String filepath;
  final int originalSize;
  final bool isJson;
  final String preview;
  final bool hasMore;
}

// ---------------------------------------------------------------------------
// Types — PersistToolResultError
// ---------------------------------------------------------------------------

/// Error result when persistence fails.
class PersistToolResultError {
  const PersistToolResultError({required this.error});
  final String error;
}

// ---------------------------------------------------------------------------
// Types — ToolResultBlockParam (simplified Dart equivalent)
// ---------------------------------------------------------------------------

/// Simplified representation of a tool result content block.
class ToolResultBlock {
  ToolResultBlock({
    required this.toolUseId,
    this.content,
    this.isError = false,
  });

  final String toolUseId;

  /// Can be a [String] or a [List<ContentBlock>].
  dynamic content;
  final bool isError;

  ToolResultBlock copyWith({
    String? toolUseId,
    dynamic content,
    bool? isError,
  }) {
    return ToolResultBlock(
      toolUseId: toolUseId ?? this.toolUseId,
      content: content ?? this.content,
      isError: isError ?? this.isError,
    );
  }
}

/// A text content block within a tool result.
class TextContentBlock {
  const TextContentBlock({required this.text, this.type = 'text'});
  final String type;
  final String text;

  Map<String, dynamic> toJson() => {'type': type, 'text': text};
}

/// An image content block within a tool result.
class ImageContentBlock {
  const ImageContentBlock({this.type = 'image'});
  final String type;
}

// ---------------------------------------------------------------------------
// Types — ContentReplacementState
// ---------------------------------------------------------------------------

/// Per-conversation-thread state for the aggregate tool result budget.
///
/// State must be stable to preserve prompt cache:
///   - seenIds: results that have passed through the budget check (replaced
///     or not). Once seen, a result's fate is frozen for the conversation.
///   - replacements: subset of seenIds that were persisted to disk and
///     replaced with previews, mapped to the exact preview string shown to
///     the model.
class ContentReplacementState {
  ContentReplacementState({
    Set<String>? seenIds,
    Map<String, String>? replacements,
  }) : seenIds = seenIds ?? {},
       replacements = replacements ?? {};

  final Set<String> seenIds;
  final Map<String, String> replacements;
}

/// Create a fresh content replacement state.
ContentReplacementState createContentReplacementState() {
  return ContentReplacementState();
}

/// Clone replacement state for a cache-sharing fork.
ContentReplacementState cloneContentReplacementState(
  ContentReplacementState source,
) {
  return ContentReplacementState(
    seenIds: Set<String>.from(source.seenIds),
    replacements: Map<String, String>.from(source.replacements),
  );
}

// ---------------------------------------------------------------------------
// Types — ContentReplacementRecord
// ---------------------------------------------------------------------------

/// Serializable record of one content-replacement decision.
/// Written to the transcript for resume reconstruction.
class ContentReplacementRecord {
  const ContentReplacementRecord({
    required this.kind,
    required this.toolUseId,
    required this.replacement,
  });

  /// Discriminated by `kind` so future replacement mechanisms can share
  /// the same transcript entry type.
  final String kind;
  final String toolUseId;
  final String replacement;

  factory ContentReplacementRecord.toolResult({
    required String toolUseId,
    required String replacement,
  }) {
    return ContentReplacementRecord(
      kind: 'tool-result',
      toolUseId: toolUseId,
      replacement: replacement,
    );
  }

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'toolUseId': toolUseId,
    'replacement': replacement,
  };

  factory ContentReplacementRecord.fromJson(Map<String, dynamic> json) {
    return ContentReplacementRecord(
      kind: json['kind'] as String,
      toolUseId: json['toolUseId'] as String,
      replacement: json['replacement'] as String,
    );
  }
}

// ---------------------------------------------------------------------------
// Types — Message (simplified)
// ---------------------------------------------------------------------------

/// Simplified message representation for budget enforcement.
class Message {
  Message({required this.type, required this.message});

  final String type;
  final MessageContent message;
}

/// Simplified message content.
class MessageContent {
  MessageContent({required this.content, this.id = ''});

  final String id;
  final List<dynamic> content;
}

// ---------------------------------------------------------------------------
// Types — ToolResultCandidate
// ---------------------------------------------------------------------------

class _ToolResultCandidate {
  _ToolResultCandidate({
    required this.toolUseId,
    required this.content,
    required this.size,
  });

  final String toolUseId;
  final dynamic content;
  final int size;
}

class _CandidatePartition {
  _CandidatePartition({
    required this.mustReapply,
    required this.frozen,
    required this.fresh,
  });

  final List<_ReapplyCandidate> mustReapply;
  final List<_ToolResultCandidate> frozen;
  final List<_ToolResultCandidate> fresh;
}

class _ReapplyCandidate extends _ToolResultCandidate {
  _ReapplyCandidate({
    required super.toolUseId,
    required super.content,
    required super.size,
    required this.replacement,
  });

  final String replacement;
}

// ---------------------------------------------------------------------------
// ToolResultStorage — SintController
// ---------------------------------------------------------------------------

/// Manages tool result persistence and content replacement budgets.
class ToolResultStorage extends SintController {
  ToolResultStorage({
    required this.projectDir,
    required this.sessionId,
    String? originalCwd,
  }) : _originalCwd = originalCwd ?? Directory.current.path;

  final String projectDir;
  final String sessionId;
  final String _originalCwd;

  /// Persistence threshold overrides keyed by tool name.
  final RxMap<String, int> persistThresholdOverrides = <String, int>{}.obs;

  // -------------------------------------------------------------------------
  // Path helpers
  // -------------------------------------------------------------------------

  /// Get the session directory.
  String getSessionDir() => '$projectDir/$sessionId';

  /// Get the tool results directory for this session.
  String getToolResultsDir() => '${getSessionDir()}/$toolResultsSubdir';

  /// Get the filepath where a tool result would be persisted.
  String getToolResultPath(String id, {required bool isJson}) {
    final ext = isJson ? 'json' : 'txt';
    return '${getToolResultsDir()}/$id.$ext';
  }

  // -------------------------------------------------------------------------
  // Persistence threshold
  // -------------------------------------------------------------------------

  /// Resolve the effective persistence threshold for a tool.
  int getPersistenceThreshold(String toolName, int declaredMaxResultSizeChars) {
    // Infinity = hard opt-out.
    if (declaredMaxResultSizeChars == -1 ||
        declaredMaxResultSizeChars >= (1 << 30)) {
      return declaredMaxResultSizeChars;
    }
    final override = persistThresholdOverrides[toolName];
    if (override != null && override > 0 && override.isFinite) {
      return override;
    }
    return min(declaredMaxResultSizeChars, defaultMaxResultSizeChars);
  }

  // -------------------------------------------------------------------------
  // Directory creation
  // -------------------------------------------------------------------------

  /// Ensure the session-specific tool results directory exists.
  Future<void> ensureToolResultsDir() async {
    try {
      await Directory(getToolResultsDir()).create(recursive: true);
    } catch (_) {
      // Directory may already exist.
    }
  }

  // -------------------------------------------------------------------------
  // Persist tool result
  // -------------------------------------------------------------------------

  /// Persist a tool result to disk and return information about the persisted file.
  Future<Object> persistToolResult(dynamic content, String toolUseId) async {
    final isJson = content is List;

    // Check for non-text content.
    if (isJson) {
      final hasNonTextContent = (content).any(
        (block) => block is Map && block['type'] != 'text',
      );
      if (hasNonTextContent) {
        return const PersistToolResultError(
          error: 'Cannot persist tool results containing non-text content',
        );
      }
    }

    await ensureToolResultsDir();
    final filepath = getToolResultPath(toolUseId, isJson: isJson);
    final contentStr = isJson
        ? const JsonEncoder.withIndent('  ').convert(content)
        : content.toString();

    try {
      final file = File(filepath);
      if (!await file.exists()) {
        await file.writeAsString(contentStr);
      }
    } catch (e) {
      return PersistToolResultError(error: _getFileSystemErrorMessage(e));
    }

    final preview = generatePreview(contentStr, previewSizeBytes);

    return PersistedToolResult(
      filepath: filepath,
      originalSize: contentStr.length,
      isJson: isJson,
      preview: preview.preview,
      hasMore: preview.hasMore,
    );
  }

  // -------------------------------------------------------------------------
  // Build large tool result message
  // -------------------------------------------------------------------------

  /// Build a message for large tool results with preview.
  static String buildLargeToolResultMessage(PersistedToolResult result) {
    final sb = StringBuffer();
    sb.writeln(persistedOutputTag);
    sb.writeln(
      'Output too large (${_formatFileSize(result.originalSize)}). Full output saved to: ${result.filepath}',
    );
    sb.writeln();
    sb.writeln('Preview (first ${_formatFileSize(previewSizeBytes)}):');
    sb.write(result.preview);
    if (result.hasMore) {
      sb.writeln();
      sb.writeln('...');
    } else {
      sb.writeln();
    }
    sb.write(persistedOutputClosingTag);
    return sb.toString();
  }

  // -------------------------------------------------------------------------
  // Process tool result block
  // -------------------------------------------------------------------------

  /// Process a tool result for inclusion in a message.
  Future<ToolResultBlock> processToolResultBlock({
    required String toolName,
    required int maxResultSizeChars,
    required ToolResultBlock toolResultBlock,
  }) async {
    return _maybePersistLargeToolResult(
      toolResultBlock,
      toolName,
      getPersistenceThreshold(toolName, maxResultSizeChars),
    );
  }

  /// Process a pre-mapped tool result block.
  Future<ToolResultBlock> processPreMappedToolResultBlock({
    required ToolResultBlock toolResultBlock,
    required String toolName,
    required int maxResultSizeChars,
  }) async {
    return _maybePersistLargeToolResult(
      toolResultBlock,
      toolName,
      getPersistenceThreshold(toolName, maxResultSizeChars),
    );
  }

  // -------------------------------------------------------------------------
  // Tool result content checks
  // -------------------------------------------------------------------------

  /// True when a tool_result's content is empty or effectively empty.
  static bool isToolResultContentEmpty(dynamic content) {
    if (content == null) return true;
    if (content is String) return content.trim().isEmpty;
    if (content is List) {
      if (content.isEmpty) return true;
      return content.every(
        (block) =>
            block is Map &&
            block['type'] == 'text' &&
            (block['text']?.toString().trim().isEmpty ?? true),
      );
    }
    return false;
  }

  /// Check if content contains image blocks.
  static bool _hasImageBlock(dynamic content) {
    if (content is List) {
      return content.any((b) => b is Map && b['type'] == 'image');
    }
    return false;
  }

  /// Calculate the content size.
  static int _contentSize(dynamic content) {
    if (content is String) return content.length;
    if (content is List) {
      return content.fold<int>(0, (sum, b) {
        if (b is Map && b['type'] == 'text') {
          return sum + ((b['text'] as String?)?.length ?? 0);
        }
        return sum;
      });
    }
    return 0;
  }

  /// Check if content is already compacted by the persisted output tag.
  static bool _isContentAlreadyCompacted(dynamic content) {
    return content is String && content.startsWith(persistedOutputTag);
  }

  // -------------------------------------------------------------------------
  // Maybe persist large tool result
  // -------------------------------------------------------------------------

  Future<ToolResultBlock> _maybePersistLargeToolResult(
    ToolResultBlock toolResultBlock,
    String toolName, [
    int? persistenceThreshold,
  ]) async {
    final content = toolResultBlock.content;

    // Empty tool_result content handling.
    if (isToolResultContentEmpty(content)) {
      return toolResultBlock.copyWith(
        content: '($toolName completed with no output)',
      );
    }

    if (content == null) return toolResultBlock;

    // Skip persistence for image content blocks.
    if (_hasImageBlock(content)) return toolResultBlock;

    final size = _contentSize(content);
    final threshold = persistenceThreshold ?? maxToolResultBytes;
    if (size <= threshold) return toolResultBlock;

    // Persist the entire content.
    final result = await persistToolResult(content, toolResultBlock.toolUseId);
    if (result is PersistToolResultError) {
      return toolResultBlock;
    }

    final persisted = result as PersistedToolResult;
    final message = buildLargeToolResultMessage(persisted);

    return toolResultBlock.copyWith(content: message);
  }

  // -------------------------------------------------------------------------
  // Generate preview
  // -------------------------------------------------------------------------

  /// Generate a preview of content, truncating at a newline boundary
  /// when possible.
  static ({String preview, bool hasMore}) generatePreview(
    String content,
    int maxBytes,
  ) {
    if (content.length <= maxBytes) {
      return (preview: content, hasMore: false);
    }

    final truncated = content.substring(0, maxBytes);
    final lastNewline = truncated.lastIndexOf('\n');

    final cutPoint = lastNewline > (maxBytes * 0.5).round()
        ? lastNewline
        : maxBytes;

    return (preview: content.substring(0, cutPoint), hasMore: true);
  }

  // -------------------------------------------------------------------------
  // Per-message budget limit
  // -------------------------------------------------------------------------

  /// Resolve the per-message aggregate budget limit.
  int getPerMessageBudgetLimit() {
    return maxToolResultsPerMessageChars;
  }

  // -------------------------------------------------------------------------
  // Provision content replacement state
  // -------------------------------------------------------------------------

  /// Provision replacement state for a new conversation thread.
  ContentReplacementState? provisionContentReplacementState({
    List<Message>? initialMessages,
    List<ContentReplacementRecord>? initialContentReplacements,
    bool enabled = true,
  }) {
    if (!enabled) return null;
    if (initialMessages != null) {
      return reconstructContentReplacementState(
        initialMessages,
        initialContentReplacements ?? [],
      );
    }
    return createContentReplacementState();
  }

  // -------------------------------------------------------------------------
  // Collect candidates
  // -------------------------------------------------------------------------

  /// Extract candidate tool_result blocks from a single user message.
  static List<_ToolResultCandidate> _collectCandidatesFromMessage(
    Message message,
  ) {
    if (message.type != 'user') return [];
    final candidates = <_ToolResultCandidate>[];
    for (final block in message.message.content) {
      if (block is! Map) continue;
      if (block['type'] != 'tool_result') continue;
      final content = block['content'];
      if (content == null) continue;
      if (_isContentAlreadyCompacted(content)) continue;
      if (_hasImageBlock(content)) continue;
      candidates.add(
        _ToolResultCandidate(
          toolUseId: block['tool_use_id'] as String,
          content: content,
          size: _contentSize(content),
        ),
      );
    }
    return candidates;
  }

  /// Extract candidate tool_result blocks grouped by API-level user message.
  static List<List<_ToolResultCandidate>> _collectCandidatesByMessage(
    List<Message> messages,
  ) {
    final groups = <List<_ToolResultCandidate>>[];
    var current = <_ToolResultCandidate>[];
    final seenAsstIds = <String>{};

    void flush() {
      if (current.isNotEmpty) groups.add(current);
      current = <_ToolResultCandidate>[];
    }

    for (final message in messages) {
      if (message.type == 'user') {
        current.addAll(_collectCandidatesFromMessage(message));
      } else if (message.type == 'assistant') {
        if (!seenAsstIds.contains(message.message.id)) {
          flush();
          seenAsstIds.add(message.message.id);
        }
      }
    }
    flush();
    return groups;
  }

  /// Build tool_use_id -> tool_name map from assistant tool_use blocks.
  static Map<String, String> _buildToolNameMap(List<Message> messages) {
    final map = <String, String>{};
    for (final message in messages) {
      if (message.type != 'assistant') continue;
      for (final block in message.message.content) {
        if (block is Map && block['type'] == 'tool_use') {
          map[block['id'] as String] = block['name'] as String;
        }
      }
    }
    return map;
  }

  // -------------------------------------------------------------------------
  // Partition candidates
  // -------------------------------------------------------------------------

  /// Partition candidates by their prior decision state.
  static _CandidatePartition _partitionByPriorDecision(
    List<_ToolResultCandidate> candidates,
    ContentReplacementState state,
  ) {
    final mustReapply = <_ReapplyCandidate>[];
    final frozen = <_ToolResultCandidate>[];
    final fresh = <_ToolResultCandidate>[];

    for (final c in candidates) {
      final replacement = state.replacements[c.toolUseId];
      if (replacement != null) {
        mustReapply.add(
          _ReapplyCandidate(
            toolUseId: c.toolUseId,
            content: c.content,
            size: c.size,
            replacement: replacement,
          ),
        );
      } else if (state.seenIds.contains(c.toolUseId)) {
        frozen.add(c);
      } else {
        fresh.add(c);
      }
    }

    return _CandidatePartition(
      mustReapply: mustReapply,
      frozen: frozen,
      fresh: fresh,
    );
  }

  /// Pick the largest fresh results to replace until under budget.
  static List<_ToolResultCandidate> _selectFreshToReplace(
    List<_ToolResultCandidate> fresh,
    int frozenSize,
    int limit,
  ) {
    final sorted = List<_ToolResultCandidate>.from(fresh)
      ..sort((a, b) => b.size.compareTo(a.size));
    final selected = <_ToolResultCandidate>[];
    var remaining = frozenSize + fresh.fold<int>(0, (s, c) => s + c.size);

    for (final c in sorted) {
      if (remaining <= limit) break;
      selected.add(c);
      remaining -= c.size;
    }
    return selected;
  }

  // -------------------------------------------------------------------------
  // Replace tool result contents
  // -------------------------------------------------------------------------

  /// Return a new Message list with replaced tool_result contents.
  static List<Message> _replaceToolResultContents(
    List<Message> messages,
    Map<String, String> replacementMap,
  ) {
    return messages.map((message) {
      if (message.type != 'user') return message;
      final content = message.message.content;
      final needsReplace = content.any(
        (b) =>
            b is Map &&
            b['type'] == 'tool_result' &&
            replacementMap.containsKey(b['tool_use_id']),
      );
      if (!needsReplace) return message;
      return Message(
        type: message.type,
        message: MessageContent(
          id: message.message.id,
          content: content.map((block) {
            if (block is! Map || block['type'] != 'tool_result') return block;
            final replacement = replacementMap[block['tool_use_id']];
            if (replacement == null) return block;
            return {...block, 'content': replacement};
          }).toList(),
        ),
      );
    }).toList();
  }

  // -------------------------------------------------------------------------
  // Enforce tool result budget
  // -------------------------------------------------------------------------

  /// Enforce the per-message budget on aggregate tool result size.
  Future<
    ({List<Message> messages, List<ContentReplacementRecord> newlyReplaced})
  >
  enforceToolResultBudget(
    List<Message> messages,
    ContentReplacementState state, {
    Set<String> skipToolNames = const {},
  }) async {
    final candidatesByMessage = _collectCandidatesByMessage(messages);
    final nameByToolUseId = skipToolNames.isNotEmpty
        ? _buildToolNameMap(messages)
        : null;

    bool shouldSkip(String id) {
      if (nameByToolUseId == null) return false;
      return skipToolNames.contains(nameByToolUseId[id] ?? '');
    }

    final limit = getPerMessageBudgetLimit();
    final replacementMap = <String, String>{};
    final toPersist = <_ToolResultCandidate>[];

    for (final candidates in candidatesByMessage) {
      final partition = _partitionByPriorDecision(candidates, state);

      // Re-apply cached replacements.
      for (final c in partition.mustReapply) {
        replacementMap[c.toolUseId] = c.replacement;
      }

      if (partition.fresh.isEmpty) {
        for (final c in candidates) {
          state.seenIds.add(c.toolUseId);
        }
        continue;
      }

      // Tools with opt-out — mark as seen.
      final skipped = partition.fresh.where((c) => shouldSkip(c.toolUseId));
      for (final c in skipped) {
        state.seenIds.add(c.toolUseId);
      }
      final eligible = partition.fresh
          .where((c) => !shouldSkip(c.toolUseId))
          .toList();

      final frozenSize = partition.frozen.fold<int>(0, (s, c) => s + c.size);
      final freshSize = eligible.fold<int>(0, (s, c) => s + c.size);

      final selected = (frozenSize + freshSize) > limit
          ? _selectFreshToReplace(eligible, frozenSize, limit)
          : <_ToolResultCandidate>[];

      final selectedIds = selected.map((c) => c.toolUseId).toSet();
      for (final c in candidates) {
        if (!selectedIds.contains(c.toolUseId)) {
          state.seenIds.add(c.toolUseId);
        }
      }

      if (selected.isEmpty) continue;
      toPersist.addAll(selected);
    }

    if (replacementMap.isEmpty && toPersist.isEmpty) {
      return (messages: messages, newlyReplaced: <ContentReplacementRecord>[]);
    }

    // Persist all selected candidates.
    final newlyReplaced = <ContentReplacementRecord>[];
    for (final candidate in toPersist) {
      state.seenIds.add(candidate.toolUseId);
      final result = await persistToolResult(
        candidate.content,
        candidate.toolUseId,
      );
      if (result is PersistToolResultError) continue;
      final persisted = result as PersistedToolResult;
      final replacementContent = buildLargeToolResultMessage(persisted);
      replacementMap[candidate.toolUseId] = replacementContent;
      state.replacements[candidate.toolUseId] = replacementContent;
      newlyReplaced.add(
        ContentReplacementRecord.toolResult(
          toolUseId: candidate.toolUseId,
          replacement: replacementContent,
        ),
      );
    }

    if (replacementMap.isEmpty) {
      return (messages: messages, newlyReplaced: <ContentReplacementRecord>[]);
    }

    return (
      messages: _replaceToolResultContents(messages, replacementMap),
      newlyReplaced: newlyReplaced,
    );
  }

  // -------------------------------------------------------------------------
  // Apply tool result budget
  // -------------------------------------------------------------------------

  /// Query-loop integration point for the aggregate budget.
  Future<List<Message>> applyToolResultBudget(
    List<Message> messages,
    ContentReplacementState? state, {
    void Function(List<ContentReplacementRecord>)? writeToTranscript,
    Set<String>? skipToolNames,
  }) async {
    if (state == null) return messages;
    final result = await enforceToolResultBudget(
      messages,
      state,
      skipToolNames: skipToolNames ?? const {},
    );
    if (result.newlyReplaced.isNotEmpty) {
      writeToTranscript?.call(result.newlyReplaced);
    }
    return result.messages;
  }

  // -------------------------------------------------------------------------
  // Reconstruct content replacement state
  // -------------------------------------------------------------------------

  /// Reconstruct replacement state from content-replacement records.
  ContentReplacementState reconstructContentReplacementState(
    List<Message> messages,
    List<ContentReplacementRecord> records, {
    Map<String, String>? inheritedReplacements,
  }) {
    final state = createContentReplacementState();
    final candidateIds = _collectCandidatesByMessage(
      messages,
    ).expand((g) => g).map((c) => c.toolUseId).toSet();

    for (final id in candidateIds) {
      state.seenIds.add(id);
    }
    for (final r in records) {
      if (r.kind == 'tool-result' && candidateIds.contains(r.toolUseId)) {
        state.replacements[r.toolUseId] = r.replacement;
      }
    }
    if (inheritedReplacements != null) {
      for (final entry in inheritedReplacements.entries) {
        if (candidateIds.contains(entry.key) &&
            !state.replacements.containsKey(entry.key)) {
          state.replacements[entry.key] = entry.value;
        }
      }
    }
    return state;
  }

  /// AgentTool-resume variant for subagent reconstruction.
  ContentReplacementState? reconstructForSubagentResume(
    ContentReplacementState? parentState,
    List<Message> resumedMessages,
    List<ContentReplacementRecord> sidechainRecords,
  ) {
    if (parentState == null) return null;
    return reconstructContentReplacementState(
      resumedMessages,
      sidechainRecords,
      inheritedReplacements: parentState.replacements,
    );
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _getFileSystemErrorMessage(Object error) {
    if (error is FileSystemException) {
      final osError = error.osError;
      if (osError != null) {
        switch (osError.errorCode) {
          case 2: // ENOENT
            return 'Directory not found: ${error.path ?? 'unknown path'}';
          case 13: // EACCES
            return 'Permission denied: ${error.path ?? 'unknown path'}';
          case 28: // ENOSPC
            return 'No space left on device';
          case 30: // EROFS
            return 'Read-only file system';
          case 24: // EMFILE
            return 'Too many open files';
          case 17: // EEXIST
            return 'File already exists: ${error.path ?? 'unknown path'}';
          default:
            return '${osError.message}: ${error.message}';
        }
      }
      return error.message;
    }
    return error.toString();
  }
}
