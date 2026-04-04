/// File access history tracking with backup/restore support.
///
/// Ported from neom_claw/src/utils/fileHistory.ts (1115 LOC).
///
/// Provides checkpoint-based file history that tracks edits, creates backups,
/// allows rewinding to previous snapshots, and computes diff statistics.
library;

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

/// Maximum number of snapshots retained in memory.
const int maxSnapshots = 100;

/// Enable debug state dumping (set to true only for local debugging).
const bool _enableDumpState = false;

// ---------------------------------------------------------------------------
// Types — BackupFileName
// ---------------------------------------------------------------------------

/// A backup file name, or null if the file does not exist in this version.
typedef BackupFileName = String?;

// ---------------------------------------------------------------------------
// Types — FileHistoryBackup
// ---------------------------------------------------------------------------

/// A single file's backup metadata.
class FileHistoryBackup {
  const FileHistoryBackup({
    required this.backupFileName,
    required this.version,
    required this.backupTime,
  });

  /// Null means the file does not exist in this version.
  final BackupFileName backupFileName;
  final int version;
  final DateTime backupTime;

  factory FileHistoryBackup.fromJson(Map<String, dynamic> json) {
    return FileHistoryBackup(
      backupFileName: json['backupFileName'] as String?,
      version: (json['version'] as num).toInt(),
      backupTime: DateTime.parse(json['backupTime'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'backupFileName': backupFileName,
    'version': version,
    'backupTime': backupTime.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Types — FileHistorySnapshot
// ---------------------------------------------------------------------------

/// A point-in-time snapshot of all tracked file states.
class FileHistorySnapshot {
  FileHistorySnapshot({
    required this.messageId,
    required this.trackedFileBackups,
    required this.timestamp,
  });

  /// The associated message ID for this snapshot.
  final String messageId;

  /// Map of file paths to backup versions.
  final Map<String, FileHistoryBackup> trackedFileBackups;
  final DateTime timestamp;

  FileHistorySnapshot copyWith({
    String? messageId,
    Map<String, FileHistoryBackup>? trackedFileBackups,
    DateTime? timestamp,
  }) {
    return FileHistorySnapshot(
      messageId: messageId ?? this.messageId,
      trackedFileBackups: trackedFileBackups ?? this.trackedFileBackups,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory FileHistorySnapshot.fromJson(Map<String, dynamic> json) {
    final backups =
        (json['trackedFileBackups'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(
            k,
            FileHistoryBackup.fromJson(v as Map<String, dynamic>),
          ),
        ) ??
        {};
    return FileHistorySnapshot(
      messageId: json['messageId'] as String,
      trackedFileBackups: backups,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'messageId': messageId,
    'trackedFileBackups': trackedFileBackups.map(
      (k, v) => MapEntry(k, v.toJson()),
    ),
    'timestamp': timestamp.toIso8601String(),
  };
}

// ---------------------------------------------------------------------------
// Types — FileHistoryState
// ---------------------------------------------------------------------------

/// The full file history state.
class FileHistoryState {
  FileHistoryState({
    List<FileHistorySnapshot>? snapshots,
    Set<String>? trackedFiles,
    this.snapshotSequence = 0,
  }) : snapshots = snapshots ?? [],
       trackedFiles = trackedFiles ?? {};

  final List<FileHistorySnapshot> snapshots;
  final Set<String> trackedFiles;

  /// Monotonically-increasing counter incremented on every snapshot, even when
  /// old snapshots are evicted. Used as an activity signal.
  final int snapshotSequence;

  FileHistoryState copyWith({
    List<FileHistorySnapshot>? snapshots,
    Set<String>? trackedFiles,
    int? snapshotSequence,
  }) {
    return FileHistoryState(
      snapshots: snapshots ?? this.snapshots,
      trackedFiles: trackedFiles ?? this.trackedFiles,
      snapshotSequence: snapshotSequence ?? this.snapshotSequence,
    );
  }
}

// ---------------------------------------------------------------------------
// Types — DiffStats
// ---------------------------------------------------------------------------

/// Diff statistics for a snapshot comparison.
class DiffStats {
  const DiffStats({
    this.filesChanged = const [],
    this.insertions = 0,
    this.deletions = 0,
  });

  final List<String> filesChanged;
  final int insertions;
  final int deletions;
}

// ---------------------------------------------------------------------------
// FileHistoryManager — SintController
// ---------------------------------------------------------------------------

/// Manages file checkpoint history, backups, and rewinding.
///
/// Usage:
/// ```dart
/// final manager = Sint.put(FileHistoryManager(
///   configHomeDir: '/home/user/.neomclaw',
///   sessionId: 'abc-123',
///   originalCwd: '/path/to/project',
/// ));
/// ```
class FileHistoryManager extends SintController {
  FileHistoryManager({
    required this.configHomeDir,
    required this.sessionId,
    String? originalCwd,
    this.fileCheckpointingEnabled = true,
    this.disableFileCheckpointing = false,
    this.isNonInteractiveSession = false,
    this.enableSdkFileCheckpointing = false,
  }) : _originalCwd = originalCwd ?? Directory.current.path;

  final String configHomeDir;
  final String sessionId;
  final String _originalCwd;

  // Configuration flags.
  final bool fileCheckpointingEnabled;
  final bool disableFileCheckpointing;
  final bool isNonInteractiveSession;
  final bool enableSdkFileCheckpointing;

  /// Reactive file history state.
  final Rx<FileHistoryState> state = FileHistoryState().obs;

  // -------------------------------------------------------------------------
  // Feature check
  // -------------------------------------------------------------------------

  /// Whether file history is enabled.
  bool fileHistoryEnabled() {
    if (isNonInteractiveSession) {
      return _fileHistoryEnabledSdk();
    }
    return fileCheckpointingEnabled && !disableFileCheckpointing;
  }

  bool _fileHistoryEnabledSdk() {
    return enableSdkFileCheckpointing && !disableFileCheckpointing;
  }

  // -------------------------------------------------------------------------
  // Path helpers
  // -------------------------------------------------------------------------

  String _resolveBackupPath(String backupFileName, [String? sid]) {
    return '$configHomeDir/file-history/${sid ?? sessionId}/$backupFileName';
  }

  String _getBackupFileName(String filePath, int version) {
    final hash = _sha256Hex(filePath).substring(0, 16);
    return '$hash@v$version';
  }

  /// Use the relative path as the key to reduce session storage space.
  String _maybeShortenFilePath(String filePath) {
    if (!_isAbsolute(filePath)) return filePath;
    if (filePath.startsWith(_originalCwd)) {
      return _relativePath(filePath, _originalCwd);
    }
    return filePath;
  }

  String _maybeExpandFilePath(String filePath) {
    if (_isAbsolute(filePath)) return filePath;
    return '$_originalCwd/$filePath';
  }

  // -------------------------------------------------------------------------
  // Track edit
  // -------------------------------------------------------------------------

  /// Tracks a file edit (and add) by creating a backup of its current contents.
  ///
  /// This must be called before the file is actually added or edited, so we can
  /// save its contents before the edit.
  Future<void> fileHistoryTrackEdit(String filePath, String messageId) async {
    if (!fileHistoryEnabled()) return;

    final trackingPath = _maybeShortenFilePath(filePath);

    // Phase 1: check if backup is needed.
    final currentState = state.value;
    final mostRecent = currentState.snapshots.isNotEmpty
        ? currentState.snapshots.last
        : null;
    if (mostRecent == null) return;
    if (mostRecent.trackedFileBackups.containsKey(trackingPath)) return;

    // Phase 2: async backup.
    FileHistoryBackup backup;
    try {
      backup = await _createBackup(filePath, 1);
    } catch (_) {
      return;
    }

    // Phase 3: commit.
    final s = state.value;
    final recentSnapshot = s.snapshots.isNotEmpty ? s.snapshots.last : null;
    if (recentSnapshot == null ||
        recentSnapshot.trackedFileBackups.containsKey(trackingPath)) {
      return;
    }

    final updatedTrackedFiles = Set<String>.from(s.trackedFiles)
      ..add(trackingPath);

    final updatedMostRecentSnapshot = recentSnapshot.copyWith(
      trackedFileBackups: {
        ...recentSnapshot.trackedFileBackups,
        trackingPath: backup,
      },
    );

    final updatedSnapshots = List<FileHistorySnapshot>.from(s.snapshots);
    updatedSnapshots[updatedSnapshots.length - 1] = updatedMostRecentSnapshot;

    state.value = s.copyWith(
      snapshots: updatedSnapshots,
      trackedFiles: updatedTrackedFiles,
    );

    _maybeDumpStateForDebug(state.value);
  }

  // -------------------------------------------------------------------------
  // Make snapshot
  // -------------------------------------------------------------------------

  /// Adds a snapshot in the file history and backs up any modified tracked files.
  Future<void> fileHistoryMakeSnapshot(String messageId) async {
    if (!fileHistoryEnabled()) return;

    final captured = state.value;

    // Phase 2: do all IO async.
    final trackedFileBackups = <String, FileHistoryBackup>{};
    final mostRecentSnapshot = captured.snapshots.isNotEmpty
        ? captured.snapshots.last
        : null;

    if (mostRecentSnapshot != null) {
      await Future.wait(
        captured.trackedFiles.map((trackingPath) async {
          try {
            final filePath = _maybeExpandFilePath(trackingPath);
            final latestBackup =
                mostRecentSnapshot.trackedFileBackups[trackingPath];
            final nextVersion = latestBackup != null
                ? latestBackup.version + 1
                : 1;

            // Stat the file; ENOENT means the tracked file was deleted.
            FileStat? fileStats;
            try {
              fileStats = await FileStat.stat(filePath);
              if (fileStats.type == FileSystemEntityType.notFound) {
                fileStats = null;
              }
            } catch (_) {
              fileStats = null;
            }

            if (fileStats == null) {
              trackedFileBackups[trackingPath] = FileHistoryBackup(
                backupFileName: null,
                version: nextVersion,
                backupTime: DateTime.now(),
              );
              return;
            }

            // File exists — check if it needs to be backed up.
            if (latestBackup != null &&
                latestBackup.backupFileName != null &&
                !(await _checkOriginFileChanged(
                  filePath,
                  latestBackup.backupFileName!,
                ))) {
              trackedFileBackups[trackingPath] = latestBackup;
              return;
            }

            trackedFileBackups[trackingPath] = await _createBackup(
              filePath,
              nextVersion,
            );
          } catch (_) {
            // Skip this file on error.
          }
        }),
      );
    }

    // Phase 3: commit the new snapshot.
    final s = state.value;
    final lastSnapshot = s.snapshots.isNotEmpty ? s.snapshots.last : null;
    if (lastSnapshot != null) {
      for (final trackingPath in s.trackedFiles) {
        if (trackedFileBackups.containsKey(trackingPath)) continue;
        final inherited = lastSnapshot.trackedFileBackups[trackingPath];
        if (inherited != null) trackedFileBackups[trackingPath] = inherited;
      }
    }

    final newSnapshot = FileHistorySnapshot(
      messageId: messageId,
      trackedFileBackups: trackedFileBackups,
      timestamp: DateTime.now(),
    );

    final allSnapshots = [...s.snapshots, newSnapshot];
    final trimmed = allSnapshots.length > maxSnapshots
        ? allSnapshots.sublist(allSnapshots.length - maxSnapshots)
        : allSnapshots;

    state.value = s.copyWith(
      snapshots: trimmed,
      snapshotSequence: s.snapshotSequence + 1,
    );

    _maybeDumpStateForDebug(state.value);
  }

  // -------------------------------------------------------------------------
  // Rewind
  // -------------------------------------------------------------------------

  /// Rewinds the file system to a previous snapshot.
  Future<void> fileHistoryRewind(String messageId) async {
    if (!fileHistoryEnabled()) return;

    final captured = state.value;
    final targetSnapshot = captured.snapshots.lastWhere(
      (snapshot) => snapshot.messageId == messageId,
      orElse: () =>
          throw StateError('FileHistory: Snapshot for $messageId not found'),
    );

    final filesChanged = await _applySnapshot(captured, targetSnapshot);
    // Log: filesChanged.length files were restored.
    // ignore: unused_local_variable
    final ignored = filesChanged;
  }

  // -------------------------------------------------------------------------
  // Can restore
  // -------------------------------------------------------------------------

  /// Whether we can restore to a given message's snapshot.
  bool fileHistoryCanRestore(String messageId) {
    if (!fileHistoryEnabled()) return false;
    return state.value.snapshots.any(
      (snapshot) => snapshot.messageId == messageId,
    );
  }

  // -------------------------------------------------------------------------
  // Diff stats
  // -------------------------------------------------------------------------

  /// Computes diff stats for a file snapshot by counting the number of files
  /// that would be changed if reverting to that snapshot.
  Future<DiffStats?> fileHistoryGetDiffStats(String messageId) async {
    if (!fileHistoryEnabled()) return null;

    final s = state.value;
    final targetSnapshot = s.snapshots.cast<FileHistorySnapshot?>().lastWhere(
      (snapshot) => snapshot?.messageId == messageId,
      orElse: () => null,
    );
    if (targetSnapshot == null) return null;

    final filesChanged = <String>[];
    var insertions = 0;
    var deletions = 0;

    await Future.wait(
      s.trackedFiles.map((trackingPath) async {
        try {
          final filePath = _maybeExpandFilePath(trackingPath);
          final targetBackup = targetSnapshot.trackedFileBackups[trackingPath];

          final backupFileName = targetBackup != null
              ? targetBackup.backupFileName
              : _getBackupFileNameFirstVersion(trackingPath, s);

          if (backupFileName == null && targetBackup == null) {
            // Cannot resolve backup — skip.
            return;
          }

          final stats = await _computeDiffStatsForFile(
            filePath,
            backupFileName,
          );
          if (stats != null && (stats.insertions > 0 || stats.deletions > 0)) {
            filesChanged.add(filePath);
            insertions += stats.insertions;
            deletions += stats.deletions;
          } else if (backupFileName == null && await File(filePath).exists()) {
            // Zero-byte file created after snapshot.
            filesChanged.add(filePath);
          }
        } catch (_) {
          // Skip on error.
        }
      }),
    );

    return DiffStats(
      filesChanged: filesChanged,
      insertions: insertions,
      deletions: deletions,
    );
  }

  // -------------------------------------------------------------------------
  // Has any changes
  // -------------------------------------------------------------------------

  /// Lightweight boolean-only check: would rewinding to this message change
  /// any file on disk?
  Future<bool> fileHistoryHasAnyChanges(String messageId) async {
    if (!fileHistoryEnabled()) return false;

    final s = state.value;
    final targetSnapshot = s.snapshots.cast<FileHistorySnapshot?>().lastWhere(
      (snapshot) => snapshot?.messageId == messageId,
      orElse: () => null,
    );
    if (targetSnapshot == null) return false;

    for (final trackingPath in s.trackedFiles) {
      try {
        final filePath = _maybeExpandFilePath(trackingPath);
        final targetBackup = targetSnapshot.trackedFileBackups[trackingPath];
        final backupFileName = targetBackup != null
            ? targetBackup.backupFileName
            : _getBackupFileNameFirstVersion(trackingPath, s);

        if (backupFileName == null) {
          if (await File(filePath).exists()) return true;
          continue;
        }
        if (await _checkOriginFileChanged(filePath, backupFileName)) {
          return true;
        }
      } catch (_) {
        // Skip on error.
      }
    }
    return false;
  }

  // -------------------------------------------------------------------------
  // Apply snapshot (internal)
  // -------------------------------------------------------------------------

  /// Applies the given file snapshot state to tracked files.
  Future<List<String>> _applySnapshot(
    FileHistoryState s,
    FileHistorySnapshot targetSnapshot,
  ) async {
    final filesChanged = <String>[];

    for (final trackingPath in s.trackedFiles) {
      try {
        final filePath = _maybeExpandFilePath(trackingPath);
        final targetBackup = targetSnapshot.trackedFileBackups[trackingPath];

        final backupFileName = targetBackup != null
            ? targetBackup.backupFileName
            : _getBackupFileNameFirstVersion(trackingPath, s);

        if (backupFileName == null && targetBackup == null) continue;

        if (backupFileName == null) {
          // File did not exist at target version — delete if present.
          try {
            await File(filePath).delete();
            filesChanged.add(filePath);
          } on FileSystemException {
            // Already absent.
          }
          continue;
        }

        if (await _checkOriginFileChanged(filePath, backupFileName)) {
          await _restoreBackup(filePath, backupFileName);
          filesChanged.add(filePath);
        }
      } catch (_) {
        // Skip on error.
      }
    }
    return filesChanged;
  }

  // -------------------------------------------------------------------------
  // Check origin file changed
  // -------------------------------------------------------------------------

  /// Checks if the original file has been changed compared to the backup.
  Future<bool> _checkOriginFileChanged(
    String originalFile,
    String backupFileName,
  ) async {
    final backupPath = _resolveBackupPath(backupFileName);

    FileStat? originalStats;
    try {
      originalStats = await FileStat.stat(originalFile);
      if (originalStats.type == FileSystemEntityType.notFound) {
        originalStats = null;
      }
    } catch (_) {
      originalStats = null;
    }

    FileStat? backupStats;
    try {
      backupStats = await FileStat.stat(backupPath);
      if (backupStats.type == FileSystemEntityType.notFound) {
        backupStats = null;
      }
    } catch (_) {
      backupStats = null;
    }

    // One exists, one missing -> changed.
    if ((originalStats == null) != (backupStats == null)) return true;

    // Both missing -> no change.
    if (originalStats == null || backupStats == null) return false;

    // Check file size.
    if (originalStats.size != backupStats.size) return true;

    // Mtime optimization.
    if (originalStats.modified.isBefore(backupStats.modified)) return false;

    // Full content comparison.
    try {
      final originalContent = await File(originalFile).readAsString();
      final backupContent = await File(backupPath).readAsString();
      return originalContent != backupContent;
    } catch (_) {
      return true;
    }
  }

  // -------------------------------------------------------------------------
  // Compute diff stats for file
  // -------------------------------------------------------------------------

  Future<DiffStats?> _computeDiffStatsForFile(
    String originalFile,
    String? backupFileName,
  ) async {
    var insertions = 0;
    var deletions = 0;

    try {
      final backupPath = backupFileName != null
          ? _resolveBackupPath(backupFileName)
          : null;

      final originalContent = await _readFileOrNull(originalFile);
      final backupContent = backupPath != null
          ? await _readFileOrNull(backupPath)
          : null;

      if (originalContent == null && backupContent == null) {
        return const DiffStats();
      }

      // Simple line-based diff.
      final originalLines = (originalContent ?? '').split('\n');
      final backupLines = (backupContent ?? '').split('\n');

      // Count added/removed lines using a simple comparison.
      final originalSet = originalLines.toSet();
      final backupSet = backupLines.toSet();

      for (final line in originalLines) {
        if (!backupSet.contains(line)) insertions++;
      }
      for (final line in backupLines) {
        if (!originalSet.contains(line)) deletions++;
      }
    } catch (_) {
      // Error generating diff stats.
    }

    return DiffStats(
      filesChanged: [originalFile],
      insertions: insertions,
      deletions: deletions,
    );
  }

  // -------------------------------------------------------------------------
  // Create backup
  // -------------------------------------------------------------------------

  /// Creates a backup of the file at [filePath].
  Future<FileHistoryBackup> _createBackup(String filePath, int version) async {
    final backupFileName = _getBackupFileName(filePath, version);
    final backupPath = _resolveBackupPath(backupFileName);

    // Stat first: if the source is missing, record a null backup.
    FileStat srcStats;
    try {
      srcStats = await FileStat.stat(filePath);
      if (srcStats.type == FileSystemEntityType.notFound) {
        return FileHistoryBackup(
          backupFileName: null,
          version: version,
          backupTime: DateTime.now(),
        );
      }
    } catch (_) {
      return FileHistoryBackup(
        backupFileName: null,
        version: version,
        backupTime: DateTime.now(),
      );
    }

    // Copy file. Lazy mkdir.
    try {
      await File(filePath).copy(backupPath);
    } on FileSystemException {
      await Directory(
        backupPath.substring(0, backupPath.lastIndexOf('/')),
      ).create(recursive: true);
      await File(filePath).copy(backupPath);
    }

    return FileHistoryBackup(
      backupFileName: backupFileName,
      version: version,
      backupTime: DateTime.now(),
    );
  }

  // -------------------------------------------------------------------------
  // Restore backup
  // -------------------------------------------------------------------------

  /// Restores a file from its backup path.
  Future<void> _restoreBackup(String filePath, String backupFileName) async {
    final backupPath = _resolveBackupPath(backupFileName);

    // Check backup exists.
    final backupFile = File(backupPath);
    if (!await backupFile.exists()) return;

    // Copy backup to destination. Lazy mkdir.
    try {
      await backupFile.copy(filePath);
    } on FileSystemException {
      await Directory(
        filePath.substring(0, filePath.lastIndexOf('/')),
      ).create(recursive: true);
      await backupFile.copy(filePath);
    }
  }

  // -------------------------------------------------------------------------
  // Get first version backup
  // -------------------------------------------------------------------------

  /// Gets the first (earliest) backup version for a file.
  BackupFileName? _getBackupFileNameFirstVersion(
    String trackingPath,
    FileHistoryState s,
  ) {
    for (final snapshot in s.snapshots) {
      final backup = snapshot.trackedFileBackups[trackingPath];
      if (backup != null && backup.version == 1) {
        return backup.backupFileName;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Restore state from log
  // -------------------------------------------------------------------------

  /// Restores file history snapshot state from log data.
  void fileHistoryRestoreStateFromLog(
    List<FileHistorySnapshot> fileHistorySnapshots,
  ) {
    if (!fileHistoryEnabled()) return;

    final snapshots = <FileHistorySnapshot>[];
    final trackedFiles = <String>{};

    for (final snapshot in fileHistorySnapshots) {
      final trackedFileBackups = <String, FileHistoryBackup>{};
      for (final entry in snapshot.trackedFileBackups.entries) {
        final trackingPath = _maybeShortenFilePath(entry.key);
        trackedFiles.add(trackingPath);
        trackedFileBackups[trackingPath] = entry.value;
      }
      snapshots.add(snapshot.copyWith(trackedFileBackups: trackedFileBackups));
    }

    state.value = FileHistoryState(
      snapshots: snapshots,
      trackedFiles: trackedFiles,
      snapshotSequence: snapshots.length,
    );
  }

  // -------------------------------------------------------------------------
  // Copy file history for resume
  // -------------------------------------------------------------------------

  /// Copy file history snapshots for session resume.
  Future<void> copyFileHistoryForResume({
    required List<FileHistorySnapshot> fileHistorySnapshots,
    required String? previousSessionId,
  }) async {
    if (!fileHistoryEnabled()) return;
    if (fileHistorySnapshots.isEmpty || previousSessionId == null) return;
    if (previousSessionId == sessionId) return;

    try {
      final newBackupDir = Directory('$configHomeDir/file-history/$sessionId');
      await newBackupDir.create(recursive: true);

      for (final snapshot in fileHistorySnapshots) {
        final backupEntries = snapshot.trackedFileBackups.values.where(
          (b) => b.backupFileName != null,
        );

        for (final backup in backupEntries) {
          final oldBackupPath = _resolveBackupPath(
            backup.backupFileName!,
            previousSessionId,
          );
          final newBackupPath = '${newBackupDir.path}/${backup.backupFileName}';

          try {
            // Try hard link first.
            await Link(newBackupPath).create(oldBackupPath);
          } catch (_) {
            try {
              // Fallback to copy.
              await File(oldBackupPath).copy(newBackupPath);
            } catch (_) {
              // Skip on error.
            }
          }
        }
      }
    } catch (_) {
      // Log error.
    }
  }

  // -------------------------------------------------------------------------
  // Private utility helpers
  // -------------------------------------------------------------------------

  static Future<String?> _readFileOrNull(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }

  static bool _isAbsolute(String path) => path.startsWith('/');

  static String _relativePath(String fullPath, String base) {
    if (fullPath.startsWith(base)) {
      var rel = fullPath.substring(base.length);
      if (rel.startsWith('/')) rel = rel.substring(1);
      return rel;
    }
    return fullPath;
  }

  static String _sha256Hex(String input) {
    // Simple hash for file path -> backup name mapping.
    // In production, use dart:crypto or crypto package.
    var hash = 0;
    for (var i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash + input.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  void _maybeDumpStateForDebug(FileHistoryState s) {
    if (_enableDumpState) {
      // ignore: avoid_print
      print(
        jsonEncode({
          'snapshots': s.snapshots.length,
          'trackedFiles': s.trackedFiles.length,
          'snapshotSequence': s.snapshotSequence,
        }),
      );
    }
  }
}
