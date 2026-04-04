/// Git commit attribution and message formatting.
///
/// Ported from openneomclaw/src/utils/commitAttribution.ts (961 LOC).
///
/// Tracks NeomClaw's contributions to files, calculates attribution
/// percentages for git commits, and provides snapshot/restore support
/// for session persistence.

import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// List of repos where internal model names are allowed in trailers.
/// Includes both SSH and HTTPS URL formats.
///
/// NOTE: This is intentionally a repo allowlist, not an org-wide check.
/// The anthropics and anthropic-experimental orgs contain PUBLIC repos.
/// Undercover mode must stay ON in those to prevent codename leaks.
/// Only add repos here that are confirmed PRIVATE.
const List<String> _internalModelRepos = [
  'github.com:anthropics/neom-claw-cli-internal',
  'github.com/anthropics/neom-claw-cli-internal',
  'github.com:anthropics/anthropic',
  'github.com/anthropics/anthropic',
  'github.com:anthropics/apps',
  'github.com/anthropics/apps',
  'github.com:anthropics/casino',
  'github.com/anthropics/casino',
  'github.com:anthropics/dbt',
  'github.com/anthropics/dbt',
  'github.com:anthropics/dotfiles',
  'github.com/anthropics/dotfiles',
  'github.com:anthropics/terraform-config',
  'github.com/anthropics/terraform-config',
  'github.com:anthropics/hex-export',
  'github.com/anthropics/hex-export',
  'github.com:anthropics/feedback-v2',
  'github.com/anthropics/feedback-v2',
  'github.com:anthropics/labs',
  'github.com/anthropics/labs',
  'github.com:anthropics/argo-rollouts',
  'github.com/anthropics/argo-rollouts',
  'github.com:anthropics/starling-configs',
  'github.com/anthropics/starling-configs',
  'github.com:anthropics/ts-tools',
  'github.com/anthropics/ts-tools',
  'github.com:anthropics/ts-capsules',
  'github.com/anthropics/ts-capsules',
  'github.com:anthropics/feldspar-testing',
  'github.com/anthropics/feldspar-testing',
  'github.com:anthropics/trellis',
  'github.com/anthropics/trellis',
  'github.com:anthropics/neom-claw-for-hiring',
  'github.com/anthropics/neom-claw-for-hiring',
  'github.com:anthropics/forge-web',
  'github.com/anthropics/forge-web',
  'github.com:anthropics/infra-manifests',
  'github.com/anthropics/infra-manifests',
  'github.com:anthropics/mycro_manifests',
  'github.com/anthropics/mycro_manifests',
  'github.com:anthropics/mycro_configs',
  'github.com/anthropics/mycro_configs',
  'github.com:anthropics/mobile-apps',
  'github.com/anthropics/mobile-apps',
];

// ---------------------------------------------------------------------------
// Types — FileAttributionState
// ---------------------------------------------------------------------------

/// Per-file attribution state tracked across edits.
class FileAttributionState {
  FileAttributionState({
    required this.contentHash,
    required this.neomClawContribution,
    required this.mtime,
  });

  final String contentHash;
  final int neomClawContribution;
  final int mtime;

  factory FileAttributionState.fromJson(Map<String, dynamic> json) {
    return FileAttributionState(
      contentHash: json['contentHash'] as String? ?? '',
      neomClawContribution:
          (json['neomClawContribution'] as num?)?.toInt() ?? 0,
      mtime: (json['mtime'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'contentHash': contentHash,
        'neomClawContribution': neomClawContribution,
        'mtime': mtime,
      };
}

// ---------------------------------------------------------------------------
// Types — AttributionState
// ---------------------------------------------------------------------------

/// Attribution state for tracking NeomClaw's contributions to files.
class AttributionState {
  AttributionState({
    Map<String, FileAttributionState>? fileStates,
    Map<String, BaselineEntry>? sessionBaselines,
    this.surface = 'cli',
    this.startingHeadSha,
    this.promptCount = 0,
    this.promptCountAtLastCommit = 0,
    this.permissionPromptCount = 0,
    this.permissionPromptCountAtLastCommit = 0,
    this.escapeCount = 0,
    this.escapeCountAtLastCommit = 0,
  })  : fileStates = fileStates ?? {},
        sessionBaselines = sessionBaselines ?? {};

  /// File states keyed by relative path (from cwd).
  final Map<String, FileAttributionState> fileStates;

  /// Session baseline states for net change calculation.
  final Map<String, BaselineEntry> sessionBaselines;

  /// Surface from which edits were made.
  final String surface;

  /// HEAD SHA at session start (for detecting external commits).
  final String? startingHeadSha;

  /// Total prompts in session (for steer count calculation).
  int promptCount;

  /// Prompts at last commit (to calculate steers for current commit).
  int promptCountAtLastCommit;

  /// Permission prompt tracking.
  int permissionPromptCount;
  int permissionPromptCountAtLastCommit;

  /// ESC press tracking (user cancelled permission prompt).
  int escapeCount;
  int escapeCountAtLastCommit;

  AttributionState copyWith({
    Map<String, FileAttributionState>? fileStates,
    Map<String, BaselineEntry>? sessionBaselines,
    String? surface,
    String? startingHeadSha,
    int? promptCount,
    int? promptCountAtLastCommit,
    int? permissionPromptCount,
    int? permissionPromptCountAtLastCommit,
    int? escapeCount,
    int? escapeCountAtLastCommit,
  }) {
    return AttributionState(
      fileStates: fileStates ?? this.fileStates,
      sessionBaselines: sessionBaselines ?? this.sessionBaselines,
      surface: surface ?? this.surface,
      startingHeadSha: startingHeadSha ?? this.startingHeadSha,
      promptCount: promptCount ?? this.promptCount,
      promptCountAtLastCommit:
          promptCountAtLastCommit ?? this.promptCountAtLastCommit,
      permissionPromptCount:
          permissionPromptCount ?? this.permissionPromptCount,
      permissionPromptCountAtLastCommit: permissionPromptCountAtLastCommit ??
          this.permissionPromptCountAtLastCommit,
      escapeCount: escapeCount ?? this.escapeCount,
      escapeCountAtLastCommit:
          escapeCountAtLastCommit ?? this.escapeCountAtLastCommit,
    );
  }
}

/// Session baseline entry.
class BaselineEntry {
  const BaselineEntry({required this.contentHash, required this.mtime});
  final String contentHash;
  final int mtime;

  factory BaselineEntry.fromJson(Map<String, dynamic> json) {
    return BaselineEntry(
      contentHash: json['contentHash'] as String? ?? '',
      mtime: (json['mtime'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'contentHash': contentHash,
        'mtime': mtime,
      };
}

// ---------------------------------------------------------------------------
// Types — AttributionSummary
// ---------------------------------------------------------------------------

/// Summary of NeomClaw's contribution for a commit.
class AttributionSummary {
  const AttributionSummary({
    required this.neomClawPercent,
    required this.neomClawChars,
    required this.humanChars,
    required this.surfaces,
  });

  final int neomClawPercent;
  final int neomClawChars;
  final int humanChars;
  final List<String> surfaces;

  Map<String, dynamic> toJson() => {
        'neomClawPercent': neomClawPercent,
        'neomClawChars': neomClawChars,
        'humanChars': humanChars,
        'surfaces': surfaces,
      };
}

// ---------------------------------------------------------------------------
// Types — FileAttribution
// ---------------------------------------------------------------------------

/// Per-file attribution details for git notes.
class FileAttribution {
  const FileAttribution({
    required this.neomClawChars,
    required this.humanChars,
    required this.percent,
    required this.surface,
  });

  final int neomClawChars;
  final int humanChars;
  final int percent;
  final String surface;

  Map<String, dynamic> toJson() => {
        'neomClawChars': neomClawChars,
        'humanChars': humanChars,
        'percent': percent,
        'surface': surface,
      };
}

// ---------------------------------------------------------------------------
// Types — AttributionData
// ---------------------------------------------------------------------------

/// Full attribution data for git notes JSON.
class AttributionData {
  const AttributionData({
    this.version = 1,
    required this.summary,
    required this.files,
    required this.surfaceBreakdown,
    required this.excludedGenerated,
    required this.sessions,
  });

  final int version;
  final AttributionSummary summary;
  final Map<String, FileAttribution> files;
  final Map<String, SurfaceBreakdownEntry> surfaceBreakdown;
  final List<String> excludedGenerated;
  final List<String> sessions;

  Map<String, dynamic> toJson() => {
        'version': version,
        'summary': summary.toJson(),
        'files': files.map((k, v) => MapEntry(k, v.toJson())),
        'surfaceBreakdown':
            surfaceBreakdown.map((k, v) => MapEntry(k, v.toJson())),
        'excludedGenerated': excludedGenerated,
        'sessions': sessions,
      };
}

/// Surface breakdown entry for attribution data.
class SurfaceBreakdownEntry {
  const SurfaceBreakdownEntry(
      {required this.neomClawChars, required this.percent});
  final int neomClawChars;
  final int percent;

  Map<String, dynamic> toJson() => {
        'neomClawChars': neomClawChars,
        'percent': percent,
      };
}

// ---------------------------------------------------------------------------
// Types — AttributionSnapshotMessage
// ---------------------------------------------------------------------------

/// Attribution snapshot message for persistence.
class AttributionSnapshotMessage {
  const AttributionSnapshotMessage({
    this.type = 'attribution-snapshot',
    required this.messageId,
    required this.surface,
    required this.fileStates,
    this.promptCount = 0,
    this.promptCountAtLastCommit = 0,
    this.permissionPromptCount = 0,
    this.permissionPromptCountAtLastCommit = 0,
    this.escapeCount = 0,
    this.escapeCountAtLastCommit = 0,
  });

  final String type;
  final String messageId;
  final String surface;
  final Map<String, FileAttributionState> fileStates;
  final int promptCount;
  final int promptCountAtLastCommit;
  final int permissionPromptCount;
  final int permissionPromptCountAtLastCommit;
  final int escapeCount;
  final int escapeCountAtLastCommit;

  factory AttributionSnapshotMessage.fromJson(Map<String, dynamic> json) {
    final fs = (json['fileStates'] as Map<String, dynamic>?)?.map((k, v) =>
            MapEntry(
                k, FileAttributionState.fromJson(v as Map<String, dynamic>))) ??
        {};
    return AttributionSnapshotMessage(
      messageId: json['messageId'] as String,
      surface: json['surface'] as String? ?? 'cli',
      fileStates: fs,
      promptCount: (json['promptCount'] as num?)?.toInt() ?? 0,
      promptCountAtLastCommit:
          (json['promptCountAtLastCommit'] as num?)?.toInt() ?? 0,
      permissionPromptCount:
          (json['permissionPromptCount'] as num?)?.toInt() ?? 0,
      permissionPromptCountAtLastCommit:
          (json['permissionPromptCountAtLastCommit'] as num?)?.toInt() ?? 0,
      escapeCount: (json['escapeCount'] as num?)?.toInt() ?? 0,
      escapeCountAtLastCommit:
          (json['escapeCountAtLastCommit'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'messageId': messageId,
        'surface': surface,
        'fileStates':
            fileStates.map((k, v) => MapEntry(k, v.toJson())),
        'promptCount': promptCount,
        'promptCountAtLastCommit': promptCountAtLastCommit,
        'permissionPromptCount': permissionPromptCount,
        'permissionPromptCountAtLastCommit':
            permissionPromptCountAtLastCommit,
        'escapeCount': escapeCount,
        'escapeCountAtLastCommit': escapeCountAtLastCommit,
      };
}

// ---------------------------------------------------------------------------
// Types — FileChange (for bulk tracking)
// ---------------------------------------------------------------------------

/// A single file change for bulk tracking.
class FileChange {
  const FileChange({
    required this.path,
    required this.type,
    required this.oldContent,
    required this.newContent,
    this.mtime,
  });

  final String path;

  /// 'modified', 'created', or 'deleted'.
  final String type;
  final String oldContent;
  final String newContent;
  final int? mtime;
}

// ---------------------------------------------------------------------------
// RepoClassification
// ---------------------------------------------------------------------------

/// Repo classification result.
enum RepoClassification {
  /// Remote matches INTERNAL_MODEL_REPOS allowlist.
  internal,

  /// Has a remote, not on allowlist (public/open-source repo).
  external,

  /// No remote URL (not a git repo, or no remote configured).
  none,
}

// ---------------------------------------------------------------------------
// CommitAttributionManager — SintController
// ---------------------------------------------------------------------------

/// Manages git commit attribution tracking and calculation.
///
/// Usage:
/// ```dart
/// final manager = Sint.put(CommitAttributionManager(
///   sessionId: 'abc-123',
///   originalCwd: '/path/to/project',
/// ));
/// ```
class CommitAttributionManager extends SintController {
  CommitAttributionManager({
    required this.sessionId,
    String? originalCwd,
    this.clientSurface = 'cli',
    this.gitExe = 'git',
  }) : _originalCwd = originalCwd ?? Directory.current.path;

  final String sessionId;
  final String _originalCwd;
  final String clientSurface;
  final String gitExe;

  /// Reactive attribution state.
  final Rx<AttributionState> state = AttributionState().obs;

  /// Cached repo classification result. Primed once per process.
  RepoClassification? _repoClassCache;

  /// Callback to check if a file is a generated file (lock files, etc.).
  bool Function(String filePath)? isGeneratedFileChecker;

  /// Callback to get the remote URL for a directory.
  Future<String?> Function(String cwd)? getRemoteUrlForDir;

  /// Callback to resolve the git directory path.
  Future<String?> Function(String cwd)? resolveGitDir;

  // -------------------------------------------------------------------------
  // Repo root
  // -------------------------------------------------------------------------

  /// Get the repo root for attribution operations.
  String getAttributionRepoRoot() {
    return _findGitRoot(_originalCwd) ?? _originalCwd;
  }

  String? _findGitRoot(String cwd) {
    var dir = cwd;
    while (true) {
      if (Directory('$dir/.git').existsSync()) return dir;
      final parent = dir.substring(0, dir.lastIndexOf('/'));
      if (parent == dir || parent.isEmpty) return null;
      dir = parent;
    }
  }

  // -------------------------------------------------------------------------
  // Repo classification
  // -------------------------------------------------------------------------

  /// Synchronously return the cached repo classification.
  RepoClassification? getRepoClassCached() => _repoClassCache;

  /// Synchronously return the cached result of isInternalModelRepo().
  bool isInternalModelRepoCached() =>
      _repoClassCache == RepoClassification.internal;

  /// Check if the current repo is in the allowlist for internal model names.
  Future<bool> isInternalModelRepo() async {
    if (_repoClassCache != null) {
      return _repoClassCache == RepoClassification.internal;
    }

    final cwd = getAttributionRepoRoot();
    final remoteUrl = await getRemoteUrlForDir?.call(cwd);

    if (remoteUrl == null) {
      _repoClassCache = RepoClassification.none;
      return false;
    }

    final isInternal =
        _internalModelRepos.any((repo) => remoteUrl.contains(repo));
    _repoClassCache =
        isInternal ? RepoClassification.internal : RepoClassification.external;
    return isInternal;
  }

  // -------------------------------------------------------------------------
  // Model name sanitization
  // -------------------------------------------------------------------------

  /// Sanitize a surface key to use public model names.
  static String sanitizeSurfaceKey(String surfaceKey) {
    final slashIndex = surfaceKey.lastIndexOf('/');
    if (slashIndex == -1) return surfaceKey;

    final surface = surfaceKey.substring(0, slashIndex);
    final model = surfaceKey.substring(slashIndex + 1);
    final sanitizedModel = sanitizeModelName(model);
    return '$surface/$sanitizedModel';
  }

  /// Sanitize a model name to its public equivalent.
  static String sanitizeModelName(String shortName) {
    if (shortName.contains('opus-4-6')) return 'claude-opus-4-6';
    if (shortName.contains('opus-4-5')) return 'claude-opus-4-5';
    if (shortName.contains('opus-4-1')) return 'claude-opus-4-1';
    if (shortName.contains('opus-4')) return 'claude-opus-4';
    if (shortName.contains('sonnet-4-6')) return 'claude-sonnet-4-6';
    if (shortName.contains('sonnet-4-5')) return 'claude-sonnet-4-5';
    if (shortName.contains('sonnet-4')) return 'claude-sonnet-4';
    if (shortName.contains('sonnet-3-7')) return 'claude-sonnet-3-7';
    if (shortName.contains('haiku-4-5')) return 'claude-haiku-4-5';
    if (shortName.contains('haiku-3-5')) return 'claude-haiku-3-5';
    return 'neomclaw';
  }

  // -------------------------------------------------------------------------
  // Surface key
  // -------------------------------------------------------------------------

  /// Get the current client surface from environment.
  String getClientSurface() => clientSurface;

  /// Build a surface key that includes the model name.
  static String buildSurfaceKey(String surface, String modelName) {
    return '$surface/$modelName';
  }

  // -------------------------------------------------------------------------
  // Content hash
  // -------------------------------------------------------------------------

  /// Compute SHA-256 hash of content.
  static String computeContentHash(String content) {
    // Simple hash — in production, use dart:crypto or crypto package.
    var hash = 0;
    for (var i = 0; i < content.length; i++) {
      hash = ((hash << 5) - hash + content.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  // -------------------------------------------------------------------------
  // Normalize / expand file path
  // -------------------------------------------------------------------------

  /// Normalize file path to relative path from cwd for consistent tracking.
  String normalizeFilePath(String filePath) {
    final cwd = getAttributionRepoRoot();
    if (!filePath.startsWith('/')) return filePath;

    // Resolve symlinks in both paths for consistent comparison.
    var resolvedPath = filePath;
    var resolvedCwd = cwd;

    try {
      resolvedPath = File(filePath).resolveSymbolicLinksSync();
    } catch (_) {
      // File may not exist yet.
    }

    try {
      resolvedCwd = Directory(cwd).resolveSymbolicLinksSync();
    } catch (_) {
      // Keep original cwd.
    }

    if (resolvedPath.startsWith('$resolvedCwd/') ||
        resolvedPath == resolvedCwd) {
      return resolvedPath
          .substring(resolvedCwd.length)
          .replaceAll(RegExp(r'^/'), '')
          .replaceAll(Platform.pathSeparator, '/');
    }

    if (filePath.startsWith('$cwd/') || filePath == cwd) {
      return filePath
          .substring(cwd.length)
          .replaceAll(RegExp(r'^/'), '')
          .replaceAll(Platform.pathSeparator, '/');
    }

    return filePath;
  }

  /// Expand a relative path to absolute path.
  String expandFilePath(String filePath) {
    if (filePath.startsWith('/')) return filePath;
    return '${getAttributionRepoRoot()}/$filePath';
  }

  // -------------------------------------------------------------------------
  // Create empty attribution state
  // -------------------------------------------------------------------------

  /// Create an empty attribution state for a new session.
  AttributionState createEmptyAttributionState() {
    return AttributionState(surface: getClientSurface());
  }

  // -------------------------------------------------------------------------
  // Compute file modification state
  // -------------------------------------------------------------------------

  /// Compute the character contribution for a file modification.
  FileAttributionState? _computeFileModificationState({
    required Map<String, FileAttributionState> existingFileStates,
    required String filePath,
    required String oldContent,
    required String newContent,
    required int mtime,
  }) {
    final normalizedPath = normalizeFilePath(filePath);

    try {
      int neomClawContribution;

      if (oldContent.isEmpty || newContent.isEmpty) {
        // New file or full deletion.
        neomClawContribution =
            oldContent.isEmpty ? newContent.length : oldContent.length;
      } else {
        // Find actual changed region via common prefix/suffix matching.
        final minLen = min(oldContent.length, newContent.length);
        var prefixEnd = 0;
        while (prefixEnd < minLen &&
            oldContent.codeUnitAt(prefixEnd) ==
                newContent.codeUnitAt(prefixEnd)) {
          prefixEnd++;
        }
        var suffixLen = 0;
        while (suffixLen < minLen - prefixEnd &&
            oldContent.codeUnitAt(oldContent.length - 1 - suffixLen) ==
                newContent.codeUnitAt(newContent.length - 1 - suffixLen)) {
          suffixLen++;
        }
        final oldChangedLen = oldContent.length - prefixEnd - suffixLen;
        final newChangedLen = newContent.length - prefixEnd - suffixLen;
        neomClawContribution = max(oldChangedLen, newChangedLen);
      }

      final existingState = existingFileStates[normalizedPath];
      final existingContribution = existingState?.neomClawContribution ?? 0;

      return FileAttributionState(
        contentHash: computeContentHash(newContent),
        neomClawContribution: existingContribution + neomClawContribution,
        mtime: mtime,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // Get file mtime
  // -------------------------------------------------------------------------

  /// Get a file's modification time (mtimeMs).
  Future<int> getFileMtime(String filePath) async {
    final normalizedPath = normalizeFilePath(filePath);
    final absPath = expandFilePath(normalizedPath);
    try {
      final stat = await FileStat.stat(absPath);
      return stat.modified.millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }

  // -------------------------------------------------------------------------
  // Track file modification
  // -------------------------------------------------------------------------

  /// Track a file modification by NeomClaw.
  /// Called after Edit/Write tool completes.
  AttributionState trackFileModification({
    required AttributionState attrState,
    required String filePath,
    required String oldContent,
    required String newContent,
    bool userModified = false,
    int? mtime,
  }) {
    final normalizedPath = normalizeFilePath(filePath);
    final effectiveMtime =
        mtime ?? DateTime.now().millisecondsSinceEpoch;

    final newFileState = _computeFileModificationState(
      existingFileStates: attrState.fileStates,
      filePath: filePath,
      oldContent: oldContent,
      newContent: newContent,
      mtime: effectiveMtime,
    );
    if (newFileState == null) return attrState;

    final newFileStates =
        Map<String, FileAttributionState>.from(attrState.fileStates);
    newFileStates[normalizedPath] = newFileState;

    return attrState.copyWith(fileStates: newFileStates);
  }

  /// Track a file creation by NeomClaw.
  AttributionState trackFileCreation({
    required AttributionState attrState,
    required String filePath,
    required String content,
    int? mtime,
  }) {
    return trackFileModification(
      attrState: attrState,
      filePath: filePath,
      oldContent: '',
      newContent: content,
      mtime: mtime,
    );
  }

  /// Track a file deletion by NeomClaw.
  AttributionState trackFileDeletion({
    required AttributionState attrState,
    required String filePath,
    required String oldContent,
  }) {
    final normalizedPath = normalizeFilePath(filePath);
    final existingState = attrState.fileStates[normalizedPath];
    final existingContribution = existingState?.neomClawContribution ?? 0;
    final deletedChars = oldContent.length;

    final newFileState = FileAttributionState(
      contentHash: '',
      neomClawContribution: existingContribution + deletedChars,
      mtime: DateTime.now().millisecondsSinceEpoch,
    );

    final newFileStates =
        Map<String, FileAttributionState>.from(attrState.fileStates);
    newFileStates[normalizedPath] = newFileState;

    return attrState.copyWith(fileStates: newFileStates);
  }

  // -------------------------------------------------------------------------
  // Track bulk file changes
  // -------------------------------------------------------------------------

  /// Track multiple file changes in bulk, mutating a single Map copy.
  AttributionState trackBulkFileChanges({
    required AttributionState attrState,
    required List<FileChange> changes,
  }) {
    final newFileStates =
        Map<String, FileAttributionState>.from(attrState.fileStates);

    for (final change in changes) {
      final effectiveMtime =
          change.mtime ?? DateTime.now().millisecondsSinceEpoch;

      if (change.type == 'deleted') {
        final normalizedPath = normalizeFilePath(change.path);
        final existingState = newFileStates[normalizedPath];
        final existingContribution = existingState?.neomClawContribution ?? 0;
        final deletedChars = change.oldContent.length;

        newFileStates[normalizedPath] = FileAttributionState(
          contentHash: '',
          neomClawContribution: existingContribution + deletedChars,
          mtime: effectiveMtime,
        );
      } else {
        final newFileState = _computeFileModificationState(
          existingFileStates: newFileStates,
          filePath: change.path,
          oldContent: change.oldContent,
          newContent: change.newContent,
          mtime: effectiveMtime,
        );
        if (newFileState != null) {
          final normalizedPath = normalizeFilePath(change.path);
          newFileStates[normalizedPath] = newFileState;
        }
      }
    }

    return attrState.copyWith(fileStates: newFileStates);
  }

  // -------------------------------------------------------------------------
  // Calculate commit attribution
  // -------------------------------------------------------------------------

  /// Calculate final attribution for staged files.
  Future<AttributionData> calculateCommitAttribution({
    required List<AttributionState> states,
    required List<String> stagedFiles,
  }) async {
    final cwd = getAttributionRepoRoot();

    final files = <String, FileAttribution>{};
    final excludedGenerated = <String>[];
    final surfaces = <String>{};
    final surfaceCounts = <String, int>{};

    var totalNeomClawChars = 0;
    var totalHumanChars = 0;

    // Merge file states from all sessions.
    final mergedFileStates = <String, FileAttributionState>{};
    final mergedBaselines = <String, BaselineEntry>{};

    for (final s in states) {
      surfaces.add(s.surface);

      for (final entry in s.sessionBaselines.entries) {
        mergedBaselines.putIfAbsent(entry.key, () => entry.value);
      }

      for (final entry in s.fileStates.entries) {
        final existing = mergedFileStates[entry.key];
        if (existing != null) {
          mergedFileStates[entry.key] = FileAttributionState(
            contentHash: entry.value.contentHash,
            neomClawContribution:
                existing.neomClawContribution + entry.value.neomClawContribution,
            mtime: entry.value.mtime,
          );
        } else {
          mergedFileStates[entry.key] = entry.value;
        }
      }
    }

    // Process files.
    for (final file in stagedFiles) {
      if (isGeneratedFileChecker?.call(file) ?? false) {
        excludedGenerated.add(file);
        continue;
      }

      final absPath = '$cwd/$file';
      final fileState = mergedFileStates[file];
      final baseline = mergedBaselines[file];
      final fileSurface = states.isNotEmpty ? states.first.surface : 'cli';

      var neomClawChars = 0;
      var humanChars = 0;

      final deleted = await isFileDeleted(file);

      if (deleted) {
        if (fileState != null) {
          neomClawChars = fileState.neomClawContribution;
        } else {
          final diffSize = await getGitDiffSize(file);
          humanChars = diffSize > 0 ? diffSize : 100;
        }
      } else {
        try {
          final fileStat = await FileStat.stat(absPath);
          if (fileStat.type == FileSystemEntityType.notFound) continue;

          if (fileState != null) {
            neomClawChars = fileState.neomClawContribution;
          } else if (baseline != null) {
            final diffSize = await getGitDiffSize(file);
            humanChars = diffSize > 0 ? diffSize : fileStat.size;
          } else {
            humanChars = fileStat.size;
          }
        } catch (_) {
          continue;
        }
      }

      neomClawChars = max(0, neomClawChars);
      humanChars = max(0, humanChars);

      final total = neomClawChars + humanChars;
      final percent =
          total > 0 ? (neomClawChars / total * 100).round() : 0;

      files[file] = FileAttribution(
        neomClawChars: neomClawChars,
        humanChars: humanChars,
        percent: percent,
        surface: fileSurface,
      );

      totalNeomClawChars += neomClawChars;
      totalHumanChars += humanChars;
      surfaceCounts[fileSurface] =
          (surfaceCounts[fileSurface] ?? 0) + neomClawChars;
    }

    final totalChars = totalNeomClawChars + totalHumanChars;
    final neomClawPercent =
        totalChars > 0 ? (totalNeomClawChars / totalChars * 100).round() : 0;

    final surfaceBreakdown = <String, SurfaceBreakdownEntry>{};
    for (final entry in surfaceCounts.entries) {
      final percent =
          totalChars > 0 ? (entry.value / totalChars * 100).round() : 0;
      surfaceBreakdown[entry.key] =
          SurfaceBreakdownEntry(neomClawChars: entry.value, percent: percent);
    }

    return AttributionData(
      summary: AttributionSummary(
        neomClawPercent: neomClawPercent,
        neomClawChars: totalNeomClawChars,
        humanChars: totalHumanChars,
        surfaces: surfaces.toList(),
      ),
      files: files,
      surfaceBreakdown: surfaceBreakdown,
      excludedGenerated: excludedGenerated,
      sessions: [sessionId],
    );
  }

  // -------------------------------------------------------------------------
  // Git diff size
  // -------------------------------------------------------------------------

  /// Get the size of changes for a file from git diff.
  Future<int> getGitDiffSize(String filePath) async {
    final cwd = getAttributionRepoRoot();

    try {
      final result = await Process.run(
        gitExe,
        ['diff', '--cached', '--stat', '--', filePath],
        workingDirectory: cwd,
      );

      if (result.exitCode != 0 || (result.stdout as String).isEmpty) {
        return 0;
      }

      final lines =
          (result.stdout as String).split('\n').where((l) => l.isNotEmpty);
      var totalChanges = 0;

      for (final line in lines) {
        if (line.contains('file changed') || line.contains('files changed')) {
          final insertMatch = RegExp(r'(\d+) insertions?').firstMatch(line);
          final deleteMatch = RegExp(r'(\d+) deletions?').firstMatch(line);

          final insertions =
              int.tryParse(insertMatch?.group(1) ?? '') ?? 0;
          final deletions =
              int.tryParse(deleteMatch?.group(1) ?? '') ?? 0;
          totalChanges += (insertions + deletions) * 40;
        }
      }

      return totalChanges;
    } catch (_) {
      return 0;
    }
  }

  // -------------------------------------------------------------------------
  // Is file deleted
  // -------------------------------------------------------------------------

  /// Check if a file was deleted in the staged changes.
  Future<bool> isFileDeleted(String filePath) async {
    final cwd = getAttributionRepoRoot();

    try {
      final result = await Process.run(
        gitExe,
        ['diff', '--cached', '--name-status', '--', filePath],
        workingDirectory: cwd,
      );

      if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
        return (result.stdout as String).trim().startsWith('D\t');
      }
    } catch (_) {
      // Ignore errors.
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // Get staged files
  // -------------------------------------------------------------------------

  /// Get staged files from git.
  Future<List<String>> getStagedFiles() async {
    final cwd = getAttributionRepoRoot();

    try {
      final result = await Process.run(
        gitExe,
        ['diff', '--cached', '--name-only'],
        workingDirectory: cwd,
      );

      if (result.exitCode == 0 && (result.stdout as String).isNotEmpty) {
        return (result.stdout as String)
            .split('\n')
            .where((l) => l.isNotEmpty)
            .toList();
      }
    } catch (_) {
      // Ignore errors.
    }

    return [];
  }

  // -------------------------------------------------------------------------
  // Is git transient state
  // -------------------------------------------------------------------------

  /// Check if we're in a transient git state (rebase, merge, cherry-pick).
  Future<bool> isGitTransientState() async {
    final gitDir = await resolveGitDir?.call(getAttributionRepoRoot());
    if (gitDir == null) return false;

    const indicators = [
      'rebase-merge',
      'rebase-apply',
      'MERGE_HEAD',
      'CHERRY_PICK_HEAD',
      'BISECT_LOG',
    ];

    for (final indicator in indicators) {
      final entity = File('$gitDir/$indicator');
      if (await entity.exists()) return true;
      final dir = Directory('$gitDir/$indicator');
      if (await dir.exists()) return true;
    }

    return false;
  }

  // -------------------------------------------------------------------------
  // Snapshot / restore
  // -------------------------------------------------------------------------

  /// Convert attribution state to snapshot message for persistence.
  AttributionSnapshotMessage stateToSnapshotMessage(
    AttributionState attrState,
    String messageId,
  ) {
    return AttributionSnapshotMessage(
      messageId: messageId,
      surface: attrState.surface,
      fileStates: attrState.fileStates,
      promptCount: attrState.promptCount,
      promptCountAtLastCommit: attrState.promptCountAtLastCommit,
      permissionPromptCount: attrState.permissionPromptCount,
      permissionPromptCountAtLastCommit:
          attrState.permissionPromptCountAtLastCommit,
      escapeCount: attrState.escapeCount,
      escapeCountAtLastCommit: attrState.escapeCountAtLastCommit,
    );
  }

  /// Restore attribution state from snapshot messages.
  AttributionState restoreAttributionStateFromSnapshots(
    List<AttributionSnapshotMessage> snapshots,
  ) {
    final attrState = createEmptyAttributionState();

    // The last snapshot has the most recent count for every path.
    final lastSnapshot = snapshots.isNotEmpty ? snapshots.last : null;
    if (lastSnapshot == null) return attrState;

    final fileStates = <String, FileAttributionState>{};
    for (final entry in lastSnapshot.fileStates.entries) {
      fileStates[entry.key] = entry.value;
    }

    return attrState.copyWith(
      surface: lastSnapshot.surface,
      fileStates: fileStates,
      promptCount: lastSnapshot.promptCount,
      promptCountAtLastCommit: lastSnapshot.promptCountAtLastCommit,
      permissionPromptCount: lastSnapshot.permissionPromptCount,
      permissionPromptCountAtLastCommit:
          lastSnapshot.permissionPromptCountAtLastCommit,
      escapeCount: lastSnapshot.escapeCount,
      escapeCountAtLastCommit: lastSnapshot.escapeCountAtLastCommit,
    );
  }

  /// Restore attribution state from log snapshots on session resume.
  void attributionRestoreStateFromLog(
    List<AttributionSnapshotMessage> attributionSnapshots,
  ) {
    state.value =
        restoreAttributionStateFromSnapshots(attributionSnapshots);
  }

  /// Increment promptCount and save an attribution snapshot.
  AttributionState incrementPromptCount({
    required AttributionState attribution,
    required void Function(AttributionSnapshotMessage) saveSnapshot,
  }) {
    final newAttribution = attribution.copyWith(
      promptCount: attribution.promptCount + 1,
    );
    final snapshot = stateToSnapshotMessage(
      newAttribution,
      DateTime.now().microsecondsSinceEpoch.toString(),
    );
    saveSnapshot(snapshot);
    return newAttribution;
  }
}
