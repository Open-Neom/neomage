// Port of neomage gitDiff.ts + git.ts + ghPrStatus.ts + detectRepository.ts
//
// Git operations, diff parsing, repository detection, and PR status utilities
// for the neomage package.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:crypto/crypto.dart' show sha256;
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Git diff aggregate statistics.
class GitDiffStats {
  const GitDiffStats({
    required this.filesCount,
    required this.linesAdded,
    required this.linesRemoved,
  });

  final int filesCount;
  final int linesAdded;
  final int linesRemoved;
}

/// Per-file diff statistics.
class PerFileStats {
  const PerFileStats({
    required this.added,
    required this.removed,
    required this.isBinary,
    this.isUntracked = false,
  });

  final int added;
  final int removed;
  final bool isBinary;
  final bool isUntracked;
}

/// A structured patch hunk.
class StructuredPatchHunk {
  StructuredPatchHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    List<String>? lines,
  }) : lines = lines ?? [];

  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final List<String> lines;
}

/// Result of a git diff operation.
class GitDiffResult {
  GitDiffResult({
    required this.stats,
    required this.perFileStats,
    required this.hunks,
  });

  final GitDiffStats stats;
  final Map<String, PerFileStats> perFileStats;
  final Map<String, List<StructuredPatchHunk>> hunks;
}

/// Result from parseGitNumstat.
class NumstatResult {
  const NumstatResult({required this.stats, required this.perFileStats});

  final GitDiffStats stats;
  final Map<String, PerFileStats> perFileStats;
}

/// Structured diff for a single file (tool use).
class ToolUseDiff {
  const ToolUseDiff({
    required this.filename,
    required this.status,
    required this.additions,
    required this.deletions,
    required this.changes,
    required this.patch,
    this.repository,
  });

  final String filename;
  final String status; // 'modified' | 'added'
  final int additions;
  final int deletions;
  final int changes;
  final String patch;
  final String? repository;
}

/// PR review state.
enum PrReviewState {
  approved,
  pending,
  changesRequested,
  draft,
  merged,
  closed,
}

/// Pull request status.
class PrStatus {
  const PrStatus({
    required this.number,
    required this.url,
    required this.reviewState,
  });

  final int number;
  final String url;
  final PrReviewState reviewState;
}

/// Parsed git remote.
class ParsedRepository {
  const ParsedRepository({
    required this.host,
    required this.owner,
    required this.name,
  });

  final String host;
  final String owner;
  final String name;
}

/// Git file status (tracked vs untracked).
class GitFileStatus {
  const GitFileStatus({required this.tracked, required this.untracked});

  final List<String> tracked;
  final List<String> untracked;
}

/// Git repository state snapshot.
class GitRepoState {
  const GitRepoState({
    required this.commitHash,
    required this.branchName,
    required this.remoteUrl,
    required this.isHeadOnRemote,
    required this.isClean,
    required this.worktreeCount,
  });

  final String commitHash;
  final String branchName;
  final String? remoteUrl;
  final bool isHeadOnRemote;
  final bool isClean;
  final int worktreeCount;
}

/// Preserved git state for issue submission.
class PreservedGitState {
  const PreservedGitState({
    required this.remoteBaseSha,
    required this.remoteBase,
    required this.patch,
    required this.untrackedFiles,
    required this.formatPatch,
    required this.headSha,
    required this.branchName,
  });

  final String? remoteBaseSha;
  final String? remoteBase;
  final String patch;
  final List<UntrackedFile> untrackedFiles;
  final String? formatPatch;
  final String? headSha;
  final String? branchName;
}

/// An untracked file with content.
class UntrackedFile {
  const UntrackedFile({required this.path, required this.content});
  final String path;
  final String content;
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _gitTimeoutMs = 5000;
const _maxFiles = 50;
const _maxDiffSizeBytes = 1000000; // 1 MB
const _maxLinesPerFile = 400;
const _maxFilesForDetails = 500;
const _singleFileDiffTimeoutMs = 3000;
const _ghTimeoutMs = 5000;
// ignore: unused_element
const _maxFileSizeBytes = 500 * 1024 * 1024; // 500 MB
// ignore: unused_element
const _maxTotalSizeBytes = 5 * 1024 * 1024 * 1024; // 5 GB
// ignore: unused_element
const _maxFileCount = 20000;

// ---------------------------------------------------------------------------
// git.ts  --  finding git root
// ---------------------------------------------------------------------------

/// Cache for git root lookups.
final _gitRootCache = <String, String?>{};

/// Find the git root by walking up the directory tree.
/// Looks for a .git directory or file (worktrees/submodules use a file).
String? findGitRoot(String startPath) {
  if (_gitRootCache.containsKey(startPath)) return _gitRootCache[startPath];

  var current = p.absolute(startPath);
  final root = p.rootPrefix(current);

  while (true) {
    try {
      final gitPath = p.join(current, '.git');
      final stat = FileStat.statSync(gitPath);
      if (stat.type == FileSystemEntityType.directory ||
          stat.type == FileSystemEntityType.file) {
        _gitRootCache[startPath] = current;
        return current;
      }
    } catch (_) {}

    final parent = p.dirname(current);
    if (parent == current || parent == root) {
      // Check root as well
      try {
        final gitPath = p.join(root, '.git');
        final stat = FileStat.statSync(gitPath);
        if (stat.type == FileSystemEntityType.directory ||
            stat.type == FileSystemEntityType.file) {
          _gitRootCache[startPath] = root;
          return root;
        }
      } catch (_) {}
      break;
    }
    current = parent;
  }

  _gitRootCache[startPath] = null;
  return null;
}

/// Resolve a git root to the canonical main repository root.
/// For worktrees follows .git file -> gitdir: -> commondir chain.
String resolveCanonicalGitRoot(String gitRoot) {
  try {
    final gitFile = File(p.join(gitRoot, '.git'));
    final gitContent = gitFile.readAsStringSync().trim();
    if (!gitContent.startsWith('gitdir:')) return gitRoot;

    final worktreeGitDir = p.normalize(
      p.join(gitRoot, gitContent.substring('gitdir:'.length).trim()),
    );

    final commondirFile = File(p.join(worktreeGitDir, 'commondir'));
    final commonDir = p.normalize(
      p.join(worktreeGitDir, commondirFile.readAsStringSync().trim()),
    );

    // Validate structure matches git worktree add
    if (p.normalize(p.dirname(worktreeGitDir)) !=
        p.join(commonDir, 'worktrees')) {
      return gitRoot;
    }

    // Validate back-link
    try {
      final backlink = File(
        p.join(worktreeGitDir, 'gitdir'),
      ).readAsStringSync().trim();
      final resolvedBacklink = File(backlink).resolveSymbolicLinksSync();
      final resolvedGitRoot = p.join(
        Directory(gitRoot).resolveSymbolicLinksSync(),
        '.git',
      );
      if (resolvedBacklink != resolvedGitRoot) return gitRoot;
    } catch (_) {
      return gitRoot;
    }

    // Bare-repo worktrees: common dir is not inside a working directory.
    if (p.basename(commonDir) != '.git') return commonDir;
    return p.dirname(commonDir);
  } catch (_) {
    return gitRoot;
  }
}

/// Find the canonical git root, resolving through worktrees.
String? findCanonicalGitRoot(String startPath) {
  final root = findGitRoot(startPath);
  if (root == null) return null;
  return resolveCanonicalGitRoot(root);
}

/// Memoized git executable path.
String? _gitExeCache;

String gitExe() {
  if (_gitExeCache != null) return _gitExeCache!;
  try {
    final result = Process.runSync('which', ['git']);
    final path = (result.stdout as String).trim();
    _gitExeCache = path.isNotEmpty ? path : 'git';
  } catch (_) {
    _gitExeCache = 'git';
  }
  return _gitExeCache!;
}

/// Run a git command and return (stdout, exitCode).
Future<_CmdResult> _runGit(
  List<String> args, {
  String? cwd,
  int timeoutMs = _gitTimeoutMs,
}) async {
  try {
    final result = await Process.run(
      gitExe(),
      args,
      workingDirectory: cwd,
    ).timeout(Duration(milliseconds: timeoutMs));
    return _CmdResult(stdout: result.stdout as String, code: result.exitCode);
  } catch (_) {
    return const _CmdResult(stdout: '', code: -1);
  }
}

class _CmdResult {
  const _CmdResult({required this.stdout, required this.code});
  final String stdout;
  final int code;
}

/// Check if cwd is inside a git repository.
Future<bool> getIsGit({String? cwd}) async {
  return findGitRoot(cwd ?? Directory.current.path) != null;
}

/// Resolve the .git directory (handles worktrees).
Future<String?> getGitDir(String cwd) async {
  final root = findGitRoot(cwd);
  if (root == null) return null;
  final gitPath = p.join(root, '.git');
  final stat = FileStat.statSync(gitPath);
  if (stat.type == FileSystemEntityType.directory) return gitPath;
  if (stat.type == FileSystemEntityType.file) {
    // Worktree - read gitdir
    try {
      final content = File(gitPath).readAsStringSync().trim();
      if (content.startsWith('gitdir:')) {
        return p.normalize(
          p.join(root, content.substring('gitdir:'.length).trim()),
        );
      }
    } catch (_) {}
  }
  return null;
}

/// Check if the cwd is at the git root.
Future<bool> isAtGitRoot({String? cwd}) async {
  final currentCwd = cwd ?? Directory.current.path;
  final gitRoot = findGitRoot(currentCwd);
  if (gitRoot == null) return false;
  try {
    final resolved = Directory(currentCwd).resolveSymbolicLinksSync();
    final resolvedRoot = Directory(gitRoot).resolveSymbolicLinksSync();
    return resolved == resolvedRoot;
  } catch (_) {
    return currentCwd == gitRoot;
  }
}

/// Check if directory is in a git repo.
Future<bool> dirIsInGitRepo(String cwd) async {
  return findGitRoot(cwd) != null;
}

/// Get HEAD commit hash.
Future<String> getHead({String? cwd}) async {
  final result = await _runGit(['rev-parse', 'HEAD'], cwd: cwd);
  return result.stdout.trim();
}

/// Get current branch name.
Future<String> getBranch({String? cwd}) async {
  final result = await _runGit(['rev-parse', '--abbrev-ref', 'HEAD'], cwd: cwd);
  return result.stdout.trim();
}

/// Get the default branch (main/master/etc).
Future<String> getDefaultBranch({String? cwd}) async {
  // Try symbolic-ref first
  final result = await _runGit([
    'symbolic-ref',
    'refs/remotes/origin/HEAD',
  ], cwd: cwd);
  if (result.code == 0 && result.stdout.trim().isNotEmpty) {
    return result.stdout.trim().replaceFirst('refs/remotes/origin/', '');
  }
  // Fallback: check common branch names
  for (final branch in ['main', 'master']) {
    final check = await _runGit([
      'rev-parse',
      '--verify',
      'origin/$branch',
    ], cwd: cwd);
    if (check.code == 0) return branch;
  }
  return 'main';
}

/// Get the remote URL.
Future<String?> getRemoteUrl({String? cwd}) async {
  final result = await _runGit([
    'config',
    '--get',
    'remote.origin.url',
  ], cwd: cwd);
  final url = result.stdout.trim();
  return url.isEmpty ? null : url;
}

/// Normalise a git remote URL to a canonical form for hashing.
/// Converts SSH and HTTPS URLs to: host/owner/repo (lowercase, no .git).
String? normalizeGitRemoteUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  // SSH format: git@host:owner/repo.git
  final sshMatch = RegExp(r'^git@([^:]+):(.+?)(?:\.git)?$').firstMatch(trimmed);
  if (sshMatch != null) {
    return '${sshMatch.group(1)}/${sshMatch.group(2)}'.toLowerCase();
  }

  // HTTPS/SSH URL format
  final urlMatch = RegExp(
    r'^(?:https?|ssh)://(?:[^@]+@)?([^/]+)/(.+?)(?:\.git)?$',
  ).firstMatch(trimmed);
  if (urlMatch != null) {
    final host = urlMatch.group(1)!;
    final path = urlMatch.group(2)!;

    if (_isLocalHost(host) && path.startsWith('git/')) {
      final proxyPath = path.substring(4);
      final segments = proxyPath.split('/');
      if (segments.length >= 3 && segments[0].contains('.')) {
        return proxyPath.toLowerCase();
      }
      return 'github.com/$proxyPath'.toLowerCase();
    }

    return '$host/$path'.toLowerCase();
  }

  return null;
}

bool _isLocalHost(String host) {
  final hostWithoutPort = host.split(':').first;
  return hostWithoutPort == 'localhost' ||
      RegExp(r'^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(hostWithoutPort);
}

/// Returns a SHA256 hash (first 16 chars) of the normalized git remote URL.
Future<String?> getRepoRemoteHash({String? cwd}) async {
  final remoteUrl = await getRemoteUrl(cwd: cwd);
  if (remoteUrl == null) return null;

  final normalized = normalizeGitRemoteUrl(remoteUrl);
  if (normalized == null) return null;

  final hash = sha256.convert(utf8.encode(normalized)).toString();
  return hash.substring(0, 16);
}

/// Check if HEAD is on a remote-tracking branch.
Future<bool> getIsHeadOnRemote({String? cwd}) async {
  final result = await _runGit(['rev-parse', '@{u}'], cwd: cwd);
  return result.code == 0;
}

/// Check if there are unpushed commits.
Future<bool> hasUnpushedCommits({String? cwd}) async {
  final result = await _runGit(['rev-list', '--count', '@{u}..HEAD'], cwd: cwd);
  return result.code == 0 && (int.tryParse(result.stdout.trim()) ?? 0) > 0;
}

/// Check if the working tree is clean.
Future<bool> getIsClean({String? cwd, bool ignoreUntracked = false}) async {
  final args = ['--no-optional-locks', 'status', '--porcelain'];
  if (ignoreUntracked) args.add('-uno');
  final result = await _runGit(args, cwd: cwd);
  return result.stdout.trim().isEmpty;
}

/// Get a list of changed files (porcelain output).
Future<List<String>> getChangedFiles({String? cwd}) async {
  final result = await _runGit([
    '--no-optional-locks',
    'status',
    '--porcelain',
  ], cwd: cwd);
  return result.stdout.trim().split('\n').where((line) => line.isNotEmpty).map((
    line,
  ) {
    final trimmed = line.trim();
    final spaceIdx = trimmed.indexOf(' ');
    return spaceIdx >= 0 ? trimmed.substring(spaceIdx + 1).trim() : trimmed;
  }).toList();
}

/// Get file status (tracked vs untracked).
Future<GitFileStatus> getFileStatus({String? cwd}) async {
  final result = await _runGit([
    '--no-optional-locks',
    'status',
    '--porcelain',
  ], cwd: cwd);

  final tracked = <String>[];
  final untracked = <String>[];

  for (final line in result.stdout.trim().split('\n')) {
    if (line.isEmpty) continue;
    final status = line.substring(0, 2);
    final filename = line.substring(2).trim();
    if (status == '??') {
      untracked.add(filename);
    } else if (filename.isNotEmpty) {
      tracked.add(filename);
    }
  }

  return GitFileStatus(tracked: tracked, untracked: untracked);
}

/// Stash all changes (including untracked) to return git to a clean state.
Future<bool> stashToCleanState({String? cwd, String? message}) async {
  try {
    final stashMessage =
        message ?? 'Neomage auto-stash - ${DateTime.now().toIso8601String()}';

    final fileStatus = await getFileStatus(cwd: cwd);
    if (fileStatus.untracked.isNotEmpty) {
      final addResult = await _runGit([
        'add',
        ...fileStatus.untracked,
      ], cwd: cwd);
      if (addResult.code != 0) return false;
    }

    final result = await _runGit([
      'stash',
      'push',
      '--message',
      stashMessage,
    ], cwd: cwd);
    return result.code == 0;
  } catch (_) {
    return false;
  }
}

/// Get the full git repository state.
Future<GitRepoState?> getGitState({String? cwd}) async {
  try {
    final results = await Future.wait([
      getHead(cwd: cwd),
      getBranch(cwd: cwd),
      getRemoteUrl(cwd: cwd),
      getIsHeadOnRemote(cwd: cwd),
      getIsClean(cwd: cwd),
    ]);

    return GitRepoState(
      commitHash: results[0] as String,
      branchName: results[1] as String,
      remoteUrl: results[2] as String?,
      isHeadOnRemote: results[3] as bool,
      isClean: results[4] as bool,
      worktreeCount: 1, // Simplified
    );
  } catch (_) {
    return null;
  }
}

/// Get the GitHub repo in "owner/repo" format.
Future<String?> getGithubRepo({String? cwd}) async {
  final remoteUrl = await getRemoteUrl(cwd: cwd);
  if (remoteUrl == null) return null;
  final parsed = parseGitRemote(remoteUrl);
  if (parsed != null && parsed.host == 'github.com') {
    return '${parsed.owner}/${parsed.name}';
  }
  return null;
}

/// Find the best remote branch to use as a base.
Future<String?> findRemoteBase({String? cwd}) async {
  // Try tracking branch
  final tracking = await _runGit([
    'rev-parse',
    '--abbrev-ref',
    '--symbolic-full-name',
    '@{u}',
  ], cwd: cwd);
  if (tracking.code == 0 && tracking.stdout.trim().isNotEmpty) {
    return tracking.stdout.trim();
  }

  // Try remote show
  final remoteRefs = await _runGit([
    'remote',
    'show',
    'origin',
    '--',
    'HEAD',
  ], cwd: cwd);
  if (remoteRefs.code == 0) {
    final match = RegExp(r'HEAD branch: (\S+)').firstMatch(remoteRefs.stdout);
    if (match != null) return 'origin/${match.group(1)}';
  }

  // Check common branches
  for (final candidate in ['origin/main', 'origin/staging', 'origin/master']) {
    final check = await _runGit(['rev-parse', '--verify', candidate], cwd: cwd);
    if (check.code == 0) return candidate;
  }

  return null;
}

/// Check if in a shallow clone.
Future<bool> isShallowClone({String? cwd}) async {
  final gitDir = await getGitDir(cwd ?? Directory.current.path);
  if (gitDir == null) return false;
  return File(p.join(gitDir, 'shallow')).existsSync();
}

/// Check if cwd looks like a bare git repo (security check).
bool isCurrentDirectoryBareGitRepo({String? cwd}) {
  final currentCwd = cwd ?? Directory.current.path;
  final gitPath = p.join(currentCwd, '.git');

  try {
    final stat = FileStat.statSync(gitPath);
    if (stat.type == FileSystemEntityType.file) return false;
    if (stat.type == FileSystemEntityType.directory) {
      try {
        final headStat = FileStat.statSync(p.join(gitPath, 'HEAD'));
        if (headStat.type == FileSystemEntityType.file) return false;
      } catch (_) {}
    }
  } catch (_) {}

  // Check bare repo indicators
  for (final item in [
    [p.join(currentCwd, 'HEAD'), FileSystemEntityType.file],
    [p.join(currentCwd, 'objects'), FileSystemEntityType.directory],
    [p.join(currentCwd, 'refs'), FileSystemEntityType.directory],
  ]) {
    try {
      final stat = FileStat.statSync(item[0] as String);
      if (stat.type == item[1]) return true;
    } catch (_) {}
  }

  return false;
}

// ---------------------------------------------------------------------------
// gitDiff.ts  --  diff parsing
// ---------------------------------------------------------------------------

/// Fetch git diff stats comparing working tree to HEAD.
/// Returns null if not in a git repo or during transient git states.
Future<GitDiffResult?> fetchGitDiff({String? cwd}) async {
  if (!await getIsGit(cwd: cwd)) return null;

  if (await _isInTransientGitState(cwd: cwd)) return null;

  // Quick probe with --shortstat
  final shortstat = await _runGit([
    '--no-optional-locks',
    'diff',
    'HEAD',
    '--shortstat',
  ], cwd: cwd);
  if (shortstat.code == 0) {
    final quickStats = parseShortstat(shortstat.stdout);
    if (quickStats != null && quickStats.filesCount > _maxFilesForDetails) {
      return GitDiffResult(stats: quickStats, perFileStats: {}, hunks: {});
    }
  }

  // Get stats via --numstat
  final numstat = await _runGit([
    '--no-optional-locks',
    'diff',
    'HEAD',
    '--numstat',
  ], cwd: cwd);
  if (numstat.code != 0) return null;

  final result = parseGitNumstat(numstat.stdout);
  final stats = GitDiffStats(
    filesCount: result.stats.filesCount,
    linesAdded: result.stats.linesAdded,
    linesRemoved: result.stats.linesRemoved,
  );
  final perFileStats = Map<String, PerFileStats>.from(result.perFileStats);

  // Include untracked files
  final remainingSlots = _maxFiles - perFileStats.length;
  if (remainingSlots > 0) {
    final untrackedStats = await _fetchUntrackedFiles(remainingSlots, cwd: cwd);
    if (untrackedStats != null) {
      perFileStats.addAll(untrackedStats);
    }
  }

  return GitDiffResult(
    stats: GitDiffStats(
      filesCount:
          stats.filesCount + (perFileStats.length - result.perFileStats.length),
      linesAdded: stats.linesAdded,
      linesRemoved: stats.linesRemoved,
    ),
    perFileStats: perFileStats,
    hunks: {},
  );
}

/// Fetch git diff hunks on-demand.
Future<Map<String, List<StructuredPatchHunk>>> fetchGitDiffHunks({
  String? cwd,
}) async {
  if (!await getIsGit(cwd: cwd)) return {};
  if (await _isInTransientGitState(cwd: cwd)) return {};

  final result = await _runGit([
    '--no-optional-locks',
    'diff',
    'HEAD',
  ], cwd: cwd);
  if (result.code != 0) return {};

  return parseGitDiff(result.stdout);
}

/// Parse git diff --numstat output.
NumstatResult parseGitNumstat(String stdout) {
  final lines = stdout.trim().split('\n').where((l) => l.isNotEmpty);
  var added = 0;
  var removed = 0;
  var validFileCount = 0;
  final perFileStats = <String, PerFileStats>{};

  for (final line in lines) {
    final parts = line.split('\t');
    if (parts.length < 3) continue;

    validFileCount++;
    final addStr = parts[0];
    final remStr = parts[1];
    final filePath = parts.sublist(2).join('\t');
    final isBinary = addStr == '-' || remStr == '-';
    final fileAdded = isBinary ? 0 : (int.tryParse(addStr) ?? 0);
    final fileRemoved = isBinary ? 0 : (int.tryParse(remStr) ?? 0);

    added += fileAdded;
    removed += fileRemoved;

    if (perFileStats.length < _maxFiles) {
      perFileStats[filePath] = PerFileStats(
        added: fileAdded,
        removed: fileRemoved,
        isBinary: isBinary,
      );
    }
  }

  return NumstatResult(
    stats: GitDiffStats(
      filesCount: validFileCount,
      linesAdded: added,
      linesRemoved: removed,
    ),
    perFileStats: perFileStats,
  );
}

/// Parse unified diff output into per-file hunks.
Map<String, List<StructuredPatchHunk>> parseGitDiff(String stdout) {
  final result = <String, List<StructuredPatchHunk>>{};
  if (stdout.trim().isEmpty) return result;

  final fileDiffs = stdout
      .split(RegExp(r'^diff --git ', multiLine: true))
      .where((s) => s.isNotEmpty)
      .toList();

  for (final fileDiff in fileDiffs) {
    if (result.length >= _maxFiles) break;
    if (fileDiff.length > _maxDiffSizeBytes) continue;

    final lines = fileDiff.split('\n');
    final headerMatch = RegExp(r'^a/(.+?) b/(.+)$').firstMatch(lines.first);
    if (headerMatch == null) continue;
    final filePath = headerMatch.group(2) ?? headerMatch.group(1) ?? '';

    final fileHunks = <StructuredPatchHunk>[];
    StructuredPatchHunk? currentHunk;
    var lineCount = 0;

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];

      final hunkMatch = RegExp(
        r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@',
      ).firstMatch(line);
      if (hunkMatch != null) {
        if (currentHunk != null) fileHunks.add(currentHunk);
        currentHunk = StructuredPatchHunk(
          oldStart: int.parse(hunkMatch.group(1) ?? '0'),
          oldLines: int.parse(hunkMatch.group(2) ?? '1'),
          newStart: int.parse(hunkMatch.group(3) ?? '0'),
          newLines: int.parse(hunkMatch.group(4) ?? '1'),
        );
        continue;
      }

      // Skip metadata lines
      if (line.startsWith('index ') ||
          line.startsWith('---') ||
          line.startsWith('+++') ||
          line.startsWith('new file') ||
          line.startsWith('deleted file') ||
          line.startsWith('old mode') ||
          line.startsWith('new mode') ||
          line.startsWith('Binary files')) {
        continue;
      }

      if (currentHunk != null &&
          (line.startsWith('+') ||
              line.startsWith('-') ||
              line.startsWith(' ') ||
              line.isEmpty)) {
        if (lineCount >= _maxLinesPerFile) continue;
        currentHunk.lines.add(line);
        lineCount++;
      }
    }

    if (currentHunk != null) fileHunks.add(currentHunk);
    if (fileHunks.isNotEmpty) result[filePath] = fileHunks;
  }

  return result;
}

/// Parse git diff --shortstat output.
GitDiffStats? parseShortstat(String stdout) {
  final match = RegExp(
    r'(\d+)\s+files?\s+changed(?:,\s+(\d+)\s+insertions?\(\+\))?(?:,\s+(\d+)\s+deletions?\(-\))?',
  ).firstMatch(stdout);
  if (match == null) return null;
  return GitDiffStats(
    filesCount: int.parse(match.group(1) ?? '0'),
    linesAdded: int.parse(match.group(2) ?? '0'),
    linesRemoved: int.parse(match.group(3) ?? '0'),
  );
}

/// Fetch a structured diff for a single file against the merge base.
Future<ToolUseDiff?> fetchSingleFileGitDiff(String absoluteFilePath) async {
  final gitRoot = findGitRoot(p.dirname(absoluteFilePath));
  if (gitRoot == null) return null;

  final gitPath = p
      .relative(absoluteFilePath, from: gitRoot)
      .replaceAll(p.separator, '/');
  final repository = getCachedRepository();

  // Check if tracked
  final lsFiles = await _runGit(
    ['--no-optional-locks', 'ls-files', '--error-unmatch', gitPath],
    cwd: gitRoot,
    timeoutMs: _singleFileDiffTimeoutMs,
  );

  if (lsFiles.code == 0) {
    final diffRef = await _getDiffRef(gitRoot);
    final diff = await _runGit(
      ['--no-optional-locks', 'diff', diffRef, '--', gitPath],
      cwd: gitRoot,
      timeoutMs: _singleFileDiffTimeoutMs,
    );
    if (diff.code != 0 || diff.stdout.isEmpty) return null;
    final parsed = _parseRawDiffToToolUseDiff(gitPath, diff.stdout, 'modified');
    return ToolUseDiff(
      filename: parsed.filename,
      status: parsed.status,
      additions: parsed.additions,
      deletions: parsed.deletions,
      changes: parsed.changes,
      patch: parsed.patch,
      repository: repository,
    );
  }

  // Untracked - synthetic diff
  final synthetic = await _generateSyntheticDiff(gitPath, absoluteFilePath);
  if (synthetic == null) return null;
  return ToolUseDiff(
    filename: synthetic.filename,
    status: synthetic.status,
    additions: synthetic.additions,
    deletions: synthetic.deletions,
    changes: synthetic.changes,
    patch: synthetic.patch,
    repository: repository,
  );
}

ToolUseDiff _parseRawDiffToToolUseDiff(
  String filename,
  String rawDiff,
  String status,
) {
  final lines = rawDiff.split('\n');
  final patchLines = <String>[];
  var inHunks = false;
  var additions = 0;
  var deletions = 0;

  for (final line in lines) {
    if (line.startsWith('@@')) inHunks = true;
    if (inHunks) {
      patchLines.add(line);
      if (line.startsWith('+') && !line.startsWith('+++')) additions++;
      if (line.startsWith('-') && !line.startsWith('---')) deletions++;
    }
  }

  return ToolUseDiff(
    filename: filename,
    status: status,
    additions: additions,
    deletions: deletions,
    changes: additions + deletions,
    patch: patchLines.join('\n'),
  );
}

Future<String> _getDiffRef(String gitRoot) async {
  final baseBranch =
      Platform.environment['MAGE_BASE_REF'] ??
      await getDefaultBranch(cwd: gitRoot);
  final result = await _runGit(
    ['--no-optional-locks', 'merge-base', 'HEAD', baseBranch],
    cwd: gitRoot,
    timeoutMs: _singleFileDiffTimeoutMs,
  );
  if (result.code == 0 && result.stdout.trim().isNotEmpty) {
    return result.stdout.trim();
  }
  return 'HEAD';
}

Future<ToolUseDiff?> _generateSyntheticDiff(
  String gitPath,
  String absoluteFilePath,
) async {
  try {
    final file = File(absoluteFilePath);
    final stat = file.statSync();
    if (stat.size > _maxDiffSizeBytes) return null;

    final content = file.readAsStringSync();
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final lineCount = lines.length;
    final addedLines = lines.map((l) => '+$l').join('\n');
    final patch = '@@ -0,0 +1,$lineCount @@\n$addedLines';

    return ToolUseDiff(
      filename: gitPath,
      status: 'added',
      additions: lineCount,
      deletions: 0,
      changes: lineCount,
      patch: patch,
    );
  } catch (_) {
    return null;
  }
}

Future<bool> _isInTransientGitState({String? cwd}) async {
  final gitDir = await getGitDir(cwd ?? Directory.current.path);
  if (gitDir == null) return false;

  for (final file in [
    'MERGE_HEAD',
    'REBASE_HEAD',
    'CHERRY_PICK_HEAD',
    'REVERT_HEAD',
  ]) {
    if (File(p.join(gitDir, file)).existsSync()) return true;
  }
  return false;
}

Future<Map<String, PerFileStats>?> _fetchUntrackedFiles(
  int maxFiles, {
  String? cwd,
}) async {
  final result = await _runGit([
    '--no-optional-locks',
    'ls-files',
    '--others',
    '--exclude-standard',
  ], cwd: cwd);
  if (result.code != 0 || result.stdout.trim().isEmpty) return null;

  final paths = result.stdout
      .trim()
      .split('\n')
      .where((l) => l.isNotEmpty)
      .toList();
  if (paths.isEmpty) return null;

  final perFileStats = <String, PerFileStats>{};
  for (final filePath in paths.take(maxFiles)) {
    perFileStats[filePath] = const PerFileStats(
      added: 0,
      removed: 0,
      isBinary: false,
      isUntracked: true,
    );
  }
  return perFileStats;
}

// ---------------------------------------------------------------------------
// ghPrStatus.ts  --  Pull Request status
// ---------------------------------------------------------------------------

/// Derive review state from GitHub API values.
PrReviewState deriveReviewState({
  required bool isDraft,
  required String reviewDecision,
}) {
  if (isDraft) return PrReviewState.draft;
  switch (reviewDecision) {
    case 'APPROVED':
      return PrReviewState.approved;
    case 'CHANGES_REQUESTED':
      return PrReviewState.changesRequested;
    default:
      return PrReviewState.pending;
  }
}

/// Fetch PR status for the current branch using `gh pr view`.
Future<PrStatus?> fetchPrStatus({String? cwd}) async {
  if (!await getIsGit(cwd: cwd)) return null;

  final branch = await getBranch(cwd: cwd);
  final defaultBranch = await getDefaultBranch(cwd: cwd);
  if (branch == defaultBranch) return null;

  try {
    final result = await Process.run(
      'gh',
      [
        'pr',
        'view',
        '--json',
        'number,url,reviewDecision,isDraft,headRefName,state',
      ],
      workingDirectory: cwd,
    ).timeout(const Duration(milliseconds: _ghTimeoutMs));

    if (result.exitCode != 0) return null;
    final stdout = (result.stdout as String).trim();
    if (stdout.isEmpty) return null;

    final data = json.decode(stdout) as Map<String, dynamic>;
    final headRefName = data['headRefName'] as String? ?? '';
    final state = data['state'] as String? ?? '';

    if (headRefName == defaultBranch ||
        headRefName == 'main' ||
        headRefName == 'master') {
      return null;
    }

    if (state == 'MERGED' || state == 'CLOSED') return null;

    return PrStatus(
      number: data['number'] as int,
      url: data['url'] as String,
      reviewState: deriveReviewState(
        isDraft: data['isDraft'] as bool? ?? false,
        reviewDecision: data['reviewDecision'] as String? ?? '',
      ),
    );
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// detectRepository.ts
// ---------------------------------------------------------------------------

final _repositoryCache = <String, ParsedRepository?>{};

/// Clear cached repository data.
void clearRepositoryCaches() {
  _repositoryCache.clear();
}

/// Detect the current repository (github.com only, "owner/repo").
Future<String?> detectCurrentRepository({String? cwd}) async {
  final result = await detectCurrentRepositoryWithHost(cwd: cwd);
  if (result == null || result.host != 'github.com') return null;
  return '${result.owner}/${result.name}';
}

/// Detect current repository including host.
Future<ParsedRepository?> detectCurrentRepositoryWithHost({String? cwd}) async {
  final currentCwd = cwd ?? Directory.current.path;

  if (_repositoryCache.containsKey(currentCwd)) {
    return _repositoryCache[currentCwd];
  }

  try {
    final remoteUrl = await getRemoteUrl(cwd: cwd);
    if (remoteUrl == null) {
      _repositoryCache[currentCwd] = null;
      return null;
    }

    final parsed = parseGitRemote(remoteUrl);
    _repositoryCache[currentCwd] = parsed;
    return parsed;
  } catch (_) {
    _repositoryCache[currentCwd] = null;
    return null;
  }
}

/// Return cached repository ("owner/name") for github.com, or null.
String? getCachedRepository({String? cwd}) {
  final currentCwd = cwd ?? Directory.current.path;
  final parsed = _repositoryCache[currentCwd];
  if (parsed == null || parsed.host != 'github.com') return null;
  return '${parsed.owner}/${parsed.name}';
}

/// Parse a git remote URL into host, owner, and name.
ParsedRepository? parseGitRemote(String input) {
  final trimmed = input.trim();

  // SSH format: git@host:owner/repo.git
  final sshMatch = RegExp(
    r'^git@([^:]+):([^/]+)/([^/]+?)(?:\.git)?$',
  ).firstMatch(trimmed);
  if (sshMatch != null) {
    final host = sshMatch.group(1)!;
    if (!_looksLikeRealHostname(host)) return null;
    return ParsedRepository(
      host: host,
      owner: sshMatch.group(2)!,
      name: sshMatch.group(3)!,
    );
  }

  // URL format
  final urlMatch = RegExp(
    r'^(https?|ssh|git)://(?:[^@]+@)?([^/:]+(?::\d+)?)/([^/]+)/([^/]+?)(?:\.git)?$',
  ).firstMatch(trimmed);
  if (urlMatch != null) {
    final protocol = urlMatch.group(1)!;
    final hostWithPort = urlMatch.group(2)!;
    final hostWithoutPort = hostWithPort.split(':').first;
    if (!_looksLikeRealHostname(hostWithoutPort)) return null;
    final host = (protocol == 'https' || protocol == 'http')
        ? hostWithPort
        : hostWithoutPort;
    return ParsedRepository(
      host: host,
      owner: urlMatch.group(3)!,
      name: urlMatch.group(4)!,
    );
  }

  return null;
}

/// Parse a GitHub repository string or URL.
String? parseGitHubRepository(String input) {
  final trimmed = input.trim();

  final parsed = parseGitRemote(trimmed);
  if (parsed != null) {
    if (parsed.host != 'github.com') return null;
    return '${parsed.owner}/${parsed.name}';
  }

  // Check "owner/repo" format
  if (!trimmed.contains('://') &&
      !trimmed.contains('@') &&
      trimmed.contains('/')) {
    final parts = trimmed.split('/');
    if (parts.length == 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      final repo = parts[1].replaceAll(RegExp(r'\.git$'), '');
      return '${parts[0]}/$repo';
    }
  }

  return null;
}

bool _looksLikeRealHostname(String host) {
  if (!host.contains('.')) return false;
  final lastSegment = host.split('.').last;
  return RegExp(r'^[a-zA-Z]+$').hasMatch(lastSegment);
}

/// Preserve git state for issue submission.
Future<PreservedGitState?> preserveGitStateForIssue({String? cwd}) async {
  try {
    if (!await getIsGit(cwd: cwd)) return null;

    if (await isShallowClone(cwd: cwd)) {
      final patch = await _runGit(['diff', 'HEAD'], cwd: cwd);
      return PreservedGitState(
        remoteBaseSha: null,
        remoteBase: null,
        patch: patch.stdout,
        untrackedFiles: [],
        formatPatch: null,
        headSha: null,
        branchName: null,
      );
    }

    final remoteBase = await findRemoteBase(cwd: cwd);
    if (remoteBase == null) {
      final patch = await _runGit(['diff', 'HEAD'], cwd: cwd);
      return PreservedGitState(
        remoteBaseSha: null,
        remoteBase: null,
        patch: patch.stdout,
        untrackedFiles: [],
        formatPatch: null,
        headSha: null,
        branchName: null,
      );
    }

    final mergeBase = await _runGit([
      'merge-base',
      'HEAD',
      remoteBase,
    ], cwd: cwd);
    if (mergeBase.code != 0 || mergeBase.stdout.trim().isEmpty) {
      final patch = await _runGit(['diff', 'HEAD'], cwd: cwd);
      return PreservedGitState(
        remoteBaseSha: null,
        remoteBase: null,
        patch: patch.stdout,
        untrackedFiles: [],
        formatPatch: null,
        headSha: null,
        branchName: null,
      );
    }

    final remoteBaseSha = mergeBase.stdout.trim();
    final results = await Future.wait([
      _runGit(['diff', remoteBaseSha], cwd: cwd),
      _runGit(['format-patch', '$remoteBaseSha..HEAD', '--stdout'], cwd: cwd),
      _runGit(['rev-parse', 'HEAD'], cwd: cwd),
      _runGit(['rev-parse', '--abbrev-ref', 'HEAD'], cwd: cwd),
    ]);

    final patchResult = results[0];
    final formatPatchResult = results[1];
    final headShaResult = results[2];
    final branchResult = results[3];

    String? formatPatch;
    if (formatPatchResult.code == 0 &&
        formatPatchResult.stdout.trim().isNotEmpty) {
      formatPatch = formatPatchResult.stdout;
    }

    final trimmedBranch = branchResult.stdout.trim();
    return PreservedGitState(
      remoteBaseSha: remoteBaseSha,
      remoteBase: remoteBase,
      patch: patchResult.stdout,
      untrackedFiles: [],
      formatPatch: formatPatch,
      headSha: headShaResult.stdout.trim().isEmpty
          ? null
          : headShaResult.stdout.trim(),
      branchName: trimmedBranch.isEmpty || trimmedBranch == 'HEAD'
          ? null
          : trimmedBranch,
    );
  } catch (_) {
    return null;
  }
}
