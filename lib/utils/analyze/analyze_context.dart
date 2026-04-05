/// Context analysis for conversations.
///
/// Ported from neomage/src/utils/analyzeContext.ts (1382 LOC).
library;

import 'dart:async';
import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Fixed token overhead added by the API when tools are present.
const int toolTokenCountOverhead = 500;

const String _reservedCategoryName = 'Autocompact buffer';
const String _manualCompactBufferName = 'Compact buffer';

/// Default autocompact buffer tokens.
const int autocompactBufferTokens = 33000;

/// Default manual compact buffer tokens.
const int manualCompactBufferTokens = 3000;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A category of context usage.
class ContextCategory {
  final String name;
  final int tokens;
  final String color;

  /// When true, these tokens are deferred and don't count toward context usage.
  final bool isDeferred;

  const ContextCategory({
    required this.name,
    required this.tokens,
    required this.color,
    this.isDeferred = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'tokens': tokens,
    'color': color,
    if (isDeferred) 'isDeferred': isDeferred,
  };
}

/// A single square in the context grid visualization.
class GridSquare {
  final String color;
  final bool isFilled;
  final String categoryName;
  final int tokens;
  final int percentage;

  /// 0-1 representing how full this individual square is.
  final double squareFullness;

  const GridSquare({
    required this.color,
    required this.isFilled,
    required this.categoryName,
    required this.tokens,
    required this.percentage,
    required this.squareFullness,
  });

  Map<String, dynamic> toJson() => {
    'color': color,
    'isFilled': isFilled,
    'categoryName': categoryName,
    'tokens': tokens,
    'percentage': percentage,
    'squareFullness': squareFullness,
  };
}

/// Information about a memory file in context.
class MemoryFile {
  final String path;
  final String type;
  final int tokens;

  const MemoryFile({
    required this.path,
    required this.type,
    required this.tokens,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'type': type,
    'tokens': tokens,
  };
}

/// Information about an MCP tool in context.
class McpTool {
  final String name;
  final String serverName;
  final int tokens;
  final bool isLoaded;

  const McpTool({
    required this.name,
    required this.serverName,
    required this.tokens,
    this.isLoaded = true,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'serverName': serverName,
    'tokens': tokens,
    'isLoaded': isLoaded,
  };
}

/// Information about a deferred builtin tool.
class DeferredBuiltinTool {
  final String name;
  final int tokens;
  final bool isLoaded;

  const DeferredBuiltinTool({
    required this.name,
    required this.tokens,
    required this.isLoaded,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'tokens': tokens,
    'isLoaded': isLoaded,
  };
}

/// Information about a system tool.
class SystemToolDetail {
  final String name;
  final int tokens;

  const SystemToolDetail({required this.name, required this.tokens});

  Map<String, dynamic> toJson() => {'name': name, 'tokens': tokens};
}

/// Information about a system prompt section.
class SystemPromptSectionDetail {
  final String name;
  final int tokens;

  const SystemPromptSectionDetail({required this.name, required this.tokens});

  Map<String, dynamic> toJson() => {'name': name, 'tokens': tokens};
}

/// Information about a custom agent.
class AgentInfo {
  final String agentType;
  final String source;
  final int tokens;

  const AgentInfo({
    required this.agentType,
    required this.source,
    required this.tokens,
  });

  Map<String, dynamic> toJson() => {
    'agentType': agentType,
    'source': source,
    'tokens': tokens,
  };
}

/// Slash command info for context display.
class SlashCommandInfo {
  final int totalCommands;
  final int includedCommands;
  final int tokens;

  const SlashCommandInfo({
    required this.totalCommands,
    required this.includedCommands,
    required this.tokens,
  });

  Map<String, dynamic> toJson() => {
    'totalCommands': totalCommands,
    'includedCommands': includedCommands,
    'tokens': tokens,
  };
}

/// Individual skill detail for context display.
class SkillFrontmatter {
  final String name;
  final String source;
  final int tokens;

  const SkillFrontmatter({
    required this.name,
    required this.source,
    required this.tokens,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'source': source,
    'tokens': tokens,
  };
}

/// Information about skills included in the context window.
class SkillInfo {
  final int totalSkills;
  final int includedSkills;
  final int tokens;
  final List<SkillFrontmatter> skillFrontmatter;

  const SkillInfo({
    required this.totalSkills,
    required this.includedSkills,
    required this.tokens,
    required this.skillFrontmatter,
  });

  Map<String, dynamic> toJson() => {
    'totalSkills': totalSkills,
    'includedSkills': includedSkills,
    'tokens': tokens,
    'skillFrontmatter': skillFrontmatter.map((s) => s.toJson()).toList(),
  };
}

/// Breakdown of token usage by tool type.
class ToolCallsByType {
  final String name;
  final int callTokens;
  final int resultTokens;

  const ToolCallsByType({
    required this.name,
    required this.callTokens,
    required this.resultTokens,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'callTokens': callTokens,
    'resultTokens': resultTokens,
  };
}

/// Breakdown of attachment tokens by type.
class AttachmentsByType {
  final String name;
  final int tokens;

  const AttachmentsByType({required this.name, required this.tokens});

  Map<String, dynamic> toJson() => {'name': name, 'tokens': tokens};
}

/// Message breakdown detail.
class MessageBreakdown {
  final int toolCallTokens;
  final int toolResultTokens;
  final int attachmentTokens;
  final int assistantMessageTokens;
  final int userMessageTokens;
  final List<ToolCallsByType> toolCallsByType;
  final List<AttachmentsByType> attachmentsByType;

  const MessageBreakdown({
    required this.toolCallTokens,
    required this.toolResultTokens,
    required this.attachmentTokens,
    required this.assistantMessageTokens,
    required this.userMessageTokens,
    required this.toolCallsByType,
    required this.attachmentsByType,
  });

  Map<String, dynamic> toJson() => {
    'toolCallTokens': toolCallTokens,
    'toolResultTokens': toolResultTokens,
    'attachmentTokens': attachmentTokens,
    'assistantMessageTokens': assistantMessageTokens,
    'userMessageTokens': userMessageTokens,
    'toolCallsByType': toolCallsByType.map((t) => t.toJson()).toList(),
    'attachmentsByType': attachmentsByType.map((a) => a.toJson()).toList(),
  };
}

/// API usage from last response.
class ApiUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  const ApiUsage({
    required this.inputTokens,
    required this.outputTokens,
    required this.cacheCreationInputTokens,
    required this.cacheReadInputTokens,
  });

  Map<String, dynamic> toJson() => {
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'cache_creation_input_tokens': cacheCreationInputTokens,
    'cache_read_input_tokens': cacheReadInputTokens,
  };

  factory ApiUsage.fromJson(Map<String, dynamic> json) => ApiUsage(
    inputTokens: json['input_tokens'] as int? ?? 0,
    outputTokens: json['output_tokens'] as int? ?? 0,
    cacheCreationInputTokens: json['cache_creation_input_tokens'] as int? ?? 0,
    cacheReadInputTokens: json['cache_read_input_tokens'] as int? ?? 0,
  );
}

/// Complete context analysis data.
class ContextData {
  final List<ContextCategory> categories;
  final int totalTokens;
  final int maxTokens;
  final int rawMaxTokens;
  final int percentage;
  final List<List<GridSquare>> gridRows;
  final String model;
  final List<MemoryFile> memoryFiles;
  final List<McpTool> mcpTools;
  final List<DeferredBuiltinTool>? deferredBuiltinTools;
  final List<SystemToolDetail>? systemTools;
  final List<SystemPromptSectionDetail>? systemPromptSections;
  final List<AgentInfo> agents;
  final SlashCommandInfo? slashCommands;
  final SkillInfo? skills;
  final int? autoCompactThreshold;
  final bool isAutoCompactEnabled;
  final MessageBreakdown? messageBreakdown;
  final ApiUsage? apiUsage;

  const ContextData({
    required this.categories,
    required this.totalTokens,
    required this.maxTokens,
    required this.rawMaxTokens,
    required this.percentage,
    required this.gridRows,
    required this.model,
    required this.memoryFiles,
    required this.mcpTools,
    this.deferredBuiltinTools,
    this.systemTools,
    this.systemPromptSections,
    required this.agents,
    this.slashCommands,
    this.skills,
    this.autoCompactThreshold,
    required this.isAutoCompactEnabled,
    this.messageBreakdown,
    this.apiUsage,
  });

  Map<String, dynamic> toJson() => {
    'categories': categories.map((c) => c.toJson()).toList(),
    'totalTokens': totalTokens,
    'maxTokens': maxTokens,
    'rawMaxTokens': rawMaxTokens,
    'percentage': percentage,
    'gridRows': gridRows
        .map((row) => row.map((s) => s.toJson()).toList())
        .toList(),
    'model': model,
    'memoryFiles': memoryFiles.map((m) => m.toJson()).toList(),
    'mcpTools': mcpTools.map((t) => t.toJson()).toList(),
    if (deferredBuiltinTools != null)
      'deferredBuiltinTools': deferredBuiltinTools!
          .map((t) => t.toJson())
          .toList(),
    if (systemTools != null)
      'systemTools': systemTools!.map((t) => t.toJson()).toList(),
    if (systemPromptSections != null)
      'systemPromptSections': systemPromptSections!
          .map((s) => s.toJson())
          .toList(),
    'agents': agents.map((a) => a.toJson()).toList(),
    if (slashCommands != null) 'slashCommands': slashCommands!.toJson(),
    if (skills != null) 'skills': skills!.toJson(),
    if (autoCompactThreshold != null)
      'autoCompactThreshold': autoCompactThreshold,
    'isAutoCompactEnabled': isAutoCompactEnabled,
    if (messageBreakdown != null)
      'messageBreakdown': messageBreakdown!.toJson(),
    if (apiUsage != null) 'apiUsage': apiUsage!.toJson(),
  };
}

// ---------------------------------------------------------------------------
// Internal message breakdown tracking
// ---------------------------------------------------------------------------

class _MutableMessageBreakdown {
  int totalTokens = 0;
  int toolCallTokens = 0;
  int toolResultTokens = 0;
  int attachmentTokens = 0;
  int assistantMessageTokens = 0;
  int userMessageTokens = 0;
  final Map<String, int> toolCallsByType = {};
  final Map<String, int> toolResultsByType = {};
  final Map<String, int> attachmentsByType = {};
}

// ---------------------------------------------------------------------------
// ContextAnalyzer SintController
// ---------------------------------------------------------------------------

/// Analyzes context window usage and provides visualization data.
class ContextAnalyzer extends SintController {
  /// The latest context analysis result.
  final Rxn<ContextData> latestAnalysis = Rxn<ContextData>(null);

  /// Callback for counting tokens with the API (or fallback).
  Future<int?> Function(
    List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>> tools,
  )
  _countTokensWithFallback = (_, _) async => null;

  /// Callback for rough token estimation.
  int Function(String text) _roughTokenCountEstimation = (text) =>
      (text.length / 4).ceil();

  /// Callback for getting the effective context window size.
  int Function(String model) _getEffectiveContextWindowSize = (_) => 200000;

  /// Callback for getting the context window for a model.
  int Function(String model) _getContextWindowForModel = (_) => 200000;

  /// Callback for checking if autocompact is enabled.
  bool Function() _isAutoCompactEnabled = () => true;

  /// Callback for getting the current API usage.
  ApiUsage? Function(List<Map<String, dynamic>> messages) _getCurrentUsage =
      (_) => null;

  /// Logging callback.
  // ignore: unused_field
  void Function(String message) _logForDebugging = (_) {};

  /// Error logging callback.
  // ignore: unused_field
  void Function(Object error) _logError = (_) {};

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void configure({
    Future<int?> Function(
      List<Map<String, dynamic>>,
      List<Map<String, dynamic>>,
    )?
    countTokensWithFallback,
    int Function(String)? roughTokenCountEstimation,
    int Function(String)? getEffectiveContextWindowSize,
    int Function(String)? getContextWindowForModel,
    bool Function()? isAutoCompactEnabled,
    ApiUsage? Function(List<Map<String, dynamic>>)? getCurrentUsage,
    void Function(String)? logForDebugging,
    void Function(Object)? logError,
  }) {
    if (countTokensWithFallback != null) {
      _countTokensWithFallback = countTokensWithFallback;
    }
    if (roughTokenCountEstimation != null) {
      _roughTokenCountEstimation = roughTokenCountEstimation;
    }
    if (getEffectiveContextWindowSize != null) {
      _getEffectiveContextWindowSize = getEffectiveContextWindowSize;
    }
    if (getContextWindowForModel != null) {
      _getContextWindowForModel = getContextWindowForModel;
    }
    if (isAutoCompactEnabled != null) {
      _isAutoCompactEnabled = isAutoCompactEnabled;
    }
    if (getCurrentUsage != null) _getCurrentUsage = getCurrentUsage;
    if (logForDebugging != null) _logForDebugging = logForDebugging;
    if (logError != null) _logError = logError;
  }

  // ---------------------------------------------------------------------------
  // Token counting helpers
  // ---------------------------------------------------------------------------

  /// Count tokens for a list of tool definitions.
  Future<int> countToolDefinitionTokens(
    List<Map<String, dynamic>> tools,
  ) async {
    final result = await _countTokensWithFallback([], tools);
    return result ?? 0;
  }

  /// Extract a human-readable name from a system prompt section's content.
  static String extractSectionName(String content) {
    // Try to find first markdown heading
    final headingMatch = RegExp(
      r'^#+\s+(.+)$',
      multiLine: true,
    ).firstMatch(content);
    if (headingMatch != null) return headingMatch.group(1)!.trim();
    // Fall back to a truncated preview
    final firstLine = content
        .split('\n')
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    return firstLine.length > 40
        ? '${firstLine.substring(0, 40)}...'
        : firstLine;
  }

  /// Count system prompt tokens.
  Future<({int systemPromptTokens, List<SystemPromptSectionDetail> sections})>
  countSystemTokens(List<String> effectiveSystemPrompt) async {
    final namedEntries = effectiveSystemPrompt
        .where((c) => c.isNotEmpty)
        .map((c) => (name: extractSectionName(c), content: c))
        .toList();

    if (namedEntries.isEmpty) {
      return (systemPromptTokens: 0, sections: <SystemPromptSectionDetail>[]);
    }

    final tokenCounts = await Future.wait(
      namedEntries.map(
        (entry) => _countTokensWithFallback([
          {'role': 'user', 'content': entry.content},
        ], []),
      ),
    );

    final sections = List.generate(namedEntries.length, (i) {
      return SystemPromptSectionDetail(
        name: namedEntries[i].name,
        tokens: tokenCounts[i] ?? 0,
      );
    });

    final total = tokenCounts.fold<int>(0, (sum, t) => sum + (t ?? 0));
    return (systemPromptTokens: total, sections: sections);
  }

  /// Count memory file tokens.
  Future<({int neomageMdTokens, List<MemoryFile> details})>
  countMemoryFileTokens(
    List<({String path, String type, String content})> memoryFiles,
  ) async {
    if (memoryFiles.isEmpty) {
      return (neomageMdTokens: 0, details: <MemoryFile>[]);
    }

    final results = await Future.wait(
      memoryFiles.map(
        (f) => _countTokensWithFallback([
          {'role': 'user', 'content': f.content},
        ], []),
      ),
    );

    int total = 0;
    final details = <MemoryFile>[];

    for (int i = 0; i < memoryFiles.length; i++) {
      final tokens = results[i] ?? 0;
      total += tokens;
      details.add(
        MemoryFile(
          path: memoryFiles[i].path,
          type: memoryFiles[i].type,
          tokens: tokens,
        ),
      );
    }

    return (neomageMdTokens: total, details: details);
  }

  // ---------------------------------------------------------------------------
  // Message breakdown
  // ---------------------------------------------------------------------------

  /// Approximate token usage by message type.
  MessageBreakdown approximateMessageBreakdown(
    List<Map<String, dynamic>> messages,
  ) {
    final breakdown = _MutableMessageBreakdown();
    final toolUseIdToName = <String, String>{};

    // Build tool_use_id to name map
    for (final msg in messages) {
      if (msg['type'] == 'assistant') {
        final content = msg['content'] as List<dynamic>? ?? [];
        for (final block in content) {
          if (block is Map && block['type'] == 'tool_use') {
            final id = block['id'] as String?;
            final name = block['name'] as String? ?? 'unknown';
            if (id != null) toolUseIdToName[id] = name;
          }
        }
      }
    }

    for (final msg in messages) {
      final type = msg['type'] as String?;

      if (type == 'assistant') {
        final content = msg['content'] as List<dynamic>? ?? [];
        for (final block in content) {
          if (block is Map) {
            final blockStr = block.toString();
            final blockTokens = _roughTokenCountEstimation(blockStr);
            if (block['type'] == 'tool_use') {
              breakdown.toolCallTokens += blockTokens;
              final toolName = block['name'] as String? ?? 'unknown';
              breakdown.toolCallsByType[toolName] =
                  (breakdown.toolCallsByType[toolName] ?? 0) + blockTokens;
            } else {
              breakdown.assistantMessageTokens += blockTokens;
            }
          }
        }
      } else if (type == 'user') {
        final content = msg['content'];
        if (content is String) {
          breakdown.userMessageTokens += _roughTokenCountEstimation(content);
        } else if (content is List) {
          for (final block in content) {
            if (block is Map) {
              final blockStr = block.toString();
              final blockTokens = _roughTokenCountEstimation(blockStr);
              if (block['type'] == 'tool_result') {
                breakdown.toolResultTokens += blockTokens;
                final toolUseId = block['tool_use_id'] as String?;
                final toolName =
                    (toolUseId != null ? toolUseIdToName[toolUseId] : null) ??
                    'unknown';
                breakdown.toolResultsByType[toolName] =
                    (breakdown.toolResultsByType[toolName] ?? 0) + blockTokens;
              } else {
                breakdown.userMessageTokens += blockTokens;
              }
            }
          }
        }
      } else if (type == 'attachment') {
        final attachment = msg['attachment'] as Map<String, dynamic>?;
        if (attachment != null) {
          final tokens = _roughTokenCountEstimation(attachment.toString());
          breakdown.attachmentTokens += tokens;
          final attachType = attachment['type'] as String? ?? 'unknown';
          breakdown.attachmentsByType[attachType] =
              (breakdown.attachmentsByType[attachType] ?? 0) + tokens;
        }
      }
    }

    breakdown.totalTokens =
        breakdown.toolCallTokens +
        breakdown.toolResultTokens +
        breakdown.attachmentTokens +
        breakdown.assistantMessageTokens +
        breakdown.userMessageTokens;

    // Convert to sorted lists
    final toolCallsByType =
        breakdown.toolCallsByType.entries
            .map(
              (e) => ToolCallsByType(
                name: e.key,
                callTokens: e.value,
                resultTokens: breakdown.toolResultsByType[e.key] ?? 0,
              ),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.callTokens + b.resultTokens) -
                (a.callTokens + a.resultTokens),
          );

    final attachmentsByType =
        breakdown.attachmentsByType.entries
            .map((e) => AttachmentsByType(name: e.key, tokens: e.value))
            .toList()
          ..sort((a, b) => b.tokens - a.tokens);

    return MessageBreakdown(
      toolCallTokens: breakdown.toolCallTokens,
      toolResultTokens: breakdown.toolResultTokens,
      attachmentTokens: breakdown.attachmentTokens,
      assistantMessageTokens: breakdown.assistantMessageTokens,
      userMessageTokens: breakdown.userMessageTokens,
      toolCallsByType: toolCallsByType,
      attachmentsByType: attachmentsByType,
    );
  }

  // ---------------------------------------------------------------------------
  // Grid visualization
  // ---------------------------------------------------------------------------

  /// Build the grid visualization from categories.
  List<List<GridSquare>> buildGrid({
    required List<ContextCategory> categories,
    required int contextWindow,
    int? terminalWidth,
  }) {
    final isNarrowScreen = terminalWidth != null && terminalWidth < 80;
    final gridWidth = contextWindow >= 1000000
        ? (isNarrowScreen ? 5 : 20)
        : (isNarrowScreen ? 5 : 10);
    final gridHeight = contextWindow >= 1000000
        ? 10
        : (isNarrowScreen ? 5 : 10);
    final totalSquares = gridWidth * gridHeight;

    // Filter out deferred categories
    final nonDeferred = categories.where((c) => !c.isDeferred).toList();

    // Calculate squares per category
    final categorySquares = nonDeferred.map((cat) {
      final squares = cat.name == 'Free space'
          ? ((cat.tokens / contextWindow) * totalSquares).round()
          : max(1, ((cat.tokens / contextWindow) * totalSquares).round());
      final percentage = ((cat.tokens / contextWindow) * 100).round();
      return (category: cat, squares: squares, percentage: percentage);
    }).toList();

    // Build grid squares
    final gridSquares = <GridSquare>[];

    // Separate reserved category
    final reservedCat = categorySquares
        .where(
          (c) =>
              c.category.name == _reservedCategoryName ||
              c.category.name == _manualCompactBufferName,
        )
        .firstOrNull;
    final nonReservedCats = categorySquares
        .where(
          (c) =>
              c.category.name != _reservedCategoryName &&
              c.category.name != _manualCompactBufferName &&
              c.category.name != 'Free space',
        )
        .toList();

    // Add non-reserved squares
    for (final cat in nonReservedCats) {
      final exactSquares = (cat.category.tokens / contextWindow) * totalSquares;
      final wholeSquares = exactSquares.floor();
      final fractionalPart = exactSquares - wholeSquares;

      for (
        int i = 0;
        i < cat.squares && gridSquares.length < totalSquares;
        i++
      ) {
        double squareFullness = 1.0;
        if (i == wholeSquares && fractionalPart > 0) {
          squareFullness = fractionalPart;
        }
        gridSquares.add(
          GridSquare(
            color: cat.category.color,
            isFilled: true,
            categoryName: cat.category.name,
            tokens: cat.category.tokens,
            percentage: cat.percentage,
            squareFullness: squareFullness,
          ),
        );
      }
    }

    // Fill with free space
    final reservedSquareCount = reservedCat?.squares ?? 0;
    final freeSpaceTarget = totalSquares - reservedSquareCount;
    final freeSpaceCat = categories
        .where((c) => c.name == 'Free space')
        .firstOrNull;

    while (gridSquares.length < freeSpaceTarget) {
      gridSquares.add(
        GridSquare(
          color: 'promptBorder',
          isFilled: true,
          categoryName: 'Free space',
          tokens: freeSpaceCat?.tokens ?? 0,
          percentage: freeSpaceCat != null
              ? ((freeSpaceCat.tokens / contextWindow) * 100).round()
              : 0,
          squareFullness: 1.0,
        ),
      );
    }

    // Add reserved squares at the end
    if (reservedCat != null) {
      for (
        int i = 0;
        i < reservedCat.squares && gridSquares.length < totalSquares;
        i++
      ) {
        gridSquares.add(
          GridSquare(
            color: reservedCat.category.color,
            isFilled: true,
            categoryName: reservedCat.category.name,
            tokens: reservedCat.category.tokens,
            percentage: reservedCat.percentage,
            squareFullness: 1.0,
          ),
        );
      }
    }

    // Convert to rows
    final gridRows = <List<GridSquare>>[];
    for (int i = 0; i < gridHeight; i++) {
      final start = i * gridWidth;
      final end = min(start + gridWidth, gridSquares.length);
      if (start < gridSquares.length) {
        gridRows.add(gridSquares.sublist(start, end));
      }
    }

    return gridRows;
  }

  // ---------------------------------------------------------------------------
  // Main analysis
  // ---------------------------------------------------------------------------

  /// Analyzes context window usage for display.
  Future<ContextData> analyzeContextUsage({
    required List<Map<String, dynamic>> messages,
    required String model,
    required int systemPromptTokens,
    required int neomageMdTokens,
    required int builtInToolTokens,
    required int mcpToolTokens,
    required int agentTokens,
    required int slashCommandTokens,
    required int skillFrontmatterTokens,
    required int messageTokens,
    required int deferredToolTokens,
    required int deferredBuiltinTokens,
    required List<MemoryFile> memoryFileDetails,
    required List<McpTool> mcpToolDetails,
    required List<AgentInfo> agentDetails,
    List<DeferredBuiltinTool>? deferredBuiltinDetails,
    List<SystemToolDetail>? systemToolDetails,
    List<SystemPromptSectionDetail>? systemPromptSections,
    SlashCommandInfo? commandInfo,
    SkillInfo? skillInfo,
    MessageBreakdown? messageBreakdownDetail,
    int? terminalWidth,
  }) async {
    final contextWindow = _getContextWindowForModel(model);
    final isAutoCompact = _isAutoCompactEnabled();
    final autoCompactThreshold = isAutoCompact
        ? _getEffectiveContextWindowSize(model) - autocompactBufferTokens
        : null;

    // Build categories
    final cats = <ContextCategory>[];

    if (systemPromptTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'System prompt',
          tokens: systemPromptTokens,
          color: 'promptBorder',
        ),
      );
    }

    final systemToolsTokens = builtInToolTokens - skillFrontmatterTokens;
    if (systemToolsTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'System tools',
          tokens: systemToolsTokens,
          color: 'inactive',
        ),
      );
    }

    if (mcpToolTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'MCP tools',
          tokens: mcpToolTokens,
          color: 'cyan',
        ),
      );
    }

    if (deferredToolTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'MCP tools (deferred)',
          tokens: deferredToolTokens,
          color: 'inactive',
          isDeferred: true,
        ),
      );
    }

    if (deferredBuiltinTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'System tools (deferred)',
          tokens: deferredBuiltinTokens,
          color: 'inactive',
          isDeferred: true,
        ),
      );
    }

    if (agentTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'Custom agents',
          tokens: agentTokens,
          color: 'permission',
        ),
      );
    }

    if (neomageMdTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'Memory files',
          tokens: neomageMdTokens,
          color: 'neomage',
        ),
      );
    }

    if (skillFrontmatterTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'Skills',
          tokens: skillFrontmatterTokens,
          color: 'warning',
        ),
      );
    }

    if (messageTokens > 0) {
      cats.add(
        ContextCategory(
          name: 'Messages',
          tokens: messageTokens,
          color: 'purple',
        ),
      );
    }

    // Calculate actual content usage
    final actualUsage = cats.fold<int>(
      0,
      (sum, cat) => sum + (cat.isDeferred ? 0 : cat.tokens),
    );

    // Reserved space
    int reservedTokens = 0;
    if (isAutoCompact && autoCompactThreshold != null) {
      reservedTokens = contextWindow - autoCompactThreshold;
      cats.add(
        ContextCategory(
          name: _reservedCategoryName,
          tokens: reservedTokens,
          color: 'inactive',
        ),
      );
    } else if (!isAutoCompact) {
      reservedTokens = manualCompactBufferTokens;
      cats.add(
        ContextCategory(
          name: _manualCompactBufferName,
          tokens: reservedTokens,
          color: 'inactive',
        ),
      );
    }

    // Free space
    final freeTokens = max(0, contextWindow - actualUsage - reservedTokens);
    cats.add(
      ContextCategory(
        name: 'Free space',
        tokens: freeTokens,
        color: 'promptBorder',
      ),
    );

    final totalIncludingReserved = actualUsage;

    // API usage
    final apiUsage = _getCurrentUsage(messages);
    final totalFromAPI = apiUsage != null
        ? apiUsage.inputTokens +
              apiUsage.cacheCreationInputTokens +
              apiUsage.cacheReadInputTokens
        : null;

    final finalTotalTokens = totalFromAPI ?? totalIncludingReserved;

    // Build grid
    final gridRows = buildGrid(
      categories: cats,
      contextWindow: contextWindow,
      terminalWidth: terminalWidth,
    );

    final result = ContextData(
      categories: cats,
      totalTokens: finalTotalTokens,
      maxTokens: contextWindow,
      rawMaxTokens: contextWindow,
      percentage: ((finalTotalTokens / contextWindow) * 100).round(),
      gridRows: gridRows,
      model: model,
      memoryFiles: memoryFileDetails,
      mcpTools: mcpToolDetails,
      deferredBuiltinTools: deferredBuiltinDetails,
      systemTools: systemToolDetails,
      systemPromptSections: systemPromptSections,
      agents: agentDetails,
      slashCommands: commandInfo,
      skills: skillInfo,
      autoCompactThreshold: autoCompactThreshold,
      isAutoCompactEnabled: isAutoCompact,
      messageBreakdown: messageBreakdownDetail,
      apiUsage: apiUsage,
    );

    latestAnalysis.value = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }
}
