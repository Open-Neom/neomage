// Permission rule system — port of neom_claw/src/utils/permissions/.
// Rule types, matching, evaluation, and filesystem safety checks.

/// Where a permission rule was loaded from.
enum PermissionRuleSource {
  policySettings,   // MDM/enterprise (highest priority)
  projectSettings,  // .neomclaw/settings.json (shared)
  localSettings,    // .neomclaw/settings.local.json (gitignored)
  userSettings,     // ~/.neomclaw/settings.json (global)
  cliArg,           // --allow/--deny flags
  command,          // /config command
  session,          // Current session only
}

/// Permission rule behavior.
enum PermissionBehavior { allow, deny, ask }

/// A permission rule.
class PermissionRule {
  final PermissionRuleSource source;
  final PermissionBehavior behavior;
  final String toolName;
  final String? ruleContent; // Command pattern, glob, etc.

  const PermissionRule({
    required this.source,
    required this.behavior,
    required this.toolName,
    this.ruleContent,
  });

  @override
  String toString() {
    if (ruleContent != null) return '$toolName($ruleContent)';
    return toolName;
  }
}

/// Parse a permission rule string like "Bash(npm install)" or "FileEdit(src/**)".
({String toolName, String? content}) parsePermissionRule(String rule) {
  // Handle escaped parentheses
  final openParen = _findUnescapedChar(rule, '(');
  if (openParen == -1) {
    return (toolName: rule.trim(), content: null);
  }

  final closeParen = _findLastUnescapedChar(rule, ')');
  if (closeParen == -1 || closeParen <= openParen) {
    return (toolName: rule.trim(), content: null);
  }

  final toolName = rule.substring(0, openParen).trim();
  var content = rule.substring(openParen + 1, closeParen);

  // Unescape parentheses in content
  content = content.replaceAll(r'\(', '(').replaceAll(r'\)', ')');

  return (toolName: toolName, content: content.isEmpty ? null : content);
}

int _findUnescapedChar(String s, String c) {
  for (var i = 0; i < s.length; i++) {
    if (s[i] == c && (i == 0 || s[i - 1] != r'\')) return i;
  }
  return -1;
}

int _findLastUnescapedChar(String s, String c) {
  for (var i = s.length - 1; i >= 0; i--) {
    if (s[i] == c && (i == 0 || s[i - 1] != r'\')) return i;
  }
  return -1;
}

// ── Rule Matching ──

/// Match a command against a rule pattern (supports exact, prefix, wildcard).
bool matchesRule(String input, String pattern) {
  // Exact match
  if (input == pattern) return true;

  // Legacy prefix match: "npm:*"
  if (pattern.endsWith(':*')) {
    final prefix = pattern.substring(0, pattern.length - 2);
    return input == prefix || input.startsWith('$prefix ');
  }

  // Wildcard match: "npm *", "git * main"
  if (pattern.contains('*') && !pattern.endsWith(':*')) {
    return _matchWildcard(input, pattern);
  }

  return false;
}

bool _matchWildcard(String input, String pattern) {
  // Step 1: Protect escaped asterisks
  var escaped = pattern.replaceAll(r'\*', '\x00');

  // Step 2: Escape regex special chars
  escaped = escaped.replaceAllMapped(
    RegExp(r'[.+?^${}()|[\]\\]'),
    (m) => '\\${m[0]}',
  );

  // Step 3: Convert * to .*
  escaped = escaped.replaceAll('*', '.*');

  // Step 4: Restore literal asterisks
  escaped = escaped.replaceAll('\x00', r'\*');

  // Step 5: Make trailing .* optional (e.g., "git" matches "git *")
  if (escaped.endsWith('.*')) {
    escaped = '${escaped.substring(0, escaped.length - 2)}(.*)?';
  }

  // Step 6: Match with anchors and dotAll
  return RegExp('^$escaped\$', dotAll: true).hasMatch(input);
}

/// Match a file path against a glob pattern.
bool matchesGlob(String path, String pattern) {
  // Convert glob to regex
  var regex = pattern
      .replaceAll('.', r'\.')
      .replaceAll('**/', '(.+/)?')
      .replaceAll('**', '.*')
      .replaceAll('*', '[^/]*')
      .replaceAll('?', '[^/]');

  return RegExp('^$regex\$').hasMatch(path);
}

// ── Permission Evaluation ──

/// Result of a permission check.
class PermissionCheckResult {
  final PermissionBehavior behavior;
  final PermissionDecisionReason? reason;
  final Map<String, dynamic>? metadata;

  const PermissionCheckResult({
    required this.behavior,
    this.reason,
    this.metadata,
  });
}

/// Why a permission decision was made.
sealed class PermissionDecisionReason {
  const PermissionDecisionReason();
}

class RuleReason extends PermissionDecisionReason {
  final PermissionRule rule;
  const RuleReason(this.rule);
}

class ModeReason extends PermissionDecisionReason {
  final PermissionMode mode;
  const ModeReason(this.mode);
}

class SafetyCheckReason extends PermissionDecisionReason {
  final String reason;
  const SafetyCheckReason(this.reason);
}

class HookReason extends PermissionDecisionReason {
  final String hookName;
  final String? reason;
  const HookReason(this.hookName, {this.reason});
}

class ClassifierReason extends PermissionDecisionReason {
  final String classifier;
  final String reason;
  const ClassifierReason(this.classifier, this.reason);
}

/// Permission modes.
enum PermissionMode {
  defaultMode,    // Standard prompt-based approval
  plan,           // Plan mode (pauses before execution)
  acceptEdits,    // Auto-accept file edits
  bypassPermissions, // Skip all checks (dangerous)
  dontAsk,        // Auto-deny unpermitted actions
}

/// Evaluate permissions for a tool invocation.
PermissionCheckResult evaluatePermission({
  required String toolName,
  required String? toolInput,
  required List<PermissionRule> rules,
  required PermissionMode mode,
  String? filePath,
}) {
  // 1. Check bypass mode
  if (mode == PermissionMode.bypassPermissions) {
    return PermissionCheckResult(
      behavior: PermissionBehavior.allow,
      reason: ModeReason(mode),
    );
  }

  // 2. Check deny rules first (highest priority)
  for (final rule in rules.where((r) => r.behavior == PermissionBehavior.deny)) {
    if (_ruleMatchesTool(rule, toolName, toolInput, filePath)) {
      return PermissionCheckResult(
        behavior: PermissionBehavior.deny,
        reason: RuleReason(rule),
      );
    }
  }

  // 3. Check allow rules
  for (final rule in rules.where((r) => r.behavior == PermissionBehavior.allow)) {
    if (_ruleMatchesTool(rule, toolName, toolInput, filePath)) {
      return PermissionCheckResult(
        behavior: PermissionBehavior.allow,
        reason: RuleReason(rule),
      );
    }
  }

  // 4. Check ask rules
  for (final rule in rules.where((r) => r.behavior == PermissionBehavior.ask)) {
    if (_ruleMatchesTool(rule, toolName, toolInput, filePath)) {
      return PermissionCheckResult(
        behavior: PermissionBehavior.ask,
        reason: RuleReason(rule),
      );
    }
  }

  // 5. Mode-based defaults
  if (mode == PermissionMode.acceptEdits) {
    if (_isFileEditTool(toolName)) {
      return PermissionCheckResult(
        behavior: PermissionBehavior.allow,
        reason: ModeReason(mode),
      );
    }
  }
  if (mode == PermissionMode.dontAsk) {
    return PermissionCheckResult(
      behavior: PermissionBehavior.deny,
      reason: ModeReason(mode),
    );
  }

  // 6. Default: ask
  return const PermissionCheckResult(behavior: PermissionBehavior.ask);
}

bool _ruleMatchesTool(
  PermissionRule rule,
  String toolName,
  String? toolInput,
  String? filePath,
) {
  // Tool name must match
  if (rule.toolName != toolName) {
    // Check MCP server-level match
    if (toolName.startsWith('mcp__') && rule.toolName.startsWith('mcp__')) {
      if (!toolName.startsWith(rule.toolName)) return false;
    } else {
      return false;
    }
  }

  // No content = match entire tool
  if (rule.ruleContent == null) return true;

  // Content match depends on tool type
  if (toolName == 'Bash' && toolInput != null) {
    return matchesRule(toolInput, rule.ruleContent!);
  }
  if (_isFileTool(toolName) && filePath != null) {
    return matchesGlob(filePath, rule.ruleContent!);
  }
  if (toolInput != null) {
    return matchesRule(toolInput, rule.ruleContent!);
  }

  return false;
}

bool _isFileTool(String toolName) =>
    toolName == 'FileEdit' ||
    toolName == 'FileRead' ||
    toolName == 'FileWrite' ||
    toolName == 'NotebookEdit';

bool _isFileEditTool(String toolName) =>
    toolName == 'FileEdit' ||
    toolName == 'FileWrite' ||
    toolName == 'NotebookEdit';

// ── Rule Loading ──

/// Load permission rules from all settings sources.
List<PermissionRule> loadPermissionRules({
  Map<String, dynamic>? policySettings,
  Map<String, dynamic>? projectSettings,
  Map<String, dynamic>? localSettings,
  Map<String, dynamic>? userSettings,
  bool managedOnly = false,
}) {
  final rules = <PermissionRule>[];

  void loadFrom(Map<String, dynamic>? settings, PermissionRuleSource source) {
    if (settings == null) return;
    final perms = settings['permissions'] as Map<String, dynamic>?;
    if (perms == null) return;

    for (final behavior in PermissionBehavior.values) {
      final ruleList = perms[behavior.name] as List?;
      if (ruleList == null) continue;

      for (final ruleStr in ruleList) {
        if (ruleStr is! String) continue;
        final parsed = parsePermissionRule(ruleStr);
        rules.add(PermissionRule(
          source: source,
          behavior: behavior,
          toolName: parsed.toolName,
          ruleContent: parsed.content,
        ));
      }
    }
  }

  // Load in priority order (policy first)
  loadFrom(policySettings, PermissionRuleSource.policySettings);

  if (!managedOnly) {
    loadFrom(projectSettings, PermissionRuleSource.projectSettings);
    loadFrom(localSettings, PermissionRuleSource.localSettings);
    loadFrom(userSettings, PermissionRuleSource.userSettings);
  }

  return rules;
}

// ── Rule Suggestion ──

/// Suggest a permission rule for a tool invocation.
String suggestRule({
  required String toolName,
  required String? input,
  String? filePath,
}) {
  if (_isFileTool(toolName) && filePath != null) {
    // Suggest glob pattern for file tools
    final parts = filePath.split('/');
    if (parts.length > 2) {
      return '$toolName(${parts.sublist(0, 2).join('/')}/**)';
    }
    return '$toolName($filePath)';
  }

  if (toolName == 'Bash' && input != null) {
    final lines = input.split('\n');
    if (lines.length > 1) {
      // Multiline → first line prefix
      final words = lines.first.trim().split(RegExp(r'\s+'));
      if (words.length >= 2) return '$toolName(${words[0]} ${words[1]}*)';
      return '$toolName(${words[0]}*)';
    }

    // Single line → 2-word prefix
    final words = input.trim().split(RegExp(r'\s+'));
    if (words.length >= 2) return '$toolName(${words[0]} ${words[1]})';
    return '$toolName(${words[0]})';
  }

  return toolName;
}

// ── Permission Rule Validation ──

/// Validate a permission rule string.
String? validatePermissionRule(String rule) {
  final parsed = parsePermissionRule(rule);

  if (parsed.toolName.isEmpty) {
    return 'Tool name cannot be empty';
  }

  // Check for empty parentheses
  if (rule.contains('()')) {
    return 'Empty parentheses — use "$rule(pattern)" or just "${parsed.toolName}"';
  }

  // Check for mismatched parentheses
  final openCount = rule.split('').where((c) => c == '(').length -
      rule.split(r'\(').length + 1;
  final closeCount = rule.split('').where((c) => c == ')').length -
      rule.split(r'\)').length + 1;
  if (openCount != closeCount) {
    return 'Mismatched parentheses';
  }

  // Tool-specific validation
  if (parsed.content != null) {
    if (parsed.toolName.startsWith('mcp__')) {
      // MCP rules don't support patterns
      if (parsed.content!.contains('*') || parsed.content!.contains('(')) {
        return 'MCP rules do not support patterns — use "mcp__server" or "mcp__server__tool"';
      }
    }

    if (_isFileTool(parsed.toolName)) {
      // File tools use glob patterns, not :* syntax
      if (parsed.content!.contains(':*')) {
        return 'File tools use glob patterns (e.g., "*.ts"), not ":*" syntax';
      }
    }
  }

  return null;
}

// ── Dangerous File Detection ──

/// Files that require extra permission to modify.
const dangerousFiles = {
  '.gitconfig', '.gitmodules', '.bashrc', '.bash_profile', '.zshrc',
  '.zprofile', '.profile', '.ripgreprc', '.mcp.json', '.neomclaw.json',
  '.npmrc', '.yarnrc', '.env', '.env.local', '.env.production',
  '.ssh/config', '.ssh/authorized_keys', '.ssh/known_hosts',
};

/// Directories that require extra permission.
const dangerousDirectories = {'.git', '.vscode', '.idea', '.neomclaw'};

/// Check if a file path is dangerous.
bool isDangerousPath(String path) {
  final fileName = path.split('/').last;
  if (dangerousFiles.contains(fileName)) return true;

  for (final dir in dangerousDirectories) {
    if (path.contains('/$dir/') || path.endsWith('/$dir')) return true;
  }

  return false;
}

/// System paths that should never be removed.
const systemPaths = {
  '/', '/bin', '/sbin', '/usr', '/usr/bin', '/usr/sbin', '/usr/lib',
  '/usr/local', '/sys', '/etc', '/boot', '/dev', '/proc', '/home',
  '/root', '/var', '/tmp', '/lib', '/lib64', '/opt',
  '/System', '/Library', '/Applications', '/Users',
};

/// Check if a path is a system path.
bool isSystemPath(String path) {
  final normalized = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
  return systemPaths.contains(normalized);
}
