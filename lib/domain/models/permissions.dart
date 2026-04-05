// Permission system types — ported from Neomage src/types/permissions.ts.
// Contains only type definitions to break import cycles.

/// User-addressable permission modes.
enum ExternalPermissionMode {
  /// Automatically accept file edits without prompting.
  acceptEdits,

  /// Skip all permission checks.
  bypassPermissions,

  /// Standard interactive permission mode.
  defaultMode, // 'default' is reserved in Dart
  /// Suppress permission prompts and auto-allow.
  dontAsk,

  /// Plan-only mode: describe actions without executing.
  plan,
}

/// Internal permission modes — superset of external modes.
enum PermissionMode {
  /// Automatically accept file edits.
  acceptEdits,

  /// Skip all permission checks.
  bypassPermissions,

  /// Standard interactive permission mode.
  defaultMode,

  /// Suppress prompts and auto-allow.
  dontAsk,

  /// Plan-only mode.
  plan,

  /// Automatic mode for background agents.
  auto,

  /// Bubble permission decisions up to the parent agent.
  bubble,
}

/// Permission behavior for a rule.
enum PermissionBehavior {
  /// Allow the action without prompting.
  allow,

  /// Deny the action.
  deny,

  /// Ask the user for permission.
  ask,
}

/// Source of a permission rule.
enum PermissionRuleSource {
  /// Rule specified via CLI flags.
  commandLine,

  /// Rule set interactively by the user.
  user,

  /// Rule defined in a .neomage.md configuration file.
  neomageMd,

  /// Rule auto-allowed by the system.
  autoAllow,

  /// Rule from an MCP server configuration.
  mcpServer,
}

/// Specification of tool name and optional rule content.
class PermissionRuleValue {
  /// The tool this rule applies to.
  final String toolName;

  /// Optional content pattern or constraint for the rule.
  final String? ruleContent;

  const PermissionRuleValue({required this.toolName, this.ruleContent});
}

/// A permission rule with source, behavior, and value.
class PermissionRule {
  /// Where this rule originated from.
  final PermissionRuleSource source;

  /// Whether to allow, deny, or ask.
  final PermissionBehavior behavior;

  /// The tool and optional pattern this rule targets.
  final PermissionRuleValue value;

  const PermissionRule({
    required this.source,
    required this.behavior,
    required this.value,
  });
}

/// Where to persist permission updates.
enum PermissionUpdateDestination {
  /// Save to the project-level configuration.
  project,

  /// Save to the user-level configuration.
  user,
}

/// Permission update operations.
sealed class PermissionUpdate {
  const PermissionUpdate();
}

/// Adds new permission rules to the existing set.
class AddRulesUpdate extends PermissionUpdate {
  /// The rules to add.
  final List<PermissionRule> rules;

  /// Where to persist the new rules.
  final PermissionUpdateDestination destination;
  const AddRulesUpdate({required this.rules, required this.destination});
}

/// Replaces all permission rules with the given set.
class ReplaceRulesUpdate extends PermissionUpdate {
  /// The replacement rules.
  final List<PermissionRule> rules;

  /// Where to persist the replaced rules.
  final PermissionUpdateDestination destination;
  const ReplaceRulesUpdate({required this.rules, required this.destination});
}

/// Removes matching permission rules.
class RemoveRulesUpdate extends PermissionUpdate {
  /// The rules to remove.
  final List<PermissionRule> rules;

  /// Where to remove the rules from.
  final PermissionUpdateDestination destination;
  const RemoveRulesUpdate({required this.rules, required this.destination});
}

/// Changes the active permission mode.
class SetModeUpdate extends PermissionUpdate {
  /// The new permission mode to set.
  final PermissionMode mode;
  const SetModeUpdate({required this.mode});
}

/// Adds directories to the allowed working set.
class AddDirectoriesUpdate extends PermissionUpdate {
  /// Directory paths to add.
  final List<String> directories;
  const AddDirectoriesUpdate({required this.directories});
}

/// Removes directories from the allowed working set.
class RemoveDirectoriesUpdate extends PermissionUpdate {
  /// Directory paths to remove.
  final List<String> directories;
  const RemoveDirectoriesUpdate({required this.directories});
}

/// Working directory source.
enum WorkingDirectorySource {
  /// Specified via CLI argument.
  commandLine,

  /// Configured in settings.
  settings,

  /// Inferred from the current working directory.
  cwd,
}

/// Additional directory in permission scope.
class AdditionalWorkingDirectory {
  /// The directory path.
  final String directory;

  /// How this directory was added.
  final WorkingDirectorySource source;
  const AdditionalWorkingDirectory({
    required this.directory,
    required this.source,
  });
}

/// Result when permission is granted.
class PermissionAllowDecision {
  /// Whether a new or modified rule was created.
  final bool updatedRule;

  /// The rule that matched, if any.
  final PermissionRule? matchedRule;
  const PermissionAllowDecision({this.updatedRule = false, this.matchedRule});
}

/// Result when user should be prompted.
class PermissionAskDecision {
  /// Optional message to display in the permission prompt.
  final String? message;
  const PermissionAskDecision({this.message});
}

/// Result when permission is denied.
class PermissionDenyDecision {
  /// Explanation of why the permission was denied.
  final String? reason;
  const PermissionDenyDecision({this.reason});
}

/// Union of permission decisions.
sealed class PermissionDecision {
  const PermissionDecision();
}

/// Permission was granted.
class AllowDecision extends PermissionDecision {
  /// Details about the allow decision.
  final PermissionAllowDecision decision;
  const AllowDecision(this.decision);
}

/// User should be prompted for permission.
class AskDecision extends PermissionDecision {
  /// Details about the ask decision.
  final PermissionAskDecision decision;
  const AskDecision(this.decision);
}

/// Permission was denied.
class DenyDecision extends PermissionDecision {
  /// Details about the deny decision.
  final PermissionDenyDecision decision;
  const DenyDecision(this.decision);
}

/// Permission result — decision plus passthrough option.
class PermissionResult {
  /// The resolved permission decision.
  final PermissionDecision decision;

  /// Whether to pass the decision through to the parent agent.
  final bool passthrough;
  const PermissionResult({required this.decision, this.passthrough = false});
}

/// Risk level for a permission.
enum RiskLevel {
  /// Low risk operation (e.g., reading files).
  low,

  /// Medium risk operation (e.g., writing files).
  medium,

  /// High risk operation (e.g., executing shell commands).
  high,
}

/// Explanation of a permission with risk level.
class PermissionExplanation {
  /// Short title for the permission prompt.
  final String title;

  /// Detailed description of what the tool will do.
  final String description;

  /// Assessed risk level for this operation.
  final RiskLevel riskLevel;
  const PermissionExplanation({
    required this.title,
    required this.description,
    required this.riskLevel,
  });
}

/// Bash classifier result.
class ClassifierResult {
  /// The determined permission behavior.
  final PermissionBehavior behavior;

  /// Optional reasoning from the classifier.
  final String? thinking;
  const ClassifierResult({required this.behavior, this.thinking});
}

/// Token usage from classifier API call.
class ClassifierUsage {
  /// Number of input tokens consumed by the classifier.
  final int inputTokens;

  /// Number of output tokens generated by the classifier.
  final int outputTokens;
  const ClassifierUsage({
    required this.inputTokens,
    required this.outputTokens,
  });
}

/// Full classifier result with detailed telemetry.
class YoloClassifierResult {
  /// The classification result.
  final ClassifierResult result;

  /// Token usage for the classifier call.
  final ClassifierUsage? usage;

  /// How long the classifier took.
  final Duration? duration;

  /// API request ID for debugging.
  final String? requestId;

  /// Which classification stage produced this result.
  final int? stage;
  const YoloClassifierResult({
    required this.result,
    this.usage,
    this.duration,
    this.requestId,
    this.stage,
  });
}

/// Context needed for permission checking.
class ToolPermissionContext {
  /// The active permission mode.
  final PermissionMode mode;

  /// Permission rules grouped by their source.
  final Map<PermissionRuleSource, List<PermissionRule>> rulesBySource;

  /// The primary working directory.
  final String workingDirectory;

  /// Additional directories included in the permission scope.
  final List<AdditionalWorkingDirectory> additionalDirectories;

  const ToolPermissionContext({
    required this.mode,
    required this.rulesBySource,
    required this.workingDirectory,
    this.additionalDirectories = const [],
  });
}
