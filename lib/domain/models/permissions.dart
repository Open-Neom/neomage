// Permission system types — ported from NeomClaw src/types/permissions.ts.
// Contains only type definitions to break import cycles.

/// User-addressable permission modes.
enum ExternalPermissionMode {
  acceptEdits,
  bypassPermissions,
  defaultMode, // 'default' is reserved in Dart
  dontAsk,
  plan,
}

/// Internal permission modes — superset of external modes.
enum PermissionMode {
  acceptEdits,
  bypassPermissions,
  defaultMode,
  dontAsk,
  plan,
  auto,
  bubble,
}

/// Permission behavior for a rule.
enum PermissionBehavior { allow, deny, ask }

/// Source of a permission rule.
enum PermissionRuleSource {
  commandLine,
  user,
  neomClawMd,
  autoAllow,
  mcpServer,
}

/// Specification of tool name and optional rule content.
class PermissionRuleValue {
  final String toolName;
  final String? ruleContent;

  const PermissionRuleValue({required this.toolName, this.ruleContent});
}

/// A permission rule with source, behavior, and value.
class PermissionRule {
  final PermissionRuleSource source;
  final PermissionBehavior behavior;
  final PermissionRuleValue value;

  const PermissionRule({
    required this.source,
    required this.behavior,
    required this.value,
  });
}

/// Where to persist permission updates.
enum PermissionUpdateDestination { project, user }

/// Permission update operations.
sealed class PermissionUpdate {
  const PermissionUpdate();
}

class AddRulesUpdate extends PermissionUpdate {
  final List<PermissionRule> rules;
  final PermissionUpdateDestination destination;
  const AddRulesUpdate({required this.rules, required this.destination});
}

class ReplaceRulesUpdate extends PermissionUpdate {
  final List<PermissionRule> rules;
  final PermissionUpdateDestination destination;
  const ReplaceRulesUpdate({required this.rules, required this.destination});
}

class RemoveRulesUpdate extends PermissionUpdate {
  final List<PermissionRule> rules;
  final PermissionUpdateDestination destination;
  const RemoveRulesUpdate({required this.rules, required this.destination});
}

class SetModeUpdate extends PermissionUpdate {
  final PermissionMode mode;
  const SetModeUpdate({required this.mode});
}

class AddDirectoriesUpdate extends PermissionUpdate {
  final List<String> directories;
  const AddDirectoriesUpdate({required this.directories});
}

class RemoveDirectoriesUpdate extends PermissionUpdate {
  final List<String> directories;
  const RemoveDirectoriesUpdate({required this.directories});
}

/// Working directory source.
enum WorkingDirectorySource { commandLine, settings, cwd }

/// Additional directory in permission scope.
class AdditionalWorkingDirectory {
  final String directory;
  final WorkingDirectorySource source;
  const AdditionalWorkingDirectory({
    required this.directory,
    required this.source,
  });
}

/// Result when permission is granted.
class PermissionAllowDecision {
  final bool updatedRule;
  final PermissionRule? matchedRule;
  const PermissionAllowDecision({this.updatedRule = false, this.matchedRule});
}

/// Result when user should be prompted.
class PermissionAskDecision {
  final String? message;
  const PermissionAskDecision({this.message});
}

/// Result when permission is denied.
class PermissionDenyDecision {
  final String? reason;
  const PermissionDenyDecision({this.reason});
}

/// Union of permission decisions.
sealed class PermissionDecision {
  const PermissionDecision();
}

class AllowDecision extends PermissionDecision {
  final PermissionAllowDecision decision;
  const AllowDecision(this.decision);
}

class AskDecision extends PermissionDecision {
  final PermissionAskDecision decision;
  const AskDecision(this.decision);
}

class DenyDecision extends PermissionDecision {
  final PermissionDenyDecision decision;
  const DenyDecision(this.decision);
}

/// Permission result — decision plus passthrough option.
class PermissionResult {
  final PermissionDecision decision;
  final bool passthrough;
  const PermissionResult({required this.decision, this.passthrough = false});
}

/// Risk level for a permission.
enum RiskLevel { low, medium, high }

/// Explanation of a permission with risk level.
class PermissionExplanation {
  final String title;
  final String description;
  final RiskLevel riskLevel;
  const PermissionExplanation({
    required this.title,
    required this.description,
    required this.riskLevel,
  });
}

/// Bash classifier result.
class ClassifierResult {
  final PermissionBehavior behavior;
  final String? thinking;
  const ClassifierResult({required this.behavior, this.thinking});
}

/// Token usage from classifier API call.
class ClassifierUsage {
  final int inputTokens;
  final int outputTokens;
  const ClassifierUsage({
    required this.inputTokens,
    required this.outputTokens,
  });
}

/// Full classifier result with detailed telemetry.
class YoloClassifierResult {
  final ClassifierResult result;
  final ClassifierUsage? usage;
  final Duration? duration;
  final String? requestId;
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
  final PermissionMode mode;
  final Map<PermissionRuleSource, List<PermissionRule>> rulesBySource;
  final String workingDirectory;
  final List<AdditionalWorkingDirectory> additionalDirectories;

  const ToolPermissionContext({
    required this.mode,
    required this.rulesBySource,
    required this.workingDirectory,
    this.additionalDirectories = const [],
  });
}
