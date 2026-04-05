// AgentTool — port of neomage/src/tools/AgentTool.
// Spawns sub-agents to handle complex, multi-step tasks autonomously.

import 'dart:async';

import '../../domain/models/message.dart';
import '../api/api_provider.dart';
import 'tool.dart';
import 'tool_registry.dart';

/// Agent definition — describes a type of sub-agent that can be spawned.
class AgentDefinition {
  final String agentType;
  final String name;
  final String description;
  final String? systemPrompt;
  final Set<String>? tools;
  final Set<String>? disallowedTools;
  final String? model;
  final bool background;
  final bool isBuiltIn;

  const AgentDefinition({
    required this.agentType,
    required this.name,
    required this.description,
    this.systemPrompt,
    this.tools,
    this.disallowedTools,
    this.model,
    this.background = false,
    this.isBuiltIn = true,
  });
}

/// Built-in agent definitions.
class BuiltInAgents {
  static const generalPurpose = AgentDefinition(
    agentType: 'general-purpose',
    name: 'General Purpose',
    description:
        'General-purpose agent for researching complex questions, '
        'searching for code, and executing multi-step tasks.',
    background: false,
  );

  static const explore = AgentDefinition(
    agentType: 'Explore',
    name: 'Explore',
    description:
        'Fast agent specialized for exploring codebases. '
        'Use for finding files, searching code, or answering codebase questions.',
    tools: {'Read', 'Glob', 'Grep', 'Bash', 'WebSearch', 'WebFetch'},
    disallowedTools: {'Agent', 'Edit', 'Write', 'NotebookEdit'},
    background: false,
  );

  static const plan = AgentDefinition(
    agentType: 'Plan',
    name: 'Plan',
    description: 'Software architect agent for designing implementation plans.',
    disallowedTools: {'Agent', 'Edit', 'Write', 'NotebookEdit'},
    background: false,
  );

  static const all = [generalPurpose, explore, plan];

  static AgentDefinition? findByType(String type) {
    for (final agent in all) {
      if (agent.agentType == type) return agent;
    }
    return null;
  }
}

/// Result of a sub-agent execution.
class AgentResult {
  final String agentId;
  final String status;
  final String content;
  final int totalToolUseCount;
  final int totalDurationMs;
  final TokenUsage usage;

  const AgentResult({
    required this.agentId,
    required this.status,
    required this.content,
    required this.totalToolUseCount,
    required this.totalDurationMs,
    required this.usage,
  });
}

/// Progress update from a running agent.
class AgentProgress {
  final String agentId;
  final String description;
  final int totalTokens;
  final int toolUses;
  final String? lastToolName;

  const AgentProgress({
    required this.agentId,
    required this.description,
    required this.totalTokens,
    required this.toolUses,
    this.lastToolName,
  });
}

/// Callback for agent progress updates.
typedef OnAgentProgress = void Function(AgentProgress progress);

/// AgentTool — spawns sub-agents for complex tasks.
class AgentTool extends Tool {
  final ApiProvider provider;
  final ToolRegistry toolRegistry;
  final String Function() systemPromptBuilder;
  final OnAgentProgress? onProgress;

  /// Active sub-agents tracked by ID.
  final Map<String, _RunningAgent> _activeAgents = {};

  /// Custom agent definitions (from markdown files, plugins, etc).
  final List<AgentDefinition> _customAgents = [];

  AgentTool({
    required this.provider,
    required this.toolRegistry,
    required this.systemPromptBuilder,
    this.onProgress,
  });

  @override
  String get name => 'Agent';

  @override
  String get description =>
      'Launch a new agent to handle complex, multi-step tasks autonomously. '
      'Each agent runs in its own context with access to tools.';

  @override
  bool get shouldDefer => false;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'prompt': {
        'type': 'string',
        'description': 'The task for the agent to perform',
      },
      'description': {
        'type': 'string',
        'description': 'A short (3-5 word) description of the task',
      },
      'subagent_type': {
        'type': 'string',
        'description': 'The type of specialized agent to use',
      },
      'model': {
        'type': 'string',
        'enum': ['sonnet', 'opus', 'haiku'],
        'description': 'Optional model override for this agent',
      },
      'run_in_background': {
        'type': 'boolean',
        'description': 'Run agent in background (default: false)',
      },
    },
    'required': ['description', 'prompt'],
  };

  /// Register a custom agent definition.
  void registerAgent(AgentDefinition agent) {
    _customAgents.add(agent);
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final prompt = input['prompt'] as String?;
    final description = input['description'] as String?;
    final subagentType = input['subagent_type'] as String?;
    final modelOverride = input['model'] as String?;
    final runInBackground = input['run_in_background'] as bool? ?? false;

    if (prompt == null || prompt.isEmpty) {
      return ToolResult.error('Missing required parameter: prompt');
    }
    if (description == null || description.isEmpty) {
      return ToolResult.error('Missing required parameter: description');
    }

    // Resolve agent definition
    final effectiveType = subagentType ?? 'general-purpose';
    final agentDef = _resolveAgent(effectiveType);
    if (agentDef == null) {
      return ToolResult.error(
        'Unknown agent type: $effectiveType. '
        'Available: ${_availableAgentTypes().join(", ")}',
      );
    }

    // Resolve model
    final model = modelOverride ?? agentDef.model;

    // Resolve available tools for this agent
    final agentTools = _resolveAgentTools(agentDef);

    final agentId = 'agent_${DateTime.now().millisecondsSinceEpoch}';
    final startTime = DateTime.now();

    if (runInBackground) {
      // Launch async and return immediately
      _launchBackground(
        agentId: agentId,
        prompt: prompt,
        description: description,
        agentDef: agentDef,
        tools: agentTools,
        model: model,
      );

      return ToolResult.success(
        'Agent launched in background.\n'
        'Agent ID: $agentId\n'
        'Type: ${agentDef.agentType}\n'
        'Description: $description',
        metadata: {'status': 'async_launched', 'agentId': agentId},
      );
    }

    // Synchronous execution
    try {
      final result = await _runAgent(
        agentId: agentId,
        prompt: prompt,
        description: description,
        agentDef: agentDef,
        tools: agentTools,
        model: model,
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds;

      return ToolResult.success(
        result.content,
        metadata: {
          'status': 'completed',
          'agentId': agentId,
          'totalToolUseCount': result.totalToolUseCount,
          'totalDurationMs': duration,
          'totalTokens': result.usage.totalTokens,
        },
      );
    } catch (e) {
      return ToolResult.error('Agent error: $e');
    }
  }

  AgentDefinition? _resolveAgent(String type) {
    // Check built-in first
    final builtIn = BuiltInAgents.findByType(type);
    if (builtIn != null) return builtIn;

    // Check custom agents
    for (final agent in _customAgents) {
      if (agent.agentType == type) return agent;
    }
    return null;
  }

  List<String> _availableAgentTypes() {
    return [
      ...BuiltInAgents.all.map((a) => a.agentType),
      ..._customAgents.map((a) => a.agentType),
    ];
  }

  List<Tool> _resolveAgentTools(AgentDefinition agentDef) {
    var tools = toolRegistry.available.toList();

    // Filter to allowed tools if specified
    if (agentDef.tools != null) {
      tools = tools.where((t) => agentDef.tools!.contains(t.name)).toList();
    }

    // Remove disallowed tools
    if (agentDef.disallowedTools != null) {
      tools = tools
          .where((t) => !agentDef.disallowedTools!.contains(t.name))
          .toList();
    }

    // Never allow recursive agent spawning from sub-agents
    tools = tools.where((t) => t.name != 'Agent').toList();

    return tools;
  }

  Future<AgentResult> _runAgent({
    required String agentId,
    required String prompt,
    required String description,
    required AgentDefinition agentDef,
    required List<Tool> tools,
    String? model,
  }) async {
    final running = _RunningAgent(
      id: agentId,
      description: description,
      definition: agentDef,
    );
    _activeAgents[agentId] = running;

    try {
      // Build agent system prompt
      final systemPrompt = agentDef.systemPrompt ?? systemPromptBuilder();

      // Build tool definitions for the sub-agent
      final toolDefs = tools.map((t) => t.definition).toList();

      // Initial message
      final messages = <Message>[Message.user(prompt)];

      var totalToolUses = 0;
      var totalInputTokens = 0;
      var totalOutputTokens = 0;
      final maxTurns = 25;

      // Agentic loop for the sub-agent
      for (var turn = 0; turn < maxTurns; turn++) {
        final response = await provider.createMessage(
          messages: messages,
          systemPrompt: systemPrompt,
          tools: toolDefs,
          maxTokens: 16384,
        );

        totalInputTokens += response.usage?.inputTokens ?? 0;
        totalOutputTokens += response.usage?.outputTokens ?? 0;

        messages.add(response);

        // Check if agent is done (no tool use)
        final toolUses = response.toolUses;
        if (toolUses.isEmpty || response.stopReason == StopReason.endTurn) {
          break;
        }

        // Execute tools and collect results
        final resultBlocks = <ContentBlock>[];
        for (final toolUse in toolUses) {
          totalToolUses++;

          // Report progress
          onProgress?.call(
            AgentProgress(
              agentId: agentId,
              description: description,
              totalTokens: totalInputTokens + totalOutputTokens,
              toolUses: totalToolUses,
              lastToolName: toolUse.name,
            ),
          );

          // Find and execute tool
          final tool = tools.firstWhere(
            (t) => t.name == toolUse.name,
            orElse: () => _unknownTool,
          );

          final result = await tool.execute(toolUse.input);
          resultBlocks.add(
            ToolResultBlock(
              toolUseId: toolUse.id,
              content: result.content,
              isError: result.isError,
            ),
          );
        }

        // Add tool results as user message
        messages.add(Message(role: MessageRole.user, content: resultBlocks));
      }

      // Extract final text content
      final lastAssistant = messages.lastWhere(
        (m) => m.role == MessageRole.assistant,
        orElse: () => Message.assistant('Agent completed without output.'),
      );

      return AgentResult(
        agentId: agentId,
        status: 'completed',
        content: lastAssistant.textContent,
        totalToolUseCount: totalToolUses,
        totalDurationMs: 0, // Caller computes this
        usage: TokenUsage(
          inputTokens: totalInputTokens,
          outputTokens: totalOutputTokens,
        ),
      );
    } finally {
      _activeAgents.remove(agentId);
    }
  }

  void _launchBackground({
    required String agentId,
    required String prompt,
    required String description,
    required AgentDefinition agentDef,
    required List<Tool> tools,
    String? model,
  }) {
    // Fire and forget — run in background
    unawaited(
      _runAgent(
            agentId: agentId,
            prompt: prompt,
            description: description,
            agentDef: agentDef,
            tools: tools,
            model: model,
          )
          .then((_) {
            // Agent completed
          })
          .catchError((_) {
            // Agent errored — tracked via _activeAgents removal
          }),
    );
  }

  /// Get info about an active agent by ID. Returns null if not active.
  ({String id, String description, DateTime startTime})? getActiveAgent(
    String agentId,
  ) {
    final agent = _activeAgents[agentId];
    if (agent == null) return null;
    return (
      id: agent.id,
      description: agent.description,
      startTime: agent.startTime,
    );
  }

  /// All active agent IDs.
  Set<String> get activeAgentIds => _activeAgents.keys.toSet();

  static final _unknownTool = _UnknownTool();
}

class _RunningAgent {
  final String id;
  final String description;
  final AgentDefinition definition;
  final DateTime startTime;

  _RunningAgent({
    required this.id,
    required this.description,
    required this.definition,
  }) : startTime = DateTime.now();
}

class _UnknownTool extends Tool {
  @override
  String get name => '__unknown__';
  @override
  String get description => '';
  @override
  Map<String, dynamic> get inputSchema => {};
  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async =>
      ToolResult.error('Unknown tool');
}
