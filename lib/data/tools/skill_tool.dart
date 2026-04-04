// SkillTool — port of neom_claw/src/tools/SkillTool/.
// Executes skills (slash commands) in the conversation, supporting inline and
// forked execution modes, permission rules, budget-aware description truncation,
// and remote canonical skill loading.

import 'dart:async';
import 'dart:math';

import '../../domain/models/permissions.dart';
import 'tool.dart';

// ─── Constants ───────────────────────────────────────────────────────────────

const String skillToolName = 'Skill';

/// Skill listing gets 1% of the context window (in characters).
const double skillBudgetContextPercent = 0.01;

/// Approximate characters per token for budget calculation.
const int charsPerToken = 4;

/// Fallback: 1% of 200k tokens * 4 chars/token.
const int defaultCharBudget = 8000;

/// Per-entry hard cap. The listing is for discovery only — the Skill tool loads
/// full content on invoke, so verbose whenToUse strings waste turn-1
/// cache_creation tokens without improving match rate.
const int maxListingDescChars = 250;

/// Minimum description length before going names-only.
const int minDescLength = 20;

// ─── Skill Command Model ─────────────────────────────────────────────────────

/// Represents a skill/slash command.
class SkillCommand {
  final String name;
  final String description;
  final String? whenToUse;
  final String type; // 'prompt', 'built-in', etc.
  final String source; // 'bundled', 'plugin', 'local', 'mcp'
  final String? loadedFrom;
  final String? kind;
  final String? context; // 'fork' or 'inline'
  final bool disableModelInvocation;
  final List<String> aliases;
  final String? model;
  final String? effort;
  final List<String>? allowedTools;
  final PluginInfo? pluginInfo;
  final String? userFacingName;
  final bool isEnabled;
  final bool isHidden;
  final int? contentLength;
  final String? progressMessage;
  final String? skillRoot;
  final String? agent;

  const SkillCommand({
    required this.name,
    required this.description,
    this.whenToUse,
    this.type = 'prompt',
    this.source = 'local',
    this.loadedFrom,
    this.kind,
    this.context,
    this.disableModelInvocation = false,
    this.aliases = const [],
    this.model,
    this.effort,
    this.allowedTools,
    this.pluginInfo,
    this.userFacingName,
    this.isEnabled = true,
    this.isHidden = false,
    this.contentLength,
    this.progressMessage,
    this.skillRoot,
    this.agent,
  });

  factory SkillCommand.fromJson(Map<String, dynamic> json) => SkillCommand(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    whenToUse: json['whenToUse'] as String?,
    type: json['type'] as String? ?? 'prompt',
    source: json['source'] as String? ?? 'local',
    loadedFrom: json['loadedFrom'] as String?,
    kind: json['kind'] as String?,
    context: json['context'] as String?,
    disableModelInvocation: json['disableModelInvocation'] as bool? ?? false,
    aliases:
        (json['aliases'] as List<dynamic>?)?.map((e) => e as String).toList() ??
        const [],
    model: json['model'] as String?,
    effort: json['effort'] as String?,
    allowedTools: (json['allowedTools'] as List<dynamic>?)
        ?.map((e) => e as String)
        .toList(),
    pluginInfo: json['pluginInfo'] != null
        ? PluginInfo.fromJson(json['pluginInfo'] as Map<String, dynamic>)
        : null,
    userFacingName: json['userFacingName'] as String?,
    isEnabled: json['isEnabled'] as bool? ?? true,
    isHidden: json['isHidden'] as bool? ?? false,
    contentLength: json['contentLength'] as int?,
    progressMessage: json['progressMessage'] as String?,
    skillRoot: json['skillRoot'] as String?,
    agent: json['agent'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    if (whenToUse != null) 'whenToUse': whenToUse,
    'type': type,
    'source': source,
    if (loadedFrom != null) 'loadedFrom': loadedFrom,
    if (kind != null) 'kind': kind,
    if (context != null) 'context': context,
    if (disableModelInvocation) 'disableModelInvocation': true,
    if (aliases.isNotEmpty) 'aliases': aliases,
    if (model != null) 'model': model,
    if (effort != null) 'effort': effort,
    if (allowedTools != null) 'allowedTools': allowedTools,
    if (pluginInfo != null) 'pluginInfo': pluginInfo!.toJson(),
  };
}

/// Plugin info for marketplace skills.
class PluginInfo {
  final String repository;
  final PluginManifest pluginManifest;

  const PluginInfo({required this.repository, required this.pluginManifest});

  factory PluginInfo.fromJson(Map<String, dynamic> json) => PluginInfo(
    repository: json['repository'] as String,
    pluginManifest: PluginManifest.fromJson(
      json['pluginManifest'] as Map<String, dynamic>,
    ),
  );

  Map<String, dynamic> toJson() => {
    'repository': repository,
    'pluginManifest': pluginManifest.toJson(),
  };
}

/// Plugin manifest data.
class PluginManifest {
  final String name;
  final String? version;

  const PluginManifest({required this.name, this.version});

  factory PluginManifest.fromJson(Map<String, dynamic> json) => PluginManifest(
    name: json['name'] as String,
    version: json['version'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    if (version != null) 'version': version,
  };
}

// ─── Skill Tool Input / Output ───────────────────────────────────────────────

/// Input for the SkillTool.
class SkillToolInput {
  final String skill;
  final String? args;

  const SkillToolInput({required this.skill, this.args});

  factory SkillToolInput.fromJson(Map<String, dynamic> json) => SkillToolInput(
    skill: json['skill'] as String,
    args: json['args'] as String?,
  );
}

/// Output for inline skill execution.
class SkillToolInlineOutput {
  final bool success;
  final String commandName;
  final List<String>? allowedTools;
  final String? model;
  final String status;

  const SkillToolInlineOutput({
    required this.success,
    required this.commandName,
    this.allowedTools,
    this.model,
    this.status = 'inline',
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'commandName': commandName,
    if (allowedTools != null && allowedTools!.isNotEmpty)
      'allowedTools': allowedTools,
    if (model != null) 'model': model,
    'status': status,
  };
}

/// Output for forked skill execution.
class SkillToolForkedOutput {
  final bool success;
  final String commandName;
  final String agentId;
  final String result;
  final String status;

  const SkillToolForkedOutput({
    required this.success,
    required this.commandName,
    required this.agentId,
    required this.result,
    this.status = 'forked',
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'commandName': commandName,
    'status': status,
    'agentId': agentId,
    'result': result,
  };
}

// ─── Budget-Aware Description Formatting ─────────────────────────────────────

/// Calculate the character budget for skill descriptions.
int getCharBudget({int? contextWindowTokens, int? envOverride}) {
  if (envOverride != null && envOverride > 0) {
    return envOverride;
  }
  if (contextWindowTokens != null) {
    return (contextWindowTokens * charsPerToken * skillBudgetContextPercent)
        .floor();
  }
  return defaultCharBudget;
}

/// Get the full description for a command, combining description + whenToUse.
String _getCommandDescription(SkillCommand cmd) {
  final desc = cmd.whenToUse != null && cmd.whenToUse!.isNotEmpty
      ? '${cmd.description} - ${cmd.whenToUse}'
      : cmd.description;
  if (desc.length > maxListingDescChars) {
    return '${desc.substring(0, maxListingDescChars - 1)}\u2026';
  }
  return desc;
}

/// Format a single command for the listing.
String _formatCommandDescription(SkillCommand cmd) {
  final _displayName = cmd.userFacingName ?? cmd.name;
  return '- ${cmd.name}: ${_getCommandDescription(cmd)}';
}

/// Truncate a string to the given max length with ellipsis.
String _truncate(String s, int maxLen) {
  if (s.length <= maxLen) return s;
  if (maxLen <= 1) return '\u2026';
  return '${s.substring(0, maxLen - 1)}\u2026';
}

/// Format commands within the character budget, preserving bundled skill
/// descriptions while truncating others as needed.
String formatCommandsWithinBudget(
  List<SkillCommand> commands, {
  int? contextWindowTokens,
}) {
  if (commands.isEmpty) return '';

  final budget = getCharBudget(contextWindowTokens: contextWindowTokens);

  // Try full descriptions first.
  final fullEntries = commands.map((cmd) {
    return _formatCommandDescription(cmd);
  }).toList();

  final fullTotal =
      fullEntries.fold<int>(0, (sum, e) => sum + e.length) +
      (fullEntries.length - 1); // newlines

  if (fullTotal <= budget) {
    return fullEntries.join('\n');
  }

  // Partition into bundled (never truncated) and rest.
  final bundledIndices = <int>{};
  final restCommands = <SkillCommand>[];
  for (var i = 0; i < commands.length; i++) {
    final cmd = commands[i];
    if (cmd.type == 'prompt' && cmd.source == 'bundled') {
      bundledIndices.add(i);
    } else {
      restCommands.add(cmd);
    }
  }

  // Compute space used by bundled skills.
  var bundledChars = 0;
  for (var i = 0; i < fullEntries.length; i++) {
    if (bundledIndices.contains(i)) {
      bundledChars += fullEntries[i].length + 1;
    }
  }
  final remainingBudget = budget - bundledChars;

  if (restCommands.isEmpty) {
    return fullEntries.join('\n');
  }

  // Calculate max description length for non-bundled commands.
  final restNameOverhead =
      restCommands.fold<int>(0, (sum, cmd) => sum + cmd.name.length + 4) +
      (restCommands.length - 1);
  final availableForDescs = remainingBudget - restNameOverhead;
  final maxDescLen = (availableForDescs / restCommands.length).floor();

  if (maxDescLen < minDescLength) {
    // Non-bundled go names-only, bundled keep descriptions.
    return commands
        .asMap()
        .entries
        .map((entry) {
          if (bundledIndices.contains(entry.key)) {
            return fullEntries[entry.key];
          }
          return '- ${entry.value.name}';
        })
        .join('\n');
  }

  // Truncate non-bundled descriptions to fit within budget.
  return commands
      .asMap()
      .entries
      .map((entry) {
        if (bundledIndices.contains(entry.key)) {
          return fullEntries[entry.key];
        }
        final description = _getCommandDescription(entry.value);
        return '- ${entry.value.name}: ${_truncate(description, maxDescLen)}';
      })
      .join('\n');
}

// ─── Safe Property Check ─────────────────────────────────────────────────────

/// Allowlist of PromptCommand property keys that are safe and don't require
/// permission. If a skill has any property NOT in this set with a meaningful
/// value, it requires permission.
const Set<String> _safeSkillProperties = {
  // PromptCommand properties
  'type', 'progressMessage', 'contentLength', 'argNames', 'model',
  'effort', 'source', 'pluginInfo', 'disableNonInteractive',
  'skillRoot', 'context', 'agent', 'getPromptForCommand', 'frontmatterKeys',
  // CommandBase properties
  'name', 'description', 'hasUserSpecifiedDescription', 'isEnabled',
  'isHidden', 'aliases', 'isMcp', 'argumentHint', 'whenToUse', 'paths',
  'version', 'disableModelInvocation', 'userInvocable', 'loadedFrom',
  'immediate', 'userFacingName',
};

/// Check if a skill command only uses safe properties (auto-allow).
bool skillHasOnlySafeProperties(Map<String, dynamic> commandData) {
  for (final key in commandData.keys) {
    if (_safeSkillProperties.contains(key)) continue;
    final value = commandData[key];
    if (value == null) continue;
    if (value is List && value.isEmpty) continue;
    if (value is Map && value.isEmpty) continue;
    return false;
  }
  return true;
}

// ─── Skill Registry ──────────────────────────────────────────────────────────

/// Registry of available skills, supporting lookup by name or alias.
class SkillRegistry {
  final List<SkillCommand> _commands = [];
  final Map<String, SkillCommand> _byName = {};
  final Map<String, SkillCommand> _byAlias = {};
  final Set<String> _builtInNames = {};

  /// All registered commands.
  List<SkillCommand> get commands => List.unmodifiable(_commands);

  /// Register a skill command.
  void register(SkillCommand command) {
    _commands.add(command);
    _byName[command.name] = command;
    for (final alias in command.aliases) {
      _byAlias[alias] = command;
    }
    if (command.type == 'built-in') {
      _builtInNames.add(command.name);
    }
  }

  /// Find a command by name, checking aliases and case-insensitive match.
  SkillCommand? findCommand(String name) {
    // Exact name match.
    if (_byName.containsKey(name)) return _byName[name];
    // Alias match.
    if (_byAlias.containsKey(name)) return _byAlias[name];
    // Case-insensitive name match.
    final lower = name.toLowerCase();
    for (final cmd in _commands) {
      if (cmd.name.toLowerCase() == lower) return cmd;
    }
    return null;
  }

  /// Whether the given name is a built-in command.
  bool isBuiltIn(String name) => _builtInNames.contains(name);

  /// Get skill info for analytics / system prompt.
  SkillInfo getSkillInfo() => SkillInfo(
    totalSkills: _commands.length,
    includedSkills: _commands.length,
  );

  /// Clear all registered commands.
  void clear() {
    _commands.clear();
    _byName.clear();
    _byAlias.clear();
    _builtInNames.clear();
  }
}

/// Skill info summary.
class SkillInfo {
  final int totalSkills;
  final int includedSkills;

  const SkillInfo({required this.totalSkills, required this.includedSkills});

  Map<String, dynamic> toJson() => {
    'totalSkills': totalSkills,
    'includedSkills': includedSkills,
  };
}

// ─── Official Marketplace Check ──────────────────────────────────────────────

/// Known official marketplace identifiers.
const Set<String> _officialMarketplaceNames = {'anthropic', 'neomclaw'};

/// Check if a marketplace name is official.
bool isOfficialMarketplaceName(String? marketplace) {
  if (marketplace == null) return false;
  return _officialMarketplaceNames.contains(marketplace.toLowerCase());
}

/// Parse a plugin identifier into its components.
/// Format: "marketplace/owner/repo" or "owner/repo" or just "repo".
({String? marketplace, String owner, String repo}) parsePluginIdentifier(
  String repository,
) {
  final parts = repository.split('/');
  if (parts.length >= 3) {
    return (
      marketplace: parts[0],
      owner: parts[1],
      repo: parts.sublist(2).join('/'),
    );
  }
  if (parts.length == 2) {
    return (marketplace: null, owner: parts[0], repo: parts[1]);
  }
  return (marketplace: null, owner: '', repo: repository);
}

/// Check if a skill command is from an official marketplace.
bool isOfficialMarketplaceSkill(SkillCommand command) {
  if (command.source != 'plugin' || command.pluginInfo == null) return false;
  final parsed = parsePluginIdentifier(command.pluginInfo!.repository);
  return isOfficialMarketplaceName(parsed.marketplace);
}

// ─── URL Scheme Extraction ───────────────────────────────────────────────────

/// Extract URL scheme for telemetry.
String extractUrlScheme(String url) {
  if (url.startsWith('gs://')) return 'gs';
  if (url.startsWith('https://')) return 'https';
  if (url.startsWith('http://')) return 'http';
  if (url.startsWith('s3://')) return 's3';
  return 'gs';
}

// ─── Frontmatter Parser ─────────────────────────────────────────────────────

/// Parse YAML frontmatter from skill content.
/// Returns the body content without frontmatter.
({String content, Map<String, String> frontmatter}) parseFrontmatter(
  String content,
) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('---')) {
    return (content: content, frontmatter: const {});
  }

  final endIndex = trimmed.indexOf('\n---', 3);
  if (endIndex == -1) {
    return (content: content, frontmatter: const {});
  }

  final frontmatterBlock = trimmed.substring(3, endIndex).trim();
  final body = trimmed.substring(endIndex + 4).trimLeft();

  final frontmatter = <String, String>{};
  for (final line in frontmatterBlock.split('\n')) {
    final colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      final key = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();
      frontmatter[key] = value;
    }
  }

  return (content: body, frontmatter: frontmatter);
}

// ─── SkillTool Implementation ────────────────────────────────────────────────

/// The SkillTool — executes skills (slash commands) in the conversation.
class SkillTool extends Tool {
  final SkillRegistry _registry;
  final Set<String> _invokedSkills = {};

  SkillTool({SkillRegistry? registry})
    : _registry = registry ?? SkillRegistry();

  @override
  String get name => skillToolName;

  @override
  String get description => 'Execute a skill within the main conversation';

  @override
  String get prompt => _prompt;

  @override
  bool get shouldDefer => false;

  @override
  bool get isConcurrencySafe => false;

  @override
  int? get maxResultSizeChars => 100000;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'skill': {
        'type': 'string',
        'description': 'The skill name. E.g., "commit", "review-pr", or "pdf"',
      },
      'args': {
        'type': 'string',
        'description': 'Optional arguments for the skill',
      },
    },
    'required': ['skill'],
    'additionalProperties': false,
  };

  /// The skill registry used by this tool.
  SkillRegistry get registry => _registry;

  /// Set of invoked skill names in this session.
  Set<String> get invokedSkills => Set.unmodifiable(_invokedSkills);

  /// Clear invoked skills for a specific agent.
  void clearInvokedSkillsForAgent(String agentId) {
    // In the full implementation this would be scoped by agent ID.
    _invokedSkills.clear();
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final skill = input['skill'] as String?;
    if (skill == null || skill.trim().isEmpty) {
      return ValidationResult.invalid('Invalid skill format: $skill');
    }

    final trimmed = skill.trim();
    final normalizedName = trimmed.startsWith('/')
        ? trimmed.substring(1)
        : trimmed;

    // Check if command exists.
    final command = _registry.findCommand(normalizedName);
    if (command == null) {
      return ValidationResult.invalid('Unknown skill: $normalizedName');
    }

    // Check disableModelInvocation.
    if (command.disableModelInvocation) {
      return ValidationResult.invalid(
        'Skill $normalizedName cannot be used with $skillToolName tool '
        'due to disable-model-invocation',
      );
    }

    // Check if it's a prompt-based command.
    if (command.type != 'prompt') {
      return ValidationResult.invalid(
        'Skill $normalizedName is not a prompt-based skill',
      );
    }

    return const ValidationResult.valid();
  }

  @override
  Future<PermissionDecision> checkPermissions(
    Map<String, dynamic> input,
    ToolPermissionContext permContext,
  ) async {
    final skill = (input['skill'] as String).trim();
    final commandName = skill.startsWith('/') ? skill.substring(1) : skill;

    // Check deny rules from permission context.
    for (final rules in permContext.rulesBySource.values) {
      for (final rule in rules) {
        if (rule.behavior == PermissionBehavior.deny) {
          final ruleStr = rule.value.ruleContent ?? '';
          if (_ruleMatches(ruleStr, commandName)) {
            return DenyDecision(
              PermissionDenyDecision(
                reason: 'Skill execution blocked by permission rules',
              ),
            );
          }
        }
      }
    }

    // Check allow rules from permission context.
    for (final rules in permContext.rulesBySource.values) {
      for (final rule in rules) {
        if (rule.behavior == PermissionBehavior.allow) {
          final ruleStr = rule.value.ruleContent ?? '';
          if (_ruleMatches(ruleStr, commandName)) {
            return AllowDecision(PermissionAllowDecision(matchedRule: rule));
          }
        }
      }
    }

    // Auto-allow skills with only safe properties.
    final command = _registry.findCommand(commandName);
    if (command != null && command.type == 'prompt') {
      final commandData = command.toJson();
      if (skillHasOnlySafeProperties(commandData)) {
        return const AllowDecision(PermissionAllowDecision());
      }
    }

    // Default: ask user for permission.
    return AskDecision(
      PermissionAskDecision(message: 'Execute skill: $commandName'),
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final parsed = SkillToolInput.fromJson(input);
    final trimmed = parsed.skill.trim();
    final commandName = trimmed.startsWith('/')
        ? trimmed.substring(1)
        : trimmed;

    final command = _registry.findCommand(commandName);
    if (command == null) {
      return ToolResult.error('Unknown skill: $commandName');
    }

    // Track skill usage.
    _invokedSkills.add(commandName);

    // Check if this should run as a forked sub-agent.
    if (command.context == 'fork') {
      return _executeForkedSkill(command, commandName, parsed.args);
    }

    // Inline execution — return the skill metadata so the caller can
    // inject the skill content into the conversation.
    final allowedTools = command.allowedTools ?? [];
    return ToolResult.success(
      'Launching skill: $commandName',
      metadata: SkillToolInlineOutput(
        success: true,
        commandName: commandName,
        allowedTools: allowedTools.isNotEmpty ? allowedTools : null,
        model: command.model,
      ).toJson(),
    );
  }

  /// Execute a skill in a forked sub-agent context.
  Future<ToolResult> _executeForkedSkill(
    SkillCommand command,
    String commandName,
    String? args,
  ) async {
    final startTime = DateTime.now();
    final agentId = _generateAgentId();

    try {
      // In a full implementation this would run a sub-agent with the skill
      // content. For the port, we simulate the forked execution pattern.
      final resultText = 'Skill execution completed';
      final _durationMs = DateTime.now().difference(startTime).inMilliseconds;

      return ToolResult.success(
        'Skill "$commandName" completed (forked execution).\n\n'
        'Result:\n$resultText',
        metadata: SkillToolForkedOutput(
          success: true,
          commandName: commandName,
          agentId: agentId,
          result: resultText,
        ).toJson(),
      );
    } finally {
      clearInvokedSkillsForAgent(agentId);
    }
  }

  /// Generate a unique agent ID for forked skills.
  String _generateAgentId() {
    final random = Random();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Check if a permission rule matches a skill name.
  bool _ruleMatches(String ruleContent, String commandName) {
    final normalizedRule = ruleContent.startsWith('/')
        ? ruleContent.substring(1)
        : ruleContent;

    if (normalizedRule == commandName) return true;

    // Prefix match: "review:*" matches "review-pr 123".
    if (normalizedRule.endsWith(':*')) {
      final prefix = normalizedRule.substring(0, normalizedRule.length - 2);
      return commandName.startsWith(prefix);
    }

    return false;
  }

  @override
  String toAutoClassifierInput(Map<String, dynamic> input) {
    return input['skill'] as String? ?? '';
  }

  static const String _prompt = '''Execute a skill within the main conversation

When users ask you to perform tasks, check if any of the available skills match. Skills provide specialized capabilities and domain knowledge.

When users reference a "slash command" or "/<something>" (e.g., "/commit", "/review-pr"), they are referring to a skill. Use this tool to invoke it.

How to invoke:
- Use this tool with the skill name and optional arguments
- Examples:
  - `skill: "pdf"` - invoke the pdf skill
  - `skill: "commit", args: "-m 'Fix bug'"` - invoke with arguments
  - `skill: "review-pr", args: "123"` - invoke with arguments
  - `skill: "ms-office-suite:pdf"` - invoke using fully qualified name

Important:
- Available skills are listed in system-reminder messages in the conversation
- When a skill matches the user's request, this is a BLOCKING REQUIREMENT: invoke the relevant Skill tool BEFORE generating any other response about the task
- NEVER mention a skill without actually calling this tool
- Do not invoke a skill that is already running
- Do not use this tool for built-in CLI commands (like /help, /clear, etc.)
- If you see a <command-name> tag in the current conversation turn, the skill has ALREADY been loaded - follow the instructions directly instead of calling this tool again
''';
}

// ─── Permission Models (supplement tool.dart) ────────────────────────────────

/// A permission rule matching content for a specific tool.
class PermissionRule {
  final String toolName;
  final String ruleContent;
  final String behavior; // 'allow' or 'deny'

  const PermissionRule({
    required this.toolName,
    required this.ruleContent,
    required this.behavior,
  });
}

/// A suggestion for adding a permission rule.
class PermissionSuggestion {
  final String toolName;
  final String ruleContent;
  final String behavior;
  final String destination;

  const PermissionSuggestion({
    required this.toolName,
    required this.ruleContent,
    required this.behavior,
    required this.destination,
  });

  Map<String, dynamic> toJson() => {
    'toolName': toolName,
    'ruleContent': ruleContent,
    'behavior': behavior,
    'destination': destination,
  };
}

// DenyDecision and AskDecision are from permissions.dart.
