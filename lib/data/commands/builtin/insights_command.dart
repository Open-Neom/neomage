// /insights command — generates usage insights report analyzing NeomClaw sessions.
// Faithful port of neom_claw/src/commands/insights.ts (3200 TS LOC).
//
// Covers: session scanning, tool/language stats extraction, facet extraction
// via model API, multi-clauding detection, data aggregation, parallel insight
// generation, HTML report building, and the command definition itself.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Constants
// ============================================================================

/// File-extension to language mapping for stats collection.
const Map<String, String> extensionToLanguage = {
  '.ts': 'TypeScript',
  '.tsx': 'TypeScript',
  '.js': 'JavaScript',
  '.jsx': 'JavaScript',
  '.py': 'Python',
  '.rb': 'Ruby',
  '.go': 'Go',
  '.rs': 'Rust',
  '.java': 'Java',
  '.dart': 'Dart',
  '.md': 'Markdown',
  '.json': 'JSON',
  '.yaml': 'YAML',
  '.yml': 'YAML',
  '.sh': 'Shell',
  '.css': 'CSS',
  '.html': 'HTML',
};

/// Label map for cleaning up category names (matching Python reference).
const Map<String, String> labelMap = {
  // Goal categories
  'debug_investigate': 'Debug/Investigate',
  'implement_feature': 'Implement Feature',
  'fix_bug': 'Fix Bug',
  'write_script_tool': 'Write Script/Tool',
  'refactor_code': 'Refactor Code',
  'configure_system': 'Configure System',
  'create_pr_commit': 'Create PR/Commit',
  'analyze_data': 'Analyze Data',
  'understand_codebase': 'Understand Codebase',
  'write_tests': 'Write Tests',
  'write_docs': 'Write Docs',
  'deploy_infra': 'Deploy/Infra',
  'warmup_minimal': 'Cache Warmup',
  // Success factors
  'fast_accurate_search': 'Fast/Accurate Search',
  'correct_code_edits': 'Correct Code Edits',
  'good_explanations': 'Good Explanations',
  'proactive_help': 'Proactive Help',
  'multi_file_changes': 'Multi-file Changes',
  'handled_complexity': 'Multi-file Changes',
  'good_debugging': 'Good Debugging',
  // Friction types
  'misunderstood_request': 'Misunderstood Request',
  'wrong_approach': 'Wrong Approach',
  'buggy_code': 'Buggy Code',
  'user_rejected_action': 'User Rejected Action',
  'neomclaw_got_blocked': 'NeomClaw Got Blocked',
  'user_stopped_early': 'User Stopped Early',
  'wrong_file_or_location': 'Wrong File/Location',
  'excessive_changes': 'Excessive Changes',
  'slow_or_verbose': 'Slow/Verbose',
  'tool_failed': 'Tool Failed',
  'user_unclear': 'User Unclear',
  'external_issue': 'External Issue',
  // Satisfaction labels
  'frustrated': 'Frustrated',
  'dissatisfied': 'Dissatisfied',
  'likely_satisfied': 'Likely Satisfied',
  'satisfied': 'Satisfied',
  'happy': 'Happy',
  'unsure': 'Unsure',
  'neutral': 'Neutral',
  'delighted': 'Delighted',
  // Session types
  'single_task': 'Single Task',
  'multi_task': 'Multi Task',
  'iterative_refinement': 'Iterative Refinement',
  'exploration': 'Exploration',
  'quick_question': 'Quick Question',
  // Outcomes
  'fully_achieved': 'Fully Achieved',
  'mostly_achieved': 'Mostly Achieved',
  'partially_achieved': 'Partially Achieved',
  'not_achieved': 'Not Achieved',
  'unclear_from_transcript': 'Unclear',
  // Helpfulness
  'unhelpful': 'Unhelpful',
  'slightly_helpful': 'Slightly Helpful',
  'moderately_helpful': 'Moderately Helpful',
  'very_helpful': 'Very Helpful',
  'essential': 'Essential',
};

/// Fixed orderings for specific charts.
const List<String> satisfactionOrder = [
  'frustrated',
  'dissatisfied',
  'likely_satisfied',
  'satisfied',
  'happy',
  'unsure',
];

const List<String> outcomeOrder = [
  'not_achieved',
  'partially_achieved',
  'mostly_achieved',
  'fully_achieved',
  'unclear_from_transcript',
];

/// Prompt for facet extraction from sessions.
const String facetExtractionPrompt =
    '''Analyze this NeomClaw session and extract structured facets.

CRITICAL GUIDELINES:

1. **goal_categories**: Count ONLY what the USER explicitly asked for.
   - DO NOT count NeomClaw's autonomous codebase exploration
   - DO NOT count work NeomClaw decided to do on its own
   - ONLY count when user says "can you...", "please...", "I need...", "let's..."

2. **user_satisfaction_counts**: Base ONLY on explicit user signals.
   - "Yay!", "great!", "perfect!" → happy
   - "thanks", "looks good", "that works" → satisfied
   - "ok, now let's..." (continuing without complaint) → likely_satisfied
   - "that's not right", "try again" → dissatisfied
   - "this is broken", "I give up" → frustrated

3. **friction_counts**: Be specific about what went wrong.
   - misunderstood_request: NeomClaw interpreted incorrectly
   - wrong_approach: Right goal, wrong solution method
   - buggy_code: Code didn't work correctly
   - user_rejected_action: User said no/stop to a tool call
   - excessive_changes: Over-engineered or changed too much

4. If very short or just warmup, use warmup_minimal for goal_category

SESSION:
''';

// ============================================================================
// Types
// ============================================================================

/// Metadata extracted from a single session.
class SessionMeta {
  final String sessionId;
  final String projectPath;
  final String startTime;
  final int durationMinutes;
  final int userMessageCount;
  final int assistantMessageCount;
  final Map<String, int> toolCounts;
  final Map<String, int> languages;
  final int gitCommits;
  final int gitPushes;
  final int inputTokens;
  final int outputTokens;
  final String firstPrompt;
  final String? summary;
  final int userInterruptions;
  final List<double> userResponseTimes;
  final int toolErrors;
  final Map<String, int> toolErrorCategories;
  final bool usesTaskAgent;
  final bool usesMcp;
  final bool usesWebSearch;
  final bool usesWebFetch;
  final int linesAdded;
  final int linesRemoved;
  final int filesModified;
  final List<int> messageHours;
  final List<String> userMessageTimestamps;

  const SessionMeta({
    required this.sessionId,
    required this.projectPath,
    required this.startTime,
    required this.durationMinutes,
    required this.userMessageCount,
    required this.assistantMessageCount,
    required this.toolCounts,
    required this.languages,
    required this.gitCommits,
    required this.gitPushes,
    required this.inputTokens,
    required this.outputTokens,
    required this.firstPrompt,
    this.summary,
    required this.userInterruptions,
    required this.userResponseTimes,
    required this.toolErrors,
    required this.toolErrorCategories,
    required this.usesTaskAgent,
    required this.usesMcp,
    required this.usesWebSearch,
    required this.usesWebFetch,
    required this.linesAdded,
    required this.linesRemoved,
    required this.filesModified,
    required this.messageHours,
    required this.userMessageTimestamps,
  });

  /// Deserialize from JSON.
  factory SessionMeta.fromJson(Map<String, dynamic> json) {
    return SessionMeta(
      sessionId: json['session_id'] as String? ?? 'unknown',
      projectPath: json['project_path'] as String? ?? '',
      startTime: json['start_time'] as String? ?? '',
      durationMinutes: json['duration_minutes'] as int? ?? 0,
      userMessageCount: json['user_message_count'] as int? ?? 0,
      assistantMessageCount: json['assistant_message_count'] as int? ?? 0,
      toolCounts: _castMapInt(json['tool_counts']),
      languages: _castMapInt(json['languages']),
      gitCommits: json['git_commits'] as int? ?? 0,
      gitPushes: json['git_pushes'] as int? ?? 0,
      inputTokens: json['input_tokens'] as int? ?? 0,
      outputTokens: json['output_tokens'] as int? ?? 0,
      firstPrompt: json['first_prompt'] as String? ?? '',
      summary: json['summary'] as String?,
      userInterruptions: json['user_interruptions'] as int? ?? 0,
      userResponseTimes: _castListDouble(json['user_response_times']),
      toolErrors: json['tool_errors'] as int? ?? 0,
      toolErrorCategories: _castMapInt(json['tool_error_categories']),
      usesTaskAgent: json['uses_task_agent'] as bool? ?? false,
      usesMcp: json['uses_mcp'] as bool? ?? false,
      usesWebSearch: json['uses_web_search'] as bool? ?? false,
      usesWebFetch: json['uses_web_fetch'] as bool? ?? false,
      linesAdded: json['lines_added'] as int? ?? 0,
      linesRemoved: json['lines_removed'] as int? ?? 0,
      filesModified: json['files_modified'] as int? ?? 0,
      messageHours: _castListInt(json['message_hours']),
      userMessageTimestamps: _castListString(json['user_message_timestamps']),
    );
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'project_path': projectPath,
    'start_time': startTime,
    'duration_minutes': durationMinutes,
    'user_message_count': userMessageCount,
    'assistant_message_count': assistantMessageCount,
    'tool_counts': toolCounts,
    'languages': languages,
    'git_commits': gitCommits,
    'git_pushes': gitPushes,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'first_prompt': firstPrompt,
    if (summary != null) 'summary': summary,
    'user_interruptions': userInterruptions,
    'user_response_times': userResponseTimes,
    'tool_errors': toolErrors,
    'tool_error_categories': toolErrorCategories,
    'uses_task_agent': usesTaskAgent,
    'uses_mcp': usesMcp,
    'uses_web_search': usesWebSearch,
    'uses_web_fetch': usesWebFetch,
    'lines_added': linesAdded,
    'lines_removed': linesRemoved,
    'files_modified': filesModified,
    'message_hours': messageHours,
    'user_message_timestamps': userMessageTimestamps,
  };
}

/// Facets extracted from a session by the model.
class SessionFacets {
  final String sessionId;
  final String underlyingGoal;
  final Map<String, int> goalCategories;
  final String outcome;
  final Map<String, int> userSatisfactionCounts;
  final String neomClawHelpfulness;
  final String sessionType;
  final Map<String, int> frictionCounts;
  final String frictionDetail;
  final String primarySuccess;
  final String briefSummary;
  final List<String>? userInstructionsToNeomClaw;

  const SessionFacets({
    required this.sessionId,
    required this.underlyingGoal,
    required this.goalCategories,
    required this.outcome,
    required this.userSatisfactionCounts,
    required this.neomClawHelpfulness,
    required this.sessionType,
    required this.frictionCounts,
    required this.frictionDetail,
    required this.primarySuccess,
    required this.briefSummary,
    this.userInstructionsToNeomClaw,
  });

  factory SessionFacets.fromJson(
    Map<String, dynamic> json, {
    String? sessionId,
  }) {
    return SessionFacets(
      sessionId: sessionId ?? json['session_id'] as String? ?? '',
      underlyingGoal: json['underlying_goal'] as String? ?? '',
      goalCategories: _castMapInt(json['goal_categories']),
      outcome: json['outcome'] as String? ?? '',
      userSatisfactionCounts: _castMapInt(json['user_satisfaction_counts']),
      neomClawHelpfulness: json['claude_helpfulness'] as String? ?? '',
      sessionType: json['session_type'] as String? ?? '',
      frictionCounts: _castMapInt(json['friction_counts']),
      frictionDetail: json['friction_detail'] as String? ?? '',
      primarySuccess: json['primary_success'] as String? ?? 'none',
      briefSummary: json['brief_summary'] as String? ?? '',
      userInstructionsToNeomClaw: _castListString(
        json['user_instructions_to_neomclaw'],
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'underlying_goal': underlyingGoal,
    'goal_categories': goalCategories,
    'outcome': outcome,
    'user_satisfaction_counts': userSatisfactionCounts,
    'claude_helpfulness': neomClawHelpfulness,
    'session_type': sessionType,
    'friction_counts': frictionCounts,
    'friction_detail': frictionDetail,
    'primary_success': primarySuccess,
    'brief_summary': briefSummary,
    if (userInstructionsToNeomClaw != null)
      'user_instructions_to_neomclaw': userInstructionsToNeomClaw,
  };

  /// Validate that a parsed JSON object has the required fields.
  static bool isValid(dynamic obj) {
    if (obj is! Map<String, dynamic>) return false;
    return obj['underlying_goal'] is String &&
        obj['outcome'] is String &&
        obj['brief_summary'] is String &&
        obj['goal_categories'] is Map &&
        obj['user_satisfaction_counts'] is Map &&
        obj['friction_counts'] is Map;
  }
}

/// Aggregated data across all sessions.
class AggregatedData {
  int totalSessions;
  int? totalSessionsScanned;
  int sessionsWithFacets;
  ({String start, String end}) dateRange;
  int totalMessages;
  double totalDurationHours;
  int totalInputTokens;
  int totalOutputTokens;
  Map<String, int> toolCounts;
  Map<String, int> languages;
  int gitCommits;
  int gitPushes;
  Map<String, int> projects;
  Map<String, int> goalCategories;
  Map<String, int> outcomes;
  Map<String, int> satisfaction;
  Map<String, int> helpfulness;
  Map<String, int> sessionTypes;
  Map<String, int> friction;
  Map<String, int> success;
  List<Map<String, String>> sessionSummaries;
  int totalInterruptions;
  int totalToolErrors;
  Map<String, int> toolErrorCategories;
  List<double> userResponseTimes;
  double medianResponseTime;
  double avgResponseTime;
  int sessionsUsingTaskAgent;
  int sessionsUsingMcp;
  int sessionsUsingWebSearch;
  int sessionsUsingWebFetch;
  int totalLinesAdded;
  int totalLinesRemoved;
  int totalFilesModified;
  int daysActive;
  double messagesPerDay;
  List<int> messageHours;
  ({int overlapEvents, int sessionsInvolved, int userMessagesDuring})
  multiClauding;

  AggregatedData({
    this.totalSessions = 0,
    this.totalSessionsScanned,
    this.sessionsWithFacets = 0,
    this.dateRange = (start: '', end: ''),
    this.totalMessages = 0,
    this.totalDurationHours = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    Map<String, int>? toolCounts,
    Map<String, int>? languages,
    this.gitCommits = 0,
    this.gitPushes = 0,
    Map<String, int>? projects,
    Map<String, int>? goalCategories,
    Map<String, int>? outcomes,
    Map<String, int>? satisfaction,
    Map<String, int>? helpfulness,
    Map<String, int>? sessionTypes,
    Map<String, int>? friction,
    Map<String, int>? success,
    List<Map<String, String>>? sessionSummaries,
    this.totalInterruptions = 0,
    this.totalToolErrors = 0,
    Map<String, int>? toolErrorCategories,
    List<double>? userResponseTimes,
    this.medianResponseTime = 0,
    this.avgResponseTime = 0,
    this.sessionsUsingTaskAgent = 0,
    this.sessionsUsingMcp = 0,
    this.sessionsUsingWebSearch = 0,
    this.sessionsUsingWebFetch = 0,
    this.totalLinesAdded = 0,
    this.totalLinesRemoved = 0,
    this.totalFilesModified = 0,
    this.daysActive = 0,
    this.messagesPerDay = 0,
    List<int>? messageHours,
    this.multiClauding = (
      overlapEvents: 0,
      sessionsInvolved: 0,
      userMessagesDuring: 0,
    ),
  }) : toolCounts = toolCounts ?? {},
       languages = languages ?? {},
       projects = projects ?? {},
       goalCategories = goalCategories ?? {},
       outcomes = outcomes ?? {},
       satisfaction = satisfaction ?? {},
       helpfulness = helpfulness ?? {},
       sessionTypes = sessionTypes ?? {},
       friction = friction ?? {},
       success = success ?? {},
       sessionSummaries = sessionSummaries ?? [],
       toolErrorCategories = toolErrorCategories ?? {},
       userResponseTimes = userResponseTimes ?? [],
       messageHours = messageHours ?? [];
}

/// Lightweight session info from filesystem metadata.
class LiteSessionInfo {
  final String sessionId;
  final String path;
  final int mtimeMs;
  final int size;

  const LiteSessionInfo({
    required this.sessionId,
    required this.path,
    required this.mtimeMs,
    required this.size,
  });
}

/// Insight section definition for parallel generation.
class InsightSection {
  final String name;
  final String prompt;
  final int maxTokens;

  const InsightSection({
    required this.name,
    required this.prompt,
    this.maxTokens = 8192,
  });
}

/// Results from all insight sections.
class InsightResults {
  Map<String, dynamic>? atAGlance;
  List<Map<String, dynamic>>? projectAreas;
  Map<String, dynamic>? interactionStyle;
  Map<String, dynamic>? whatWorks;
  Map<String, dynamic>? frictionAnalysis;
  Map<String, dynamic>? suggestions;
  Map<String, dynamic>? onTheHorizon;
  Map<String, dynamic>? funEnding;

  InsightResults();

  Map<String, dynamic> toJson() => {
    if (atAGlance != null) 'at_a_glance': atAGlance,
    if (projectAreas != null) 'project_areas': projectAreas,
    if (interactionStyle != null) 'interaction_style': interactionStyle,
    if (whatWorks != null) 'what_works': whatWorks,
    if (frictionAnalysis != null) 'friction_analysis': frictionAnalysis,
    if (suggestions != null) 'suggestions': suggestions,
    if (onTheHorizon != null) 'on_the_horizon': onTheHorizon,
    if (funEnding != null) 'fun_ending': funEnding,
  };
}

/// Export format for structured data.
class InsightsExport {
  final Map<String, dynamic> metadata;
  final AggregatedData aggregatedData;
  final InsightResults insights;
  final Map<String, dynamic>? facetsSummary;

  const InsightsExport({
    required this.metadata,
    required this.aggregatedData,
    required this.insights,
    this.facetsSummary,
  });
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Safely cast a dynamic value to `Map<String, int>`.
Map<String, int> _castMapInt(dynamic value) {
  if (value is Map) {
    return value.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
  }
  return {};
}

/// Safely cast a dynamic value to `List<double>`.
List<double> _castListDouble(dynamic value) {
  if (value is List) {
    return value.map((v) => (v as num).toDouble()).toList();
  }
  return [];
}

/// Safely cast a dynamic value to `List<int>`.
List<int> _castListInt(dynamic value) {
  if (value is List) {
    return value.map((v) => (v as num).toInt()).toList();
  }
  return [];
}

/// Safely cast a dynamic value to `List<String>`.
List<String> _castListString(dynamic value) {
  if (value is List) {
    return value.map((v) => v.toString()).toList();
  }
  return [];
}

/// Get language from file path extension.
String? getLanguageFromPath(String filePath) {
  final ext = p.extension(filePath).toLowerCase();
  return extensionToLanguage[ext];
}

/// Count occurrences of a character in a string.
int _countChar(String s, String ch) {
  int count = 0;
  for (int i = 0; i < s.length; i++) {
    if (s[i] == ch) count++;
  }
  return count;
}

/// Categorize a tool error based on its content.
String categorizeToolError(String content) {
  final lower = content.toLowerCase();
  if (lower.contains('exit code')) return 'Command Failed';
  if (lower.contains('rejected') || lower.contains("doesn't want")) {
    return 'User Rejected';
  }
  if (lower.contains('string to replace not found') ||
      lower.contains('no changes')) {
    return 'Edit Failed';
  }
  if (lower.contains('modified since read')) return 'File Changed';
  if (lower.contains('exceeds maximum') || lower.contains('too large')) {
    return 'File Too Large';
  }
  if (lower.contains('file not found') || lower.contains('does not exist')) {
    return 'File Not Found';
  }
  return 'Other';
}

// ============================================================================
// Tool Stats Extraction
// ============================================================================

/// Result of extracting tool statistics from a session log.
class ToolStatsResult {
  final Map<String, int> toolCounts;
  final Map<String, int> languages;
  int gitCommits;
  int gitPushes;
  int inputTokens;
  int outputTokens;
  int userInterruptions;
  final List<double> userResponseTimes;
  int toolErrors;
  final Map<String, int> toolErrorCategories;
  bool usesTaskAgent;
  bool usesMcp;
  bool usesWebSearch;
  bool usesWebFetch;
  int linesAdded;
  int linesRemoved;
  final Set<String> filesModified;
  final List<int> messageHours;
  final List<String> userMessageTimestamps;

  ToolStatsResult()
    : toolCounts = {},
      languages = {},
      gitCommits = 0,
      gitPushes = 0,
      inputTokens = 0,
      outputTokens = 0,
      userInterruptions = 0,
      userResponseTimes = [],
      toolErrors = 0,
      toolErrorCategories = {},
      usesTaskAgent = false,
      usesMcp = false,
      usesWebSearch = false,
      usesWebFetch = false,
      linesAdded = 0,
      linesRemoved = 0,
      filesModified = {},
      messageHours = [],
      userMessageTimestamps = [];
}

/// Extract tool usage statistics from session messages.
///
/// Processes each message to count tool invocations, detect language usage,
/// track git operations, measure response times, and identify errors.
ToolStatsResult extractToolStats(List<Map<String, dynamic>> messages) {
  final stats = ToolStatsResult();
  String? lastAssistantTimestamp;

  for (final msg in messages) {
    final type = msg['type'] as String?;
    final message = msg['message'] as Map<String, dynamic>?;
    final msgTimestamp = msg['timestamp'] as String?;

    if (type == 'assistant' && message != null) {
      if (msgTimestamp != null) {
        lastAssistantTimestamp = msgTimestamp;
      }

      // Track token usage.
      final usage = message['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        stats.inputTokens += (usage['input_tokens'] as int?) ?? 0;
        stats.outputTokens += (usage['output_tokens'] as int?) ?? 0;
      }

      // Process content blocks.
      final content = message['content'];
      if (content is List) {
        for (final block in content) {
          if (block is! Map<String, dynamic>) continue;
          if (block['type'] == 'tool_use' && block['name'] != null) {
            final toolName = block['name'] as String;
            stats.toolCounts[toolName] = (stats.toolCounts[toolName] ?? 0) + 1;

            // Check for special tool usage.
            if (toolName == 'Task' || toolName == 'dispatch_agent') {
              stats.usesTaskAgent = true;
            }
            if (toolName.startsWith('mcp__')) stats.usesMcp = true;
            if (toolName == 'WebSearch') stats.usesWebSearch = true;
            if (toolName == 'WebFetch') stats.usesWebFetch = true;

            final input = block['input'] as Map<String, dynamic>?;
            if (input != null) {
              final filePath = input['file_path'] as String? ?? '';
              if (filePath.isNotEmpty) {
                final lang = getLanguageFromPath(filePath);
                if (lang != null) {
                  stats.languages[lang] = (stats.languages[lang] ?? 0) + 1;
                }
                // Track files modified by Edit/Write tools.
                if (toolName == 'Edit' || toolName == 'Write') {
                  stats.filesModified.add(filePath);
                }
              }

              // Count lines changed in Edit operations.
              if (toolName == 'Edit') {
                final oldString = input['old_string'] as String? ?? '';
                final newString = input['new_string'] as String? ?? '';
                final oldLines = oldString.split('\n').length;
                final newLines = newString.split('\n').length;
                if (newLines > oldLines) {
                  stats.linesAdded += newLines - oldLines;
                } else {
                  stats.linesRemoved += oldLines - newLines;
                }
              }

              // Track lines from Write tool (all added).
              if (toolName == 'Write') {
                final writeContent = input['content'] as String? ?? '';
                if (writeContent.isNotEmpty) {
                  stats.linesAdded += _countChar(writeContent, '\n') + 1;
                }
              }

              // Track git operations.
              final command = input['command'] as String? ?? '';
              if (command.contains('git commit')) stats.gitCommits++;
              if (command.contains('git push')) stats.gitPushes++;
            }
          }
        }
      }
    }

    // Process user messages.
    if (type == 'user' && message != null) {
      final content = message['content'];
      bool isHumanMessage = false;

      if (content is String && content.trim().isNotEmpty) {
        isHumanMessage = true;
      } else if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic> &&
              block['type'] == 'text' &&
              block['text'] != null) {
            isHumanMessage = true;
            break;
          }
        }
      }

      // Track message hours and response times for actual human messages.
      if (isHumanMessage && msgTimestamp != null) {
        try {
          final msgDate = DateTime.parse(msgTimestamp);
          stats.messageHours.add(msgDate.hour);
          stats.userMessageTimestamps.add(msgTimestamp);
        } catch (_) {
          // Skip invalid timestamps.
        }

        // Calculate response time.
        if (lastAssistantTimestamp != null) {
          try {
            final assistantTime = DateTime.parse(
              lastAssistantTimestamp,
            ).millisecondsSinceEpoch;
            final userTime = DateTime.parse(
              msgTimestamp,
            ).millisecondsSinceEpoch;
            final responseTimeSec = (userTime - assistantTime) / 1000.0;
            // Only count reasonable response times (2s-1 hour).
            if (responseTimeSec > 2 && responseTimeSec < 3600) {
              stats.userResponseTimes.add(responseTimeSec);
            }
          } catch (_) {
            // Skip invalid timestamps.
          }
        }
      }

      // Process tool results for error tracking.
      if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic> &&
              block['type'] == 'tool_result' &&
              block['is_error'] == true) {
            stats.toolErrors++;
            final resultContent = block['content'] as String? ?? '';
            final category = categorizeToolError(resultContent);
            stats.toolErrorCategories[category] =
                (stats.toolErrorCategories[category] ?? 0) + 1;
          }
        }
      }

      // Check for interruptions.
      if (content is String &&
          content.contains('[Request interrupted by user')) {
        stats.userInterruptions++;
      } else if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic> &&
              block['type'] == 'text' &&
              (block['text'] as String? ?? '').contains(
                '[Request interrupted by user',
              )) {
            stats.userInterruptions++;
            break;
          }
        }
      }
    }
  }

  return stats;
}

// ============================================================================
// Multi-Clauding Detection
// ============================================================================

/// Detect multi-clawing (using multiple NeomClaw sessions concurrently).
///
/// Uses a sliding window to find the pattern: session1 -> session2 -> session1
/// within a 30-minute window.
({int overlapEvents, int sessionsInvolved, int userMessagesDuring})
detectMultiClauding(
  List<({String sessionId, List<String> timestamps})> sessions,
) {
  const overlapWindowMs = 30 * 60000;

  final allMessages = <({int ts, String sessionId})>[];
  for (final session in sessions) {
    for (final timestamp in session.timestamps) {
      try {
        final ts = DateTime.parse(timestamp).millisecondsSinceEpoch;
        allMessages.add((ts: ts, sessionId: session.sessionId));
      } catch (_) {
        // Skip invalid timestamps.
      }
    }
  }

  allMessages.sort((a, b) => a.ts.compareTo(b.ts));

  final multiNeomClawSessionPairs = <String>{};
  final messagesDuringMultiNeomClaw = <String>{};

  int windowStart = 0;
  final sessionLastIndex = <String, int>{};

  for (int i = 0; i < allMessages.length; i++) {
    final msg = allMessages[i];

    // Shrink window from the left.
    while (windowStart < i &&
        msg.ts - allMessages[windowStart].ts > overlapWindowMs) {
      final expiring = allMessages[windowStart];
      if (sessionLastIndex[expiring.sessionId] == windowStart) {
        sessionLastIndex.remove(expiring.sessionId);
      }
      windowStart++;
    }

    // Check if this session appeared earlier in the window.
    final prevIndex = sessionLastIndex[msg.sessionId];
    if (prevIndex != null) {
      for (int j = prevIndex + 1; j < i; j++) {
        final between = allMessages[j];
        if (between.sessionId != msg.sessionId) {
          final pair = [msg.sessionId, between.sessionId]..sort();
          multiNeomClawSessionPairs.add(pair.join(':'));
          messagesDuringMultiNeomClaw.add(
            '${allMessages[prevIndex].ts}:${msg.sessionId}',
          );
          messagesDuringMultiNeomClaw.add('${between.ts}:${between.sessionId}');
          messagesDuringMultiNeomClaw.add('${msg.ts}:${msg.sessionId}');
          break;
        }
      }
    }

    sessionLastIndex[msg.sessionId] = i;
  }

  final sessionsWithOverlaps = <String>{};
  for (final pair in multiNeomClawSessionPairs) {
    final parts = pair.split(':');
    if (parts.length == 2) {
      sessionsWithOverlaps.add(parts[0]);
      sessionsWithOverlaps.add(parts[1]);
    }
  }

  return (
    overlapEvents: multiNeomClawSessionPairs.length,
    sessionsInvolved: sessionsWithOverlaps.length,
    userMessagesDuring: messagesDuringMultiNeomClaw.length,
  );
}

// ============================================================================
// Session Branch Deduplication
// ============================================================================

/// Deduplicate conversation branches within the same session.
///
/// When a session file has multiple leaf messages (from retries or branching),
/// each branch shares the same root. This keeps only the branch with the most
/// user messages (tie-break by longest duration) per session_id.
List<SessionMeta> deduplicateSessionBranches(List<SessionMeta> metas) {
  final bestBySession = <String, SessionMeta>{};
  for (final meta in metas) {
    final existing = bestBySession[meta.sessionId];
    if (existing == null ||
        meta.userMessageCount > existing.userMessageCount ||
        (meta.userMessageCount == existing.userMessageCount &&
            meta.durationMinutes > existing.durationMinutes)) {
      bestBySession[meta.sessionId] = meta;
    }
  }
  return bestBySession.values.toList();
}

// ============================================================================
// Data Aggregation
// ============================================================================

/// Aggregate data from all sessions and facets into a single report.
AggregatedData aggregateData(
  List<SessionMeta> sessions,
  Map<String, SessionFacets> facets,
) {
  final result = AggregatedData(totalSessions: sessions.length);
  result.sessionsWithFacets = facets.length;

  final dates = <String>[];
  final allResponseTimes = <double>[];
  final allMessageHours = <int>[];

  for (final session in sessions) {
    dates.add(session.startTime);
    result.totalMessages += session.userMessageCount;
    result.totalDurationHours += session.durationMinutes / 60.0;
    result.totalInputTokens += session.inputTokens;
    result.totalOutputTokens += session.outputTokens;
    result.gitCommits += session.gitCommits;
    result.gitPushes += session.gitPushes;

    // Aggregate new stats.
    result.totalInterruptions += session.userInterruptions;
    result.totalToolErrors += session.toolErrors;
    for (final entry in session.toolErrorCategories.entries) {
      result.toolErrorCategories[entry.key] =
          (result.toolErrorCategories[entry.key] ?? 0) + entry.value;
    }
    allResponseTimes.addAll(session.userResponseTimes);
    if (session.usesTaskAgent) result.sessionsUsingTaskAgent++;
    if (session.usesMcp) result.sessionsUsingMcp++;
    if (session.usesWebSearch) result.sessionsUsingWebSearch++;
    if (session.usesWebFetch) result.sessionsUsingWebFetch++;

    // Additional stats.
    result.totalLinesAdded += session.linesAdded;
    result.totalLinesRemoved += session.linesRemoved;
    result.totalFilesModified += session.filesModified;
    allMessageHours.addAll(session.messageHours);

    // Merge tool and language counts.
    for (final entry in session.toolCounts.entries) {
      result.toolCounts[entry.key] =
          (result.toolCounts[entry.key] ?? 0) + entry.value;
    }
    for (final entry in session.languages.entries) {
      result.languages[entry.key] =
          (result.languages[entry.key] ?? 0) + entry.value;
    }

    if (session.projectPath.isNotEmpty) {
      result.projects[session.projectPath] =
          (result.projects[session.projectPath] ?? 0) + 1;
    }

    // Merge facets.
    final sessionFacets = facets[session.sessionId];
    if (sessionFacets != null) {
      for (final entry in sessionFacets.goalCategories.entries) {
        if (entry.value > 0) {
          result.goalCategories[entry.key] =
              (result.goalCategories[entry.key] ?? 0) + entry.value;
        }
      }

      result.outcomes[sessionFacets.outcome] =
          (result.outcomes[sessionFacets.outcome] ?? 0) + 1;

      for (final entry in sessionFacets.userSatisfactionCounts.entries) {
        if (entry.value > 0) {
          result.satisfaction[entry.key] =
              (result.satisfaction[entry.key] ?? 0) + entry.value;
        }
      }

      result.helpfulness[sessionFacets.neomClawHelpfulness] =
          (result.helpfulness[sessionFacets.neomClawHelpfulness] ?? 0) + 1;

      result.sessionTypes[sessionFacets.sessionType] =
          (result.sessionTypes[sessionFacets.sessionType] ?? 0) + 1;

      for (final entry in sessionFacets.frictionCounts.entries) {
        if (entry.value > 0) {
          result.friction[entry.key] =
              (result.friction[entry.key] ?? 0) + entry.value;
        }
      }

      if (sessionFacets.primarySuccess != 'none') {
        result.success[sessionFacets.primarySuccess] =
            (result.success[sessionFacets.primarySuccess] ?? 0) + 1;
      }
    }

    // Collect session summaries (max 50).
    if (result.sessionSummaries.length < 50) {
      result.sessionSummaries.add({
        'id': session.sessionId.length >= 8
            ? session.sessionId.substring(0, 8)
            : session.sessionId,
        'date': session.startTime.split('T').first,
        'summary':
            session.summary ??
            (session.firstPrompt.length > 100
                ? session.firstPrompt.substring(0, 100)
                : session.firstPrompt),
        if (sessionFacets?.underlyingGoal != null)
          'goal': sessionFacets!.underlyingGoal,
      });
    }
  }

  // Date range.
  dates.sort();
  if (dates.isNotEmpty) {
    result.dateRange = (
      start: dates.first.split('T').first,
      end: dates.last.split('T').first,
    );
  }

  // Response time statistics.
  result.userResponseTimes = allResponseTimes;
  if (allResponseTimes.isNotEmpty) {
    final sorted = [...allResponseTimes]..sort();
    result.medianResponseTime = sorted[sorted.length ~/ 2];
    result.avgResponseTime =
        allResponseTimes.reduce((a, b) => a + b) / allResponseTimes.length;
  }

  // Days active and messages per day.
  final uniqueDays = dates.map((d) => d.split('T').first).toSet();
  result.daysActive = uniqueDays.length;
  result.messagesPerDay = result.daysActive > 0
      ? (result.totalMessages / result.daysActive * 10).round() / 10.0
      : 0;

  // Store message hours for time-of-day chart.
  result.messageHours = allMessageHours;

  // Multi-clauding detection.
  result.multiClauding = detectMultiClauding(
    sessions
        .map(
          (s) => (sessionId: s.sessionId, timestamps: s.userMessageTimestamps),
        )
        .toList(),
  );

  return result;
}

// ============================================================================
// Insight Section Prompts
// ============================================================================

/// Build the set of insight section definitions for parallel generation.
List<InsightSection> buildInsightSections() {
  return [
    const InsightSection(
      name: 'project_areas',
      prompt: '''Analyze this NeomClaw usage data and identify project areas.

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "areas": [
    {"name": "Area name", "session_count": N, "description": "2-3 sentences about what was worked on."}
  ]
}

Include 4-5 areas. Skip internal CC operations.''',
    ),
    const InsightSection(
      name: 'interaction_style',
      prompt:
          '''Analyze this NeomClaw usage data and describe the user's interaction style.

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "narrative": "2-3 paragraphs analyzing HOW the user interacts with NeomClaw. Use second person 'you'. Use **bold** for key insights.",
  "key_pattern": "One sentence summary of most distinctive interaction style"
}''',
    ),
    const InsightSection(
      name: 'what_works',
      prompt:
          '''Analyze this NeomClaw usage data and identify what's working well for this user. Use second person ("you").

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "intro": "1 sentence of context",
  "impressive_workflows": [
    {"title": "Short title (3-6 words)", "description": "2-3 sentences describing the impressive workflow or approach."}
  ]
}

Include 3 impressive workflows.''',
    ),
    const InsightSection(
      name: 'friction_analysis',
      prompt:
          '''Analyze this NeomClaw usage data and identify friction points for this user. Use second person ("you").

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "intro": "1 sentence summarizing friction patterns",
  "categories": [
    {"category": "Concrete category name", "description": "1-2 sentences explaining this category.", "examples": ["Specific example", "Another example"]}
  ]
}

Include 3 friction categories with 2 examples each.''',
    ),
    const InsightSection(
      name: 'suggestions',
      prompt: '''Analyze this NeomClaw usage data and suggest improvements.

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "neomclaw_md_additions": [
    {"addition": "A specific line to add to NEOMCLAW.md", "why": "1 sentence explaining why", "prompt_scaffold": "Instructions for where to add"}
  ],
  "features_to_try": [
    {"feature": "Feature name", "one_liner": "What it does", "why_for_you": "Why this would help", "example_code": "Command to copy"}
  ],
  "usage_patterns": [
    {"title": "Short title", "suggestion": "1-2 sentence summary", "detail": "3-4 sentences", "copyable_prompt": "A specific prompt to try"}
  ]
}

Include 2-3 items for each category.''',
    ),
    const InsightSection(
      name: 'on_the_horizon',
      prompt:
          '''Analyze this NeomClaw usage data and identify future opportunities.

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "intro": "1 sentence about evolving AI-assisted development",
  "opportunities": [
    {"title": "Short title (4-8 words)", "whats_possible": "2-3 sentences about autonomous workflows", "how_to_try": "1-2 sentences", "copyable_prompt": "Detailed prompt to try"}
  ]
}

Include 3 opportunities. Think BIG.''',
    ),
    const InsightSection(
      name: 'fun_ending',
      prompt: '''Analyze this NeomClaw usage data and find a memorable moment.

RESPOND WITH ONLY A VALID JSON OBJECT:
{
  "headline": "A memorable QUALITATIVE moment from the transcripts - not a statistic.",
  "detail": "Brief context about when/where this happened"
}''',
    ),
  ];
}

// ============================================================================
// Directory Helpers
// ============================================================================

/// Get the usage data directory path.
String getDataDir() {
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.neomclaw', 'usage-data');
}

/// Get the facets cache directory path.
String getFacetsDir() => p.join(getDataDir(), 'facets');

/// Get the session meta cache directory path.
String getSessionMetaDir() => p.join(getDataDir(), 'session-meta');

/// Get the projects directory path.
String getProjectsDir() {
  final home = Platform.environment['HOME'] ?? '';
  return p.join(home, '.neomclaw', 'projects');
}

// ============================================================================
// Cache Operations
// ============================================================================

/// Load cached facets for a session.
Future<SessionFacets?> loadCachedFacets(String sessionId) async {
  final facetPath = p.join(getFacetsDir(), '$sessionId.json');
  try {
    final file = File(facetPath);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final parsed = jsonDecode(content);
    if (!SessionFacets.isValid(parsed)) {
      // Delete corrupted cache.
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
    return SessionFacets.fromJson(parsed as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Save facets to cache.
Future<void> saveFacets(SessionFacets facets) async {
  final dir = Directory(getFacetsDir());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final facetPath = p.join(getFacetsDir(), '${facets.sessionId}.json');
  await File(
    facetPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(facets.toJson()));
}

/// Load cached session metadata.
Future<SessionMeta?> loadCachedSessionMeta(String sessionId) async {
  final metaPath = p.join(getSessionMetaDir(), '$sessionId.json');
  try {
    final file = File(metaPath);
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    return SessionMeta.fromJson(jsonDecode(content) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}

/// Save session metadata to cache.
Future<void> saveSessionMeta(SessionMeta meta) async {
  final dir = Directory(getSessionMetaDir());
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  final metaPath = p.join(getSessionMetaDir(), '${meta.sessionId}.json');
  await File(
    metaPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(meta.toJson()));
}

// ============================================================================
// Session Scanning
// ============================================================================

/// Scan all project directories using filesystem metadata only.
/// Returns a list of session file info sorted by mtime descending.
Future<List<LiteSessionInfo>> scanAllSessions() async {
  final projectsDir = Directory(getProjectsDir());
  if (!await projectsDir.exists()) return [];

  final allSessions = <LiteSessionInfo>[];

  await for (final entity in projectsDir.list()) {
    if (entity is! Directory) continue;

    try {
      await for (final file in entity.list()) {
        if (file is! File || !file.path.endsWith('.jsonl')) continue;

        final stat = await file.stat();
        final sessionId = p.basenameWithoutExtension(file.path);
        allSessions.add(
          LiteSessionInfo(
            sessionId: sessionId,
            path: file.path,
            mtimeMs: stat.modified.millisecondsSinceEpoch,
            size: stat.size,
          ),
        );
      }
    } catch (_) {
      // Skip inaccessible project directories.
    }
  }

  // Sort by mtime descending (most recent first).
  allSessions.sort((a, b) => b.mtimeMs.compareTo(a.mtimeMs));
  return allSessions;
}

/// Check if a session is substantive (not minimal).
bool isSubstantiveSession(SessionMeta meta) {
  return meta.userMessageCount >= 2 && meta.durationMinutes >= 1;
}

/// Check if a session is minimal (warmup only).
bool isMinimalSession(String sessionId, Map<String, SessionFacets> facets) {
  final sessionFacets = facets[sessionId];
  if (sessionFacets == null) return false;
  final cats = sessionFacets.goalCategories;
  final catKeys = cats.entries
      .where((e) => e.value > 0)
      .map((e) => e.key)
      .toList();
  return catKeys.length == 1 && catKeys.first == 'warmup_minimal';
}

// ============================================================================
// Command Definition
// ============================================================================

/// The /insights command — generates a usage report analyzing NeomClaw sessions.
class InsightsCommand extends PromptCommand {
  @override
  String get name => 'insights';

  @override
  String get description =>
      'Generate a report analyzing your NeomClaw sessions';

  @override
  String get progressMessage => 'analyzing your sessions';

  @override
  Set<String> get allowedTools => const {'Bash', 'Read', 'Glob', 'Grep'};

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    // Scan sessions, aggregate data, and generate insights.
    final scannedSessions = await scanAllSessions();
    final totalSessionsScanned = scannedSessions.length;

    // Load cached session metas and identify uncached sessions.
    final allMetas = <SessionMeta>[];
    final uncachedSessions = <LiteSessionInfo>[];
    const maxSessionsToLoad = 200;

    for (final sessionInfo in scannedSessions) {
      final cached = await loadCachedSessionMeta(sessionInfo.sessionId);
      if (cached != null) {
        allMetas.add(cached);
      } else if (uncachedSessions.length < maxSessionsToLoad) {
        uncachedSessions.add(sessionInfo);
      }
    }

    // Deduplicate session branches.
    final deduplicated = deduplicateSessionBranches(allMetas);

    // Filter substantive sessions.
    final substantive = deduplicated.where(isSubstantiveSession).toList();

    // Load cached facets.
    final facets = <String, SessionFacets>{};
    for (final meta in substantive) {
      final cached = await loadCachedFacets(meta.sessionId);
      if (cached != null) {
        facets[meta.sessionId] = cached;
      }
    }

    // Filter out minimal sessions.
    final nonMinimal = substantive
        .where((s) => !isMinimalSession(s.sessionId, facets))
        .toList();

    final substantiveFacets = <String, SessionFacets>{};
    for (final entry in facets.entries) {
      if (!isMinimalSession(entry.key, facets)) {
        substantiveFacets[entry.key] = entry.value;
      }
    }

    // Aggregate data.
    final aggregated = aggregateData(nonMinimal, substantiveFacets);
    aggregated.totalSessionsScanned = totalSessionsScanned;

    // Build stats line.
    final sessionLabel =
        aggregated.totalSessionsScanned != null &&
            aggregated.totalSessionsScanned! > aggregated.totalSessions
        ? '${aggregated.totalSessionsScanned} sessions total, '
              '${aggregated.totalSessions} analyzed'
        : '${aggregated.totalSessions} sessions';

    final stats = [
      sessionLabel,
      '${aggregated.totalMessages} messages',
      '${aggregated.totalDurationHours.round()}h',
      '${aggregated.gitCommits} commits',
    ].join(' . ');

    final htmlPath = p.join(getDataDir(), 'report.html');
    final reportUrl = 'file://$htmlPath';

    return [
      TextBlock(
        'The user just ran /insights to generate a usage report analyzing '
        'their NeomClaw sessions.\n\n'
        'Stats: $stats\n'
        'Date range: ${aggregated.dateRange.start} to ${aggregated.dateRange.end}\n'
        'Sessions with facets: ${aggregated.sessionsWithFacets}\n'
        'Report URL: $reportUrl\n\n'
        'Summarize the session analysis for the user. Include:\n'
        '- Total sessions and messages\n'
        '- Top languages used: ${_topEntries(aggregated.languages, 3)}\n'
        '- Top tools used: ${_topEntries(aggregated.toolCounts, 3)}\n'
        '- Top goals: ${_topEntries(aggregated.goalCategories, 3)}\n'
        '- Outcomes: ${_topEntries(aggregated.outcomes, 3)}\n'
        '- Friction types: ${_topEntries(aggregated.friction, 3)}\n'
        '- Days active: ${aggregated.daysActive}\n'
        '- Messages per day: ${aggregated.messagesPerDay}\n'
        '- Lines added/removed: +${aggregated.totalLinesAdded}/-${aggregated.totalLinesRemoved}\n'
        '- Multi-clauding events: ${aggregated.multiClauding.overlapEvents}\n\n'
        'End with: "Your shareable insights report is ready: $reportUrl"\n'
        'Ask if they want to dig into any section.',
      ),
    ];
  }

  /// Format top N entries from a map for display.
  static String _topEntries(Map<String, int> data, int n) {
    final sorted = data.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted
        .take(n)
        .map((e) {
          final label =
              labelMap[e.key] ??
              e.key
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) {
                    if (w.isEmpty) return w;
                    return w[0].toUpperCase() + w.substring(1);
                  })
                  .join(' ');
          return '$label (${e.value})';
        })
        .join(', ');
  }
}
