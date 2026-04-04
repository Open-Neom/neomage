// Git utilities — port of neom_claw git helpers.
// Git operations, branch info, diff generation, worktree management.

import 'package:flutter_claw/core/platform/claw_io.dart';

/// Git operation result.
class GitResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const GitResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  bool get success => exitCode == 0;
  String get output => stdout.trim();
}

/// Git status entry.
class GitStatusEntry {
  final String path;
  final GitFileStatus status;
  final String? originalPath; // For renames

  const GitStatusEntry({
    required this.path,
    required this.status,
    this.originalPath,
  });
}

enum GitFileStatus {
  added,
  modified,
  deleted,
  renamed,
  copied,
  untracked,
  ignored,
}

/// Run a git command.
Future<GitResult> runGit(
  List<String> args, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final result = await Process.run(
    'git',
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );

  return GitResult(
    exitCode: result.exitCode,
    stdout: result.stdout as String,
    stderr: result.stderr as String,
  );
}

/// Check if a directory is a git repository.
Future<bool> isGitRepo({String? dir}) async {
  final result = await runGit(
    ['rev-parse', '--is-inside-work-tree'],
    workingDirectory: dir,
  );
  return result.success && result.output == 'true';
}

/// Get the current branch name.
Future<String?> currentBranch({String? dir}) async {
  final result = await runGit(
    ['branch', '--show-current'],
    workingDirectory: dir,
  );
  return result.success ? result.output : null;
}

/// Get the repository root directory.
Future<String?> repoRoot({String? dir}) async {
  final result = await runGit(
    ['rev-parse', '--show-toplevel'],
    workingDirectory: dir,
  );
  return result.success ? result.output : null;
}

/// Get the current commit hash.
Future<String?> currentCommit({String? dir, bool short = false}) async {
  final result = await runGit(
    ['rev-parse', if (short) '--short', 'HEAD'],
    workingDirectory: dir,
  );
  return result.success ? result.output : null;
}

/// Get git status (porcelain v1 format).
Future<List<GitStatusEntry>> gitStatus({String? dir}) async {
  final result = await runGit(
    ['status', '--porcelain=v1'],
    workingDirectory: dir,
  );

  if (!result.success) return [];

  return result.output
      .split('\n')
      .where((l) => l.length >= 3)
      .map((line) {
    final xy = line.substring(0, 2);
    final path = line.substring(3);

    final status = switch (xy.trim()) {
      'A' || '??' => GitFileStatus.added,
      'M' || 'MM' => GitFileStatus.modified,
      'D' => GitFileStatus.deleted,
      'R' => GitFileStatus.renamed,
      'C' => GitFileStatus.copied,
      '!!' => GitFileStatus.ignored,
      _ when xy.contains('?') => GitFileStatus.untracked,
      _ => GitFileStatus.modified,
    };

    String? originalPath;
    if (status == GitFileStatus.renamed && path.contains(' -> ')) {
      final parts = path.split(' -> ');
      originalPath = parts[0];
      return GitStatusEntry(
        path: parts[1],
        status: status,
        originalPath: originalPath,
      );
    }

    return GitStatusEntry(path: path, status: status);
  }).toList();
}

/// Get diff for staged files.
Future<String> stagedDiff({String? dir}) async {
  final result = await runGit(['diff', '--cached'], workingDirectory: dir);
  return result.success ? result.output : '';
}

/// Get diff for unstaged files.
Future<String> unstagedDiff({String? dir}) async {
  final result = await runGit(['diff'], workingDirectory: dir);
  return result.success ? result.output : '';
}

/// Get diff between two refs.
Future<String> diffBetween(
  String fromRef,
  String toRef, {
  String? dir,
}) async {
  final result = await runGit(
    ['diff', '$fromRef...$toRef'],
    workingDirectory: dir,
  );
  return result.success ? result.output : '';
}

/// Get recent commit log.
Future<List<String>> recentCommits({
  String? dir,
  int count = 10,
  String format = '%h %s',
}) async {
  final result = await runGit(
    ['log', '--oneline', '-$count', '--format=$format'],
    workingDirectory: dir,
  );
  if (!result.success) return [];
  return result.output.split('\n').where((l) => l.isNotEmpty).toList();
}

/// Create a git worktree.
Future<String?> createWorktree({
  String? dir,
  required String path,
  required String branch,
  bool createBranch = true,
}) async {
  final args = ['worktree', 'add'];
  if (createBranch) args.add('-b');
  args.addAll([path, if (!createBranch) branch]);

  final result = await runGit(args, workingDirectory: dir);
  return result.success ? path : null;
}

/// Remove a git worktree.
Future<bool> removeWorktree({
  String? dir,
  required String path,
  bool force = false,
}) async {
  final result = await runGit(
    ['worktree', 'remove', if (force) '--force', path],
    workingDirectory: dir,
  );
  return result.success;
}

/// List git worktrees.
Future<List<String>> listWorktrees({String? dir}) async {
  final result = await runGit(
    ['worktree', 'list', '--porcelain'],
    workingDirectory: dir,
  );
  if (!result.success) return [];

  return result.output
      .split('\n')
      .where((l) => l.startsWith('worktree '))
      .map((l) => l.substring(9))
      .toList();
}

/// Stage files for commit.
Future<bool> stageFiles(List<String> files, {String? dir}) async {
  final result = await runGit(['add', ...files], workingDirectory: dir);
  return result.success;
}

/// Create a commit.
Future<GitResult> commit(String message, {String? dir}) async {
  return runGit(['commit', '-m', message], workingDirectory: dir);
}

/// Check if there are uncommitted changes.
Future<bool> hasUncommittedChanges({String? dir}) async {
  final result = await runGit(
    ['status', '--porcelain'],
    workingDirectory: dir,
  );
  return result.success && result.output.isNotEmpty;
}

/// Get the tracking remote for the current branch.
Future<String?> trackingRemote({String? dir}) async {
  final branch = await currentBranch(dir: dir);
  if (branch == null) return null;

  final result = await runGit(
    ['config', 'branch.$branch.remote'],
    workingDirectory: dir,
  );
  return result.success ? result.output : null;
}
