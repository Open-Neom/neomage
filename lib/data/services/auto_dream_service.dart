// Auto-dream service — port of neom_claw/src/services/autoDream/.
// Background memory consolidation. Fires a /dream prompt as a forked
// subagent when a time-gate passes AND enough sessions have accumulated.
//
// Gate order (cheapest first):
//   1. Time: hours since lastConsolidatedAt >= minHours (one stat)
//   2. Sessions: transcript count with mtime > lastConsolidatedAt >= minSessions
//   3. Lock: no other process mid-consolidation
//
// This file ports all four TS source files:
//   - autoDream.ts       (main runner)
//   - config.ts          (isAutoDreamEnabled)
//   - consolidationLock.ts (lock file / session listing)
//   - consolidationPrompt.ts (prompt builder)

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:sint/sint.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Configuration (config.ts port)
// ═══════════════════════════════════════════════════════════════════════════

/// Auto-dream scheduling thresholds.
class AutoDreamConfig {
  /// Minimum hours since last consolidation before triggering.
  final double minHours;

  /// Minimum number of sessions touched since last consolidation.
  final int minSessions;

  const AutoDreamConfig({this.minHours = 24, this.minSessions = 5});

  factory AutoDreamConfig.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const AutoDreamConfig();
    return AutoDreamConfig(
      minHours: (json['minHours'] is num && (json['minHours'] as num) > 0)
          ? (json['minHours'] as num).toDouble()
          : 24,
      minSessions:
          (json['minSessions'] is int && (json['minSessions'] as int) > 0)
          ? json['minSessions'] as int
          : 5,
    );
  }
}

/// Whether background memory consolidation should run.
///
/// User setting (`autoDreamEnabled` in settings.json) overrides the
/// GrowthBook default when explicitly set; otherwise falls through to the
/// feature flag.
class AutoDreamEnabledCheck {
  /// Read the user setting from settings.json (may be null if unset).
  final bool? Function() getUserSetting;

  /// Read the GrowthBook feature flag value.
  final bool Function() getFeatureFlagEnabled;

  const AutoDreamEnabledCheck({
    required this.getUserSetting,
    required this.getFeatureFlagEnabled,
  });

  bool get isEnabled {
    final setting = getUserSetting();
    if (setting != null) return setting;
    return getFeatureFlagEnabled();
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Consolidation lock (consolidationLock.ts port)
// ═══════════════════════════════════════════════════════════════════════════

/// Lock file whose mtime IS lastConsolidatedAt. Body is the holder's PID.
///
/// Lives inside the memory dir (getAutoMemPath) so it keys on git-root
/// like memory does, and so it's writable even when the memory path comes
/// from an env/settings override.
const _lockFileName = '.consolidate-lock';

/// Stale past this even if the PID is live (PID reuse guard).
const _holderStaleMs = 60 * 60 * 1000;

/// A session candidate from the transcript directory.
class SessionCandidate {
  final String sessionId;
  final int mtimeMs;

  const SessionCandidate({required this.sessionId, required this.mtimeMs});
}

/// Consolidation lock service — manages the lock file that tracks when the
/// last consolidation ran, prevents concurrent consolidations, and lists
/// sessions touched since the last one.
class ConsolidationLockService {
  /// Get the auto-memory root path.
  final String Function() getAutoMemPath;

  /// Get the transcript/project directory.
  final String Function() getProjectDir;

  /// Check if a PID is currently running.
  final bool Function(int pid) isProcessRunning;

  /// File stat (returns mtimeMs, or null if absent).
  final Future<int?> Function(String path) statMtimeMs;

  /// Read file as string (returns null if absent).
  final Future<String?> Function(String path) readFileOrNull;

  /// Write file.
  final Future<void> Function(String path, String content) writeFile;

  /// Delete file (no-throw if absent).
  final Future<void> Function(String path) deleteFile;

  /// Set file mtime (utimes).
  final Future<void> Function(String path, DateTime time) setMtime;

  /// Create directory recursively.
  final Future<void> Function(String path) mkdirRecursive;

  /// List session candidates in a directory.
  final Future<List<SessionCandidate>> Function(String dir) listCandidates;

  /// Debug logger.
  final void Function(String message) logDebug;

  ConsolidationLockService({
    required this.getAutoMemPath,
    required this.getProjectDir,
    required this.isProcessRunning,
    required this.statMtimeMs,
    required this.readFileOrNull,
    required this.writeFile,
    required this.deleteFile,
    required this.setMtime,
    required this.mkdirRecursive,
    required this.listCandidates,
    required this.logDebug,
  });

  String get _lockPath => '${getAutoMemPath()}/$_lockFileName';

  /// mtime of the lock file = lastConsolidatedAt. 0 if absent.
  Future<int> readLastConsolidatedAt() async {
    final mtime = await statMtimeMs(_lockPath);
    return mtime ?? 0;
  }

  /// Acquire: write PID -> mtime = now. Returns the pre-acquire mtime
  /// (for rollback), or null if blocked / lost a race.
  Future<int?> tryAcquireLock() async {
    int? mtimeMs;
    int? holderPid;

    try {
      final results = await Future.wait([
        statMtimeMs(_lockPath),
        readFileOrNull(_lockPath),
      ]);
      mtimeMs = results[0] as int?;
      final raw = results[1] as String?;
      if (raw != null) {
        final parsed = int.tryParse(raw.trim());
        holderPid = parsed;
      }
    } catch (_) {
      // ENOENT — no prior lock.
    }

    if (mtimeMs != null &&
        DateTime.now().millisecondsSinceEpoch - mtimeMs < _holderStaleMs) {
      if (holderPid != null && isProcessRunning(holderPid)) {
        logDebug(
          '[autoDream] lock held by live PID $holderPid '
          '(mtime ${((DateTime.now().millisecondsSinceEpoch - mtimeMs) / 1000).round()}s ago)',
        );
        return null;
      }
      // Dead PID or unparseable body — reclaim.
    }

    // Memory dir may not exist yet.
    await mkdirRecursive(getAutoMemPath());
    await writeFile(_lockPath, pid.toString());

    // Two reclaimers both write -> last wins the PID. Loser bails on re-read.
    String? verify;
    try {
      verify = await readFileOrNull(_lockPath);
    } catch (_) {
      return null;
    }
    if (verify == null || int.tryParse(verify.trim()) != pid) return null;

    return mtimeMs ?? 0;
  }

  /// Rewind mtime to pre-acquire after a failed fork.
  Future<void> rollbackLock(int priorMtimeMs) async {
    try {
      if (priorMtimeMs == 0) {
        await deleteFile(_lockPath);
        return;
      }
      await writeFile(_lockPath, '');
      final t = DateTime.fromMillisecondsSinceEpoch(priorMtimeMs);
      await setMtime(_lockPath, t);
    } catch (e) {
      logDebug('[autoDream] rollback failed: $e');
    }
  }

  /// Session IDs with mtime after sinceMs.
  Future<List<String>> listSessionsTouchedSince(int sinceMs) async {
    final dir = getProjectDir();
    final candidates = await listCandidates(dir);
    return candidates
        .where((c) => c.mtimeMs > sinceMs)
        .map((c) => c.sessionId)
        .toList();
  }

  /// Stamp from manual /dream. Best-effort.
  Future<void> recordConsolidation() async {
    try {
      await mkdirRecursive(getAutoMemPath());
      await writeFile(_lockPath, pid.toString());
    } catch (e) {
      logDebug('[autoDream] recordConsolidation write failed: $e');
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Consolidation prompt (consolidationPrompt.ts port)
// ═══════════════════════════════════════════════════════════════════════════

/// Constants from memdir.
const _entrypointName = 'README.md';
const _maxEntrypointLines = 150;
const _dirExistsGuidance =
    'This directory already exists. Read existing files before creating new ones '
    'to avoid duplicating information.';

/// Build the consolidation prompt for a dream run.
String buildConsolidationPrompt(
  String memoryRoot,
  String transcriptDir,
  String extra,
) {
  return '''# Dream: Memory Consolidation

You are performing a dream — a reflective pass over your memory files. Synthesize what you've learned recently into durable, well-organized memories so that future sessions can orient quickly.

Memory directory: `$memoryRoot`
$_dirExistsGuidance

Session transcripts: `$transcriptDir` (large JSONL files — grep narrowly, don't read whole files)

---

## Phase 1 — Orient

- `ls` the memory directory to see what already exists
- Read `$_entrypointName` to understand the current index
- Skim existing topic files so you improve them rather than creating duplicates
- If `logs/` or `sessions/` subdirectories exist (assistant-mode layout), review recent entries there

## Phase 2 — Gather recent signal

Look for new information worth persisting. Sources in rough priority order:

1. **Daily logs** (`logs/YYYY/MM/YYYY-MM-DD.md`) if present — these are the append-only stream
2. **Existing memories that drifted** — facts that contradict something you see in the codebase now
3. **Transcript search** — if you need specific context (e.g., "what was the error message from yesterday's build failure?"), grep the JSONL transcripts for narrow terms:
   `grep -rn "<narrow term>" $transcriptDir/ --include="*.jsonl" | tail -50`

Don't exhaustively read transcripts. Look only for things you already suspect matter.

## Phase 3 — Consolidate

For each thing worth remembering, write or update a memory file at the top level of the memory directory. Use the memory file format and type conventions from your system prompt's auto-memory section — it's the source of truth for what to save, how to structure it, and what NOT to save.

Focus on:
- Merging new signal into existing topic files rather than creating near-duplicates
- Converting relative dates ("yesterday", "last week") to absolute dates so they remain interpretable after time passes
- Deleting contradicted facts — if today's investigation disproves an old memory, fix it at the source

## Phase 4 — Prune and index

Update `$_entrypointName` so it stays under $_maxEntrypointLines lines AND under ~25KB. It's an **index**, not a dump — each entry should be one line under ~150 characters: `- [Title](file.md) — one-line hook`. Never write memory content directly into it.

- Remove pointers to memories that are now stale, wrong, or superseded
- Demote verbose entries: if an index line is over ~200 chars, it's carrying content that belongs in the topic file — shorten the line, move the detail
- Add pointers to newly important memories
- Resolve contradictions — if two files disagree, fix the wrong one

---

Return a brief summary of what you consolidated, updated, or pruned. If nothing changed (memories are already tight), say so.${extra.isNotEmpty ? '\n\n## Additional context\n\n$extra' : ''}''';
}

// ═══════════════════════════════════════════════════════════════════════════
// Dream task state
// ═══════════════════════════════════════════════════════════════════════════

/// Status of a dream task.
enum DreamTaskStatus { running, completed, failed, killed }

/// A single turn from the dream agent.
class DreamTurn {
  final String text;
  final int toolUseCount;

  const DreamTurn({required this.text, required this.toolUseCount});
}

/// State of an in-progress or completed dream task.
class DreamTaskState {
  final String taskId;
  final DreamTaskStatus status;
  final int sessionsReviewing;
  final int priorMtime;
  final List<DreamTurn> turns;
  final List<String> filesTouched;

  const DreamTaskState({
    required this.taskId,
    this.status = DreamTaskStatus.running,
    this.sessionsReviewing = 0,
    this.priorMtime = 0,
    this.turns = const [],
    this.filesTouched = const [],
  });

  DreamTaskState copyWith({
    DreamTaskStatus? status,
    List<DreamTurn>? turns,
    List<String>? filesTouched,
  }) => DreamTaskState(
    taskId: taskId,
    status: status ?? this.status,
    sessionsReviewing: sessionsReviewing,
    priorMtime: priorMtime,
    turns: turns ?? this.turns,
    filesTouched: filesTouched ?? this.filesTouched,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Dream message model
// ═══════════════════════════════════════════════════════════════════════════

/// Simplified message model for dream progress watching.
class DreamMessage {
  final String type; // 'assistant', 'user', 'system'
  final List<DreamMessageBlock> content;

  const DreamMessage({required this.type, this.content = const []});
}

/// A block within a dream message.
class DreamMessageBlock {
  final String type; // 'text', 'tool_use'
  final String? text;
  final String? toolName;
  final Map<String, dynamic>? input;

  const DreamMessageBlock({
    required this.type,
    this.text,
    this.toolName,
    this.input,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Auto-dream controller (autoDream.ts port)
// ═══════════════════════════════════════════════════════════════════════════

/// Scan throttle: when time-gate passes but session-gate doesn't, the lock
/// mtime doesn't advance, so the time-gate keeps passing every turn.
const _sessionScanIntervalMs = 10 * 60 * 1000;

/// Main auto-dream controller. Call [initialize] once at startup, then
/// [executeAutoDream] from a post-sampling hook.
class AutoDreamController extends SintController {
  // ── Dependencies ────────────────────────────────────────────────────

  /// Feature gate + config retrieval.
  final AutoDreamEnabledCheck enabledCheck;

  /// Get the auto-dream config from feature flags.
  final AutoDreamConfig Function() getConfig;

  /// Check if KAIROS mode is active.
  final bool Function() isKairosActive;

  /// Check if remote mode is active.
  final bool Function() isRemoteMode;

  /// Check if auto-memory is enabled.
  final bool Function() isAutoMemoryEnabled;

  /// Get the current session ID.
  final String Function() getSessionId;

  /// Get the auto-memory root path.
  final String Function() getAutoMemPath;

  /// Get the original CWD.
  final String Function() getOriginalCwd;

  /// Get the project directory for transcripts.
  final String Function(String cwd) getProjectDir;

  /// Consolidation lock service.
  final ConsolidationLockService lockService;

  /// Analytics event logger.
  final void Function(String eventName, Map<String, Object?> metadata) logEvent;

  /// Debug logger.
  final void Function(String message) logDebug;

  /// Run the forked dream agent.
  final Future<DreamRunResult> Function({
    required String prompt,
    required void Function(DreamMessage) onMessage,
  })
  runDreamAgent;

  // ── State ───────────────────────────────────────────────────────────

  /// Currently active dream tasks.
  final dreamTasks = <String, DreamTaskState>{}.obs;

  /// Last session scan timestamp.
  int _lastSessionScanAt = 0;

  /// Whether the runner has been initialised.
  bool _initialized = false;

  /// Next task ID counter.
  int _nextTaskId = 0;

  AutoDreamController({
    required this.enabledCheck,
    required this.getConfig,
    required this.isKairosActive,
    required this.isRemoteMode,
    required this.isAutoMemoryEnabled,
    required this.getSessionId,
    required this.getAutoMemPath,
    required this.getOriginalCwd,
    required this.getProjectDir,
    required this.lockService,
    required this.logEvent,
    required this.logDebug,
    required this.runDreamAgent,
  });

  /// Call once at startup.
  void initialize() {
    _initialized = true;
    _lastSessionScanAt = 0;
  }

  /// Whether the dream gate is open (all preconditions met).
  bool _isGateOpen() {
    if (isKairosActive()) return false;
    if (isRemoteMode()) return false;
    if (!isAutoMemoryEnabled()) return false;
    return enabledCheck.isEnabled;
  }

  /// Entry point from post-sampling hooks.
  Future<void> executeAutoDream() async {
    if (!_initialized) return;
    if (!_isGateOpen()) return;

    final cfg = getConfig();

    // --- Time gate ---
    int lastAt;
    try {
      lastAt = await lockService.readLastConsolidatedAt();
    } catch (e) {
      logDebug('[autoDream] readLastConsolidatedAt failed: $e');
      return;
    }
    final hoursSince =
        (DateTime.now().millisecondsSinceEpoch - lastAt) / 3600000.0;
    if (hoursSince < cfg.minHours) return;

    // --- Scan throttle ---
    final sinceScanMs =
        DateTime.now().millisecondsSinceEpoch - _lastSessionScanAt;
    if (sinceScanMs < _sessionScanIntervalMs) {
      logDebug(
        '[autoDream] scan throttle — time-gate passed but last scan was '
        '${(sinceScanMs / 1000).round()}s ago',
      );
      return;
    }
    _lastSessionScanAt = DateTime.now().millisecondsSinceEpoch;

    // --- Session gate ---
    List<String> sessionIds;
    try {
      sessionIds = await lockService.listSessionsTouchedSince(lastAt);
    } catch (e) {
      logDebug('[autoDream] listSessionsTouchedSince failed: $e');
      return;
    }
    // Exclude the current session.
    final currentSession = getSessionId();
    sessionIds = sessionIds.where((id) => id != currentSession).toList();
    if (sessionIds.length < cfg.minSessions) {
      logDebug(
        '[autoDream] skip — ${sessionIds.length} sessions since last '
        'consolidation, need ${cfg.minSessions}',
      );
      return;
    }

    // --- Lock ---
    int? priorMtime;
    try {
      priorMtime = await lockService.tryAcquireLock();
    } catch (e) {
      logDebug('[autoDream] lock acquire failed: $e');
      return;
    }
    if (priorMtime == null) return;

    logDebug(
      '[autoDream] firing — ${hoursSince.toStringAsFixed(1)}h since last, '
      '${sessionIds.length} sessions to review',
    );
    logEvent('tengu_auto_dream_fired', {
      'hours_since': hoursSince.round(),
      'sessions_since': sessionIds.length,
    });

    final taskId = 'dream_${_nextTaskId++}';
    dreamTasks[taskId] = DreamTaskState(
      taskId: taskId,
      sessionsReviewing: sessionIds.length,
      priorMtime: priorMtime,
    );

    try {
      final memoryRoot = getAutoMemPath();
      final transcriptDir = getProjectDir(getOriginalCwd());
      final extra =
          '''

**Tool constraints for this run:** Bash is restricted to read-only commands (`ls`, `find`, `grep`, `cat`, `stat`, `wc`, `head`, `tail`, and similar). Anything that writes, redirects to a file, or modifies state will be denied.

Sessions since last consolidation (${sessionIds.length}):
${sessionIds.map((id) => '- $id').join('\n')}''';

      final prompt = buildConsolidationPrompt(memoryRoot, transcriptDir, extra);

      final result = await runDreamAgent(
        prompt: prompt,
        onMessage: (msg) => _watchProgress(taskId, msg),
      );

      // Complete.
      final currentTask = dreamTasks[taskId];
      if (currentTask != null) {
        dreamTasks[taskId] = currentTask.copyWith(
          status: DreamTaskStatus.completed,
        );
      }

      logDebug(
        '[autoDream] completed — cache: read=${result.cacheReadTokens} '
        'created=${result.cacheCreatedTokens}',
      );
      logEvent('tengu_auto_dream_completed', {
        'cache_read': result.cacheReadTokens,
        'cache_created': result.cacheCreatedTokens,
        'output': result.outputTokens,
        'sessions_reviewed': sessionIds.length,
      });
    } catch (e) {
      logDebug('[autoDream] fork failed: $e');
      logEvent('tengu_auto_dream_failed', {});

      final currentTask = dreamTasks[taskId];
      if (currentTask != null) {
        dreamTasks[taskId] = currentTask.copyWith(
          status: DreamTaskStatus.failed,
        );
      }

      // Rewind mtime so time-gate passes again.
      await lockService.rollbackLock(priorMtime);
    }
  }

  /// Watch the forked agent's messages for progress.
  void _watchProgress(String taskId, DreamMessage msg) {
    if (msg.type != 'assistant') return;

    final textBuffer = StringBuffer();
    var toolUseCount = 0;
    final touchedPaths = <String>[];

    for (final block in msg.content) {
      if (block.type == 'text' && block.text != null) {
        textBuffer.write(block.text);
      } else if (block.type == 'tool_use') {
        toolUseCount++;
        if (block.toolName == 'Edit' || block.toolName == 'Write') {
          final filePath = block.input?['file_path'];
          if (filePath is String) {
            touchedPaths.add(filePath);
          }
        }
      }
    }

    final currentTask = dreamTasks[taskId];
    if (currentTask == null) return;

    final newTurns = [
      ...currentTask.turns,
      DreamTurn(text: textBuffer.toString().trim(), toolUseCount: toolUseCount),
    ];
    final newFiles = {...currentTask.filesTouched, ...touchedPaths}.toList();

    dreamTasks[taskId] = currentTask.copyWith(
      turns: newTurns,
      filesTouched: newFiles,
    );
  }

  /// Kill a running dream task.
  Future<void> killDreamTask(String taskId) async {
    final task = dreamTasks[taskId];
    if (task == null || task.status != DreamTaskStatus.running) return;

    dreamTasks[taskId] = task.copyWith(status: DreamTaskStatus.killed);
    await lockService.rollbackLock(task.priorMtime);
    logDebug('[autoDream] task $taskId killed by user');
  }
}

/// Result from a dream agent run.
class DreamRunResult {
  final int cacheReadTokens;
  final int cacheCreatedTokens;
  final int outputTokens;

  const DreamRunResult({
    this.cacheReadTokens = 0,
    this.cacheCreatedTokens = 0,
    this.outputTokens = 0,
  });
}
