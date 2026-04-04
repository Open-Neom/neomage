/// Git worktree management: creating, listing, cleaning up worktrees.
///
/// Ported from openneomclaw/src/utils/worktree.ts (1519 LOC).
library;

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

final RegExp _validWorktreeSlugSegment = RegExp(r'^[a-zA-Z0-9._-]+$');
const int _maxWorktreeSlugLength = 64;

/// Env vars to prevent git/SSH from prompting for credentials (which hangs the CLI).
const Map<String, String> _gitNoPromptEnv = {
  'GIT_TERMINAL_PROMPT': '0',
  'GIT_ASKPASS': '',
};

/// Slug patterns for throwaway worktrees created by AgentTool, WorkflowTool,
/// and bridgeMain. These leak when the parent process is killed before their
/// in-process cleanup runs.
final List<RegExp> _ephemeralWorktreePatterns = [
  RegExp(r'^agent-a[0-9a-f]{7}$'),
  RegExp(r'^wf_[0-9a-f]{8}-[0-9a-f]{3}-\d+$'),
  RegExp(r'^wf-\d+$'),
  RegExp(r'^bridge-[A-Za-z0-9_]+(-[A-Za-z0-9_]+)*$'),
  RegExp(r'^job-[a-zA-Z0-9._-]{1,55}-[0-9a-f]{8}$'),
];

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Represents an active worktree session.
class WorktreeSession {
  final String originalCwd;
  final String worktreePath;
  final String worktreeName;
  final String? worktreeBranch;
  final String? originalBranch;
  final String? originalHeadCommit;
  final String sessionId;
  final String? tmuxSessionName;
  final bool hookBased;

  /// How long worktree creation took (unset when resuming an existing worktree).
  final int? creationDurationMs;

  /// True if git sparse-checkout was applied via settings.worktree.sparsePaths.
  final bool usedSparsePaths;

  const WorktreeSession({
    required this.originalCwd,
    required this.worktreePath,
    required this.worktreeName,
    this.worktreeBranch,
    this.originalBranch,
    this.originalHeadCommit,
    required this.sessionId,
    this.tmuxSessionName,
    this.hookBased = false,
    this.creationDurationMs,
    this.usedSparsePaths = false,
  });

  WorktreeSession copyWith({
    String? originalCwd,
    String? worktreePath,
    String? worktreeName,
    String? worktreeBranch,
    String? originalBranch,
    String? originalHeadCommit,
    String? sessionId,
    String? tmuxSessionName,
    bool? hookBased,
    int? creationDurationMs,
    bool? usedSparsePaths,
  }) {
    return WorktreeSession(
      originalCwd: originalCwd ?? this.originalCwd,
      worktreePath: worktreePath ?? this.worktreePath,
      worktreeName: worktreeName ?? this.worktreeName,
      worktreeBranch: worktreeBranch ?? this.worktreeBranch,
      originalBranch: originalBranch ?? this.originalBranch,
      originalHeadCommit: originalHeadCommit ?? this.originalHeadCommit,
      sessionId: sessionId ?? this.sessionId,
      tmuxSessionName: tmuxSessionName ?? this.tmuxSessionName,
      hookBased: hookBased ?? this.hookBased,
      creationDurationMs: creationDurationMs ?? this.creationDurationMs,
      usedSparsePaths: usedSparsePaths ?? this.usedSparsePaths,
    );
  }

  Map<String, dynamic> toJson() => {
        'originalCwd': originalCwd,
        'worktreePath': worktreePath,
        'worktreeName': worktreeName,
        if (worktreeBranch != null) 'worktreeBranch': worktreeBranch,
        if (originalBranch != null) 'originalBranch': originalBranch,
        if (originalHeadCommit != null)
          'originalHeadCommit': originalHeadCommit,
        'sessionId': sessionId,
        if (tmuxSessionName != null) 'tmuxSessionName': tmuxSessionName,
        'hookBased': hookBased,
        if (creationDurationMs != null)
          'creationDurationMs': creationDurationMs,
        'usedSparsePaths': usedSparsePaths,
      };

  factory WorktreeSession.fromJson(Map<String, dynamic> json) {
    return WorktreeSession(
      originalCwd: json['originalCwd'] as String,
      worktreePath: json['worktreePath'] as String,
      worktreeName: json['worktreeName'] as String,
      worktreeBranch: json['worktreeBranch'] as String?,
      originalBranch: json['originalBranch'] as String?,
      originalHeadCommit: json['originalHeadCommit'] as String?,
      sessionId: json['sessionId'] as String,
      tmuxSessionName: json['tmuxSessionName'] as String?,
      hookBased: json['hookBased'] as bool? ?? false,
      creationDurationMs: json['creationDurationMs'] as int?,
      usedSparsePaths: json['usedSparsePaths'] as bool? ?? false,
    );
  }
}

/// Result of creating or resuming a worktree.
sealed class WorktreeCreateResult {
  final String worktreePath;
  final String worktreeBranch;
  final String headCommit;

  const WorktreeCreateResult({
    required this.worktreePath,
    required this.worktreeBranch,
    required this.headCommit,
  });
}

class WorktreeCreated extends WorktreeCreateResult {
  final String baseBranch;

  const WorktreeCreated({
    required super.worktreePath,
    required super.worktreeBranch,
    required super.headCommit,
    required this.baseBranch,
  });
}

class WorktreeResumed extends WorktreeCreateResult {
  const WorktreeResumed({
    required super.worktreePath,
    required super.worktreeBranch,
    required super.headCommit,
  });
}

/// Options for worktree creation.
class WorktreeCreateOptions {
  final int? prNumber;

  const WorktreeCreateOptions({this.prNumber});
}

// ---------------------------------------------------------------------------
// Result type for exec commands
// ---------------------------------------------------------------------------

class ExecResult {
  final int code;
  final String stdout;
  final String stderr;
  final String? error;

  const ExecResult({
    required this.code,
    this.stdout = '',
    this.stderr = '',
    this.error,
  });
}

// ---------------------------------------------------------------------------
// WorktreeManager SintController
// ---------------------------------------------------------------------------

/// Manages git worktree lifecycle: creation, listing, cleanup, tmux integration.
class WorktreeManager extends SintController {
  /// The currently active worktree session.
  final Rxn<WorktreeSession> currentSession = Rxn<WorktreeSession>(null);

  /// Path to the git executable.
  String _gitExe = 'git';

  /// Callback for getting the current working directory.
  String Function() _getCwd = () => Directory.current.path;

  /// Callback for finding the git root.
  String? Function(String path) _findGitRoot = _defaultFindGitRoot;

  /// Callback for finding the canonical git root.
  String? Function(String path) _findCanonicalGitRoot =
      _defaultFindCanonicalGitRoot;

  /// Callback for getting the default branch.
  Future<String> Function() _getDefaultBranch =
      () async => 'main';

  /// Callback for getting the current branch.
  Future<String> Function() _getBranch =
      () async => 'main';

  /// Callback for saving project config.
  void Function(WorktreeSession? session)? onSaveProjectConfig;

  /// Callback for executing worktree create hooks.
  Future<({String worktreePath})> Function(String slug)?
      onExecuteWorktreeCreateHook;

  /// Callback for executing worktree remove hooks.
  Future<bool> Function(String worktreePath)? onExecuteWorktreeRemoveHook;

  /// Callback for checking if worktree create hook exists.
  bool Function() _hasWorktreeCreateHook = () => false;

  /// Callback for reading worktree HEAD SHA.
  Future<String?> Function(String worktreePath) _readWorktreeHeadSha =
      (_) async => null;

  /// Callback for logging debug messages.
  void Function(String message, {String? level}) _logForDebugging =
      (message, {level}) {};

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void configure({
    String? gitExe,
    String Function()? getCwd,
    String? Function(String)? findGitRoot,
    String? Function(String)? findCanonicalGitRoot,
    Future<String> Function()? getDefaultBranch,
    Future<String> Function()? getBranch,
    void Function(WorktreeSession?)? saveProjectConfig,
    Future<({String worktreePath})> Function(String)?
        executeWorktreeCreateHook,
    Future<bool> Function(String)? executeWorktreeRemoveHook,
    bool Function()? hasWorktreeCreateHook,
    Future<String?> Function(String)? readWorktreeHeadSha,
    void Function(String, {String? level})? logForDebugging,
  }) {
    if (gitExe != null) _gitExe = gitExe;
    if (getCwd != null) _getCwd = getCwd;
    if (findGitRoot != null) _findGitRoot = findGitRoot;
    if (findCanonicalGitRoot != null) {
      _findCanonicalGitRoot = findCanonicalGitRoot;
    }
    if (getDefaultBranch != null) _getDefaultBranch = getDefaultBranch;
    if (getBranch != null) _getBranch = getBranch;
    if (saveProjectConfig != null) onSaveProjectConfig = saveProjectConfig;
    if (executeWorktreeCreateHook != null) {
      onExecuteWorktreeCreateHook = executeWorktreeCreateHook;
    }
    if (executeWorktreeRemoveHook != null) {
      onExecuteWorktreeRemoveHook = executeWorktreeRemoveHook;
    }
    if (hasWorktreeCreateHook != null) {
      _hasWorktreeCreateHook = hasWorktreeCreateHook;
    }
    if (readWorktreeHeadSha != null) {
      _readWorktreeHeadSha = readWorktreeHeadSha;
    }
    if (logForDebugging != null) _logForDebugging = logForDebugging;
  }

  // ---------------------------------------------------------------------------
  // Slug validation
  // ---------------------------------------------------------------------------

  /// Validates a worktree slug to prevent path traversal and directory escape.
  ///
  /// The slug is joined into `.neomclaw/worktrees/<slug>` via path.join, which
  /// normalizes `..` segments. Forward slashes are allowed for nesting (e.g.
  /// `asm/feature-foo`); each segment is validated independently.
  ///
  /// Throws synchronously -- callers rely on this running before any side effects.
  static void validateWorktreeSlug(String slug) {
    if (slug.length > _maxWorktreeSlugLength) {
      throw ArgumentError(
        'Invalid worktree name: must be $_maxWorktreeSlugLength characters '
        'or fewer (got ${slug.length})',
      );
    }
    for (final segment in slug.split('/')) {
      if (segment == '.' || segment == '..') {
        throw ArgumentError(
          'Invalid worktree name "$slug": must not contain "." or ".." path segments',
        );
      }
      if (!_validWorktreeSlugSegment.hasMatch(segment)) {
        throw ArgumentError(
          'Invalid worktree name "$slug": each "/"-separated segment must be '
          'non-empty and contain only letters, digits, dots, underscores, and dashes',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Naming helpers
  // ---------------------------------------------------------------------------

  /// Flatten nested slugs (`user/feature` -> `user+feature`) for both the branch
  /// name and the directory path.
  static String _flattenSlug(String slug) => slug.replaceAll('/', '+');

  /// Returns the branch name for a worktree slug.
  static String worktreeBranchName(String slug) =>
      'worktree-${_flattenSlug(slug)}';

  /// Returns the directory path for worktrees within a repo root.
  static String _worktreesDir(String repoRoot) {
    return '$repoRoot/.neomclaw/worktrees';
  }

  /// Returns the full path for a specific worktree.
  static String _worktreePathFor(String repoRoot, String slug) {
    return '${_worktreesDir(repoRoot)}/${_flattenSlug(slug)}';
  }

  /// Generates a tmux session name from repo path and branch.
  static String generateTmuxSessionName(String repoPath, String branch) {
    final repoName = repoPath.split('/').last;
    final combined = '${repoName}_$branch';
    return combined.replaceAll(RegExp(r'[/.]'), '_');
  }

  // ---------------------------------------------------------------------------
  // PR reference parsing
  // ---------------------------------------------------------------------------

  /// Parses a PR reference from a string.
  /// Accepts GitHub-style PR URLs or `#N` format.
  static int? parsePRReference(String input) {
    // GitHub-style PR URL
    final urlMatch = RegExp(
      r'^https?://[^/]+/[^/]+/[^/]+/pull/(\d+)/?(?:[?#].*)?$',
      caseSensitive: false,
    ).firstMatch(input);
    if (urlMatch != null) {
      return int.tryParse(urlMatch.group(1)!);
    }

    // #N format
    final hashMatch = RegExp(r'^#(\d+)$').firstMatch(input);
    if (hashMatch != null) {
      return int.tryParse(hashMatch.group(1)!);
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // Git command execution
  // ---------------------------------------------------------------------------

  Future<ExecResult> _execGit(
    List<String> args, {
    String? cwd,
    Map<String, String>? env,
  }) async {
    return _execFileNoThrow(_gitExe, args, cwd: cwd, env: env);
  }

  Future<ExecResult> _execFileNoThrow(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String>? env,
  }) async {
    try {
      final result = await Process.run(
        command,
        args,
        workingDirectory: cwd ?? _getCwd(),
        environment: env,
      );
      return ExecResult(
        code: result.exitCode,
        stdout: result.stdout as String? ?? '',
        stderr: result.stderr as String? ?? '',
      );
    } catch (e) {
      return ExecResult(
        code: -1,
        stderr: e.toString(),
        error: e.toString(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Worktree creation
  // ---------------------------------------------------------------------------

  /// Creates a new git worktree for the given slug, or resumes it if it already exists.
  Future<WorktreeCreateResult> _getOrCreateWorktree(
    String repoRoot,
    String slug, {
    WorktreeCreateOptions? options,
  }) async {
    final worktreePath = _worktreePathFor(repoRoot, slug);
    final worktreeBranch = worktreeBranchName(slug);

    // Fast resume path: if the worktree already exists skip fetch and creation.
    final existingHead = await _readWorktreeHeadSha(worktreePath);
    if (existingHead != null) {
      return WorktreeResumed(
        worktreePath: worktreePath,
        worktreeBranch: worktreeBranch,
        headCommit: existingHead,
      );
    }

    // New worktree: fetch base branch then add
    await Directory(_worktreesDir(repoRoot)).create(recursive: true);

    final fetchEnv = {
      ...Platform.environment,
      ..._gitNoPromptEnv,
    };

    String baseBranch;
    String? baseSha;

    if (options?.prNumber != null) {
      final prFetchResult = await _execGit(
        ['fetch', 'origin', 'pull/${options!.prNumber}/head'],
        cwd: repoRoot,
        env: fetchEnv,
      );
      if (prFetchResult.code != 0) {
        throw StateError(
          'Failed to fetch PR #${options.prNumber}: '
          '${prFetchResult.stderr.trim().isNotEmpty ? prFetchResult.stderr.trim() : 'PR may not exist or the repository may not have a remote named "origin"'}',
        );
      }
      baseBranch = 'FETCH_HEAD';
    } else {
      final defaultBranch = await _getDefaultBranch();
      final originRef = 'origin/$defaultBranch';

      // Try to resolve locally first to skip fetch
      final revParseResult = await _execGit(
        ['rev-parse', '--verify', 'refs/remotes/origin/$defaultBranch'],
        cwd: repoRoot,
      );

      if (revParseResult.code == 0 && revParseResult.stdout.trim().isNotEmpty) {
        baseBranch = originRef;
        baseSha = revParseResult.stdout.trim();
      } else {
        final fetchResult = await _execGit(
          ['fetch', 'origin', defaultBranch],
          cwd: repoRoot,
          env: fetchEnv,
        );
        baseBranch = fetchResult.code == 0 ? originRef : 'HEAD';
      }
    }

    // Resolve base SHA if we don't have it yet
    if (baseSha == null) {
      final shaResult = await _execGit(
        ['rev-parse', baseBranch],
        cwd: repoRoot,
      );
      if (shaResult.code != 0) {
        throw StateError(
          'Failed to resolve base branch "$baseBranch": git rev-parse failed',
        );
      }
      baseSha = shaResult.stdout.trim();
    }

    // Create the worktree. -B (not -b) resets any orphan branch left behind.
    final addArgs = ['worktree', 'add', '-B', worktreeBranch, worktreePath, baseBranch];

    final createResult = await _execGit(addArgs, cwd: repoRoot);
    if (createResult.code != 0) {
      throw StateError('Failed to create worktree: ${createResult.stderr}');
    }

    return WorktreeCreated(
      worktreePath: worktreePath,
      worktreeBranch: worktreeBranch,
      headCommit: baseSha,
      baseBranch: baseBranch,
    );
  }

  /// Post-creation setup for a newly created worktree.
  /// Propagates settings, configures git hooks, and symlinks directories.
  Future<void> _performPostCreationSetup(
    String repoRoot,
    String worktreePath,
  ) async {
    // Copy settings.local.json to the worktree's .neomclaw directory
    final localSettingsRelPath = '.neomclaw/settings.local.json';
    final sourceSettings = '$repoRoot/$localSettingsRelPath';
    try {
      final destSettings = '$worktreePath/$localSettingsRelPath';
      final destDir = destSettings.substring(0, destSettings.lastIndexOf('/'));
      await Directory(destDir).create(recursive: true);
      await File(sourceSettings).copy(destSettings);
      _logForDebugging('Copied settings.local.json to worktree: $destSettings');
    } catch (e) {
      if (e is! PathNotFoundException) {
        _logForDebugging(
          'Failed to copy settings.local.json: $e',
          level: 'warn',
        );
      }
    }

    // Configure the worktree to use hooks from the main repository
    final huskyPath = '$repoRoot/.husky';
    final gitHooksPath = '$repoRoot/.git/hooks';
    String? hooksPath;

    for (final candidatePath in [huskyPath, gitHooksPath]) {
      try {
        final stat = await FileStat.stat(candidatePath);
        if (stat.type == FileSystemEntityType.directory) {
          hooksPath = candidatePath;
          break;
        }
      } catch (_) {
        // Path doesn't exist or can't be accessed
      }
    }

    if (hooksPath != null) {
      final configResult = await _execGit(
        ['config', 'core.hooksPath', hooksPath],
        cwd: worktreePath,
      );
      if (configResult.code == 0) {
        _logForDebugging(
          'Configured worktree to use hooks from main repository: $hooksPath',
        );
      } else {
        _logForDebugging(
          'Failed to configure hooks path: ${configResult.stderr}',
          level: 'error',
        );
      }
    }

    // Copy gitignored files specified in .worktreeinclude (best-effort)
    await copyWorktreeIncludeFiles(repoRoot, worktreePath);
  }

  // ---------------------------------------------------------------------------
  // .worktreeinclude support
  // ---------------------------------------------------------------------------

  /// Copy gitignored files specified in .worktreeinclude from base repo to worktree.
  ///
  /// Only copies files that are BOTH:
  /// 1. Matched by patterns in .worktreeinclude (uses .gitignore syntax)
  /// 2. Gitignored (not tracked by git)
  Future<List<String>> copyWorktreeIncludeFiles(
    String repoRoot,
    String worktreePath,
  ) async {
    String includeContent;
    try {
      includeContent =
          await File('$repoRoot/.worktreeinclude').readAsString();
    } catch (_) {
      return [];
    }

    final patterns = includeContent
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('#'))
        .toList();

    if (patterns.isEmpty) return [];

    // List gitignored files with --directory for performance
    final gitignored = await _execGit(
      [
        'ls-files',
        '--others',
        '--ignored',
        '--exclude-standard',
        '--directory',
      ],
      cwd: repoRoot,
    );

    if (gitignored.code != 0 || gitignored.stdout.trim().isEmpty) return [];

    final entries =
        gitignored.stdout.trim().split('\n').where((e) => e.isNotEmpty).toList();

    final files = <String>[];
    final collapsedDirs = entries.where((e) => e.endsWith('/')).toList();

    // Simple pattern matching for gitignore-style patterns
    for (final entry in entries) {
      if (entry.endsWith('/')) continue;
      if (_matchesAnyPattern(entry, patterns)) {
        files.add(entry);
      }
    }

    // Expand collapsed directories if patterns target paths inside them
    final dirsToExpand = collapsedDirs.where((dir) {
      return patterns.any((p) {
        final normalized = p.startsWith('/') ? p.substring(1) : p;
        if (normalized.startsWith(dir)) return true;
        final globIdx = normalized.indexOf(RegExp(r'[*?[]'));
        if (globIdx > 0) {
          final literalPrefix = normalized.substring(0, globIdx);
          if (dir.startsWith(literalPrefix)) return true;
        }
        return false;
      });
    }).toList();

    if (dirsToExpand.isNotEmpty) {
      final expanded = await _execGit(
        [
          'ls-files',
          '--others',
          '--ignored',
          '--exclude-standard',
          '--',
          ...dirsToExpand,
        ],
        cwd: repoRoot,
      );
      if (expanded.code == 0 && expanded.stdout.trim().isNotEmpty) {
        for (final f
            in expanded.stdout.trim().split('\n').where((e) => e.isNotEmpty)) {
          if (_matchesAnyPattern(f, patterns)) {
            files.add(f);
          }
        }
      }
    }

    final copied = <String>[];
    for (final relativePath in files) {
      final srcPath = '$repoRoot/$relativePath';
      final destPath = '$worktreePath/$relativePath';
      try {
        final destDir = destPath.substring(0, destPath.lastIndexOf('/'));
        await Directory(destDir).create(recursive: true);
        await File(srcPath).copy(destPath);
        copied.add(relativePath);
      } catch (e) {
        _logForDebugging(
          'Failed to copy $relativePath to worktree: $e',
          level: 'warn',
        );
      }
    }

    if (copied.isNotEmpty) {
      _logForDebugging(
        'Copied ${copied.length} files from .worktreeinclude: ${copied.join(', ')}',
      );
    }

    return copied;
  }

  /// Simple gitignore-style pattern matching.
  static bool _matchesAnyPattern(String path, List<String> patterns) {
    for (final pattern in patterns) {
      final normalized = pattern.startsWith('/') ? pattern.substring(1) : pattern;
      // Simple glob matching (supports * and **)
      final regexStr = normalized
          .replaceAll('.', r'\.')
          .replaceAll('**/', '(.+/)?')
          .replaceAll('**', '.*')
          .replaceAll('*', '[^/]*')
          .replaceAll('?', '[^/]');
      if (RegExp('^$regexStr\$').hasMatch(path)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Symlink support
  // ---------------------------------------------------------------------------

  /// Symlinks directories from the main repository to avoid duplication.
  Future<void> symlinkDirectories(
    String repoRootPath,
    String worktreePath,
    List<String> dirsToSymlink,
  ) async {
    for (final dir in dirsToSymlink) {
      if (dir.contains('..')) {
        _logForDebugging(
          'Skipping symlink for "$dir": path traversal detected',
          level: 'warn',
        );
        continue;
      }

      final sourcePath = '$repoRootPath/$dir';
      final destPath = '$worktreePath/$dir';

      try {
        await Link(destPath).create(sourcePath);
        _logForDebugging(
          'Symlinked $dir from main repository to worktree to avoid disk bloat',
        );
      } on FileSystemException catch (e) {
        // ENOENT: source doesn't exist yet; EEXIST: destination already exists
        if (!e.message.contains('No such file') &&
            !e.message.contains('File exists')) {
          _logForDebugging(
            'Failed to symlink $dir: ${e.message}',
            level: 'warn',
          );
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Session management
  // ---------------------------------------------------------------------------

  /// Gets the current worktree session.
  WorktreeSession? getCurrentWorktreeSession() => currentSession.value;

  /// Restore the worktree session on --resume.
  void restoreWorktreeSession(WorktreeSession? session) {
    currentSession.value = session;
  }

  /// Creates a worktree for a session. Hook-based creation takes precedence.
  Future<WorktreeSession> createWorktreeForSession(
    String sessionId,
    String slug, {
    String? tmuxSessionName,
    WorktreeCreateOptions? options,
  }) async {
    validateWorktreeSlug(slug);
    final originalCwd = _getCwd();

    if (_hasWorktreeCreateHook() && onExecuteWorktreeCreateHook != null) {
      final hookResult = await onExecuteWorktreeCreateHook!(slug);
      _logForDebugging(
        'Created hook-based worktree at: ${hookResult.worktreePath}',
      );

      final session = WorktreeSession(
        originalCwd: originalCwd,
        worktreePath: hookResult.worktreePath,
        worktreeName: slug,
        sessionId: sessionId,
        tmuxSessionName: tmuxSessionName,
        hookBased: true,
      );
      currentSession.value = session;
    } else {
      final gitRoot = _findGitRoot(_getCwd());
      if (gitRoot == null) {
        throw StateError(
          'Cannot create a worktree: not in a git repository and no '
          'WorktreeCreate hooks are configured.',
        );
      }

      final originalBranch = await _getBranch();
      final createStart = DateTime.now().millisecondsSinceEpoch;
      final result = await _getOrCreateWorktree(gitRoot, slug, options: options);

      int? creationDurationMs;
      if (result is WorktreeCreated) {
        _logForDebugging(
          'Created worktree at: ${result.worktreePath} on branch: ${result.worktreeBranch}',
        );
        await _performPostCreationSetup(gitRoot, result.worktreePath);
        creationDurationMs =
            DateTime.now().millisecondsSinceEpoch - createStart;
      } else {
        _logForDebugging(
          'Resuming existing worktree at: ${result.worktreePath}',
        );
      }

      final session = WorktreeSession(
        originalCwd: originalCwd,
        worktreePath: result.worktreePath,
        worktreeName: slug,
        worktreeBranch: result.worktreeBranch,
        originalBranch: originalBranch,
        originalHeadCommit: result.headCommit,
        sessionId: sessionId,
        tmuxSessionName: tmuxSessionName,
        creationDurationMs: creationDurationMs,
      );
      currentSession.value = session;
    }

    onSaveProjectConfig?.call(currentSession.value);
    return currentSession.value!;
  }

  /// Keeps the worktree intact but clears the session.
  Future<void> keepWorktree() async {
    final session = currentSession.value;
    if (session == null) return;

    try {
      Directory.current = Directory(session.originalCwd);
      currentSession.value = null;
      onSaveProjectConfig?.call(null);

      _logForDebugging(
        'Linked worktree preserved at: ${session.worktreePath}'
        '${session.worktreeBranch != null ? ' on branch: ${session.worktreeBranch}' : ''}',
      );
      _logForDebugging(
        'You can continue working there by running: cd ${session.worktreePath}',
      );
    } catch (e) {
      _logForDebugging('Error keeping worktree: $e', level: 'error');
    }
  }

  /// Cleans up the worktree, removing it and its branch.
  Future<void> cleanupWorktree() async {
    final session = currentSession.value;
    if (session == null) return;

    try {
      Directory.current = Directory(session.originalCwd);

      if (session.hookBased) {
        if (onExecuteWorktreeRemoveHook != null) {
          final hookRan =
              await onExecuteWorktreeRemoveHook!(session.worktreePath);
          if (hookRan) {
            _logForDebugging(
              'Removed hook-based worktree at: ${session.worktreePath}',
            );
          } else {
            _logForDebugging(
              'No WorktreeRemove hook configured, hook-based worktree left at: '
              '${session.worktreePath}',
              level: 'warn',
            );
          }
        }
      } else {
        final removeResult = await _execGit(
          ['worktree', 'remove', '--force', session.worktreePath],
          cwd: session.originalCwd,
        );

        if (removeResult.code != 0) {
          _logForDebugging(
            'Failed to remove linked worktree: ${removeResult.stderr}',
            level: 'error',
          );
        } else {
          _logForDebugging(
            'Removed linked worktree at: ${session.worktreePath}',
          );
        }
      }

      currentSession.value = null;
      onSaveProjectConfig?.call(null);

      // Delete the temporary worktree branch (git-based only)
      if (!session.hookBased && session.worktreeBranch != null) {
        await Future.delayed(const Duration(milliseconds: 100));

        final deleteResult = await _execGit(
          ['branch', '-D', session.worktreeBranch!],
          cwd: session.originalCwd,
        );

        if (deleteResult.code != 0) {
          _logForDebugging(
            'Could not delete worktree branch: ${deleteResult.stderr}',
            level: 'error',
          );
        } else {
          _logForDebugging(
            'Deleted worktree branch: ${session.worktreeBranch}',
          );
        }
      }

      _logForDebugging('Linked worktree cleaned up completely');
    } catch (e) {
      _logForDebugging('Error cleaning up worktree: $e', level: 'error');
    }
  }

  // ---------------------------------------------------------------------------
  // Agent worktree management
  // ---------------------------------------------------------------------------

  /// Create a lightweight worktree for a subagent.
  Future<({
    String worktreePath,
    String? worktreeBranch,
    String? headCommit,
    String? gitRoot,
    bool hookBased,
  })> createAgentWorktree(String slug) async {
    validateWorktreeSlug(slug);

    if (_hasWorktreeCreateHook() && onExecuteWorktreeCreateHook != null) {
      final hookResult = await onExecuteWorktreeCreateHook!(slug);
      _logForDebugging(
        'Created hook-based agent worktree at: ${hookResult.worktreePath}',
      );
      return (
        worktreePath: hookResult.worktreePath,
        worktreeBranch: null,
        headCommit: null,
        gitRoot: null,
        hookBased: true,
      );
    }

    final gitRoot = _findCanonicalGitRoot(_getCwd());
    if (gitRoot == null) {
      throw StateError(
        'Cannot create agent worktree: not in a git repository and no '
        'WorktreeCreate hooks are configured.',
      );
    }

    final result = await _getOrCreateWorktree(gitRoot, slug);

    if (result is WorktreeCreated) {
      _logForDebugging(
        'Created agent worktree at: ${result.worktreePath} on branch: ${result.worktreeBranch}',
      );
      await _performPostCreationSetup(gitRoot, result.worktreePath);
    } else {
      // Bump mtime so periodic cleanup doesn't consider this stale
      final now = DateTime.now();
      try {
        await Process.run('touch', [result.worktreePath]);
      } catch (_) {}
      _logForDebugging(
        'Resuming existing agent worktree at: ${result.worktreePath}',
      );
    }

    return (
      worktreePath: result.worktreePath,
      worktreeBranch: result.worktreeBranch,
      headCommit: result.headCommit,
      gitRoot: gitRoot,
      hookBased: false,
    );
  }

  /// Remove a worktree created by createAgentWorktree.
  Future<bool> removeAgentWorktree(
    String worktreePath, {
    String? worktreeBranch,
    String? gitRoot,
    bool hookBased = false,
  }) async {
    if (hookBased) {
      if (onExecuteWorktreeRemoveHook != null) {
        final hookRan = await onExecuteWorktreeRemoveHook!(worktreePath);
        if (hookRan) {
          _logForDebugging(
            'Removed hook-based agent worktree at: $worktreePath',
          );
        }
        return hookRan;
      }
      return false;
    }

    if (gitRoot == null) {
      _logForDebugging(
        'Cannot remove agent worktree: no git root provided',
        level: 'error',
      );
      return false;
    }

    final removeResult = await _execGit(
      ['worktree', 'remove', '--force', worktreePath],
      cwd: gitRoot,
    );

    if (removeResult.code != 0) {
      _logForDebugging(
        'Failed to remove agent worktree: ${removeResult.stderr}',
        level: 'error',
      );
      return false;
    }

    _logForDebugging('Removed agent worktree at: $worktreePath');

    if (worktreeBranch == null) return true;

    final deleteResult = await _execGit(
      ['branch', '-D', worktreeBranch],
      cwd: gitRoot,
    );

    if (deleteResult.code != 0) {
      _logForDebugging(
        'Could not delete agent worktree branch: ${deleteResult.stderr}',
        level: 'error',
      );
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Stale worktree cleanup
  // ---------------------------------------------------------------------------

  /// Remove stale agent/workflow worktrees older than cutoffDate.
  ///
  /// Safety:
  /// - Only touches slugs matching ephemeral patterns (never user-named worktrees)
  /// - Skips the current session's worktree
  /// - Fail-closed: skips if git status fails or shows tracked changes
  /// - Fail-closed: skips if any commits aren't reachable from a remote
  Future<int> cleanupStaleAgentWorktrees(DateTime cutoffDate) async {
    final gitRoot = _findCanonicalGitRoot(_getCwd());
    if (gitRoot == null) return 0;

    final dir = _worktreesDir(gitRoot);
    List<FileSystemEntity> entries;
    try {
      entries = await Directory(dir).list().toList();
    } catch (_) {
      return 0;
    }

    final cutoffMs = cutoffDate.millisecondsSinceEpoch;
    final currentPath = currentSession.value?.worktreePath;
    int removed = 0;

    for (final entry in entries) {
      final slug = entry.path.split('/').last;
      if (!_ephemeralWorktreePatterns.any((p) => p.hasMatch(slug))) continue;

      final worktreePath = '$dir/$slug';
      if (currentPath == worktreePath) continue;

      int mtimeMs;
      try {
        final stat = await FileStat.stat(worktreePath);
        mtimeMs = stat.modified.millisecondsSinceEpoch;
      } catch (_) {
        continue;
      }
      if (mtimeMs >= cutoffMs) continue;

      // Both checks must succeed with empty output
      final statusFuture = _execGit(
        ['--no-optional-locks', 'status', '--porcelain', '-uno'],
        cwd: worktreePath,
      );
      final unpushedFuture = _execGit(
        ['rev-list', '--max-count=1', 'HEAD', '--not', '--remotes'],
        cwd: worktreePath,
      );

      final results = await Future.wait([statusFuture, unpushedFuture]);
      final status = results[0];
      final unpushed = results[1];

      if (status.code != 0 || status.stdout.trim().isNotEmpty) continue;
      if (unpushed.code != 0 || unpushed.stdout.trim().isNotEmpty) continue;

      final success = await removeAgentWorktree(
        worktreePath,
        worktreeBranch: worktreeBranchName(slug),
        gitRoot: gitRoot,
      );
      if (success) removed++;
    }

    if (removed > 0) {
      await _execGit(['worktree', 'prune'], cwd: gitRoot);
      _logForDebugging(
        'cleanupStaleAgentWorktrees: removed $removed stale worktree(s)',
      );
    }
    return removed;
  }

  // ---------------------------------------------------------------------------
  // Worktree change detection
  // ---------------------------------------------------------------------------

  /// Check whether a worktree has uncommitted changes or new commits since creation.
  Future<bool> hasWorktreeChanges(
    String worktreePath,
    String headCommit,
  ) async {
    final statusResult = await _execGit(
      ['status', '--porcelain'],
      cwd: worktreePath,
    );
    if (statusResult.code != 0) return true;
    if (statusResult.stdout.trim().isNotEmpty) return true;

    final revListResult = await _execGit(
      ['rev-list', '--count', '$headCommit..HEAD'],
      cwd: worktreePath,
    );
    if (revListResult.code != 0) return true;
    if ((int.tryParse(revListResult.stdout.trim()) ?? 0) > 0) return true;

    return false;
  }

  // ---------------------------------------------------------------------------
  // tmux integration
  // ---------------------------------------------------------------------------

  /// Check if tmux is available on the system.
  Future<bool> isTmuxAvailable() async {
    final result = await _execFileNoThrow('tmux', ['-V']);
    return result.code == 0;
  }

  /// Get tmux install instructions for the current platform.
  String getTmuxInstallInstructions() {
    if (Platform.isMacOS) {
      return 'Install tmux with: brew install tmux';
    } else if (Platform.isLinux) {
      return 'Install tmux with: sudo apt install tmux (Debian/Ubuntu) '
          'or sudo dnf install tmux (Fedora/RHEL)';
    } else if (Platform.isWindows) {
      return 'tmux is not natively available on Windows. '
          'Consider using WSL or Cygwin.';
    }
    return 'Install tmux using your system package manager.';
  }

  /// Create a tmux session for a worktree.
  Future<({bool created, String? error})> createTmuxSessionForWorktree(
    String sessionName,
    String worktreePath,
  ) async {
    final result = await _execFileNoThrow('tmux', [
      'new-session',
      '-d',
      '-s',
      sessionName,
      '-c',
      worktreePath,
    ]);

    if (result.code != 0) {
      return (created: false, error: result.stderr);
    }
    return (created: true, error: null);
  }

  /// Kill a tmux session.
  Future<bool> killTmuxSession(String sessionName) async {
    final result = await _execFileNoThrow('tmux', [
      'kill-session',
      '-t',
      sessionName,
    ]);
    return result.code == 0;
  }

  /// Fast-path handler for --worktree --tmux.
  /// Creates the worktree and execs into tmux running NeomClaw inside.
  Future<({bool handled, String? error})> execIntoTmuxWorktree(
    List<String> args,
  ) async {
    // Check platform
    if (Platform.isWindows) {
      return (handled: false, error: 'Error: --tmux is not supported on Windows');
    }

    // Check tmux
    final tmuxAvailable = await isTmuxAvailable();
    if (!tmuxAvailable) {
      return (
        handled: false,
        error: 'Error: tmux is not installed. ${getTmuxInstallInstructions()}',
      );
    }

    // Parse worktree name from args
    String? worktreeName;
    bool forceClassicTmux = false;

    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '-w' || arg == '--worktree') {
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
          worktreeName = args[i + 1];
        }
      } else if (arg.startsWith('--worktree=')) {
        worktreeName = arg.substring('--worktree='.length);
      } else if (arg == '--tmux=classic') {
        forceClassicTmux = true;
      }
    }

    // Check for PR reference
    int? prNumber;
    if (worktreeName != null) {
      prNumber = parsePRReference(worktreeName);
      if (prNumber != null) {
        worktreeName = 'pr-$prNumber';
      }
    }

    // Generate a slug if no name provided
    if (worktreeName == null) {
      const adjectives = ['swift', 'bright', 'calm', 'keen', 'bold'];
      const nouns = ['fox', 'owl', 'elm', 'oak', 'ray'];
      final rng = Random();
      final adj = adjectives[rng.nextInt(adjectives.length)];
      final noun = nouns[rng.nextInt(nouns.length)];
      final suffix = rng.nextInt(0xFFFF).toRadixString(36).padLeft(4, '0');
      worktreeName = '$adj-$noun-$suffix';
    }

    try {
      validateWorktreeSlug(worktreeName);
    } catch (e) {
      return (handled: false, error: 'Error: $e');
    }

    // Create or resume worktree
    final gitRoot = _findCanonicalGitRoot(_getCwd());
    if (gitRoot == null && !_hasWorktreeCreateHook()) {
      return (
        handled: false,
        error: 'Error: --worktree requires a git repository',
      );
    }

    String worktreeDir;
    String repoName;

    if (_hasWorktreeCreateHook() && onExecuteWorktreeCreateHook != null) {
      try {
        final hookResult = await onExecuteWorktreeCreateHook!(worktreeName);
        worktreeDir = hookResult.worktreePath;
      } catch (e) {
        return (handled: false, error: 'Error: $e');
      }
      repoName = (gitRoot ?? _getCwd()).split('/').last;
    } else {
      repoName = gitRoot!.split('/').last;
      worktreeDir = _worktreePathFor(gitRoot, worktreeName);

      try {
        final result = await _getOrCreateWorktree(
          gitRoot,
          worktreeName,
          options: prNumber != null
              ? WorktreeCreateOptions(prNumber: prNumber)
              : null,
        );
        if (result is WorktreeCreated) {
          await _performPostCreationSetup(gitRoot, worktreeDir);
        }
      } catch (e) {
        return (handled: false, error: 'Error: $e');
      }
    }

    // Build tmux session name
    final tmuxSessionNameFinal =
        '${repoName}_${worktreeBranchName(worktreeName)}'
            .replaceAll(RegExp(r'[/.]'), '_');

    // Build new args without --tmux and --worktree
    final newArgs = <String>[];
    for (int i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--tmux' || arg == '--tmux=classic') continue;
      if (arg == '-w' || arg == '--worktree') {
        if (i + 1 < args.length && !args[i + 1].startsWith('-')) i++;
        continue;
      }
      if (arg.startsWith('--worktree=')) continue;
      newArgs.add(arg);
    }

    // Create tmux session
    final tmuxArgs = [
      'new-session',
      '-A',
      '-s',
      tmuxSessionNameFinal,
      '-c',
      worktreeDir,
      '--',
      Platform.resolvedExecutable,
      ...newArgs,
    ];

    final tmuxResult = Process.runSync('tmux', tmuxArgs,
        workingDirectory: worktreeDir);

    return (handled: true, error: null);
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    super.onClose();
  }
}

// ---------------------------------------------------------------------------
// Default implementations for callbacks
// ---------------------------------------------------------------------------

String? _defaultFindGitRoot(String path) {
  var dir = Directory(path);
  while (true) {
    if (Directory('${dir.path}/.git').existsSync() ||
        File('${dir.path}/.git').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

String? _defaultFindCanonicalGitRoot(String path) {
  return _defaultFindGitRoot(path);
}
