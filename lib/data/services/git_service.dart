// Git service — port of neom_claw git integration.
// Full git operations: status, log, diff, blame, branches, stash, remotes, etc.
// Wraps the git CLI with typed Dart models.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Overall repository status.
enum GitStatus { clean, dirty, merging, rebasing, cherryPicking }

/// Status of an individual file in the working tree or index.
enum GitFileStatus {
  modified,
  added,
  deleted,
  renamed,
  copied,
  untracked,
  ignored,
}

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// A single file change reported by `git status`.
class GitFileChange {
  final String path;
  final String? oldPath;
  final GitFileStatus status;
  final bool staged;

  const GitFileChange({
    required this.path,
    this.oldPath,
    required this.status,
    required this.staged,
  });

  @override
  String toString() =>
      'GitFileChange(path: $path, status: $status, staged: $staged'
      '${oldPath != null ? ', oldPath: $oldPath' : ''})';
}

/// A commit object.
class GitCommit {
  final String hash;
  final String shortHash;
  final String author;
  final String email;
  final DateTime date;
  final String message;
  final List<String> parents;

  const GitCommit({
    required this.hash,
    required this.shortHash,
    required this.author,
    required this.email,
    required this.date,
    required this.message,
    this.parents = const [],
  });

  @override
  String toString() => 'GitCommit($shortHash "$message")';
}

/// A local or remote branch.
class GitBranch {
  final String name;
  final bool isRemote;
  final bool isCurrent;
  final String? upstream;
  final int ahead;
  final int behind;

  const GitBranch({
    required this.name,
    this.isRemote = false,
    this.isCurrent = false,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
  });

  @override
  String toString() => 'GitBranch($name${isCurrent ? ' *' : ''})';
}

/// A stash entry.
class GitStash {
  final int index;
  final String message;
  final String? branch;
  final DateTime? date;

  const GitStash({
    required this.index,
    required this.message,
    this.branch,
    this.date,
  });

  @override
  String toString() => 'GitStash($index: $message)';
}

/// A single blame line.
class BlameLine {
  final String commit;
  final String author;
  final DateTime date;
  final int lineNumber;
  final String content;

  const BlameLine({
    required this.commit,
    required this.author,
    required this.date,
    required this.lineNumber,
    required this.content,
  });
}

/// Result of a `git blame`.
class GitBlame {
  final String path;
  final List<BlameLine> lines;

  const GitBlame({required this.path, required this.lines});

  @override
  String toString() => 'GitBlame($path, ${lines.length} lines)';
}

/// A configured remote.
class GitRemote {
  final String name;
  final String fetchUrl;
  final String pushUrl;

  const GitRemote({
    required this.name,
    required this.fetchUrl,
    required this.pushUrl,
  });

  @override
  String toString() => 'GitRemote($name $fetchUrl)';
}

/// Per-author commit statistics from `git shortlog`.
class AuthorStats {
  final String name;
  final String email;
  final int commitCount;

  const AuthorStats({
    required this.name,
    required this.email,
    required this.commitCount,
  });

  @override
  String toString() => 'AuthorStats($name <$email> $commitCount commits)';
}

/// Result bundle from [GitService.status].
class GitStatusResult {
  final GitStatus repoStatus;
  final String? branch;
  final String? upstream;
  final int ahead;
  final int behind;
  final List<GitFileChange> changes;
  final int stashCount;

  const GitStatusResult({
    required this.repoStatus,
    this.branch,
    this.upstream,
    this.ahead = 0,
    this.behind = 0,
    this.changes = const [],
    this.stashCount = 0,
  });

  bool get isClean => changes.isEmpty;

  @override
  String toString() =>
      'GitStatusResult(branch: $branch, status: $repoStatus, '
      '${changes.length} changes)';
}

// ---------------------------------------------------------------------------
// Exceptions
// ---------------------------------------------------------------------------

/// Exception thrown when a git command fails.
class GitException implements Exception {
  final String command;
  final int exitCode;
  final String stderr;

  const GitException({
    required this.command,
    required this.exitCode,
    required this.stderr,
  });

  @override
  String toString() =>
      'GitException(git $command exited $exitCode): $stderr';
}

// ---------------------------------------------------------------------------
// GitService
// ---------------------------------------------------------------------------

/// Service that wraps the git CLI with typed Dart models.
///
/// All methods that modify state accept an optional [workDir] parameter.
/// If not provided the service falls back to the [defaultWorkDir] given at
/// construction time (or the current directory).
class GitService {
  final String? defaultWorkDir;
  final String _gitBinary;

  GitService({this.defaultWorkDir, String gitBinary = 'git'})
      : _gitBinary = gitBinary;

  // -------------------------------------------------------------------------
  // Status
  // -------------------------------------------------------------------------

  /// Returns the current repository status including branch tracking info,
  /// file changes, and stash count.
  Future<GitStatusResult> status({String? path}) async {
    final workDir = path ?? defaultWorkDir;

    // Porcelain v2 gives machine-readable output.
    final result = await _runGit(
      ['status', '--porcelain=v2', '--branch', '--untracked-files=normal'],
      workDir: workDir,
    );

    String? branch;
    String? upstream;
    int ahead = 0;
    int behind = 0;
    final changes = <GitFileChange>[];

    for (final line in LineSplitter.split(result.stdout as String)) {
      if (line.startsWith('# branch.head ')) {
        branch = line.substring('# branch.head '.length);
      } else if (line.startsWith('# branch.upstream ')) {
        upstream = line.substring('# branch.upstream '.length);
      } else if (line.startsWith('# branch.ab ')) {
        final parts = line.substring('# branch.ab '.length).split(' ');
        if (parts.length >= 2) {
          ahead = int.tryParse(parts[0].replaceFirst('+', '')) ?? 0;
          behind = int.tryParse(parts[1].replaceFirst('-', '')) ?? 0;
        }
      } else if (line.startsWith('1 ') || line.startsWith('2 ')) {
        changes.add(_parseStatusLine(line));
      } else if (line.startsWith('? ')) {
        final filePath = line.substring(2);
        changes.add(GitFileChange(
          path: filePath,
          status: GitFileStatus.untracked,
          staged: false,
        ));
      }
    }

    // Detect special repo states.
    final repoStatus = await _detectRepoStatus(workDir);

    // Stash count.
    int stashCount = 0;
    try {
      final stashResult = await _runGit(['stash', 'list'], workDir: workDir);
      final stashOutput = (stashResult.stdout as String).trim();
      if (stashOutput.isNotEmpty) {
        stashCount = LineSplitter.split(stashOutput).length;
      }
    } catch (_) {
      // Stash list may fail in bare repos.
    }

    return GitStatusResult(
      repoStatus: repoStatus,
      branch: branch,
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      changes: changes,
      stashCount: stashCount,
    );
  }

  // -------------------------------------------------------------------------
  // Log
  // -------------------------------------------------------------------------

  /// Returns commit log entries.
  Future<List<GitCommit>> log({
    int? maxCount,
    String? since,
    String? until,
    String? author,
    String? path,
    bool oneline = false,
    String? workDir,
  }) async {
    final args = <String>[
      'log',
      '--format=%H%n%h%n%an%n%ae%n%aI%n%P%n%s%n---END---',
    ];

    if (maxCount != null) args.add('--max-count=$maxCount');
    if (since != null) args.add('--since=$since');
    if (until != null) args.add('--until=$until');
    if (author != null) args.add('--author=$author');
    if (path != null) {
      args.add('--');
      args.add(path);
    }

    final result = await _runGit(args, workDir: workDir ?? defaultWorkDir);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];

    final commits = <GitCommit>[];
    final blocks = output.split('---END---');

    for (final block in blocks) {
      final lines = LineSplitter.split(block.trim()).toList();
      if (lines.length < 6) continue;

      commits.add(GitCommit(
        hash: lines[0],
        shortHash: lines[1],
        author: lines[2],
        email: lines[3],
        date: DateTime.tryParse(lines[4]) ?? DateTime.now(),
        parents: lines[5].isNotEmpty ? lines[5].split(' ') : [],
        message: lines.length > 6 ? lines.sublist(6).join('\n') : '',
      ));
    }

    return commits;
  }

  // -------------------------------------------------------------------------
  // Diff
  // -------------------------------------------------------------------------

  /// Returns the diff output as a raw string.
  Future<String> diff({
    bool staged = false,
    String? path,
    String? commit1,
    String? commit2,
    String? workDir,
  }) async {
    final args = <String>['diff'];

    if (staged) args.add('--cached');
    if (commit1 != null) args.add(commit1);
    if (commit2 != null) args.add(commit2);
    if (path != null) {
      args.add('--');
      args.add(path);
    }

    final result = await _runGit(args, workDir: workDir ?? defaultWorkDir);
    return (result.stdout as String);
  }

  // -------------------------------------------------------------------------
  // Blame
  // -------------------------------------------------------------------------

  /// Returns per-line blame information for a file.
  Future<GitBlame> blame(String filePath, {String? rev, String? workDir}) async {
    final args = <String>['blame', '--porcelain'];
    if (rev != null) args.add(rev);
    args.add(filePath);

    final result = await _runGit(args, workDir: workDir ?? defaultWorkDir);
    final output = (result.stdout as String);
    final blameLines = <BlameLine>[];

    String? currentCommit;
    String? currentAuthor;
    DateTime? currentDate;
    int? currentLine;

    for (final line in LineSplitter.split(output)) {
      // Commit header: 40-char hash followed by line info.
      final commitMatch = RegExp(r'^([0-9a-f]{40})\s+\d+\s+(\d+)').firstMatch(line);
      if (commitMatch != null) {
        currentCommit = commitMatch.group(1);
        currentLine = int.tryParse(commitMatch.group(2)!);
        continue;
      }

      if (line.startsWith('author ')) {
        currentAuthor = line.substring('author '.length);
      } else if (line.startsWith('author-time ')) {
        final epoch = int.tryParse(line.substring('author-time '.length));
        if (epoch != null) {
          currentDate = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
        }
      } else if (line.startsWith('\t')) {
        // Content line.
        if (currentCommit != null && currentLine != null) {
          blameLines.add(BlameLine(
            commit: currentCommit,
            author: currentAuthor ?? 'Unknown',
            date: currentDate ?? DateTime.now(),
            lineNumber: currentLine,
            content: line.substring(1),
          ));
        }
      }
    }

    return GitBlame(path: filePath, lines: blameLines);
  }

  // -------------------------------------------------------------------------
  // Branches
  // -------------------------------------------------------------------------

  /// Lists branches. Set [all] to include remote-tracking branches.
  Future<List<GitBranch>> branches({bool all = false, String? workDir}) async {
    final args = <String>[
      'branch',
      '--format=%(HEAD)%(refname:short)|%(upstream:short)|%(upstream:track,nobracket)',
      if (all) '-a',
    ];

    final result = await _runGit(args, workDir: workDir ?? defaultWorkDir);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];

    final branchList = <GitBranch>[];

    for (final line in LineSplitter.split(output)) {
      final isCurrent = line.startsWith('*');
      final cleaned = isCurrent ? line.substring(1) : line;
      final parts = cleaned.split('|');

      final name = parts[0].trim();
      final upstreamName = parts.length > 1 && parts[1].isNotEmpty
          ? parts[1].trim()
          : null;
      final trackInfo = parts.length > 2 ? parts[2].trim() : '';

      int ahead = 0;
      int behind = 0;
      final aheadMatch = RegExp(r'ahead (\d+)').firstMatch(trackInfo);
      final behindMatch = RegExp(r'behind (\d+)').firstMatch(trackInfo);
      if (aheadMatch != null) ahead = int.parse(aheadMatch.group(1)!);
      if (behindMatch != null) behind = int.parse(behindMatch.group(1)!);

      branchList.add(GitBranch(
        name: name,
        isRemote: name.startsWith('remotes/') || name.contains('/'),
        isCurrent: isCurrent,
        upstream: upstreamName,
        ahead: ahead,
        behind: behind,
      ));
    }

    return branchList;
  }

  // -------------------------------------------------------------------------
  // Checkout
  // -------------------------------------------------------------------------

  /// Checks out a ref (branch, tag, commit).
  Future<void> checkout(
    String ref, {
    bool create = false,
    bool force = false,
    String? workDir,
  }) async {
    final args = <String>['checkout'];
    if (create) args.add('-b');
    if (force) args.add('-f');
    args.add(ref);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  // -------------------------------------------------------------------------
  // Commit
  // -------------------------------------------------------------------------

  /// Creates a commit.
  Future<GitCommit> commit(
    String message, {
    List<String>? files,
    bool all = false,
    bool amend = false,
    bool allowEmpty = false,
    String? workDir,
  }) async {
    if (files != null && files.isNotEmpty) {
      await add(files, workDir: workDir);
    }

    final args = <String>['commit', '-m', message];
    if (all) args.add('-a');
    if (amend) args.add('--amend');
    if (allowEmpty) args.add('--allow-empty');

    await _runGit(args, workDir: workDir ?? defaultWorkDir);

    // Return the commit that was just created.
    final commits = await log(maxCount: 1, workDir: workDir);
    return commits.first;
  }

  // -------------------------------------------------------------------------
  // Stash
  // -------------------------------------------------------------------------

  /// Stashes current changes.
  Future<void> stash({
    String? message,
    bool includeUntracked = false,
    String? workDir,
  }) async {
    final args = <String>['stash', 'push'];
    if (message != null) {
      args.addAll(['-m', message]);
    }
    if (includeUntracked) args.add('--include-untracked');
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Pops a stash entry.
  Future<void> stashPop({int? index, String? workDir}) async {
    final args = <String>['stash', 'pop'];
    if (index != null) args.add('stash@{$index}');
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Lists all stash entries.
  Future<List<GitStash>> stashList({String? workDir}) async {
    final result = await _runGit(
      ['stash', 'list', '--format=%gd|%gs|%aI'],
      workDir: workDir ?? defaultWorkDir,
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];

    final stashes = <GitStash>[];
    for (final line in LineSplitter.split(output)) {
      final parts = line.split('|');
      if (parts.isEmpty) continue;

      final indexMatch = RegExp(r'stash@\{(\d+)\}').firstMatch(parts[0]);
      final index = indexMatch != null
          ? int.tryParse(indexMatch.group(1)!) ?? 0
          : stashes.length;

      stashes.add(GitStash(
        index: index,
        message: parts.length > 1 ? parts[1] : '',
        date: parts.length > 2 ? DateTime.tryParse(parts[2]) : null,
      ));
    }

    return stashes;
  }

  // -------------------------------------------------------------------------
  // Add / Reset
  // -------------------------------------------------------------------------

  /// Stages files.
  Future<void> add(List<String> paths, {String? workDir}) async {
    if (paths.isEmpty) return;
    await _runGit(['add', ...paths], workDir: workDir ?? defaultWorkDir);
  }

  /// Resets files or the branch pointer.
  Future<void> reset(
    List<String> paths, {
    bool hard = false,
    bool soft = false,
    bool mixed = false,
    String? workDir,
  }) async {
    final args = <String>['reset'];
    if (hard) {
      args.add('--hard');
    } else if (soft) {
      args.add('--soft');
    } else if (mixed) {
      args.add('--mixed');
    }
    if (paths.isNotEmpty) {
      args.add('--');
      args.addAll(paths);
    }
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  // -------------------------------------------------------------------------
  // Fetch / Pull / Push
  // -------------------------------------------------------------------------

  /// Fetches from a remote.
  Future<void> fetch({
    String? remote,
    bool prune = false,
    String? workDir,
  }) async {
    final args = <String>['fetch'];
    if (prune) args.add('--prune');
    if (remote != null) args.add(remote);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Pulls from the upstream branch.
  Future<void> pull({bool rebase = false, String? workDir}) async {
    final args = <String>['pull'];
    if (rebase) args.add('--rebase');
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Pushes to a remote.
  Future<void> push({
    String? remote,
    String? branch,
    bool force = false,
    bool setUpstream = false,
    String? workDir,
  }) async {
    final args = <String>['push'];
    if (force) args.add('--force');
    if (setUpstream) args.add('--set-upstream');
    if (remote != null) args.add(remote);
    if (branch != null) args.add(branch);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  // -------------------------------------------------------------------------
  // Merge / Rebase
  // -------------------------------------------------------------------------

  /// Merges a branch into the current branch.
  Future<void> merge(
    String branch, {
    bool noFf = false,
    bool squash = false,
    String? workDir,
  }) async {
    final args = <String>['merge'];
    if (noFf) args.add('--no-ff');
    if (squash) args.add('--squash');
    args.add(branch);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Rebases the current branch onto [onto].
  Future<void> rebase(
    String onto, {
    bool interactive = false,
    String? workDir,
  }) async {
    final args = <String>['rebase'];
    if (interactive) args.add('--interactive');
    args.add(onto);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  // -------------------------------------------------------------------------
  // Tags
  // -------------------------------------------------------------------------

  /// Creates a tag.
  Future<void> tag(
    String name, {
    String? message,
    bool annotated = false,
    String? workDir,
  }) async {
    final args = <String>['tag'];
    if (annotated || message != null) {
      args.add('-a');
      args.addAll(['-m', message ?? name]);
    }
    args.add(name);
    await _runGit(args, workDir: workDir ?? defaultWorkDir);
  }

  /// Lists tags.
  Future<List<String>> tagList({String? workDir}) async {
    final result = await _runGit(['tag', '--list'], workDir: workDir ?? defaultWorkDir);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];
    return LineSplitter.split(output).toList();
  }

  // -------------------------------------------------------------------------
  // Remotes
  // -------------------------------------------------------------------------

  /// Lists configured remotes.
  Future<List<GitRemote>> remotes({String? workDir}) async {
    final result = await _runGit(
      ['remote', '-v'],
      workDir: workDir ?? defaultWorkDir,
    );
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];

    final map = <String, _RemoteUrls>{};

    for (final line in LineSplitter.split(output)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 3) continue;
      final name = parts[0];
      final url = parts[1];
      final type = parts[2]; // (fetch) or (push)

      map.putIfAbsent(name, () => _RemoteUrls());
      if (type.contains('fetch')) {
        map[name]!.fetchUrl = url;
      } else {
        map[name]!.pushUrl = url;
      }
    }

    return map.entries.map((e) => GitRemote(
      name: e.key,
      fetchUrl: e.value.fetchUrl ?? '',
      pushUrl: e.value.pushUrl ?? e.value.fetchUrl ?? '',
    )).toList();
  }

  /// Adds a remote.
  Future<void> remoteAdd(String name, String url, {String? workDir}) async {
    await _runGit(
      ['remote', 'add', name, url],
      workDir: workDir ?? defaultWorkDir,
    );
  }

  /// Removes a remote.
  Future<void> remoteRemove(String name, {String? workDir}) async {
    await _runGit(
      ['remote', 'remove', name],
      workDir: workDir ?? defaultWorkDir,
    );
  }

  // -------------------------------------------------------------------------
  // Repository queries
  // -------------------------------------------------------------------------

  /// Returns `true` if [path] is inside a git repository.
  Future<bool> isGitRepo(String path) async {
    try {
      final result = await Process.run(
        _gitBinary,
        ['rev-parse', '--is-inside-work-tree'],
        workingDirectory: path,
      );
      return result.exitCode == 0 &&
          (result.stdout as String).trim() == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Returns the root of the git repository containing [path], or `null`.
  Future<String?> getRepoRoot(String path) async {
    try {
      final result = await Process.run(
        _gitBinary,
        ['rev-parse', '--show-toplevel'],
        workingDirectory: path,
      );
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Cherry-pick
  // -------------------------------------------------------------------------

  /// Cherry-picks a commit onto the current branch.
  Future<void> cherryPick(String commit, {String? workDir}) async {
    await _runGit(
      ['cherry-pick', commit],
      workDir: workDir ?? defaultWorkDir,
    );
  }

  // -------------------------------------------------------------------------
  // Shortlog
  // -------------------------------------------------------------------------

  /// Returns per-author commit counts.
  Future<List<AuthorStats>> shortlog({String? since, String? workDir}) async {
    final args = <String>['shortlog', '-sne', 'HEAD'];
    if (since != null) args.insert(2, '--since=$since');

    final result = await _runGit(args, workDir: workDir ?? defaultWorkDir);
    final output = (result.stdout as String).trim();
    if (output.isEmpty) return [];

    final stats = <AuthorStats>[];
    for (final line in LineSplitter.split(output)) {
      final match = RegExp(r'^\s*(\d+)\s+(.+?)\s+<(.+?)>\s*$').firstMatch(line);
      if (match != null) {
        stats.add(AuthorStats(
          name: match.group(2)!,
          email: match.group(3)!,
          commitCount: int.parse(match.group(1)!),
        ));
      }
    }

    return stats;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Runs a git command and returns the [ProcessResult].
  ///
  /// Throws [GitException] on non-zero exit codes.
  Future<ProcessResult> _runGit(
    List<String> args, {
    String? workDir,
  }) async {
    final result = await Process.run(
      _gitBinary,
      args,
      workingDirectory: workDir,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

    if (result.exitCode != 0) {
      throw GitException(
        command: args.join(' '),
        exitCode: result.exitCode,
        stderr: (result.stderr as String).trim(),
      );
    }

    return result;
  }

  /// Detects special repository states (merging, rebasing, etc.).
  Future<GitStatus> _detectRepoStatus(String? workDir) async {
    final dir = workDir ?? Directory.current.path;

    try {
      final gitDir = await _findGitDir(dir);
      if (gitDir == null) return GitStatus.clean;

      if (await File('$gitDir/MERGE_HEAD').exists()) {
        return GitStatus.merging;
      }
      if (await Directory('$gitDir/rebase-merge').exists() ||
          await Directory('$gitDir/rebase-apply').exists()) {
        return GitStatus.rebasing;
      }
      if (await File('$gitDir/CHERRY_PICK_HEAD').exists()) {
        return GitStatus.cherryPicking;
      }
    } catch (_) {
      // Ignore errors; fall through to clean/dirty.
    }

    return GitStatus.clean;
  }

  /// Finds the .git directory for the given working directory.
  Future<String?> _findGitDir(String workDir) async {
    try {
      final result = await Process.run(
        _gitBinary,
        ['rev-parse', '--git-dir'],
        workingDirectory: workDir,
        stdoutEncoding: utf8,
      );
      if (result.exitCode != 0) return null;
      final gitDir = (result.stdout as String).trim();
      // May be relative; resolve against workDir.
      if (gitDir.startsWith('/')) return gitDir;
      return '$workDir/$gitDir';
    } catch (_) {
      return null;
    }
  }

  /// Parses a porcelain v2 status line into a [GitFileChange].
  GitFileChange _parseStatusLine(String line) {
    // Ordinary changed entry:  1 XY sub mH mI mW hH hI path
    // Renamed/copied entry:    2 XY sub mH mI mW hH hI X score path\toldPath

    final isRenamed = line.startsWith('2 ');
    final parts = line.split(' ');

    // XY codes are at index 1.
    final xy = parts[1];
    final indexStatus = xy[0];
    final workTreeStatus = xy[1];

    // Path is the last element (may include tab-separated old path for renames).
    String filePath;
    String? oldPath;

    if (isRenamed) {
      // Everything after the 8th space is the path info.
      final pathPart = parts.sublist(8).join(' ');
      final pathParts = pathPart.split('\t');
      filePath = pathParts[0];
      oldPath = pathParts.length > 1 ? pathParts[1] : null;
    } else {
      filePath = parts.sublist(8).join(' ');
    }

    // Determine status and staged flag.
    // Index status takes precedence if staged.
    if (indexStatus != '.') {
      return GitFileChange(
        path: filePath,
        oldPath: oldPath,
        status: _charToFileStatus(indexStatus),
        staged: true,
      );
    }

    return GitFileChange(
      path: filePath,
      oldPath: oldPath,
      status: _charToFileStatus(workTreeStatus),
      staged: false,
    );
  }

  /// Converts a single-character status code to [GitFileStatus].
  GitFileStatus _charToFileStatus(String c) {
    switch (c) {
      case 'M':
        return GitFileStatus.modified;
      case 'A':
        return GitFileStatus.added;
      case 'D':
        return GitFileStatus.deleted;
      case 'R':
        return GitFileStatus.renamed;
      case 'C':
        return GitFileStatus.copied;
      case '?':
        return GitFileStatus.untracked;
      case '!':
        return GitFileStatus.ignored;
      default:
        return GitFileStatus.modified;
    }
  }
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

/// Temporary holder for remote URLs while parsing `git remote -v`.
class _RemoteUrls {
  String? fetchUrl;
  String? pushUrl;
}
