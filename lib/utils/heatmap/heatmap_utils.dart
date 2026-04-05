/// Heatmap generation, plan management, code indexing detection, and
/// transcript search utilities.
///
/// Ported from:
///   - heatmap.ts (198 LOC) -- GitHub-style activity heatmap
///   - plans.ts (397 LOC) -- plan file management and recovery
///   - codeIndexing.ts (206 LOC) -- code indexing tool detection
///   - transcriptSearch.ts (202 LOC) -- searchable text extraction
library;

import 'package:neomage/core/platform/neomage_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ===========================================================================
// Heatmap (ported from heatmap.ts)
// ===========================================================================

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Options for heatmap generation.
class HeatmapOptions {
  final int terminalWidth;
  final bool showMonthLabels;

  const HeatmapOptions({this.terminalWidth = 80, this.showMonthLabels = true});
}

/// Daily activity data point.
class DailyActivity {
  final String date;
  final int messageCount;

  const DailyActivity({required this.date, required this.messageCount});
}

/// Pre-calculated percentile thresholds.
class _Percentiles {
  final int p25;
  final int p50;
  final int p75;

  const _Percentiles({required this.p25, required this.p50, required this.p75});
}

// ---------------------------------------------------------------------------
// Heatmap Color (ANSI escape for Neomage orange #da7756)
// ---------------------------------------------------------------------------

/// Apply Neomage orange color to text using ANSI escape codes.
String _neomageOrange(String text) {
  // 24-bit ANSI color: RGB(218, 119, 86) = #da7756
  return '\x1B[38;2;218;119;86m$text\x1B[0m';
}

/// Apply gray color to text using ANSI escape codes.
String _gray(String text) {
  return '\x1B[90m$text\x1B[0m';
}

// ---------------------------------------------------------------------------
// Heatmap Functions
// ---------------------------------------------------------------------------

/// Pre-calculates percentiles from activity data for intensity calculations.
_Percentiles? _calculatePercentiles(List<DailyActivity> dailyActivity) {
  final counts =
      dailyActivity.map((a) => a.messageCount).where((c) => c > 0).toList()
        ..sort();

  if (counts.isEmpty) return null;

  return _Percentiles(
    p25: counts[(counts.length * 0.25).floor()],
    p50: counts[(counts.length * 0.5).floor()],
    p75: counts[(counts.length * 0.75).floor()],
  );
}

/// Determine intensity level based on message count and percentiles.
int _getIntensity(int messageCount, _Percentiles? percentiles) {
  if (messageCount == 0 || percentiles == null) return 0;

  if (messageCount >= percentiles.p75) return 4;
  if (messageCount >= percentiles.p50) return 3;
  if (messageCount >= percentiles.p25) return 2;
  return 1;
}

/// Get the heatmap character for a given intensity level.
String _getHeatmapChar(int intensity) {
  switch (intensity) {
    case 0:
      return _gray('\u00B7');
    case 1:
      return _neomageOrange('\u2591');
    case 2:
      return _neomageOrange('\u2592');
    case 3:
      return _neomageOrange('\u2593');
    case 4:
      return _neomageOrange('\u2588');
    default:
      return _gray('\u00B7');
  }
}

/// Convert a DateTime to a date string in YYYY-MM-DD format.
String _toDateString(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = (date.month).toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Generates a GitHub-style activity heatmap for the terminal.
String generateHeatmap(
  List<DailyActivity> dailyActivity, {
  HeatmapOptions options = const HeatmapOptions(),
}) {
  final terminalWidth = options.terminalWidth;
  final showMonthLabels = options.showMonthLabels;

  // Day labels take 4 characters, calculate weeks that fit.
  // Cap at 52 weeks (1 year) to match GitHub style.
  const dayLabelWidth = 4;
  final availableWidth = terminalWidth - dayLabelWidth;
  final width = min(52, max(10, availableWidth));

  // Build activity map by date
  final activityMap = <String, DailyActivity>{};
  for (final activity in dailyActivity) {
    activityMap[activity.date] = activity;
  }

  // Pre-calculate percentiles once
  final percentiles = _calculatePercentiles(dailyActivity);

  // Calculate date range -- end at today, go back N weeks
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);

  // Find the Sunday of the current week
  final currentWeekStart = todayDate.subtract(
    Duration(days: todayDate.weekday % 7),
  );

  // Go back (width - 1) weeks from the current week start
  final startDate = currentWeekStart.subtract(Duration(days: (width - 1) * 7));

  // Generate grid (7 rows for days of week, width columns for weeks)
  final grid = List.generate(7, (_) => List.filled(width, ''));
  final monthStarts = <({int month, int week})>[];
  int lastMonth = -1;

  var currentDate = startDate;
  for (int week = 0; week < width; week++) {
    for (int day = 0; day < 7; day++) {
      // Don't show future dates
      if (currentDate.isAfter(todayDate)) {
        grid[day][week] = ' ';
        currentDate = currentDate.add(const Duration(days: 1));
        continue;
      }

      final dateStr = _toDateString(currentDate);
      final activity = activityMap[dateStr];

      // Track month changes (on day 0 = Sunday of each week)
      if (day == 0) {
        final month = currentDate.month;
        if (month != lastMonth) {
          monthStarts.add((month: month, week: week));
          lastMonth = month;
        }
      }

      final intensity = _getIntensity(activity?.messageCount ?? 0, percentiles);
      grid[day][week] = _getHeatmapChar(intensity);

      currentDate = currentDate.add(const Duration(days: 1));
    }
  }

  // Build output
  final lines = <String>[];

  // Month labels
  if (showMonthLabels) {
    const monthNames = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final uniqueMonths = monthStarts.map((m) => m.month).toList();
    final labelWidth = (width / max(uniqueMonths.length, 1)).floor();
    final monthLabels = uniqueMonths
        .map((month) => monthNames[month - 1].padRight(labelWidth))
        .join('');

    lines.add('    $monthLabels');
  }

  // Day labels
  const dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  // Grid
  for (int day = 0; day < 7; day++) {
    final label = [1, 3, 5].contains(day) ? dayLabels[day].padRight(3) : '   ';
    final row = '$label ${grid[day].join('')}';
    lines.add(row);
  }

  // Legend
  lines.add('');
  lines.add(
    '    Less '
    '${_neomageOrange('\u2591')} '
    '${_neomageOrange('\u2592')} '
    '${_neomageOrange('\u2593')} '
    '${_neomageOrange('\u2588')} '
    'More',
  );

  return lines.join('\n');
}

// ===========================================================================
// Plans (ported from plans.ts)
// ===========================================================================

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A snapshot of a file persisted in the transcript.
class FileSnapshotEntry {
  final String key;
  final String path;
  final String content;

  const FileSnapshotEntry({
    required this.key,
    required this.path,
    required this.content,
  });
}

/// A message from the log for plan recovery.
class LogMessage {
  final String type;
  final String? subtype;
  final String? slug;
  final String? planContent;
  final Map<String, dynamic>? message;
  final Map<String, dynamic>? attachment;
  final List<FileSnapshotEntry>? snapshotFiles;

  const LogMessage({
    required this.type,
    this.subtype,
    this.slug,
    this.planContent,
    this.message,
    this.attachment,
    this.snapshotFiles,
  });
}

/// Log option with messages for plan restoration.
class LogOption {
  final List<LogMessage> messages;

  const LogOption({required this.messages});
}

// ---------------------------------------------------------------------------
// Plan Controller
// ---------------------------------------------------------------------------

const int _maxSlugRetries = 10;
const String _exitPlanModeV2ToolName = 'ExitPlanModeV2';

/// Controller for plan file management.
///
/// Manages plan slugs, plan file reading/writing, and plan recovery from
/// message history.
class PlanController extends SintController {
  /// Cache of session ID to plan slug.
  final Map<String, String> _planSlugCache = {};

  /// The plans directory path.
  final String plansDirectory;

  /// The config home directory.
  final String configHomeDir;

  /// The current working directory.
  final String cwd;

  /// Word slug generator function (injectable for testing).
  final String Function() _generateWordSlug;

  PlanController({
    required this.plansDirectory,
    required this.configHomeDir,
    required this.cwd,
    String Function()? generateWordSlug,
  }) : _generateWordSlug = generateWordSlug ?? _defaultWordSlug;

  static String _defaultWordSlug() {
    const words = [
      'alpha',
      'beta',
      'gamma',
      'delta',
      'echo',
      'foxtrot',
      'golf',
      'hotel',
      'india',
      'juliet',
      'kilo',
      'lima',
      'mike',
      'november',
      'oscar',
      'papa',
      'quebec',
      'romeo',
      'sierra',
      'tango',
      'uniform',
      'victor',
      'whiskey',
      'xray',
    ];
    final random = Random();
    return '${words[random.nextInt(words.length)]}-'
        '${words[random.nextInt(words.length)]}-'
        '${random.nextInt(999).toString().padLeft(3, '0')}';
  }

  /// Get or generate a word slug for the given session's plan.
  String getPlanSlug(String sessionId) {
    var slug = _planSlugCache[sessionId];
    if (slug == null) {
      for (int i = 0; i < _maxSlugRetries; i++) {
        slug = _generateWordSlug();
        final filePath = '$plansDirectory/$slug.md';
        if (!File(filePath).existsSync()) break;
      }
      _planSlugCache[sessionId] = slug!;
    }
    return slug;
  }

  /// Set a specific plan slug for a session (used when resuming).
  void setPlanSlug(String sessionId, String slug) {
    _planSlugCache[sessionId] = slug;
  }

  /// Clear the plan slug for the given session.
  void clearPlanSlug(String sessionId) {
    _planSlugCache.remove(sessionId);
  }

  /// Clear ALL plan slug entries (all sessions).
  void clearAllPlanSlugs() {
    _planSlugCache.clear();
  }

  /// Get the file path for a session's plan.
  ///
  /// For main conversation (no agentId), returns {planSlug}.md.
  /// For subagents (agentId provided), returns {planSlug}-agent-{agentId}.md.
  String getPlanFilePath({required String sessionId, String? agentId}) {
    final planSlug = getPlanSlug(sessionId);
    if (agentId == null) {
      return '$plansDirectory/$planSlug.md';
    }
    return '$plansDirectory/$planSlug-agent-$agentId.md';
  }

  /// Get the plan content for a session.
  String? getPlan({required String sessionId, String? agentId}) {
    final filePath = getPlanFilePath(sessionId: sessionId, agentId: agentId);
    try {
      return File(filePath).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Extract the plan slug from a log's message history.
  String? _getSlugFromLog(LogOption log) {
    for (final msg in log.messages) {
      if (msg.slug != null) return msg.slug;
    }
    return null;
  }

  /// Restore plan slug from a resumed session.
  ///
  /// Sets the slug in the session cache so getPlanSlug returns it.
  /// If the plan file is missing, attempts to recover it from a file snapshot
  /// or from message history. Returns true if a plan file exists (or was
  /// recovered) for the slug.
  Future<bool> copyPlanForResume({
    required LogOption log,
    required String targetSessionId,
    bool isRemoteSession = false,
  }) async {
    final slug = _getSlugFromLog(log);
    if (slug == null) return false;

    setPlanSlug(targetSessionId, slug);

    final planPath = '$plansDirectory/$slug.md';
    try {
      await File(planPath).readAsString();
      return true;
    } on FileSystemException {
      if (!isRemoteSession) return false;

      // Try file snapshot first
      final snapshotPlan = _findFileSnapshotEntry(log.messages, 'plan');
      String? recovered;
      if (snapshotPlan != null && snapshotPlan.content.isNotEmpty) {
        recovered = snapshotPlan.content;
      } else {
        recovered = _recoverPlanFromMessages(log);
      }

      if (recovered != null) {
        try {
          await File(planPath).writeAsString(recovered);
          return true;
        } catch (_) {
          return false;
        }
      }
      return false;
    }
  }

  /// Copy a plan file for a forked session.
  ///
  /// Unlike copyPlanForResume (which reuses the original slug), this generates
  /// a NEW slug for the forked session and writes the original plan content to
  /// the new file.
  Future<bool> copyPlanForFork({
    required LogOption log,
    required String targetSessionId,
  }) async {
    final originalSlug = _getSlugFromLog(log);
    if (originalSlug == null) return false;

    final originalPlanPath = '$plansDirectory/$originalSlug.md';
    final newSlug = getPlanSlug(targetSessionId);
    final newPlanPath = '$plansDirectory/$newSlug.md';

    try {
      await File(originalPlanPath).copy(newPlanPath);
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Recover plan content from the message history.
  ///
  /// Plan content can appear in three forms:
  /// 1. ExitPlanMode tool_use input
  /// 2. planContent field on user messages
  /// 3. plan_file_reference attachment
  String? _recoverPlanFromMessages(LogOption log) {
    for (int i = log.messages.length - 1; i >= 0; i--) {
      final msg = log.messages[i];

      if (msg.type == 'assistant') {
        final content = msg.message?['content'];
        if (content is List) {
          for (final block in content) {
            if (block is Map<String, dynamic> &&
                block['type'] == 'tool_use' &&
                block['name'] == _exitPlanModeV2ToolName) {
              final input = block['input'] as Map<String, dynamic>?;
              final plan = input?['plan'];
              if (plan is String && plan.isNotEmpty) return plan;
            }
          }
        }
      }

      if (msg.type == 'user' && msg.planContent != null) {
        if (msg.planContent!.isNotEmpty) return msg.planContent;
      }

      if (msg.type == 'attachment') {
        if (msg.attachment?['type'] == 'plan_file_reference') {
          final plan = msg.attachment?['planContent'];
          if (plan is String && plan.isNotEmpty) return plan;
        }
      }
    }
    return null;
  }

  /// Find a file entry in the most recent file-snapshot system message.
  FileSnapshotEntry? _findFileSnapshotEntry(
    List<LogMessage> messages,
    String key,
  ) {
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.type == 'system' &&
          msg.subtype == 'file_snapshot' &&
          msg.snapshotFiles != null) {
        return msg.snapshotFiles!.cast<FileSnapshotEntry?>().firstWhere(
          (f) => f?.key == key,
          orElse: () => null,
        );
      }
    }
    return null;
  }
}

// ===========================================================================
// Code Indexing (ported from codeIndexing.ts)
// ===========================================================================

/// Known code indexing tool identifiers.
enum CodeIndexingTool {
  sourcegraph,
  hound,
  seagoat,
  bloop,
  gitloop,
  cody,
  aider,
  continueAi,
  githubCopilot,
  cursor,
  tabby,
  codeium,
  tabnine,
  augment,
  windsurf,
  aide,
  pieces,
  qodo,
  amazonQ,
  gemini,
  neomageContext,
  codeIndexMcp,
  localCodeSearch,
  autodevCodebase,
  openctx,
}

/// Mapping of CLI command prefixes to code indexing tools.
const Map<String, CodeIndexingTool> _cliCommandMapping = {
  'src': CodeIndexingTool.sourcegraph,
  'cody': CodeIndexingTool.cody,
  'aider': CodeIndexingTool.aider,
  'tabby': CodeIndexingTool.tabby,
  'tabnine': CodeIndexingTool.tabnine,
  'augment': CodeIndexingTool.augment,
  'pieces': CodeIndexingTool.pieces,
  'qodo': CodeIndexingTool.qodo,
  'aide': CodeIndexingTool.aide,
  'hound': CodeIndexingTool.hound,
  'seagoat': CodeIndexingTool.seagoat,
  'bloop': CodeIndexingTool.bloop,
  'gitloop': CodeIndexingTool.gitloop,
  'q': CodeIndexingTool.amazonQ,
  'gemini': CodeIndexingTool.gemini,
};

/// MCP server name patterns for code indexing tool detection.
class _McpPattern {
  final RegExp pattern;
  final CodeIndexingTool tool;
  const _McpPattern(this.pattern, this.tool);
}

final List<_McpPattern> _mcpServerPatterns = [
  _McpPattern(
    RegExp(r'^sourcegraph$', caseSensitive: false),
    CodeIndexingTool.sourcegraph,
  ),
  _McpPattern(RegExp(r'^cody$', caseSensitive: false), CodeIndexingTool.cody),
  _McpPattern(
    RegExp(r'^openctx$', caseSensitive: false),
    CodeIndexingTool.openctx,
  ),
  _McpPattern(RegExp(r'^aider$', caseSensitive: false), CodeIndexingTool.aider),
  _McpPattern(
    RegExp(r'^continue$', caseSensitive: false),
    CodeIndexingTool.continueAi,
  ),
  _McpPattern(
    RegExp(r'^github[-_]?copilot$', caseSensitive: false),
    CodeIndexingTool.githubCopilot,
  ),
  _McpPattern(
    RegExp(r'^copilot$', caseSensitive: false),
    CodeIndexingTool.githubCopilot,
  ),
  _McpPattern(
    RegExp(r'^cursor$', caseSensitive: false),
    CodeIndexingTool.cursor,
  ),
  _McpPattern(RegExp(r'^tabby$', caseSensitive: false), CodeIndexingTool.tabby),
  _McpPattern(
    RegExp(r'^codeium$', caseSensitive: false),
    CodeIndexingTool.codeium,
  ),
  _McpPattern(
    RegExp(r'^tabnine$', caseSensitive: false),
    CodeIndexingTool.tabnine,
  ),
  _McpPattern(
    RegExp(r'^augment[-_]?code$', caseSensitive: false),
    CodeIndexingTool.augment,
  ),
  _McpPattern(
    RegExp(r'^augment$', caseSensitive: false),
    CodeIndexingTool.augment,
  ),
  _McpPattern(
    RegExp(r'^windsurf$', caseSensitive: false),
    CodeIndexingTool.windsurf,
  ),
  _McpPattern(RegExp(r'^aide$', caseSensitive: false), CodeIndexingTool.aide),
  _McpPattern(
    RegExp(r'^codestory$', caseSensitive: false),
    CodeIndexingTool.aide,
  ),
  _McpPattern(
    RegExp(r'^pieces$', caseSensitive: false),
    CodeIndexingTool.pieces,
  ),
  _McpPattern(RegExp(r'^qodo$', caseSensitive: false), CodeIndexingTool.qodo),
  _McpPattern(
    RegExp(r'^amazon[-_]?q$', caseSensitive: false),
    CodeIndexingTool.amazonQ,
  ),
  _McpPattern(
    RegExp(r'^gemini[-_]?code[-_]?assist$', caseSensitive: false),
    CodeIndexingTool.gemini,
  ),
  _McpPattern(
    RegExp(r'^gemini$', caseSensitive: false),
    CodeIndexingTool.gemini,
  ),
  _McpPattern(RegExp(r'^hound$', caseSensitive: false), CodeIndexingTool.hound),
  _McpPattern(
    RegExp(r'^seagoat$', caseSensitive: false),
    CodeIndexingTool.seagoat,
  ),
  _McpPattern(RegExp(r'^bloop$', caseSensitive: false), CodeIndexingTool.bloop),
  _McpPattern(
    RegExp(r'^gitloop$', caseSensitive: false),
    CodeIndexingTool.gitloop,
  ),
  _McpPattern(
    RegExp(r'^claude[-_]?context$', caseSensitive: false),
    CodeIndexingTool.neomageContext,
  ),
  _McpPattern(
    RegExp(r'^code[-_]?index[-_]?mcp$', caseSensitive: false),
    CodeIndexingTool.codeIndexMcp,
  ),
  _McpPattern(
    RegExp(r'^code[-_]?index$', caseSensitive: false),
    CodeIndexingTool.codeIndexMcp,
  ),
  _McpPattern(
    RegExp(r'^local[-_]?code[-_]?search$', caseSensitive: false),
    CodeIndexingTool.localCodeSearch,
  ),
  _McpPattern(
    RegExp(r'^codebase$', caseSensitive: false),
    CodeIndexingTool.autodevCodebase,
  ),
  _McpPattern(
    RegExp(r'^autodev[-_]?codebase$', caseSensitive: false),
    CodeIndexingTool.autodevCodebase,
  ),
  _McpPattern(
    RegExp(r'^code[-_]?context$', caseSensitive: false),
    CodeIndexingTool.neomageContext,
  ),
];

/// Detects if a bash command is using a code indexing CLI tool.
///
/// Returns the code indexing tool identifier, or null if not a code indexing
/// command.
CodeIndexingTool? detectCodeIndexingFromCommand(String command) {
  final trimmed = command.trim();
  final firstWord = trimmed.split(RegExp(r'\s+')).firstOrNull?.toLowerCase();

  if (firstWord == null) return null;

  // Check for npx/bunx prefixed commands
  if (firstWord == 'npx' || firstWord == 'bunx') {
    final words = trimmed.split(RegExp(r'\s+'));
    final secondWord = words.length > 1 ? words[1].toLowerCase() : null;
    if (secondWord != null && _cliCommandMapping.containsKey(secondWord)) {
      return _cliCommandMapping[secondWord];
    }
  }

  return _cliCommandMapping[firstWord];
}

/// Detects if an MCP tool is from a code indexing server.
///
/// MCP tool names follow the format: mcp__serverName__toolName.
CodeIndexingTool? detectCodeIndexingFromMcpTool(String toolName) {
  if (!toolName.startsWith('mcp__')) return null;

  final parts = toolName.split('__');
  if (parts.length < 3) return null;

  final serverName = parts[1];
  if (serverName.isEmpty) return null;

  for (final entry in _mcpServerPatterns) {
    if (entry.pattern.hasMatch(serverName)) {
      return entry.tool;
    }
  }

  return null;
}

/// Detects if an MCP server name corresponds to a code indexing tool.
CodeIndexingTool? detectCodeIndexingFromMcpServerName(String serverName) {
  for (final entry in _mcpServerPatterns) {
    if (entry.pattern.hasMatch(serverName)) {
      return entry.tool;
    }
  }
  return null;
}

// ===========================================================================
// Transcript Search (ported from transcriptSearch.ts)
// ===========================================================================

/// Interrupt message sentinel values.
const String interruptMessage = 'Interrupted by user';
const String interruptMessageForToolUse2 =
    'The user has interrupted the tool use.';

const String _systemReminderClose = '</system-reminder>';

/// Messages that are rendered as a sentinel (InterruptedByUser).
/// Raw text never appears on screen; searching it yields phantom matches.
final Set<String> _renderedAsSentinel = {
  interruptMessage,
  interruptMessageForToolUse2,
};

/// Cache for computed search text. Uses Expando (Dart's WeakMap equivalent).
final Expando<String> _searchTextCache = Expando<String>('searchTextCache');

/// A renderable message for transcript search.
class RenderableMessage {
  final String type;
  final Map<String, dynamic>? message;
  final dynamic toolUseResult;
  final Map<String, dynamic>? attachment;
  final List<Map<String, dynamic>>? relevantMemories;

  const RenderableMessage({
    required this.type,
    this.message,
    this.toolUseResult,
    this.attachment,
    this.relevantMemories,
  });
}

/// Flatten a RenderableMessage to lowercased searchable text.
///
/// Cached -- messages are append-only and immutable so a hit is always valid.
/// Lowercased at cache time.
String renderableSearchText(RenderableMessage msg) {
  final cached = _searchTextCache[msg];
  if (cached != null) return cached;
  final result = _computeSearchText(msg).toLowerCase();
  _searchTextCache[msg] = result;
  return result;
}

String _computeSearchText(RenderableMessage msg) {
  String raw = '';

  switch (msg.type) {
    case 'user':
      final c = msg.message?['content'];
      if (c is String) {
        raw = _renderedAsSentinel.contains(c) ? '' : c;
      } else if (c is List) {
        final parts = <String>[];
        for (final b in c) {
          if (b is! Map<String, dynamic>) continue;
          if (b['type'] == 'text') {
            final text = b['text'] as String? ?? '';
            if (!_renderedAsSentinel.contains(text)) parts.add(text);
          } else if (b['type'] == 'tool_result') {
            parts.add(toolResultSearchText(msg.toolUseResult));
          }
        }
        raw = parts.join('\n');
      }
      break;

    case 'assistant':
      final c = msg.message?['content'];
      if (c is List) {
        raw = c
            .whereType<Map<String, dynamic>>()
            .expand((b) {
              if (b['type'] == 'text') return [b['text'] as String? ?? ''];
              if (b['type'] == 'tool_use') {
                return [toolUseSearchText(b['input'])];
              }
              return <String>[];
            })
            .join('\n');
      }
      break;

    case 'attachment':
      if (msg.attachment?['type'] == 'relevant_memories') {
        final memories = msg.attachment?['memories'] as List?;
        if (memories != null) {
          raw = memories
              .whereType<Map<String, dynamic>>()
              .map((m) => m['content'] as String? ?? '')
              .join('\n');
        }
      } else if (msg.attachment?['type'] == 'queued_command' &&
          msg.attachment?['commandMode'] != 'task-notification' &&
          msg.attachment?['isMeta'] != true) {
        final p = msg.attachment?['prompt'];
        if (p is String) {
          raw = p;
        } else if (p is List) {
          raw = p
              .whereType<Map<String, dynamic>>()
              .where((b) => b['type'] == 'text')
              .map((b) => b['text'] as String? ?? '')
              .join('\n');
        }
      }
      break;

    case 'collapsed_read_search':
      if (msg.relevantMemories != null) {
        raw = msg.relevantMemories!
            .map((m) => m['content'] as String? ?? '')
            .join('\n');
      }
      break;

    default:
      break;
  }

  // Strip <system-reminder> blocks
  var t = raw;
  var open = t.indexOf('<system-reminder>');
  while (open >= 0) {
    final close = t.indexOf(_systemReminderClose, open);
    if (close < 0) break;
    t = t.substring(0, open) + t.substring(close + _systemReminderClose.length);
    open = t.indexOf('<system-reminder>');
  }
  return t;
}

/// Extract searchable text from a tool_use input.
///
/// renderToolUseMessage shows input fields like command (Bash), pattern (Grep),
/// file_path (Read/Edit), prompt (Agent).
String toolUseSearchText(dynamic input) {
  if (input == null || input is! Map<String, dynamic>) return '';

  final parts = <String>[];

  // Primary argument fields
  for (final k in [
    'command',
    'pattern',
    'file_path',
    'path',
    'prompt',
    'description',
    'query',
    'url',
    'skill',
  ]) {
    final v = input[k];
    if (v is String) parts.add(v);
  }

  // Array fields (args, files)
  for (final k in ['args', 'files']) {
    final v = input[k];
    if (v is List && v.every((x) => x is String)) {
      parts.add((v as List<String>).join(' '));
    }
  }

  return parts.join('\n');
}

/// Duck-type the tool's native Out for searchable text.
///
/// Known shapes: {stdout,stderr} (Bash), {content} (Grep),
/// {file:{content}} (Read), {filenames:[]} (Grep/Glob), {output} (generic).
String toolResultSearchText(dynamic r) {
  if (r == null) return '';
  if (r is String) return r;
  if (r is! Map<String, dynamic>) return '';

  // Known shapes first
  if (r['stdout'] is String) {
    final err = r['stderr'] is String ? r['stderr'] as String : '';
    return '${r['stdout']}${err.isNotEmpty ? '\n$err' : ''}';
  }

  if (r['file'] is Map<String, dynamic>) {
    final content = (r['file'] as Map<String, dynamic>)['content'];
    if (content is String) return content;
  }

  // Known output-field names only
  final parts = <String>[];
  for (final k in ['content', 'output', 'result', 'text', 'message']) {
    final v = r[k];
    if (v is String) parts.add(v);
  }
  for (final k in ['filenames', 'lines', 'results']) {
    final v = r[k];
    if (v is List && v.every((x) => x is String)) {
      parts.add((v as List<String>).join('\n'));
    }
  }
  return parts.join('\n');
}
