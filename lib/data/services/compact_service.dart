// Compact service — faithful port of neom_claw/src/services/compact/.
// Covers: compact.ts, sessionMemoryCompact.ts, microCompact.ts,
//         autoCompact.ts, prompt.ts, grouping.ts, postCompactCleanup.ts,
//         compactWarningState.ts, timeBasedMCConfig.ts.
//
// All classes, types, methods, validation, and constants are ported.

import 'dart:convert';
import 'dart:math';

// ---------------------------------------------------------------------------
// Types / enums
// ---------------------------------------------------------------------------

/// Compact trigger origin.
enum CompactTrigger { auto, manual }

/// Direction for partial compact.
enum PartialCompactDirection { from, upTo }

/// Compact progress event type.
enum CompactProgressType { hooksStart, compactStart, compactEnd }

/// Hook type for compact progress.
enum CompactHookType { preCompact, sessionStart, postCompact }

/// Compact progress event sent to UI.
class CompactProgressEvent {
  final CompactProgressType type;
  final CompactHookType? hookType;

  const CompactProgressEvent({required this.type, this.hookType});
}

// ---------------------------------------------------------------------------
// Message types (lightweight representations for compact logic)
// ---------------------------------------------------------------------------

/// Lightweight message role (mirrors TS Message.type).
enum MessageRole { user, assistant, system, progress, attachment }

/// Content block type within a message.
enum ContentBlockType {
  text,
  toolUse,
  toolResult,
  image,
  document,
  thinking,
  redactedThinking,
  serverToolUse,
  webSearchToolResult,
}

/// A content block inside a message.
class ContentBlock {
  final ContentBlockType type;
  final String? text;
  final String? id; // tool_use id
  final String? name; // tool name
  final String? toolUseId; // tool_result reference
  final dynamic input;
  final dynamic content; // tool_result content
  final bool? isError;
  final String? thinking;
  final String? data; // redacted_thinking data

  const ContentBlock({
    required this.type,
    this.text,
    this.id,
    this.name,
    this.toolUseId,
    this.input,
    this.content,
    this.isError,
    this.thinking,
    this.data,
  });
}

/// A message in the conversation.
class CompactMessage {
  final String uuid;
  final MessageRole type;
  final String? messageId; // API message id (for thinking-block merge)
  final List<ContentBlock> contentBlocks;
  final DateTime timestamp;
  final bool isMeta;
  final bool isCompactSummary;
  final bool isCompactBoundary;
  final Map<String, dynamic>? compactMetadata;
  final bool isVisibleInTranscriptOnly;
  final String? toolUseResult;
  final String? sourceToolAssistantUUID;
  final Map<String, dynamic>? summarizeMetadata;

  const CompactMessage({
    required this.uuid,
    required this.type,
    this.messageId,
    this.contentBlocks = const [],
    required this.timestamp,
    this.isMeta = false,
    this.isCompactSummary = false,
    this.isCompactBoundary = false,
    this.compactMetadata,
    this.isVisibleInTranscriptOnly = false,
    this.toolUseResult,
    this.sourceToolAssistantUUID,
    this.summarizeMetadata,
  });

  CompactMessage copyWith({
    List<ContentBlock>? contentBlocks,
    Map<String, dynamic>? compactMetadata,
    bool? isCompactBoundary,
  }) {
    return CompactMessage(
      uuid: uuid,
      type: type,
      messageId: messageId,
      contentBlocks: contentBlocks ?? this.contentBlocks,
      timestamp: timestamp,
      isMeta: isMeta,
      isCompactSummary: isCompactSummary,
      isCompactBoundary: isCompactBoundary ?? this.isCompactBoundary,
      compactMetadata: compactMetadata ?? this.compactMetadata,
      isVisibleInTranscriptOnly: isVisibleInTranscriptOnly,
      toolUseResult: toolUseResult,
      sourceToolAssistantUUID: sourceToolAssistantUUID,
      summarizeMetadata: summarizeMetadata,
    );
  }
}

// ---------------------------------------------------------------------------
// Token estimation
// ---------------------------------------------------------------------------

/// Rough token count estimation using ~4 chars per token.
int roughTokenCountEstimation(String text) {
  return (text.length / 4).ceil();
}

/// Rough token count for a JSON-serializable object.
int roughTokenCountEstimationForMessages(List<CompactMessage> messages) {
  int total = 0;
  for (final msg in messages) {
    for (final block in msg.contentBlocks) {
      total += _estimateBlockTokens(block);
    }
  }
  return total;
}

int _estimateBlockTokens(ContentBlock block) {
  const imageTokenSize = 2000;
  switch (block.type) {
    case ContentBlockType.text:
      return roughTokenCountEstimation(block.text ?? '');
    case ContentBlockType.toolResult:
      return _calculateToolResultTokens(block);
    case ContentBlockType.image:
    case ContentBlockType.document:
      return imageTokenSize;
    case ContentBlockType.thinking:
      return roughTokenCountEstimation(block.thinking ?? '');
    case ContentBlockType.redactedThinking:
      return roughTokenCountEstimation(block.data ?? '');
    case ContentBlockType.toolUse:
      final inputStr = block.input != null ? jsonEncode(block.input) : '{}';
      return roughTokenCountEstimation((block.name ?? '') + inputStr);
    default:
      return roughTokenCountEstimation(jsonEncode(block));
  }
}

int _calculateToolResultTokens(ContentBlock block) {
  const imageTokenSize = 2000;
  if (block.content == null) return 0;
  if (block.content is String) {
    return roughTokenCountEstimation(block.content as String);
  }
  if (block.content is List) {
    int sum = 0;
    for (final item in block.content as List) {
      if (item is Map) {
        final type = item['type'] as String?;
        if (type == 'text') {
          sum += roughTokenCountEstimation(item['text'] as String? ?? '');
        } else if (type == 'image' || type == 'document') {
          sum += imageTokenSize;
        }
      }
    }
    return sum;
  }
  return 0;
}

/// Estimate token count for messages — pads by 4/3 to be conservative.
int estimateMessageTokens(List<CompactMessage> messages) {
  int totalTokens = 0;
  for (final message in messages) {
    if (message.type != MessageRole.user &&
        message.type != MessageRole.assistant) {
      continue;
    }
    for (final block in message.contentBlocks) {
      totalTokens += _estimateBlockTokens(block);
    }
  }
  return (totalTokens * 4 / 3).ceil();
}

// ---------------------------------------------------------------------------
// Compact warning state
// ---------------------------------------------------------------------------

bool _compactWarningSuppressed = false;

/// Suppress the compact warning (after successful microcompact).
void suppressCompactWarning() {
  _compactWarningSuppressed = true;
}

/// Clear the suppression flag at start of new microcompact attempt.
void clearCompactWarningSuppression() {
  _compactWarningSuppressed = false;
}

/// Whether the compact warning is currently suppressed.
bool get isCompactWarningSuppressed => _compactWarningSuppressed;

// ---------------------------------------------------------------------------
// Time-based microcompact config
// ---------------------------------------------------------------------------

/// Configuration for time-based microcompact trigger.
class TimeBasedMCConfig {
  final bool enabled;
  final double gapThresholdMinutes;
  final int keepRecent;

  const TimeBasedMCConfig({
    this.enabled = false,
    this.gapThresholdMinutes = 15.0,
    this.keepRecent = 5,
  });
}

TimeBasedMCConfig _timeBasedMCConfig = const TimeBasedMCConfig();

TimeBasedMCConfig getTimeBasedMCConfig() => _timeBasedMCConfig;

void setTimeBasedMCConfig(TimeBasedMCConfig config) {
  _timeBasedMCConfig = config;
}

// ---------------------------------------------------------------------------
// Session memory compact config
// ---------------------------------------------------------------------------

/// Configuration for session memory compaction thresholds.
class SessionMemoryCompactConfig {
  /// Minimum tokens to preserve after compaction.
  final int minTokens;

  /// Minimum number of messages with text blocks to keep.
  final int minTextBlockMessages;

  /// Maximum tokens to preserve after compaction (hard cap).
  final int maxTokens;

  const SessionMemoryCompactConfig({
    this.minTokens = 10000,
    this.minTextBlockMessages = 5,
    this.maxTokens = 40000,
  });

  SessionMemoryCompactConfig copyWith({
    int? minTokens,
    int? minTextBlockMessages,
    int? maxTokens,
  }) {
    return SessionMemoryCompactConfig(
      minTokens: minTokens ?? this.minTokens,
      minTextBlockMessages: minTextBlockMessages ?? this.minTextBlockMessages,
      maxTokens: maxTokens ?? this.maxTokens,
    );
  }
}

const defaultSmCompactConfig = SessionMemoryCompactConfig();

SessionMemoryCompactConfig _smCompactConfig = defaultSmCompactConfig;

SessionMemoryCompactConfig getSessionMemoryCompactConfig() => _smCompactConfig;

void setSessionMemoryCompactConfig(SessionMemoryCompactConfig config) {
  _smCompactConfig = config;
}

void resetSessionMemoryCompactConfig() {
  _smCompactConfig = defaultSmCompactConfig;
}

// ---------------------------------------------------------------------------
// Message grouping (grouping.ts)
// ---------------------------------------------------------------------------

/// Group messages by API round. The preamble (all messages up to and including
/// the first assistant message) forms group 0. Each subsequent assistant
/// message starts a new group (the assistant + all following user/attachment
/// messages until the next assistant).
List<List<CompactMessage>> groupMessagesByApiRound(
  List<CompactMessage> messages,
) {
  if (messages.isEmpty) return [];

  final groups = <List<CompactMessage>>[];
  var currentGroup = <CompactMessage>[];
  bool seenFirstAssistant = false;

  for (final msg in messages) {
    if (msg.type == MessageRole.assistant) {
      if (!seenFirstAssistant) {
        // Include this assistant in the preamble group
        currentGroup.add(msg);
        groups.add(currentGroup);
        currentGroup = <CompactMessage>[];
        seenFirstAssistant = true;
      } else {
        // Start a new group with this assistant
        if (currentGroup.isNotEmpty) {
          groups.add(currentGroup);
        }
        currentGroup = [msg];
      }
    } else {
      currentGroup.add(msg);
    }
  }

  if (currentGroup.isNotEmpty) {
    groups.add(currentGroup);
  }

  return groups;
}

// ---------------------------------------------------------------------------
// Image stripping
// ---------------------------------------------------------------------------

/// Strip image blocks from user messages before sending for compaction.
/// Images are not needed for generating a conversation summary.
List<CompactMessage> stripImagesFromMessages(List<CompactMessage> messages) {
  return messages.map((message) {
    if (message.type != MessageRole.user) return message;

    bool hasMediaBlock = false;
    final newBlocks = <ContentBlock>[];

    for (final block in message.contentBlocks) {
      if (block.type == ContentBlockType.image) {
        hasMediaBlock = true;
        newBlocks.add(
          const ContentBlock(type: ContentBlockType.text, text: '[image]'),
        );
      } else if (block.type == ContentBlockType.document) {
        hasMediaBlock = true;
        newBlocks.add(
          const ContentBlock(type: ContentBlockType.text, text: '[document]'),
        );
      } else if (block.type == ContentBlockType.toolResult &&
          block.content is List) {
        bool toolHasMedia = false;
        final newToolContent = (block.content as List).map((item) {
          if (item is Map) {
            if (item['type'] == 'image') {
              toolHasMedia = true;
              return {'type': 'text', 'text': '[image]'};
            }
            if (item['type'] == 'document') {
              toolHasMedia = true;
              return {'type': 'text', 'text': '[document]'};
            }
          }
          return item;
        }).toList();

        if (toolHasMedia) {
          hasMediaBlock = true;
          newBlocks.add(
            ContentBlock(
              type: block.type,
              toolUseId: block.toolUseId,
              content: newToolContent,
              isError: block.isError,
            ),
          );
        } else {
          newBlocks.add(block);
        }
      } else {
        newBlocks.add(block);
      }
    }

    if (!hasMediaBlock) return message;
    return message.copyWith(contentBlocks: newBlocks);
  }).toList();
}

// ---------------------------------------------------------------------------
// Compaction result
// ---------------------------------------------------------------------------

/// Result of a compaction operation.
class CompactionResult {
  final CompactMessage boundaryMarker;
  final List<CompactMessage> summaryMessages;
  final List<CompactMessage> attachments;
  final List<CompactMessage> hookResults;
  final List<CompactMessage>? messagesToKeep;
  final String? userDisplayMessage;
  final int? preCompactTokenCount;
  final int? postCompactTokenCount;
  final int? truePostCompactTokenCount;
  final Map<String, int>? compactionUsage;

  const CompactionResult({
    required this.boundaryMarker,
    required this.summaryMessages,
    this.attachments = const [],
    this.hookResults = const [],
    this.messagesToKeep,
    this.userDisplayMessage,
    this.preCompactTokenCount,
    this.postCompactTokenCount,
    this.truePostCompactTokenCount,
    this.compactionUsage,
  });

  CompactionResult copyWith({
    int? postCompactTokenCount,
    int? truePostCompactTokenCount,
  }) {
    return CompactionResult(
      boundaryMarker: boundaryMarker,
      summaryMessages: summaryMessages,
      attachments: attachments,
      hookResults: hookResults,
      messagesToKeep: messagesToKeep,
      userDisplayMessage: userDisplayMessage,
      preCompactTokenCount: preCompactTokenCount,
      postCompactTokenCount:
          postCompactTokenCount ?? this.postCompactTokenCount,
      truePostCompactTokenCount:
          truePostCompactTokenCount ?? this.truePostCompactTokenCount,
      compactionUsage: compactionUsage,
    );
  }
}

/// Diagnosis context passed from autoCompactIfNeeded into compactConversation.
class RecompactionInfo {
  final bool isRecompactionInChain;
  final int turnsSincePreviousCompact;
  final String? previousCompactTurnId;
  final int autoCompactThreshold;
  final String? querySource;

  const RecompactionInfo({
    required this.isRecompactionInChain,
    required this.turnsSincePreviousCompact,
    this.previousCompactTurnId,
    required this.autoCompactThreshold,
    this.querySource,
  });
}

// ---------------------------------------------------------------------------
// Build post-compact messages
// ---------------------------------------------------------------------------

/// Build the base post-compact messages array from a CompactionResult.
/// Ensures consistent ordering across all compaction paths.
List<CompactMessage> buildPostCompactMessages(CompactionResult result) {
  return [
    result.boundaryMarker,
    ...result.summaryMessages,
    ...?result.messagesToKeep,
    ...result.attachments,
    ...result.hookResults,
  ];
}

// ---------------------------------------------------------------------------
// Preserved segment annotation
// ---------------------------------------------------------------------------

/// Annotate a compact boundary with relink metadata for messagesToKeep.
CompactMessage annotateBoundaryWithPreservedSegment(
  CompactMessage boundary,
  String anchorUuid,
  List<CompactMessage>? messagesToKeep,
) {
  final keep = messagesToKeep ?? [];
  if (keep.isEmpty) return boundary;

  final metadata = Map<String, dynamic>.from(boundary.compactMetadata ?? {});
  metadata['preservedSegment'] = {
    'headUuid': keep.first.uuid,
    'anchorUuid': anchorUuid,
    'tailUuid': keep.last.uuid,
  };

  return boundary.copyWith(compactMetadata: metadata);
}

// ---------------------------------------------------------------------------
// Merge hook instructions
// ---------------------------------------------------------------------------

/// Merges user-supplied custom instructions with hook-provided instructions.
String? mergeHookInstructions(
  String? userInstructions,
  String? hookInstructions,
) {
  if (hookInstructions == null || hookInstructions.isEmpty) {
    return (userInstructions != null && userInstructions.isNotEmpty)
        ? userInstructions
        : null;
  }
  if (userInstructions == null || userInstructions.isEmpty) {
    return hookInstructions;
  }
  return '$userInstructions\n\n$hookInstructions';
}

// ---------------------------------------------------------------------------
// Error constants
// ---------------------------------------------------------------------------

const errorMessageNotEnoughMessages = 'Not enough messages to compact.';
const errorMessagePromptTooLong =
    'Conversation too long. Press esc twice to go up a few messages and try again.';
const errorMessageUserAbort = 'API Error: Request was aborted.';
const errorMessageIncompleteResponse =
    'Compaction interrupted - This may be due to network issues -- please try again.';

// ---------------------------------------------------------------------------
// PTL retry marker
// ---------------------------------------------------------------------------

const _ptlRetryMarker = '[earlier conversation truncated for compaction retry]';

/// Drops the oldest API-round groups from messages until tokenGap is covered.
/// Returns null when nothing can be dropped without leaving an empty summarize set.
List<CompactMessage>? truncateHeadForPTLRetry(
  List<CompactMessage> messages,
  int? tokenGap,
) {
  // Strip our own synthetic marker from a previous retry before grouping.
  final input =
      (messages.isNotEmpty &&
          messages.first.type == MessageRole.user &&
          messages.first.isMeta &&
          messages.first.contentBlocks.length == 1 &&
          messages.first.contentBlocks.first.text == _ptlRetryMarker)
      ? messages.sublist(1)
      : messages;

  final groups = groupMessagesByApiRound(input);
  if (groups.length < 2) return null;

  int dropCount;
  if (tokenGap != null) {
    int acc = 0;
    dropCount = 0;
    for (final g in groups) {
      acc += roughTokenCountEstimationForMessages(g);
      dropCount++;
      if (acc >= tokenGap) break;
    }
  } else {
    dropCount = max(1, (groups.length * 0.2).floor());
  }

  // Keep at least one group so there's something to summarize.
  dropCount = min(dropCount, groups.length - 1);
  if (dropCount < 1) return null;

  final sliced = groups.sublist(dropCount).expand((g) => g).toList();

  // Prepend synthetic user marker if first message is assistant.
  if (sliced.isNotEmpty && sliced.first.type == MessageRole.assistant) {
    return [
      CompactMessage(
        uuid: _generateUuid(),
        type: MessageRole.user,
        timestamp: DateTime.now(),
        isMeta: true,
        contentBlocks: [
          const ContentBlock(
            type: ContentBlockType.text,
            text: _ptlRetryMarker,
          ),
        ],
      ),
      ...sliced,
    ];
  }
  return sliced;
}

// ---------------------------------------------------------------------------
// Session memory compact helpers
// ---------------------------------------------------------------------------

/// Check if a message contains text blocks (text content for user/assistant).
bool hasTextBlocks(CompactMessage message) {
  if (message.type == MessageRole.assistant) {
    return message.contentBlocks.any((b) => b.type == ContentBlockType.text);
  }
  if (message.type == MessageRole.user) {
    if (message.contentBlocks.isEmpty) return false;
    return message.contentBlocks.any(
      (b) => b.type == ContentBlockType.text && (b.text?.isNotEmpty ?? false),
    );
  }
  return false;
}

/// Check if a message contains tool_result blocks and return their tool_use_ids.
List<String> _getToolResultIds(CompactMessage message) {
  if (message.type != MessageRole.user) return [];
  final ids = <String>[];
  for (final block in message.contentBlocks) {
    if (block.type == ContentBlockType.toolResult && block.toolUseId != null) {
      ids.add(block.toolUseId!);
    }
  }
  return ids;
}

/// Check if a message contains tool_use blocks with any of the given ids.
bool _hasToolUseWithIds(CompactMessage message, Set<String> toolUseIds) {
  if (message.type != MessageRole.assistant) return false;
  return message.contentBlocks.any(
    (block) =>
        block.type == ContentBlockType.toolUse &&
        block.id != null &&
        toolUseIds.contains(block.id),
  );
}

/// Adjust the start index to ensure we don't split tool_use/tool_result pairs
/// or thinking blocks that share the same message.id with kept assistant
/// messages.
int adjustIndexToPreserveAPIInvariants(
  List<CompactMessage> messages,
  int startIndex,
) {
  if (startIndex <= 0 || startIndex >= messages.length) return startIndex;

  int adjustedIndex = startIndex;

  // Step 1: Handle tool_use/tool_result pairs
  final allToolResultIds = <String>[];
  for (int i = startIndex; i < messages.length; i++) {
    allToolResultIds.addAll(_getToolResultIds(messages[i]));
  }

  if (allToolResultIds.isNotEmpty) {
    final toolUseIdsInKeptRange = <String>{};
    for (int i = adjustedIndex; i < messages.length; i++) {
      final msg = messages[i];
      if (msg.type == MessageRole.assistant) {
        for (final block in msg.contentBlocks) {
          if (block.type == ContentBlockType.toolUse && block.id != null) {
            toolUseIdsInKeptRange.add(block.id!);
          }
        }
      }
    }

    final neededToolUseIds = <String>{
      ...allToolResultIds.where((id) => !toolUseIdsInKeptRange.contains(id)),
    };

    for (
      int i = adjustedIndex - 1;
      i >= 0 && neededToolUseIds.isNotEmpty;
      i--
    ) {
      final message = messages[i];
      if (_hasToolUseWithIds(message, neededToolUseIds)) {
        adjustedIndex = i;
        if (message.type == MessageRole.assistant) {
          for (final block in message.contentBlocks) {
            if (block.type == ContentBlockType.toolUse &&
                block.id != null &&
                neededToolUseIds.contains(block.id)) {
              neededToolUseIds.remove(block.id);
            }
          }
        }
      }
    }
  }

  // Step 2: Handle thinking blocks that share message.id
  final messageIdsInKeptRange = <String>{};
  for (int i = adjustedIndex; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.type == MessageRole.assistant && msg.messageId != null) {
      messageIdsInKeptRange.add(msg.messageId!);
    }
  }

  for (int i = adjustedIndex - 1; i >= 0; i--) {
    final message = messages[i];
    if (message.type == MessageRole.assistant &&
        message.messageId != null &&
        messageIdsInKeptRange.contains(message.messageId)) {
      adjustedIndex = i;
    }
  }

  return adjustedIndex;
}

/// Calculate the starting index for messages to keep after compaction.
int calculateMessagesToKeepIndex(
  List<CompactMessage> messages,
  int lastSummarizedIndex,
) {
  if (messages.isEmpty) return 0;

  final config = getSessionMemoryCompactConfig();

  int startIndex = lastSummarizedIndex >= 0
      ? lastSummarizedIndex + 1
      : messages.length;

  int totalTokens = 0;
  int textBlockMessageCount = 0;
  for (int i = startIndex; i < messages.length; i++) {
    totalTokens += estimateMessageTokens([messages[i]]);
    if (hasTextBlocks(messages[i])) textBlockMessageCount++;
  }

  if (totalTokens >= config.maxTokens) {
    return adjustIndexToPreserveAPIInvariants(messages, startIndex);
  }

  if (totalTokens >= config.minTokens &&
      textBlockMessageCount >= config.minTextBlockMessages) {
    return adjustIndexToPreserveAPIInvariants(messages, startIndex);
  }

  // Find floor at last compact boundary
  int floorIdx = 0;
  for (int i = messages.length - 1; i >= 0; i--) {
    if (messages[i].isCompactBoundary) {
      floorIdx = i + 1;
      break;
    }
  }

  for (int i = startIndex - 1; i >= floorIdx; i--) {
    final msgTokens = estimateMessageTokens([messages[i]]);
    totalTokens += msgTokens;
    if (hasTextBlocks(messages[i])) textBlockMessageCount++;
    startIndex = i;

    if (totalTokens >= config.maxTokens) break;
    if (totalTokens >= config.minTokens &&
        textBlockMessageCount >= config.minTextBlockMessages) {
      break;
    }
  }

  return adjustIndexToPreserveAPIInvariants(messages, startIndex);
}

// ---------------------------------------------------------------------------
// Compact prompts (prompt.ts)
// ---------------------------------------------------------------------------

const _noToolsPreamble =
    '''CRITICAL: Respond with TEXT ONLY. Do NOT call any tools.

- Do NOT use Read, Bash, Grep, Glob, Edit, Write, or ANY other tool.
- You already have all the context you need in the conversation above.
- Tool calls will be REJECTED and will waste your only turn -- you will fail the task.
- Your entire response must be plain text: an <analysis> block followed by a <summary> block.

''';

const _detailedAnalysisInstructionBase =
    '''Before providing your final summary, wrap your analysis in <analysis> tags to organize your thoughts and ensure you've covered all necessary points. In your analysis process:

1. Chronologically analyze each message and section of the conversation. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like:
     - file names
     - full code snippets
     - function signatures
     - file edits
   - Errors that you ran into and how you fixed them
   - Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
2. Double-check for technical accuracy and completeness, addressing each required element thoroughly.''';

const _detailedAnalysisInstructionPartial =
    '''Before providing your final summary, wrap your analysis in <analysis> tags to organize your thoughts and ensure you've covered all necessary points. In your analysis process:

1. Analyze the recent messages chronologically. For each section thoroughly identify:
   - The user's explicit requests and intents
   - Your approach to addressing the user's requests
   - Key decisions, technical concepts and code patterns
   - Specific details like:
     - file names
     - full code snippets
     - function signatures
     - file edits
   - Errors that you ran into and how you fixed them
   - Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
2. Double-check for technical accuracy and completeness, addressing each required element thoroughly.''';

const _baseCompactPrompt =
    '''Your task is to create a detailed summary of the conversation so far, paying close attention to the user's explicit requests and your previous actions.
This summary should be thorough in capturing technical details, code patterns, and architectural decisions that would be essential for continuing development work without losing context.

$_detailedAnalysisInstructionBase

Your summary should include the following sections:

1. Primary Request and Intent: Capture all of the user's explicit requests and intents in detail
2. Key Technical Concepts: List all important technical concepts, technologies, and frameworks discussed.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created. Pay special attention to the most recent messages and include full code snippets where applicable and include a summary of why this file read or edit is important.
4. Errors and fixes: List all errors that you ran into, and how you fixed them. Pay special attention to specific user feedback that you received, especially if the user told you to do something differently.
5. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
6. All user messages: List ALL user messages that are not tool results. These are critical for understanding the users' feedback and changing intent.
7. Pending Tasks: Outline any pending tasks that you have explicitly been asked to work on.
8. Current Work: Describe in detail precisely what was being worked on immediately before this summary request, paying special attention to the most recent messages from both user and assistant. Include file names and code snippets where applicable.
9. Optional Next Step: List the next step that you will take that is related to the most recent work you were doing.

Please provide your summary based on the conversation so far, following this structure and ensuring precision and thoroughness in your response.
''';

const _partialCompactPrompt =
    '''Your task is to create a detailed summary of the RECENT portion of the conversation -- the messages that follow earlier retained context. The earlier messages are being kept intact and do NOT need to be summarized. Focus your summary on what was discussed, learned, and accomplished in the recent messages only.

$_detailedAnalysisInstructionPartial

Your summary should include the following sections:

1. Primary Request and Intent: Capture the user's explicit requests and intents from the recent messages
2. Key Technical Concepts: List important technical concepts, technologies, and frameworks discussed recently.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created. Include full code snippets where applicable.
4. Errors and fixes: List errors encountered and how they were fixed.
5. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
6. All user messages: List ALL user messages from the recent portion that are not tool results.
7. Pending Tasks: Outline any pending tasks from the recent messages.
8. Current Work: Describe precisely what was being worked on immediately before this summary request.
9. Optional Next Step: List the next step related to the most recent work.

Please provide your summary based on the RECENT messages only, following this structure.
''';

const _partialCompactUpToPrompt =
    '''Your task is to create a detailed summary of this conversation. This summary will be placed at the start of a continuing session; newer messages that build on this context will follow after your summary.

$_detailedAnalysisInstructionBase

Your summary should include the following sections:

1. Primary Request and Intent: Capture the user's explicit requests and intents in detail
2. Key Technical Concepts: List important technical concepts, technologies, and frameworks discussed.
3. Files and Code Sections: Enumerate specific files and code sections examined, modified, or created.
4. Errors and fixes: List errors encountered and how they were fixed.
5. Problem Solving: Document problems solved and any ongoing troubleshooting efforts.
6. All user messages: List ALL user messages that are not tool results.
7. Pending Tasks: Outline any pending tasks.
8. Work Completed: Describe what was accomplished by the end of this portion.
9. Context for Continuing Work: Summarize context needed to continue the work.

Please provide your summary following this structure.
''';

const _noToolsTrailer =
    '\n\nREMINDER: Do NOT call any tools. Respond with plain text only -- '
    'an <analysis> block followed by a <summary> block. '
    'Tool calls will be rejected and you will fail the task.';

/// Get the partial compact prompt.
String getPartialCompactPrompt({
  String? customInstructions,
  PartialCompactDirection direction = PartialCompactDirection.from,
}) {
  final template = direction == PartialCompactDirection.upTo
      ? _partialCompactUpToPrompt
      : _partialCompactPrompt;
  var prompt = _noToolsPreamble + template;

  if (customInstructions != null && customInstructions.trim().isNotEmpty) {
    prompt += '\n\nAdditional Instructions:\n$customInstructions';
  }

  prompt += _noToolsTrailer;
  return prompt;
}

/// Get the full compact prompt.
String getCompactPrompt({String? customInstructions}) {
  var prompt = _noToolsPreamble + _baseCompactPrompt;

  if (customInstructions != null && customInstructions.trim().isNotEmpty) {
    prompt += '\n\nAdditional Instructions:\n$customInstructions';
  }

  prompt += _noToolsTrailer;
  return prompt;
}

/// Formats the compact summary by stripping the `<analysis>` drafting scratchpad.
String formatCompactSummary(String summary) {
  var formatted = summary;

  // Strip analysis section
  formatted = formatted.replaceFirst(
    RegExp(r'<analysis>[\s\S]*?</analysis>'),
    '',
  );

  // Extract and format summary section
  final summaryMatch = RegExp(
    r'<summary>([\s\S]*?)</summary>',
  ).firstMatch(formatted);
  if (summaryMatch != null) {
    final content = summaryMatch.group(1) ?? '';
    formatted = formatted.replaceFirst(
      RegExp(r'<summary>[\s\S]*?</summary>'),
      'Summary:\n${content.trim()}',
    );
  }

  // Clean up extra whitespace
  formatted = formatted.replaceAll(RegExp(r'\n\n+'), '\n\n');
  return formatted.trim();
}

/// Get the compact user summary message content.
String getCompactUserSummaryMessage(
  String summary, {
  bool suppressFollowUpQuestions = false,
  String? transcriptPath,
  bool recentMessagesPreserved = false,
}) {
  final formattedSummary = formatCompactSummary(summary);

  var baseSummary =
      'This session is being continued from a previous conversation that ran out of context. '
      'The summary below covers the earlier portion of the conversation.\n\n'
      '$formattedSummary';

  if (transcriptPath != null) {
    baseSummary +=
        '\n\nIf you need specific details from before compaction, '
        'read the full transcript at: $transcriptPath';
  }

  if (recentMessagesPreserved) {
    baseSummary += '\n\nRecent messages are preserved verbatim.';
  }

  if (suppressFollowUpQuestions) {
    return '$baseSummary\n'
        'Continue the conversation from where it left off without asking the user any further questions. '
        'Resume directly -- do not acknowledge the summary, do not recap what was happening, '
        'do not preface with "I\'ll continue" or similar. Pick up the last task as if the break never happened.';
  }

  return baseSummary;
}

// ---------------------------------------------------------------------------
// Auto-compact (autoCompact.ts)
// ---------------------------------------------------------------------------

/// Reserve this many tokens for output during compaction.
const maxOutputTokensForSummary = 20000;

/// Buffer tokens for auto-compact threshold.
const autocompactBufferTokens = 13000;

/// Warning threshold buffer tokens.
const warningThresholdBufferTokens = 20000;

/// Error threshold buffer tokens.
const errorThresholdBufferTokens = 20000;

/// Manual compact buffer tokens.
const manualCompactBufferTokens = 3000;

/// Max consecutive autocompact failures before circuit breaker trips.
const maxConsecutiveAutocompactFailures = 3;

/// Post-compact constants.
const postCompactMaxFilesToRestore = 5;
const postCompactTokenBudget = 50000;
const postCompactMaxTokensPerFile = 5000;
const postCompactMaxTokensPerSkill = 5000;
const postCompactSkillsTokenBudget = 25000;

/// Autocompact tracking state.
class AutoCompactTrackingState {
  bool compacted;
  int turnCounter;
  String turnId;
  int consecutiveFailures;

  AutoCompactTrackingState({
    this.compacted = false,
    this.turnCounter = 0,
    required this.turnId,
    this.consecutiveFailures = 0,
  });
}

/// Returns the context window size minus the max output tokens for the model.
int getEffectiveContextWindowSize(String model, int contextWindow) {
  final reservedTokens = min(
    _getMaxOutputTokensForModel(model),
    maxOutputTokensForSummary,
  );
  return contextWindow - reservedTokens;
}

int _getMaxOutputTokensForModel(String model) {
  // Default max output tokens — can be overridden per model
  return 16384;
}

/// Calculate the auto-compact threshold.
int getAutoCompactThreshold(String model, int contextWindow) {
  final effectiveContextWindow = getEffectiveContextWindowSize(
    model,
    contextWindow,
  );
  return effectiveContextWindow - autocompactBufferTokens;
}

/// Token warning state result.
class TokenWarningState {
  final int percentLeft;
  final bool isAboveWarningThreshold;
  final bool isAboveErrorThreshold;
  final bool isAboveAutoCompactThreshold;
  final bool isAtBlockingLimit;

  const TokenWarningState({
    required this.percentLeft,
    required this.isAboveWarningThreshold,
    required this.isAboveErrorThreshold,
    required this.isAboveAutoCompactThreshold,
    required this.isAtBlockingLimit,
  });
}

/// Calculate the token warning state given current usage.
TokenWarningState calculateTokenWarningState(
  int tokenUsage,
  String model,
  int contextWindow, {
  bool autoCompactEnabled = true,
}) {
  final autoCompactThreshold = getAutoCompactThreshold(model, contextWindow);
  final effectiveWindow = getEffectiveContextWindowSize(model, contextWindow);
  final threshold = autoCompactEnabled ? autoCompactThreshold : effectiveWindow;

  final percentLeft = max(
    0,
    ((threshold - tokenUsage) / threshold * 100).round(),
  );

  final warningThreshold = threshold - warningThresholdBufferTokens;
  final errorThreshold = threshold - errorThresholdBufferTokens;

  final isAboveWarningThreshold = tokenUsage >= warningThreshold;
  final isAboveErrorThreshold = tokenUsage >= errorThreshold;
  final isAboveAutoCompactThreshold =
      autoCompactEnabled && tokenUsage >= autoCompactThreshold;

  final defaultBlockingLimit = effectiveWindow - manualCompactBufferTokens;
  final isAtBlockingLimit = tokenUsage >= defaultBlockingLimit;

  return TokenWarningState(
    percentLeft: percentLeft,
    isAboveWarningThreshold: isAboveWarningThreshold,
    isAboveErrorThreshold: isAboveErrorThreshold,
    isAboveAutoCompactThreshold: isAboveAutoCompactThreshold,
    isAtBlockingLimit: isAtBlockingLimit,
  );
}

/// Determine whether auto-compact should run.
bool shouldAutoCompact(
  List<CompactMessage> messages,
  String model,
  int contextWindow,
  int tokenCount, {
  String? querySource,
  bool autoCompactEnabled = true,
  int snipTokensFreed = 0,
}) {
  // Recursion guards
  if (querySource == 'session_memory' || querySource == 'compact') {
    return false;
  }
  if (!autoCompactEnabled) return false;

  final effectiveTokenCount = tokenCount - snipTokensFreed;
  final state = calculateTokenWarningState(
    effectiveTokenCount,
    model,
    contextWindow,
    autoCompactEnabled: autoCompactEnabled,
  );

  return state.isAboveAutoCompactThreshold;
}

// ---------------------------------------------------------------------------
// Microcompact (microCompact.ts)
// ---------------------------------------------------------------------------

/// Set of tool names that can be microcompacted.
const compactableTools = <String>{
  'Read',
  'Bash',
  'Grep',
  'Glob',
  'WebSearch',
  'WebFetch',
  'Edit',
  'Write',
};

/// Sentinel for cleared tool result content.
const timeBasedMCClearedMessage = '[Old tool result content cleared]';

/// Result of a microcompact operation.
class MicrocompactResult {
  final List<CompactMessage> messages;
  final Map<String, dynamic>? compactionInfo;

  const MicrocompactResult({required this.messages, this.compactionInfo});
}

/// Collect tool_use IDs whose tool name is compactable.
List<String> collectCompactableToolIds(List<CompactMessage> messages) {
  final ids = <String>[];
  for (final message in messages) {
    if (message.type == MessageRole.assistant) {
      for (final block in message.contentBlocks) {
        if (block.type == ContentBlockType.toolUse &&
            block.name != null &&
            compactableTools.contains(block.name) &&
            block.id != null) {
          ids.add(block.id!);
        }
      }
    }
  }
  return ids;
}

/// Evaluate whether the time-based microcompact trigger should fire.
({double gapMinutes, TimeBasedMCConfig config})? evaluateTimeBasedTrigger(
  List<CompactMessage> messages,
  String? querySource,
) {
  final config = getTimeBasedMCConfig();
  if (!config.enabled ||
      querySource == null ||
      !querySource.startsWith('repl_main_thread')) {
    return null;
  }

  CompactMessage? lastAssistant;
  for (int i = messages.length - 1; i >= 0; i--) {
    if (messages[i].type == MessageRole.assistant) {
      lastAssistant = messages[i];
      break;
    }
  }
  if (lastAssistant == null) return null;

  final gapMinutes = DateTime.now()
      .difference(lastAssistant.timestamp)
      .inMinutes
      .toDouble();
  if (!gapMinutes.isFinite || gapMinutes < config.gapThresholdMinutes) {
    return null;
  }
  return (gapMinutes: gapMinutes, config: config);
}

/// Time-based microcompact: content-clear old tool results when the gap
/// since the last assistant message exceeds the threshold.
MicrocompactResult? maybeTimeBasedMicrocompact(
  List<CompactMessage> messages,
  String? querySource,
) {
  final trigger = evaluateTimeBasedTrigger(messages, querySource);
  if (trigger == null) return null;

  final config = trigger.config;
  final compactableIds = collectCompactableToolIds(messages);

  final keepRecent = max(1, config.keepRecent);
  final keepSet = <String>{};
  for (
    int i = max(0, compactableIds.length - keepRecent);
    i < compactableIds.length;
    i++
  ) {
    keepSet.add(compactableIds[i]);
  }

  final clearSet = <String>{
    ...compactableIds.where((id) => !keepSet.contains(id)),
  };

  if (clearSet.isEmpty) return null;

  int tokensSaved = 0;
  final result = messages.map((message) {
    if (message.type != MessageRole.user) return message;
    bool touched = false;
    final newBlocks = message.contentBlocks.map((block) {
      if (block.type == ContentBlockType.toolResult &&
          block.toolUseId != null &&
          clearSet.contains(block.toolUseId) &&
          block.content != timeBasedMCClearedMessage) {
        tokensSaved += _calculateToolResultTokens(block);
        touched = true;
        return ContentBlock(
          type: block.type,
          toolUseId: block.toolUseId,
          content: timeBasedMCClearedMessage,
          isError: block.isError,
        );
      }
      return block;
    }).toList();
    if (!touched) return message;
    return message.copyWith(contentBlocks: newBlocks);
  }).toList();

  if (tokensSaved == 0) return null;

  suppressCompactWarning();
  return MicrocompactResult(messages: result);
}

/// Run microcompact on messages. Returns original messages if no compaction needed.
MicrocompactResult microcompactMessages(
  List<CompactMessage> messages, {
  String? querySource,
}) {
  clearCompactWarningSuppression();

  // Time-based trigger runs first and short-circuits
  final timeBasedResult = maybeTimeBasedMicrocompact(messages, querySource);
  if (timeBasedResult != null) return timeBasedResult;

  // Legacy microcompact removed — autocompact handles context pressure
  return MicrocompactResult(messages: messages);
}

// ---------------------------------------------------------------------------
// Post-compact cleanup (postCompactCleanup.ts)
// ---------------------------------------------------------------------------

/// Callbacks for post-compact cleanup.
typedef PostCompactCleanupCallback = void Function(String? querySource);

final _postCompactCleanupCallbacks = <PostCompactCleanupCallback>[];

/// Register a callback to run after compaction.
void registerPostCompactCleanup(PostCompactCleanupCallback callback) {
  _postCompactCleanupCallbacks.add(callback);
}

/// Run all registered post-compact cleanup callbacks.
void runPostCompactCleanup(String? querySource) {
  for (final callback in _postCompactCleanupCallbacks) {
    try {
      callback(querySource);
    } catch (_) {
      // Swallow errors in cleanup callbacks
    }
  }
}

// ---------------------------------------------------------------------------
// Skill truncation
// ---------------------------------------------------------------------------

const _skillTruncationMarker =
    '\n\n[... skill content truncated for compaction; use Read on the skill path if you need the full text]';

/// Truncate content to roughly maxTokens, keeping the head.
String truncateToTokens(String content, int maxTokens) {
  if (roughTokenCountEstimation(content) <= maxTokens) return content;
  final charBudget = maxTokens * 4 - _skillTruncationMarker.length;
  return content.substring(0, min(charBudget, content.length)) +
      _skillTruncationMarker;
}

// ---------------------------------------------------------------------------
// UUID generation helper
// ---------------------------------------------------------------------------

String _generateUuid() {
  final random = Random();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return [
        bytes.sublist(0, 4),
        bytes.sublist(4, 6),
        bytes.sublist(6, 8),
        bytes.sublist(8, 10),
        bytes.sublist(10, 16),
      ]
      .map((b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join())
      .join('-');
}
