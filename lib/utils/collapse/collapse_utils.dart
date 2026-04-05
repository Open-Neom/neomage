/// Message collapsing/grouping utilities for read, search, bash, hook,
/// background bash, and teammate shutdown operations.
///
/// Ported from:
///   - neomage/src/utils/collapseReadSearch.ts (1109 LOC)
///   - neomage/src/utils/collapseBackgroundBashNotifications.ts (84 LOC)
///   - neomage/src/utils/collapseHookSummaries.ts (59 LOC)
///   - neomage/src/utils/collapseTeammateShutdowns.ts (55 LOC)
///
/// Provides functions to collapse consecutive search/read/bash tool uses
/// into summary groups, collapse hook summaries, background bash notifications,
/// and teammate shutdown messages.
library;

import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// ~5 lines x ~60 cols. Generous static cap for hints.
const int _maxHintChars = 300;

// Tool name constants.
const String bashToolName = 'Bash';
const String fileEditToolName = 'Edit';
const String fileWriteToolName = 'Write';
const String replToolName = 'REPL';
const String toolSearchToolName = 'ToolSearch';

// XML tag constants for background bash notifications.
const String taskNotificationTag = 'task_notification';
const String statusTag = 'status';
const String summaryTag = 'summary';
const String backgroundBashSummaryPrefix = 'Background command:';

// ---------------------------------------------------------------------------
// Types — SearchOrReadResult
// ---------------------------------------------------------------------------

/// Result of checking if a tool use is a search or read operation.
class SearchOrReadResult {
  const SearchOrReadResult({
    this.isCollapsible = false,
    this.isSearch = false,
    this.isRead = false,
    this.isList = false,
    this.isREPL = false,
    this.isMemoryWrite = false,
    this.isAbsorbedSilently = false,
    this.mcpServerName,
    this.isBash,
  });

  final bool isCollapsible;
  final bool isSearch;
  final bool isRead;
  final bool isList;
  final bool isREPL;

  /// True if this is a Write/Edit targeting a memory file.
  final bool isMemoryWrite;

  /// True for meta-operations that should be absorbed into a collapse group
  /// without incrementing any count (Snip, ToolSearch).
  final bool isAbsorbedSilently;

  /// MCP server name when this is an MCP tool.
  final String? mcpServerName;

  /// Bash command that is NOT a search/read (under fullscreen mode).
  final bool? isBash;
}

// ---------------------------------------------------------------------------
// Types — CommitKind / BranchAction / PrAction
// ---------------------------------------------------------------------------

/// Kind of git commit detected.
enum CommitKind { regular, amend, merge }

/// Git branch action detected.
enum BranchAction { create, delete, checkout }

/// Git PR action detected.
enum PrAction { create, merge, close }

/// A detected git commit.
class DetectedCommit {
  const DetectedCommit({required this.sha, required this.kind});
  final String sha;
  final CommitKind kind;
}

/// A detected git push.
class DetectedPush {
  const DetectedPush({required this.branch});
  final String branch;
}

/// A detected git branch operation.
class DetectedBranch {
  const DetectedBranch({required this.ref, required this.action});
  final String ref;
  final BranchAction action;
}

/// A detected PR operation.
class DetectedPr {
  const DetectedPr({required this.number, this.url, required this.action});
  final int number;
  final String? url;
  final PrAction action;
}

// ---------------------------------------------------------------------------
// Types — StopHookInfo
// ---------------------------------------------------------------------------

/// Information about a hook that was stopped.
class StopHookInfo {
  const StopHookInfo({required this.hookName, this.durationMs, this.output});

  final String hookName;
  final int? durationMs;
  final String? output;
}

// ---------------------------------------------------------------------------
// Types — RenderableMessage (simplified)
// ---------------------------------------------------------------------------

/// A simplified renderable message for collapse processing.
class RenderableMessage {
  RenderableMessage({
    required this.type,
    required this.uuid,
    this.timestamp,
    this.message,
    this.subtype,
    this.hookLabel,
    this.hookCount = 0,
    this.hookInfos = const [],
    this.hookErrors = const [],
    this.preventedContinuation = false,
    this.hasOutput = false,
    this.totalDurationMs,
    this.toolName,
    this.messages,
    this.toolUseResult,
    this.attachment,
    this.displayMessage,
  });

  final String
  type; // 'user', 'assistant', 'system', 'attachment', 'grouped_tool_use', 'collapsed_read_search'
  final String uuid;
  final DateTime? timestamp;

  /// For assistant/user messages.
  final MessageData? message;

  /// For system messages.
  final String? subtype;
  final String? hookLabel;
  int hookCount;
  List<StopHookInfo> hookInfos;
  List<String> hookErrors;
  bool preventedContinuation;
  bool hasOutput;
  int? totalDurationMs;

  /// For grouped_tool_use messages.
  final String? toolName;
  final List<RenderableMessage>? messages;

  /// For user messages with tool results.
  final dynamic toolUseResult;

  /// For attachment messages.
  final AttachmentData? attachment;

  /// Display message for collapsed groups.
  final RenderableMessage? displayMessage;
}

/// Simplified message data.
class MessageData {
  const MessageData({
    this.id = '',
    this.role = '',
    this.content = const [],
    this.model,
  });

  final String id;
  final String role;
  final List<Map<String, dynamic>> content;
  final String? model;
}

/// Simplified attachment data.
class AttachmentData {
  const AttachmentData({
    required this.type,
    this.taskType,
    this.status,
    this.count,
    this.memories,
  });

  final String type;
  final String? taskType;
  final String? status;
  final int? count;
  final List<Map<String, dynamic>>? memories;
}

// ---------------------------------------------------------------------------
// Types — CollapsedReadSearchGroup
// ---------------------------------------------------------------------------

/// A collapsed group of read/search operations.
class CollapsedReadSearchGroup {
  CollapsedReadSearchGroup({
    required this.uuid,
    this.timestamp,
    this.searchCount = 0,
    this.readCount = 0,
    this.listCount = 0,
    this.replCount = 0,
    this.memorySearchCount = 0,
    this.memoryReadCount = 0,
    this.memoryWriteCount = 0,
    this.teamMemorySearchCount,
    this.teamMemoryReadCount,
    this.teamMemoryWriteCount,
    this.readFilePaths = const [],
    this.searchArgs = const [],
    this.latestDisplayHint,
    this.messages = const [],
    this.displayMessage,
    this.mcpCallCount,
    this.mcpServerNames,
    this.bashCount,
    this.gitOpBashCount,
    this.commits,
    this.pushes,
    this.branches,
    this.prs,
    this.hookTotalMs,
    this.hookCount,
    this.hookInfos,
    this.relevantMemories,
  });

  final String uuid;
  final DateTime? timestamp;
  final int searchCount;
  final int readCount;
  final int listCount;
  final int replCount;
  final int memorySearchCount;
  final int memoryReadCount;
  final int memoryWriteCount;
  final int? teamMemorySearchCount;
  final int? teamMemoryReadCount;
  final int? teamMemoryWriteCount;
  final List<String> readFilePaths;
  final List<String> searchArgs;
  final String? latestDisplayHint;
  final List<RenderableMessage> messages;
  final RenderableMessage? displayMessage;
  final int? mcpCallCount;
  final List<String>? mcpServerNames;
  final int? bashCount;
  final int? gitOpBashCount;
  final List<DetectedCommit>? commits;
  final List<DetectedPush>? pushes;
  final List<DetectedBranch>? branches;
  final List<DetectedPr>? prs;
  final int? hookTotalMs;
  final int? hookCount;
  final List<StopHookInfo>? hookInfos;
  final List<Map<String, dynamic>>? relevantMemories;
}

// ---------------------------------------------------------------------------
// Types — GroupAccumulator (internal)
// ---------------------------------------------------------------------------

class _GroupAccumulator {
  _GroupAccumulator();

  final List<RenderableMessage> messages = [];
  int searchCount = 0;
  final Set<String> readFilePaths = {};
  int readOperationCount = 0;
  int listCount = 0;
  final Set<String> toolUseIds = {};
  int memorySearchCount = 0;
  final Set<String> memoryReadFilePaths = {};
  int memoryWriteCount = 0;
  int teamMemorySearchCount = 0;
  final Set<String> teamMemoryReadFilePaths = {};
  int teamMemoryWriteCount = 0;
  final List<String> nonMemSearchArgs = [];
  String? latestDisplayHint;
  int mcpCallCount = 0;
  final Set<String> mcpServerNames = {};
  int bashCount = 0;
  final Map<String, String> bashCommands = {};
  final List<DetectedCommit> commits = [];
  final List<DetectedPush> pushes = [];
  final List<DetectedBranch> branches = [];
  final List<DetectedPr> prs = [];
  int gitOpBashCount = 0;
  int hookTotalMs = 0;
  int hookCount = 0;
  final List<StopHookInfo> hookInfos = [];
  List<Map<String, dynamic>>? relevantMemories;
}

// ---------------------------------------------------------------------------
// CollapseUtils — SintController
// ---------------------------------------------------------------------------

/// Manages message collapsing and grouping logic.
///
/// Usage:
/// ```dart
/// final utils = Sint.put(CollapseUtils());
/// final collapsed = utils.collapseReadSearchGroups(messages, tools);
/// ```
class CollapseUtils extends SintController {
  CollapseUtils({
    this.fullscreenEnabled = false,
    this.teamMemEnabled = false,
    this.historySnipEnabled = false,
  });

  /// Feature flags.
  final bool fullscreenEnabled;
  final bool teamMemEnabled;
  final bool historySnipEnabled;

  /// Tool name to isSearchOrRead checker callback.
  /// Set this externally for tool-aware collapsing.
  bool Function(String toolName, dynamic toolInput)? isSearchOrReadChecker;

  /// Memory file detection callbacks.
  bool Function(String path)? isAutoManagedMemoryFile;
  bool Function(String path)? isMemoryDirectory;
  bool Function(String pattern)? isAutoManagedMemoryPattern;
  bool Function(String command)? isShellCommandTargetingMemory;

  // -------------------------------------------------------------------------
  // File path extraction
  // -------------------------------------------------------------------------

  /// Extract the primary file/directory path from a tool_use input.
  static String? getFilePathFromToolInput(dynamic toolInput) {
    if (toolInput is Map) {
      return (toolInput['file_path'] as String?) ??
          (toolInput['path'] as String?);
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Check if tool is search/read
  // -------------------------------------------------------------------------

  /// Checks if a tool is a search/read operation.
  SearchOrReadResult getToolSearchOrReadInfo(
    String toolName,
    dynamic toolInput,
  ) {
    // REPL is absorbed silently.
    if (toolName == replToolName) {
      return const SearchOrReadResult(
        isCollapsible: true,
        isREPL: true,
        isAbsorbedSilently: true,
      );
    }

    // Memory file writes/edits are collapsible.
    if (_isMemoryWriteOrEdit(toolName, toolInput)) {
      return const SearchOrReadResult(isCollapsible: true, isMemoryWrite: true);
    }

    // Meta-operations absorbed silently.
    if ((historySnipEnabled && toolName == 'Snip') ||
        (fullscreenEnabled && toolName == toolSearchToolName)) {
      return const SearchOrReadResult(
        isCollapsible: true,
        isAbsorbedSilently: true,
      );
    }

    // Delegate to external checker.
    if (isSearchOrReadChecker != null &&
        isSearchOrReadChecker!(toolName, toolInput)) {
      return SearchOrReadResult(
        isCollapsible: true,
        isSearch: true,
        isRead: false,
      );
    }

    // Under fullscreen mode, non-search/read Bash commands are also collapsible.
    if (fullscreenEnabled && toolName == bashToolName) {
      return const SearchOrReadResult(isCollapsible: true, isBash: true);
    }

    return const SearchOrReadResult();
  }

  /// Check if a tool_use content block is collapsible.
  SearchOrReadResult? getSearchOrReadFromContent(
    Map<String, dynamic>? content,
  ) {
    if (content == null) return null;
    if (content['type'] == 'tool_use' && content['name'] != null) {
      final info = getToolSearchOrReadInfo(
        content['name'] as String,
        content['input'],
      );
      if (info.isCollapsible || info.isREPL) return info;
    }
    return null;
  }

  bool _isMemoryWriteOrEdit(String toolName, dynamic toolInput) {
    if (toolName != fileWriteToolName && toolName != fileEditToolName) {
      return false;
    }
    final filePath = getFilePathFromToolInput(toolInput);
    if (filePath == null) return false;
    return isAutoManagedMemoryFile?.call(filePath) ?? false;
  }

  bool _isMemorySearch(dynamic toolInput) {
    if (toolInput is! Map) return false;
    final path = toolInput['path'] as String?;
    if (path != null) {
      if (isAutoManagedMemoryFile?.call(path) ?? false) return true;
      if (isMemoryDirectory?.call(path) ?? false) return true;
    }
    final glob = toolInput['glob'] as String?;
    if (glob != null && (isAutoManagedMemoryPattern?.call(glob) ?? false)) {
      return true;
    }
    final command = toolInput['command'] as String?;
    if (command != null &&
        (isShellCommandTargetingMemory?.call(command) ?? false)) {
      return true;
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Format bash command as hint
  // -------------------------------------------------------------------------

  /// Format a bash command for the hint display.
  static String commandAsHint(String command) {
    final cleaned =
        '\$ ${command.split('\n').map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim()).where((l) => l.isNotEmpty).join('\n')}';
    return cleaned.length > _maxHintChars
        ? '${cleaned.substring(0, _maxHintChars - 1)}...'
        : cleaned;
  }

  // -------------------------------------------------------------------------
  // Message classification helpers
  // -------------------------------------------------------------------------

  /// Check if a message is assistant text that should break a group.
  static bool isTextBreaker(RenderableMessage msg) {
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        final first = content.first;
        if (first['type'] == 'text' &&
            (first['text'] as String?)?.trim().isNotEmpty == true) {
          return true;
        }
      }
    }
    return false;
  }

  /// Check if a message should be skipped (not break the group).
  static bool shouldSkipMessage(RenderableMessage msg) {
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        final first = content.first;
        if (first['type'] == 'thinking' ||
            first['type'] == 'redacted_thinking') {
          return true;
        }
      }
    }
    if (msg.type == 'attachment') return true;
    if (msg.type == 'system') return true;
    return false;
  }

  /// Check if a message is a pre-tool hook summary.
  static bool isPreToolHookSummary(RenderableMessage msg) {
    return msg.type == 'system' &&
        msg.subtype == 'stop_hook_summary' &&
        msg.hookLabel == 'PreToolUse';
  }

  /// Get all tool use IDs from a single message.
  static List<String> getToolUseIdsFromMessage(RenderableMessage msg) {
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        final first = content.first;
        if (first['type'] == 'tool_use' && first['id'] != null) {
          return [first['id'] as String];
        }
      }
    }
    if (msg.type == 'grouped_tool_use' && msg.messages != null) {
      return msg.messages!
          .map((m) {
            final c = m.message?.content;
            if (c != null && c.isNotEmpty && c.first['type'] == 'tool_use') {
              return c.first['id'] as String?;
            }
            return null;
          })
          .whereType<String>()
          .toList();
    }
    return [];
  }

  /// Get all tool use IDs from a collapsed group.
  static List<String> getToolUseIdsFromCollapsedGroup(
    CollapsedReadSearchGroup message,
  ) {
    return message.messages
        .expand((msg) => getToolUseIdsFromMessage(msg))
        .toList();
  }

  /// Check if any tool in a collapsed group is in progress.
  static bool hasAnyToolInProgress(
    CollapsedReadSearchGroup message,
    Set<String> inProgressToolUseIDs,
  ) {
    return getToolUseIdsFromCollapsedGroup(
      message,
    ).any((id) => inProgressToolUseIDs.contains(id));
  }

  /// Count the number of tool uses in a message.
  static int countToolUses(RenderableMessage msg) {
    if (msg.type == 'grouped_tool_use' && msg.messages != null) {
      return msg.messages!.length;
    }
    return 1;
  }

  /// Extract file paths from read tool inputs in a message.
  static List<String> getFilePathsFromReadMessage(RenderableMessage msg) {
    final paths = <String>[];
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        final first = content.first;
        if (first['type'] == 'tool_use') {
          final filePath = (first['input'] as Map?)?['file_path'] as String?;
          if (filePath != null) paths.add(filePath);
        }
      }
    } else if (msg.type == 'grouped_tool_use' && msg.messages != null) {
      for (final m in msg.messages!) {
        final content = m.message?.content;
        if (content != null && content.isNotEmpty) {
          final first = content.first;
          if (first['type'] == 'tool_use') {
            final filePath = (first['input'] as Map?)?['file_path'] as String?;
            if (filePath != null) paths.add(filePath);
          }
        }
      }
    }
    return paths;
  }

  // -------------------------------------------------------------------------
  // Create collapsed group from accumulator
  // -------------------------------------------------------------------------

  CollapsedReadSearchGroup _createCollapsedGroup(_GroupAccumulator group) {
    final firstMsg = group.messages.first;
    final totalReadCount = group.readFilePaths.isNotEmpty
        ? group.readFilePaths.length
        : group.readOperationCount;
    final toolMemoryReadCount = group.memoryReadFilePaths.length;
    final memoryReadCount =
        toolMemoryReadCount + (group.relevantMemories?.length ?? 0);
    final nonMemReadFilePaths = group.readFilePaths
        .where(
          (p) =>
              !group.memoryReadFilePaths.contains(p) &&
              !group.teamMemoryReadFilePaths.contains(p),
        )
        .toList();

    final teamMemSearchCount = teamMemEnabled ? group.teamMemorySearchCount : 0;
    final teamMemReadCount = teamMemEnabled
        ? group.teamMemoryReadFilePaths.length
        : 0;
    final teamMemWriteCount = teamMemEnabled ? group.teamMemoryWriteCount : 0;

    return CollapsedReadSearchGroup(
      uuid: 'collapsed-${firstMsg.uuid}',
      timestamp: firstMsg.timestamp,
      searchCount: max(
        0,
        group.searchCount - group.memorySearchCount - teamMemSearchCount,
      ),
      readCount: max(
        0,
        totalReadCount - toolMemoryReadCount - teamMemReadCount,
      ),
      listCount: group.listCount,
      replCount: 0,
      memorySearchCount: group.memorySearchCount,
      memoryReadCount: memoryReadCount,
      memoryWriteCount: group.memoryWriteCount,
      teamMemorySearchCount: teamMemEnabled ? teamMemSearchCount : null,
      teamMemoryReadCount: teamMemEnabled ? teamMemReadCount : null,
      teamMemoryWriteCount: teamMemEnabled ? teamMemWriteCount : null,
      readFilePaths: nonMemReadFilePaths,
      searchArgs: group.nonMemSearchArgs,
      latestDisplayHint: group.latestDisplayHint,
      messages: group.messages,
      displayMessage: firstMsg,
      mcpCallCount: group.mcpCallCount > 0 ? group.mcpCallCount : null,
      mcpServerNames: group.mcpServerNames.isNotEmpty
          ? group.mcpServerNames.toList()
          : null,
      bashCount: fullscreenEnabled && group.bashCount > 0
          ? group.bashCount
          : null,
      gitOpBashCount: fullscreenEnabled && group.gitOpBashCount > 0
          ? group.gitOpBashCount
          : null,
      commits: group.commits.isNotEmpty ? group.commits : null,
      pushes: group.pushes.isNotEmpty ? group.pushes : null,
      branches: group.branches.isNotEmpty ? group.branches : null,
      prs: group.prs.isNotEmpty ? group.prs : null,
      hookTotalMs: group.hookCount > 0 ? group.hookTotalMs : null,
      hookCount: group.hookCount > 0 ? group.hookCount : null,
      hookInfos: group.hookCount > 0 ? group.hookInfos : null,
      relevantMemories:
          group.relevantMemories != null && group.relevantMemories!.isNotEmpty
          ? group.relevantMemories
          : null,
    );
  }

  // -------------------------------------------------------------------------
  // Collapse read/search groups
  // -------------------------------------------------------------------------

  /// Collapse consecutive Read/Search operations into summary groups.
  List<dynamic> collapseReadSearchGroups(List<RenderableMessage> messages) {
    final result = <dynamic>[];
    var currentGroup = _GroupAccumulator();
    var deferredSkippable = <RenderableMessage>[];

    void flushGroup() {
      if (currentGroup.messages.isEmpty) return;
      result.add(_createCollapsedGroup(currentGroup));
      for (final deferred in deferredSkippable) {
        result.add(deferred);
      }
      deferredSkippable = [];
      currentGroup = _GroupAccumulator();
    }

    for (final msg in messages) {
      // Check if collapsible tool use.
      final toolInfo = _getCollapsibleToolInfo(msg);
      if (toolInfo != null) {
        if (toolInfo.isMemoryWrite) {
          final count = countToolUses(msg);
          if (teamMemEnabled) {
            currentGroup.teamMemoryWriteCount += count;
          } else {
            currentGroup.memoryWriteCount += count;
          }
        } else if (toolInfo.isAbsorbedSilently) {
          // Absorbed silently.
        } else if (toolInfo.mcpServerName != null) {
          final count = countToolUses(msg);
          currentGroup.mcpCallCount += count;
          currentGroup.mcpServerNames.add(toolInfo.mcpServerName!);
        } else if (fullscreenEnabled && (toolInfo.isBash ?? false)) {
          final count = countToolUses(msg);
          currentGroup.bashCount += count;
          final input = _getToolInput(msg);
          final command = input?['command'] as String?;
          if (command != null) {
            currentGroup.latestDisplayHint = commandAsHint(command);
            for (final id in getToolUseIdsFromMessage(msg)) {
              currentGroup.bashCommands[id] = command;
            }
          }
        } else if (toolInfo.isList) {
          currentGroup.listCount += countToolUses(msg);
        } else if (toolInfo.isSearch) {
          final count = countToolUses(msg);
          currentGroup.searchCount += count;
          if (_isMemorySearch(_getToolInput(msg))) {
            currentGroup.memorySearchCount += count;
          } else {
            final input = _getToolInput(msg);
            final pattern = input?['pattern'] as String?;
            if (pattern != null) {
              currentGroup.nonMemSearchArgs.add(pattern);
              currentGroup.latestDisplayHint = '"$pattern"';
            }
          }
        } else {
          // Read operations.
          final filePaths = getFilePathsFromReadMessage(msg);
          for (final filePath in filePaths) {
            currentGroup.readFilePaths.add(filePath);
            if (isAutoManagedMemoryFile?.call(filePath) ?? false) {
              currentGroup.memoryReadFilePaths.add(filePath);
            }
          }
          if (filePaths.isEmpty) {
            currentGroup.readOperationCount += countToolUses(msg);
            final input = _getToolInput(msg);
            final command = input?['command'] as String?;
            if (command != null) {
              currentGroup.latestDisplayHint = commandAsHint(command);
            }
          }
        }

        for (final id in getToolUseIdsFromMessage(msg)) {
          currentGroup.toolUseIds.add(id);
        }
        currentGroup.messages.add(msg);
      } else if (_isCollapsibleToolResult(msg, currentGroup.toolUseIds)) {
        currentGroup.messages.add(msg);
      } else if (currentGroup.messages.isNotEmpty &&
          isPreToolHookSummary(msg)) {
        currentGroup.hookCount += msg.hookCount;
        currentGroup.hookTotalMs +=
            msg.totalDurationMs ??
            msg.hookInfos.fold<int>(0, (s, h) => s + (h.durationMs ?? 0));
        currentGroup.hookInfos.addAll(msg.hookInfos);
      } else if (currentGroup.messages.isNotEmpty &&
          msg.type == 'attachment' &&
          msg.attachment?.type == 'relevant_memories') {
        currentGroup.relevantMemories ??= [];
        currentGroup.relevantMemories!.addAll(msg.attachment?.memories ?? []);
      } else if (shouldSkipMessage(msg)) {
        if (currentGroup.messages.isNotEmpty &&
            !(msg.type == 'attachment' &&
                msg.attachment?.type == 'nested_memory')) {
          deferredSkippable.add(msg);
        } else {
          result.add(msg);
        }
      } else if (isTextBreaker(msg)) {
        flushGroup();
        result.add(msg);
      } else {
        // Non-collapsible tool use or user message breaks the group.
        flushGroup();
        result.add(msg);
      }
    }

    flushGroup();
    return result;
  }

  // -------------------------------------------------------------------------
  // Internal helpers for collapse
  // -------------------------------------------------------------------------

  SearchOrReadResult? _getCollapsibleToolInfo(RenderableMessage msg) {
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        final first = content.first;
        if (first['type'] == 'tool_use' && first['name'] != null) {
          final info = getToolSearchOrReadInfo(
            first['name'] as String,
            first['input'],
          );
          if (info.isCollapsible) return info;
        }
      }
    }
    if (msg.type == 'grouped_tool_use' &&
        msg.messages != null &&
        msg.messages!.isNotEmpty) {
      final firstContent = msg.messages!.first.message?.content;
      if (firstContent != null && firstContent.isNotEmpty) {
        final info = getToolSearchOrReadInfo(
          msg.toolName ?? '',
          firstContent.first['input'],
        );
        if (info.isCollapsible) return info;
      }
    }
    return null;
  }

  Map<String, dynamic>? _getToolInput(RenderableMessage msg) {
    if (msg.type == 'assistant') {
      final content = msg.message?.content;
      if (content != null && content.isNotEmpty) {
        return content.first['input'] as Map<String, dynamic>?;
      }
    }
    if (msg.type == 'grouped_tool_use' &&
        msg.messages != null &&
        msg.messages!.isNotEmpty) {
      final firstContent = msg.messages!.first.message?.content;
      if (firstContent != null && firstContent.isNotEmpty) {
        return firstContent.first['input'] as Map<String, dynamic>?;
      }
    }
    return null;
  }

  bool _isCollapsibleToolResult(
    RenderableMessage msg,
    Set<String> collapsibleToolUseIds,
  ) {
    if (msg.type != 'user') return false;
    final content = msg.message?.content ?? [];
    final toolResults = content
        .where((c) => c['type'] == 'tool_result')
        .toList();
    return toolResults.isNotEmpty &&
        toolResults.every(
          (r) => collapsibleToolUseIds.contains(r['tool_use_id']),
        );
  }

  // -------------------------------------------------------------------------
  // Summary text generation
  // -------------------------------------------------------------------------

  /// Generate a summary text for search/read/REPL counts.
  static String getSearchReadSummaryText({
    required int searchCount,
    required int readCount,
    required bool isActive,
    int replCount = 0,
    int memorySearchCount = 0,
    int memoryReadCount = 0,
    int memoryWriteCount = 0,
    int teamMemorySearchCount = 0,
    int teamMemoryReadCount = 0,
    int teamMemoryWriteCount = 0,
    int listCount = 0,
  }) {
    final parts = <String>[];

    // Memory operations first.
    if (memoryReadCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Recalling' : 'recalling')
          : (parts.isEmpty ? 'Recalled' : 'recalled');
      parts.add(
        '$verb $memoryReadCount ${memoryReadCount == 1 ? 'memory' : 'memories'}',
      );
    }
    if (memorySearchCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Searching' : 'searching')
          : (parts.isEmpty ? 'Searched' : 'searched');
      parts.add('$verb memories');
    }
    if (memoryWriteCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Writing' : 'writing')
          : (parts.isEmpty ? 'Wrote' : 'wrote');
      parts.add(
        '$verb $memoryWriteCount ${memoryWriteCount == 1 ? 'memory' : 'memories'}',
      );
    }

    if (searchCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Searching for' : 'searching for')
          : (parts.isEmpty ? 'Searched for' : 'searched for');
      parts.add(
        '$verb $searchCount ${searchCount == 1 ? 'pattern' : 'patterns'}',
      );
    }

    if (readCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Reading' : 'reading')
          : (parts.isEmpty ? 'Read' : 'read');
      parts.add('$verb $readCount ${readCount == 1 ? 'file' : 'files'}');
    }

    if (listCount > 0) {
      final verb = isActive
          ? (parts.isEmpty ? 'Listing' : 'listing')
          : (parts.isEmpty ? 'Listed' : 'listed');
      parts.add(
        '$verb $listCount ${listCount == 1 ? 'directory' : 'directories'}',
      );
    }

    if (replCount > 0) {
      final replVerb = isActive ? "REPL'ing" : "REPL'd";
      parts.add('$replVerb $replCount ${replCount == 1 ? 'time' : 'times'}');
    }

    final text = parts.join(', ');
    return isActive ? '$text...' : text;
  }

  /// Summarize a list of recent tool activities into a compact description.
  static String? summarizeRecentActivities(
    List<Map<String, dynamic>> activities,
  ) {
    if (activities.isEmpty) return null;

    var searchCount = 0;
    var readCount = 0;
    for (var i = activities.length - 1; i >= 0; i--) {
      final activity = activities[i];
      if (activity['isSearch'] == true) {
        searchCount++;
      } else if (activity['isRead'] == true) {
        readCount++;
      } else {
        break;
      }
    }

    final collapsibleCount = searchCount + readCount;
    if (collapsibleCount >= 2) {
      return getSearchReadSummaryText(
        searchCount: searchCount,
        readCount: readCount,
        isActive: true,
      );
    }

    // Fall back to most recent activity with a description.
    for (var i = activities.length - 1; i >= 0; i--) {
      final desc = activities[i]['activityDescription'] as String?;
      if (desc != null && desc.isNotEmpty) return desc;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Collapse background bash notifications
  // -------------------------------------------------------------------------

  /// Collapses consecutive completed-background-bash task-notifications into a
  /// single synthetic "N background commands completed" notification.
  static List<RenderableMessage> collapseBackgroundBashNotifications(
    List<RenderableMessage> messages, {
    required bool verbose,
    required bool fullscreenEnabled,
  }) {
    if (!fullscreenEnabled) return messages;
    if (verbose) return messages;

    final result = <RenderableMessage>[];
    var i = 0;

    while (i < messages.length) {
      final msg = messages[i];
      if (_isCompletedBackgroundBash(msg)) {
        var count = 0;
        while (i < messages.length && _isCompletedBackgroundBash(messages[i])) {
          count++;
          i++;
        }
        if (count == 1) {
          result.add(msg);
        } else {
          result.add(
            RenderableMessage(
              type: msg.type,
              uuid: msg.uuid,
              timestamp: msg.timestamp,
              message: MessageData(
                role: 'user',
                content: [
                  {
                    'type': 'text',
                    'text':
                        '<$taskNotificationTag><$statusTag>completed</$statusTag><$summaryTag>$count background commands completed</$summaryTag></$taskNotificationTag>',
                  },
                ],
              ),
            ),
          );
        }
      } else {
        result.add(msg);
        i++;
      }
    }

    return result;
  }

  static bool _isCompletedBackgroundBash(RenderableMessage msg) {
    if (msg.type != 'user') return false;
    final content = msg.message?.content;
    if (content == null || content.isEmpty) return false;
    final first = content.first;
    if (first['type'] != 'text') return false;
    final text = first['text'] as String? ?? '';
    if (!text.contains('<$taskNotificationTag')) return false;
    if (!text.contains('<$statusTag>completed</$statusTag>')) return false;
    final summaryMatch = RegExp(
      '<$summaryTag>(.*?)</$summaryTag>',
    ).firstMatch(text);
    if (summaryMatch == null) return false;
    return summaryMatch.group(1)?.startsWith(backgroundBashSummaryPrefix) ??
        false;
  }

  // -------------------------------------------------------------------------
  // Collapse hook summaries
  // -------------------------------------------------------------------------

  /// Collapses consecutive hook summary messages with the same hookLabel
  /// into a single summary.
  static List<RenderableMessage> collapseHookSummaries(
    List<RenderableMessage> messages,
  ) {
    final result = <RenderableMessage>[];
    var i = 0;

    while (i < messages.length) {
      final msg = messages[i];
      if (_isLabeledHookSummary(msg)) {
        final label = msg.hookLabel;
        final group = <RenderableMessage>[];
        while (i < messages.length) {
          final next = messages[i];
          if (!_isLabeledHookSummary(next) || next.hookLabel != label) break;
          group.add(next);
          i++;
        }
        if (group.length == 1) {
          result.add(msg);
        } else {
          result.add(
            RenderableMessage(
              type: msg.type,
              uuid: msg.uuid,
              timestamp: msg.timestamp,
              subtype: msg.subtype,
              hookLabel: msg.hookLabel,
              hookCount: group.fold<int>(0, (s, m) => s + m.hookCount),
              hookInfos: group.expand((m) => m.hookInfos).toList(),
              hookErrors: group.expand((m) => m.hookErrors).toList(),
              preventedContinuation: group.any((m) => m.preventedContinuation),
              hasOutput: group.any((m) => m.hasOutput),
              totalDurationMs: group
                  .map((m) => m.totalDurationMs ?? 0)
                  .reduce((a, b) => max(a, b)),
            ),
          );
        }
      } else {
        result.add(msg);
        i++;
      }
    }

    return result;
  }

  static bool _isLabeledHookSummary(RenderableMessage msg) {
    return msg.type == 'system' &&
        msg.subtype == 'stop_hook_summary' &&
        msg.hookLabel != null;
  }

  // -------------------------------------------------------------------------
  // Collapse teammate shutdowns
  // -------------------------------------------------------------------------

  /// Collapses consecutive in-process teammate shutdown task_status
  /// attachments into a single batch attachment with a count.
  static List<RenderableMessage> collapseTeammateShutdowns(
    List<RenderableMessage> messages,
  ) {
    final result = <RenderableMessage>[];
    var i = 0;

    while (i < messages.length) {
      final msg = messages[i];
      if (_isTeammateShutdownAttachment(msg)) {
        var count = 0;
        while (i < messages.length &&
            _isTeammateShutdownAttachment(messages[i])) {
          count++;
          i++;
        }
        if (count == 1) {
          result.add(msg);
        } else {
          result.add(
            RenderableMessage(
              type: 'attachment',
              uuid: msg.uuid,
              timestamp: msg.timestamp,
              attachment: AttachmentData(
                type: 'teammate_shutdown_batch',
                count: count,
              ),
            ),
          );
        }
      } else {
        result.add(msg);
        i++;
      }
    }

    return result;
  }

  static bool _isTeammateShutdownAttachment(RenderableMessage msg) {
    return msg.type == 'attachment' &&
        msg.attachment?.type == 'task_status' &&
        msg.attachment?.taskType == 'in_process_teammate' &&
        msg.attachment?.status == 'completed';
  }
}
