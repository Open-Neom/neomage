// Cron manager — port of openneomclaw/src/utils/cron.ts, cronScheduler.ts,
// cronTasks.ts, cronTasksLock.ts, cronJitterConfig.ts.
// Cron expression parsing, scheduling, task management, locking, jitter config.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;

// ============================================================================
// Part 1: Cron expression parsing (from cron.ts)
// ============================================================================

/// Expanded cron fields — each is a sorted list of matching values.
class CronFields {
  final List<int> minute;
  final List<int> hour;
  final List<int> dayOfMonth;
  final List<int> month;
  final List<int> dayOfWeek;

  const CronFields({
    required this.minute,
    required this.hour,
    required this.dayOfMonth,
    required this.month,
    required this.dayOfWeek,
  });
}

/// Range constraint for a single cron field.
class _FieldRange {
  final int min;
  final int max;
  const _FieldRange(this.min, this.max);
}

const List<_FieldRange> _fieldRanges = [
  _FieldRange(0, 59), // minute
  _FieldRange(0, 23), // hour
  _FieldRange(1, 31), // dayOfMonth
  _FieldRange(1, 12), // month
  _FieldRange(0, 6),  // dayOfWeek (0=Sunday; 7 accepted as Sunday alias)
];

/// Parse a single cron field into a sorted list of matching values.
/// Supports: wildcard, N, star/N (step), N-M (range), and comma-lists.
/// Returns null if invalid.
List<int>? _expandField(String field, _FieldRange range) {
  final out = <int>{};

  for (final part in field.split(',')) {
    // wildcard or */N
    final stepMatch = RegExp(r'^\*(?:/(\d+))?$').firstMatch(part);
    if (stepMatch != null) {
      final step = stepMatch.group(1) != null
          ? int.parse(stepMatch.group(1)!)
          : 1;
      if (step < 1) return null;
      for (int i = range.min; i <= range.max; i += step) {
        out.add(i);
      }
      continue;
    }

    // N-M or N-M/S
    final rangeMatch = RegExp(r'^(\d+)-(\d+)(?:/(\d+))?$').firstMatch(part);
    if (rangeMatch != null) {
      final lo = int.parse(rangeMatch.group(1)!);
      final hi = int.parse(rangeMatch.group(2)!);
      final step = rangeMatch.group(3) != null
          ? int.parse(rangeMatch.group(3)!)
          : 1;
      // dayOfWeek: accept 7 as Sunday alias in ranges.
      final isDow = range.min == 0 && range.max == 6;
      final effMax = isDow ? 7 : range.max;
      if (lo > hi || step < 1 || lo < range.min || hi > effMax) return null;
      for (int i = lo; i <= hi; i += step) {
        out.add(isDow && i == 7 ? 0 : i);
      }
      continue;
    }

    // plain N
    final singleMatch = RegExp(r'^\d+$').firstMatch(part);
    if (singleMatch != null) {
      var n = int.parse(part);
      // dayOfWeek: accept 7 as Sunday alias -> 0.
      if (range.min == 0 && range.max == 6 && n == 7) n = 0;
      if (n < range.min || n > range.max) return null;
      out.add(n);
      continue;
    }

    return null;
  }

  if (out.isEmpty) return null;
  final sorted = out.toList()..sort();
  return sorted;
}

/// Parse a 5-field cron expression into expanded number arrays.
/// Returns null if invalid or unsupported syntax.
CronFields? parseCronExpression(String expr) {
  final parts = expr.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return null;

  final expanded = <List<int>>[];
  for (int i = 0; i < 5; i++) {
    final result = _expandField(parts[i], _fieldRanges[i]);
    if (result == null) return null;
    expanded.add(result);
  }

  return CronFields(
    minute: expanded[0],
    hour: expanded[1],
    dayOfMonth: expanded[2],
    month: expanded[3],
    dayOfWeek: expanded[4],
  );
}

/// Compute the next DateTime strictly after [from] that matches the cron
/// fields, using the process's local timezone. Walks forward minute-by-minute.
/// Bounded at 366 days; returns null if no match.
///
/// Standard cron semantics: when both dayOfMonth and dayOfWeek are constrained
/// (neither is the full range), a date matches if EITHER matches.
///
/// DST: fixed-hour crons targeting a spring-forward gap skip the transition
/// day. Wildcard-hour crons fire at the first valid minute after the gap.
DateTime? computeNextCronRun(CronFields fields, DateTime from) {
  final minuteSet = fields.minute.toSet();
  final hourSet = fields.hour.toSet();
  final domSet = fields.dayOfMonth.toSet();
  final monthSet = fields.month.toSet();
  final dowSet = fields.dayOfWeek.toSet();

  // Is the field wildcarded (full range)?
  final domWild = fields.dayOfMonth.length == 31;
  final dowWild = fields.dayOfWeek.length == 7;

  // Round up to the next whole minute (strictly after `from`).
  var t = DateTime(from.year, from.month, from.day, from.hour, from.minute)
      .add(const Duration(minutes: 1));

  const maxIter = 366 * 24 * 60;
  for (int i = 0; i < maxIter; i++) {
    final month = t.month;
    if (!monthSet.contains(month)) {
      // Jump to start of next month.
      if (t.month == 12) {
        t = DateTime(t.year + 1, 1, 1);
      } else {
        t = DateTime(t.year, t.month + 1, 1);
      }
      continue;
    }

    final dom = t.day;
    final dow = t.weekday % 7; // DateTime weekday: Mon=1..Sun=7, cron: Sun=0.
    final dayMatches = domWild && dowWild
        ? true
        : domWild
            ? dowSet.contains(dow)
            : dowWild
                ? domSet.contains(dom)
                : domSet.contains(dom) || dowSet.contains(dow);

    if (!dayMatches) {
      // Jump to start of next day.
      t = DateTime(t.year, t.month, t.day + 1);
      continue;
    }

    if (!hourSet.contains(t.hour)) {
      t = DateTime(t.year, t.month, t.day, t.hour + 1);
      continue;
    }

    if (!minuteSet.contains(t.minute)) {
      t = t.add(const Duration(minutes: 1));
      continue;
    }

    return t;
  }

  return null;
}

// ─── cronToHuman ─────────────────────────────────────────────────────────────

const List<String> _dayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

String _formatLocalTime(int minute, int hour) {
  // Use January 1 to avoid DST gaps.
  final d = DateTime(2000, 1, 1, hour, minute);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m $ampm';
}

String _formatUtcTimeAsLocal(int minute, int hour) {
  final d = DateTime.utc(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    hour,
    minute,
  ).toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour >= 12 ? 'PM' : 'AM';
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m $ampm';
}

/// Convert a cron expression to a human-readable string.
/// Covers common patterns; falls through to the raw cron string for anything
/// else.
///
/// The [utc] option exists for remote triggers which run on servers and always
/// use UTC cron strings -- that path translates UTC -> local for display.
String cronToHuman(String cron, {bool utc = false}) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return cron;

  final minute = parts[0];
  final hour = parts[1];
  final dayOfMonth = parts[2];
  final month = parts[3];
  final dayOfWeek = parts[4];

  // Every N minutes: */N * * * *
  final everyMinMatch = RegExp(r'^\*/(\d+)$').firstMatch(minute);
  if (everyMinMatch != null &&
      hour == '*' &&
      dayOfMonth == '*' &&
      month == '*' &&
      dayOfWeek == '*') {
    final n = int.parse(everyMinMatch.group(1)!);
    return n == 1 ? 'Every minute' : 'Every $n minutes';
  }

  // Every hour: N * * * *
  if (RegExp(r'^\d+$').hasMatch(minute) &&
      hour == '*' &&
      dayOfMonth == '*' &&
      month == '*' &&
      dayOfWeek == '*') {
    final m = int.parse(minute);
    if (m == 0) return 'Every hour';
    return 'Every hour at :${m.toString().padLeft(2, '0')}';
  }

  // Every N hours: M */N * * *
  final everyHourMatch = RegExp(r'^\*/(\d+)$').firstMatch(hour);
  if (RegExp(r'^\d+$').hasMatch(minute) &&
      everyHourMatch != null &&
      dayOfMonth == '*' &&
      month == '*' &&
      dayOfWeek == '*') {
    final n = int.parse(everyHourMatch.group(1)!);
    final m = int.parse(minute);
    final suffix = m == 0 ? '' : ' at :${m.toString().padLeft(2, '0')}';
    return n == 1 ? 'Every hour$suffix' : 'Every $n hours$suffix';
  }

  // Remaining cases reference hour+minute.
  if (!RegExp(r'^\d+$').hasMatch(minute) ||
      !RegExp(r'^\d+$').hasMatch(hour)) {
    return cron;
  }
  final m = int.parse(minute);
  final h = int.parse(hour);
  final fmtTime = utc ? _formatUtcTimeAsLocal : _formatLocalTime;

  // Daily at specific time: M H * * *
  if (dayOfMonth == '*' && month == '*' && dayOfWeek == '*') {
    return 'Every day at ${fmtTime(m, h)}';
  }

  // Specific day of week: M H * * D
  if (dayOfMonth == '*' && month == '*' && RegExp(r'^\d$').hasMatch(dayOfWeek)) {
    final dayIndex = int.parse(dayOfWeek) % 7;
    String? dayName;
    if (utc) {
      final ref = DateTime.now().toUtc();
      final daysToAdd = (dayIndex - (ref.weekday % 7) + 7) % 7;
      final target = ref.add(Duration(days: daysToAdd));
      final local = DateTime.utc(
        target.year,
        target.month,
        target.day,
        h,
        m,
      ).toLocal();
      dayName = _dayNames[local.weekday % 7];
    } else {
      dayName = _dayNames[dayIndex];
    }
    if (dayName != null) return 'Every $dayName at ${fmtTime(m, h)}';
  }

  // Weekdays: M H * * 1-5
  if (dayOfMonth == '*' && month == '*' && dayOfWeek == '1-5') {
    return 'Weekdays at ${fmtTime(m, h)}';
  }

  return cron;
}

// ============================================================================
// Part 2: Cron tasks (from cronTasks.ts)
// ============================================================================

/// A scheduled cron task.
class CronTask {
  final String id;

  /// 5-field cron string (local time) -- validated on write, re-validated on
  /// read.
  final String cron;

  /// Prompt to enqueue when the task fires.
  final String prompt;

  /// Epoch ms when the task was created. Anchor for missed-task detection.
  final int createdAt;

  /// Epoch ms of the most recent fire. Written back by the scheduler after
  /// each recurring fire so next-fire computation survives process restarts.
  int? lastFiredAt;

  /// When true, the task reschedules after firing instead of being deleted.
  final bool recurring;

  /// When true, the task is exempt from recurringMaxAgeMs auto-expiry.
  final bool permanent;

  /// Runtime-only flag. false -> session-scoped (never written to disk).
  final bool? durable;

  /// Runtime-only. When set, the task was created by an in-process teammate.
  final String? agentId;

  CronTask({
    required this.id,
    required this.cron,
    required this.prompt,
    required this.createdAt,
    this.lastFiredAt,
    this.recurring = false,
    this.permanent = false,
    this.durable,
    this.agentId,
  });

  factory CronTask.fromJson(Map<String, dynamic> json) => CronTask(
        id: json['id'] as String,
        cron: json['cron'] as String,
        prompt: json['prompt'] as String,
        createdAt: json['createdAt'] as int,
        lastFiredAt: json['lastFiredAt'] as int?,
        recurring: json['recurring'] as bool? ?? false,
        permanent: json['permanent'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'cron': cron,
        'prompt': prompt,
        'createdAt': createdAt,
        if (lastFiredAt != null) 'lastFiredAt': lastFiredAt,
        if (recurring) 'recurring': true,
        if (permanent) 'permanent': true,
        // durable and agentId are runtime-only, not persisted.
      };

  CronTask copyWith({
    String? id,
    String? cron,
    String? prompt,
    int? createdAt,
    int? lastFiredAt,
    bool? recurring,
    bool? permanent,
    bool? durable,
    String? agentId,
  }) =>
      CronTask(
        id: id ?? this.id,
        cron: cron ?? this.cron,
        prompt: prompt ?? this.prompt,
        createdAt: createdAt ?? this.createdAt,
        lastFiredAt: lastFiredAt ?? this.lastFiredAt,
        recurring: recurring ?? this.recurring,
        permanent: permanent ?? this.permanent,
        durable: durable ?? this.durable,
        agentId: agentId ?? this.agentId,
      );
}

/// Cron file JSON shape.
class _CronFile {
  final List<CronTask> tasks;
  const _CronFile({required this.tasks});
}

const String _cronFileRel = '.neomclaw/scheduled_tasks.json';

/// Path to the cron file. [dir] defaults to the project root.
String getCronFilePath({String? dir}) {
  final base = dir ?? Directory.current.path;
  return p.join(base, _cronFileRel);
}

/// Read and parse .neomclaw/scheduled_tasks.json. Returns an empty task list if
/// the file is missing, empty, or malformed. Tasks with invalid cron strings
/// are silently dropped.
Future<List<CronTask>> readCronTasks({String? dir}) async {
  final path = getCronFilePath(dir: dir);
  final file = File(path);

  String raw;
  try {
    raw = await file.readAsString();
  } catch (e) {
    return [];
  }

  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return [];
  }

  if (parsed is! Map<String, dynamic>) return [];
  final tasks = parsed['tasks'];
  if (tasks is! List) return [];

  final out = <CronTask>[];
  for (final t in tasks) {
    if (t is! Map<String, dynamic>) continue;
    if (t['id'] is! String ||
        t['cron'] is! String ||
        t['prompt'] is! String ||
        t['createdAt'] is! num) {
      continue;
    }
    final cronStr = t['cron'] as String;
    if (parseCronExpression(cronStr) == null) {
      continue;
    }
    out.add(CronTask.fromJson(t));
  }
  return out;
}

/// Sync check for whether the cron file has any valid tasks.
bool hasCronTasksSync({String? dir}) {
  final path = getCronFilePath(dir: dir);
  final file = File(path);
  String raw;
  try {
    raw = file.readAsStringSync();
  } catch (_) {
    return false;
  }
  dynamic parsed;
  try {
    parsed = jsonDecode(raw);
  } catch (_) {
    return false;
  }
  if (parsed is! Map<String, dynamic>) return false;
  final tasks = parsed['tasks'];
  return tasks is List && tasks.isNotEmpty;
}

/// Overwrite .neomclaw/scheduled_tasks.json with the given tasks. Creates
/// .neomclaw/ if missing.
Future<void> writeCronTasks(List<CronTask> tasks, {String? dir}) async {
  final root = dir ?? Directory.current.path;
  final neomClawDir = Directory(p.join(root, '.neomclaw'));
  if (!neomClawDir.existsSync()) {
    await neomClawDir.create(recursive: true);
  }
  final body = {
    'tasks': tasks.map((t) => t.toJson()).toList(),
  };
  await File(getCronFilePath(dir: root))
      .writeAsString('${const JsonEncoder.withIndent('  ').convert(body)}\n');
}

/// Append a task. Returns the generated id.
///
/// When [durable] is false the task is held in process memory only -- it fires
/// on schedule this session but is never written to .neomclaw/scheduled_tasks.json.
Future<String> addCronTask({
  required String cron,
  required String prompt,
  required bool recurring,
  required bool durable,
  String? agentId,
  List<CronTask>? sessionTasks,
}) async {
  // Short ID -- 8 hex chars.
  final random = Random.secure();
  final id = List.generate(8, (_) => random.nextInt(16).toRadixString(16))
      .join();

  final task = CronTask(
    id: id,
    cron: cron,
    prompt: prompt,
    createdAt: DateTime.now().millisecondsSinceEpoch,
    recurring: recurring,
  );

  if (!durable) {
    final taskWithAgent = agentId != null
        ? task.copyWith(agentId: agentId, durable: false)
        : task.copyWith(durable: false);
    sessionTasks?.add(taskWithAgent);
    return id;
  }

  final tasks = await readCronTasks();
  tasks.add(task);
  await writeCronTasks(tasks);
  return id;
}

/// Remove tasks by id. No-op if none match.
Future<void> removeCronTasks(
  List<String> ids, {
  String? dir,
  List<CronTask>? sessionTasks,
}) async {
  if (ids.isEmpty) return;

  // Sweep session store first.
  if (dir == null && sessionTasks != null) {
    final idSet = ids.toSet();
    final removedCount =
        sessionTasks.where((t) => idSet.contains(t.id)).length;
    sessionTasks.removeWhere((t) => idSet.contains(t.id));
    if (removedCount == ids.length) return;
  }

  final idSet = ids.toSet();
  final tasks = await readCronTasks(dir: dir);
  final remaining = tasks.where((t) => !idSet.contains(t.id)).toList();
  if (remaining.length == tasks.length) return;
  await writeCronTasks(remaining, dir: dir);
}

/// Stamp `lastFiredAt` on the given recurring tasks and write back.
Future<void> markCronTasksFired(
  List<String> ids,
  int firedAt, {
  String? dir,
}) async {
  if (ids.isEmpty) return;
  final idSet = ids.toSet();
  final tasks = await readCronTasks(dir: dir);
  bool changed = false;
  for (final t in tasks) {
    if (idSet.contains(t.id)) {
      t.lastFiredAt = firedAt;
      changed = true;
    }
  }
  if (!changed) return;
  await writeCronTasks(tasks, dir: dir);
}

/// File-backed tasks + session-only tasks, merged.
Future<List<CronTask>> listAllCronTasks({
  String? dir,
  List<CronTask>? sessionTasks,
}) async {
  final fileTasks = await readCronTasks(dir: dir);
  if (dir != null) return fileTasks;
  final session = (sessionTasks ?? [])
      .map((t) => t.copyWith(durable: false))
      .toList();
  return [...fileTasks, ...session];
}

/// Next fire time in epoch ms for a cron string, strictly after [fromMs].
/// Returns null if invalid or no match in the next 366 days.
int? nextCronRunMs(String cron, int fromMs) {
  final fields = parseCronExpression(cron);
  if (fields == null) return null;
  final next = computeNextCronRun(
    fields,
    DateTime.fromMillisecondsSinceEpoch(fromMs),
  );
  return next?.millisecondsSinceEpoch;
}

/// A task is "missed" when its next scheduled run (computed from createdAt)
/// is in the past.
List<CronTask> findMissedTasks(List<CronTask> tasks, int nowMs) {
  return tasks.where((t) {
    final next = nextCronRunMs(t.cron, t.createdAt);
    return next != null && next < nowMs;
  }).toList();
}

// ============================================================================
// Part 3: Cron jitter config (from cronJitterConfig.ts + cronTasks.ts)
// ============================================================================

/// Cron scheduler tuning knobs.
class CronJitterConfig {
  /// Recurring-task forward delay as a fraction of the interval between fires.
  final double recurringFrac;

  /// Upper bound on recurring forward delay regardless of interval length.
  final int recurringCapMs;

  /// One-shot backward lead: maximum ms a task may fire early.
  final int oneShotMaxMs;

  /// One-shot backward lead: minimum ms a task fires early when the minute-mod
  /// gate matches.
  final int oneShotFloorMs;

  /// Jitter fires landing on minutes where `minute % N == 0`.
  final int oneShotMinuteMod;

  /// Recurring tasks auto-expire this many ms after creation (unless marked
  /// permanent). 0 = unlimited.
  final int recurringMaxAgeMs;

  const CronJitterConfig({
    required this.recurringFrac,
    required this.recurringCapMs,
    required this.oneShotMaxMs,
    required this.oneShotFloorMs,
    required this.oneShotMinuteMod,
    required this.recurringMaxAgeMs,
  });
}

/// Default jitter config.
const CronJitterConfig kDefaultCronJitterConfig = CronJitterConfig(
  recurringFrac: 0.1,
  recurringCapMs: 15 * 60 * 1000,          // 15 minutes
  oneShotMaxMs: 90 * 1000,                  // 90 seconds
  oneShotFloorMs: 0,
  oneShotMinuteMod: 30,
  recurringMaxAgeMs: 7 * 24 * 60 * 60 * 1000, // 7 days
);

/// taskId is an 8-hex-char UUID slice -> parse as u32 -> [0, 1). Stable
/// across restarts, uniformly distributed.
double _jitterFrac(String taskId) {
  final hex = taskId.length >= 8 ? taskId.substring(0, 8) : taskId;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return 0;
  final frac = value / 0x100000000;
  return frac.isFinite ? frac : 0;
}

/// Same as [nextCronRunMs], plus a deterministic per-task delay to avoid a
/// thundering herd when many sessions schedule the same cron string.
///
/// Only used for recurring tasks.
int? jitteredNextCronRunMs(
  String cron,
  int fromMs,
  String taskId, [
  CronJitterConfig cfg = kDefaultCronJitterConfig,
]) {
  final t1 = nextCronRunMs(cron, fromMs);
  if (t1 == null) return null;
  final t2 = nextCronRunMs(cron, t1);
  if (t2 == null) return t1;
  final jitter = min(
    _jitterFrac(taskId) * cfg.recurringFrac * (t2 - t1),
    cfg.recurringCapMs.toDouble(),
  );
  return t1 + jitter.round();
}

/// Same as [nextCronRunMs], minus a deterministic per-task lead time when the
/// fire time lands on a minute boundary matching [CronJitterConfig.oneShotMinuteMod].
///
/// One-shot tasks are user-pinned so delaying them breaks the contract, but
/// firing slightly early is invisible and spreads the inference spike.
int? oneShotJitteredNextCronRunMs(
  String cron,
  int fromMs,
  String taskId, [
  CronJitterConfig cfg = kDefaultCronJitterConfig,
]) {
  final t1 = nextCronRunMs(cron, fromMs);
  if (t1 == null) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(t1);
  if (dt.minute % cfg.oneShotMinuteMod != 0) return t1;
  final lead = cfg.oneShotFloorMs +
      _jitterFrac(taskId) * (cfg.oneShotMaxMs - cfg.oneShotFloorMs);
  return max(t1 - lead.round(), fromMs);
}

// ============================================================================
// Part 4: Scheduler lock (from cronTasksLock.ts)
// ============================================================================

const String _lockFileRel = '.neomclaw/scheduled_tasks.lock';

/// Scheduler lock data.
class SchedulerLock {
  final String sessionId;
  final int pid;
  final int acquiredAt;

  const SchedulerLock({
    required this.sessionId,
    required this.pid,
    required this.acquiredAt,
  });

  factory SchedulerLock.fromJson(Map<String, dynamic> json) => SchedulerLock(
        sessionId: json['sessionId'] as String,
        pid: json['pid'] as int,
        acquiredAt: json['acquiredAt'] as int,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'pid': pid,
        'acquiredAt': acquiredAt,
      };
}

/// Options for out-of-REPL callers that don't have bootstrap state.
class SchedulerLockOptions {
  final String? dir;
  final String? lockIdentity;

  const SchedulerLockOptions({this.dir, this.lockIdentity});
}

/// Module-level state for lock management.
String? _lastBlockedBy;

String _getLockPath({String? dir}) {
  final base = dir ?? Directory.current.path;
  return p.join(base, _lockFileRel);
}

Future<SchedulerLock?> _readLock({String? dir}) async {
  final path = _getLockPath(dir: dir);
  final file = File(path);
  String raw;
  try {
    raw = await file.readAsString();
  } catch (_) {
    return null;
  }
  try {
    final parsed = jsonDecode(raw);
    if (parsed is! Map<String, dynamic>) return null;
    return SchedulerLock.fromJson(parsed);
  } catch (_) {
    return null;
  }
}

/// Try to create the lock file exclusively (atomic test-and-set).
Future<bool> _tryCreateExclusive(
  SchedulerLock lock, {
  String? dir,
}) async {
  final path = _getLockPath(dir: dir);
  final file = File(path);
  final body = jsonEncode(lock.toJson());
  try {
    // O_EXCL equivalent: create only if it doesn't exist.
    if (file.existsSync()) return false;
    await file.writeAsString(body, flush: true);
    return true;
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == 17) return false; // EEXIST
    if (e.osError?.errorCode == 2) {
      // ENOENT: .neomclaw/ doesn't exist yet.
      await Directory(p.dirname(path)).create(recursive: true);
      try {
        if (file.existsSync()) return false;
        await file.writeAsString(body, flush: true);
        return true;
      } on FileSystemException catch (retryErr) {
        if (retryErr.osError?.errorCode == 17) return false;
        rethrow;
      }
    }
    rethrow;
  }
}

/// Check if a process with the given PID is running.
bool _isProcessRunning(int pid) {
  try {
    // On Unix, sending signal 0 checks if process exists without killing it.
    return Process.killPid(pid, ProcessSignal.sigusr1) || true;
  } catch (_) {
    // If we can't send the signal, process is likely not running.
    // Use a try-catch around a more reliable method.
    try {
      final result = Process.runSync('kill', ['-0', pid.toString()]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}

/// Try to acquire the scheduler lock for the current session.
/// Returns true on success, false if another live session holds it.
///
/// Uses exclusive create for atomic test-and-set. If the file exists:
///   - Already ours -> true (idempotent re-acquire)
///   - Another live PID -> false
///   - Stale (PID dead / corrupt) -> unlink and retry once
Future<bool> tryAcquireSchedulerLock({
  SchedulerLockOptions? opts,
  String? sessionId,
}) async {
  final dir = opts?.dir;
  final identity = opts?.lockIdentity ?? sessionId ?? 'unknown';
  final lock = SchedulerLock(
    sessionId: identity,
    pid: pid,
    acquiredAt: DateTime.now().millisecondsSinceEpoch,
  );

  if (await _tryCreateExclusive(lock, dir: dir)) {
    _lastBlockedBy = null;
    return true;
  }

  final existing = await _readLock(dir: dir);

  // Already ours (idempotent).
  if (existing?.sessionId == identity) {
    if (existing!.pid != pid) {
      await File(_getLockPath(dir: dir))
          .writeAsString(jsonEncode(lock.toJson()));
    }
    return true;
  }

  // Another live session -- blocked.
  if (existing != null && _isProcessRunning(existing.pid)) {
    if (_lastBlockedBy != existing.sessionId) {
      _lastBlockedBy = existing.sessionId;
    }
    return false;
  }

  // Stale -- unlink and retry once.
  try {
    await File(_getLockPath(dir: dir)).delete();
  } catch (_) {}
  if (await _tryCreateExclusive(lock, dir: dir)) {
    _lastBlockedBy = null;
    return true;
  }
  // Another session won the recovery race.
  return false;
}

/// Release the scheduler lock if the current session owns it.
Future<void> releaseSchedulerLock({
  SchedulerLockOptions? opts,
  String? sessionId,
}) async {
  _lastBlockedBy = null;
  final dir = opts?.dir;
  final identity = opts?.lockIdentity ?? sessionId ?? 'unknown';
  final existing = await _readLock(dir: dir);
  if (existing == null || existing.sessionId != identity) return;
  try {
    await File(_getLockPath(dir: dir)).delete();
  } catch (_) {
    // Already gone.
  }
}

// ============================================================================
// Part 5: Cron scheduler (from cronScheduler.ts)
// ============================================================================

/// Check interval for the scheduler timer.
const int kCheckIntervalMs = 1000;

/// File stability threshold for watcher debouncing.
const int kFileStabilityMs = 300;

/// How often a non-owning session re-probes the scheduler lock.
const int kLockProbeIntervalMs = 5000;

/// True when a recurring task was created more than [maxAgeMs] ago and should
/// be deleted on its next fire.
bool isRecurringTaskAged(CronTask t, int nowMs, int maxAgeMs) {
  if (maxAgeMs == 0) return false;
  return t.recurring && !t.permanent && nowMs - t.createdAt >= maxAgeMs;
}

/// Options for creating a cron scheduler.
class CronSchedulerOptions {
  /// Called when a task fires (regular or missed-on-startup).
  final void Function(String prompt) onFire;

  /// While true, firing is deferred to the next tick.
  final bool Function() isLoading;

  /// When true, bypasses the isLoading gate and auto-enables the scheduler.
  final bool assistantMode;

  /// When provided, receives the full CronTask on normal fires (and onFire is
  /// NOT called for that fire).
  final void Function(CronTask task)? onFireTask;

  /// When provided, receives the missed one-shot tasks on initial load.
  final void Function(List<CronTask> tasks)? onMissed;

  /// Directory containing .neomclaw/scheduled_tasks.json.
  final String? dir;

  /// Owner key written into the lock file.
  final String? lockIdentity;

  /// Returns the cron jitter config to use for this tick.
  final CronJitterConfig Function()? getJitterConfig;

  /// Killswitch: polled once per check() tick.
  final bool Function()? isKilled;

  /// Per-task gate applied before any side effect.
  final bool Function(CronTask t)? filter;

  const CronSchedulerOptions({
    required this.onFire,
    required this.isLoading,
    this.assistantMode = false,
    this.onFireTask,
    this.onMissed,
    this.dir,
    this.lockIdentity,
    this.getJitterConfig,
    this.isKilled,
    this.filter,
  });
}

/// A running cron scheduler.
class CronScheduler {
  final CronSchedulerOptions _options;

  List<CronTask> _tasks = [];
  final Map<String, int> _nextFireAt = {};
  final Set<String> _missedAsked = {};
  final Set<String> _inFlight = {};

  Timer? _enablePoll;
  Timer? _checkTimer;
  Timer? _lockProbeTimer;
  // File watcher would be StreamSubscription in Dart.
  StreamSubscription<FileSystemEvent>? _watcher;

  bool _stopped = false;
  bool _isOwner = false;

  /// Session-scoped tasks (runtime-only, never written to disk).
  final List<CronTask> sessionTasks = [];

  /// External flag: whether scheduled tasks are enabled.
  bool _scheduledTasksEnabled = false;

  CronScheduler(this._options);

  /// Epoch ms of the soonest scheduled fire, or null if nothing is scheduled.
  int? get nextFireTime {
    int minVal = -1 >>> 1; // max int
    bool found = false;
    for (final t in _nextFireAt.values) {
      if (t < minVal) {
        minVal = t;
        found = true;
      }
    }
    return found && minVal < (-1 >>> 1) ? minVal : null;
  }

  /// Start the scheduler.
  void start() {
    _stopped = false;

    if (_options.dir != null) {
      _enable();
      return;
    }

    if (!_scheduledTasksEnabled &&
        (_options.assistantMode || hasCronTasksSync())) {
      _scheduledTasksEnabled = true;
    }

    if (_scheduledTasksEnabled) {
      _enable();
      return;
    }

    _enablePoll = Timer.periodic(
      const Duration(milliseconds: kCheckIntervalMs),
      (_) {
        if (_scheduledTasksEnabled) _enable();
      },
    );
  }

  /// Stop the scheduler.
  void stop() {
    _stopped = true;
    _enablePoll?.cancel();
    _enablePoll = null;
    _checkTimer?.cancel();
    _checkTimer = null;
    _lockProbeTimer?.cancel();
    _lockProbeTimer = null;
    _watcher?.cancel();
    _watcher = null;
    if (_isOwner) {
      _isOwner = false;
      releaseSchedulerLock(
        opts: _options.dir != null || _options.lockIdentity != null
            ? SchedulerLockOptions(
                dir: _options.dir,
                lockIdentity: _options.lockIdentity,
              )
            : null,
        sessionId: _options.lockIdentity,
      );
    }
  }

  /// Enable scheduled tasks externally.
  void setScheduledTasksEnabled(bool value) {
    _scheduledTasksEnabled = value;
  }

  Future<void> _enable() async {
    if (_stopped) return;
    _enablePoll?.cancel();
    _enablePoll = null;

    // Acquire the per-project scheduler lock.
    final lockOpts = _options.dir != null || _options.lockIdentity != null
        ? SchedulerLockOptions(
            dir: _options.dir,
            lockIdentity: _options.lockIdentity,
          )
        : null;

    try {
      _isOwner = await tryAcquireSchedulerLock(
        opts: lockOpts,
        sessionId: _options.lockIdentity,
      );
    } catch (_) {
      _isOwner = false;
    }

    if (_stopped) {
      if (_isOwner) {
        _isOwner = false;
        await releaseSchedulerLock(
          opts: lockOpts,
          sessionId: _options.lockIdentity,
        );
      }
      return;
    }

    if (!_isOwner) {
      _lockProbeTimer = Timer.periodic(
        const Duration(milliseconds: kLockProbeIntervalMs),
        (_) async {
          try {
            final owned = await tryAcquireSchedulerLock(
              opts: lockOpts,
              sessionId: _options.lockIdentity,
            );
            if (_stopped) {
              if (owned) {
                await releaseSchedulerLock(
                  opts: lockOpts,
                  sessionId: _options.lockIdentity,
                );
              }
              return;
            }
            if (owned) {
              _isOwner = true;
              _lockProbeTimer?.cancel();
              _lockProbeTimer = null;
            }
          } catch (_) {}
        },
      );
    }

    await _load(initial: true);

    // Set up file watcher.
    final cronPath = getCronFilePath(dir: _options.dir);
    final cronFile = File(cronPath);
    try {
      final parentDir = cronFile.parent;
      if (parentDir.existsSync()) {
        _watcher = parentDir.watch().listen((event) {
          if (event.path == cronPath) {
            if (event.type == FileSystemEvent.delete) {
              if (!_stopped) {
                _tasks = [];
                _nextFireAt.clear();
              }
            } else {
              _load(initial: false);
            }
          }
        });
      }
    } catch (_) {
      // File watcher not available -- rely on timer.
    }

    _checkTimer = Timer.periodic(
      const Duration(milliseconds: kCheckIntervalMs),
      (_) => _check(),
    );
  }

  Future<void> _load({required bool initial}) async {
    final next = await readCronTasks(dir: _options.dir);
    if (_stopped) return;
    _tasks = next;

    if (!initial) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final missed = findMissedTasks(next, now)
        .where((t) =>
            !t.recurring &&
            !_missedAsked.contains(t.id) &&
            (_options.filter == null || _options.filter!(t)))
        .toList();

    if (missed.isNotEmpty) {
      for (final t in missed) {
        _missedAsked.add(t.id);
        _nextFireAt[t.id] = -1 >>> 1; // Infinity equivalent
      }

      if (_options.onMissed != null) {
        _options.onMissed!(missed);
      } else {
        _options.onFire(buildMissedTaskNotification(missed));
      }

      removeCronTasks(
        missed.map((t) => t.id).toList(),
        dir: _options.dir,
      ).catchError((_) {});
    }
  }

  void _check() {
    if (_options.isKilled?.call() == true) return;
    if (_options.isLoading() && !_options.assistantMode) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final seen = <String>{};
    final firedFileRecurring = <String>[];
    final jitterCfg =
        _options.getJitterConfig?.call() ?? kDefaultCronJitterConfig;

    void process(CronTask t, bool isSession) {
      if (_options.filter != null && !_options.filter!(t)) return;
      seen.add(t.id);
      if (_inFlight.contains(t.id)) return;

      var next = _nextFireAt[t.id];
      if (next == null) {
        next = t.recurring
            ? (jitteredNextCronRunMs(
                    t.cron, t.lastFiredAt ?? t.createdAt, t.id, jitterCfg) ??
                (-1 >>> 1))
            : (oneShotJitteredNextCronRunMs(
                    t.cron, t.createdAt, t.id, jitterCfg) ??
                (-1 >>> 1));
        _nextFireAt[t.id] = next;
      }

      if (now < next) return;

      // Fire!
      if (_options.onFireTask != null) {
        _options.onFireTask!(t);
      } else {
        _options.onFire(t.prompt);
      }

      final aged = isRecurringTaskAged(t, now, jitterCfg.recurringMaxAgeMs);

      if (t.recurring && !aged) {
        final newNext =
            jitteredNextCronRunMs(t.cron, now, t.id, jitterCfg) ??
                (-1 >>> 1);
        _nextFireAt[t.id] = newNext;
        if (!isSession) firedFileRecurring.add(t.id);
      } else if (isSession) {
        sessionTasks.removeWhere((s) => s.id == t.id);
        _nextFireAt.remove(t.id);
      } else {
        _inFlight.add(t.id);
        removeCronTasks([t.id], dir: _options.dir).catchError((_) {}).then(
            (_) {
          _inFlight.remove(t.id);
        });
        _nextFireAt.remove(t.id);
      }
    }

    // File-backed tasks: only when we own the scheduler lock.
    if (_isOwner) {
      for (final t in _tasks) {
        process(t, false);
      }
      if (firedFileRecurring.isNotEmpty) {
        for (final id in firedFileRecurring) {
          _inFlight.add(id);
        }
        markCronTasksFired(firedFileRecurring, now, dir: _options.dir)
            .catchError((_) {})
            .then((_) {
          for (final id in firedFileRecurring) {
            _inFlight.remove(id);
          }
        });
      }
    }

    // Session-only tasks.
    if (_options.dir == null) {
      for (final t in List.of(sessionTasks)) {
        process(t, true);
      }
    }

    if (seen.isEmpty) {
      _nextFireAt.clear();
      return;
    }

    // Evict schedule entries for tasks no longer present.
    _nextFireAt.removeWhere((id, _) => !seen.contains(id));
  }
}

/// Build the missed-task notification text.
String buildMissedTaskNotification(List<CronTask> missed) {
  final plural = missed.length > 1;
  final header =
      'The following one-shot scheduled task${plural ? 's were' : ' was'} '
      'missed while NeomClaw was not running. '
      '${plural ? 'They have' : 'It has'} already been removed from '
      '.neomclaw/scheduled_tasks.json.\n\n'
      'Do NOT execute ${plural ? 'these prompts' : 'this prompt'} yet. '
      'First use the AskUserQuestion tool to ask whether to run '
      '${plural ? 'each one' : 'it'} now. '
      'Only execute if the user confirms.';

  final blocks = missed.map((t) {
    final meta =
        '[${cronToHuman(t.cron)}, created ${DateTime.fromMillisecondsSinceEpoch(t.createdAt)}]';
    // Use a fence one longer than any backtick run in the prompt.
    final longestRun = RegExp(r'`+')
        .allMatches(t.prompt)
        .fold(0, (maxVal, match) => max(maxVal, match.group(0)!.length));
    final fence = '`' * max(3, longestRun + 1);
    return '$meta\n$fence\n${t.prompt}\n$fence';
  }).toList();

  return '$header\n\n${blocks.join('\n\n')}';
}
