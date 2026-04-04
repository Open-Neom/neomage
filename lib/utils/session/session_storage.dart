// Session storage — port of neom_claw/src/utils/sessionStorage.ts.
// Session persistence, transcript JSONL read/write, message chain management,
// session listing, metadata caching, and project directory resolution.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

// ─── Constants ───

/// Maximum transcript file size before bail-out to prevent OOM.
const int maxTranscriptReadBytes = 50 * 1024 * 1024;

/// Maximum size for tombstone rewrite slow path.
const int _maxTombstoneRewriteBytes = 50 * 1024 * 1024;

/// Tail read buffer size for lite metadata scans.
const int _liteReadBufSize = 64 * 1024;

/// Default flush interval for batched writes (ms).
const int _defaultFlushIntervalMs = 100;

/// Maximum bytes per write chunk.
const int _maxChunkBytes = 100 * 1024 * 1024;

/// Pattern to skip non-meaningful messages when extracting first prompt.
final RegExp _skipFirstPromptPattern = RegExp(
  r'^(?:\s*<[a-z][\w-]*[\s>]|\[Request interrupted by user[^\]]*\])',
);

// ─── Types ───

/// A transcript is a list of serialized messages.
typedef Transcript = List<Map<String, dynamic>>;

/// Metadata for a persisted session.
class SessionMetadata {
  final String sessionId;
  final String? customTitle;
  final String? aiTitle;
  final String? firstPrompt;
  final String? lastPrompt;
  final String? tag;
  final String? agentName;
  final String? agentColor;
  final String? agentSetting;
  final String? mode;
  final DateTime? lastModified;
  final int? fileSize;
  final WorktreeSessionInfo? worktreeSession;
  final PrLink? prLink;

  const SessionMetadata({
    required this.sessionId,
    this.customTitle,
    this.aiTitle,
    this.firstPrompt,
    this.lastPrompt,
    this.tag,
    this.agentName,
    this.agentColor,
    this.agentSetting,
    this.mode,
    this.lastModified,
    this.fileSize,
    this.worktreeSession,
    this.prLink,
  });

  /// Display title: custom > AI-generated > first prompt > session ID.
  String get displayTitle => customTitle ?? aiTitle ?? firstPrompt ?? sessionId;
}

/// Worktree session state.
class WorktreeSessionInfo {
  final String originalCwd;
  final String worktreePath;
  final String worktreeName;
  final String? originalBranch;
  final String sessionId;
  final bool? hookBased;

  const WorktreeSessionInfo({
    required this.originalCwd,
    required this.worktreePath,
    required this.worktreeName,
    this.originalBranch,
    required this.sessionId,
    this.hookBased,
  });

  factory WorktreeSessionInfo.fromJson(Map<String, dynamic> json) {
    return WorktreeSessionInfo(
      originalCwd: json['originalCwd'] as String,
      worktreePath: json['worktreePath'] as String,
      worktreeName: json['worktreeName'] as String,
      originalBranch: json['originalBranch'] as String?,
      sessionId: json['sessionId'] as String,
      hookBased: json['hookBased'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
    'originalCwd': originalCwd,
    'worktreePath': worktreePath,
    'worktreeName': worktreeName,
    if (originalBranch != null) 'originalBranch': originalBranch,
    'sessionId': sessionId,
    if (hookBased != null) 'hookBased': hookBased,
  };
}

/// PR link metadata.
class PrLink {
  final int prNumber;
  final String prUrl;
  final String prRepository;
  final String timestamp;

  const PrLink({
    required this.prNumber,
    required this.prUrl,
    required this.prRepository,
    required this.timestamp,
  });

  factory PrLink.fromJson(Map<String, dynamic> json) {
    return PrLink(
      prNumber: json['prNumber'] as int,
      prUrl: json['prUrl'] as String,
      prRepository: json['prRepository'] as String,
      timestamp: json['timestamp'] as String,
    );
  }
}

/// Agent metadata for subagent transcripts.
class AgentMetadata {
  final String agentType;
  final String? worktreePath;
  final String? description;

  const AgentMetadata({
    required this.agentType,
    this.worktreePath,
    this.description,
  });

  factory AgentMetadata.fromJson(Map<String, dynamic> json) {
    return AgentMetadata(
      agentType: json['agentType'] as String,
      worktreePath: json['worktreePath'] as String?,
      description: json['description'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'agentType': agentType,
    if (worktreePath != null) 'worktreePath': worktreePath,
    if (description != null) 'description': description,
  };
}

/// Remote agent metadata.
class RemoteAgentMetadata {
  final String taskId;
  final String remoteTaskType;
  final String sessionId;
  final String title;
  final String command;
  final int spawnedAt;
  final String? toolUseId;
  final bool? isLongRunning;
  final bool? isUltraplan;
  final bool? isRemoteReview;
  final Map<String, dynamic>? remoteTaskMetadata;

  const RemoteAgentMetadata({
    required this.taskId,
    required this.remoteTaskType,
    required this.sessionId,
    required this.title,
    required this.command,
    required this.spawnedAt,
    this.toolUseId,
    this.isLongRunning,
    this.isUltraplan,
    this.isRemoteReview,
    this.remoteTaskMetadata,
  });

  factory RemoteAgentMetadata.fromJson(Map<String, dynamic> json) {
    return RemoteAgentMetadata(
      taskId: json['taskId'] as String,
      remoteTaskType: json['remoteTaskType'] as String,
      sessionId: json['sessionId'] as String,
      title: json['title'] as String,
      command: json['command'] as String,
      spawnedAt: json['spawnedAt'] as int,
      toolUseId: json['toolUseId'] as String?,
      isLongRunning: json['isLongRunning'] as bool?,
      isUltraplan: json['isUltraplan'] as bool?,
      isRemoteReview: json['isRemoteReview'] as bool?,
      remoteTaskMetadata: json['remoteTaskMetadata'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson() => {
    'taskId': taskId,
    'remoteTaskType': remoteTaskType,
    'sessionId': sessionId,
    'title': title,
    'command': command,
    'spawnedAt': spawnedAt,
    if (toolUseId != null) 'toolUseId': toolUseId,
    if (isLongRunning != null) 'isLongRunning': isLongRunning,
    if (isUltraplan != null) 'isUltraplan': isUltraplan,
    if (isRemoteReview != null) 'isRemoteReview': isRemoteReview,
    if (remoteTaskMetadata != null) 'remoteTaskMetadata': remoteTaskMetadata,
  };
}

/// A JSONL log entry.
class LogEntry {
  final String type;
  final Map<String, dynamic> data;

  const LogEntry({required this.type, required this.data});

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(type: json['type'] as String? ?? 'unknown', data: json);
  }

  String toJsonLine() => jsonEncode(data);
}

// ─── Session Storage ───

/// Manages session transcript persistence.
///
/// Handles JSONL-based session file writing with batched I/O,
/// metadata caching, and session enumeration.
class SessionStorage {
  /// Config home directory (e.g., ~/.neomclaw).
  final String configHomeDir;

  /// Current working directory for project resolution.
  final String cwd;

  /// Current session ID.
  String _sessionId;

  /// Session file path (null until materialized).
  String? _sessionFile;

  /// Entries buffered before session file is created.
  final List<LogEntry> _pendingEntries = [];

  /// Per-file write queues for batched I/O.
  final Map<String, List<_QueuedWrite>> _writeQueues = {};

  /// Timer for scheduled queue draining.
  Timer? _flushTimer;

  /// Active drain future (if running).
  Future<void>? _activeDrain;

  /// Flush interval in milliseconds.
  final int _flushIntervalMs = _defaultFlushIntervalMs;

  /// Pending write counter for flush synchronization.
  int _pendingWriteCount = 0;

  /// Completers waiting for all writes to finish.
  final List<Completer<void>> _flushCompleters = [];

  /// Cached session metadata.
  String? currentSessionTitle;
  String? currentSessionTag;
  String? currentSessionAgentName;
  String? currentSessionAgentColor;
  String? currentSessionAgentSetting;
  String? currentSessionLastPrompt;
  String? currentSessionMode;
  WorktreeSessionInfo? currentSessionWorktree;
  PrLink? currentSessionPrLink;

  /// Set of already-recorded message UUIDs.
  final Map<String, Set<String>> _sessionMessageSets = {};

  /// Cached existing session file paths.
  // ignore: unused_field
  final Map<String, String> _existingSessionFiles = {};

  /// Agent transcript subdirectories.
  final Map<String, String> _agentTranscriptSubdirs = {};

  SessionStorage({
    required this.configHomeDir,
    required this.cwd,
    required String sessionId,
  }) : _sessionId = sessionId;

  String get sessionId => _sessionId;

  /// Set the session ID (e.g., on resume or fork).
  void switchSession(String newSessionId) {
    _sessionId = newSessionId;
    _sessionFile = null;
    _pendingEntries.clear();
  }

  // ─── Path Resolution ───

  /// Get the projects directory.
  String get projectsDir => p.join(configHomeDir, 'projects');

  /// Get the project directory for a given working directory.
  String getProjectDir(String projectDir) {
    return p.join(projectsDir, _sanitizePath(projectDir));
  }

  /// Get the transcript path for the current session.
  String get transcriptPath {
    final projectDir = getProjectDir(cwd);
    return p.join(projectDir, '$_sessionId.jsonl');
  }

  /// Get the transcript path for a specific session.
  String getTranscriptPathForSession(String sessionId) {
    if (sessionId == _sessionId) return transcriptPath;
    final projectDir = getProjectDir(cwd);
    return p.join(projectDir, '$sessionId.jsonl');
  }

  /// Get the agent transcript path for a subagent.
  String getAgentTranscriptPath(String agentId) {
    final projectDir = getProjectDir(cwd);
    final subdir = _agentTranscriptSubdirs[agentId];
    final base = subdir != null
        ? p.join(projectDir, _sessionId, 'subagents', subdir)
        : p.join(projectDir, _sessionId, 'subagents');
    return p.join(base, 'agent-$agentId.jsonl');
  }

  /// Set a subdirectory for an agent's transcripts.
  void setAgentTranscriptSubdir(String agentId, String subdir) {
    _agentTranscriptSubdirs[agentId] = subdir;
  }

  /// Clear an agent's transcript subdirectory.
  void clearAgentTranscriptSubdir(String agentId) {
    _agentTranscriptSubdirs.remove(agentId);
  }

  // ─── Session Existence ───

  /// Check if a session ID exists on disk.
  bool sessionIdExists(String sessionId) {
    final sessionFile = p.join(getProjectDir(cwd), '$sessionId.jsonl');
    return File(sessionFile).existsSync();
  }

  // ─── Write Operations ───

  /// Insert a chain of messages into the transcript.
  Future<void> insertMessageChain(
    Transcript messages, {
    bool isSidechain = false,
    String? agentId,
    String? startingParentUuid,
  }) async {
    String? parentUuid = startingParentUuid;

    // First user/assistant message materializes the session file.
    if (_sessionFile == null &&
        messages.any((m) => m['type'] == 'user' || m['type'] == 'assistant')) {
      await _materializeSessionFile();
    }

    for (final message in messages) {
      final isCompactBoundary =
          message['type'] == 'system' &&
          message['subtype'] == 'compact_boundary';

      // Build transcript entry.
      final entry = <String, dynamic>{
        'parentUuid': isCompactBoundary ? null : parentUuid,
        if (isCompactBoundary && parentUuid != null)
          'logicalParentUuid': parentUuid,
        'isSidechain': isSidechain,
        'agentId': ?agentId,
        ...message,
        'sessionId': _sessionId,
        'cwd': cwd,
        'version': 'flutter-port',
      };

      await _appendEntry(LogEntry(type: entry['type'] as String, data: entry));

      // Update parent chain (skip progress messages).
      if (message['type'] != 'progress') {
        parentUuid = message['uuid'] as String?;
      }
    }

    // Cache last user prompt for metadata.
    if (!isSidechain) {
      final text = _getFirstMeaningfulText(messages);
      if (text != null) {
        final flat = text.replaceAll('\n', ' ').trim();
        currentSessionLastPrompt = flat.length > 200
            ? '${flat.substring(0, 200).trim()}\u2026'
            : flat;
      }
    }
  }

  /// Record a transcript (public API, deduplicates against already-recorded).
  Future<String?> recordTranscript(
    Transcript messages, {
    String? startingParentUuidHint,
  }) async {
    final messageSet = await _getSessionMessages(_sessionId);
    final newMessages = <Map<String, dynamic>>[];
    String? startingParentUuid = startingParentUuidHint;
    var seenNewMessage = false;

    for (final m in messages) {
      final uuid = m['uuid'] as String?;
      if (uuid != null && messageSet.contains(uuid)) {
        if (!seenNewMessage && m['type'] != 'progress') {
          startingParentUuid = uuid;
        }
      } else {
        newMessages.add(m);
        seenNewMessage = true;
      }
    }

    if (newMessages.isNotEmpty) {
      await insertMessageChain(
        newMessages,
        startingParentUuid: startingParentUuid,
      );
    }

    // Return last recorded chain participant's UUID.
    final lastRecorded = newMessages.lastWhere(
      (m) => m['type'] != 'progress',
      orElse: () => <String, dynamic>{},
    );
    return (lastRecorded['uuid'] as String?) ?? startingParentUuid;
  }

  /// Record a sidechain transcript (e.g., subagent).
  Future<void> recordSidechainTranscript(
    Transcript messages, {
    String? agentId,
    String? startingParentUuid,
  }) async {
    await insertMessageChain(
      messages,
      isSidechain: true,
      agentId: agentId,
      startingParentUuid: startingParentUuid,
    );
  }

  /// Remove a message from the transcript by UUID.
  Future<void> removeTranscriptMessage(String targetUuid) async {
    if (_sessionFile == null) return;
    _incrementPendingWrites();
    try {
      await _removeMessageByUuid(targetUuid);
    } finally {
      _decrementPendingWrites();
    }
  }

  /// Flush all pending writes to disk.
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;

    if (_activeDrain != null) {
      await _activeDrain;
    }
    await _drainWriteQueue();

    if (_pendingWriteCount > 0) {
      final completer = Completer<void>();
      _flushCompleters.add(completer);
      return completer.future;
    }
  }

  /// Re-append cached session metadata to the end of the transcript.
  void reAppendSessionMetadata({bool skipTitleRefresh = false}) {
    if (_sessionFile == null) return;

    if (currentSessionLastPrompt != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'last-prompt',
        'lastPrompt': currentSessionLastPrompt,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionTitle != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'custom-title',
        'customTitle': currentSessionTitle,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionTag != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'tag',
        'tag': currentSessionTag,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionAgentName != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'agent-name',
        'agentName': currentSessionAgentName,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionAgentColor != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'agent-color',
        'agentColor': currentSessionAgentColor,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionMode != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'mode',
        'mode': currentSessionMode,
        'sessionId': _sessionId,
      });
    }
    if (currentSessionPrLink != null) {
      _appendEntryToFileSync(_sessionFile!, {
        'type': 'pr-link',
        'sessionId': _sessionId,
        'prNumber': currentSessionPrLink!.prNumber,
        'prUrl': currentSessionPrLink!.prUrl,
        'prRepository': currentSessionPrLink!.prRepository,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
    }
  }

  /// Reset the session file pointer after session switch.
  void resetSessionFile() {
    _sessionFile = null;
    _pendingEntries.clear();
  }

  /// Adopt an existing session file for resume.
  void adoptResumedSessionFile() {
    _sessionFile = transcriptPath;
    reAppendSessionMetadata(skipTitleRefresh: true);
  }

  // ─── Read Operations ───

  /// Load a transcript from a JSONL file.
  Future<List<Map<String, dynamic>>> loadTranscriptFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    final stat = await file.stat();
    if (stat.size > maxTranscriptReadBytes) {
      return []; // Too large, prevent OOM.
    }

    final content = await file.readAsString();
    return _parseJSONL(content);
  }

  /// Read lite metadata from the tail of a session file.
  Future<SessionMetadata?> readLiteMetadata(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    final stat = await file.stat();
    final tail = await _readFileTail(filePath, _liteReadBufSize);
    if (tail.isEmpty) return null;

    final lines = tail.split('\n');
    String? customTitle;
    String? aiTitle;
    String? firstPrompt;
    String? lastPrompt;
    String? tag;
    String? agentName;
    String? agentColor;
    String? agentSetting;
    String? mode;

    for (final line in lines.reversed) {
      if (line.isEmpty) continue;
      try {
        if (line.startsWith('{"type":"custom-title"')) {
          customTitle ??= _extractJsonField(line, 'customTitle');
        } else if (line.startsWith('{"type":"ai-title"')) {
          aiTitle ??= _extractJsonField(line, 'title');
        } else if (line.startsWith('{"type":"last-prompt"')) {
          lastPrompt ??= _extractJsonField(line, 'lastPrompt');
        } else if (line.startsWith('{"type":"tag"')) {
          tag ??= _extractJsonField(line, 'tag');
        } else if (line.startsWith('{"type":"agent-name"')) {
          agentName ??= _extractJsonField(line, 'agentName');
        } else if (line.startsWith('{"type":"agent-color"')) {
          agentColor ??= _extractJsonField(line, 'agentColor');
        } else if (line.startsWith('{"type":"agent-setting"')) {
          agentSetting ??= _extractJsonField(line, 'agentSetting');
        } else if (line.startsWith('{"type":"mode"')) {
          mode ??= _extractJsonField(line, 'mode');
        }
      } catch (_) {
        // Skip malformed lines.
      }
    }

    // Extract first prompt from transcript messages.
    for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final parsed = jsonDecode(line) as Map<String, dynamic>;
        if (parsed['type'] == 'user') {
          final content = parsed['message']?['content'];
          final text = content is String ? content : null;
          if (text != null &&
              text.isNotEmpty &&
              !_skipFirstPromptPattern.hasMatch(text)) {
            firstPrompt = text.length > 200
                ? '${text.substring(0, 200).trim()}\u2026'
                : text;
            break;
          }
        }
      } catch (_) {
        // Skip malformed lines.
      }
    }

    final sessionId = p.basenameWithoutExtension(filePath);
    return SessionMetadata(
      sessionId: sessionId,
      customTitle: customTitle,
      aiTitle: aiTitle,
      firstPrompt: firstPrompt,
      lastPrompt: lastPrompt,
      tag: tag,
      agentName: agentName,
      agentColor: agentColor,
      agentSetting: agentSetting,
      mode: mode,
      lastModified: stat.modified,
      fileSize: stat.size,
    );
  }

  /// List all sessions for the current project.
  Future<List<SessionMetadata>> listSessions({int limit = 50}) async {
    final projectDir = getProjectDir(cwd);
    final dir = Directory(projectDir);
    if (!await dir.exists()) return [];

    final sessions = <SessionMetadata>[];
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.jsonl')) continue;

      final metadata = await readLiteMetadata(entity.path);
      if (metadata != null) {
        sessions.add(metadata);
      }
    }

    // Sort by last modified, newest first.
    sessions.sort((a, b) {
      final aTime = a.lastModified ?? DateTime(2000);
      final bTime = b.lastModified ?? DateTime(2000);
      return bTime.compareTo(aTime);
    });

    return sessions.take(limit).toList();
  }

  // ─── Agent Metadata ───

  /// Write agent metadata to a sidecar file.
  Future<void> writeAgentMetadata(
    String agentId,
    AgentMetadata metadata,
  ) async {
    final path = _getAgentMetadataPath(agentId);
    final dir = Directory(p.dirname(path));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await File(path).writeAsString(jsonEncode(metadata.toJson()));
  }

  /// Read agent metadata from a sidecar file.
  Future<AgentMetadata?> readAgentMetadata(String agentId) async {
    final path = _getAgentMetadataPath(agentId);
    try {
      final raw = await File(path).readAsString();
      return AgentMetadata.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on FileSystemException {
      return null;
    }
  }

  // ─── Private Helpers ───

  String _getAgentMetadataPath(String agentId) {
    return getAgentTranscriptPath(
      agentId,
    ).replaceFirst(RegExp(r'\.jsonl$'), '.meta.json');
  }

  /// Sanitize a path for use as a config key / directory name.
  String _sanitizePath(String pathStr) {
    return pathStr
        .replaceAll(RegExp(r'[^\w\-./]'), '_')
        .replaceAll(RegExp(r'/+'), '_');
  }

  /// Get or create the set of recorded message UUIDs for a session.
  Future<Set<String>> _getSessionMessages(String sessionId) async {
    if (_sessionMessageSets.containsKey(sessionId)) {
      return _sessionMessageSets[sessionId]!;
    }
    final messageSet = <String>{};
    _sessionMessageSets[sessionId] = messageSet;
    return messageSet;
  }

  /// Materialize the session file on first real message.
  Future<void> _materializeSessionFile() async {
    _ensureCurrentSessionFile();
    reAppendSessionMetadata();
    if (_pendingEntries.isNotEmpty) {
      final buffered = List<LogEntry>.from(_pendingEntries);
      _pendingEntries.clear();
      for (final entry in buffered) {
        await _appendEntry(entry);
      }
    }
  }

  /// Ensure the session file path is set.
  String _ensureCurrentSessionFile() {
    _sessionFile ??= transcriptPath;
    return _sessionFile!;
  }

  /// Append an entry to the session.
  Future<void> _appendEntry(LogEntry entry) async {
    if (_sessionFile == null) {
      _pendingEntries.add(entry);
      return;
    }

    final sessionFile = _sessionFile!;
    final messageSet = await _getSessionMessages(_sessionId);
    final uuid = entry.data['uuid'] as String?;

    // Dedup check for transcript messages.
    if (uuid != null &&
        (entry.type == 'user' ||
            entry.type == 'assistant' ||
            entry.type == 'attachment' ||
            entry.type == 'system')) {
      if (messageSet.contains(uuid)) return;
      messageSet.add(uuid);
    }

    _enqueueWrite(sessionFile, entry);
  }

  /// Enqueue a write for batched I/O.
  void _enqueueWrite(String filePath, LogEntry entry) {
    _writeQueues.putIfAbsent(filePath, () => []);
    final completer = Completer<void>();
    _writeQueues[filePath]!.add(
      _QueuedWrite(entry: entry, completer: completer),
    );
    _scheduleDrain();
  }

  /// Schedule a drain of the write queue.
  void _scheduleDrain() {
    if (_flushTimer != null) return;
    _flushTimer = Timer(Duration(milliseconds: _flushIntervalMs), () async {
      _flushTimer = null;
      _activeDrain = _drainWriteQueue();
      await _activeDrain;
      _activeDrain = null;
      if (_writeQueues.isNotEmpty) _scheduleDrain();
    });
  }

  /// Drain all write queues to disk.
  Future<void> _drainWriteQueue() async {
    for (final entry in _writeQueues.entries) {
      final filePath = entry.key;
      final queue = entry.value;
      if (queue.isEmpty) continue;

      final batch = List<_QueuedWrite>.from(queue);
      queue.clear();

      var content = StringBuffer();
      final completers = <Completer<void>>[];

      for (final qw in batch) {
        final line = '${qw.entry.toJsonLine()}\n';
        if (content.length + line.length >= _maxChunkBytes) {
          await _appendToFile(filePath, content.toString());
          for (final c in completers) {
            c.complete();
          }
          completers.clear();
          content = StringBuffer();
        }
        content.write(line);
        completers.add(qw.completer);
      }

      if (content.isNotEmpty) {
        await _appendToFile(filePath, content.toString());
        for (final c in completers) {
          c.complete();
        }
      }
    }

    // Clean up empty queues.
    _writeQueues.removeWhere((_, queue) => queue.isEmpty);
  }

  /// Append data to a file, creating directories if needed.
  Future<void> _appendToFile(String filePath, String data) async {
    try {
      await File(filePath).writeAsString(data, mode: FileMode.append);
    } on FileSystemException {
      final dir = Directory(p.dirname(filePath));
      await dir.create(recursive: true);
      await File(filePath).writeAsString(data, mode: FileMode.append);
    }
  }

  /// Synchronously append an entry to a file (for metadata re-append).
  void _appendEntryToFileSync(String filePath, Map<String, dynamic> entry) {
    try {
      File(
        filePath,
      ).writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Remove a message by UUID from the transcript file.
  Future<void> _removeMessageByUuid(String targetUuid) async {
    if (_sessionFile == null) return;
    try {
      final file = File(_sessionFile!);
      final stat = await file.stat();
      if (stat.size == 0) return;

      if (stat.size > _maxTombstoneRewriteBytes) return;

      final content = await file.readAsString();
      final lines = content.split('\n').where((line) {
        if (line.trim().isEmpty) return true;
        try {
          final entry = jsonDecode(line) as Map<String, dynamic>;
          return entry['uuid'] != targetUuid;
        } catch (_) {
          return true;
        }
      }).toList();
      await file.writeAsString(lines.join('\n'));
    } catch (_) {
      // Silently ignore errors.
    }
  }

  void _incrementPendingWrites() => _pendingWriteCount++;

  void _decrementPendingWrites() {
    _pendingWriteCount--;
    if (_pendingWriteCount == 0) {
      for (final completer in _flushCompleters) {
        completer.complete();
      }
      _flushCompleters.clear();
    }
  }

  /// Read the tail of a file.
  Future<String> _readFileTail(String filePath, int maxBytes) async {
    try {
      final file = File(filePath);
      final length = await file.length();
      final start = length > maxBytes ? length - maxBytes : 0;
      final raf = await file.open(mode: FileMode.read);
      try {
        await raf.setPosition(start);
        final bytes = await raf.read(maxBytes);
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return '';
    }
  }

  /// Extract a JSON string field from a line.
  String? _extractJsonField(String line, String field) {
    final pattern = '"$field":"';
    final start = line.indexOf(pattern);
    if (start < 0) return null;
    final valueStart = start + pattern.length;
    final end = line.indexOf('"', valueStart);
    if (end < 0) return null;
    return line.substring(valueStart, end);
  }

  /// Parse JSONL content into a list of maps.
  List<Map<String, dynamic>> _parseJSONL(String content) {
    final result = <Map<String, dynamic>>[];
    for (final line in content.split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        result.add(jsonDecode(line) as Map<String, dynamic>);
      } catch (_) {
        // Skip malformed lines.
      }
    }
    return result;
  }

  /// Get the first meaningful user text from a list of messages.
  String? _getFirstMeaningfulText(Transcript messages) {
    for (final msg in messages) {
      if (msg['type'] != 'user') continue;
      final content = msg['message']?['content'];
      final text = content is String ? content : null;
      if (text != null &&
          text.isNotEmpty &&
          !_skipFirstPromptPattern.hasMatch(text)) {
        return text;
      }
    }
    return null;
  }
}

/// Internal queued write entry.
class _QueuedWrite {
  final LogEntry entry;
  final Completer<void> completer;

  const _QueuedWrite({required this.entry, required this.completer});
}

/// Check if an entry is a transcript message (user, assistant, attachment, system).
bool isTranscriptMessage(Map<String, dynamic> entry) {
  final type = entry['type'];
  return type == 'user' ||
      type == 'assistant' ||
      type == 'attachment' ||
      type == 'system';
}

/// Check if a message is a chain participant (excludes progress).
bool isChainParticipant(Map<String, dynamic> message) {
  return message['type'] != 'progress';
}

/// Check if an entry is a compact boundary message.
bool isCompactBoundaryMessage(Map<String, dynamic> entry) {
  return entry['type'] == 'system' && entry['subtype'] == 'compact_boundary';
}
