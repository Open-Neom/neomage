// HistoryService — port of neom_claw/src/services/SessionMemory/ +
// src/assistant/sessionHistory.ts.
// Manages conversation history, search, replay, and analytics.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ─── Types ───

/// Type of history entry.
enum HistoryEntryType {
  message,
  toolUse,
  toolResult,
  command,
  systemEvent,
  compaction,
  fork,
  resume,
}

/// A single history entry with full metadata.
class HistoryEntry {
  final String id;
  final String sessionId;
  final HistoryEntryType type;
  final DateTime timestamp;
  final String role; // 'user', 'assistant', 'system', 'tool'
  final String content;
  final Map<String, dynamic>? metadata;
  final String? toolName;
  final String? toolId;
  final int? tokenCount;
  final double? cost;
  final Duration? latency;
  final String? parentId;
  final int turnIndex;

  const HistoryEntry({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.timestamp,
    required this.role,
    required this.content,
    this.metadata,
    this.toolName,
    this.toolId,
    this.tokenCount,
    this.cost,
    this.latency,
    this.parentId,
    required this.turnIndex,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'sessionId': sessionId,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'role': role,
        'content': content,
        if (metadata != null) 'metadata': metadata,
        if (toolName != null) 'toolName': toolName,
        if (toolId != null) 'toolId': toolId,
        if (tokenCount != null) 'tokenCount': tokenCount,
        if (cost != null) 'cost': cost,
        if (latency != null) 'latencyMs': latency!.inMilliseconds,
        if (parentId != null) 'parentId': parentId,
        'turnIndex': turnIndex,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String,
        sessionId: json['sessionId'] as String,
        type: HistoryEntryType.values.byName(json['type'] as String),
        timestamp: DateTime.parse(json['timestamp'] as String),
        role: json['role'] as String,
        content: json['content'] as String,
        metadata: json['metadata'] as Map<String, dynamic>?,
        toolName: json['toolName'] as String?,
        toolId: json['toolId'] as String?,
        tokenCount: json['tokenCount'] as int?,
        cost: json['cost'] as double?,
        latency: json['latencyMs'] != null
            ? Duration(milliseconds: json['latencyMs'] as int)
            : null,
        parentId: json['parentId'] as String?,
        turnIndex: json['turnIndex'] as int? ?? 0,
      );

  HistoryEntry copyWith({
    String? id,
    String? sessionId,
    HistoryEntryType? type,
    DateTime? timestamp,
    String? role,
    String? content,
    Map<String, dynamic>? metadata,
    String? toolName,
    String? toolId,
    int? tokenCount,
    double? cost,
    Duration? latency,
    String? parentId,
    int? turnIndex,
  }) =>
      HistoryEntry(
        id: id ?? this.id,
        sessionId: sessionId ?? this.sessionId,
        type: type ?? this.type,
        timestamp: timestamp ?? this.timestamp,
        role: role ?? this.role,
        content: content ?? this.content,
        metadata: metadata ?? this.metadata,
        toolName: toolName ?? this.toolName,
        toolId: toolId ?? this.toolId,
        tokenCount: tokenCount ?? this.tokenCount,
        cost: cost ?? this.cost,
        latency: latency ?? this.latency,
        parentId: parentId ?? this.parentId,
        turnIndex: turnIndex ?? this.turnIndex,
      );
}

// ─── Session Summary ───

/// Summarized view of a session for listing.
class SessionSummary {
  final String id;
  final String? title;
  final DateTime startedAt;
  final DateTime lastActiveAt;
  final int messageCount;
  final int toolUseCount;
  final int totalInputTokens;
  final int totalOutputTokens;
  final double totalCost;
  final String model;
  final String? gitBranch;
  final String? workingDirectory;
  final List<String> toolsUsed;
  final bool isActive;
  final String? preview; // first user message snippet

  const SessionSummary({
    required this.id,
    this.title,
    required this.startedAt,
    required this.lastActiveAt,
    required this.messageCount,
    this.toolUseCount = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCost = 0.0,
    required this.model,
    this.gitBranch,
    this.workingDirectory,
    this.toolsUsed = const [],
    this.isActive = false,
    this.preview,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title != null) 'title': title,
        'startedAt': startedAt.toIso8601String(),
        'lastActiveAt': lastActiveAt.toIso8601String(),
        'messageCount': messageCount,
        'toolUseCount': toolUseCount,
        'totalInputTokens': totalInputTokens,
        'totalOutputTokens': totalOutputTokens,
        'totalCost': totalCost,
        'model': model,
        if (gitBranch != null) 'gitBranch': gitBranch,
        if (workingDirectory != null) 'workingDirectory': workingDirectory,
        'toolsUsed': toolsUsed,
        'isActive': isActive,
        if (preview != null) 'preview': preview,
      };

  factory SessionSummary.fromJson(Map<String, dynamic> json) =>
      SessionSummary(
        id: json['id'] as String,
        title: json['title'] as String?,
        startedAt: DateTime.parse(json['startedAt'] as String),
        lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
        messageCount: json['messageCount'] as int? ?? 0,
        toolUseCount: json['toolUseCount'] as int? ?? 0,
        totalInputTokens: json['totalInputTokens'] as int? ?? 0,
        totalOutputTokens: json['totalOutputTokens'] as int? ?? 0,
        totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
        model: json['model'] as String? ?? 'unknown',
        gitBranch: json['gitBranch'] as String?,
        workingDirectory: json['workingDirectory'] as String?,
        toolsUsed: (json['toolsUsed'] as List<dynamic>?)
                ?.cast<String>()
                .toList() ??
            [],
        isActive: json['isActive'] as bool? ?? false,
        preview: json['preview'] as String?,
      );
}

// ─── Search ───

/// History search query.
class HistorySearchQuery {
  final String? text;
  final String? sessionId;
  final Set<HistoryEntryType>? types;
  final Set<String>? roles;
  final String? toolName;
  final DateTime? after;
  final DateTime? before;
  final int? minTokens;
  final int? maxTokens;
  final int limit;
  final int offset;
  final bool sortDescending;

  const HistorySearchQuery({
    this.text,
    this.sessionId,
    this.types,
    this.roles,
    this.toolName,
    this.after,
    this.before,
    this.minTokens,
    this.maxTokens,
    this.limit = 50,
    this.offset = 0,
    this.sortDescending = true,
  });
}

/// History search result.
class HistorySearchResult {
  final List<HistoryEntry> entries;
  final int totalCount;
  final Duration searchDuration;
  final bool hasMore;

  const HistorySearchResult({
    required this.entries,
    required this.totalCount,
    required this.searchDuration,
    required this.hasMore,
  });
}

// ─── Analytics ───

/// Usage analytics for a time period.
class UsageAnalytics {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int totalSessions;
  final int totalMessages;
  final int totalToolUses;
  final int totalInputTokens;
  final int totalOutputTokens;
  final int totalCacheReadTokens;
  final double totalCost;
  final Duration totalSessionTime;
  final Map<String, int> toolUsageCounts;
  final Map<String, int> modelUsageCounts;
  final Map<String, int> commandUsageCounts;
  final double averageTokensPerMessage;
  final double averageCostPerSession;
  final Duration averageSessionDuration;
  final int peakConcurrentAgents;
  final List<DailyUsage> dailyBreakdown;

  const UsageAnalytics({
    required this.periodStart,
    required this.periodEnd,
    this.totalSessions = 0,
    this.totalMessages = 0,
    this.totalToolUses = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCacheReadTokens = 0,
    this.totalCost = 0.0,
    this.totalSessionTime = Duration.zero,
    this.toolUsageCounts = const {},
    this.modelUsageCounts = const {},
    this.commandUsageCounts = const {},
    this.averageTokensPerMessage = 0.0,
    this.averageCostPerSession = 0.0,
    this.averageSessionDuration = Duration.zero,
    this.peakConcurrentAgents = 0,
    this.dailyBreakdown = const [],
  });

  Map<String, dynamic> toJson() => {
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'totalSessions': totalSessions,
        'totalMessages': totalMessages,
        'totalToolUses': totalToolUses,
        'totalInputTokens': totalInputTokens,
        'totalOutputTokens': totalOutputTokens,
        'totalCacheReadTokens': totalCacheReadTokens,
        'totalCost': totalCost,
        'totalSessionTimeMs': totalSessionTime.inMilliseconds,
        'toolUsageCounts': toolUsageCounts,
        'modelUsageCounts': modelUsageCounts,
        'commandUsageCounts': commandUsageCounts,
        'averageTokensPerMessage': averageTokensPerMessage,
        'averageCostPerSession': averageCostPerSession,
        'averageSessionDurationMs': averageSessionDuration.inMilliseconds,
        'peakConcurrentAgents': peakConcurrentAgents,
      };
}

/// Single day usage breakdown.
class DailyUsage {
  final DateTime date;
  final int sessions;
  final int messages;
  final int tokens;
  final double cost;

  const DailyUsage({
    required this.date,
    this.sessions = 0,
    this.messages = 0,
    this.tokens = 0,
    this.cost = 0.0,
  });
}

// ─── Replay ───

/// Replay state for stepping through history.
class ReplayState {
  final String sessionId;
  final List<HistoryEntry> entries;
  final int currentIndex;
  final bool isPlaying;
  final Duration playbackSpeed;

  const ReplayState({
    required this.sessionId,
    required this.entries,
    this.currentIndex = 0,
    this.isPlaying = false,
    this.playbackSpeed = const Duration(milliseconds: 500),
  });

  bool get isAtStart => currentIndex <= 0;
  bool get isAtEnd => currentIndex >= entries.length - 1;
  HistoryEntry? get currentEntry =>
      currentIndex < entries.length ? entries[currentIndex] : null;
  double get progress =>
      entries.isEmpty ? 0 : currentIndex / (entries.length - 1);

  ReplayState copyWith({
    int? currentIndex,
    bool? isPlaying,
    Duration? playbackSpeed,
  }) =>
      ReplayState(
        sessionId: sessionId,
        entries: entries,
        currentIndex: currentIndex ?? this.currentIndex,
        isPlaying: isPlaying ?? this.isPlaying,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      );
}

// ─── History Service ───

/// Service for managing conversation history, search, and analytics.
class HistoryService {
  final String _baseDir;
  final Map<String, List<HistoryEntry>> _sessionCache = {};
  final Map<String, SessionSummary> _summaryCache = {};
  final StreamController<HistoryEntry> _entryStream =
      StreamController<HistoryEntry>.broadcast();
  final StreamController<SessionSummary> _sessionStream =
      StreamController<SessionSummary>.broadcast();
  Timer? _flushTimer;
  final List<HistoryEntry> _pendingWrites = [];
  int _idCounter = 0;
  bool _initialized = false;

  HistoryService({String? baseDir})
      : _baseDir = baseDir ?? _defaultBaseDir();

  static String _defaultBaseDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '$home/.claw/history';
  }

  /// Entry stream for new entries.
  Stream<HistoryEntry> get entryStream => _entryStream.stream;

  /// Session update stream.
  Stream<SessionSummary> get sessionStream => _sessionStream.stream;

  // ─── Initialization ───

  /// Initialize history service and create directories.
  Future<void> initialize() async {
    if (_initialized) return;

    final dir = Directory(_baseDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // Start periodic flush (every 5 seconds).
    _flushTimer = Timer.periodic(const Duration(seconds: 5), (_) => flush());

    // Load session summaries index.
    await _loadSummaryIndex();
    _initialized = true;
  }

  /// Flush pending writes to disk.
  Future<void> flush() async {
    if (_pendingWrites.isEmpty) return;

    final toWrite = List<HistoryEntry>.from(_pendingWrites);
    _pendingWrites.clear();

    // Group by session.
    final bySession = <String, List<HistoryEntry>>{};
    for (final entry in toWrite) {
      bySession.putIfAbsent(entry.sessionId, () => []).add(entry);
    }

    // Append to session files.
    for (final entry in bySession.entries) {
      final file = File('$_baseDir/${entry.key}.jsonl');
      final lines =
          entry.value.map((e) => jsonEncode(e.toJson())).join('\n');
      await file.writeAsString('$lines\n', mode: FileMode.append);
    }
  }

  // ─── Write ───

  /// Generate a unique entry ID.
  String _nextId() {
    _idCounter++;
    return 'h_${DateTime.now().millisecondsSinceEpoch}_$_idCounter';
  }

  /// Record a new history entry.
  Future<HistoryEntry> record({
    required String sessionId,
    required HistoryEntryType type,
    required String role,
    required String content,
    Map<String, dynamic>? metadata,
    String? toolName,
    String? toolId,
    int? tokenCount,
    double? cost,
    Duration? latency,
    String? parentId,
    int turnIndex = 0,
  }) async {
    final entry = HistoryEntry(
      id: _nextId(),
      sessionId: sessionId,
      type: type,
      timestamp: DateTime.now(),
      role: role,
      content: content,
      metadata: metadata,
      toolName: toolName,
      toolId: toolId,
      tokenCount: tokenCount,
      cost: cost,
      latency: latency,
      parentId: parentId,
      turnIndex: turnIndex,
    );

    // Update cache.
    _sessionCache.putIfAbsent(sessionId, () => []).add(entry);

    // Queue for disk write.
    _pendingWrites.add(entry);

    // Notify listeners.
    _entryStream.add(entry);

    // Update session summary.
    _updateSummary(entry);

    return entry;
  }

  /// Record a user message.
  Future<HistoryEntry> recordUserMessage(
    String sessionId,
    String content, {
    int turnIndex = 0,
  }) =>
      record(
        sessionId: sessionId,
        type: HistoryEntryType.message,
        role: 'user',
        content: content,
        turnIndex: turnIndex,
      );

  /// Record an assistant message.
  Future<HistoryEntry> recordAssistantMessage(
    String sessionId,
    String content, {
    int? tokenCount,
    double? cost,
    Duration? latency,
    int turnIndex = 0,
  }) =>
      record(
        sessionId: sessionId,
        type: HistoryEntryType.message,
        role: 'assistant',
        content: content,
        tokenCount: tokenCount,
        cost: cost,
        latency: latency,
        turnIndex: turnIndex,
      );

  /// Record a tool use.
  Future<HistoryEntry> recordToolUse(
    String sessionId, {
    required String toolName,
    required String toolId,
    required Map<String, dynamic> input,
    int turnIndex = 0,
  }) =>
      record(
        sessionId: sessionId,
        type: HistoryEntryType.toolUse,
        role: 'assistant',
        content: jsonEncode(input),
        toolName: toolName,
        toolId: toolId,
        turnIndex: turnIndex,
      );

  /// Record a tool result.
  Future<HistoryEntry> recordToolResult(
    String sessionId, {
    required String toolId,
    required String toolName,
    required String output,
    bool isError = false,
    Duration? latency,
    int turnIndex = 0,
  }) =>
      record(
        sessionId: sessionId,
        type: HistoryEntryType.toolResult,
        role: 'tool',
        content: output,
        toolName: toolName,
        toolId: toolId,
        latency: latency,
        metadata: isError ? {'isError': true} : null,
        turnIndex: turnIndex,
      );

  /// Record a slash command execution.
  Future<HistoryEntry> recordCommand(
    String sessionId, {
    required String commandName,
    required String args,
    required String result,
    int turnIndex = 0,
  }) =>
      record(
        sessionId: sessionId,
        type: HistoryEntryType.command,
        role: 'system',
        content: result,
        metadata: {'command': commandName, 'args': args},
        turnIndex: turnIndex,
      );

  // ─── Read ───

  /// Get all entries for a session.
  Future<List<HistoryEntry>> getSessionHistory(String sessionId) async {
    // Check cache first.
    if (_sessionCache.containsKey(sessionId)) {
      return List.unmodifiable(_sessionCache[sessionId]!);
    }

    // Load from disk.
    final file = File('$_baseDir/$sessionId.jsonl');
    if (!await file.exists()) return [];

    final lines = await file.readAsLines();
    final entries = <HistoryEntry>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        entries.add(HistoryEntry.fromJson(
          jsonDecode(line) as Map<String, dynamic>,
        ));
      } catch (_) {
        // Skip malformed entries.
      }
    }

    _sessionCache[sessionId] = entries;
    return List.unmodifiable(entries);
  }

  /// Get session summary.
  Future<SessionSummary?> getSessionSummary(String sessionId) async {
    if (_summaryCache.containsKey(sessionId)) {
      return _summaryCache[sessionId];
    }

    final entries = await getSessionHistory(sessionId);
    if (entries.isEmpty) return null;

    return _buildSummary(sessionId, entries);
  }

  /// List all sessions.
  Future<List<SessionSummary>> listSessions({
    String? searchText,
    DateTime? after,
    DateTime? before,
    int limit = 50,
    int offset = 0,
    String sortBy = 'lastActive', // 'lastActive', 'created', 'messages', 'cost'
    bool descending = true,
  }) async {
    var summaries = _summaryCache.values.toList();

    // Filter.
    if (searchText != null && searchText.isNotEmpty) {
      final query = searchText.toLowerCase();
      summaries = summaries.where((s) {
        return (s.title?.toLowerCase().contains(query) ?? false) ||
            (s.preview?.toLowerCase().contains(query) ?? false) ||
            s.toolsUsed.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    if (after != null) {
      summaries =
          summaries.where((s) => s.lastActiveAt.isAfter(after)).toList();
    }

    if (before != null) {
      summaries =
          summaries.where((s) => s.lastActiveAt.isBefore(before)).toList();
    }

    // Sort.
    summaries.sort((a, b) {
      int cmp;
      switch (sortBy) {
        case 'created':
          cmp = a.startedAt.compareTo(b.startedAt);
        case 'messages':
          cmp = a.messageCount.compareTo(b.messageCount);
        case 'cost':
          cmp = a.totalCost.compareTo(b.totalCost);
        case 'tokens':
          cmp = (a.totalInputTokens + a.totalOutputTokens)
              .compareTo(b.totalInputTokens + b.totalOutputTokens);
        default: // 'lastActive'
          cmp = a.lastActiveAt.compareTo(b.lastActiveAt);
      }
      return descending ? -cmp : cmp;
    });

    // Paginate.
    final start = offset.clamp(0, summaries.length);
    final end = (offset + limit).clamp(0, summaries.length);
    return summaries.sublist(start, end);
  }

  // ─── Search ───

  /// Search across all history.
  Future<HistorySearchResult> search(HistorySearchQuery query) async {
    final sw = Stopwatch()..start();
    final allEntries = <HistoryEntry>[];

    if (query.sessionId != null) {
      allEntries.addAll(await getSessionHistory(query.sessionId!));
    } else {
      // Search all sessions.
      final dir = Directory(_baseDir);
      if (await dir.exists()) {
        await for (final entity in dir.list()) {
          if (entity is File && entity.path.endsWith('.jsonl')) {
            final sessionId =
                entity.uri.pathSegments.last.replaceAll('.jsonl', '');
            allEntries.addAll(await getSessionHistory(sessionId));
          }
        }
      }
    }

    // Filter.
    var filtered = allEntries.where((e) {
      if (query.types != null && !query.types!.contains(e.type)) return false;
      if (query.roles != null && !query.roles!.contains(e.role)) return false;
      if (query.toolName != null && e.toolName != query.toolName) return false;
      if (query.after != null && e.timestamp.isBefore(query.after!)) {
        return false;
      }
      if (query.before != null && e.timestamp.isAfter(query.before!)) {
        return false;
      }
      if (query.minTokens != null &&
          (e.tokenCount ?? 0) < query.minTokens!) {
        return false;
      }
      if (query.maxTokens != null &&
          (e.tokenCount ?? 0) > query.maxTokens!) {
        return false;
      }
      if (query.text != null && query.text!.isNotEmpty) {
        if (!e.content.toLowerCase().contains(query.text!.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();

    // Sort.
    filtered.sort((a, b) => query.sortDescending
        ? b.timestamp.compareTo(a.timestamp)
        : a.timestamp.compareTo(b.timestamp));

    sw.stop();

    final total = filtered.length;
    final start = query.offset.clamp(0, total);
    final end = (query.offset + query.limit).clamp(0, total);
    final page = filtered.sublist(start, end);

    return HistorySearchResult(
      entries: page,
      totalCount: total,
      searchDuration: sw.elapsed,
      hasMore: end < total,
    );
  }

  // ─── Analytics ───

  /// Compute usage analytics for a time period.
  Future<UsageAnalytics> getAnalytics({
    required DateTime start,
    required DateTime end,
  }) async {
    final allEntries = <HistoryEntry>[];
    final sessionIds = <String>{};

    // Load all sessions in range.
    final dir = Directory(_baseDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.jsonl')) {
          final sid =
              entity.uri.pathSegments.last.replaceAll('.jsonl', '');
          final entries = await getSessionHistory(sid);
          final inRange = entries.where(
            (e) => e.timestamp.isAfter(start) && e.timestamp.isBefore(end),
          );
          if (inRange.isNotEmpty) {
            allEntries.addAll(inRange);
            sessionIds.add(sid);
          }
        }
      }
    }

    // Compute metrics.
    final toolCounts = <String, int>{};
    final modelCounts = <String, int>{};
    final commandCounts = <String, int>{};
    int totalInput = 0;
    int totalOutput = 0;
    double totalCost = 0;
    int messages = 0;
    int toolUses = 0;

    for (final e in allEntries) {
      if (e.type == HistoryEntryType.message) messages++;
      if (e.type == HistoryEntryType.toolUse) {
        toolUses++;
        if (e.toolName != null) {
          toolCounts[e.toolName!] = (toolCounts[e.toolName!] ?? 0) + 1;
        }
      }
      if (e.type == HistoryEntryType.command) {
        final cmd = e.metadata?['command'] as String?;
        if (cmd != null) {
          commandCounts[cmd] = (commandCounts[cmd] ?? 0) + 1;
        }
      }
      totalInput += e.tokenCount ?? 0;
      totalCost += e.cost ?? 0;
    }

    // Daily breakdown.
    final dailyMap = <String, DailyUsage>{};
    for (final e in allEntries) {
      final dayKey =
          '${e.timestamp.year}-${e.timestamp.month.toString().padLeft(2, '0')}-${e.timestamp.day.toString().padLeft(2, '0')}';
      final existing = dailyMap[dayKey];
      dailyMap[dayKey] = DailyUsage(
        date: DateTime(e.timestamp.year, e.timestamp.month, e.timestamp.day),
        sessions: existing?.sessions ?? 0,
        messages: (existing?.messages ?? 0) +
            (e.type == HistoryEntryType.message ? 1 : 0),
        tokens: (existing?.tokens ?? 0) + (e.tokenCount ?? 0),
        cost: (existing?.cost ?? 0) + (e.cost ?? 0),
      );
    }

    return UsageAnalytics(
      periodStart: start,
      periodEnd: end,
      totalSessions: sessionIds.length,
      totalMessages: messages,
      totalToolUses: toolUses,
      totalInputTokens: totalInput,
      totalOutputTokens: totalOutput,
      totalCost: totalCost,
      toolUsageCounts: toolCounts,
      modelUsageCounts: modelCounts,
      commandUsageCounts: commandCounts,
      averageTokensPerMessage:
          messages > 0 ? totalInput / messages : 0,
      averageCostPerSession:
          sessionIds.isNotEmpty ? totalCost / sessionIds.length : 0,
      dailyBreakdown: dailyMap.values.toList()
        ..sort((a, b) => a.date.compareTo(b.date)),
    );
  }

  // ─── Replay ───

  /// Start a replay of a session.
  Future<ReplayState> startReplay(String sessionId) async {
    final entries = await getSessionHistory(sessionId);
    return ReplayState(sessionId: sessionId, entries: entries);
  }

  /// Step forward in replay.
  ReplayState replayNext(ReplayState state) {
    if (state.isAtEnd) return state;
    return state.copyWith(currentIndex: state.currentIndex + 1);
  }

  /// Step backward in replay.
  ReplayState replayPrevious(ReplayState state) {
    if (state.isAtStart) return state;
    return state.copyWith(currentIndex: state.currentIndex - 1);
  }

  /// Jump to a specific point in replay.
  ReplayState replayJumpTo(ReplayState state, int index) {
    return state.copyWith(
      currentIndex: index.clamp(0, state.entries.length - 1),
    );
  }

  /// Get entries up to current replay point (for rendering).
  List<HistoryEntry> replayVisibleEntries(ReplayState state) {
    return state.entries.sublist(0, state.currentIndex + 1);
  }

  // ─── Session Management ───

  /// Delete a session's history.
  Future<void> deleteSession(String sessionId) async {
    _sessionCache.remove(sessionId);
    _summaryCache.remove(sessionId);

    final file = File('$_baseDir/$sessionId.jsonl');
    if (await file.exists()) {
      await file.delete();
    }

    await _saveSummaryIndex();
  }

  /// Fork a session from a specific point.
  Future<String> forkSession(
    String sessionId, {
    required int fromTurnIndex,
  }) async {
    final entries = await getSessionHistory(sessionId);
    final forked =
        entries.where((e) => e.turnIndex <= fromTurnIndex).toList();

    final newId =
        'fork_${DateTime.now().millisecondsSinceEpoch}';

    // Write forked entries.
    for (final entry in forked) {
      await record(
        sessionId: newId,
        type: entry.type,
        role: entry.role,
        content: entry.content,
        metadata: {
          ...?entry.metadata,
          'forkedFrom': sessionId,
          'forkPoint': fromTurnIndex,
        },
        toolName: entry.toolName,
        toolId: entry.toolId,
        tokenCount: entry.tokenCount,
        cost: entry.cost,
        latency: entry.latency,
        turnIndex: entry.turnIndex,
      );
    }

    return newId;
  }

  /// Export a session's history.
  Future<String> exportSession(
    String sessionId, {
    String format = 'markdown', // 'markdown', 'json', 'text'
  }) async {
    final entries = await getSessionHistory(sessionId);

    switch (format) {
      case 'json':
        return jsonEncode(entries.map((e) => e.toJson()).toList());

      case 'text':
        final buffer = StringBuffer();
        for (final e in entries) {
          buffer.writeln('[${e.timestamp}] ${e.role}: ${e.content}');
          buffer.writeln();
        }
        return buffer.toString();

      case 'markdown':
      default:
        final buffer = StringBuffer();
        buffer.writeln('# Session: $sessionId');
        buffer.writeln();

        for (final e in entries) {
          if (e.type == HistoryEntryType.message) {
            if (e.role == 'user') {
              buffer.writeln('## User');
              buffer.writeln(e.content);
            } else if (e.role == 'assistant') {
              buffer.writeln('## Assistant');
              buffer.writeln(e.content);
            }
          } else if (e.type == HistoryEntryType.toolUse) {
            buffer.writeln('### Tool: ${e.toolName}');
            buffer.writeln('```json');
            buffer.writeln(e.content);
            buffer.writeln('```');
          } else if (e.type == HistoryEntryType.toolResult) {
            buffer.writeln('#### Result');
            buffer.writeln('```');
            buffer.writeln(
                e.content.length > 500
                    ? '${e.content.substring(0, 500)}...'
                    : e.content);
            buffer.writeln('```');
          }
          buffer.writeln();
        }

        return buffer.toString();
    }
  }

  /// Compact old session history files (entries older than retention period).
  Future<int> compactHistory({
    Duration retention = const Duration(days: 90),
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    int deleted = 0;

    final dir = Directory(_baseDir);
    if (!await dir.exists()) return 0;

    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete();
          final sid =
              entity.uri.pathSegments.last.replaceAll('.jsonl', '');
          _sessionCache.remove(sid);
          _summaryCache.remove(sid);
          deleted++;
        }
      }
    }

    if (deleted > 0) await _saveSummaryIndex();
    return deleted;
  }

  // ─── Internal Helpers ───

  void _updateSummary(HistoryEntry entry) {
    final sid = entry.sessionId;
    final existing = _summaryCache[sid];

    final toolsUsed = existing?.toolsUsed.toList() ?? [];
    if (entry.toolName != null && !toolsUsed.contains(entry.toolName)) {
      toolsUsed.add(entry.toolName!);
    }

    _summaryCache[sid] = SessionSummary(
      id: sid,
      title: existing?.title,
      startedAt: existing?.startedAt ?? entry.timestamp,
      lastActiveAt: entry.timestamp,
      messageCount: (existing?.messageCount ?? 0) +
          (entry.type == HistoryEntryType.message ? 1 : 0),
      toolUseCount: (existing?.toolUseCount ?? 0) +
          (entry.type == HistoryEntryType.toolUse ? 1 : 0),
      totalInputTokens:
          (existing?.totalInputTokens ?? 0) + (entry.tokenCount ?? 0),
      totalCost: (existing?.totalCost ?? 0) + (entry.cost ?? 0),
      model: existing?.model ?? 'unknown',
      toolsUsed: toolsUsed,
      isActive: true,
      preview: existing?.preview ??
          (entry.role == 'user' && entry.type == HistoryEntryType.message
              ? (entry.content.length > 100
                  ? '${entry.content.substring(0, 100)}...'
                  : entry.content)
              : null),
    );

    _sessionStream.add(_summaryCache[sid]!);
  }

  SessionSummary _buildSummary(
      String sessionId, List<HistoryEntry> entries) {
    final toolsUsed = <String>{};
    int messages = 0;
    int toolUses = 0;
    int tokens = 0;
    double cost = 0;
    String? preview;

    for (final e in entries) {
      if (e.type == HistoryEntryType.message) messages++;
      if (e.type == HistoryEntryType.toolUse) {
        toolUses++;
        if (e.toolName != null) toolsUsed.add(e.toolName!);
      }
      tokens += e.tokenCount ?? 0;
      cost += e.cost ?? 0;

      if (preview == null &&
          e.role == 'user' &&
          e.type == HistoryEntryType.message) {
        preview = e.content.length > 100
            ? '${e.content.substring(0, 100)}...'
            : e.content;
      }
    }

    return SessionSummary(
      id: sessionId,
      startedAt: entries.first.timestamp,
      lastActiveAt: entries.last.timestamp,
      messageCount: messages,
      toolUseCount: toolUses,
      totalInputTokens: tokens,
      totalCost: cost,
      model: 'unknown',
      toolsUsed: toolsUsed.toList(),
      preview: preview,
    );
  }

  Future<void> _loadSummaryIndex() async {
    final indexFile = File('$_baseDir/_index.json');
    if (!await indexFile.exists()) return;

    try {
      final content = await indexFile.readAsString();
      final list = jsonDecode(content) as List<dynamic>;
      for (final item in list) {
        final summary =
            SessionSummary.fromJson(item as Map<String, dynamic>);
        _summaryCache[summary.id] = summary;
      }
    } catch (_) {
      // Rebuild index from files if corrupt.
    }
  }

  Future<void> _saveSummaryIndex() async {
    final indexFile = File('$_baseDir/_index.json');
    final data = _summaryCache.values.map((s) => s.toJson()).toList();
    await indexFile.writeAsString(jsonEncode(data));
  }

  /// Dispose resources.
  void dispose() {
    _flushTimer?.cancel();
    flush(); // Final flush.
    _entryStream.close();
    _sessionStream.close();
  }
}
