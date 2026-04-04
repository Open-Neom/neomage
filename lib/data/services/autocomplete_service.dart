// AutocompleteService — port of neom_claw/src/services/PromptSuggestion/.
// Provides intelligent prompt suggestions, file completions, command completions,
// and contextual auto-complete for the chat input.

import 'dart:async';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';

// ─── Types ───

/// Type of auto-complete suggestion.
enum SuggestionType {
  file,
  directory,
  command,
  symbol,
  gitBranch,
  gitRef,
  model,
  mcpTool,
  mcpServer,
  historyEntry,
  snippet,
  variable,
  path,
  url,
}

/// Category for prompt suggestions.
enum PromptCategory {
  coding,
  debugging,
  refactoring,
  testing,
  documentation,
  git,
  devops,
  general,
}

/// A single auto-complete suggestion.
class CompletionSuggestion {
  final String value;
  final String displayText;
  final String? description;
  final SuggestionType type;
  final String? icon;
  final double score;
  final String? detail;
  final String? insertText;
  final int? cursorOffset; // where to place cursor after insert
  final Map<String, dynamic>? metadata;

  const CompletionSuggestion({
    required this.value,
    required this.displayText,
    this.description,
    required this.type,
    this.icon,
    this.score = 0.0,
    this.detail,
    this.insertText,
    this.cursorOffset,
    this.metadata,
  });

  CompletionSuggestion withScore(double newScore) => CompletionSuggestion(
        value: value,
        displayText: displayText,
        description: description,
        type: type,
        icon: icon,
        score: newScore,
        detail: detail,
        insertText: insertText,
        cursorOffset: cursorOffset,
        metadata: metadata,
      );
}

/// A prompt suggestion (canned/intelligent prompt).
class PromptSuggestion {
  final String text;
  final String title;
  final String? description;
  final PromptCategory category;
  final List<String> tags;
  final int usageCount;
  final DateTime? lastUsed;
  final bool isCustom;
  final String? requiredContext; // 'git', 'file', 'project', etc.

  const PromptSuggestion({
    required this.text,
    required this.title,
    this.description,
    required this.category,
    this.tags = const [],
    this.usageCount = 0,
    this.lastUsed,
    this.isCustom = false,
    this.requiredContext,
  });

  PromptSuggestion copyWith({int? usageCount, DateTime? lastUsed}) =>
      PromptSuggestion(
        text: text,
        title: title,
        description: description,
        category: category,
        tags: tags,
        usageCount: usageCount ?? this.usageCount,
        lastUsed: lastUsed ?? this.lastUsed,
        isCustom: isCustom,
        requiredContext: requiredContext,
      );
}

/// Context for generating relevant suggestions.
class SuggestionContext {
  final String currentInput;
  final int cursorPosition;
  final String? currentFile;
  final String? currentDirectory;
  final String? gitBranch;
  final List<String> recentFiles;
  final List<String> recentCommands;
  final String? projectType; // 'dart', 'node', 'python', etc.
  final bool hasGit;
  final List<String> availableCommands;
  final List<String> availableTools;

  const SuggestionContext({
    required this.currentInput,
    required this.cursorPosition,
    this.currentFile,
    this.currentDirectory,
    this.gitBranch,
    this.recentFiles = const [],
    this.recentCommands = const [],
    this.projectType,
    this.hasGit = false,
    this.availableCommands = const [],
    this.availableTools = const [],
  });
}

// ─── Completion Provider Interface ───

/// Abstract completion provider. Multiple providers can be registered.
abstract class CompletionProvider {
  String get name;
  SuggestionType get type;
  int get priority;

  Future<List<CompletionSuggestion>> getSuggestions(
    String query,
    SuggestionContext context,
  );

  bool canHandle(String query, SuggestionContext context);
}

// ─── File Completion Provider ───

/// Provides file path completions.
class FileCompletionProvider implements CompletionProvider {
  @override
  String get name => 'file';
  @override
  SuggestionType get type => SuggestionType.file;
  @override
  int get priority => 10;

  @override
  bool canHandle(String query, SuggestionContext context) {
    return query.startsWith('@') ||
        query.startsWith('./') ||
        query.startsWith('/') ||
        query.startsWith('~/') ||
        query.contains('/');
  }

  @override
  Future<List<CompletionSuggestion>> getSuggestions(
    String query,
    SuggestionContext context,
  ) async {
    String searchPath;
    String prefix;

    if (query.startsWith('@')) {
      prefix = query.substring(1);
      searchPath = context.currentDirectory ?? '.';
    } else {
      prefix = query;
      searchPath = context.currentDirectory ?? '.';
    }

    // Resolve path.
    final parts = prefix.split('/');
    final dirPart = parts.length > 1 ? parts.sublist(0, parts.length - 1).join('/') : '';
    final filePart = parts.last.toLowerCase();

    String targetDir;
    if (prefix.startsWith('/')) {
      targetDir = dirPart.isEmpty ? '/' : dirPart;
    } else if (prefix.startsWith('~/')) {
      final home = Platform.environment['HOME'] ?? '.';
      targetDir = dirPart.isEmpty ? home : '$home/${dirPart.substring(2)}';
    } else {
      targetDir = dirPart.isEmpty ? searchPath : '$searchPath/$dirPart';
    }

    final suggestions = <CompletionSuggestion>[];

    try {
      final dir = Directory(targetDir);
      if (!await dir.exists()) return suggestions;

      await for (final entity in dir.list()) {
        final name = entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .lastOrNull ?? '';

        // Skip hidden files unless query starts with '.'
        if (name.startsWith('.') && !filePart.startsWith('.')) continue;

        // Fuzzy match.
        if (filePart.isNotEmpty && !_fuzzyMatch(name, filePart)) continue;

        final isDir = entity is Directory;
        final relativePath =
            dirPart.isEmpty ? name : '$dirPart/$name';
        final icon = isDir
            ? 'folder'
            : _fileIcon(name);

        suggestions.add(CompletionSuggestion(
          value: relativePath,
          displayText: name,
          description: isDir ? 'Directory' : _fileDescription(name),
          type: isDir ? SuggestionType.directory : SuggestionType.file,
          icon: icon,
          score: _fuzzyScore(name, filePart),
          insertText: isDir ? '$relativePath/' : relativePath,
        ));
      }
    } catch (_) {
      // Permission denied or other IO error.
    }

    suggestions.sort((a, b) => b.score.compareTo(a.score));
    return suggestions.take(20).toList();
  }

  String _fileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => 'code',
      'ts' || 'tsx' || 'js' || 'jsx' => 'code',
      'py' => 'code',
      'rs' => 'code',
      'go' => 'code',
      'java' || 'kt' => 'code',
      'yaml' || 'yml' || 'json' || 'toml' => 'settings',
      'md' || 'txt' || 'rst' => 'document',
      'png' || 'jpg' || 'gif' || 'svg' => 'image',
      'sh' || 'bash' || 'zsh' => 'terminal',
      _ => 'file',
    };
  }

  String _fileDescription(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'dart' => 'Dart source',
      'ts' => 'TypeScript',
      'tsx' => 'TypeScript React',
      'js' => 'JavaScript',
      'py' => 'Python',
      'rs' => 'Rust',
      'go' => 'Go',
      'yaml' || 'yml' => 'YAML',
      'json' => 'JSON',
      'md' => 'Markdown',
      'toml' => 'TOML',
      'sh' || 'bash' => 'Shell script',
      _ => ext.isEmpty ? 'File' : '.$ext file',
    };
  }
}

// ─── Command Completion Provider ───

/// Provides slash command completions.
class CommandCompletionProvider implements CompletionProvider {
  @override
  String get name => 'command';
  @override
  SuggestionType get type => SuggestionType.command;
  @override
  int get priority => 20;

  @override
  bool canHandle(String query, SuggestionContext context) {
    return query.startsWith('/');
  }

  @override
  Future<List<CompletionSuggestion>> getSuggestions(
    String query,
    SuggestionContext context,
  ) async {
    final search = query.substring(1).toLowerCase(); // Remove '/'

    final commands = context.availableCommands;
    final suggestions = <CompletionSuggestion>[];

    for (final cmd in commands) {
      if (search.isEmpty || _fuzzyMatch(cmd, search)) {
        suggestions.add(CompletionSuggestion(
          value: '/$cmd',
          displayText: '/$cmd',
          description: _commandDescription(cmd),
          type: SuggestionType.command,
          icon: 'command',
          score: _fuzzyScore(cmd, search),
          insertText: '/$cmd ',
        ));
      }
    }

    suggestions.sort((a, b) => b.score.compareTo(a.score));
    return suggestions.take(15).toList();
  }

  String _commandDescription(String cmd) {
    return switch (cmd) {
      'help' => 'Show available commands',
      'clear' => 'Clear conversation',
      'compact' => 'Compact context window',
      'cost' => 'Show token usage and cost',
      'model' => 'Switch AI model',
      'commit' => 'Create a git commit',
      'diff' => 'Show file changes',
      'review' => 'Review code changes',
      'plan' => 'Enter plan mode',
      'session' => 'Manage sessions',
      'memory' => 'Manage memory files',
      'context' => 'Show context info',
      'config' => 'Edit configuration',
      'permissions' => 'Manage permissions',
      'hooks' => 'Manage hooks',
      'theme' => 'Change theme',
      'vim' => 'Toggle vim mode',
      'mcp' => 'Manage MCP servers',
      'tasks' => 'View background tasks',
      'agents' => 'View active agents',
      'doctor' => 'Run diagnostics',
      'export' => 'Export conversation',
      'bug' => 'Report a bug',
      'init' => 'Initialize project',
      'status' => 'Show project status',
      'login' => 'Authenticate',
      'logout' => 'Sign out',
      'resume' => 'Resume a session',
      'undo' => 'Undo last file change',
      'profile' => 'Show profile info',
      'tools' => 'List available tools',
      'listen' => 'Toggle voice input',
      'prompt' => 'Edit system prompt',
      'ide' => 'IDE integration',
      _ => 'Execute /$cmd',
    };
  }
}

// ─── Git Completion Provider ───

/// Provides git branch and ref completions.
class GitCompletionProvider implements CompletionProvider {
  @override
  String get name => 'git';
  @override
  SuggestionType get type => SuggestionType.gitBranch;
  @override
  int get priority => 5;

  @override
  bool canHandle(String query, SuggestionContext context) {
    return context.hasGit && query.startsWith('#');
  }

  @override
  Future<List<CompletionSuggestion>> getSuggestions(
    String query,
    SuggestionContext context,
  ) async {
    final search = query.substring(1).toLowerCase(); // Remove '#'
    final suggestions = <CompletionSuggestion>[];

    try {
      final result = await Process.run('git', ['branch', '-a', '--format=%(refname:short)'],
          workingDirectory: context.currentDirectory);
      if (result.exitCode == 0) {
        final branches = (result.stdout as String)
            .split('\n')
            .where((b) => b.trim().isNotEmpty)
            .toList();

        for (final branch in branches) {
          final name = branch.trim();
          if (search.isEmpty || _fuzzyMatch(name, search)) {
            final isRemote = name.startsWith('origin/');
            suggestions.add(CompletionSuggestion(
              value: name,
              displayText: name,
              description: isRemote ? 'Remote branch' : 'Local branch',
              type: SuggestionType.gitBranch,
              icon: isRemote ? 'cloud' : 'branch',
              score: _fuzzyScore(name, search),
            ));
          }
        }
      }

      // Also add recent tags.
      final tagResult = await Process.run('git', ['tag', '-l', '--sort=-version:refname'],
          workingDirectory: context.currentDirectory);
      if (tagResult.exitCode == 0) {
        final tags = (tagResult.stdout as String)
            .split('\n')
            .where((t) => t.trim().isNotEmpty)
            .take(10)
            .toList();

        for (final tag in tags) {
          final name = tag.trim();
          if (search.isEmpty || _fuzzyMatch(name, search)) {
            suggestions.add(CompletionSuggestion(
              value: name,
              displayText: name,
              description: 'Tag',
              type: SuggestionType.gitRef,
              icon: 'tag',
              score: _fuzzyScore(name, search) * 0.8, // Slightly lower than branches
            ));
          }
        }
      }
    } catch (_) {}

    suggestions.sort((a, b) => b.score.compareTo(a.score));
    return suggestions.take(15).toList();
  }
}

// ─── Snippet Provider ───

/// Provides code snippet suggestions.
class SnippetProvider implements CompletionProvider {
  @override
  String get name => 'snippet';
  @override
  SuggestionType get type => SuggestionType.snippet;
  @override
  int get priority => 3;

  final List<_Snippet> _snippets = [
    _Snippet('fix-bug', 'Fix a bug', 'Fix the bug in {file} where {description}', PromptCategory.debugging),
    _Snippet('add-test', 'Add tests', 'Add comprehensive tests for {file/function}', PromptCategory.testing),
    _Snippet('refactor', 'Refactor code', 'Refactor {file/function} to improve {readability/performance/maintainability}', PromptCategory.refactoring),
    _Snippet('add-docs', 'Add documentation', 'Add documentation comments to all public APIs in {file}', PromptCategory.documentation),
    _Snippet('review', 'Code review', 'Review the recent changes and suggest improvements', PromptCategory.coding),
    _Snippet('explain', 'Explain code', 'Explain how {file/function} works step by step', PromptCategory.coding),
    _Snippet('optimize', 'Optimize performance', 'Optimize {file/function} for better performance', PromptCategory.coding),
    _Snippet('add-error-handling', 'Add error handling', 'Add proper error handling to {file/function}', PromptCategory.coding),
    _Snippet('add-logging', 'Add logging', 'Add appropriate logging to {file/module}', PromptCategory.coding),
    _Snippet('create-api', 'Create API endpoint', 'Create a REST API endpoint for {resource} with CRUD operations', PromptCategory.coding),
    _Snippet('git-commit', 'Create commit', 'Review my changes and create a well-formatted git commit', PromptCategory.git),
    _Snippet('git-pr', 'Create PR', 'Create a pull request with a summary of all my changes', PromptCategory.git),
    _Snippet('add-ci', 'Add CI/CD', 'Set up CI/CD pipeline with {GitHub Actions/GitLab CI}', PromptCategory.devops),
    _Snippet('add-dockerfile', 'Add Dockerfile', 'Create a Dockerfile for this project', PromptCategory.devops),
    _Snippet('security-audit', 'Security audit', 'Audit the codebase for security vulnerabilities', PromptCategory.coding),
    _Snippet('migrate-db', 'Database migration', 'Create a database migration for {change}', PromptCategory.coding),
    _Snippet('add-types', 'Add type annotations', 'Add type annotations to {file/function}', PromptCategory.coding),
    _Snippet('cleanup', 'Clean up code', 'Clean up {file}: remove dead code, fix formatting, organize imports', PromptCategory.refactoring),
    _Snippet('implement-feature', 'Implement feature', 'Implement {feature description} following the existing patterns', PromptCategory.coding),
    _Snippet('debug-error', 'Debug error', 'Debug this error: {paste error message}', PromptCategory.debugging),
  ];

  @override
  bool canHandle(String query, SuggestionContext context) {
    return query.startsWith('>') || query.startsWith('prompt:');
  }

  @override
  Future<List<CompletionSuggestion>> getSuggestions(
    String query,
    SuggestionContext context,
  ) async {
    final search = query.startsWith('>')
        ? query.substring(1).trim().toLowerCase()
        : query.substring(7).trim().toLowerCase();

    return _snippets
        .where((s) =>
            search.isEmpty ||
            _fuzzyMatch(s.id, search) ||
            _fuzzyMatch(s.title, search))
        .map((s) => CompletionSuggestion(
              value: s.template,
              displayText: s.title,
              description: s.template,
              type: SuggestionType.snippet,
              icon: 'snippet',
              score: _fuzzyScore(s.title, search),
              insertText: s.template,
            ))
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));
  }
}

class _Snippet {
  final String id;
  final String title;
  final String template;
  final PromptCategory category;
  const _Snippet(this.id, this.title, this.template, this.category);
}

// ─── Autocomplete Service ───

/// Main autocomplete service that aggregates multiple providers.
class AutocompleteService {
  final List<CompletionProvider> _providers = [];
  final List<PromptSuggestion> _promptSuggestions = [];
  final List<String> _recentInputs = [];
  final int _maxRecentInputs;
  Timer? _debounceTimer;

  AutocompleteService({int maxRecentInputs = 100})
      : _maxRecentInputs = maxRecentInputs {
    // Register default providers.
    _providers.addAll([
      FileCompletionProvider(),
      CommandCompletionProvider(),
      GitCompletionProvider(),
      SnippetProvider(),
    ]);

    // Load built-in prompt suggestions.
    _loadBuiltInPrompts();
  }

  /// Register a custom completion provider.
  void registerProvider(CompletionProvider provider) {
    _providers.add(provider);
    _providers.sort((a, b) => b.priority.compareTo(a.priority));
  }

  /// Unregister a completion provider.
  void unregisterProvider(String name) {
    _providers.removeWhere((p) => p.name == name);
  }

  /// Get completions for the current input.
  Future<List<CompletionSuggestion>> getCompletions(
    SuggestionContext context, {
    int maxResults = 15,
    Duration debounce = const Duration(milliseconds: 150),
  }) async {
    final input = context.currentInput;
    if (input.isEmpty) return [];

    // Determine the word being completed.
    final wordStart = _findWordStart(input, context.cursorPosition);
    final query = input.substring(wordStart, context.cursorPosition);

    if (query.isEmpty) return [];

    // Collect suggestions from all applicable providers.
    final allSuggestions = <CompletionSuggestion>[];

    for (final provider in _providers) {
      if (provider.canHandle(query, context)) {
        try {
          final suggestions = await provider.getSuggestions(query, context);
          allSuggestions.addAll(suggestions);
        } catch (_) {
          // Skip failed providers.
        }
      }
    }

    // Add recent input matches.
    if (!query.startsWith('/') && !query.startsWith('@') && !query.startsWith('#')) {
      for (final recent in _recentInputs) {
        if (_fuzzyMatch(recent, query) && recent != input) {
          allSuggestions.add(CompletionSuggestion(
            value: recent,
            displayText: recent.length > 60
                ? '${recent.substring(0, 60)}...'
                : recent,
            description: 'Recent input',
            type: SuggestionType.historyEntry,
            icon: 'history',
            score: _fuzzyScore(recent, query) * 0.5, // Lower priority
          ));
        }
      }
    }

    // Sort by score and deduplicate.
    allSuggestions.sort((a, b) => b.score.compareTo(a.score));
    final seen = <String>{};
    return allSuggestions
        .where((s) => seen.add(s.value))
        .take(maxResults)
        .toList();
  }

  /// Get prompt suggestions based on context.
  List<PromptSuggestion> getPromptSuggestions({
    PromptCategory? category,
    String? search,
    String? projectType,
    bool? hasGit,
    int limit = 10,
  }) {
    var suggestions = List<PromptSuggestion>.from(_promptSuggestions);

    if (category != null) {
      suggestions = suggestions.where((s) => s.category == category).toList();
    }

    if (search != null && search.isNotEmpty) {
      final query = search.toLowerCase();
      suggestions = suggestions.where((s) {
        return s.title.toLowerCase().contains(query) ||
            s.text.toLowerCase().contains(query) ||
            s.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    }

    // Filter by required context.
    if (hasGit == false) {
      suggestions =
          suggestions.where((s) => s.requiredContext != 'git').toList();
    }

    // Sort by usage count (most used first), then by name.
    suggestions.sort((a, b) {
      final usageCmp = b.usageCount.compareTo(a.usageCount);
      if (usageCmp != 0) return usageCmp;
      return a.title.compareTo(b.title);
    });

    return suggestions.take(limit).toList();
  }

  /// Record that a prompt suggestion was used (for ranking).
  void recordPromptUsage(String promptText) {
    final idx =
        _promptSuggestions.indexWhere((s) => s.text == promptText);
    if (idx >= 0) {
      _promptSuggestions[idx] = _promptSuggestions[idx].copyWith(
        usageCount: _promptSuggestions[idx].usageCount + 1,
        lastUsed: DateTime.now(),
      );
    }
  }

  /// Add a custom prompt suggestion.
  void addCustomPrompt(PromptSuggestion suggestion) {
    _promptSuggestions.add(suggestion);
  }

  /// Record a user input for history-based completions.
  void recordInput(String input) {
    if (input.isEmpty || input.startsWith('/')) return;
    _recentInputs.remove(input); // Remove duplicate.
    _recentInputs.insert(0, input);
    if (_recentInputs.length > _maxRecentInputs) {
      _recentInputs.removeLast();
    }
  }

  /// Get inline completion (ghost text) for current input.
  Future<String?> getInlineCompletion(SuggestionContext context) async {
    final input = context.currentInput;
    if (input.length < 3) return null;

    // Check recent inputs for prefix match.
    for (final recent in _recentInputs) {
      if (recent.startsWith(input) && recent != input) {
        return recent.substring(input.length);
      }
    }

    // Check prompt suggestions for prefix match.
    for (final prompt in _promptSuggestions) {
      if (prompt.text.startsWith(input) && prompt.text != input) {
        return prompt.text.substring(input.length);
      }
    }

    return null;
  }

  // ─── Internal ───

  int _findWordStart(String text, int cursor) {
    if (cursor <= 0) return 0;
    int i = cursor - 1;
    // Walk backwards to find word boundary.
    while (i >= 0) {
      final c = text[i];
      if (c == ' ' || c == '\n' || c == '\t') {
        return i + 1;
      }
      i--;
    }
    return 0;
  }

  void _loadBuiltInPrompts() {
    _promptSuggestions.addAll([
      const PromptSuggestion(
        text: 'Explain how this codebase is structured',
        title: 'Explain codebase',
        category: PromptCategory.general,
        tags: ['architecture', 'overview'],
      ),
      const PromptSuggestion(
        text: 'Find and fix any bugs in the recent changes',
        title: 'Find bugs in changes',
        category: PromptCategory.debugging,
        tags: ['bugs', 'review'],
        requiredContext: 'git',
      ),
      const PromptSuggestion(
        text: 'Write comprehensive tests for the untested code',
        title: 'Write tests',
        category: PromptCategory.testing,
        tags: ['testing', 'coverage'],
      ),
      const PromptSuggestion(
        text: 'Review my changes and suggest improvements',
        title: 'Review changes',
        category: PromptCategory.coding,
        tags: ['review', 'improvements'],
        requiredContext: 'git',
      ),
      const PromptSuggestion(
        text: 'Create a git commit with a descriptive message',
        title: 'Create commit',
        category: PromptCategory.git,
        tags: ['git', 'commit'],
        requiredContext: 'git',
      ),
      const PromptSuggestion(
        text: 'Refactor this code for better readability',
        title: 'Refactor for readability',
        category: PromptCategory.refactoring,
        tags: ['refactor', 'clean'],
      ),
      const PromptSuggestion(
        text: 'Add error handling and edge case coverage',
        title: 'Add error handling',
        category: PromptCategory.coding,
        tags: ['error-handling', 'robustness'],
      ),
      const PromptSuggestion(
        text: 'Add documentation comments to public APIs',
        title: 'Add documentation',
        category: PromptCategory.documentation,
        tags: ['docs', 'comments'],
      ),
      const PromptSuggestion(
        text: 'Optimize performance in the hot path',
        title: 'Optimize performance',
        category: PromptCategory.coding,
        tags: ['performance', 'optimization'],
      ),
      const PromptSuggestion(
        text: 'Set up CI/CD pipeline for this project',
        title: 'Set up CI/CD',
        category: PromptCategory.devops,
        tags: ['ci', 'cd', 'pipeline'],
      ),
      const PromptSuggestion(
        text: 'Create a pull request with a summary of changes',
        title: 'Create pull request',
        category: PromptCategory.git,
        tags: ['git', 'pr', 'pull-request'],
        requiredContext: 'git',
      ),
      const PromptSuggestion(
        text: 'Audit the codebase for security vulnerabilities',
        title: 'Security audit',
        category: PromptCategory.coding,
        tags: ['security', 'audit', 'vulnerability'],
      ),
      const PromptSuggestion(
        text: 'Add proper logging throughout the codebase',
        title: 'Add logging',
        category: PromptCategory.coding,
        tags: ['logging', 'observability'],
      ),
      const PromptSuggestion(
        text: 'Create a Dockerfile and docker-compose for this project',
        title: 'Add Docker support',
        category: PromptCategory.devops,
        tags: ['docker', 'containerization'],
      ),
      const PromptSuggestion(
        text: 'Implement the feature described in the latest issue',
        title: 'Implement feature',
        category: PromptCategory.coding,
        tags: ['feature', 'implement'],
      ),
    ]);
  }

  /// Dispose resources.
  void dispose() {
    _debounceTimer?.cancel();
  }
}

// ─── Fuzzy matching utilities ───

/// Check if a string fuzzy-matches a query.
bool _fuzzyMatch(String text, String query) {
  if (query.isEmpty) return true;
  final lower = text.toLowerCase();
  final q = query.toLowerCase();

  int qi = 0;
  for (int i = 0; i < lower.length && qi < q.length; i++) {
    if (lower[i] == q[qi]) qi++;
  }
  return qi == q.length;
}

/// Compute a fuzzy match score (higher = better match).
double _fuzzyScore(String text, String query) {
  if (query.isEmpty) return 1.0;
  final lower = text.toLowerCase();
  final q = query.toLowerCase();

  // Exact prefix match gets highest score.
  if (lower.startsWith(q)) return 100.0 + (1.0 / text.length);

  // Exact contains match gets high score.
  if (lower.contains(q)) return 80.0 + (1.0 / text.length);

  // Fuzzy match scoring.
  double score = 0;
  int qi = 0;
  int lastMatchIndex = -1;
  int consecutiveMatches = 0;

  for (int i = 0; i < lower.length && qi < q.length; i++) {
    if (lower[i] == q[qi]) {
      score += 10;

      // Bonus for consecutive matches.
      if (lastMatchIndex == i - 1) {
        consecutiveMatches++;
        score += consecutiveMatches * 5;
      } else {
        consecutiveMatches = 0;
      }

      // Bonus for word boundary match.
      if (i == 0 || text[i - 1] == '_' || text[i - 1] == '-' || text[i - 1] == '/' ||
          (text[i - 1].toLowerCase() == text[i - 1] && text[i].toUpperCase() == text[i])) {
        score += 15;
      }

      lastMatchIndex = i;
      qi++;
    }
  }

  // Penalty for unmatched query characters.
  if (qi < q.length) return 0;

  // Normalize by text length (prefer shorter matches).
  return score / sqrt(text.length);
}
