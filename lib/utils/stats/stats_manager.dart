/// Statistics tracking and caching for NeomClaw sessions.
///
/// Ported from:
///   - openneomclaw/src/utils/stats.ts (1061 LOC)
///   - openneomclaw/src/utils/statsCache.ts (434 LOC)
///
/// Provides aggregation of session statistics, daily activity tracking,
/// streak calculations, model usage tracking, and a disk-persisted cache
/// to avoid reprocessing historical data.

import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const int statsCacheVersion = 3;
const int _minMigratableVersion = 1;
const String _statsCacheFilename = 'stats-cache.json';
const int _batchSize = 20;

/// Regex for extracting shot counts from PR attribution text.
/// The attribution format is: "N-shotted by model-name"
final RegExp _shotCountRegex = RegExp(r'(\d+)-shotted by');

/// Transcript message types that match isTranscriptMessage() in sessionStorage.
const Set<String> _transcriptMessageTypes = {
  'user',
  'assistant',
  'attachment',
  'system',
  'progress',
};

// Synthetic model marker — internal messages that shouldn't appear in stats.
const String syntheticModel = '__synthetic__';

// ---------------------------------------------------------------------------
// Types — DailyActivity
// ---------------------------------------------------------------------------

/// Daily activity aggregate for heatmap / trend display.
class DailyActivity {
  DailyActivity({
    required this.date,
    this.messageCount = 0,
    this.sessionCount = 0,
    this.toolCallCount = 0,
  });

  /// Date in YYYY-MM-DD format.
  final String date;
  int messageCount;
  int sessionCount;
  int toolCallCount;

  DailyActivity copyWith({
    String? date,
    int? messageCount,
    int? sessionCount,
    int? toolCallCount,
  }) {
    return DailyActivity(
      date: date ?? this.date,
      messageCount: messageCount ?? this.messageCount,
      sessionCount: sessionCount ?? this.sessionCount,
      toolCallCount: toolCallCount ?? this.toolCallCount,
    );
  }

  factory DailyActivity.fromJson(Map<String, dynamic> json) {
    return DailyActivity(
      date: json['date'] as String,
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      sessionCount: (json['sessionCount'] as num?)?.toInt() ?? 0,
      toolCallCount: (json['toolCallCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'messageCount': messageCount,
        'sessionCount': sessionCount,
        'toolCallCount': toolCallCount,
      };
}

// ---------------------------------------------------------------------------
// Types — DailyModelTokens
// ---------------------------------------------------------------------------

/// Daily token usage per model for charts.
class DailyModelTokens {
  DailyModelTokens({
    required this.date,
    Map<String, int>? tokensByModel,
  }) : tokensByModel = tokensByModel ?? {};

  /// Date in YYYY-MM-DD format.
  final String date;

  /// Total tokens (input + output) per model name.
  final Map<String, int> tokensByModel;

  factory DailyModelTokens.fromJson(Map<String, dynamic> json) {
    final raw = json['tokensByModel'] as Map<String, dynamic>? ?? {};
    return DailyModelTokens(
      date: json['date'] as String,
      tokensByModel:
          raw.map((k, v) => MapEntry(k, (v as num).toInt())),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': date,
        'tokensByModel': tokensByModel,
      };
}

// ---------------------------------------------------------------------------
// Types — StreakInfo
// ---------------------------------------------------------------------------

/// Streak calculation results.
class StreakInfo {
  const StreakInfo({
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.currentStreakStart,
    this.longestStreakStart,
    this.longestStreakEnd,
  });

  final int currentStreak;
  final int longestStreak;
  final String? currentStreakStart;
  final String? longestStreakStart;
  final String? longestStreakEnd;

  Map<String, dynamic> toJson() => {
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'currentStreakStart': currentStreakStart,
        'longestStreakStart': longestStreakStart,
        'longestStreakEnd': longestStreakEnd,
      };
}

// ---------------------------------------------------------------------------
// Types — SessionStats
// ---------------------------------------------------------------------------

/// Per-session aggregate.
class SessionStats {
  const SessionStats({
    required this.sessionId,
    required this.duration,
    required this.messageCount,
    required this.timestamp,
  });

  final String sessionId;

  /// Duration in milliseconds.
  final int duration;
  final int messageCount;
  final String timestamp;

  factory SessionStats.fromJson(Map<String, dynamic> json) {
    return SessionStats(
      sessionId: json['sessionId'] as String,
      duration: (json['duration'] as num).toInt(),
      messageCount: (json['messageCount'] as num).toInt(),
      timestamp: json['timestamp'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'duration': duration,
        'messageCount': messageCount,
        'timestamp': timestamp,
      };
}

// ---------------------------------------------------------------------------
// Types — ModelUsage
// ---------------------------------------------------------------------------

/// Aggregated model usage.
class ModelUsage {
  ModelUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadInputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.webSearchRequests = 0,
    this.costUSD = 0.0,
    this.contextWindow = 0,
    this.maxOutputTokens = 0,
  });

  int inputTokens;
  int outputTokens;
  int cacheReadInputTokens;
  int cacheCreationInputTokens;
  int webSearchRequests;
  double costUSD;
  int contextWindow;
  int maxOutputTokens;

  factory ModelUsage.fromJson(Map<String, dynamic> json) {
    return ModelUsage(
      inputTokens: (json['inputTokens'] as num?)?.toInt() ?? 0,
      outputTokens: (json['outputTokens'] as num?)?.toInt() ?? 0,
      cacheReadInputTokens:
          (json['cacheReadInputTokens'] as num?)?.toInt() ?? 0,
      cacheCreationInputTokens:
          (json['cacheCreationInputTokens'] as num?)?.toInt() ?? 0,
      webSearchRequests:
          (json['webSearchRequests'] as num?)?.toInt() ?? 0,
      costUSD: (json['costUSD'] as num?)?.toDouble() ?? 0.0,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 0,
      maxOutputTokens: (json['maxOutputTokens'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'cacheReadInputTokens': cacheReadInputTokens,
        'cacheCreationInputTokens': cacheCreationInputTokens,
        'webSearchRequests': webSearchRequests,
        'costUSD': costUSD,
        'contextWindow': contextWindow,
        'maxOutputTokens': maxOutputTokens,
      };

  /// Merge another [ModelUsage] into this one (additive).
  ModelUsage merge(ModelUsage other) {
    return ModelUsage(
      inputTokens: inputTokens + other.inputTokens,
      outputTokens: outputTokens + other.outputTokens,
      cacheReadInputTokens:
          cacheReadInputTokens + other.cacheReadInputTokens,
      cacheCreationInputTokens:
          cacheCreationInputTokens + other.cacheCreationInputTokens,
      webSearchRequests: webSearchRequests + other.webSearchRequests,
      costUSD: costUSD + other.costUSD,
      contextWindow: max(contextWindow, other.contextWindow),
      maxOutputTokens: max(maxOutputTokens, other.maxOutputTokens),
    );
  }
}

// ---------------------------------------------------------------------------
// Types — NeomClawStats (final aggregated output)
// ---------------------------------------------------------------------------

/// Complete aggregated stats returned by [aggregateNeomClawStats].
class NeomClawStats {
  NeomClawStats({
    this.totalSessions = 0,
    this.totalMessages = 0,
    this.totalDays = 0,
    this.activeDays = 0,
    this.streaks = const StreakInfo(),
    this.dailyActivity = const [],
    this.dailyModelTokens = const [],
    this.longestSession,
    this.modelUsage = const {},
    this.firstSessionDate,
    this.lastSessionDate,
    this.peakActivityDay,
    this.peakActivityHour,
    this.totalSpeculationTimeSavedMs = 0,
    this.shotDistribution,
    this.oneShotRate,
  });

  final int totalSessions;
  final int totalMessages;
  final int totalDays;
  final int activeDays;
  final StreakInfo streaks;
  final List<DailyActivity> dailyActivity;
  final List<DailyModelTokens> dailyModelTokens;
  final SessionStats? longestSession;
  final Map<String, ModelUsage> modelUsage;
  final String? firstSessionDate;
  final String? lastSessionDate;
  final String? peakActivityDay;
  final int? peakActivityHour;
  final int totalSpeculationTimeSavedMs;

  /// Shot distribution: map of shot count -> number of sessions (ant-only).
  final Map<int, int>? shotDistribution;
  final int? oneShotRate;
}

// ---------------------------------------------------------------------------
// Types — ProcessedStats (intermediate)
// ---------------------------------------------------------------------------

/// Result of processing session files — intermediate stats that can be merged.
class ProcessedStats {
  ProcessedStats({
    this.dailyActivity = const [],
    this.dailyModelTokens = const [],
    this.modelUsage = const {},
    this.sessionStats = const [],
    this.hourCounts = const {},
    this.totalMessages = 0,
    this.totalSpeculationTimeSavedMs = 0,
    this.shotDistribution,
  });

  final List<DailyActivity> dailyActivity;
  final List<DailyModelTokens> dailyModelTokens;
  final Map<String, ModelUsage> modelUsage;
  final List<SessionStats> sessionStats;
  final Map<int, int> hourCounts;
  final int totalMessages;
  final int totalSpeculationTimeSavedMs;
  final Map<int, int>? shotDistribution;
}

// ---------------------------------------------------------------------------
// Types — ProcessOptions
// ---------------------------------------------------------------------------

/// Options for processing session files.
class ProcessOptions {
  const ProcessOptions({this.fromDate, this.toDate});

  /// Only include data from dates >= this date (YYYY-MM-DD format).
  final String? fromDate;

  /// Only include data from dates <= this date (YYYY-MM-DD format).
  final String? toDate;
}

// ---------------------------------------------------------------------------
// Types — PersistedStatsCache
// ---------------------------------------------------------------------------

/// Persisted stats cache stored on disk.
/// Contains aggregated historical stats that won't change.
/// All fields are bounded to prevent unbounded file growth.
class PersistedStatsCache {
  PersistedStatsCache({
    this.version = statsCacheVersion,
    this.lastComputedDate,
    this.dailyActivity = const [],
    this.dailyModelTokens = const [],
    this.modelUsage = const {},
    this.totalSessions = 0,
    this.totalMessages = 0,
    this.longestSession,
    this.firstSessionDate,
    this.hourCounts = const {},
    this.totalSpeculationTimeSavedMs = 0,
    this.shotDistribution,
  });

  final int version;

  /// Last date that was fully computed (YYYY-MM-DD format).
  /// Stats up to and including this date are considered complete.
  final String? lastComputedDate;

  /// Daily aggregates needed for heatmap, streaks, trends (bounded by days).
  final List<DailyActivity> dailyActivity;
  final List<DailyModelTokens> dailyModelTokens;

  /// Model usage aggregated (bounded by number of models).
  final Map<String, ModelUsage> modelUsage;

  /// Session aggregates (replaces unbounded sessionStats array).
  final int totalSessions;
  final int totalMessages;
  final SessionStats? longestSession;

  /// First session date ever recorded.
  final String? firstSessionDate;

  /// Hour counts for peak hour calculation (bounded to 24 entries).
  final Map<int, int> hourCounts;

  /// Speculation time saved across all sessions.
  final int totalSpeculationTimeSavedMs;

  /// Shot distribution: map of shot count -> number of sessions (ant-only).
  final Map<int, int>? shotDistribution;

  factory PersistedStatsCache.fromJson(Map<String, dynamic> json) {
    return PersistedStatsCache(
      version: (json['version'] as num?)?.toInt() ?? 0,
      lastComputedDate: json['lastComputedDate'] as String?,
      dailyActivity: (json['dailyActivity'] as List<dynamic>?)
              ?.map((e) => DailyActivity.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dailyModelTokens: (json['dailyModelTokens'] as List<dynamic>?)
              ?.map(
                  (e) => DailyModelTokens.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      modelUsage: (json['modelUsage'] as Map<String, dynamic>?)?.map(
              (k, v) =>
                  MapEntry(k, ModelUsage.fromJson(v as Map<String, dynamic>))) ??
          {},
      totalSessions: (json['totalSessions'] as num?)?.toInt() ?? 0,
      totalMessages: (json['totalMessages'] as num?)?.toInt() ?? 0,
      longestSession: json['longestSession'] != null
          ? SessionStats.fromJson(
              json['longestSession'] as Map<String, dynamic>)
          : null,
      firstSessionDate: json['firstSessionDate'] as String?,
      hourCounts: (json['hourCounts'] as Map<String, dynamic>?)?.map(
              (k, v) => MapEntry(int.parse(k), (v as num).toInt())) ??
          {},
      totalSpeculationTimeSavedMs:
          (json['totalSpeculationTimeSavedMs'] as num?)?.toInt() ?? 0,
      shotDistribution: (json['shotDistribution'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(int.parse(k), (v as num).toInt())),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'lastComputedDate': lastComputedDate,
        'dailyActivity': dailyActivity.map((e) => e.toJson()).toList(),
        'dailyModelTokens':
            dailyModelTokens.map((e) => e.toJson()).toList(),
        'modelUsage':
            modelUsage.map((k, v) => MapEntry(k, v.toJson())),
        'totalSessions': totalSessions,
        'totalMessages': totalMessages,
        'longestSession': longestSession?.toJson(),
        'firstSessionDate': firstSessionDate,
        'hourCounts':
            hourCounts.map((k, v) => MapEntry(k.toString(), v)),
        'totalSpeculationTimeSavedMs': totalSpeculationTimeSavedMs,
        if (shotDistribution != null)
          'shotDistribution':
              shotDistribution!.map((k, v) => MapEntry(k.toString(), v)),
      };

  PersistedStatsCache copyWith({
    int? version,
    String? lastComputedDate,
    List<DailyActivity>? dailyActivity,
    List<DailyModelTokens>? dailyModelTokens,
    Map<String, ModelUsage>? modelUsage,
    int? totalSessions,
    int? totalMessages,
    SessionStats? longestSession,
    String? firstSessionDate,
    Map<int, int>? hourCounts,
    int? totalSpeculationTimeSavedMs,
    Map<int, int>? shotDistribution,
  }) {
    return PersistedStatsCache(
      version: version ?? this.version,
      lastComputedDate: lastComputedDate ?? this.lastComputedDate,
      dailyActivity: dailyActivity ?? this.dailyActivity,
      dailyModelTokens: dailyModelTokens ?? this.dailyModelTokens,
      modelUsage: modelUsage ?? this.modelUsage,
      totalSessions: totalSessions ?? this.totalSessions,
      totalMessages: totalMessages ?? this.totalMessages,
      longestSession: longestSession ?? this.longestSession,
      firstSessionDate: firstSessionDate ?? this.firstSessionDate,
      hourCounts: hourCounts ?? this.hourCounts,
      totalSpeculationTimeSavedMs:
          totalSpeculationTimeSavedMs ?? this.totalSpeculationTimeSavedMs,
      shotDistribution: shotDistribution ?? this.shotDistribution,
    );
  }
}

// ---------------------------------------------------------------------------
// Types — StatsDateRange
// ---------------------------------------------------------------------------

/// Range filter for stats aggregation.
enum StatsDateRange {
  sevenDays,
  thirtyDays,
  all,
}

// ---------------------------------------------------------------------------
// StatsManager — SintController
// ---------------------------------------------------------------------------

/// Manages stats collection, caching, and aggregation.
///
/// Usage:
/// ```dart
/// final manager = Sint.put(StatsManager());
/// final stats = await manager.aggregateNeomClawStats();
/// ```
class StatsManager extends SintController {
  StatsManager({
    String? configHomeDir,
    String? projectsDir,
  })  : _configHomeDir = configHomeDir ?? _defaultConfigHome(),
        _projectsDir = projectsDir;

  final String _configHomeDir;
  final String? _projectsDir;

  /// Feature flags — default to false. Override in tests or config.
  final RxBool shotStatsEnabled = false.obs;

  /// In-memory lock to prevent concurrent cache operations.
  Future<void>? _statsCacheLockFuture;

  // -------------------------------------------------------------------------
  // Date helpers
  // -------------------------------------------------------------------------

  /// Extract the date portion (YYYY-MM-DD) from a [DateTime] object.
  static String toDateString(DateTime date) {
    return date.toUtc().toIso8601String().split('T').first;
  }

  /// Get today's date in YYYY-MM-DD format.
  static String getTodayDateString() => toDateString(DateTime.now());

  /// Get yesterday's date in YYYY-MM-DD format.
  static String getYesterdayDateString() {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return toDateString(yesterday);
  }

  /// Check if [date1] is before [date2]. Both YYYY-MM-DD.
  static bool isDateBefore(String date1, String date2) {
    return date1.compareTo(date2) < 0;
  }

  /// Get the next day after [dateStr] (YYYY-MM-DD).
  static String getNextDay(String dateStr) {
    final date = DateTime.parse(dateStr);
    return toDateString(date.add(const Duration(days: 1)));
  }

  // -------------------------------------------------------------------------
  // Config / path helpers
  // -------------------------------------------------------------------------

  static String _defaultConfigHome() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return '/.neomclaw';
  }

  String getStatsCachePath() {
    return '$_configHomeDir/$_statsCacheFilename';
  }

  String _getProjectsDir() {
    return _projectsDir ?? '$_configHomeDir/projects';
  }

  // -------------------------------------------------------------------------
  // Stats cache lock
  // -------------------------------------------------------------------------

  /// Execute [fn] while holding the stats cache lock.
  /// Only one operation can hold the lock at a time.
  Future<T> withStatsCacheLock<T>(Future<T> Function() fn) async {
    // Wait for any existing lock to be released.
    while (_statsCacheLockFuture != null) {
      await _statsCacheLockFuture;
    }

    late void Function() releaseLock;
    _statsCacheLockFuture = Future<void>(() {
      // The completer is effectively resolved when releaseLock is called.
    });

    try {
      return await fn();
    } finally {
      _statsCacheLockFuture = null;
      // releaseLock is not needed in Dart's single-threaded model,
      // but we mirror the TS pattern for clarity.
    }
  }

  // -------------------------------------------------------------------------
  // Empty cache / empty stats
  // -------------------------------------------------------------------------

  PersistedStatsCache _getEmptyCache() {
    return PersistedStatsCache(
      version: statsCacheVersion,
      shotDistribution: shotStatsEnabled.value ? {} : null,
    );
  }

  NeomClawStats _getEmptyStats() {
    return NeomClawStats();
  }

  // -------------------------------------------------------------------------
  // Cache migration
  // -------------------------------------------------------------------------

  /// Migrate an older cache to the current schema.
  /// Returns null if the version is unknown or too old to migrate.
  PersistedStatsCache? _migrateStatsCache(Map<String, dynamic> parsed) {
    final version = parsed['version'];
    if (version is! int ||
        version < _minMigratableVersion ||
        version > statsCacheVersion) {
      return null;
    }
    final dailyActivity = parsed['dailyActivity'];
    final dailyModelTokens = parsed['dailyModelTokens'];
    final totalSessions = parsed['totalSessions'];
    final totalMessages = parsed['totalMessages'];

    if (dailyActivity is! List ||
        dailyModelTokens is! List ||
        totalSessions is! int ||
        totalMessages is! int) {
      return null;
    }

    final cache = PersistedStatsCache.fromJson({
      ...parsed,
      'version': statsCacheVersion,
    });
    return cache;
  }

  // -------------------------------------------------------------------------
  // Load / Save cache
  // -------------------------------------------------------------------------

  /// Load the stats cache from disk.
  /// Returns an empty cache if the file doesn't exist or is invalid.
  Future<PersistedStatsCache> loadStatsCache() async {
    final cachePath = getStatsCachePath();

    try {
      final file = File(cachePath);
      if (!await file.exists()) {
        return _getEmptyCache();
      }
      final content = await file.readAsString();
      final parsed = jsonDecode(content) as Map<String, dynamic>;

      // Validate version.
      final version = (parsed['version'] as num?)?.toInt() ?? 0;
      if (version != statsCacheVersion) {
        final migrated = _migrateStatsCache(parsed);
        if (migrated == null) {
          return _getEmptyCache();
        }
        await saveStatsCache(migrated);
        if (shotStatsEnabled.value && migrated.shotDistribution == null) {
          return _getEmptyCache();
        }
        return migrated;
      }

      final cache = PersistedStatsCache.fromJson(parsed);

      // Basic validation.
      if (cache.dailyActivity is! List ||
          cache.totalSessions < 0) {
        return _getEmptyCache();
      }

      if (shotStatsEnabled.value && cache.shotDistribution == null) {
        return _getEmptyCache();
      }

      return cache;
    } catch (_) {
      return _getEmptyCache();
    }
  }

  /// Save the stats cache to disk atomically.
  /// Uses a temp file + rename pattern to prevent corruption.
  Future<void> saveStatsCache(PersistedStatsCache cache) async {
    final cachePath = getStatsCachePath();
    final tempPath = '$cachePath.${DateTime.now().microsecondsSinceEpoch}.tmp';

    try {
      final configDir = Directory(_configHomeDir);
      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final content =
          const JsonEncoder.withIndent('  ').convert(cache.toJson());
      final tempFile = File(tempPath);
      await tempFile.writeAsString(content, flush: true);

      // Atomic rename.
      await tempFile.rename(cachePath);
    } catch (_) {
      // Clean up temp file.
      try {
        await File(tempPath).delete();
      } catch (_) {
        // Ignore cleanup errors.
      }
    }
  }

  // -------------------------------------------------------------------------
  // Merge cache
  // -------------------------------------------------------------------------

  /// Merge new stats into an existing cache.
  /// Used when incrementally adding new days to the cache.
  PersistedStatsCache mergeCacheWithNewStats({
    required PersistedStatsCache existingCache,
    required ProcessedStats newStats,
    required String newLastComputedDate,
  }) {
    // Merge daily activity — combine by date.
    final dailyActivityMap = <String, DailyActivity>{};
    for (final day in existingCache.dailyActivity) {
      dailyActivityMap[day.date] = day.copyWith();
    }
    for (final day in newStats.dailyActivity) {
      final existing = dailyActivityMap[day.date];
      if (existing != null) {
        existing.messageCount += day.messageCount;
        existing.sessionCount += day.sessionCount;
        existing.toolCallCount += day.toolCallCount;
      } else {
        dailyActivityMap[day.date] = day.copyWith();
      }
    }

    // Merge daily model tokens — combine by date.
    final dailyModelTokensMap = <String, Map<String, int>>{};
    for (final day in existingCache.dailyModelTokens) {
      dailyModelTokensMap[day.date] = Map<String, int>.from(day.tokensByModel);
    }
    for (final day in newStats.dailyModelTokens) {
      final existing = dailyModelTokensMap[day.date];
      if (existing != null) {
        for (final entry in day.tokensByModel.entries) {
          existing[entry.key] = (existing[entry.key] ?? 0) + entry.value;
        }
      } else {
        dailyModelTokensMap[day.date] =
            Map<String, int>.from(day.tokensByModel);
      }
    }

    // Merge model usage.
    final modelUsage = Map<String, ModelUsage>.from(existingCache.modelUsage);
    for (final entry in newStats.modelUsage.entries) {
      final existing = modelUsage[entry.key];
      if (existing != null) {
        modelUsage[entry.key] = existing.merge(entry.value);
      } else {
        modelUsage[entry.key] = entry.value;
      }
    }

    // Merge hour counts.
    final hourCounts = Map<int, int>.from(existingCache.hourCounts);
    for (final entry in newStats.hourCounts.entries) {
      hourCounts[entry.key] = (hourCounts[entry.key] ?? 0) + entry.value;
    }

    // Update session aggregates.
    final totalSessions =
        existingCache.totalSessions + newStats.sessionStats.length;
    final totalMessages = existingCache.totalMessages +
        newStats.sessionStats.fold<int>(0, (sum, s) => sum + s.messageCount);

    // Find longest session.
    SessionStats? longestSession = existingCache.longestSession;
    for (final session in newStats.sessionStats) {
      if (longestSession == null || session.duration > longestSession.duration) {
        longestSession = session;
      }
    }

    // Find first session date.
    String? firstSessionDate = existingCache.firstSessionDate;
    for (final session in newStats.sessionStats) {
      if (firstSessionDate == null ||
          session.timestamp.compareTo(firstSessionDate) < 0) {
        firstSessionDate = session.timestamp;
      }
    }

    final sortedDailyActivity = dailyActivityMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final sortedDailyModelTokens = dailyModelTokensMap.entries
        .map((e) => DailyModelTokens(date: e.key, tokensByModel: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    var result = PersistedStatsCache(
      version: statsCacheVersion,
      lastComputedDate: newLastComputedDate,
      dailyActivity: sortedDailyActivity,
      dailyModelTokens: sortedDailyModelTokens,
      modelUsage: modelUsage,
      totalSessions: totalSessions,
      totalMessages: totalMessages,
      longestSession: longestSession,
      firstSessionDate: firstSessionDate,
      hourCounts: hourCounts,
      totalSpeculationTimeSavedMs: existingCache.totalSpeculationTimeSavedMs +
          newStats.totalSpeculationTimeSavedMs,
    );

    if (shotStatsEnabled.value) {
      final shotDistribution = Map<int, int>.from(
          existingCache.shotDistribution ?? {});
      for (final entry in (newStats.shotDistribution ?? {}).entries) {
        shotDistribution[entry.key] =
            (shotDistribution[entry.key] ?? 0) + entry.value;
      }
      result = result.copyWith(shotDistribution: shotDistribution);
    }

    return result;
  }

  // -------------------------------------------------------------------------
  // Session file discovery
  // -------------------------------------------------------------------------

  /// Get all session files from all project directories.
  /// Includes both main session files and subagent transcript files.
  Future<List<String>> getAllSessionFiles() async {
    final projectsDir = _getProjectsDir();
    final dir = Directory(projectsDir);

    if (!await dir.exists()) return [];

    final allEntries = await dir.list().toList();
    final projectDirs = allEntries
        .whereType<Directory>()
        .map((d) => d.path)
        .toList();

    final allFiles = <String>[];

    for (final projectDir in projectDirs) {
      try {
        final entries = await Directory(projectDir).list().toList();

        // Main session files (*.jsonl directly in project dir).
        final mainFiles = entries
            .whereType<File>()
            .where((f) => f.path.endsWith('.jsonl'))
            .map((f) => f.path)
            .toList();
        allFiles.addAll(mainFiles);

        // Subagent files from session subdirectories.
        final sessionDirs = entries.whereType<Directory>();
        for (final sessionDir in sessionDirs) {
          final subagentsDir =
              Directory('${sessionDir.path}/subagents');
          if (await subagentsDir.exists()) {
            final subagentEntries = await subagentsDir.list().toList();
            final subagentFiles = subagentEntries
                .whereType<File>()
                .where((f) =>
                    f.path.endsWith('.jsonl') &&
                    f.uri.pathSegments.last.startsWith('agent-'))
                .map((f) => f.path)
                .toList();
            allFiles.addAll(subagentFiles);
          }
        }
      } catch (_) {
        // Failed to read project directory — skip.
      }
    }

    return allFiles;
  }

  // -------------------------------------------------------------------------
  // Session file processing
  // -------------------------------------------------------------------------

  /// Process session files and extract stats.
  /// Can filter by date range.
  Future<ProcessedStats> processSessionFiles(
    List<String> sessionFiles, {
    ProcessOptions options = const ProcessOptions(),
  }) async {
    final fromDate = options.fromDate;
    final toDate = options.toDate;

    final dailyActivityMap = <String, DailyActivity>{};
    final dailyModelTokensMap = <String, Map<String, int>>{};
    final sessions = <SessionStats>[];
    final hourCounts = <int, int>{};
    var totalMessages = 0;
    var totalSpeculationTimeSavedMs = 0;
    final modelUsageAgg = <String, ModelUsage>{};
    final shotDistributionMap =
        shotStatsEnabled.value ? <int, int>{} : null;
    final sessionsWithShotCount = <String>{};

    // Process session files in batches.
    for (var i = 0; i < sessionFiles.length; i += _batchSize) {
      final batch = sessionFiles.sublist(
          i, min(i + _batchSize, sessionFiles.length));

      final results = await Future.wait(batch.map((sessionFile) async {
        try {
          if (fromDate != null) {
            try {
              final fileStat = await File(sessionFile).stat();
              final fileModifiedDate = toDateString(fileStat.modified);
              if (isDateBefore(fileModifiedDate, fromDate)) {
                return _SessionReadResult(
                    sessionFile: sessionFile, skipped: true);
              }
            } catch (_) {
              // If we can't stat the file, try to read it anyway.
            }
          }

          final file = File(sessionFile);
          final content = await file.readAsString();
          final lines = content.split('\n').where((l) => l.isNotEmpty);
          final entries = <Map<String, dynamic>>[];
          for (final line in lines) {
            try {
              entries.add(jsonDecode(line) as Map<String, dynamic>);
            } catch (_) {
              // Skip malformed lines.
            }
          }
          return _SessionReadResult(
              sessionFile: sessionFile, entries: entries);
        } catch (e) {
          return _SessionReadResult(
              sessionFile: sessionFile, error: e.toString());
        }
      }));

      for (final result in results) {
        if (result.skipped) continue;
        if (result.error != null || result.entries == null) continue;

        final sessionFile = result.sessionFile;
        final entries = result.entries!;
        final sessionId = _basenameWithoutExtension(sessionFile, '.jsonl');

        final messages = entries
            .where((e) => _isTranscriptMessage(e))
            .toList();

        if (messages.isEmpty) continue;

        // Check for speculation-accept entries.
        for (final entry in entries) {
          if (entry['type'] == 'speculation-accept') {
            totalSpeculationTimeSavedMs +=
                ((entry['timeSavedMs'] as num?)?.toInt() ?? 0);
          }
        }

        final isSubagentFile = sessionFile.contains('/subagents/');

        // Extract shot count from PR attribution.
        if (shotStatsEnabled.value && shotDistributionMap != null) {
          final parentSessionId = isSubagentFile
              ? _extractParentSessionId(sessionFile)
              : sessionId;

          if (!sessionsWithShotCount.contains(parentSessionId)) {
            final shotCount = _extractShotCountFromMessages(messages);
            if (shotCount != null) {
              sessionsWithShotCount.add(parentSessionId);
              shotDistributionMap[shotCount] =
                  (shotDistributionMap[shotCount] ?? 0) + 1;
            }
          }
        }

        // Filter out sidechain messages for session metadata.
        final mainMessages = isSubagentFile
            ? messages
            : messages.where((m) => m['isSidechain'] != true).toList();
        if (mainMessages.isEmpty) continue;

        final firstMessage = mainMessages.first;
        final lastMessage = mainMessages.last;

        final firstTimestamp =
            DateTime.tryParse(firstMessage['timestamp']?.toString() ?? '');
        final lastTimestamp =
            DateTime.tryParse(lastMessage['timestamp']?.toString() ?? '');

        if (firstTimestamp == null || lastTimestamp == null) continue;

        final dateKey = toDateString(firstTimestamp);

        if (fromDate != null && isDateBefore(dateKey, fromDate)) continue;
        if (toDate != null && isDateBefore(toDate, dateKey)) continue;

        final existing = dailyActivityMap[dateKey] ??
            DailyActivity(date: dateKey);

        if (!isSubagentFile) {
          final duration = lastTimestamp.difference(firstTimestamp).inMilliseconds;
          sessions.add(SessionStats(
            sessionId: sessionId,
            duration: duration,
            messageCount: mainMessages.length,
            timestamp: firstMessage['timestamp'] as String,
          ));

          totalMessages += mainMessages.length;
          existing.sessionCount++;
          existing.messageCount += mainMessages.length;

          final hour = firstTimestamp.hour;
          hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
        }

        if (!isSubagentFile || dailyActivityMap.containsKey(dateKey)) {
          dailyActivityMap[dateKey] = existing;
        }

        // Process messages for tool usage and model stats.
        for (final message in mainMessages) {
          if (message['type'] == 'assistant') {
            final content = message['message']?['content'];
            if (content is List) {
              for (final block in content) {
                if (block is Map && block['type'] == 'tool_use') {
                  final activity = dailyActivityMap[dateKey];
                  if (activity != null) {
                    activity.toolCallCount++;
                  }
                }
              }
            }

            final usage = message['message']?['usage'];
            if (usage is Map) {
              final model =
                  (message['message']?['model'] as String?) ?? 'unknown';
              if (model == syntheticModel) continue;

              modelUsageAgg.putIfAbsent(model, () => ModelUsage());
              final agg = modelUsageAgg[model]!;
              agg.inputTokens +=
                  (usage['input_tokens'] as num?)?.toInt() ?? 0;
              agg.outputTokens +=
                  (usage['output_tokens'] as num?)?.toInt() ?? 0;
              agg.cacheReadInputTokens +=
                  (usage['cache_read_input_tokens'] as num?)?.toInt() ?? 0;
              agg.cacheCreationInputTokens +=
                  (usage['cache_creation_input_tokens'] as num?)?.toInt() ??
                      0;

              final totalTokens =
                  ((usage['input_tokens'] as num?)?.toInt() ?? 0) +
                      ((usage['output_tokens'] as num?)?.toInt() ?? 0);
              if (totalTokens > 0) {
                final dayTokens = dailyModelTokensMap[dateKey] ?? {};
                dayTokens[model] = (dayTokens[model] ?? 0) + totalTokens;
                dailyModelTokensMap[dateKey] = dayTokens;
              }
            }
          }
        }
      }
    }

    final sortedDailyActivity = dailyActivityMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final sortedDailyModelTokens = dailyModelTokensMap.entries
        .map((e) => DailyModelTokens(date: e.key, tokensByModel: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    return ProcessedStats(
      dailyActivity: sortedDailyActivity,
      dailyModelTokens: sortedDailyModelTokens,
      modelUsage: modelUsageAgg,
      sessionStats: sessions,
      hourCounts: hourCounts,
      totalMessages: totalMessages,
      totalSpeculationTimeSavedMs: totalSpeculationTimeSavedMs,
      shotDistribution: shotDistributionMap,
    );
  }

  // -------------------------------------------------------------------------
  // Cache -> Stats conversion
  // -------------------------------------------------------------------------

  /// Convert a [PersistedStatsCache] to [NeomClawStats] by computing
  /// derived fields, optionally merging today's live stats.
  NeomClawStats cacheToStats(
    PersistedStatsCache cache,
    ProcessedStats? todayStats,
  ) {
    // Merge cache with today's stats.
    final dailyActivityMap = <String, DailyActivity>{};
    for (final day in cache.dailyActivity) {
      dailyActivityMap[day.date] = day.copyWith();
    }
    if (todayStats != null) {
      for (final day in todayStats.dailyActivity) {
        final existing = dailyActivityMap[day.date];
        if (existing != null) {
          existing.messageCount += day.messageCount;
          existing.sessionCount += day.sessionCount;
          existing.toolCallCount += day.toolCallCount;
        } else {
          dailyActivityMap[day.date] = day.copyWith();
        }
      }
    }

    final dailyModelTokensMap = <String, Map<String, int>>{};
    for (final day in cache.dailyModelTokens) {
      dailyModelTokensMap[day.date] =
          Map<String, int>.from(day.tokensByModel);
    }
    if (todayStats != null) {
      for (final day in todayStats.dailyModelTokens) {
        final existing = dailyModelTokensMap[day.date];
        if (existing != null) {
          for (final entry in day.tokensByModel.entries) {
            existing[entry.key] = (existing[entry.key] ?? 0) + entry.value;
          }
        } else {
          dailyModelTokensMap[day.date] =
              Map<String, int>.from(day.tokensByModel);
        }
      }
    }

    // Merge model usage.
    final modelUsage = Map<String, ModelUsage>.from(cache.modelUsage);
    if (todayStats != null) {
      for (final entry in todayStats.modelUsage.entries) {
        final existing = modelUsage[entry.key];
        if (existing != null) {
          modelUsage[entry.key] = existing.merge(entry.value);
        } else {
          modelUsage[entry.key] = entry.value;
        }
      }
    }

    // Merge hour counts.
    final hourCountsMap = <int, int>{};
    for (final entry in cache.hourCounts.entries) {
      hourCountsMap[entry.key] = entry.value;
    }
    if (todayStats != null) {
      for (final entry in todayStats.hourCounts.entries) {
        hourCountsMap[entry.key] =
            (hourCountsMap[entry.key] ?? 0) + entry.value;
      }
    }

    // Calculate derived stats.
    final dailyActivityArray = dailyActivityMap.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final streaks = calculateStreaks(dailyActivityArray);

    final dailyModelTokens = dailyModelTokensMap.entries
        .map((e) => DailyModelTokens(date: e.key, tokensByModel: e.value))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final totalSessions =
        cache.totalSessions + (todayStats?.sessionStats.length ?? 0);
    final totalMessages =
        cache.totalMessages + (todayStats?.totalMessages ?? 0);

    SessionStats? longestSession = cache.longestSession;
    if (todayStats != null) {
      for (final session in todayStats.sessionStats) {
        if (longestSession == null ||
            session.duration > longestSession.duration) {
          longestSession = session;
        }
      }
    }

    String? firstSessionDate = cache.firstSessionDate;
    String? lastSessionDate;
    if (todayStats != null) {
      for (final session in todayStats.sessionStats) {
        if (firstSessionDate == null ||
            session.timestamp.compareTo(firstSessionDate) < 0) {
          firstSessionDate = session.timestamp;
        }
        if (lastSessionDate == null ||
            session.timestamp.compareTo(lastSessionDate) > 0) {
          lastSessionDate = session.timestamp;
        }
      }
    }
    if (lastSessionDate == null && dailyActivityArray.isNotEmpty) {
      lastSessionDate = dailyActivityArray.last.date;
    }

    final peakActivityDay = dailyActivityArray.isNotEmpty
        ? dailyActivityArray
            .reduce((m, d) => d.messageCount > m.messageCount ? d : m)
            .date
        : null;

    final peakActivityHour = hourCountsMap.isNotEmpty
        ? hourCountsMap.entries
            .reduce((m, e) => e.value > m.value ? e : m)
            .key
        : null;

    final totalDays = (firstSessionDate != null && lastSessionDate != null)
        ? ((DateTime.parse(lastSessionDate)
                        .difference(DateTime.parse(firstSessionDate))
                        .inDays) +
                1)
        : 0;

    final totalSpeculationTimeSavedMs =
        cache.totalSpeculationTimeSavedMs +
            (todayStats?.totalSpeculationTimeSavedMs ?? 0);

    Map<int, int>? shotDistribution;
    int? oneShotRate;
    if (shotStatsEnabled.value) {
      shotDistribution = Map<int, int>.from(cache.shotDistribution ?? {});
      if (todayStats?.shotDistribution != null) {
        for (final entry in todayStats!.shotDistribution!.entries) {
          shotDistribution[entry.key] =
              (shotDistribution[entry.key] ?? 0) + entry.value;
        }
      }
      final totalWithShots =
          shotDistribution.values.fold<int>(0, (s, n) => s + n);
      oneShotRate = totalWithShots > 0
          ? ((shotDistribution[1] ?? 0) / totalWithShots * 100).round()
          : 0;
    }

    return NeomClawStats(
      totalSessions: totalSessions,
      totalMessages: totalMessages,
      totalDays: totalDays,
      activeDays: dailyActivityMap.length,
      streaks: streaks,
      dailyActivity: dailyActivityArray,
      dailyModelTokens: dailyModelTokens,
      longestSession: longestSession,
      modelUsage: modelUsage,
      firstSessionDate: firstSessionDate,
      lastSessionDate: lastSessionDate,
      peakActivityDay: peakActivityDay,
      peakActivityHour: peakActivityHour,
      totalSpeculationTimeSavedMs: totalSpeculationTimeSavedMs,
      shotDistribution: shotDistribution,
      oneShotRate: oneShotRate,
    );
  }

  // -------------------------------------------------------------------------
  // Main aggregation
  // -------------------------------------------------------------------------

  /// Aggregates stats from all NeomClaw sessions across all projects.
  /// Uses a disk cache to avoid reprocessing historical data.
  Future<NeomClawStats> aggregateNeomClawStats() async {
    final allSessionFiles = await getAllSessionFiles();

    if (allSessionFiles.isEmpty) {
      return _getEmptyStats();
    }

    final updatedCache = await withStatsCacheLock(() async {
      final cache = await loadStatsCache();
      final yesterday = getYesterdayDateString();

      var result = cache;

      if (cache.lastComputedDate == null) {
        // No cache — process all historical data.
        final historicalStats = await processSessionFiles(
          allSessionFiles,
          options: ProcessOptions(toDate: yesterday),
        );

        if (historicalStats.sessionStats.isNotEmpty ||
            historicalStats.dailyActivity.isNotEmpty) {
          result = mergeCacheWithNewStats(
            existingCache: cache,
            newStats: historicalStats,
            newLastComputedDate: yesterday,
          );
          await saveStatsCache(result);
        }
      } else if (isDateBefore(cache.lastComputedDate!, yesterday)) {
        // Cache is stale — process new days.
        final nextDay = getNextDay(cache.lastComputedDate!);
        final newStats = await processSessionFiles(
          allSessionFiles,
          options: ProcessOptions(fromDate: nextDay, toDate: yesterday),
        );

        if (newStats.sessionStats.isNotEmpty ||
            newStats.dailyActivity.isNotEmpty) {
          result = mergeCacheWithNewStats(
            existingCache: cache,
            newStats: newStats,
            newLastComputedDate: yesterday,
          );
          await saveStatsCache(result);
        } else {
          result = cache.copyWith(lastComputedDate: yesterday);
          await saveStatsCache(result);
        }
      }

      return result;
    });

    // Always process today's data live (it's incomplete).
    final today = getTodayDateString();
    final todayStats = await processSessionFiles(
      allSessionFiles,
      options: ProcessOptions(fromDate: today, toDate: today),
    );

    return cacheToStats(updatedCache, todayStats);
  }

  /// Aggregates stats for a specific date range.
  Future<NeomClawStats> aggregateNeomClawStatsForRange(
    StatsDateRange range,
  ) async {
    if (range == StatsDateRange.all) {
      return aggregateNeomClawStats();
    }

    final allSessionFiles = await getAllSessionFiles();
    if (allSessionFiles.isEmpty) {
      return _getEmptyStats();
    }

    final today = DateTime.now();
    final daysBack = range == StatsDateRange.sevenDays ? 7 : 30;
    final fromDate = today.subtract(Duration(days: daysBack - 1));
    final fromDateStr = toDateString(fromDate);

    final stats = await processSessionFiles(
      allSessionFiles,
      options: ProcessOptions(fromDate: fromDateStr),
    );

    return _processedStatsToNeomClawStats(stats);
  }

  /// Convert [ProcessedStats] to [NeomClawStats].
  /// Used for filtered date ranges that bypass the cache.
  NeomClawStats _processedStatsToNeomClawStats(ProcessedStats stats) {
    final dailyActivitySorted = stats.dailyActivity.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final dailyModelTokensSorted = stats.dailyModelTokens.toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    final streaks = calculateStreaks(dailyActivitySorted);

    SessionStats? longestSession;
    for (final session in stats.sessionStats) {
      if (longestSession == null ||
          session.duration > longestSession.duration) {
        longestSession = session;
      }
    }

    String? firstSessionDate;
    String? lastSessionDate;
    for (final session in stats.sessionStats) {
      if (firstSessionDate == null ||
          session.timestamp.compareTo(firstSessionDate) < 0) {
        firstSessionDate = session.timestamp;
      }
      if (lastSessionDate == null ||
          session.timestamp.compareTo(lastSessionDate) > 0) {
        lastSessionDate = session.timestamp;
      }
    }

    final peakActivityDay = dailyActivitySorted.isNotEmpty
        ? dailyActivitySorted
            .reduce((m, d) => d.messageCount > m.messageCount ? d : m)
            .date
        : null;

    final hourEntries = stats.hourCounts.entries.toList();
    final peakActivityHour = hourEntries.isNotEmpty
        ? hourEntries.reduce((m, e) => e.value > m.value ? e : m).key
        : null;

    final totalDays = (firstSessionDate != null && lastSessionDate != null)
        ? (DateTime.parse(lastSessionDate)
                    .difference(DateTime.parse(firstSessionDate))
                    .inDays +
                1)
        : 0;

    Map<int, int>? shotDistribution;
    int? oneShotRate;
    if (shotStatsEnabled.value && stats.shotDistribution != null) {
      shotDistribution = stats.shotDistribution;
      final totalWithShots =
          shotDistribution!.values.fold<int>(0, (s, n) => s + n);
      oneShotRate = totalWithShots > 0
          ? ((shotDistribution[1] ?? 0) / totalWithShots * 100).round()
          : 0;
    }

    return NeomClawStats(
      totalSessions: stats.sessionStats.length,
      totalMessages: stats.totalMessages,
      totalDays: totalDays,
      activeDays: stats.dailyActivity.length,
      streaks: streaks,
      dailyActivity: dailyActivitySorted,
      dailyModelTokens: dailyModelTokensSorted,
      longestSession: longestSession,
      modelUsage: stats.modelUsage,
      firstSessionDate: firstSessionDate,
      lastSessionDate: lastSessionDate,
      peakActivityDay: peakActivityDay,
      peakActivityHour: peakActivityHour,
      totalSpeculationTimeSavedMs: stats.totalSpeculationTimeSavedMs,
      shotDistribution: shotDistribution,
      oneShotRate: oneShotRate,
    );
  }

  // -------------------------------------------------------------------------
  // Streak calculation
  // -------------------------------------------------------------------------

  /// Calculate current and longest streaks from daily activity data.
  static StreakInfo calculateStreaks(List<DailyActivity> dailyActivity) {
    if (dailyActivity.isEmpty) {
      return const StreakInfo();
    }

    final today = DateTime.now();
    final todayNorm = DateTime(today.year, today.month, today.day);

    final activeDates = dailyActivity.map((d) => d.date).toSet();

    // Calculate current streak (working backwards from today).
    var currentStreak = 0;
    String? currentStreakStart;
    var checkDate = todayNorm;

    while (true) {
      final dateStr = toDateString(checkDate);
      if (!activeDates.contains(dateStr)) break;
      currentStreak++;
      currentStreakStart = dateStr;
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    // Calculate longest streak.
    var longestStreak = 0;
    String? longestStreakStart;
    String? longestStreakEnd;

    final sortedDates = activeDates.toList()..sort();
    var tempStreak = 1;
    var tempStart = sortedDates.first;

    for (var i = 1; i < sortedDates.length; i++) {
      final prevDate = DateTime.parse(sortedDates[i - 1]);
      final currDate = DateTime.parse(sortedDates[i]);

      final dayDiff = currDate.difference(prevDate).inDays;

      if (dayDiff == 1) {
        tempStreak++;
      } else {
        if (tempStreak > longestStreak) {
          longestStreak = tempStreak;
          longestStreakStart = tempStart;
          longestStreakEnd = sortedDates[i - 1];
        }
        tempStreak = 1;
        tempStart = sortedDates[i];
      }
    }

    // Check final streak.
    if (tempStreak > longestStreak) {
      longestStreak = tempStreak;
      longestStreakStart = tempStart;
      longestStreakEnd = sortedDates.last;
    }

    return StreakInfo(
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      currentStreakStart: currentStreakStart,
      longestStreakStart: longestStreakStart,
      longestStreakEnd: longestStreakEnd,
    );
  }

  // -------------------------------------------------------------------------
  // Shot count extraction
  // -------------------------------------------------------------------------

  /// Extract the shot count from PR attribution text in a `gh pr create` call.
  static int? _extractShotCountFromMessages(
      List<Map<String, dynamic>> messages) {
    for (final m in messages) {
      if (m['type'] != 'assistant') continue;
      final content = m['message']?['content'];
      if (content is! List) continue;
      for (final block in content) {
        if (block is! Map) continue;
        if (block['type'] != 'tool_use') continue;
        final input = block['input'];
        if (input is! Map) continue;
        final command = input['command'];
        if (command is! String) continue;
        final match = _shotCountRegex.firstMatch(command);
        if (match != null) {
          return int.tryParse(match.group(1) ?? '');
        }
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Peek at session start date
  // -------------------------------------------------------------------------

  /// Peeks at the head of a session file to get the session start date.
  /// Uses a small 4 KB read to avoid loading the full file.
  static Future<String?> readSessionStartDate(String filePath) async {
    try {
      final file = File(filePath);
      final raf = await file.open(mode: FileMode.read);
      try {
        final buf = List<int>.filled(4096, 0);
        final bytesRead = await raf.readInto(buf);
        if (bytesRead == 0) return null;

        final head = utf8.decode(buf.sublist(0, bytesRead), allowMalformed: true);
        final lastNewline = head.lastIndexOf('\n');
        if (lastNewline < 0) return null;

        for (final line in head.substring(0, lastNewline).split('\n')) {
          if (line.isEmpty) continue;
          Map<String, dynamic> entry;
          try {
            entry = jsonDecode(line) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }
          final type = entry['type'];
          if (type is! String) continue;
          if (!_transcriptMessageTypes.contains(type)) continue;
          if (entry['isSidechain'] == true) continue;
          final timestamp = entry['timestamp'];
          if (timestamp is! String) return null;
          final date = DateTime.tryParse(timestamp);
          if (date == null) return null;
          return toDateString(date);
        }
        return null;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  static bool _isTranscriptMessage(Map<String, dynamic> entry) {
    final type = entry['type'];
    return type is String && _transcriptMessageTypes.contains(type);
  }

  static String _basenameWithoutExtension(String path, String ext) {
    final segments = path.split('/');
    final filename = segments.last;
    if (filename.endsWith(ext)) {
      return filename.substring(0, filename.length - ext.length);
    }
    return filename;
  }

  static String _extractParentSessionId(String sessionFile) {
    // Structure: {projectDir}/{sessionId}/subagents/agent-{agentId}.jsonl
    final parts = sessionFile.split('/');
    final subagentsIdx = parts.indexOf('subagents');
    if (subagentsIdx >= 2) {
      return parts[subagentsIdx - 1];
    }
    return '';
  }
}

// ---------------------------------------------------------------------------
// Internal helper class for session file reads
// ---------------------------------------------------------------------------

class _SessionReadResult {
  _SessionReadResult({
    required this.sessionFile,
    this.entries,
    this.error,
    this.skipped = false,
  });

  final String sessionFile;
  final List<Map<String, dynamic>>? entries;
  final String? error;
  final bool skipped;
}
