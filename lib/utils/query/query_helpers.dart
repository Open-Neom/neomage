// Query helpers — port of openneomclaw queryHelpers.ts + queryContext.ts +
// queryProfiler.ts + readEditContext.ts.
// Query building, context fetching, profiling, and file context extraction.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// Part 1 — Query Helpers (from queryHelpers.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Representation of a permission prompt tool.
typedef PermissionPromptTool = Map<String, dynamic>;

/// Small cache size for ask operations.
const int _askReadFileStateCacheSize = 10;

/// Maximum entries tracked for tool progress throttling.
const int _maxToolProgressTrackingEntries = 100;

/// Throttle interval for tool progress messages (ms).
const int _toolProgressThrottleMs = 30000;

/// Tracks last sent time for tool progress messages per tool use ID.
final Map<String, int> _toolProgressLastSentTime = {};

/// Checks if the result should be considered successful based on the last
/// message.
bool isResultSuccessful(
  Map<String, dynamic>? message, {
  String? stopReason,
}) {
  if (message == null) return false;

  final type = message['type'] as String?;

  if (type == 'assistant') {
    final content = message['message']?['content'];
    if (content is List && content.isNotEmpty) {
      final lastContent = content.last;
      if (lastContent is Map<String, dynamic>) {
        final blockType = lastContent['type'] as String?;
        return blockType == 'text' ||
            blockType == 'thinking' ||
            blockType == 'redacted_thinking';
      }
    }
  }

  if (type == 'user') {
    final content = message['message']?['content'];
    if (content is List &&
        content.isNotEmpty &&
        content.every((block) =>
            block is Map<String, dynamic> && block['type'] == 'tool_result')) {
      return true;
    }
  }

  // API completed but yielded no assistant content.
  return stopReason == 'end_turn';
}

/// Normalize a single message for SDK output.
Iterable<Map<String, dynamic>> normalizeMessage(
  Map<String, dynamic> message, {
  required String sessionId,
}) sync* {
  final type = message['type'] as String?;

  switch (type) {
    case 'assistant':
      yield {
        'type': 'assistant',
        'message': message['message'],
        'parent_tool_use_id': null,
        'session_id': sessionId,
        'uuid': message['uuid'],
        if (message.containsKey('error')) 'error': message['error'],
      };
    case 'progress':
      final data = message['data'] as Map<String, dynamic>?;
      if (data == null) break;
      final progressType = data['type'] as String?;

      if (progressType == 'agent_progress' ||
          progressType == 'skill_progress') {
        final innerMsg = data['message'] as Map<String, dynamic>?;
        if (innerMsg == null) break;
        final innerType = innerMsg['type'] as String?;

        if (innerType == 'assistant') {
          yield {
            'type': 'assistant',
            'message': innerMsg['message'],
            'parent_tool_use_id': message['parentToolUseID'],
            'session_id': sessionId,
            'uuid': innerMsg['uuid'],
            if (innerMsg.containsKey('error')) 'error': innerMsg['error'],
          };
        } else if (innerType == 'user') {
          yield {
            'type': 'user',
            'message': innerMsg['message'],
            'parent_tool_use_id': message['parentToolUseID'],
            'session_id': sessionId,
            'uuid': innerMsg['uuid'],
            'timestamp': innerMsg['timestamp'],
            'isSynthetic':
                innerMsg['isMeta'] == true || innerMsg['isVisibleInTranscriptOnly'] == true,
            'tool_use_result': innerMsg['toolUseResult'],
          };
        }
      } else if (progressType == 'bash_progress' ||
          progressType == 'powershell_progress') {
        // Throttle: only emit one every 30 seconds.
        final trackingKey = message['parentToolUseID'] as String? ?? '';
        final now = DateTime.now().millisecondsSinceEpoch;
        final lastSent = _toolProgressLastSentTime[trackingKey] ?? 0;

        if (now - lastSent >= _toolProgressThrottleMs) {
          // Evict oldest entry if at capacity.
          if (_toolProgressLastSentTime.length >=
              _maxToolProgressTrackingEntries) {
            _toolProgressLastSentTime.remove(
              _toolProgressLastSentTime.keys.first,
            );
          }
          _toolProgressLastSentTime[trackingKey] = now;

          yield {
            'type': 'tool_progress',
            'tool_use_id': message['toolUseID'],
            'tool_name': progressType == 'bash_progress' ? 'Bash' : 'PowerShell',
            'parent_tool_use_id': message['parentToolUseID'],
            'elapsed_time_seconds': data['elapsedTimeSeconds'],
            'task_id': data['taskId'],
            'session_id': sessionId,
            'uuid': message['uuid'],
          };
        }
      }
    case 'user':
      yield {
        'type': 'user',
        'message': message['message'],
        'parent_tool_use_id': null,
        'session_id': sessionId,
        'uuid': message['uuid'],
        'timestamp': message['timestamp'],
        'isSynthetic':
            message['isMeta'] == true || message['isVisibleInTranscriptOnly'] == true,
        'tool_use_result': message['toolUseResult'],
      };
    default:
      // yield nothing.
      break;
  }
}

/// Handle an orphaned permission by executing the tool.
Stream<Map<String, dynamic>> handleOrphanedPermission({
  required Map<String, dynamic> permissionResult,
  required Map<String, dynamic> assistantMessage,
  required List<Map<String, dynamic>> tools,
  required List<Map<String, dynamic>> mutableMessages,
  required String sessionId,
  required bool persistSession,
  Future<void> Function(List<Map<String, dynamic>>)? recordTranscript,
  Stream<Map<String, dynamic>> Function(Map<String, dynamic>)? runToolUse,
}) async* {
  final toolUseId = permissionResult['toolUseID'] as String?;
  if (toolUseId == null) return;

  final content = assistantMessage['message']?['content'];
  Map<String, dynamic>? toolUseBlock;
  if (content is List) {
    for (final block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'tool_use' &&
          block['id'] == toolUseId) {
        toolUseBlock = block;
        break;
      }
    }
  }

  if (toolUseBlock == null) return;

  final toolName = toolUseBlock['name'] as String?;
  if (toolName == null) return;

  // Check if tool exists.
  final toolDefinition = tools.firstWhere(
    (t) => t['name'] == toolName,
    orElse: () => <String, dynamic>{},
  );
  if (toolDefinition.isEmpty) return;

  // Get final input.
  var finalInput = toolUseBlock['input'];
  if (permissionResult['behavior'] == 'allow' &&
      permissionResult['updatedInput'] != null) {
    finalInput = permissionResult['updatedInput'];
  }

  final finalToolUseBlock = {
    ...toolUseBlock,
    'input': finalInput,
  };

  // Add assistant message if not already present.
  final alreadyPresent = mutableMessages.any((m) {
    if (m['type'] != 'assistant') return false;
    final c = m['message']?['content'];
    if (c is! List) return false;
    return c.any((b) =>
        b is Map<String, dynamic> &&
        b['type'] == 'tool_use' &&
        b['id'] == toolUseId);
  });

  if (!alreadyPresent) {
    mutableMessages.add(assistantMessage);
    if (persistSession && recordTranscript != null) {
      await recordTranscript(mutableMessages);
    }
  }

  yield {
    ...assistantMessage,
    'session_id': sessionId,
    'parent_tool_use_id': null,
  };

  // Execute the tool.
  if (runToolUse != null) {
    await for (final update in runToolUse(finalToolUseBlock)) {
      if (update.containsKey('message')) {
        mutableMessages.add(update['message'] as Map<String, dynamic>);
        if (persistSession && recordTranscript != null) {
          await recordTranscript(mutableMessages);
        }

        yield {
          ...(update['message'] as Map<String, dynamic>),
          'session_id': sessionId,
          'parent_tool_use_id': null,
        };
      }
    }
  }
}

/// File state cache entry.
class FileStateCacheEntry {
  FileStateCacheEntry({
    required this.content,
    required this.timestamp,
    this.offset,
    this.limit,
  });

  final String content;
  final int timestamp;
  final int? offset;
  final int? limit;
}

/// Simple LRU file state cache.
class FileStateCache {
  FileStateCache({int maxSize = 100}) : _maxSize = maxSize;

  final int _maxSize;
  final Map<String, FileStateCacheEntry> _cache = {};

  void set(String key, FileStateCacheEntry value) {
    if (_cache.length >= _maxSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  FileStateCacheEntry? get(String key) => _cache[key];

  int get length => _cache.length;
}

/// Create a file state cache with size limit.
FileStateCache createFileStateCacheWithSizeLimit(int maxSize) {
  return FileStateCache(maxSize: maxSize);
}

/// Strip line number prefix from a line (e.g. "  42\tcode" -> "code").
String _stripLineNumberPrefix(String line) {
  final match = RegExp(r'^\s*\d+\t').firstMatch(line);
  if (match != null) return line.substring(match.end);
  return line;
}

/// Expand a path relative to cwd into an absolute path.
String _expandPath(String filePath, String cwd) {
  if (p.isAbsolute(filePath)) return filePath;
  return p.join(cwd, filePath);
}

/// File unchanged stub marker.
const String _fileUnchangedStub = '(file unchanged since last read)';

/// Extract read files from messages to populate the file state cache.
FileStateCache extractReadFilesFromMessages(
  List<Map<String, dynamic>> messages,
  String cwd, {
  int maxSize = _askReadFileStateCacheSize,
}) {
  final cache = createFileStateCacheWithSizeLimit(maxSize);

  // First pass: find tool_use blocks.
  final fileReadToolUseIds = <String, String>{}; // toolUseId -> filePath
  final fileWriteToolUseIds =
      <String, ({String filePath, String content})>{}; // toolUseId -> data
  final fileEditToolUseIds = <String, String>{}; // toolUseId -> filePath

  for (final message in messages) {
    if (message['type'] != 'assistant') continue;
    final content = message['message']?['content'];
    if (content is! List) continue;

    for (final block in content) {
      if (block is! Map<String, dynamic> || block['type'] != 'tool_use') {
        continue;
      }

      final name = block['name'] as String?;
      final input = block['input'] as Map<String, dynamic>?;
      final id = block['id'] as String?;
      if (id == null || input == null) continue;

      if (name == 'FileRead') {
        final path = input['file_path'] as String?;
        if (path != null &&
            input['offset'] == null &&
            input['limit'] == null) {
          fileReadToolUseIds[id] = _expandPath(path, cwd);
        }
      } else if (name == 'FileWrite') {
        final path = input['file_path'] as String?;
        final writeContent = input['content'] as String?;
        if (path != null && writeContent != null) {
          fileWriteToolUseIds[id] = (
            filePath: _expandPath(path, cwd),
            content: writeContent,
          );
        }
      } else if (name == 'FileEdit') {
        final path = input['file_path'] as String?;
        if (path != null) {
          fileEditToolUseIds[id] = _expandPath(path, cwd);
        }
      }
    }
  }

  // Second pass: find corresponding tool results.
  for (final message in messages) {
    if (message['type'] != 'user') continue;
    final content = message['message']?['content'];
    if (content is! List) continue;

    for (final block in content) {
      if (block is! Map<String, dynamic> || block['type'] != 'tool_result') {
        continue;
      }

      final toolUseId = block['tool_use_id'] as String?;
      if (toolUseId == null) continue;

      // Handle Read tool results.
      final readFilePath = fileReadToolUseIds[toolUseId];
      if (readFilePath != null) {
        final resultContent = block['content'] as String?;
        if (resultContent != null &&
            !resultContent.startsWith(_fileUnchangedStub)) {
          // Remove system-reminder blocks.
          final processed = resultContent.replaceAll(
            RegExp(r'<system-reminder>[\s\S]*?<\/system-reminder>'),
            '',
          );

          final fileContent = processed
              .split('\n')
              .map(_stripLineNumberPrefix)
              .join('\n')
              .trim();

          final timestamp = message['timestamp'] as String?;
          if (timestamp != null) {
            final ts = DateTime.parse(timestamp).millisecondsSinceEpoch;
            cache.set(
              readFilePath,
              FileStateCacheEntry(content: fileContent, timestamp: ts),
            );
          }
        }
      }

      // Handle Write tool results.
      final writeData = fileWriteToolUseIds[toolUseId];
      if (writeData != null) {
        final timestamp = message['timestamp'] as String?;
        if (timestamp != null) {
          final ts = DateTime.parse(timestamp).millisecondsSinceEpoch;
          cache.set(
            writeData.filePath,
            FileStateCacheEntry(
              content: writeData.content,
              timestamp: ts,
            ),
          );
        }
      }

      // Handle Edit tool results — read from disk.
      final editFilePath = fileEditToolUseIds[toolUseId];
      if (editFilePath != null && block['is_error'] != true) {
        try {
          final file = File(editFilePath);
          final diskContent = file.readAsStringSync();
          final mtime = file.statSync().modified.millisecondsSinceEpoch;
          cache.set(
            editFilePath,
            FileStateCacheEntry(content: diskContent, timestamp: mtime),
          );
        } catch (_) {
          // File deleted or inaccessible.
        }
      }
    }
  }

  return cache;
}

/// Extract the top-level CLI tools used in BashTool calls from messages.
Set<String> extractBashToolsFromMessages(
  List<Map<String, dynamic>> messages,
) {
  final tools = <String>{};
  for (final message in messages) {
    if (message['type'] != 'assistant') continue;
    final content = message['message']?['content'];
    if (content is! List) continue;

    for (final block in content) {
      if (block is! Map<String, dynamic> ||
          block['type'] != 'tool_use' ||
          block['name'] != 'Bash') {
        continue;
      }
      final input = block['input'] as Map<String, dynamic>?;
      if (input == null) continue;
      final command = input['command'] as String?;
      final cliName = _extractCliName(command);
      if (cliName != null) tools.add(cliName);
    }
  }
  return tools;
}

/// Commands to strip from the front of a command string.
const Set<String> _strippedCommands = {'sudo'};

/// Extract the actual CLI name from a bash command string.
String? _extractCliName(String? command) {
  if (command == null) return null;
  final tokens = command.trim().split(RegExp(r'\s+'));
  for (final token in tokens) {
    if (RegExp(r'^[A-Za-z_]\w*=').hasMatch(token)) continue;
    if (_strippedCommands.contains(token)) continue;
    return token;
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 2 — Query Context (from queryContext.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Callback types for system prompt building.
typedef GetSystemPromptFn = Future<List<String>> Function();
typedef GetUserContextFn = Future<Map<String, String>> Function();
typedef GetSystemContextFn = Future<Map<String, String>> Function();

/// Fetch the three context pieces for the API cache-key prefix.
Future<({List<String> defaultSystemPrompt, Map<String, String> userContext, Map<String, String> systemContext})>
    fetchSystemPromptParts({
  required GetSystemPromptFn getSystemPrompt,
  required GetUserContextFn getUserContext,
  required GetSystemContextFn getSystemContext,
  String? customSystemPrompt,
}) async {
  late List<String> defaultSystemPrompt;
  late Map<String, String> userContext;
  late Map<String, String> systemContext;

  if (customSystemPrompt != null) {
    defaultSystemPrompt = [];
    systemContext = {};
    userContext = await getUserContext();
  } else {
    final results = await Future.wait([
      getSystemPrompt(),
      getUserContext(),
      getSystemContext(),
    ]);
    defaultSystemPrompt = results[0] as List<String>;
    userContext = results[1] as Map<String, String>;
    systemContext = results[2] as Map<String, String>;
  }

  return (
    defaultSystemPrompt: defaultSystemPrompt,
    userContext: userContext,
    systemContext: systemContext,
  );
}

/// Cache-safe parameters for query execution.
class CacheSafeParams {
  CacheSafeParams({
    required this.systemPrompt,
    required this.userContext,
    required this.systemContext,
    required this.toolUseContext,
    required this.forkContextMessages,
  });

  final List<String> systemPrompt;
  final Map<String, String> userContext;
  final Map<String, String> systemContext;
  final Map<String, dynamic> toolUseContext;
  final List<Map<String, dynamic>> forkContextMessages;
}

/// Build CacheSafeParams for a side question fallback.
Future<CacheSafeParams> buildSideQuestionFallbackParams({
  required List<Map<String, dynamic>> tools,
  required List<Map<String, dynamic>> commands,
  required List<Map<String, dynamic>> mcpClients,
  required List<Map<String, dynamic>> messages,
  required FileStateCache readFileState,
  required Map<String, dynamic> Function() getAppState,
  required void Function(void Function(Map<String, dynamic>)) setAppState,
  String? customSystemPrompt,
  String? appendSystemPrompt,
  Map<String, dynamic>? thinkingConfig,
  required List<Map<String, dynamic>> agents,
  required GetSystemPromptFn getSystemPrompt,
  required GetUserContextFn getUserContext,
  required GetSystemContextFn getSystemContext,
}) async {
  final parts = await fetchSystemPromptParts(
    getSystemPrompt: getSystemPrompt,
    getUserContext: getUserContext,
    getSystemContext: getSystemContext,
    customSystemPrompt: customSystemPrompt,
  );

  final systemPrompt = <String>[
    if (customSystemPrompt != null)
      customSystemPrompt
    else
      ...parts.defaultSystemPrompt,
    if (appendSystemPrompt != null) appendSystemPrompt,
  ];

  // Strip in-progress assistant message.
  final last = messages.isNotEmpty ? messages.last : null;
  final forkContextMessages =
      (last != null &&
              last['type'] == 'assistant' &&
              last['message']?['stop_reason'] == null)
          ? messages.sublist(0, messages.length - 1)
          : messages;

  final toolUseContext = <String, dynamic>{
    'options': {
      'commands': commands,
      'debug': false,
      'tools': tools,
      'verbose': false,
      'thinkingConfig': thinkingConfig,
      'mcpClients': mcpClients,
      'isNonInteractiveSession': true,
      'agentDefinitions': {'activeAgents': agents, 'allAgents': []},
      'customSystemPrompt': customSystemPrompt,
      'appendSystemPrompt': appendSystemPrompt,
    },
    'readFileState': readFileState,
    'messages': forkContextMessages,
  };

  return CacheSafeParams(
    systemPrompt: systemPrompt,
    userContext: parts.userContext,
    systemContext: parts.systemContext,
    toolUseContext: toolUseContext,
    forkContextMessages: forkContextMessages,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 3 — Query Profiler (from queryProfiler.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Whether query profiling is enabled.
final bool _queryProfilerEnabled = _isEnvTruthy(
  Platform.environment['NEOMCLAW_PROFILE_QUERY'],
);

/// Track memory snapshots separately.
final Map<String, Map<String, int>> _memorySnapshots = {};

/// Query count for reporting.
int _queryCount = 0;

/// First token received time for summary.
double? _firstTokenTime;

/// Checkpoint timestamps.
final Map<String, double> _checkpointTimes = {};
double? _baselineTime;

/// Start profiling a new query session.
void startQueryProfile() {
  if (!_queryProfilerEnabled) return;
  _checkpointTimes.clear();
  _memorySnapshots.clear();
  _firstTokenTime = null;
  _baselineTime = null;
  _queryCount++;
  queryCheckpoint('query_user_input_received');
}

/// Record a checkpoint with the given name.
void queryCheckpoint(String name) {
  if (!_queryProfilerEnabled) return;
  final now = DateTime.now().microsecondsSinceEpoch / 1000.0;
  _checkpointTimes[name] = now;
  _baselineTime ??= now;

  if (name == 'query_first_chunk_received' && _firstTokenTime == null) {
    _firstTokenTime = now;
  }
}

/// End the current query profiling session.
void endQueryProfile() {
  if (!_queryProfilerEnabled) return;
  queryCheckpoint('query_profile_end');
}

/// Format milliseconds for display.
String _formatMs(double ms) {
  return ms.toStringAsFixed(1);
}

/// Identify slow operations.
String _getSlowWarning(double deltaMs, String name) {
  if (name == 'query_user_input_received') return '';
  if (deltaMs > 1000) return ' VERY SLOW';
  if (deltaMs > 100) return ' SLOW';
  if (name.contains('git_status') && deltaMs > 50) return ' git status';
  if (name.contains('tool_schema') && deltaMs > 50) return ' tool schemas';
  if (name.contains('client_creation') && deltaMs > 50) return ' client creation';
  return '';
}

/// Phase definitions for the query pipeline.
class _QueryPhase {
  _QueryPhase({required this.name, required this.start, required this.end});
  final String name;
  final String start;
  final String end;
}

final List<_QueryPhase> _queryPhases = [
  _QueryPhase(name: 'Context loading', start: 'query_context_loading_start', end: 'query_context_loading_end'),
  _QueryPhase(name: 'Microcompact', start: 'query_microcompact_start', end: 'query_microcompact_end'),
  _QueryPhase(name: 'Autocompact', start: 'query_autocompact_start', end: 'query_autocompact_end'),
  _QueryPhase(name: 'Query setup', start: 'query_setup_start', end: 'query_setup_end'),
  _QueryPhase(name: 'Tool schemas', start: 'query_tool_schema_build_start', end: 'query_tool_schema_build_end'),
  _QueryPhase(name: 'Message normalization', start: 'query_message_normalization_start', end: 'query_message_normalization_end'),
  _QueryPhase(name: 'Client creation', start: 'query_client_creation_start', end: 'query_client_creation_end'),
  _QueryPhase(name: 'Network TTFB', start: 'query_api_request_sent', end: 'query_first_chunk_received'),
  _QueryPhase(name: 'Tool execution', start: 'query_tool_execution_start', end: 'query_tool_execution_end'),
];

/// Get the phase summary for the profiling report.
String _getPhaseSummary() {
  if (_baselineTime == null) return '';
  final lines = <String>[];
  lines.add('');
  lines.add('PHASE BREAKDOWN:');

  for (final phase in _queryPhases) {
    final startTime = _checkpointTimes[phase.start];
    final endTime = _checkpointTimes[phase.end];
    if (startTime != null && endTime != null) {
      final duration = endTime - startTime;
      final barLen = math.min((duration / 10).ceil(), 50);
      final bar = '\u2588' * barLen;
      lines.add('  ${phase.name.padRight(22)} ${_formatMs(duration).padLeft(10)}ms $bar');
    }
  }

  final apiRequestSent = _checkpointTimes['query_api_request_sent'];
  if (apiRequestSent != null && _baselineTime != null) {
    final preApiOverhead = apiRequestSent - _baselineTime!;
    lines.add('');
    lines.add('  ${'Total pre-API overhead'.padRight(22)} ${_formatMs(preApiOverhead).padLeft(10)}ms');
  }

  return lines.join('\n');
}

/// Get the full profiling report.
String getQueryProfileReport() {
  if (!_queryProfilerEnabled) {
    return 'Query profiling not enabled (set NEOMCLAW_PROFILE_QUERY=1)';
  }

  if (_checkpointTimes.isEmpty) {
    return 'No query profiling checkpoints recorded';
  }

  final lines = <String>[];
  lines.add('=' * 80);
  lines.add('QUERY PROFILING REPORT - Query #$_queryCount');
  lines.add('=' * 80);
  lines.add('');

  final baseline = _baselineTime ?? 0;
  var prevTime = baseline;
  double apiRequestSentTime = 0;
  double firstChunkTime = 0;

  final sortedNames = _checkpointTimes.keys.toList()
    ..sort((a, b) => _checkpointTimes[a]!.compareTo(_checkpointTimes[b]!));

  for (final name in sortedNames) {
    final time = _checkpointTimes[name]!;
    final relativeTime = time - baseline;
    final deltaMs = time - prevTime;
    final warning = _getSlowWarning(deltaMs, name);
    lines.add(
      '${_formatMs(relativeTime).padLeft(10)}ms  +${_formatMs(deltaMs).padLeft(9)}ms  $name$warning',
    );

    if (name == 'query_api_request_sent') apiRequestSentTime = relativeTime;
    if (name == 'query_first_chunk_received') firstChunkTime = relativeTime;

    prevTime = time;
  }

  lines.add('');
  lines.add('-' * 80);

  if (firstChunkTime > 0) {
    final preRequestOverhead = apiRequestSentTime;
    final networkLatency = firstChunkTime - apiRequestSentTime;
    final preRequestPercent =
        (preRequestOverhead / firstChunkTime * 100).toStringAsFixed(1);
    final networkPercent =
        (networkLatency / firstChunkTime * 100).toStringAsFixed(1);

    lines.add('Total TTFT: ${_formatMs(firstChunkTime)}ms');
    lines.add(
      '  - Pre-request overhead: ${_formatMs(preRequestOverhead)}ms ($preRequestPercent%)',
    );
    lines.add(
      '  - Network latency: ${_formatMs(networkLatency)}ms ($networkPercent%)',
    );
  } else {
    final totalTime = prevTime - baseline;
    lines.add('Total time: ${_formatMs(totalTime)}ms');
  }

  lines.add(_getPhaseSummary());
  lines.add('=' * 80);

  return lines.join('\n');
}

/// Log the query profile report to debug output.
void logQueryProfileReport() {
  if (!_queryProfilerEnabled) return;
  // In the Dart port, callers should capture the output of
  // getQueryProfileReport() and route it to their debug logger.
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 4 — Read/Edit Context (from readEditContext.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Chunk size for file scanning (8 KB).
const int chunkSize = 8 * 1024;

/// Maximum bytes to scan before giving up.
const int maxScanBytes = 10 * 1024 * 1024;

/// Newline byte.
const int _nl = 0x0a; // \n

/// Result of scanning a file for an edit context.
class EditContext {
  EditContext({
    required this.content,
    required this.lineOffset,
    required this.truncated,
  });

  /// Slice of the file around the match.
  final String content;

  /// 1-based line number of content's first line.
  final int lineOffset;

  /// True if maxScanBytes was hit without finding the needle.
  final bool truncated;
}

/// Count newlines in a byte range.
int _countNewlines(Uint8List buf, int start, int end) {
  var n = 0;
  for (var i = start; i < end; i++) {
    if (buf[i] == _nl) n++;
  }
  return n;
}

/// Find needle in buf bounded to [0, end).
int _indexOfWithin(Uint8List buf, Uint8List needle, int end) {
  outer:
  for (var i = 0; i <= end - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (buf[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  return -1;
}

/// Normalize CRLF to LF.
String _normalizeCRLF(Uint8List buf, int len) {
  final s = utf8.decode(buf.sublist(0, len));
  return s.contains('\r') ? s.replaceAll('\r\n', '\n') : s;
}

/// Read the edit context around a needle in a file.
/// Returns `null` on ENOENT. Returns truncated context if needle not found.
Future<EditContext?> readEditContext(
  String path,
  String needle, {
  int contextLines = 3,
}) async {
  RandomAccessFile handle;
  try {
    handle = await File(path).open(mode: FileMode.read);
  } on PathNotFoundException {
    return null;
  }

  try {
    return await _scanForContext(handle, needle, contextLines);
  } finally {
    await handle.close();
  }
}

/// Core scanning logic for readEditContext.
Future<EditContext> _scanForContext(
  RandomAccessFile handle,
  String needle,
  int contextLines,
) async {
  if (needle.isEmpty) {
    return EditContext(content: '', lineOffset: 1, truncated: false);
  }

  final needleLF = utf8.encode(needle);
  final needleLFBytes = Uint8List.fromList(needleLF);

  // Count newlines for CRLF alternative.
  var nlCount = 0;
  for (final b in needleLFBytes) {
    if (b == _nl) nlCount++;
  }

  Uint8List? needleCRLF;
  final overlap = needleLFBytes.length + nlCount - 1;

  final buf = Uint8List(chunkSize + overlap);
  var pos = 0;
  var linesBeforePos = 0;
  var prevTail = 0;

  while (pos < maxScanBytes) {
    await handle.setPosition(pos);
    final bytesRead = await handle.readInto(buf, prevTail, chunkSize + prevTail);
    if (bytesRead == 0) break;
    final actualRead = bytesRead - prevTail;
    if (actualRead <= 0) break;
    final viewLen = prevTail + actualRead;

    var matchAt = _indexOfWithin(buf, needleLFBytes, viewLen);
    var matchLen = needleLFBytes.length;

    if (matchAt == -1 && nlCount > 0) {
      needleCRLF ??= Uint8List.fromList(
        utf8.encode(needle.replaceAll('\n', '\r\n')),
      );
      matchAt = _indexOfWithin(buf, needleCRLF!, viewLen);
      matchLen = needleCRLF!.length;
    }

    if (matchAt != -1) {
      final absMatch = pos - prevTail + matchAt;
      return await _sliceContext(
        handle,
        absMatch,
        matchLen,
        contextLines,
        linesBeforePos + _countNewlines(buf, 0, matchAt),
      );
    }

    pos += actualRead;
    final nextTail = math.min(overlap, viewLen);
    linesBeforePos += _countNewlines(buf, 0, viewLen - nextTail);
    prevTail = nextTail;
    // Copy tail to front.
    for (var i = 0; i < prevTail; i++) {
      buf[i] = buf[viewLen - prevTail + i];
    }
  }

  return EditContext(
    content: '',
    lineOffset: 1,
    truncated: pos >= maxScanBytes,
  );
}

/// Slice context around a match.
Future<EditContext> _sliceContext(
  RandomAccessFile handle,
  int matchStart,
  int matchLen,
  int contextLines,
  int linesBeforeMatch,
) async {
  // Scan backward to find contextLines prior newlines.
  final backChunk = math.min(matchStart, chunkSize);
  final backBuf = Uint8List(backChunk);
  await handle.setPosition(matchStart - backChunk);
  final backRead = await handle.readInto(backBuf);

  var ctxStart = matchStart;
  var nlSeen = 0;
  for (var i = backRead - 1; i >= 0 && nlSeen <= contextLines; i--) {
    if (backBuf[i] == _nl) {
      nlSeen++;
      if (nlSeen > contextLines) break;
    }
    ctxStart--;
  }

  final walkedBack = matchStart - ctxStart;
  final lineOffset =
      linesBeforeMatch -
      _countNewlines(backBuf, backRead - walkedBack, backRead) +
      1;

  // Scan forward to find contextLines trailing newlines.
  final matchEnd = matchStart + matchLen;
  final fwdBuf = Uint8List(chunkSize);
  await handle.setPosition(matchEnd);
  final fwdRead = await handle.readInto(fwdBuf);

  var ctxEnd = matchEnd;
  nlSeen = 0;
  for (var i = 0; i < fwdRead; i++) {
    ctxEnd++;
    if (fwdBuf[i] == _nl) {
      nlSeen++;
      if (nlSeen >= contextLines + 1) break;
    }
  }

  // Read the exact context range.
  final len = ctxEnd - ctxStart;
  final out = Uint8List(len);
  await handle.setPosition(ctxStart);
  final outRead = await handle.readInto(out);

  return EditContext(
    content: _normalizeCRLF(out, outRead),
    lineOffset: lineOffset,
    truncated: false,
  );
}

/// Read a capped portion of a file. Returns null if the file exceeds
/// maxScanBytes.
Future<String?> readCapped(RandomAccessFile handle) async {
  var buf = Uint8List(chunkSize);
  var total = 0;

  while (true) {
    if (total == buf.length) {
      final grown = Uint8List(math.min(buf.length * 2, maxScanBytes + chunkSize));
      grown.setRange(0, total, buf);
      buf = grown;
    }
    await handle.setPosition(total);
    final bytesRead = await handle.readInto(buf, total, buf.length);
    final actualRead = bytesRead - total;
    if (actualRead <= 0) break;
    total = bytesRead;
    if (total > maxScanBytes) return null;
  }

  return _normalizeCRLF(buf, total);
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════════════════

bool _isEnvTruthy(String? value) {
  if (value == null) return false;
  final v = value.toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}
