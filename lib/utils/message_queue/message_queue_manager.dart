/// Message queue management, command grouping, memoization, and sequential
/// execution utilities.
///
/// Ported from:
///   - messageQueueManager.ts (547 LOC) -- unified command queue
///   - groupToolUses.ts (182 LOC) -- tool use grouping for rendering
///   - memoize.ts (269 LOC) -- TTL / LRU memoization
///   - sequential.ts (56 LOC) -- sequential async execution wrapper
library;

import 'dart:async';
import 'dart:convert';

import 'package:sint/sint.dart';

// ===========================================================================
// Queue Priority
// ===========================================================================

/// Priority determines dequeue order: now > next > later.
/// Within the same priority, commands are processed FIFO.
enum QueuePriority {
  now(0),
  next(1),
  later(2);

  final int order;
  const QueuePriority(this.order);
}

// ===========================================================================
// Prompt Input Mode
// ===========================================================================

/// The mode in which a prompt was submitted.
enum PromptInputMode {
  normal,
  bash,
  orphanedPermission,
  taskNotification,
  channel,
}

/// Editable prompt input modes (excludes task-notification).
const Set<PromptInputMode> _nonEditableModes = {
  PromptInputMode.taskNotification,
};

/// Whether this mode is editable (can be pulled into the input buffer).
bool isPromptInputModeEditable(PromptInputMode mode) {
  return !_nonEditableModes.contains(mode);
}

// ===========================================================================
// Queue Operation (for logging)
// ===========================================================================

/// Represents a queue operation for logging purposes.
enum QueueOperation {
  enqueue,
  dequeue,
  popAll,
  remove,
}

/// A logged queue operation message.
class QueueOperationMessage {
  final String type;
  final QueueOperation operation;
  final String timestamp;
  final String sessionId;
  final String? content;

  const QueueOperationMessage({
    this.type = 'queue-operation',
    required this.operation,
    required this.timestamp,
    required this.sessionId,
    this.content,
  });
}

// ===========================================================================
// Pasted Content
// ===========================================================================

/// Represents pasted content (images) attached to a queued command.
class PastedContent {
  final int id;
  final String type;
  final String content;
  final String? mediaType;
  final String? filename;

  const PastedContent({
    required this.id,
    required this.type,
    required this.content,
    this.mediaType,
    this.filename,
  });
}

// ===========================================================================
// Content Block (simplified)
// ===========================================================================

/// Simplified content block for queued command values.
sealed class ContentBlock {
  const ContentBlock();
}

/// A text content block.
class TextContentBlock extends ContentBlock {
  final String text;
  const TextContentBlock(this.text);
}

/// An image content block.
class ImageContentBlock extends ContentBlock {
  final String sourceType;
  final String data;
  final String mediaType;

  const ImageContentBlock({
    this.sourceType = 'base64',
    required this.data,
    required this.mediaType,
  });
}

/// A tool result content block.
class ToolResultContentBlock extends ContentBlock {
  final String toolUseId;
  final List<ContentBlock> content;

  const ToolResultContentBlock({
    required this.toolUseId,
    this.content = const [],
  });
}

// ===========================================================================
// Queued Command Value
// ===========================================================================

/// The value of a queued command -- either a string or a list of content blocks.
sealed class QueuedCommandValue {
  const QueuedCommandValue();
}

/// A simple string command value.
class StringCommandValue extends QueuedCommandValue {
  final String value;
  const StringCommandValue(this.value);
}

/// A structured content block command value.
class BlocksCommandValue extends QueuedCommandValue {
  final List<ContentBlock> blocks;
  const BlocksCommandValue(this.blocks);
}

// ===========================================================================
// Command Origin
// ===========================================================================

/// Origin of a queued command.
class CommandOrigin {
  final String kind;
  final String? agentId;

  const CommandOrigin({
    required this.kind,
    this.agentId,
  });
}

// ===========================================================================
// Queued Command
// ===========================================================================

/// A command in the unified command queue.
class QueuedCommand {
  final QueuedCommandValue value;
  final PromptInputMode mode;
  final QueuePriority priority;
  final bool skipSlashCommands;
  final bool isMeta;
  final String? agentId;
  final CommandOrigin? origin;
  final Map<int, PastedContent>? pastedContents;

  const QueuedCommand({
    required this.value,
    required this.mode,
    this.priority = QueuePriority.next,
    this.skipSlashCommands = false,
    this.isMeta = false,
    this.agentId,
    this.origin,
    this.pastedContents,
  });
}

// ===========================================================================
// Pop All Editable Result
// ===========================================================================

/// Result of popping all editable commands from the queue.
class PopAllEditableResult {
  final String text;
  final int cursorOffset;
  final List<PastedContent> images;

  const PopAllEditableResult({
    required this.text,
    required this.cursorOffset,
    required this.images,
  });
}

// ===========================================================================
// Signal (simple pub/sub for queue change notifications)
// ===========================================================================

/// A simple signal for notifying subscribers of changes.
class Signal {
  final List<void Function()> _listeners = [];

  /// Subscribe to the signal. Returns an unsubscribe function.
  void Function() subscribe(void Function() listener) {
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  /// Emit the signal, notifying all subscribers.
  void emit() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }
}

// ===========================================================================
// Message Queue Manager Controller
// ===========================================================================

/// Unified command queue controller.
///
/// All commands -- user input, task notifications, orphaned permissions -- go
/// through this single queue. Priority determines dequeue order:
/// 'now' > 'next' > 'later'. Within the same priority, commands are FIFO.
class MessageQueueController extends SintController {
  final List<QueuedCommand> _commandQueue = [];

  /// Frozen snapshot -- recreated on every mutation for external store pattern.
  final RxList<QueuedCommand> snapshot = <QueuedCommand>[].obs;

  /// Signal for queue change notifications.
  final Signal _queueChanged = Signal();

  /// Callback for logging operations (injectable for testing).
  final void Function(QueueOperation operation, String? content)?
      _onLogOperation;

  MessageQueueController({
    void Function(QueueOperation operation, String? content)? onLogOperation,
  }) : _onLogOperation = onLogOperation;

  @override
  void onInit() {
    super.onInit();
  }

  // -------------------------------------------------------------------------
  // Notification
  // -------------------------------------------------------------------------

  void _notifySubscribers() {
    snapshot.value = List.unmodifiable(_commandQueue);
    _queueChanged.emit();
  }

  void _logOperation(QueueOperation operation, [String? content]) {
    _onLogOperation?.call(operation, content);
  }

  // -------------------------------------------------------------------------
  // Subscribe interface
  // -------------------------------------------------------------------------

  /// Subscribe to command queue changes.
  void Function() subscribeToCommandQueue(void Function() listener) {
    return _queueChanged.subscribe(listener);
  }

  /// Get current snapshot of the command queue.
  List<QueuedCommand> getCommandQueueSnapshot() {
    return List.unmodifiable(_commandQueue);
  }

  // -------------------------------------------------------------------------
  // Read operations
  // -------------------------------------------------------------------------

  /// Get a copy of the current queue.
  List<QueuedCommand> getCommandQueue() {
    return List.of(_commandQueue);
  }

  /// Get the current queue length without copying.
  int getCommandQueueLength() => _commandQueue.length;

  /// Check if there are commands in the queue.
  bool hasCommandsInQueue() => _commandQueue.isNotEmpty;

  /// Trigger a re-check by notifying subscribers.
  void recheckCommandQueue() {
    if (_commandQueue.isNotEmpty) {
      _notifySubscribers();
    }
  }

  // -------------------------------------------------------------------------
  // Write operations
  // -------------------------------------------------------------------------

  /// Add a command to the queue. Defaults priority to 'next'.
  void enqueue(QueuedCommand command) {
    _commandQueue.add(QueuedCommand(
      value: command.value,
      mode: command.mode,
      priority: command.priority,
      skipSlashCommands: command.skipSlashCommands,
      isMeta: command.isMeta,
      agentId: command.agentId,
      origin: command.origin,
      pastedContents: command.pastedContents,
    ));
    _notifySubscribers();
    final content = command.value is StringCommandValue
        ? (command.value as StringCommandValue).value
        : null;
    _logOperation(QueueOperation.enqueue, content);
  }

  /// Add a task notification. Defaults priority to 'later'.
  void enqueuePendingNotification(QueuedCommand command) {
    _commandQueue.add(QueuedCommand(
      value: command.value,
      mode: command.mode,
      priority: command.priority == QueuePriority.next
          ? QueuePriority.later
          : command.priority,
      skipSlashCommands: command.skipSlashCommands,
      isMeta: command.isMeta,
      agentId: command.agentId,
      origin: command.origin,
      pastedContents: command.pastedContents,
    ));
    _notifySubscribers();
    final content = command.value is StringCommandValue
        ? (command.value as StringCommandValue).value
        : null;
    _logOperation(QueueOperation.enqueue, content);
  }

  /// Remove and return the highest-priority command, or null if empty.
  ///
  /// An optional [filter] narrows the candidates: only commands for which
  /// the predicate returns true are considered.
  QueuedCommand? dequeue({
    bool Function(QueuedCommand)? filter,
  }) {
    if (_commandQueue.isEmpty) return null;

    int bestIdx = -1;
    int bestPriority = 999;

    for (int i = 0; i < _commandQueue.length; i++) {
      final cmd = _commandQueue[i];
      if (filter != null && !filter(cmd)) continue;
      final priority = cmd.priority.order;
      if (priority < bestPriority) {
        bestIdx = i;
        bestPriority = priority;
      }
    }

    if (bestIdx == -1) return null;

    final dequeued = _commandQueue.removeAt(bestIdx);
    _notifySubscribers();
    _logOperation(QueueOperation.dequeue);
    return dequeued;
  }

  /// Remove and return all commands from the queue.
  List<QueuedCommand> dequeueAll() {
    if (_commandQueue.isEmpty) return [];

    final commands = List.of(_commandQueue);
    _commandQueue.clear();
    _notifySubscribers();

    for (final _ in commands) {
      _logOperation(QueueOperation.dequeue);
    }

    return commands;
  }

  /// Return the highest-priority command without removing it.
  QueuedCommand? peek({
    bool Function(QueuedCommand)? filter,
  }) {
    if (_commandQueue.isEmpty) return null;

    int bestIdx = -1;
    int bestPriority = 999;

    for (int i = 0; i < _commandQueue.length; i++) {
      final cmd = _commandQueue[i];
      if (filter != null && !filter(cmd)) continue;
      final priority = cmd.priority.order;
      if (priority < bestPriority) {
        bestIdx = i;
        bestPriority = priority;
      }
    }

    if (bestIdx == -1) return null;
    return _commandQueue[bestIdx];
  }

  /// Remove and return all commands matching a predicate.
  List<QueuedCommand> dequeueAllMatching(
    bool Function(QueuedCommand) predicate,
  ) {
    final matched = <QueuedCommand>[];
    final remaining = <QueuedCommand>[];

    for (final cmd in _commandQueue) {
      if (predicate(cmd)) {
        matched.add(cmd);
      } else {
        remaining.add(cmd);
      }
    }

    if (matched.isEmpty) return [];

    _commandQueue
      ..clear()
      ..addAll(remaining);
    _notifySubscribers();

    for (final _ in matched) {
      _logOperation(QueueOperation.dequeue);
    }

    return matched;
  }

  /// Remove specific commands from the queue by reference identity.
  void remove(List<QueuedCommand> commandsToRemove) {
    if (commandsToRemove.isEmpty) return;

    final before = _commandQueue.length;
    for (int i = _commandQueue.length - 1; i >= 0; i--) {
      if (commandsToRemove.contains(_commandQueue[i])) {
        _commandQueue.removeAt(i);
      }
    }

    if (_commandQueue.length != before) {
      _notifySubscribers();
    }

    for (final _ in commandsToRemove) {
      _logOperation(QueueOperation.remove);
    }
  }

  /// Remove commands matching a predicate. Returns the removed commands.
  List<QueuedCommand> removeByFilter(
    bool Function(QueuedCommand) predicate,
  ) {
    final removed = <QueuedCommand>[];
    for (int i = _commandQueue.length - 1; i >= 0; i--) {
      if (predicate(_commandQueue[i])) {
        removed.insert(0, _commandQueue.removeAt(i));
      }
    }

    if (removed.isNotEmpty) {
      _notifySubscribers();
      for (final _ in removed) {
        _logOperation(QueueOperation.remove);
      }
    }

    return removed;
  }

  /// Clear all commands from the queue.
  void clearCommandQueue() {
    if (_commandQueue.isEmpty) return;
    _commandQueue.clear();
    _notifySubscribers();
  }

  /// Clear all commands and reset snapshot. Used for test cleanup.
  void resetCommandQueue() {
    _commandQueue.clear();
    snapshot.value = [];
  }

  // -------------------------------------------------------------------------
  // Editable mode helpers
  // -------------------------------------------------------------------------

  /// Whether this queued command can be pulled into the input buffer.
  bool isQueuedCommandEditable(QueuedCommand cmd) {
    return isPromptInputModeEditable(cmd.mode) && !cmd.isMeta;
  }

  /// Whether this queued command should render in the queue preview.
  bool isQueuedCommandVisible(QueuedCommand cmd) {
    if (cmd.origin?.kind == 'channel') return true;
    return isQueuedCommandEditable(cmd);
  }

  /// Extract text from a queued command value.
  String _extractTextFromValue(QueuedCommandValue value) {
    switch (value) {
      case StringCommandValue(:final value):
        return value;
      case BlocksCommandValue(:final blocks):
        return blocks
            .whereType<TextContentBlock>()
            .map((b) => b.text)
            .join('\n');
    }
  }

  /// Extract images from a BlocksCommandValue.
  List<PastedContent> _extractImagesFromValue(
    QueuedCommandValue value,
    int startId,
  ) {
    if (value is! BlocksCommandValue) return [];

    final images = <PastedContent>[];
    int imageIndex = 0;
    for (final block in value.blocks) {
      if (block is ImageContentBlock && block.sourceType == 'base64') {
        images.add(PastedContent(
          id: startId + imageIndex,
          type: 'image',
          content: block.data,
          mediaType: block.mediaType,
          filename: 'image${imageIndex + 1}',
        ));
        imageIndex++;
      }
    }
    return images;
  }

  /// Pop all editable commands and combine them with current input.
  ///
  /// Notification modes (task-notification) are left in the queue.
  /// Returns null if no editable commands in queue.
  PopAllEditableResult? popAllEditable({
    required String currentInput,
    required int currentCursorOffset,
  }) {
    if (_commandQueue.isEmpty) return null;

    final editable = <QueuedCommand>[];
    final nonEditable = <QueuedCommand>[];

    for (final cmd in _commandQueue) {
      if (isQueuedCommandEditable(cmd)) {
        editable.add(cmd);
      } else {
        nonEditable.add(cmd);
      }
    }

    if (editable.isEmpty) return null;

    // Extract text from queued commands
    final queuedTexts =
        editable.map((cmd) => _extractTextFromValue(cmd.value)).toList();
    final allParts = [...queuedTexts, currentInput]
        .where((s) => s.isNotEmpty)
        .toList();
    final newInput = allParts.join('\n');

    // Calculate cursor offset
    final cursorOffset =
        queuedTexts.join('\n').length + 1 + currentCursorOffset;

    // Extract images from queued commands
    final images = <PastedContent>[];
    int nextImageId = DateTime.now().millisecondsSinceEpoch;
    for (final cmd in editable) {
      // Preserve original PastedContent from pastedContents map.
      if (cmd.pastedContents != null) {
        for (final content in cmd.pastedContents!.values) {
          if (content.type == 'image') {
            images.add(content);
          }
        }
      }
      final cmdImages = _extractImagesFromValue(cmd.value, nextImageId);
      images.addAll(cmdImages);
      nextImageId += cmdImages.length;
    }

    for (final command in editable) {
      final content = command.value is StringCommandValue
          ? (command.value as StringCommandValue).value
          : null;
      _logOperation(QueueOperation.popAll, content);
    }

    // Replace queue with only the non-editable commands
    _commandQueue
      ..clear()
      ..addAll(nonEditable);
    _notifySubscribers();

    return PopAllEditableResult(
      text: newInput,
      cursorOffset: cursorOffset,
      images: images,
    );
  }

  /// Get commands at or above a given priority level without removing them.
  List<QueuedCommand> getCommandsByMaxPriority(QueuePriority maxPriority) {
    return _commandQueue
        .where((cmd) => cmd.priority.order <= maxPriority.order)
        .toList();
  }

  /// Returns true if the command is a slash command that should be routed
  /// through processSlashCommand rather than sent to the model as text.
  bool isSlashCommand(QueuedCommand cmd) {
    if (cmd.value is! StringCommandValue) return false;
    final text = (cmd.value as StringCommandValue).value;
    return text.trim().startsWith('/') && !cmd.skipSlashCommands;
  }
}

// ===========================================================================
// Group Tool Uses (ported from groupToolUses.ts)
// ===========================================================================

/// Information about a tool use extracted from a normalized message.
class ToolUseInfo {
  final String messageId;
  final String toolUseId;
  final String toolName;

  const ToolUseInfo({
    required this.messageId,
    required this.toolUseId,
    required this.toolName,
  });
}

/// A normalized message for tool use grouping.
class NormalizedMessage {
  final String type;
  final String uuid;
  final DateTime timestamp;
  final Map<String, dynamic> message;
  final dynamic toolUseResult;

  const NormalizedMessage({
    required this.type,
    required this.uuid,
    required this.timestamp,
    required this.message,
    this.toolUseResult,
  });
}

/// A grouped tool use message for rendering.
class GroupedToolUseMessage {
  final String type;
  final String toolName;
  final List<NormalizedMessage> messages;
  final List<NormalizedMessage> results;
  final NormalizedMessage displayMessage;
  final String uuid;
  final DateTime timestamp;
  final String messageId;

  const GroupedToolUseMessage({
    this.type = 'grouped_tool_use',
    required this.toolName,
    required this.messages,
    required this.results,
    required this.displayMessage,
    required this.uuid,
    required this.timestamp,
    required this.messageId,
  });
}

/// Result of the grouping operation.
class GroupingResult {
  final List<dynamic> messages;

  const GroupingResult({required this.messages});
}

/// Extract tool use info from a normalized message.
ToolUseInfo? getToolUseInfo(NormalizedMessage msg) {
  if (msg.type != 'assistant') return null;

  final content = msg.message['content'];
  if (content is! List || content.isEmpty) return null;

  final firstBlock = content[0];
  if (firstBlock is! Map<String, dynamic>) return null;
  if (firstBlock['type'] != 'tool_use') return null;

  return ToolUseInfo(
    messageId: msg.message['id'] as String? ?? '',
    toolUseId: firstBlock['id'] as String? ?? '',
    toolName: firstBlock['name'] as String? ?? '',
  );
}

/// Groups tool uses by message.id (same API response) if the tool supports
/// grouped rendering.
///
/// Only groups 2+ tools of the same type from the same message. Also collects
/// corresponding tool_results and attaches them to the grouped message.
/// When [verbose] is true, skips grouping so messages render at original
/// positions.
GroupingResult applyGrouping({
  required List<NormalizedMessage> messages,
  required Set<String> toolsWithGrouping,
  bool verbose = false,
}) {
  if (verbose) {
    return GroupingResult(messages: messages);
  }

  // First pass: group tool uses by message.id + tool name
  final groups = <String, List<NormalizedMessage>>{};

  for (final msg in messages) {
    final info = getToolUseInfo(msg);
    if (info != null && toolsWithGrouping.contains(info.toolName)) {
      final key = '${info.messageId}:${info.toolName}';
      groups.putIfAbsent(key, () => []).add(msg);
    }
  }

  // Identify valid groups (2+ items) and collect their tool use IDs
  final validGroups = <String, List<NormalizedMessage>>{};
  final groupedToolUseIds = <String>{};

  for (final entry in groups.entries) {
    if (entry.value.length >= 2) {
      validGroups[entry.key] = entry.value;
      for (final msg in entry.value) {
        final info = getToolUseInfo(msg);
        if (info != null) {
          groupedToolUseIds.add(info.toolUseId);
        }
      }
    }
  }

  // Collect result messages for grouped tool_uses
  final resultsByToolUseId = <String, NormalizedMessage>{};

  for (final msg in messages) {
    if (msg.type != 'user') continue;
    final content = msg.message['content'];
    if (content is! List) continue;
    for (final block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'tool_result' &&
          groupedToolUseIds.contains(block['tool_use_id'])) {
        resultsByToolUseId[block['tool_use_id'] as String] = msg;
      }
    }
  }

  // Second pass: build output, emitting each group only once
  final result = <dynamic>[];
  final emittedGroups = <String>{};

  for (final msg in messages) {
    final info = getToolUseInfo(msg);

    if (info != null) {
      final key = '${info.messageId}:${info.toolName}';
      final group = validGroups[key];

      if (group != null) {
        if (!emittedGroups.contains(key)) {
          emittedGroups.add(key);
          final firstMsg = group.first;

          // Collect results for this group
          final results = <NormalizedMessage>[];
          for (final assistantMsg in group) {
            final content = assistantMsg.message['content'];
            if (content is List && content.isNotEmpty) {
              final toolUseId =
                  (content[0] as Map<String, dynamic>)['id'] as String?;
              if (toolUseId != null) {
                final resultMsg = resultsByToolUseId[toolUseId];
                if (resultMsg != null) results.add(resultMsg);
              }
            }
          }

          result.add(GroupedToolUseMessage(
            toolName: info.toolName,
            messages: group,
            results: results,
            displayMessage: firstMsg,
            uuid: 'grouped-${firstMsg.uuid}',
            timestamp: firstMsg.timestamp,
            messageId: info.messageId,
          ));
        }
        continue;
      }
    }

    // Skip user messages whose tool_results are all grouped
    if (msg.type == 'user') {
      final content = msg.message['content'];
      if (content is List) {
        final toolResults = content
            .whereType<Map<String, dynamic>>()
            .where((c) => c['type'] == 'tool_result')
            .toList();
        if (toolResults.isNotEmpty) {
          final allGrouped = toolResults.every(
            (tr) => groupedToolUseIds.contains(tr['tool_use_id']),
          );
          if (allGrouped) continue;
        }
      }
    }

    result.add(msg);
  }

  return GroupingResult(messages: result);
}

// ===========================================================================
// Memoize with TTL (ported from memoize.ts)
// ===========================================================================

/// Cache entry for TTL-based memoization.
class _CacheEntry<T> {
  T value;
  int timestamp;
  bool refreshing;

  _CacheEntry({
    required this.value,
    required this.timestamp,
    this.refreshing = false,
  });
}

/// Creates a memoized function that returns cached values while refreshing
/// in parallel (write-through cache pattern).
///
/// - If cache is fresh, return immediately.
/// - If cache is stale, return the stale value but refresh in the background.
/// - If no cache exists, block and compute the value.
class MemoizeWithTTL<R> {
  final R Function(List<dynamic> args) _fn;
  final Duration cacheLifetime;
  final String Function(List<dynamic> args)? _keyFn;
  final Map<String, _CacheEntry<R>> _cache = {};

  MemoizeWithTTL(
    this._fn, {
    this.cacheLifetime = const Duration(minutes: 5),
    String Function(List<dynamic> args)? keyFn,
  }) : _keyFn = keyFn;

  String _makeKey(List<dynamic> args) {
    if (_keyFn != null) return _keyFn!(args);
    return jsonEncode(args);
  }

  R call(List<dynamic> args) {
    final key = _makeKey(args);
    final cached = _cache[key];
    final now = DateTime.now().millisecondsSinceEpoch;

    // Populate cache
    if (cached == null) {
      final value = _fn(args);
      _cache[key] = _CacheEntry(value: value, timestamp: now);
      return value;
    }

    // If stale and not already refreshing
    if (now - cached.timestamp > cacheLifetime.inMilliseconds &&
        !cached.refreshing) {
      cached.refreshing = true;

      // Schedule async refresh (non-blocking)
      final staleEntry = cached;
      Future.microtask(() {
        try {
          final newValue = _fn(args);
          if (_cache[key] == staleEntry) {
            _cache[key] = _CacheEntry(
              value: newValue,
              timestamp: DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {
          if (_cache[key] == staleEntry) {
            _cache.remove(key);
          }
        }
      });

      return cached.value;
    }

    return _cache[key]!.value;
  }

  /// Clear the cache.
  void clear() => _cache.clear();
}

/// Creates a memoized async function with TTL (write-through cache pattern).
class MemoizeWithTTLAsync<R> {
  final Future<R> Function(List<dynamic> args) _fn;
  final Duration cacheLifetime;
  final String Function(List<dynamic> args)? _keyFn;
  final Map<String, _CacheEntry<R>> _cache = {};
  final Map<String, Future<R>> _inFlight = {};

  MemoizeWithTTLAsync(
    this._fn, {
    this.cacheLifetime = const Duration(minutes: 5),
    String Function(List<dynamic> args)? keyFn,
  }) : _keyFn = keyFn;

  String _makeKey(List<dynamic> args) {
    if (_keyFn != null) return _keyFn!(args);
    return jsonEncode(args);
  }

  Future<R> call(List<dynamic> args) async {
    final key = _makeKey(args);
    final cached = _cache[key];
    final now = DateTime.now().millisecondsSinceEpoch;

    // Populate cache -- cold miss with in-flight dedup
    if (cached == null) {
      final pending = _inFlight[key];
      if (pending != null) return pending;

      final promise = _fn(args);
      _inFlight[key] = promise;
      try {
        final result = await promise;
        // Identity-guard: cache.clear() during the await should discard
        if (_inFlight[key] == promise) {
          _cache[key] = _CacheEntry(value: result, timestamp: now);
        }
        return result;
      } finally {
        if (_inFlight[key] == promise) {
          _inFlight.remove(key);
        }
      }
    }

    // If stale and not already refreshing
    if (now - cached.timestamp > cacheLifetime.inMilliseconds &&
        !cached.refreshing) {
      cached.refreshing = true;

      final staleEntry = cached;
      _fn(args).then((newValue) {
        if (_cache[key] == staleEntry) {
          _cache[key] = _CacheEntry(
            value: newValue,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          );
        }
      }).catchError((_) {
        if (_cache[key] == staleEntry) {
          _cache.remove(key);
        }
      });

      return cached.value;
    }

    return _cache[key]!.value;
  }

  /// Clear the cache and in-flight requests.
  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}

/// Creates a memoized function with LRU (Least Recently Used) eviction.
///
/// Prevents unbounded memory growth by evicting the least recently used
/// entries when the cache reaches its maximum size.
class MemoizeWithLRU<R> {
  final R Function(List<dynamic> args) _fn;
  final String Function(List<dynamic> args) _keyFn;
  final int maxCacheSize;

  final Map<String, R> _cache = {};
  final List<String> _accessOrder = [];

  MemoizeWithLRU(
    this._fn, {
    required String Function(List<dynamic> args) keyFn,
    this.maxCacheSize = 100,
  }) : _keyFn = keyFn;

  R call(List<dynamic> args) {
    final key = _keyFn(args);

    if (_cache.containsKey(key)) {
      // Move to most recent
      _accessOrder.remove(key);
      _accessOrder.add(key);
      return _cache[key] as R;
    }

    final result = _fn(args);
    _cache[key] = result;
    _accessOrder.add(key);

    // Evict if over capacity
    while (_accessOrder.length > maxCacheSize) {
      final evicted = _accessOrder.removeAt(0);
      _cache.remove(evicted);
    }

    return result;
  }

  /// Clear the cache.
  void clear() {
    _cache.clear();
    _accessOrder.clear();
  }

  /// Number of cached entries.
  int get size => _cache.length;

  /// Delete a specific key.
  bool delete(String key) {
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      _accessOrder.remove(key);
      return true;
    }
    return false;
  }

  /// Get a value without updating recency.
  R? get(String key) => _cache[key];

  /// Check if the cache contains a key.
  bool has(String key) => _cache.containsKey(key);
}

// ===========================================================================
// Sequential (ported from sequential.ts)
// ===========================================================================

/// Creates a sequential execution wrapper for async functions to prevent
/// race conditions.
///
/// Ensures that concurrent calls to the wrapped function are executed one
/// at a time in the order they were received, while preserving the correct
/// return values.
///
/// This is useful for operations that must be performed sequentially, such
/// as file writes or database updates that could cause conflicts if executed
/// concurrently.
class Sequential<R> {
  final Future<R> Function(List<dynamic> args) _fn;
  final List<_QueueItem<R>> _queue = [];
  bool _processing = false;

  Sequential(this._fn);

  Future<R> call(List<dynamic> args) {
    final completer = Completer<R>();
    _queue.add(_QueueItem(args: args, completer: completer));
    _processQueue();
    return completer.future;
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    if (_queue.isEmpty) return;

    _processing = true;

    while (_queue.isNotEmpty) {
      final item = _queue.removeAt(0);
      try {
        final result = await _fn(item.args);
        item.completer.complete(result);
      } catch (error, stackTrace) {
        item.completer.completeError(error, stackTrace);
      }
    }

    _processing = false;

    // Check if new items were added while we were processing
    if (_queue.isNotEmpty) {
      _processQueue();
    }
  }
}

class _QueueItem<R> {
  final List<dynamic> args;
  final Completer<R> completer;

  _QueueItem({
    required this.args,
    required this.completer,
  });
}
