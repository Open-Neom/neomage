// Permission hooks — port of neom_claw/src/hooks/permissions.ts.
// Provides permission scoping, rule evaluation, caching, and specialized
// checkers for files, tools, git, and network operations.

import 'dart:async';
import 'dart:convert';

import 'hook_types.dart';

// ---------------------------------------------------------------------------
// Permission Scope
// ---------------------------------------------------------------------------

/// Categories of operations that require permission checks.
///
/// Each scope covers a distinct surface area of the system. Permission rules
/// are evaluated against scopes to determine whether an operation is allowed.
enum PermissionScope {
  /// Tool execution (bash, file read/write, etc.).
  tool,

  /// File system access (read, write, delete).
  file,

  /// Git operations (commit, push, reset, etc.).
  git,

  /// Network access (HTTP requests, MCP connections).
  network,

  /// System-level operations (process spawn, env access).
  system,

  /// MCP server interactions.
  mcp,

  /// Sub-agent spawning and communication.
  agent,
}

// ---------------------------------------------------------------------------
// Permission Level
// ---------------------------------------------------------------------------

/// The decision level for a permission request.
///
/// Ordered from most restrictive to most permissive. Rules and caches store
/// these levels to control how future requests of the same type are handled.
enum PermissionLevel {
  /// Always deny this operation.
  deny,

  /// Ask the user interactively every time.
  ask,

  /// Allow once, then revert to [ask].
  allowOnce,

  /// Allow for the remainder of the current session.
  allowSession,

  /// Allow permanently (persisted across sessions).
  allowAlways;

  /// Whether this level grants access (at least once).
  bool get isAllowed =>
      this == allowOnce || this == allowSession || this == allowAlways;

  /// Whether this level should be cached beyond the current check.
  bool get isCacheable => this == allowSession || this == allowAlways;
}

// ---------------------------------------------------------------------------
// Risk Level
// ---------------------------------------------------------------------------

/// Risk classification for a permission request.
///
/// Used to surface appropriate UI and determine default behaviors.
enum RiskLevel {
  /// No meaningful risk (e.g., reading a file inside the sandbox).
  low,

  /// Moderate risk (e.g., writing a file, running a safe shell command).
  medium,

  /// High risk (e.g., network access, running arbitrary bash).
  high,

  /// Critical risk (e.g., force push, deleting protected files).
  critical;

  /// Whether this risk level should always prompt the user.
  bool get requiresExplicitApproval => this == high || this == critical;
}

// ---------------------------------------------------------------------------
// Permission Request
// ---------------------------------------------------------------------------

/// A request to perform a permissioned operation.
///
/// Created by tool executors and permission checkers, then evaluated against
/// the active [PermissionRuleSet].
class PermissionRequest {
  /// The scope of the requested operation.
  final PermissionScope scope;

  /// The specific action within the scope (e.g., "read", "write", "execute").
  final String action;

  /// The resource being acted upon (e.g., file path, URL, tool name).
  final String resource;

  /// The tool requesting the permission, if applicable.
  final String? toolName;

  /// Human-readable description of what is being requested.
  final String detail;

  /// Risk assessment for this request.
  final RiskLevel riskLevel;

  /// When this request was created.
  final DateTime timestamp;

  /// Additional metadata about the request.
  final Map<String, dynamic> metadata;

  PermissionRequest({
    required this.scope,
    required this.action,
    required this.resource,
    this.toolName,
    required this.detail,
    this.riskLevel = RiskLevel.medium,
    DateTime? timestamp,
    this.metadata = const {},
  }) : timestamp = timestamp ?? DateTime.now();

  /// Unique key for caching purposes. Combines scope, action, and resource.
  String get cacheKey => '${scope.name}:$action:$resource';

  @override
  String toString() => 'PermissionRequest('
      'scope: ${scope.name}, action: $action, '
      'resource: $resource, risk: ${riskLevel.name})';
}

// ---------------------------------------------------------------------------
// Permission Decision
// ---------------------------------------------------------------------------

/// The result of evaluating a [PermissionRequest] against rules.
class PermissionDecision {
  /// The granted permission level.
  final PermissionLevel level;

  /// The rule that matched, if any. Null means the default level was used.
  final PermissionRule? matchedRule;

  /// Human-readable reason for the decision.
  final String reason;

  /// When this decision automatically expires. Null means no expiry.
  final DateTime? autoExpiry;

  /// When the decision was made.
  final DateTime timestamp;

  PermissionDecision({
    required this.level,
    this.matchedRule,
    required this.reason,
    this.autoExpiry,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Whether the decision grants access.
  bool get isAllowed => level.isAllowed;

  /// Whether this decision has expired.
  bool get isExpired =>
      autoExpiry != null && DateTime.now().isAfter(autoExpiry!);

  @override
  String toString() => 'PermissionDecision('
      'level: ${level.name}, reason: $reason, '
      'expired: $isExpired)';
}

// ---------------------------------------------------------------------------
// Permission Rule
// ---------------------------------------------------------------------------

/// A single permission rule that matches requests by scope, action, and
/// resource pattern.
class PermissionRule {
  /// Unique identifier for this rule.
  final String id;

  /// Human-readable name.
  final String name;

  /// Scope this rule applies to, or null for all scopes.
  final PermissionScope? scope;

  /// Action pattern (exact match or glob). Null matches all actions.
  final String? actionPattern;

  /// Resource pattern (exact, prefix, glob, or regex). Null matches all.
  final String? resourcePattern;

  /// Tool name pattern. Null matches all tools.
  final String? toolPattern;

  /// The permission level to grant when this rule matches.
  final PermissionLevel level;

  /// Priority for rule ordering. Lower values take precedence.
  final int priority;

  /// Whether this rule is currently active.
  bool enabled;

  /// Optional expiry time after which the rule is ignored.
  final DateTime? expiresAt;

  /// Source of this rule (e.g., "user", "config", "session").
  final String? source;

  PermissionRule({
    required this.id,
    required this.name,
    this.scope,
    this.actionPattern,
    this.resourcePattern,
    this.toolPattern,
    required this.level,
    this.priority = 100,
    this.enabled = true,
    this.expiresAt,
    this.source,
  });

  /// Whether this rule has expired.
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// Whether this rule is active (enabled and not expired).
  bool get isActive => enabled && !isExpired;

  /// Check if this rule matches the given request.
  bool matches(PermissionRequest request) {
    if (!isActive) return false;

    // Scope filter
    if (scope != null && scope != request.scope) return false;

    // Action filter
    if (actionPattern != null &&
        !PermissionPatternMatcher.match(actionPattern!, request.action)) {
      return false;
    }

    // Resource filter
    if (resourcePattern != null &&
        !PermissionPatternMatcher.match(
            resourcePattern!, request.resource)) {
      return false;
    }

    // Tool filter
    if (toolPattern != null && request.toolName != null &&
        !PermissionPatternMatcher.match(toolPattern!, request.toolName!)) {
      return false;
    }
    if (toolPattern != null && request.toolName == null) return false;

    return true;
  }

  @override
  String toString() => 'PermissionRule(id: $id, name: $name, '
      'level: ${level.name}, priority: $priority)';
}

// ---------------------------------------------------------------------------
// Permission Rule Set
// ---------------------------------------------------------------------------

/// An ordered collection of [PermissionRule]s with a default fallback level.
///
/// Rules are evaluated in priority order (lowest first). The first matching
/// rule determines the [PermissionDecision]. If no rule matches, the
/// [defaultLevel] is used.
class PermissionRuleSet {
  /// The rules in this set, sorted by priority.
  final List<PermissionRule> _rules;

  /// Default permission level when no rule matches.
  final PermissionLevel defaultLevel;

  PermissionRuleSet({
    List<PermissionRule>? rules,
    this.defaultLevel = PermissionLevel.ask,
  }) : _rules = List.of(rules ?? []) {
    _sortRules();
  }

  /// All rules in priority order.
  List<PermissionRule> get rules => List.unmodifiable(_rules);

  /// Only active (enabled, non-expired) rules.
  List<PermissionRule> get activeRules =>
      _rules.where((r) => r.isActive).toList();

  /// Add a rule, maintaining priority sort order.
  void addRule(PermissionRule rule) {
    _rules.add(rule);
    _sortRules();
  }

  /// Remove a rule by ID. Returns true if found.
  bool removeRule(String id) {
    final index = _rules.indexWhere((r) => r.id == id);
    if (index == -1) return false;
    _rules.removeAt(index);
    return true;
  }

  /// Find a rule by ID.
  PermissionRule? findRule(String id) {
    for (final rule in _rules) {
      if (rule.id == id) return rule;
    }
    return null;
  }

  /// Remove all rules from a given source.
  int removeBySource(String source) {
    final before = _rules.length;
    _rules.removeWhere((r) => r.source == source);
    return before - _rules.length;
  }

  /// Remove all expired rules.
  int purgeExpired() {
    final before = _rules.length;
    _rules.removeWhere((r) => r.isExpired);
    return before - _rules.length;
  }

  /// Evaluate a [PermissionRequest] against all active rules.
  ///
  /// Returns a [PermissionDecision] from the first matching rule, or a
  /// decision with [defaultLevel] if no rule matches.
  PermissionDecision evaluate(PermissionRequest request) {
    for (final rule in _rules) {
      if (!rule.isActive) continue;
      if (rule.matches(request)) {
        return PermissionDecision(
          level: rule.level,
          matchedRule: rule,
          reason: 'Matched rule "${rule.name}" (${rule.id})',
          autoExpiry: rule.level == PermissionLevel.allowOnce
              ? DateTime.now()
              : null,
        );
      }
    }

    // No rule matched — use default
    return PermissionDecision(
      level: defaultLevel,
      reason: 'No matching rule; using default level '
          '(${defaultLevel.name})',
    );
  }

  /// Evaluate and also check the cache first.
  PermissionDecision evaluateWithCache(
    PermissionRequest request,
    PermissionCache cache,
  ) {
    final cached = cache.get(request.cacheKey);
    if (cached != null && !cached.isExpired) {
      return cached;
    }

    final decision = evaluate(request);

    if (decision.level.isCacheable) {
      cache.set(request.cacheKey, decision);
    }

    return decision;
  }

  void _sortRules() {
    _rules.sort((a, b) => a.priority.compareTo(b.priority));
  }
}

// ---------------------------------------------------------------------------
// Permission Cache
// ---------------------------------------------------------------------------

/// TTL-aware cache for [PermissionDecision]s.
///
/// Stores decisions keyed by the request's cache key. Entries are
/// automatically considered stale after their TTL or [PermissionDecision.autoExpiry].
class PermissionCache {
  final Map<String, _CacheEntry> _entries = {};

  /// Default time-to-live for cached decisions.
  final Duration defaultTtl;

  PermissionCache({
    this.defaultTtl = const Duration(minutes: 30),
  });

  /// Number of entries currently in the cache.
  int get length => _entries.length;

  /// Whether the cache is empty.
  bool get isEmpty => _entries.isEmpty;

  /// Get a cached decision by key. Returns null if not found or expired.
  PermissionDecision? get(String key) {
    final entry = _entries[key];
    if (entry == null) return null;

    if (entry.isExpired) {
      _entries.remove(key);
      return null;
    }

    if (entry.decision.isExpired) {
      _entries.remove(key);
      return null;
    }

    return entry.decision;
  }

  /// Store a decision in the cache with optional custom TTL.
  void set(String key, PermissionDecision decision, {Duration? ttl}) {
    _entries[key] = _CacheEntry(
      decision: decision,
      expiresAt: DateTime.now().add(ttl ?? defaultTtl),
    );
  }

  /// Remove a specific entry by key. Returns true if it existed.
  bool invalidate(String key) => _entries.remove(key) != null;

  /// Remove all entries matching a scope.
  int invalidateScope(PermissionScope scope) {
    final prefix = '${scope.name}:';
    final keysToRemove =
        _entries.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      _entries.remove(key);
    }
    return keysToRemove.length;
  }

  /// Remove all expired entries.
  int purgeExpired() {
    final keysToRemove =
        _entries.entries
            .where((e) => e.value.isExpired || e.value.decision.isExpired)
            .map((e) => e.key)
            .toList();
    for (final key in keysToRemove) {
      _entries.remove(key);
    }
    return keysToRemove.length;
  }

  /// Clear all cached entries.
  void clearAll() => _entries.clear();

  /// Get all cache keys (for debugging).
  List<String> get keys => _entries.keys.toList();
}

/// Internal cache entry with expiry tracking.
class _CacheEntry {
  final PermissionDecision decision;
  final DateTime expiresAt;

  const _CacheEntry({
    required this.decision,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// ---------------------------------------------------------------------------
// File Permission Checker
// ---------------------------------------------------------------------------

/// Checks file-system permissions against sandbox rules and protected paths.
class FilePermissionChecker {
  /// Paths the agent is allowed to access.
  final List<String> _allowedPaths;

  /// Paths that are always protected (e.g., system directories, credentials).
  final List<String> _protectedPaths;

  /// The rule set to evaluate against.
  final PermissionRuleSet _ruleSet;

  /// Permission cache for file operations.
  final PermissionCache _cache;

  FilePermissionChecker({
    required List<String> allowedPaths,
    List<String>? protectedPaths,
    required PermissionRuleSet ruleSet,
    PermissionCache? cache,
  })  : _allowedPaths = List.of(allowedPaths),
        _protectedPaths = List.of(protectedPaths ?? _defaultProtectedPaths),
        _ruleSet = ruleSet,
        _cache = cache ?? PermissionCache();

  /// Default protected paths that should never be modified.
  static const _defaultProtectedPaths = <String>[
    '/etc/passwd',
    '/etc/shadow',
    '/etc/sudoers',
    '/etc/hosts',
    '/root',
    '/var/log',
    '/System',
    '/usr/bin',
    '/usr/sbin',
    '/private/etc',
  ];

  /// Sensitive file patterns that trigger elevated risk.
  static final _sensitivePatterns = <RegExp>[
    RegExp(r'\.env($|\.)'),
    RegExp(r'\.ssh/'),
    RegExp(r'\.aws/'),
    RegExp(r'\.gnupg/'),
    RegExp(r'credentials\.json$'),
    RegExp(r'\.pem$'),
    RegExp(r'\.key$'),
    RegExp(r'\.p12$'),
    RegExp(r'\.pfx$'),
    RegExp(r'id_rsa$'),
    RegExp(r'id_ed25519$'),
    RegExp(r'\.netrc$'),
    RegExp(r'\.npmrc$'),
    RegExp(r'\.pypirc$'),
  ];

  /// Check read permission for a file path.
  PermissionDecision checkRead(String path) {
    final normalized = _normalizePath(path);

    if (isProtectedPath(normalized)) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Path "$normalized" is a protected system path.',
      );
    }

    final risk = _isSensitiveFile(normalized) ? RiskLevel.high : RiskLevel.low;
    final request = PermissionRequest(
      scope: PermissionScope.file,
      action: 'read',
      resource: normalized,
      detail: 'Read file: $normalized',
      riskLevel: risk,
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Check write permission for a file path.
  PermissionDecision checkWrite(String path) {
    final normalized = _normalizePath(path);

    if (isProtectedPath(normalized)) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Path "$normalized" is a protected system path. '
            'Write operations are blocked.',
      );
    }

    if (!isInSandbox(normalized)) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Path "$normalized" is outside the sandbox.',
      );
    }

    final risk =
        _isSensitiveFile(normalized) ? RiskLevel.critical : RiskLevel.medium;
    final request = PermissionRequest(
      scope: PermissionScope.file,
      action: 'write',
      resource: normalized,
      detail: 'Write file: $normalized',
      riskLevel: risk,
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Check delete permission for a file path.
  PermissionDecision checkDelete(String path) {
    final normalized = _normalizePath(path);

    if (isProtectedPath(normalized)) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Path "$normalized" is a protected system path. '
            'Delete operations are blocked.',
      );
    }

    if (!isInSandbox(normalized)) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Path "$normalized" is outside the sandbox.',
      );
    }

    final request = PermissionRequest(
      scope: PermissionScope.file,
      action: 'delete',
      resource: normalized,
      detail: 'Delete file: $normalized',
      riskLevel: RiskLevel.high,
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Whether the given path falls inside any allowed sandbox path.
  bool isInSandbox(String path) {
    final normalized = _normalizePath(path);
    for (final allowed in _allowedPaths) {
      final normalizedAllowed = _normalizePath(allowed);
      if (normalized == normalizedAllowed ||
          normalized.startsWith('$normalizedAllowed/')) {
        return true;
      }
    }
    return false;
  }

  /// Whether the given path is a protected system path.
  bool isProtectedPath(String path) {
    final normalized = _normalizePath(path);
    for (final protectedPath in _protectedPaths) {
      if (normalized == protectedPath ||
          normalized.startsWith('$protectedPath/')) {
        return true;
      }
    }
    return false;
  }

  /// Expand allowed paths from a set of rules that have file scope.
  ///
  /// Extracts resource patterns from file-scope rules with allow levels and
  /// adds them to the allowed paths list.
  List<String> expandAllowedPaths(List<PermissionRule> rules) {
    final expanded = <String>[];
    for (final rule in rules) {
      if (rule.scope == PermissionScope.file &&
          rule.isActive &&
          rule.level.isAllowed &&
          rule.resourcePattern != null) {
        final pattern = rule.resourcePattern!;
        // Only expand literal paths, not globs or regex.
        if (!pattern.contains('*') &&
            !pattern.contains('?') &&
            !pattern.startsWith('regex:')) {
          expanded.add(pattern);
          if (!_allowedPaths.contains(pattern)) {
            _allowedPaths.add(pattern);
          }
        }
      }
    }
    return expanded;
  }

  /// Check whether a file matches sensitive patterns.
  bool _isSensitiveFile(String path) {
    for (final pattern in _sensitivePatterns) {
      if (pattern.hasMatch(path)) return true;
    }
    return false;
  }

  /// Normalize a file path for consistent comparison.
  String _normalizePath(String path) {
    // Remove trailing slashes and resolve double slashes.
    var normalized = path.replaceAll(RegExp(r'/+'), '/');
    if (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

// ---------------------------------------------------------------------------
// Tool Permission Checker
// ---------------------------------------------------------------------------

/// Checks permissions for tool execution, including input validation and
/// dangerous command detection.
class ToolPermissionChecker {
  final PermissionRuleSet _ruleSet;
  final PermissionCache _cache;

  /// Tools that are always considered high-risk.
  static const _highRiskTools = <String>{
    'Bash',
    'bash',
    'shell',
    'terminal',
  };

  /// Tools that are always considered safe (low risk).
  static const _safeTools = <String>{
    'Read',
    'Glob',
    'Grep',
    'TodoWrite',
  };

  /// Dangerous bash command patterns.
  static final _dangerousBashPatterns = <_DangerousPattern>[
    _DangerousPattern(
      RegExp(r'\brm\s+(-[^\s]*)?(-r|-f|-rf|-fr)\b'),
      'Recursive or forced file deletion',
    ),
    _DangerousPattern(
      RegExp(r'\bsudo\b'),
      'Elevated privilege execution',
    ),
    _DangerousPattern(
      RegExp(r'\bchmod\s+[0-7]*7[0-7]*\b'),
      'World-writable permission change',
    ),
    _DangerousPattern(
      RegExp(r'\bchown\b'),
      'File ownership change',
    ),
    _DangerousPattern(
      RegExp(r'\bmkfs\b'),
      'Filesystem creation (destructive)',
    ),
    _DangerousPattern(
      RegExp(r'\bdd\s+.*\bof=\s*/dev/'),
      'Direct device write',
    ),
    _DangerousPattern(
      RegExp(r'>\s*/dev/sd[a-z]'),
      'Direct device write via redirect',
    ),
    _DangerousPattern(
      RegExp(r'\bcurl\b.*\|\s*(ba)?sh'),
      'Piping remote content to shell',
    ),
    _DangerousPattern(
      RegExp(r'\bwget\b.*\|\s*(ba)?sh'),
      'Piping remote download to shell',
    ),
    _DangerousPattern(
      RegExp(r'\beval\b'),
      'Dynamic code evaluation',
    ),
    _DangerousPattern(
      RegExp(r'>\s*/etc/'),
      'Writing to system configuration',
    ),
    _DangerousPattern(
      RegExp(r'\bnc\s+-[^\s]*l'),
      'Network listener (netcat)',
    ),
    _DangerousPattern(
      RegExp(r'\bsshpass\b'),
      'Automated SSH password authentication',
    ),
    _DangerousPattern(
      RegExp(r'\bgit\s+push\s+.*--force\b'),
      'Git force push',
    ),
    _DangerousPattern(
      RegExp(r'\bgit\s+reset\s+--hard\b'),
      'Git hard reset',
    ),
    _DangerousPattern(
      RegExp(r'\bgit\s+clean\s+.*-f'),
      'Git clean (forced file removal)',
    ),
  ];

  /// Suspicious URL patterns for network checks.
  static final _suspiciousUrlPatterns = <RegExp>[
    RegExp(r'^https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)'),
    RegExp(r'^https?://(?:10\.|172\.(?:1[6-9]|2\d|3[01])\.|192\.168\.)'),
    RegExp(r'^file://'),
    RegExp(r'\.onion(?:$|/)'),
  ];

  ToolPermissionChecker({
    required PermissionRuleSet ruleSet,
    PermissionCache? cache,
  })  : _ruleSet = ruleSet,
        _cache = cache ?? PermissionCache();

  /// Check whether a tool execution is permitted.
  PermissionDecision checkToolExecution(
    String toolName,
    Map<String, dynamic> input,
  ) {
    final (isDangerous, dangerReason) = isDangerousInput(toolName, input);

    final RiskLevel risk;
    if (isDangerous) {
      risk = RiskLevel.critical;
    } else if (_highRiskTools.contains(toolName)) {
      risk = RiskLevel.high;
    } else if (_safeTools.contains(toolName)) {
      risk = RiskLevel.low;
    } else {
      risk = RiskLevel.medium;
    }

    final request = PermissionRequest(
      scope: PermissionScope.tool,
      action: 'execute',
      resource: toolName,
      toolName: toolName,
      detail: isDangerous
          ? 'Execute $toolName (WARNING: $dangerReason)'
          : 'Execute $toolName',
      riskLevel: risk,
      metadata: {
        if (isDangerous) 'dangerReason': dangerReason,
        'inputKeys': input.keys.toList(),
      },
    );

    // Critical risk always requires explicit approval.
    if (risk == RiskLevel.critical) {
      final decision = _ruleSet.evaluate(request);
      if (decision.level == PermissionLevel.allowAlways ||
          decision.level == PermissionLevel.allowSession) {
        // Even cached allow rules should warn for critical operations.
        return PermissionDecision(
          level: PermissionLevel.ask,
          matchedRule: decision.matchedRule,
          reason: 'Critical risk operation requires explicit approval: '
              '${dangerReason ?? toolName}',
        );
      }
      return decision;
    }

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Determine if the input to a tool is dangerous.
  ///
  /// Returns a tuple of (isDangerous, reason). If not dangerous, reason
  /// is an empty string.
  (bool, String) isDangerousInput(
    String toolName,
    Map<String, dynamic> input,
  ) {
    // Special handling for bash/shell tools
    final lowerToolName = toolName.toLowerCase();
    if (lowerToolName == 'bash' ||
        lowerToolName == 'shell' ||
        lowerToolName == 'terminal') {
      final command = input['command'] as String? ?? '';
      return _checkBashDangers(command);
    }

    // Check for file paths pointing to sensitive locations
    final filePath = input['file_path'] as String? ??
        input['path'] as String? ??
        '';
    if (filePath.isNotEmpty) {
      for (final pattern in FilePermissionChecker._sensitivePatterns) {
        if (pattern.hasMatch(filePath)) {
          return (true, 'Operation on sensitive file: $filePath');
        }
      }
    }

    return (false, '');
  }

  /// Check a bash command string for dangerous patterns.
  PermissionDecision checkBashCommand(String command) {
    final (isDangerous, reason) = _checkBashDangers(command);

    final request = PermissionRequest(
      scope: PermissionScope.tool,
      action: 'bash',
      resource: command.length > 80
          ? '${command.substring(0, 80)}...'
          : command,
      toolName: 'Bash',
      detail: isDangerous
          ? 'Bash command (WARNING: $reason): $command'
          : 'Bash command: $command',
      riskLevel: isDangerous ? RiskLevel.critical : RiskLevel.high,
      metadata: {'fullCommand': command},
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Check whether network access to a URL is permitted.
  PermissionDecision checkNetworkAccess(String url) {
    final isSuspicious = _suspiciousUrlPatterns.any((p) => p.hasMatch(url));

    final request = PermissionRequest(
      scope: PermissionScope.network,
      action: 'access',
      resource: url,
      detail: isSuspicious
          ? 'Network access to suspicious URL: $url'
          : 'Network access: $url',
      riskLevel: isSuspicious ? RiskLevel.high : RiskLevel.medium,
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Internal bash danger checker.
  (bool, String) _checkBashDangers(String command) {
    for (final dp in _dangerousBashPatterns) {
      if (dp.pattern.hasMatch(command)) {
        return (true, dp.reason);
      }
    }
    return (false, '');
  }
}

/// Internal helper for dangerous pattern matching.
class _DangerousPattern {
  final RegExp pattern;
  final String reason;

  const _DangerousPattern(this.pattern, this.reason);
}

// ---------------------------------------------------------------------------
// Git Permission Checker
// ---------------------------------------------------------------------------

/// Checks permissions for git operations.
class GitPermissionChecker {
  final PermissionRuleSet _ruleSet;
  final PermissionCache _cache;

  /// Branches protected from destructive operations.
  final List<String> protectedBranches;

  /// Operations considered destructive.
  static const _destructiveOps = <GitOperation>{
    GitOperation.reset,
    GitOperation.revert,
    GitOperation.cherryPick,
    GitOperation.rebase,
  };

  /// Operations that modify remote state.
  static const _remoteOps = <GitOperation>{
    GitOperation.push,
    GitOperation.fetch,
    GitOperation.pull,
    GitOperation.clone,
  };

  GitPermissionChecker({
    required PermissionRuleSet ruleSet,
    PermissionCache? cache,
    this.protectedBranches = const ['main', 'master', 'develop', 'release'],
  })  : _ruleSet = ruleSet,
        _cache = cache ?? PermissionCache();

  /// Check whether a git operation is permitted.
  PermissionDecision checkGitOperation(GitOperation operation) {
    final isDestructive = _destructiveOps.contains(operation);
    final isRemote = _remoteOps.contains(operation);

    final RiskLevel risk;
    if (isDestructive) {
      risk = RiskLevel.high;
    } else if (isRemote) {
      risk = RiskLevel.medium;
    } else {
      risk = RiskLevel.low;
    }

    final request = PermissionRequest(
      scope: PermissionScope.git,
      action: operation.name,
      resource: 'git ${operation.name}',
      detail: 'Git operation: ${operation.name}',
      riskLevel: risk,
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }

  /// Determine if a full git command string is destructive.
  ///
  /// Returns (isDestructive, reason).
  (bool, String) isDestructiveGitOp(String command) {
    final lower = command.toLowerCase().trim();

    if (RegExp(r'\bgit\s+push\s+.*--force\b').hasMatch(lower) ||
        RegExp(r'\bgit\s+push\s+-f\b').hasMatch(lower)) {
      return (true, 'Force push can overwrite remote history');
    }

    if (RegExp(r'\bgit\s+reset\s+--hard\b').hasMatch(lower)) {
      return (true, 'Hard reset discards all uncommitted changes');
    }

    if (RegExp(r'\bgit\s+clean\s+.*-f').hasMatch(lower)) {
      return (true, 'Clean -f permanently removes untracked files');
    }

    if (RegExp(r'\bgit\s+branch\s+(-d|-D)\s+').hasMatch(lower)) {
      return (true, 'Branch deletion');
    }

    if (RegExp(r'\bgit\s+checkout\s+--\s+\.').hasMatch(lower)) {
      return (true, 'Discard all working directory changes');
    }

    if (RegExp(r'\bgit\s+stash\s+drop\b').hasMatch(lower)) {
      return (true, 'Permanently drops a stash entry');
    }

    if (RegExp(r'\bgit\s+rebase\s+').hasMatch(lower)) {
      return (true, 'Rebase rewrites commit history');
    }

    return (false, '');
  }

  /// Check whether a push to a specific remote/branch is permitted.
  PermissionDecision checkPush(
    String remote,
    String branch, {
    bool force = false,
  }) {
    final isProtected = protectedBranches.contains(branch);

    if (force && isProtected) {
      return PermissionDecision(
        level: PermissionLevel.deny,
        reason: 'Force push to protected branch "$branch" on '
            'remote "$remote" is blocked.',
      );
    }

    final RiskLevel risk;
    if (force) {
      risk = RiskLevel.critical;
    } else if (isProtected) {
      risk = RiskLevel.high;
    } else {
      risk = RiskLevel.medium;
    }

    final request = PermissionRequest(
      scope: PermissionScope.git,
      action: 'push',
      resource: '$remote/$branch',
      detail: force
          ? 'Force push to $remote/$branch'
          : 'Push to $remote/$branch',
      riskLevel: risk,
      metadata: {
        'remote': remote,
        'branch': branch,
        'force': force,
        'isProtected': isProtected,
      },
    );

    return _ruleSet.evaluateWithCache(request, _cache);
  }
}

// ---------------------------------------------------------------------------
// Permission Audit Log
// ---------------------------------------------------------------------------

/// Records all permission requests and decisions for auditing.
class PermissionAuditLog {
  final List<PermissionAuditEntry> _entries = [];

  /// Maximum number of entries to retain.
  final int maxEntries;

  PermissionAuditLog({this.maxEntries = 10000});

  /// Number of log entries.
  int get length => _entries.length;

  /// Log a permission request and its decision.
  void log(PermissionRequest request, PermissionDecision decision) {
    _entries.add(PermissionAuditEntry(
      request: request,
      decision: decision,
      timestamp: DateTime.now(),
    ));

    if (_entries.length > maxEntries) {
      _entries.removeRange(0, _entries.length - maxEntries);
    }
  }

  /// Get log entries, optionally filtered by time and/or scope.
  List<PermissionAuditEntry> getLog({
    DateTime? since,
    PermissionScope? scope,
    PermissionLevel? level,
    int? limit,
  }) {
    Iterable<PermissionAuditEntry> results = _entries;

    if (since != null) {
      results = results.where((e) => e.timestamp.isAfter(since));
    }
    if (scope != null) {
      results = results.where((e) => e.request.scope == scope);
    }
    if (level != null) {
      results = results.where((e) => e.decision.level == level);
    }

    final list = results.toList();
    if (limit != null && list.length > limit) {
      return list.sublist(list.length - limit);
    }
    return list;
  }

  /// Get a summary of denied requests.
  List<PermissionAuditEntry> getDenied({DateTime? since}) {
    return getLog(since: since, level: PermissionLevel.deny);
  }

  /// Export the log as a list of JSON-serializable maps.
  List<Map<String, dynamic>> export() {
    return _entries.map((e) => e.toJson()).toList();
  }

  /// Clear all log entries.
  void clear() => _entries.clear();
}

/// A single audit log entry.
class PermissionAuditEntry {
  final PermissionRequest request;
  final PermissionDecision decision;
  final DateTime timestamp;

  const PermissionAuditEntry({
    required this.request,
    required this.decision,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'scope': request.scope.name,
        'action': request.action,
        'resource': request.resource,
        'toolName': request.toolName,
        'riskLevel': request.riskLevel.name,
        'decision': decision.level.name,
        'reason': decision.reason,
        'matchedRule': decision.matchedRule?.id,
      };
}

// ---------------------------------------------------------------------------
// Permission Pattern Matcher
// ---------------------------------------------------------------------------

/// Utility class for matching permission patterns against values.
///
/// Supports four pattern types:
///   - **Exact**: `"foo"` matches only `"foo"`
///   - **Prefix (wildcard)**: `"src/*"` matches `"src/main.dart"`, etc.
///   - **Glob**: `"*.dart"`, `"src/**/*.ts"` — standard glob matching
///   - **Regex**: `"regex:^[a-z]+$"` — explicit regex prefix
class PermissionPatternMatcher {
  PermissionPatternMatcher._();

  /// Match a [pattern] against a [value].
  ///
  /// Automatically detects the pattern type and delegates to the
  /// appropriate matching strategy.
  static bool match(String pattern, String value) {
    if (pattern.isEmpty) return true;

    // Explicit regex prefix
    if (pattern.startsWith('regex:')) {
      return _matchRegex(pattern.substring(6), value);
    }

    // Contains glob characters
    if (pattern.contains('*') || pattern.contains('?')) {
      return _matchGlob(pattern, value);
    }

    // Exact match
    return pattern == value;
  }

  /// Match using a regular expression pattern.
  static bool _matchRegex(String pattern, String value) {
    try {
      return RegExp(pattern).hasMatch(value);
    } catch (_) {
      // Invalid regex — treat as literal.
      return pattern == value;
    }
  }

  /// Match using glob pattern.
  ///
  /// Supports:
  ///   - `*` matches any characters except `/`
  ///   - `**` matches any characters including `/`
  ///   - `?` matches any single character except `/`
  static bool _matchGlob(String pattern, String value) {
    // Convert glob to regex
    final buffer = StringBuffer('^');
    final chars = pattern.split('');

    for (var i = 0; i < chars.length; i++) {
      final char = chars[i];
      switch (char) {
        case '*':
          if (i + 1 < chars.length && chars[i + 1] == '*') {
            // ** matches everything including /
            buffer.write('.*');
            i++; // Skip next *
            // Skip trailing / after **
            if (i + 1 < chars.length && chars[i + 1] == '/') {
              buffer.write('(?:/)?');
              i++;
            }
          } else {
            // * matches everything except /
            buffer.write('[^/]*');
          }
        case '?':
          buffer.write('[^/]');
        case '.':
          buffer.write(r'\.');
        case '(':
          buffer.write(r'\(');
        case ')':
          buffer.write(r'\)');
        case '{':
          buffer.write(r'\{');
        case '}':
          buffer.write(r'\}');
        case '[':
          buffer.write(r'\[');
        case ']':
          buffer.write(r'\]');
        case '+':
          buffer.write(r'\+');
        case '^':
          buffer.write(r'\^');
        case r'$':
          buffer.write(r'\$');
        case '|':
          buffer.write(r'\|');
        case r'\':
          buffer.write(r'\\');
        default:
          buffer.write(char);
      }
    }

    buffer.write(r'$');

    try {
      return RegExp(buffer.toString()).hasMatch(value);
    } catch (_) {
      return false;
    }
  }

  /// Check if a pattern is a valid regex when prefixed with "regex:".
  static bool isValidRegex(String pattern) {
    if (!pattern.startsWith('regex:')) return true;
    try {
      RegExp(pattern.substring(6));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Return the type of a pattern as a human-readable string.
  static String patternType(String pattern) {
    if (pattern.startsWith('regex:')) return 'regex';
    if (pattern.contains('**')) return 'doubleGlob';
    if (pattern.contains('*') || pattern.contains('?')) return 'glob';
    return 'exact';
  }
}
