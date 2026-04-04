// Message utilities — port of neom_claw/src/utils/messages.ts.
// Message creation, normalization, reordering, merging, lookup building,
// tag extraction, and API preparation.

import 'package:uuid/uuid.dart';

// ─── Constants ───

const String interruptMessage = '[Request interrupted by user]';
const String interruptMessageForToolUse =
    '[Request interrupted by user for tool use]';
const String cancelMessage =
    "The user doesn't want to take this action right now. STOP what you are "
    'doing and wait for the user to tell you how to proceed.';
const String rejectMessage =
    "The user doesn't want to proceed with this tool use. The tool use was "
    'rejected (eg. if it was a file edit, the new_string was NOT written to '
    'the file). STOP what you are doing and wait for the user to tell you '
    'how to proceed.';
const String rejectMessageWithReasonPrefix =
    "The user doesn't want to proceed with this tool use. The tool use was "
    'rejected (eg. if it was a file edit, the new_string was NOT written to '
    'the file). To tell you how to proceed, the user said:\n';
const String subagentRejectMessage =
    'Permission for this tool use was denied. The tool use was rejected '
    '(eg. if it was a file edit, the new_string was NOT written to the file). '
    'Try a different approach or report the limitation to complete your task.';
const String subagentRejectMessageWithReasonPrefix =
    'Permission for this tool use was denied. The tool use was rejected '
    '(eg. if it was a file edit, the new_string was NOT written to the file). '
    'The user said:\n';
const String planRejectionPrefix =
    'The agent proposed a plan that was rejected by the user. The user chose '
    'to stay in plan mode rather than proceed with implementation.\n\n'
    'Rejected plan:\n';
const String denialWorkaroundGuidance =
    'IMPORTANT: You *may* attempt to accomplish this action using other tools '
    'that might naturally be used to accomplish this goal, e.g. using head '
    'instead of cat. But you *should not* attempt to work around this denial '
    'in malicious ways, e.g. do not use your ability to run tests to execute '
    'non-test actions. You should only try to work around this restriction '
    'in reasonable ways that do not attempt to bypass the intent behind this '
    'denial. If you believe this capability is essential to complete the '
    "user's request, STOP and explain to the user what you were trying to do "
    'and why you need this permission. Let the user decide how to proceed.';
const String noResponseRequested = 'No response requested.';
const String syntheticToolResultPlaceholder =
    '[Tool result missing due to internal error]';
const String noContentMessage = '[No content]';
const String syntheticModel = '<synthetic>';

const String _memoryCorrectionHint =
    "\n\nNote: The user's next message may contain a correction or preference. "
    "Pay close attention \u2014 if they explain what went wrong or how they'd "
    'prefer you to work, consider saving that to memory for future sessions.';

const String _autoModeRejectionPrefix =
    'Permission for this action has been denied. Reason: ';

final Set<String> syntheticMessages = {
  interruptMessage,
  interruptMessageForToolUse,
  cancelMessage,
  rejectMessage,
  noResponseRequested,
};

// ─── Enums & Types ───

/// Message types in the conversation.
enum MessageType { user, assistant, attachment, progress, system }

/// System message subtypes.
enum SystemMessageSubtype {
  apiError,
  localCommand,
  informational,
  turnDuration,
  compactBoundary,
  microcompactBoundary,
  memorySaved,
  permissionRetry,
  stopHookSummary,
  agentsKilled,
  bridgeStatus,
  apiMetrics,
  scheduledTaskFire,
  awaySummary,
}

/// System message severity level.
enum SystemMessageLevel { info, warning, error }

/// Permission mode for message context.
enum PermissionMode { normal, auto, dontAsk, bypassAll }

/// Origin of a message.
enum MessageOrigin {
  human,
  hook,
  queuedCommand,
  slashCommand,
  autoCompact,
  skillTool,
  taskCreate,
  taskOutput,
  sendMessage,
}

/// Hook event types.
enum HookEvent {
  preToolUse,
  postToolUse,
  notification,
  stop,
  instructionsLoaded,
}

// ─── Content Block Types ───

/// A content block within a message.
abstract class ContentBlock {
  String get type;
  Map<String, dynamic> toJson();
}

/// Text content block.
class TextBlock extends ContentBlock {
  final String text;

  TextBlock({required this.text});

  @override
  String get type => 'text';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'text': text};

  TextBlock copyWith({String? text}) => TextBlock(text: text ?? this.text);
}

/// Tool use content block.
class ToolUseBlock extends ContentBlock {
  final String id;
  final String name;
  final Map<String, dynamic> input;
  final String? caller;

  ToolUseBlock({
    required this.id,
    required this.name,
    required this.input,
    this.caller,
  });

  @override
  String get type => 'tool_use';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'id': id,
    'name': name,
    'input': input,
    if (caller != null) 'caller': caller,
  };

  ToolUseBlock copyWith({
    String? id,
    String? name,
    Map<String, dynamic>? input,
    String? caller,
  }) => ToolUseBlock(
    id: id ?? this.id,
    name: name ?? this.name,
    input: input ?? this.input,
    caller: caller ?? this.caller,
  );
}

/// Tool result content block.
class ToolResultBlock extends ContentBlock {
  final String toolUseId;
  final dynamic content; // String or List<ContentBlock>
  final bool isError;

  ToolResultBlock({
    required this.toolUseId,
    this.content,
    this.isError = false,
  });

  @override
  String get type => 'tool_result';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'tool_use_id': toolUseId,
    if (content != null) 'content': content,
    if (isError) 'is_error': isError,
  };
}

/// Image content block.
class ImageBlock extends ContentBlock {
  final String mediaType;
  final String data;
  final String sourceType;

  ImageBlock({
    required this.mediaType,
    required this.data,
    this.sourceType = 'base64',
  });

  @override
  String get type => 'image';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'source': {'type': sourceType, 'media_type': mediaType, 'data': data},
  };
}

// ─── Message Types ───

/// Usage statistics for an API response.
class Usage {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;
  final int webSearchRequests;

  const Usage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.webSearchRequests = 0,
  });

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
    'cache_read_input_tokens': cacheReadInputTokens,
    'server_tool_use': {'web_search_requests': webSearchRequests},
  };
}

/// Base message type.
abstract class Message {
  MessageType get type;
  String get uuid;
  String get timestamp;

  Map<String, dynamic> toJson();
}

/// User message.
class UserMessage extends Message {
  @override
  final String uuid;
  @override
  final String timestamp;
  final dynamic content; // String or List<ContentBlock>
  final bool? isMeta;
  final bool? isVisibleInTranscriptOnly;
  final bool? isVirtual;
  final bool? isCompactSummary;
  final dynamic toolUseResult;
  final Map<String, dynamic>? mcpMeta;
  final List<int>? imagePasteIds;
  final String? sourceToolAssistantUUID;
  final PermissionMode? permissionMode;
  final MessageOrigin? origin;
  final Map<String, dynamic>? summarizeMetadata;

  UserMessage({
    String? uuid,
    String? timestamp,
    required this.content,
    this.isMeta,
    this.isVisibleInTranscriptOnly,
    this.isVirtual,
    this.isCompactSummary,
    this.toolUseResult,
    this.mcpMeta,
    this.imagePasteIds,
    this.sourceToolAssistantUUID,
    this.permissionMode,
    this.origin,
    this.summarizeMetadata,
  }) : uuid = uuid ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  @override
  MessageType get type => MessageType.user;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'user',
    'uuid': uuid,
    'timestamp': timestamp,
    'message': {
      'role': 'user',
      'content': content is String
          ? content
          : (content as List).map((b) => (b as ContentBlock).toJson()).toList(),
    },
    if (isMeta == true) 'isMeta': true,
    if (isVisibleInTranscriptOnly == true) 'isVisibleInTranscriptOnly': true,
    if (isVirtual == true) 'isVirtual': true,
    if (isCompactSummary == true) 'isCompactSummary': true,
  };

  UserMessage copyWith({
    String? uuid,
    String? timestamp,
    dynamic content,
    bool? isMeta,
    bool? isVirtual,
    List<int>? imagePasteIds,
    MessageOrigin? origin,
  }) => UserMessage(
    uuid: uuid ?? this.uuid,
    timestamp: timestamp ?? this.timestamp,
    content: content ?? this.content,
    isMeta: isMeta ?? this.isMeta,
    isVisibleInTranscriptOnly: isVisibleInTranscriptOnly,
    isVirtual: isVirtual ?? this.isVirtual,
    isCompactSummary: isCompactSummary,
    toolUseResult: toolUseResult,
    mcpMeta: mcpMeta,
    imagePasteIds: imagePasteIds ?? this.imagePasteIds,
    sourceToolAssistantUUID: sourceToolAssistantUUID,
    permissionMode: permissionMode,
    origin: origin ?? this.origin,
    summarizeMetadata: summarizeMetadata,
  );
}

/// Assistant message.
class AssistantMessage extends Message {
  @override
  final String uuid;
  @override
  final String timestamp;
  final String messageId;
  final String model;
  final List<ContentBlock> content;
  final Usage usage;
  final String? stopReason;
  final String? requestId;
  final bool isApiErrorMessage;
  final bool? isVirtual;
  final Map<String, dynamic>? apiError;
  final Map<String, dynamic>? error;
  final String? errorDetails;
  final String? advisorModel;

  AssistantMessage({
    String? uuid,
    String? timestamp,
    String? messageId,
    this.model = syntheticModel,
    required this.content,
    this.usage = const Usage(),
    this.stopReason = 'stop_sequence',
    this.requestId,
    this.isApiErrorMessage = false,
    this.isVirtual,
    this.apiError,
    this.error,
    this.errorDetails,
    this.advisorModel,
  }) : uuid = uuid ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String(),
       messageId = messageId ?? const Uuid().v4();

  @override
  MessageType get type => MessageType.assistant;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'assistant',
    'uuid': uuid,
    'timestamp': timestamp,
    'message': {
      'id': messageId,
      'model': model,
      'role': 'assistant',
      'stop_reason': stopReason,
      'type': 'message',
      'usage': usage.toJson(),
      'content': content.map((b) => b.toJson()).toList(),
    },
    if (requestId != null) 'requestId': requestId,
    if (isApiErrorMessage) 'isApiErrorMessage': true,
    if (isVirtual == true) 'isVirtual': true,
  };

  AssistantMessage copyWith({
    String? uuid,
    String? timestamp,
    String? messageId,
    String? model,
    List<ContentBlock>? content,
    Usage? usage,
    String? requestId,
    bool? isApiErrorMessage,
    bool? isVirtual,
  }) => AssistantMessage(
    uuid: uuid ?? this.uuid,
    timestamp: timestamp ?? this.timestamp,
    messageId: messageId ?? this.messageId,
    model: model ?? this.model,
    content: content ?? this.content,
    usage: usage ?? this.usage,
    requestId: requestId ?? this.requestId,
    isApiErrorMessage: isApiErrorMessage ?? this.isApiErrorMessage,
    isVirtual: isVirtual ?? this.isVirtual,
    apiError: apiError,
    error: error,
    errorDetails: errorDetails,
    advisorModel: advisorModel,
  );
}

/// Progress message for tool execution.
class ProgressMessage extends Message {
  @override
  final String uuid;
  @override
  final String timestamp;
  final String toolUseID;
  final String parentToolUseID;
  final Map<String, dynamic> data;

  ProgressMessage({
    String? uuid,
    String? timestamp,
    required this.toolUseID,
    required this.parentToolUseID,
    required this.data,
  }) : uuid = uuid ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  @override
  MessageType get type => MessageType.progress;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'progress',
    'uuid': uuid,
    'timestamp': timestamp,
    'toolUseID': toolUseID,
    'parentToolUseID': parentToolUseID,
    'data': data,
  };
}

/// System message.
class SystemMessage extends Message {
  @override
  final String uuid;
  @override
  final String timestamp;
  final SystemMessageSubtype subtype;
  final SystemMessageLevel level;
  final String content;
  final Map<String, dynamic>? metadata;

  SystemMessage({
    String? uuid,
    String? timestamp,
    required this.subtype,
    this.level = SystemMessageLevel.info,
    required this.content,
    this.metadata,
  }) : uuid = uuid ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  @override
  MessageType get type => MessageType.system;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'system',
    'uuid': uuid,
    'timestamp': timestamp,
    'subtype': subtype.name,
    'level': level.name,
    'content': content,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Attachment message.
class AttachmentMessage extends Message {
  @override
  final String uuid;
  @override
  final String timestamp;
  final Map<String, dynamic> attachment;

  AttachmentMessage({String? uuid, String? timestamp, required this.attachment})
    : uuid = uuid ?? const Uuid().v4(),
      timestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();

  @override
  MessageType get type => MessageType.attachment;

  @override
  Map<String, dynamic> toJson() => {
    'type': 'attachment',
    'uuid': uuid,
    'timestamp': timestamp,
    'attachment': attachment,
  };
}

// ─── Normalized Message (single content block per message) ───

/// A normalized message with exactly one content block.
class NormalizedMessage {
  final Message original;

  const NormalizedMessage(this.original);

  MessageType get type => original.type;
  String get uuid => original.uuid;
  String get timestamp => original.timestamp;
}

// ─── Message Lookups (pre-computed O(1) lookup tables) ───

/// Pre-computed lookups for O(1) access to message relationships.
class MessageLookups {
  final Map<String, Set<String>> siblingToolUseIDs;
  final Map<String, List<ProgressMessage>> progressMessagesByToolUseID;
  final Map<String, Map<HookEvent, int>> inProgressHookCounts;
  final Map<String, Map<HookEvent, int>> resolvedHookCounts;
  final Map<String, NormalizedMessage> toolResultByToolUseID;
  final Map<String, ToolUseBlock> toolUseByToolUseID;
  final int normalizedMessageCount;
  final Set<String> resolvedToolUseIDs;
  final Set<String> erroredToolUseIDs;

  const MessageLookups({
    this.siblingToolUseIDs = const {},
    this.progressMessagesByToolUseID = const {},
    this.inProgressHookCounts = const {},
    this.resolvedHookCounts = const {},
    this.toolResultByToolUseID = const {},
    this.toolUseByToolUseID = const {},
    this.normalizedMessageCount = 0,
    this.resolvedToolUseIDs = const {},
    this.erroredToolUseIDs = const {},
  });

  static const empty = MessageLookups();
}

// ─── Message Creation Functions ───

/// Create a user message with the given content.
UserMessage createUserMessage({
  required dynamic content,
  bool? isMeta,
  bool? isVisibleInTranscriptOnly,
  bool? isVirtual,
  bool? isCompactSummary,
  dynamic toolUseResult,
  Map<String, dynamic>? mcpMeta,
  String? uuid,
  String? timestamp,
  List<int>? imagePasteIds,
  String? sourceToolAssistantUUID,
  PermissionMode? permissionMode,
  MessageOrigin? origin,
  Map<String, dynamic>? summarizeMetadata,
}) {
  final effectiveContent = (content is String && content.isEmpty)
      ? noContentMessage
      : content;
  return UserMessage(
    uuid: uuid,
    timestamp: timestamp,
    content: effectiveContent,
    isMeta: isMeta,
    isVisibleInTranscriptOnly: isVisibleInTranscriptOnly,
    isVirtual: isVirtual,
    isCompactSummary: isCompactSummary,
    toolUseResult: toolUseResult,
    mcpMeta: mcpMeta,
    imagePasteIds: imagePasteIds,
    sourceToolAssistantUUID: sourceToolAssistantUUID,
    permissionMode: permissionMode,
    origin: origin,
    summarizeMetadata: summarizeMetadata,
  );
}

/// Create an assistant message.
AssistantMessage createAssistantMessage({
  required dynamic content,
  Usage? usage,
  bool? isVirtual,
}) {
  final List<ContentBlock> blocks;
  if (content is String) {
    blocks = [TextBlock(text: content.isEmpty ? noContentMessage : content)];
  } else {
    blocks = content as List<ContentBlock>;
  }
  return AssistantMessage(
    content: blocks,
    usage: usage ?? const Usage(),
    isVirtual: isVirtual,
  );
}

/// Create an assistant API error message.
AssistantMessage createAssistantAPIErrorMessage({
  required String content,
  Map<String, dynamic>? apiError,
  Map<String, dynamic>? error,
  String? errorDetails,
}) {
  return AssistantMessage(
    content: [TextBlock(text: content.isEmpty ? noContentMessage : content)],
    isApiErrorMessage: true,
    apiError: apiError,
    error: error,
    errorDetails: errorDetails,
  );
}

/// Create a user interruption message.
UserMessage createUserInterruptionMessage({bool toolUse = false}) {
  final text = toolUse ? interruptMessageForToolUse : interruptMessage;
  return createUserMessage(content: [TextBlock(text: text)]);
}

/// Create a progress message.
ProgressMessage createProgressMessage({
  required String toolUseID,
  required String parentToolUseID,
  required Map<String, dynamic> data,
}) {
  return ProgressMessage(
    toolUseID: toolUseID,
    parentToolUseID: parentToolUseID,
    data: data,
  );
}

/// Create a tool result stop message.
ToolResultBlock createToolResultStopMessage(String toolUseID) {
  return ToolResultBlock(
    toolUseId: toolUseID,
    content: cancelMessage,
    isError: true,
  );
}

// ─── Message Query Functions ───

/// Derive a short stable message ID (6-char base36) from a UUID.
String deriveShortMessageId(String uuid) {
  final hex = uuid.replaceAll('-', '').substring(0, 10);
  return int.parse(hex, radix: 16).toRadixString(36).substring(0, 6);
}

/// Deterministic UUID derivation from parent UUID + index.
String deriveUUID(String parentUUID, int index) {
  final hex = index.toRadixString(16).padLeft(12, '0');
  return '${parentUUID.substring(0, 24)}$hex';
}

/// Append a memory correction hint when auto-memory is enabled.
String withMemoryCorrectionHint(
  String message, {
  bool autoMemoryEnabled = false,
}) {
  if (autoMemoryEnabled) {
    return message + _memoryCorrectionHint;
  }
  return message;
}

/// Build an auto-reject message for a denied tool.
String autoRejectMessage(String toolName) {
  return 'Permission to use $toolName has been denied. $denialWorkaroundGuidance';
}

/// Build a don't-ask reject message for a denied tool.
String dontAskRejectMessage(String toolName) {
  return 'Permission to use $toolName has been denied because NeomClaw is '
      'running in don\'t ask mode. $denialWorkaroundGuidance';
}

/// Check if a tool result is a classifier denial.
bool isClassifierDenial(String content) {
  return content.startsWith(_autoModeRejectionPrefix);
}

/// Build a rejection message for auto mode classifier denials.
String buildYoloRejectionMessage(String reason) {
  return '$_autoModeRejectionPrefix$reason. '
      "If you have other tasks that don't depend on this action, continue "
      'working on those. $denialWorkaroundGuidance '
      'To allow this type of action in the future, the user can add a '
      'permission rule to their settings.';
}

/// Build a message for when the classifier is temporarily unavailable.
String buildClassifierUnavailableMessage(
  String toolName,
  String classifierModel,
) {
  return '$classifierModel is temporarily unavailable, so auto mode cannot '
      'determine the safety of $toolName right now. Wait briefly and then '
      'try this action again. If it keeps failing, continue with other '
      "tasks that don't require this action and come back to it later. "
      'Note: reading files, searching code, and other read-only operations '
      'do not require the classifier and can still be used.';
}

/// Check if a message is synthetic (interrupt, cancel, reject, etc.).
bool isSyntheticMessage(Message message) {
  if (message is! UserMessage && message is! AssistantMessage) return false;

  dynamic content;
  if (message is UserMessage) {
    content = message.content;
  } else if (message is AssistantMessage) {
    content = message.content;
  }

  if (content is List && content.isNotEmpty) {
    final first = content[0];
    if (first is TextBlock) {
      return syntheticMessages.contains(first.text);
    }
  }
  return false;
}

/// Get the last assistant message from a list.
AssistantMessage? getLastAssistantMessage(List<Message> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i] is AssistantMessage) {
      return messages[i] as AssistantMessage;
    }
  }
  return null;
}

/// Check if the last assistant turn has tool calls.
bool hasToolCallsInLastAssistantTurn(List<Message> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    if (messages[i] is AssistantMessage) {
      final msg = messages[i] as AssistantMessage;
      return msg.content.any((block) => block is ToolUseBlock);
    }
  }
  return false;
}

/// Check if a message is not empty.
bool isNotEmptyMessage(Message message) {
  if (message is ProgressMessage ||
      message is AttachmentMessage ||
      message is SystemMessage) {
    return true;
  }

  if (message is UserMessage) {
    if (message.content is String) {
      return (message.content as String).trim().isNotEmpty;
    }
    final blocks = message.content as List;
    if (blocks.isEmpty) return false;
    if (blocks.length > 1) return true;
    final first = blocks[0];
    if (first is TextBlock) {
      return first.text.trim().isNotEmpty &&
          first.text != noContentMessage &&
          first.text != interruptMessageForToolUse;
    }
    return true;
  }

  if (message is AssistantMessage) {
    if (message.content.isEmpty) return false;
    if (message.content.length > 1) return true;
    final first = message.content[0];
    if (first is TextBlock) {
      return first.text.trim().isNotEmpty &&
          first.text != noContentMessage &&
          first.text != interruptMessageForToolUse;
    }
    return true;
  }

  return true;
}

/// Check if a message is a tool use request.
bool isToolUseRequestMessage(Message message) {
  if (message is! AssistantMessage) return false;
  return message.content.any((b) => b is ToolUseBlock);
}

/// Check if a message is a tool use result.
bool isToolUseResultMessage(Message message) {
  if (message is! UserMessage) return false;
  final content = message.content;
  if (content is List) {
    return content.isNotEmpty && content[0] is ToolResultBlock;
  }
  return message.toolUseResult != null;
}

/// Get the tool use ID from a normalized message.
String? getToolUseID(Message message) {
  if (message is AssistantMessage && message.content.isNotEmpty) {
    final first = message.content[0];
    if (first is ToolUseBlock) return first.id;
  }
  if (message is UserMessage) {
    final content = message.content;
    if (content is List &&
        content.isNotEmpty &&
        content[0] is ToolResultBlock) {
      return (content[0] as ToolResultBlock).toolUseId;
    }
  }
  return null;
}

/// Get all tool use IDs from a list of messages.
Set<String> getToolUseIDs(List<Message> messages) {
  return messages
      .whereType<AssistantMessage>()
      .expand((m) => m.content)
      .whereType<ToolUseBlock>()
      .map((b) => b.id)
      .toSet();
}

/// Get tool result IDs from normalized messages.
Map<String, bool> getToolResultIDs(List<Message> messages) {
  final result = <String, bool>{};
  for (final msg in messages) {
    if (msg is UserMessage) {
      final content = msg.content;
      if (content is List) {
        for (final block in content) {
          if (block is ToolResultBlock) {
            result[block.toolUseId] = block.isError;
          }
        }
      }
    }
  }
  return result;
}

// ─── Tag Extraction ───

/// Extract content from an XML-like tag in a string.
String? extractTag(String html, String tagName) {
  if (html.trim().isEmpty || tagName.trim().isEmpty) return null;

  final escapedTag = RegExp.escape(tagName);
  final pattern = RegExp(
    '<$escapedTag(?:\\s+[^>]*)?>([\\s\\S]*?)</$escapedTag>',
    caseSensitive: false,
  );

  final match = pattern.firstMatch(html);
  if (match != null) {
    final content = match.group(1);
    if (content != null && content.isNotEmpty) return content;
  }
  return null;
}

// ─── Message Merging ───

/// Merge two user messages.
UserMessage mergeUserMessages(UserMessage a, UserMessage b) {
  final lastContent = _normalizeUserTextContent(a.content);
  final currentContent = _normalizeUserTextContent(b.content);
  return a.copyWith(
    uuid: (a.isMeta == true) ? b.uuid : a.uuid,
    content: _hoistToolResults(_joinTextAtSeam(lastContent, currentContent)),
  );
}

/// Merge two user messages including tool results.
UserMessage mergeUserMessagesAndToolResults(UserMessage a, UserMessage b) {
  final lastContent = _normalizeUserTextContent(a.content);
  final currentContent = _normalizeUserTextContent(b.content);
  return a.copyWith(
    content: _hoistToolResults(
      _mergeUserContentBlocks(lastContent, currentContent),
    ),
  );
}

/// Merge two assistant messages.
AssistantMessage mergeAssistantMessages(
  AssistantMessage a,
  AssistantMessage b,
) {
  return a.copyWith(content: [...a.content, ...b.content]);
}

/// Normalize user text content to a list of content blocks.
List<ContentBlock> _normalizeUserTextContent(dynamic content) {
  if (content is String) {
    return [TextBlock(text: content)];
  }
  return List<ContentBlock>.from(content as List);
}

/// Join two content block arrays with a newline at the text-text seam.
List<ContentBlock> _joinTextAtSeam(List<ContentBlock> a, List<ContentBlock> b) {
  if (a.isEmpty || b.isEmpty) return [...a, ...b];
  final lastA = a.last;
  final firstB = b.first;
  if (lastA is TextBlock && firstB is TextBlock) {
    return [
      ...a.sublist(0, a.length - 1),
      lastA.copyWith(text: '${lastA.text}\n'),
      ...b,
    ];
  }
  return [...a, ...b];
}

/// Merge two content block lists.
List<ContentBlock> _mergeUserContentBlocks(
  List<ContentBlock> a,
  List<ContentBlock> b,
) {
  return [...a, ...b];
}

/// Hoist tool_result blocks to the front of the content list.
List<ContentBlock> _hoistToolResults(List<ContentBlock> content) {
  final toolResults = <ContentBlock>[];
  final otherBlocks = <ContentBlock>[];
  for (final block in content) {
    if (block is ToolResultBlock) {
      toolResults.add(block);
    } else {
      otherBlocks.add(block);
    }
  }
  return [...toolResults, ...otherBlocks];
}

// ─── Message Lookup Building ───

/// Build pre-computed lookups for O(1) access to message relationships.
MessageLookups buildMessageLookups(
  List<Message> normalizedMessages,
  List<Message> messages,
) {
  // Group assistant messages by ID and collect all tool use IDs per message
  final toolUseIDsByMessageID = <String, Set<String>>{};
  final toolUseIDToMessageID = <String, String>{};
  final toolUseByToolUseID = <String, ToolUseBlock>{};

  for (final msg in messages) {
    if (msg is AssistantMessage) {
      final id = msg.messageId;
      toolUseIDsByMessageID.putIfAbsent(id, () => <String>{});
      for (final block in msg.content) {
        if (block is ToolUseBlock) {
          toolUseIDsByMessageID[id]!.add(block.id);
          toolUseIDToMessageID[block.id] = id;
          toolUseByToolUseID[block.id] = block;
        }
      }
    }
  }

  // Build sibling lookup
  final siblingToolUseIDs = <String, Set<String>>{};
  for (final entry in toolUseIDToMessageID.entries) {
    siblingToolUseIDs[entry.key] =
        toolUseIDsByMessageID[entry.value] ?? <String>{};
  }

  // Single pass for progress, hook, and tool result lookups
  final progressMessagesByToolUseID = <String, List<ProgressMessage>>{};
  final inProgressHookCounts = <String, Map<HookEvent, int>>{};
  final resolvedHookNames = <String, Map<HookEvent, Set<String>>>{};
  final toolResultByToolUseID = <String, NormalizedMessage>{};
  final resolvedToolUseIDs = <String>{};
  final erroredToolUseIDs = <String>{};

  for (final msg in normalizedMessages) {
    if (msg is ProgressMessage) {
      progressMessagesByToolUseID
          .putIfAbsent(msg.parentToolUseID, () => [])
          .add(msg);

      if (msg.data['type'] == 'hook_progress') {
        final hookEvent = _parseHookEvent(msg.data['hookEvent']);
        if (hookEvent != null) {
          inProgressHookCounts
              .putIfAbsent(msg.parentToolUseID, () => {})
              .update(hookEvent, (v) => v + 1, ifAbsent: () => 1);
        }
      }
    }

    if (msg is UserMessage) {
      final content = msg.content;
      if (content is List) {
        for (final block in content) {
          if (block is ToolResultBlock) {
            toolResultByToolUseID[block.toolUseId] = NormalizedMessage(msg);
            resolvedToolUseIDs.add(block.toolUseId);
            if (block.isError) erroredToolUseIDs.add(block.toolUseId);
          }
        }
      }
    }
  }

  // Convert resolved hook name sets to counts
  final resolvedHookCounts = <String, Map<HookEvent, int>>{};
  for (final entry in resolvedHookNames.entries) {
    final countMap = <HookEvent, int>{};
    for (final hookEntry in entry.value.entries) {
      countMap[hookEntry.key] = hookEntry.value.length;
    }
    resolvedHookCounts[entry.key] = countMap;
  }

  return MessageLookups(
    siblingToolUseIDs: siblingToolUseIDs,
    progressMessagesByToolUseID: progressMessagesByToolUseID,
    inProgressHookCounts: inProgressHookCounts,
    resolvedHookCounts: resolvedHookCounts,
    toolResultByToolUseID: toolResultByToolUseID,
    toolUseByToolUseID: toolUseByToolUseID,
    normalizedMessageCount: normalizedMessages.length,
    resolvedToolUseIDs: resolvedToolUseIDs,
    erroredToolUseIDs: erroredToolUseIDs,
  );
}

/// Check for unresolved hooks using pre-computed lookup.
bool hasUnresolvedHooksFromLookup(
  String toolUseID,
  HookEvent hookEvent,
  MessageLookups lookups,
) {
  final inProgressCount =
      lookups.inProgressHookCounts[toolUseID]?[hookEvent] ?? 0;
  final resolvedCount = lookups.resolvedHookCounts[toolUseID]?[hookEvent] ?? 0;
  return inProgressCount > resolvedCount;
}

/// Get sibling tool use IDs from lookup.
Set<String> getSiblingToolUseIDsFromLookup(
  Message message,
  MessageLookups lookups,
) {
  final toolUseID = getToolUseID(message);
  if (toolUseID == null) return const {};
  return lookups.siblingToolUseIDs[toolUseID] ?? const {};
}

/// Get progress messages from lookup.
List<ProgressMessage> getProgressMessagesFromLookup(
  Message message,
  MessageLookups lookups,
) {
  final toolUseID = getToolUseID(message);
  if (toolUseID == null) return const [];
  return lookups.progressMessagesByToolUseID[toolUseID] ?? const [];
}

// ─── User Content Preparation ───

/// Prepare user content with preceding input blocks.
dynamic prepareUserContent({
  required String inputString,
  required List<ContentBlock> precedingInputBlocks,
}) {
  if (precedingInputBlocks.isEmpty) return inputString;
  return [...precedingInputBlocks, TextBlock(text: inputString)];
}

// ─── Utilities ───

/// Extract text content from a message.
String extractTextContent(Message message) {
  if (message is UserMessage) {
    final content = message.content;
    if (content is String) return content;
    if (content is List) {
      return content.whereType<TextBlock>().map((b) => b.text).join('\n');
    }
  }
  if (message is AssistantMessage) {
    return message.content.whereType<TextBlock>().map((b) => b.text).join('\n');
  }
  return '';
}

/// Get user message text content.
String getUserMessageText(Message message) {
  if (message is! UserMessage) return '';
  return extractTextContent(message);
}

/// Check if a message is a thinking message (extended thinking).
bool isThinkingMessage(Message message) {
  if (message is! AssistantMessage) return false;
  return message.content.any((block) {
    final json = block.toJson();
    return json['type'] == 'thinking' || json['type'] == 'redacted_thinking';
  });
}

/// Parse hook event from string.
HookEvent? _parseHookEvent(dynamic value) {
  if (value is! String) return null;
  return switch (value) {
    'PreToolUse' => HookEvent.preToolUse,
    'PostToolUse' => HookEvent.postToolUse,
    'Notification' => HookEvent.notification,
    'Stop' => HookEvent.stop,
    'InstructionsLoaded' => HookEvent.instructionsLoaded,
    _ => null,
  };
}

/// Wrap text in system-reminder XML tags.
String wrapInSystemReminder(String text) {
  return '<system-reminder>\n$text\n</system-reminder>';
}
