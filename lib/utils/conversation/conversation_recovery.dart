// Conversation recovery — port of openneomclaw/src/utils/conversationRecovery.ts.
// Session/conversation recovery logic: deserialization, interrupt detection,
// skill state restoration, and full resume loading.

import 'dart:async';

import 'package:neom_claw/utils/messages/message_utils.dart' hide Message;
import 'package:neom_claw/utils/session/session_storage.dart';
import 'package:neom_claw/domain/models/logs.dart' hide SerializedMessage, LogOption;

// ─── Local Type Stubs ────────────────────────────────────────────────────────
//
// These types are local to conversation recovery and provide the shape needed
// by the deserialization / resume loading logic.

/// Simple conversation message used during recovery.
class Message {
  final MessageType type;
  final String uuid;
  final String timestamp;
  final dynamic content;
  final bool? isMeta;
  final bool? isApiErrorMessage;
  final bool? isCompactSummary;
  final Attachment? attachment;
  String? permissionMode;

  Message({
    required this.type,
    this.content,
    String? uuid,
    String? timestamp,
    this.isMeta,
    this.isApiErrorMessage,
    this.isCompactSummary,
    this.attachment,
    this.permissionMode,
  })  : uuid = uuid ?? DateTime.now().microsecondsSinceEpoch.toString(),
        timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  Message copyWith({
    MessageType? type,
    dynamic content,
    String? uuid,
    String? timestamp,
    bool? isMeta,
    bool? isApiErrorMessage,
    bool? isCompactSummary,
    Attachment? attachment,
    String? permissionMode,
  }) =>
      Message(
        type: type ?? this.type,
        content: content ?? this.content,
        uuid: uuid ?? this.uuid,
        timestamp: timestamp ?? this.timestamp,
        isMeta: isMeta ?? this.isMeta,
        isApiErrorMessage: isApiErrorMessage ?? this.isApiErrorMessage,
        isCompactSummary: isCompactSummary ?? this.isCompactSummary,
        attachment: attachment ?? this.attachment,
        permissionMode: permissionMode ?? this.permissionMode,
      );
}

/// Alias for a user message after normalisation.
typedef NormalizedUserMessage = Message;

/// Attachment on a message.
class Attachment {
  final Map<String, dynamic> _data;

  Attachment.fromJson(Map<String, dynamic> json) : _data = Map.from(json);

  Map<String, dynamic> toJson() => _data;

  String? get type => _data['type'] as String?;
}

/// Transcript message with session metadata.
class TranscriptMessage {
  final String uuid;
  final String timestamp;
  final String? sessionId;
  final bool isSidechain;
  final Map<String, dynamic> data;

  const TranscriptMessage({
    required this.uuid,
    required this.timestamp,
    this.sessionId,
    this.isSidechain = false,
    this.data = const {},
  });
}

/// Serialized message wrapper for recovery.
class SerializedMessage {
  final Message message;
  final String? sessionId;

  const SerializedMessage({required this.message, this.sessionId});
}

/// Result of loading a transcript file.
class TranscriptLoadResult {
  final Map<String, TranscriptMessage> messages;
  final Set<String> leafUuids;

  const TranscriptLoadResult({
    required this.messages,
    required this.leafUuids,
  });
}

/// Log option with loaded messages for recovery.
class LogOption {
  final String path;
  final List<Message>? messages;
  final DateTime? created;
  final DateTime? modified;
  final List<FileHistorySnapshot>? fileHistorySnapshots;
  final List<AttributionSnapshotMessage>? attributionSnapshots;
  final List<ContentReplacementRecord>? contentReplacements;
  final List<ContextCollapseCommitEntry>? contextCollapseCommits;
  final ContextCollapseSnapshotEntry? contextCollapseSnapshot;
  final String? agentName;
  final String? agentColor;
  final String? agentSetting;
  final String? customTitle;
  final String? tag;
  final String? mode;
  final PersistedWorktreeSession? worktreeSession;
  final int? prNumber;
  final String? prUrl;
  final String? prRepository;
  final String? fullPath;

  const LogOption({
    required this.path,
    this.messages,
    this.created,
    this.modified,
    this.fileHistorySnapshots,
    this.attributionSnapshots,
    this.contentReplacements,
    this.contextCollapseCommits,
    this.contextCollapseSnapshot,
    this.agentName,
    this.agentColor,
    this.agentSetting,
    this.customTitle,
    this.tag,
    this.mode,
    this.worktreeSession,
    this.prNumber,
    this.prUrl,
    this.prRepository,
    this.fullPath,
  });
}

// ─── Stub functions ──────────────────────────────────────────────────────────
//
// These will be connected to session_storage once the full wiring is complete.

/// Load a transcript JSONL file and return structured data.
Future<TranscriptLoadResult> loadTranscriptFile(String path) async {
  // Stub — delegates to session_storage in production.
  return const TranscriptLoadResult(messages: {}, leafUuids: {});
}

/// Build a linear conversation chain from a UUID map and a tip message.
List<SerializedMessage> buildConversationChain(
  Map<String, TranscriptMessage> byUuid,
  TranscriptMessage tip,
) {
  // Walk parentUuid chain backwards.
  return [];
}

/// Strip internal-only fields from serialized messages.
List<SerializedMessage> removeExtraFields(List<SerializedMessage> chain) {
  return chain;
}

/// Load all available message logs sorted by recency.
Future<List<LogOption>> loadMessageLogs() async {
  return [];
}

/// Extract session ID from a log option.
String? getSessionIdFromLog(LogOption log) {
  return log.path.split('/').last.replaceAll('.jsonl', '');
}

/// Get the last session log matching a session ID.
Future<LogOption?> getLastSessionLog(String sessionId) async {
  return null;
}

/// Check if a log is a lite (metadata-only) log.
bool isLiteLog(LogOption log) {
  return false;
}

/// Load the full log from a lite log.
Future<LogOption> loadFullLog(LogOption log) async {
  return log;
}

/// Validate message consistency for resume.
void checkResumeConsistency(List<dynamic>? messages) {
  // No-op stub for now.
}

// ─── Types ───────────────────────────────────────────────────────────────────

/// Result of a teleport remote operation.
class TeleportRemoteResponse {
  final List<Message> log;
  final String? branch;

  const TeleportRemoteResponse({
    required this.log,
    this.branch,
  });

  TeleportRemoteResponse copyWith({
    List<Message>? log,
    String? branch,
  }) =>
      TeleportRemoteResponse(
        log: log ?? this.log,
        branch: branch ?? this.branch,
      );
}

/// Describes how a turn was interrupted (if at all).
sealed class TurnInterruptionState {
  const TurnInterruptionState();
}

/// No interruption detected.
class TurnInterruptionNone extends TurnInterruptionState {
  const TurnInterruptionNone();
}

/// The user had typed a prompt but the assistant never responded.
class TurnInterruptionPrompt extends TurnInterruptionState {
  final NormalizedUserMessage message;

  const TurnInterruptionPrompt({required this.message});
}

/// Internal-only state: the assistant was mid-turn (tool use in flight).
/// Transformed into [TurnInterruptionPrompt] with a synthetic continuation
/// message before being surfaced to callers.
class _TurnInterruptionMidTurn extends TurnInterruptionState {
  const _TurnInterruptionMidTurn();
}

/// Result of deserializing messages with interruption detection.
class DeserializeResult {
  final List<Message> messages;
  final TurnInterruptionState turnInterruptionState;

  const DeserializeResult({
    required this.messages,
    required this.turnInterruptionState,
  });
}

/// File history snapshot entry from a log.
class FileHistorySnapshot {
  final String filePath;
  final String content;
  final int timestamp;

  const FileHistorySnapshot({
    required this.filePath,
    required this.content,
    required this.timestamp,
  });

  factory FileHistorySnapshot.fromJson(Map<String, dynamic> json) =>
      FileHistorySnapshot(
        filePath: json['filePath'] as String,
        content: json['content'] as String,
        timestamp: json['timestamp'] as int,
      );

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'content': content,
        'timestamp': timestamp,
      };
}

/// Attribution snapshot message.
class AttributionSnapshotMessage {
  final String id;
  final Map<String, dynamic> data;

  const AttributionSnapshotMessage({
    required this.id,
    required this.data,
  });

  factory AttributionSnapshotMessage.fromJson(Map<String, dynamic> json) =>
      AttributionSnapshotMessage(
        id: json['id'] as String,
        data: json['data'] as Map<String, dynamic>,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'data': data,
      };
}

/// Content replacement record for tool result storage.
class ContentReplacementRecord {
  final String toolUseId;
  final String originalContent;
  final String replacementContent;

  const ContentReplacementRecord({
    required this.toolUseId,
    required this.originalContent,
    required this.replacementContent,
  });

  factory ContentReplacementRecord.fromJson(Map<String, dynamic> json) =>
      ContentReplacementRecord(
        toolUseId: json['toolUseId'] as String,
        originalContent: json['originalContent'] as String,
        replacementContent: json['replacementContent'] as String,
      );

  Map<String, dynamic> toJson() => {
        'toolUseId': toolUseId,
        'originalContent': originalContent,
        'replacementContent': replacementContent,
      };
}

/// Context collapse commit entry.
class ContextCollapseCommitEntry {
  final String commitHash;
  final String message;
  final int timestamp;

  const ContextCollapseCommitEntry({
    required this.commitHash,
    required this.message,
    required this.timestamp,
  });

  factory ContextCollapseCommitEntry.fromJson(Map<String, dynamic> json) =>
      ContextCollapseCommitEntry(
        commitHash: json['commitHash'] as String,
        message: json['message'] as String,
        timestamp: json['timestamp'] as int,
      );

  Map<String, dynamic> toJson() => {
        'commitHash': commitHash,
        'message': message,
        'timestamp': timestamp,
      };
}

/// Context collapse snapshot entry.
class ContextCollapseSnapshotEntry {
  final String content;
  final int timestamp;

  const ContextCollapseSnapshotEntry({
    required this.content,
    required this.timestamp,
  });

  factory ContextCollapseSnapshotEntry.fromJson(Map<String, dynamic> json) =>
      ContextCollapseSnapshotEntry(
        content: json['content'] as String,
        timestamp: json['timestamp'] as int,
      );

  Map<String, dynamic> toJson() => {
        'content': content,
        'timestamp': timestamp,
      };
}

/// Persisted worktree session metadata.
class PersistedWorktreeSession {
  final String worktreePath;
  final String branchName;
  final String? originalBranch;

  const PersistedWorktreeSession({
    required this.worktreePath,
    required this.branchName,
    this.originalBranch,
  });

  factory PersistedWorktreeSession.fromJson(Map<String, dynamic> json) =>
      PersistedWorktreeSession(
        worktreePath: json['worktreePath'] as String,
        branchName: json['branchName'] as String,
        originalBranch: json['originalBranch'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'worktreePath': worktreePath,
        'branchName': branchName,
        if (originalBranch != null) 'originalBranch': originalBranch,
      };
}

/// Session mode.
enum SessionMode { coordinator, normal }

/// Full result of loading a conversation for resume.
class ConversationResumeResult {
  final List<Message> messages;
  final TurnInterruptionState turnInterruptionState;
  final List<FileHistorySnapshot>? fileHistorySnapshots;
  final List<AttributionSnapshotMessage>? attributionSnapshots;
  final List<ContentReplacementRecord>? contentReplacements;
  final List<ContextCollapseCommitEntry>? contextCollapseCommits;
  final ContextCollapseSnapshotEntry? contextCollapseSnapshot;
  final String? sessionId;
  final String? agentName;
  final String? agentColor;
  final String? agentSetting;
  final String? customTitle;
  final String? tag;
  final SessionMode? mode;
  final PersistedWorktreeSession? worktreeSession;
  final int? prNumber;
  final String? prUrl;
  final String? prRepository;
  final String? fullPath;

  const ConversationResumeResult({
    required this.messages,
    required this.turnInterruptionState,
    this.fileHistorySnapshots,
    this.attributionSnapshots,
    this.contentReplacements,
    this.contextCollapseCommits,
    this.contextCollapseSnapshot,
    this.sessionId,
    this.agentName,
    this.agentColor,
    this.agentSetting,
    this.customTitle,
    this.tag,
    this.mode,
    this.worktreeSession,
    this.prNumber,
    this.prUrl,
    this.prRepository,
    this.fullPath,
  });
}

// ─── Permission modes ────────────────────────────────────────────────────────

/// Valid permission modes. Used to strip invalid values from deserialized
/// user messages.
const Set<String> kPermissionModes = {
  'default',
  'plan',
  'bypassPermissions',
  'autoEdit',
};

// ─── Tool name constants ─────────────────────────────────────────────────────

/// Tool names that terminate a turn (brief mode). When a tool_result message
/// is the last in a session and it belongs to one of these tools, the turn
/// completed normally rather than being interrupted.
const Set<String> kTerminalToolNames = {
  'BriefTool',
  'LegacyBriefTool',
  'SendUserFile',
};

// ─── Sentinel ────────────────────────────────────────────────────────────────

/// Synthetic assistant content appended after a trailing user message so the
/// conversation remains API-valid when no resume action is taken.
const String kNoResponseRequested = '[No response requested]';

// ─── Legacy attachment migration ─────────────────────────────────────────────

/// Transforms legacy attachment types to current types for backward
/// compatibility. Handles `new_file` -> `file`, `new_directory` -> `directory`,
/// and backfills `displayPath` for old attachments.
Message migrateLegacyAttachmentTypes(
  Message message, {
  required String Function() getCwd,
}) {
  if (message.type != MessageType.attachment) {
    return message;
  }

  final attachment = message.attachment;
  if (attachment == null) return message;

  final attachmentMap = attachment.toJson();
  final attachmentType = attachmentMap['type'] as String?;

  // Transform legacy attachment types.
  if (attachmentType == 'new_file') {
    final filename = attachmentMap['filename'] as String?;
    if (filename != null) {
      final displayPath = _relativePath(getCwd(), filename);
      return message.copyWith(
        attachment: Attachment.fromJson({
          ...attachmentMap,
          'type': 'file',
          'displayPath': displayPath,
        }),
      );
    }
  }

  if (attachmentType == 'new_directory') {
    final path = attachmentMap['path'] as String?;
    if (path != null) {
      final displayPath = _relativePath(getCwd(), path);
      return message.copyWith(
        attachment: Attachment.fromJson({
          ...attachmentMap,
          'type': 'directory',
          'displayPath': displayPath,
        }),
      );
    }
  }

  // Backfill displayPath for attachments from old sessions.
  if (!attachmentMap.containsKey('displayPath')) {
    final path = attachmentMap['filename'] as String? ??
        attachmentMap['path'] as String? ??
        attachmentMap['skillDir'] as String?;
    if (path != null) {
      final displayPath = _relativePath(getCwd(), path);
      return message.copyWith(
        attachment: Attachment.fromJson({
          ...attachmentMap,
          'displayPath': displayPath,
        }),
      );
    }
  }

  return message;
}

/// Compute a relative path from [from] to [to].
String _relativePath(String from, String to) {
  // Simplified: in real code this would use p.relative(to, from: from).
  if (to.startsWith(from)) {
    final rel = to.substring(from.length);
    if (rel.startsWith('/')) return rel.substring(1);
    return rel;
  }
  return to;
}

// ─── Deserialization ─────────────────────────────────────────────────────────

/// Deserializes messages from a log file into the format expected by the REPL.
/// Filters unresolved tool uses, orphaned thinking messages, and appends a
/// synthetic assistant sentinel when the last message is from the user.
///
/// This is the simple entry point; use [deserializeMessagesWithInterruptDetection]
/// when you also need to know if the session was interrupted mid-turn.
List<Message> deserializeMessages(List<Message> serializedMessages) {
  return deserializeMessagesWithInterruptDetection(serializedMessages).messages;
}

/// Like [deserializeMessages], but also detects whether the session was
/// interrupted mid-turn. Used by the SDK resume path to auto-continue
/// interrupted turns after a gateway-triggered restart.
DeserializeResult deserializeMessagesWithInterruptDetection(
  List<Message> serializedMessages, {
  String Function()? getCwd,
}) {
  try {
    final effectiveGetCwd = getCwd ?? () => '.';

    // Transform legacy attachment types before processing.
    final migratedMessages = serializedMessages
        .map((m) => migrateLegacyAttachmentTypes(m, getCwd: effectiveGetCwd))
        .toList();

    // Strip invalid permissionMode values from deserialized user messages.
    for (final msg in migratedMessages) {
      if (msg.type == MessageType.user &&
          msg.permissionMode != null &&
          !kPermissionModes.contains(msg.permissionMode)) {
        msg.permissionMode = null;
      }
    }

    // Filter out unresolved tool uses and any synthetic messages that follow.
    final filteredToolUses =
        filterUnresolvedToolUses(migratedMessages);

    // Filter out orphaned thinking-only assistant messages that can cause API
    // errors during resume. These occur when streaming yields separate messages
    // per content block and interleaved user messages prevent proper merging.
    final filteredThinking =
        filterOrphanedThinkingOnlyMessages(filteredToolUses);

    // Filter out assistant messages with only whitespace text content.
    // This can happen when model outputs "\n\n" before thinking, user cancels.
    final filteredMessages =
        filterWhitespaceOnlyAssistantMessages(filteredThinking);

    final internalState = _detectTurnInterruption(filteredMessages);

    // Transform mid-turn interruptions into interrupted_prompt by appending
    // a synthetic continuation message.
    TurnInterruptionState turnInterruptionState;
    if (internalState is _TurnInterruptionMidTurn) {
      final continuationMessage = createUserMessage(
        content: 'Continue from where you left off.',
        isMeta: true,
      );
      final normalized = normalizeMessages([continuationMessage]);
      final normalizedMsg = normalized.first;
      filteredMessages.add(normalizedMsg);
      turnInterruptionState =
          TurnInterruptionPrompt(message: normalizedMsg as NormalizedUserMessage);
    } else {
      turnInterruptionState = internalState;
    }

    // Append a synthetic assistant sentinel after the last user message so
    // the conversation is API-valid if no resume action is taken.
    final lastRelevantIdx = _findLastRelevantIndex(filteredMessages);
    if (lastRelevantIdx != -1 &&
        filteredMessages[lastRelevantIdx].type == MessageType.user) {
      filteredMessages.insert(
        lastRelevantIdx + 1,
        createAssistantMessage(content: kNoResponseRequested),
      );
    }

    return DeserializeResult(
      messages: filteredMessages,
      turnInterruptionState: turnInterruptionState,
    );
  } catch (error) {
    logError(error);
    rethrow;
  }
}

/// Find the index of the last message that is not a system or progress message.
int _findLastRelevantIndex(List<Message> messages) {
  for (int i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.type != MessageType.system && m.type != MessageType.progress) {
      return i;
    }
  }
  return -1;
}

// ─── Turn interruption detection ─────────────────────────────────────────────

/// Determines whether the conversation was interrupted mid-turn based on the
/// last message after filtering.
///
/// An assistant as last message (after filtering unresolved tool_uses) is
/// treated as a completed turn because stop_reason is always null on persisted
/// messages in the streaming path.
///
/// System and progress messages are skipped when finding the last turn-relevant
/// message -- they are bookkeeping artifacts that should not mask a genuine
/// interruption. Attachments are kept as part of the turn.
TurnInterruptionState _detectTurnInterruption(
  List<Message> messages,
) {
  if (messages.isEmpty) {
    return const TurnInterruptionNone();
  }

  // Find the last turn-relevant message, skipping system/progress and
  // synthetic API error assistants.
  int lastMessageIdx = -1;
  for (int i = messages.length - 1; i >= 0; i--) {
    final m = messages[i];
    if (m.type == MessageType.system || m.type == MessageType.progress) {
      continue;
    }
    if (m.type == MessageType.assistant && m.isApiErrorMessage == true) {
      continue;
    }
    lastMessageIdx = i;
    break;
  }

  if (lastMessageIdx == -1) {
    return const TurnInterruptionNone();
  }

  final lastMessage = messages[lastMessageIdx];

  if (lastMessage.type == MessageType.assistant) {
    // In the streaming path, stop_reason is always null on persisted messages.
    // After filterUnresolvedToolUses has removed assistant messages with
    // unmatched tool_uses, an assistant as the last message means the turn
    // most likely completed normally.
    return const TurnInterruptionNone();
  }

  if (lastMessage.type == MessageType.user) {
    if (lastMessage.isMeta == true || lastMessage.isCompactSummary == true) {
      return const TurnInterruptionNone();
    }
    if (isToolUseResultMessage(lastMessage)) {
      // Brief mode drops the trailing assistant text block, so a completed
      // brief-mode turn legitimately ends on SendUserMessage's tool_result.
      if (_isTerminalToolResult(lastMessage, messages, lastMessageIdx)) {
        return const TurnInterruptionNone();
      }
      return const _TurnInterruptionMidTurn();
    }
    // Plain text user prompt -- CC hadn't started responding.
    return TurnInterruptionPrompt(
      message: lastMessage as NormalizedUserMessage,
    );
  }

  if (lastMessage.type == MessageType.attachment) {
    // Attachments are part of the user turn -- the user provided context but
    // the assistant never responded.
    return const _TurnInterruptionMidTurn();
  }

  return const TurnInterruptionNone();
}

/// Checks if a tool_result is the output of a tool that legitimately
/// terminates a turn. Walks back to find the assistant tool_use that this
/// result belongs to and checks its name against [kTerminalToolNames].
bool _isTerminalToolResult(
  Message result,
  List<Message> messages,
  int resultIdx,
) {
  final content = result.content;
  if (content is! List) return false;
  if (content.isEmpty) return false;

  final block = content[0];
  if (block is! Map || block['type'] != 'tool_result') return false;
  final toolUseId = block['tool_use_id'] as String?;
  if (toolUseId == null) return false;

  for (int i = resultIdx - 1; i >= 0; i--) {
    final msg = messages[i];
    if (msg.type != MessageType.assistant) continue;
    final msgContent = msg.content;
    if (msgContent is! List) continue;
    for (final b in msgContent) {
      if (b is Map &&
          b['type'] == 'tool_use' &&
          b['id'] == toolUseId) {
        final name = b['name'] as String?;
        return name != null && kTerminalToolNames.contains(name);
      }
    }
  }
  return false;
}

// ─── Skill state restoration ─────────────────────────────────────────────────

/// Callback type for adding an invoked skill to global state.
typedef AddInvokedSkillCallback = void Function(
  String name,
  String path,
  String content,
  String? agentId,
);

/// Callback type for suppressing the next skill listing.
typedef SuppressNextSkillListingCallback = void Function();

/// Restores skill state from invoked_skills attachments in messages.
/// This ensures that skills are preserved across resume after compaction.
/// Without this, if another compaction happens after resume, the skills would
/// be lost because invokedSkills state would be empty.
void restoreSkillStateFromMessages(
  List<Message> messages, {
  required AddInvokedSkillCallback addInvokedSkill,
  required SuppressNextSkillListingCallback suppressNextSkillListing,
}) {
  for (final message in messages) {
    if (message.type != MessageType.attachment) {
      continue;
    }

    final attachment = message.attachment;
    if (attachment == null) continue;

    final attachmentJson = attachment.toJson();
    final attachmentType = attachmentJson['type'] as String?;

    if (attachmentType == 'invoked_skills') {
      final skills = attachmentJson['skills'] as List?;
      if (skills != null) {
        for (final skill in skills) {
          if (skill is Map) {
            final name = skill['name'] as String?;
            final path = skill['path'] as String?;
            final content = skill['content'] as String?;
            if (name != null && path != null && content != null) {
              // Resume only happens for the main session, so agentId is null.
              addInvokedSkill(name, path, content, null);
            }
          }
        }
      }
    }

    // A prior process already injected the skills-available reminder.
    // sentSkillNames is process-local, so without this every resume
    // re-announces the same ~600 tokens.
    if (attachmentType == 'skill_listing') {
      suppressNextSkillListing();
    }
  }
}

// ─── Loading messages from JSONL ─────────────────────────────────────────────

/// Result of loading messages from a JSONL path.
class LoadMessagesResult {
  final List<SerializedMessage> messages;
  final String? sessionId;

  const LoadMessagesResult({
    required this.messages,
    this.sessionId,
  });
}

/// Chain-walk a transcript JSONL by path. Same sequence loadFullLog runs
/// internally -- loadTranscriptFile -> find newest non-sidechain leaf ->
/// buildConversationChain -> removeExtraFields -- just starting from an
/// arbitrary path instead of the session-ID-derived one.
///
/// leafUuids is populated by loadTranscriptFile as "UUIDs that no other
/// message's parentUuid points at" -- the chain tips. There can be several
/// (sidechains, orphans); newest non-sidechain is the main conversation's end.
Future<LoadMessagesResult> loadMessagesFromJsonlPath(String path) async {
  final transcriptResult = await loadTranscriptFile(path);
  final byUuid = transcriptResult.messages;
  final leafUuids = transcriptResult.leafUuids;

  TranscriptMessage? tip;
  int tipTs = 0;

  for (final m in byUuid.values) {
    if (m.isSidechain || !leafUuids.contains(m.uuid)) continue;
    final ts = DateTime.parse(m.timestamp).millisecondsSinceEpoch;
    if (ts > tipTs) {
      tipTs = ts;
      tip = m;
    }
  }

  if (tip == null) {
    return const LoadMessagesResult(messages: []);
  }

  final chain = buildConversationChain(byUuid, tip);
  return LoadMessagesResult(
    messages: removeExtraFields(chain),
    sessionId: tip.sessionId,
  );
}

// ─── Main resume loader ──────────────────────────────────────────────────────

/// Loads a conversation for resume from various sources.
///
/// This is the centralized function for loading and deserializing
/// conversations.
///
/// [source] can be:
///   - null: load most recent conversation
///   - String: session ID to load
///   - LogOption: already loaded conversation
///
/// [sourceJsonlFile] is an alternate path to a transcript JSONL. Used when
/// --resume receives a .jsonl path, typically for cross-directory resume where
/// the transcript lives outside the current project dir.
Future<ConversationResumeResult?> loadConversationForResume({
  Object? source,
  String? sourceJsonlFile,
  required String Function() getCwd,
  required AddInvokedSkillCallback addInvokedSkill,
  required SuppressNextSkillListingCallback suppressNextSkillListing,
  Future<List<Message>> Function({String? sessionId})?
      processSessionStartHooks,
  Future<void> Function(LogOption log, String sessionId)? copyPlanForResume,
  Future<void> Function(LogOption log)? copyFileHistoryForResume,
  Future<Set<String>> Function()? listLiveSessions,
}) async {
  try {
    LogOption? log;
    List<Message>? messages;
    String? sessionId;

    if (source == null && sourceJsonlFile == null) {
      // --continue: most recent session, skipping live --bg/daemon sessions
      // that are actively writing their own transcript.
      final logs = await loadMessageLogs();
      Set<String> skip = {};
      if (listLiveSessions != null) {
        try {
          skip = await listLiveSessions();
        } catch (_) {
          // UDS unavailable -- treat all sessions as continuable.
        }
      }
      log = logs.cast<LogOption?>().firstWhere(
        (l) {
          if (l == null) return false;
          final id = getSessionIdFromLog(l);
          return id == null || !skip.contains(id);
        },
        orElse: () => null,
      );
    } else if (sourceJsonlFile != null) {
      // --resume with a .jsonl path.
      final loaded = await loadMessagesFromJsonlPath(sourceJsonlFile);
      messages = loaded.messages.cast<Message>();
      sessionId = loaded.sessionId;
    } else if (source is String) {
      // Load specific session by ID.
      log = await getLastSessionLog(source);
      sessionId = source;
    } else if (source is LogOption) {
      // Already have a LogOption.
      log = source;
    }

    if (log == null && messages == null) {
      return null;
    }

    if (log != null) {
      // Load full messages for lite logs.
      if (isLiteLog(log)) {
        log = await loadFullLog(log);
      }

      // Determine sessionId first so we can pass it to copy functions.
      sessionId ??= getSessionIdFromLog(log);

      // Copy plan for resume.
      if (sessionId != null && copyPlanForResume != null) {
        await copyPlanForResume(log, sessionId);
      }

      // Copy file history for resume (fire-and-forget).
      if (copyFileHistoryForResume != null) {
        // ignore: unawaited_futures
        copyFileHistoryForResume(log);
      }

      messages = log.messages;
      checkResumeConsistency(messages);
    }

    // Restore skill state from invoked_skills attachments before
    // deserialization. This ensures skills survive multiple compaction
    // cycles after resume.
    restoreSkillStateFromMessages(
      messages!,
      addInvokedSkill: addInvokedSkill,
      suppressNextSkillListing: suppressNextSkillListing,
    );

    // Deserialize messages to handle unresolved tool uses and ensure
    // proper format.
    final deserialized = deserializeMessagesWithInterruptDetection(
      messages,
      getCwd: getCwd,
    );
    messages = deserialized.messages;

    // Process session start hooks for resume.
    if (processSessionStartHooks != null) {
      final hookMessages =
          await processSessionStartHooks(sessionId: sessionId);
      messages.addAll(hookMessages);
    }

    return ConversationResumeResult(
      messages: messages,
      turnInterruptionState: deserialized.turnInterruptionState,
      fileHistorySnapshots: log?.fileHistorySnapshots,
      attributionSnapshots: log?.attributionSnapshots,
      contentReplacements: log?.contentReplacements,
      contextCollapseCommits: log?.contextCollapseCommits,
      contextCollapseSnapshot: log?.contextCollapseSnapshot,
      sessionId: sessionId,
      agentName: log?.agentName,
      agentColor: log?.agentColor,
      agentSetting: log?.agentSetting,
      customTitle: log?.customTitle,
      tag: log?.tag,
      mode: log?.mode != null
          ? (log!.mode == 'coordinator'
              ? SessionMode.coordinator
              : SessionMode.normal)
          : null,
      worktreeSession: log?.worktreeSession,
      prNumber: log?.prNumber,
      prUrl: log?.prUrl,
      prRepository: log?.prRepository,
      fullPath: log?.fullPath,
    );
  } catch (error) {
    logError(error);
    rethrow;
  }
}

// ─── Stub helpers (to be wired to real implementations) ──────────────────────

/// Filter out unresolved tool uses from a message list.
/// Messages with tool_use blocks that have no matching tool_result are dropped.
List<Message> filterUnresolvedToolUses(List<Message> messages) {
  // Collect all tool_result IDs.
  final resolvedIds = <String>{};
  for (final msg in messages) {
    if (msg.type == MessageType.user) {
      final content = msg.content;
      if (content is List) {
        for (final block in content) {
          if (block is Map && block['type'] == 'tool_result') {
            final id = block['tool_use_id'] as String?;
            if (id != null) resolvedIds.add(id);
          }
        }
      }
    }
  }

  final result = <Message>[];
  for (final msg in messages) {
    if (msg.type == MessageType.assistant) {
      final content = msg.content;
      if (content is List) {
        // Check if any tool_use blocks are unresolved.
        bool hasUnresolved = false;
        for (final block in content) {
          if (block is Map && block['type'] == 'tool_use') {
            final id = block['id'] as String?;
            if (id != null && !resolvedIds.contains(id)) {
              hasUnresolved = true;
              break;
            }
          }
        }
        if (hasUnresolved) {
          // Drop this assistant message and any following synthetic messages.
          continue;
        }
      }
    }
    result.add(msg);
  }
  return result;
}

/// Filter out orphaned thinking-only assistant messages that can cause
/// API errors during resume. These occur when streaming yields separate
/// messages per content block and interleaved user messages prevent proper
/// merging by message.id.
List<Message> filterOrphanedThinkingOnlyMessages(List<Message> messages) {
  return messages.where((msg) {
    if (msg.type != MessageType.assistant) return true;
    final content = msg.content;
    if (content is! List || content.isEmpty) return true;
    // Check if ALL blocks are thinking blocks.
    final allThinking = content.every(
      (block) => block is Map && block['type'] == 'thinking',
    );
    return !allThinking;
  }).toList();
}

/// Filter out assistant messages with only whitespace text content.
/// This can happen when model outputs "\n\n" before thinking, user cancels
/// mid-stream.
List<Message> filterWhitespaceOnlyAssistantMessages(List<Message> messages) {
  return messages.where((msg) {
    if (msg.type != MessageType.assistant) return true;
    final content = msg.content;
    if (content is String) {
      return content.trim().isNotEmpty;
    }
    if (content is List) {
      // Check if all text blocks are whitespace-only.
      final textBlocks = content.where(
        (block) => block is Map && block['type'] == 'text',
      );
      if (textBlocks.isEmpty) return true;
      final allWhitespace = textBlocks.every((block) {
        final text = (block as Map)['text'] as String?;
        return text == null || text.trim().isEmpty;
      });
      return !allWhitespace;
    }
    return true;
  }).toList();
}

/// Check if a message is a tool use result message.
bool isToolUseResultMessage(Message message) {
  if (message.type != MessageType.user) return false;
  final content = message.content;
  if (content is! List || content.isEmpty) return false;
  final first = content[0];
  return first is Map && first['type'] == 'tool_result';
}

/// Create a user message.
Message createUserMessage({
  required String content,
  bool isMeta = false,
}) {
  return Message(
    type: MessageType.user,
    content: content,
    isMeta: isMeta,
  );
}

/// Create an assistant message.
Message createAssistantMessage({
  required String content,
}) {
  return Message(
    type: MessageType.assistant,
    content: content,
  );
}

/// Normalize messages for API consumption.
List<Message> normalizeMessages(List<Message> messages) {
  // In the full implementation, this merges adjacent same-role messages,
  // strips internal-only fields, etc.
  return messages;
}

/// Log an error to the error reporting system.
void logError(Object error) {
  // In the full implementation, this logs to the error reporting service.
  // ignore: avoid_print
  print('[ConversationRecovery] Error: $error');
}
