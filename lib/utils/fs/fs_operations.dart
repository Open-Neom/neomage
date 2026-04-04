// ---------------------------------------------------------------------------
// fs_operations.dart -- Filesystem operations, range reading, generated file
// detection. Ported from:
//   fsOperations.ts (770 LOC)
//   readFileInRange.ts (383 LOC)
//   generatedFiles.ts (136 LOC)
// ---------------------------------------------------------------------------

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

// ============================================================================
// FsOperations -- abstract interface
// ============================================================================

/// File stat result mirroring Node's fs.Stats.
class FileStat {
  final int size;
  final DateTime modified;
  final double mtimeMs;
  final FileSystemEntityType type;
  final bool isSymLink;

  FileStat({
    required this.size,
    required this.modified,
    required this.mtimeMs,
    required this.type,
    this.isSymLink = false,
  });

  bool get isFile => type == FileSystemEntityType.file;
  bool get isDirectory => type == FileSystemEntityType.directory;
  bool get isSymbolicLink => isSymLink;

  /// Returns true if this is a FIFO (named pipe).
  bool isFIFO() => false; // Dart doesn't expose FIFO type directly
  /// Returns true if this is a socket.
  bool isSocket() => false;

  /// Returns true if this is a character device.
  bool isCharacterDevice() => false;

  /// Returns true if this is a block device.
  bool isBlockDevice() => false;
}

/// Directory entry with file type information.
class Dirent {
  final String name;
  final FileSystemEntityType type;
  final bool isSymLink;

  Dirent({required this.name, required this.type, this.isSymLink = false});

  bool get isFile => type == FileSystemEntityType.file;
  bool get isDirectory => type == FileSystemEntityType.directory;
  bool get isSymbolicLink => isSymLink;
}

/// Read result for partial file reads.
class ReadSyncResult {
  final Uint8List buffer;
  final int bytesRead;

  ReadSyncResult({required this.buffer, required this.bytesRead});
}

/// Simplified filesystem operations interface based on dart:io.
/// Provides a subset of commonly used sync operations with type safety.
/// Allows abstraction for alternative implementations (e.g., mock, virtual).
abstract class FsOperations {
  // File access and information operations

  /// Gets the current working directory.
  String cwd();

  /// Checks if a file or directory exists.
  bool existsSync(String path);

  /// Gets file stats asynchronously.
  Future<FileStat> stat(String path);

  /// Lists directory contents with file type information asynchronously.
  Future<List<Dirent>> readdir(String path);

  /// Deletes file asynchronously.
  Future<void> unlink(String path);

  /// Removes an empty directory asynchronously.
  Future<void> rmdir(String path);

  /// Removes files and directories asynchronously (with recursive option).
  Future<void> rm(String path, {bool recursive, bool force});

  /// Creates directory recursively asynchronously.
  Future<void> mkdir(String path, {int? mode});

  /// Reads file content as string asynchronously.
  Future<String> readFile(String path, {String encoding = 'utf-8'});

  /// Renames/moves file asynchronously.
  Future<void> rename(String oldPath, String newPath);

  /// Gets file stats.
  FileStat statSync(String path);

  /// Gets file stats without following symlinks.
  FileStat lstatSync(String path);

  // File content operations

  /// Reads file content as string with specified encoding.
  String readFileSync(String path, {String encoding = 'utf-8'});

  /// Reads raw file bytes as Uint8List.
  Uint8List readFileBytesSync(String path);

  /// Reads specified number of bytes from file start.
  ReadSyncResult readSync(String path, {required int length});

  /// Appends string to file.
  void appendFileSync(String path, String data, {int? mode});

  /// Copies file from source to destination.
  void copyFileSync(String src, String dest);

  /// Deletes file.
  void unlinkSync(String path);

  /// Renames/moves file.
  void renameSync(String oldPath, String newPath);

  /// Creates hard link.
  void linkSync(String target, String path);

  /// Creates symbolic link.
  void symlinkSync(String target, String path, {String? type});

  /// Reads symbolic link.
  String readlinkSync(String path);

  /// Resolves symbolic links and returns the canonical pathname.
  String realpathSync(String path);

  // Directory operations

  /// Creates directory recursively. Mode defaults to 0o777 & ~umask if not specified.
  void mkdirSync(String path, {int? mode});

  /// Lists directory contents with file type information.
  List<Dirent> readdirSync(String path);

  /// Lists directory contents as strings.
  List<String> readdirStringSync(String path);

  /// Checks if the directory is empty.
  bool isDirEmptySync(String path);

  /// Removes an empty directory.
  void rmdirSync(String path);

  /// Removes files and directories (with recursive option).
  void rmSync(String path, {bool recursive, bool force});

  /// Reads raw file bytes as Uint8List asynchronously.
  /// When maxBytes is set, only reads up to that many bytes.
  Future<Uint8List> readFileBytes(String path, {int? maxBytes});
}

// ============================================================================
// SafeResolvePath result
// ============================================================================

/// Result of safeResolvePath.
class SafeResolvePathResult {
  final String resolvedPath;
  final bool isSymlink;
  final bool isCanonical;

  SafeResolvePathResult({
    required this.resolvedPath,
    required this.isSymlink,
    required this.isCanonical,
  });
}

/// Safely resolves a file path, handling symlinks and errors gracefully.
///
/// Error handling strategy:
/// - If the file doesn't exist, returns the original path (allows for file creation)
/// - If symlink resolution fails (broken symlink, permission denied, circular links),
///   returns the original path and marks it as not a symlink
/// - This ensures operations can continue with the original path rather than failing
SafeResolvePathResult safeResolvePath(FsOperations fs, String filePath) {
  // Block UNC paths before any filesystem access to prevent network
  // requests (DNS/SMB) during validation on Windows
  if (filePath.startsWith('//') || filePath.startsWith('\\\\')) {
    return SafeResolvePathResult(
      resolvedPath: filePath,
      isSymlink: false,
      isCanonical: false,
    );
  }

  try {
    // Check for special file types (FIFOs, sockets, devices) before calling realpathSync.
    // realpathSync can block on FIFOs waiting for a writer, causing hangs.
    // If the file doesn't exist, lstatSync throws which the catch
    // below handles by returning the original path (allows file creation).
    final stats = fs.lstatSync(filePath);
    if (stats.isFIFO() ||
        stats.isSocket() ||
        stats.isCharacterDevice() ||
        stats.isBlockDevice()) {
      return SafeResolvePathResult(
        resolvedPath: filePath,
        isSymlink: false,
        isCanonical: false,
      );
    }

    final resolvedPath = fs.realpathSync(filePath);
    return SafeResolvePathResult(
      resolvedPath: resolvedPath,
      isSymlink: resolvedPath != filePath,
      // realpathSync returned: resolvedPath is canonical (all symlinks in
      // all path components resolved). Callers can skip further symlink
      // resolution on this path.
      isCanonical: true,
    );
  } catch (_) {
    // If lstat/realpath fails for any reason (ENOENT, broken symlink,
    // EACCES, ELOOP, etc.), return the original path to allow operations
    // to proceed
    return SafeResolvePathResult(
      resolvedPath: filePath,
      isSymlink: false,
      isCanonical: false,
    );
  }
}

/// Check if a file path is a duplicate and should be skipped.
/// Resolves symlinks to detect duplicates pointing to the same file.
/// If not a duplicate, adds the resolved path to loadedPaths.
///
/// Returns true if the file should be skipped (is duplicate).
bool isDuplicatePath(
  FsOperations fs,
  String filePath,
  Set<String> loadedPaths,
) {
  final result = safeResolvePath(fs, filePath);
  if (loadedPaths.contains(result.resolvedPath)) {
    return true;
  }
  loadedPaths.add(result.resolvedPath);
  return false;
}

/// Resolve the deepest existing ancestor of a path via realpathSync, walking
/// up until it succeeds. Detects dangling symlinks (link entry exists, target
/// doesn't) via lstat and resolves them via readlink.
///
/// Use when the input path may not exist (new file writes) and you need to
/// know where the write would ACTUALLY land after the OS follows symlinks.
///
/// Returns the resolved absolute path with non-existent tail segments
/// rejoined, or null if no symlink was found in any existing ancestor
/// (the path's existing ancestors all resolve to themselves).
///
/// Handles: live parent symlinks, dangling file symlinks, dangling parent
/// symlinks.
String? resolveDeepestExistingAncestorSync(
  FsOperations fs,
  String absolutePath,
) {
  String dir = absolutePath;
  final List<String> segments = [];

  // Walk up using lstat (cheap, O(1)) to find the first existing component.
  // lstat does not follow symlinks, so dangling symlinks are detected here.
  // Only call realpathSync (expensive, O(depth)) once at the end.
  while (dir != p.dirname(dir)) {
    FileStat st;
    try {
      st = fs.lstatSync(dir);
    } catch (_) {
      // lstat failed: truly non-existent. Walk up.
      segments.insert(0, p.basename(dir));
      dir = p.dirname(dir);
      continue;
    }

    if (st.isSymbolicLink) {
      // Found a symlink (live or dangling). Try realpath first (resolves
      // chained symlinks); fall back to readlink for dangling symlinks.
      try {
        final resolved = fs.realpathSync(dir);
        return segments.isEmpty ? resolved : p.joinAll([resolved, ...segments]);
      } catch (_) {
        // Dangling: realpath failed but lstat saw the link entry.
        final target = fs.readlinkSync(dir);
        final absTarget = p.isAbsolute(target)
            ? target
            : p.join(p.dirname(dir), target);
        return segments.isEmpty
            ? absTarget
            : p.joinAll([absTarget, ...segments]);
      }
    }

    // Existing non-symlink component. One realpath call resolves any
    // symlinks in its ancestors. If none, return null (no symlink).
    try {
      final resolved = fs.realpathSync(dir);
      if (resolved != dir) {
        return segments.isEmpty ? resolved : p.joinAll([resolved, ...segments]);
      }
    } catch (_) {
      // realpath can still fail (e.g. EACCES in ancestors). Return
      // null -- we can't resolve, and the logical path is already
      // in pathSet for the caller.
    }
    return null;
  }
  return null;
}

/// Gets all paths that should be checked for permissions.
/// This includes the original path, all intermediate symlink targets in the chain,
/// and the final resolved path.
///
/// For example, if test.txt -> /etc/passwd -> /private/etc/passwd:
/// - test.txt (original path)
/// - /etc/passwd (intermediate symlink target)
/// - /private/etc/passwd (final resolved path)
///
/// This is important for security: a deny rule for /etc/passwd should block
/// access even if the file is actually at /private/etc/passwd (as on macOS).
List<String> getPathsForPermissionCheck(String inputPath) {
  // Expand tilde notation defensively
  String path = inputPath;
  final homeDir = Platform.environment['HOME'] ?? '';
  if (path == '~') {
    path = homeDir;
  } else if (path.startsWith('~/')) {
    path = p.join(homeDir, path.substring(2));
  }

  final pathSet = <String>{};
  final fsImpl = getFsImplementation();

  // Always check the original path
  pathSet.add(path);

  // Block UNC paths before any filesystem access to prevent network
  // requests (DNS/SMB) during validation on Windows
  if (path.startsWith('//') || path.startsWith('\\\\')) {
    return pathSet.toList();
  }

  // Follow the symlink chain, collecting ALL intermediate targets
  try {
    String currentPath = path;
    final visited = <String>{};
    const maxDepth = 40; // Prevent runaway loops, matches typical SYMLOOP_MAX

    for (int depth = 0; depth < maxDepth; depth++) {
      // Prevent infinite loops from circular symlinks
      if (visited.contains(currentPath)) {
        break;
      }
      visited.add(currentPath);

      if (!fsImpl.existsSync(currentPath)) {
        // Path doesn't exist (new file case). existsSync follows symlinks,
        // so this is also reached for DANGLING symlinks.
        if (currentPath == path) {
          final resolved = resolveDeepestExistingAncestorSync(fsImpl, path);
          if (resolved != null) {
            pathSet.add(resolved);
          }
        }
        break;
      }

      final stats = fsImpl.lstatSync(currentPath);

      // Skip special file types that can cause issues
      if (stats.isFIFO() ||
          stats.isSocket() ||
          stats.isCharacterDevice() ||
          stats.isBlockDevice()) {
        break;
      }

      if (!stats.isSymbolicLink) {
        break;
      }

      // Get the immediate symlink target
      final target = fsImpl.readlinkSync(currentPath);

      // If target is relative, resolve it relative to the symlink's directory
      final absoluteTarget = p.isAbsolute(target)
          ? target
          : p.join(p.dirname(currentPath), target);

      // Add this intermediate target to the set
      pathSet.add(absoluteTarget);
      currentPath = absoluteTarget;
    }
  } catch (_) {
    // If anything fails during chain traversal, continue with what we have
  }

  // Also add the final resolved path using realpathSync for completeness
  final safeResult = safeResolvePath(fsImpl, path);
  if (safeResult.isSymlink && safeResult.resolvedPath != path) {
    pathSet.add(safeResult.resolvedPath);
  }

  return pathSet.toList();
}

// ============================================================================
// DartFsOperations -- concrete implementation using dart:io
// ============================================================================

/// Concrete filesystem implementation using dart:io.
class DartFsOperations extends FsOperations {
  @override
  String cwd() => Directory.current.path;

  @override
  bool existsSync(String path) {
    return File(path).existsSync() || Directory(path).existsSync();
  }

  @override
  Future<FileStat> stat(String fsPath) async {
    // Use dart:io FileStat
    final s = await File(fsPath).stat();
    return FileStat(
      size: s.size,
      modified: s.modified,
      mtimeMs: s.modified.millisecondsSinceEpoch.toDouble(),
      type: s.type,
    );
  }

  @override
  Future<List<Dirent>> readdir(String fsPath) async {
    final dir = Directory(fsPath);
    final entries = <Dirent>[];
    await for (final entity in dir.list()) {
      final entityStat = await entity.stat();
      entries.add(
        Dirent(
          name: p.basename(entity.path),
          type: entityStat.type,
          isSymLink: await FileSystemEntity.isLink(entity.path),
        ),
      );
    }
    return entries;
  }

  @override
  Future<void> unlink(String fsPath) async {
    await File(fsPath).delete();
  }

  @override
  Future<void> rmdir(String fsPath) async {
    await Directory(fsPath).delete();
  }

  @override
  Future<void> rm(
    String fsPath, {
    bool recursive = false,
    bool force = false,
  }) async {
    try {
      if (FileSystemEntity.isDirectorySync(fsPath)) {
        await Directory(fsPath).delete(recursive: recursive);
      } else {
        await File(fsPath).delete();
      }
    } catch (e) {
      if (!force) rethrow;
    }
  }

  @override
  Future<void> mkdir(String dirPath, {int? mode}) async {
    try {
      await Directory(dirPath).create(recursive: true);
    } on FileSystemException catch (e) {
      // Ignore EEXIST for recursive mkdir
      if (!e.message.contains('exists')) rethrow;
    }
  }

  @override
  Future<String> readFile(String fsPath, {String encoding = 'utf-8'}) async {
    return await File(fsPath).readAsString();
  }

  @override
  Future<void> rename(String oldPath, String newPath) async {
    await File(oldPath).rename(newPath);
  }

  @override
  FileStat statSync(String fsPath) {
    final s = File(fsPath).statSync();
    return FileStat(
      size: s.size,
      modified: s.modified,
      mtimeMs: s.modified.millisecondsSinceEpoch.toDouble(),
      type: s.type,
    );
  }

  @override
  FileStat lstatSync(String fsPath) {
    final isLink = FileSystemEntity.isLinkSync(fsPath);
    final s = File(fsPath).statSync();
    return FileStat(
      size: s.size,
      modified: s.modified,
      mtimeMs: s.modified.millisecondsSinceEpoch.toDouble(),
      type: s.type,
      isSymLink: isLink,
    );
  }

  @override
  String readFileSync(String fsPath, {String encoding = 'utf-8'}) {
    return File(fsPath).readAsStringSync();
  }

  @override
  Uint8List readFileBytesSync(String fsPath) {
    return File(fsPath).readAsBytesSync();
  }

  @override
  ReadSyncResult readSync(String fsPath, {required int length}) {
    final raf = File(fsPath).openSync(mode: FileMode.read);
    try {
      final buffer = Uint8List(length);
      final bytesRead = raf.readIntoSync(buffer);
      return ReadSyncResult(buffer: buffer, bytesRead: bytesRead);
    } finally {
      raf.closeSync();
    }
  }

  @override
  void appendFileSync(String path, String data, {int? mode}) {
    final file = File(path);
    if (mode != null && !file.existsSync()) {
      // Create with explicit mode for new files
      final raf = file.openSync(mode: FileMode.writeOnlyAppend);
      try {
        raf.writeStringSync(data);
      } finally {
        raf.closeSync();
      }
      return;
    }
    file.writeAsStringSync(data, mode: FileMode.append);
  }

  @override
  void copyFileSync(String src, String dest) {
    File(src).copySync(dest);
  }

  @override
  void unlinkSync(String path) {
    File(path).deleteSync();
  }

  @override
  void renameSync(String oldPath, String newPath) {
    File(oldPath).renameSync(newPath);
  }

  @override
  void linkSync(String target, String path) {
    Link(path).createSync(target);
  }

  @override
  void symlinkSync(String target, String path, {String? type}) {
    Link(path).createSync(target);
  }

  @override
  String readlinkSync(String path) {
    return Link(path).targetSync();
  }

  @override
  String realpathSync(String path) {
    return File(path).resolveSymbolicLinksSync();
  }

  @override
  void mkdirSync(String dirPath, {int? mode}) {
    try {
      Directory(dirPath).createSync(recursive: true);
    } on FileSystemException catch (e) {
      // Ignore EEXIST for recursive mkdir
      if (!e.message.contains('exists')) rethrow;
    }
  }

  @override
  List<Dirent> readdirSync(String dirPath) {
    final dir = Directory(dirPath);
    return dir.listSync().map((entity) {
      final stat = entity.statSync();
      return Dirent(
        name: p.basename(entity.path),
        type: stat.type,
        isSymLink: FileSystemEntity.isLinkSync(entity.path),
      );
    }).toList();
  }

  @override
  List<String> readdirStringSync(String dirPath) {
    final dir = Directory(dirPath);
    return dir.listSync().map((entity) => p.basename(entity.path)).toList();
  }

  @override
  bool isDirEmptySync(String dirPath) {
    return readdirSync(dirPath).isEmpty;
  }

  @override
  void rmdirSync(String dirPath) {
    Directory(dirPath).deleteSync();
  }

  @override
  void rmSync(String path, {bool recursive = false, bool force = false}) {
    try {
      if (FileSystemEntity.isDirectorySync(path)) {
        Directory(path).deleteSync(recursive: recursive);
      } else {
        File(path).deleteSync();
      }
    } catch (e) {
      if (!force) rethrow;
    }
  }

  @override
  Future<Uint8List> readFileBytes(String fsPath, {int? maxBytes}) async {
    if (maxBytes == null) {
      return await File(fsPath).readAsBytes();
    }
    final raf = await File(fsPath).open(mode: FileMode.read);
    try {
      final size = (await raf.length());
      final readSize = min(size, maxBytes);
      final buffer = Uint8List(readSize);
      int offset = 0;
      while (offset < readSize) {
        final bytesRead = await raf.readInto(buffer, offset, readSize);
        if (bytesRead == 0) break;
        offset += bytesRead;
      }
      return offset < readSize ? buffer.sublist(0, offset) : buffer;
    } finally {
      await raf.close();
    }
  }
}

// ============================================================================
// Active filesystem implementation (singleton pattern)
// ============================================================================

/// The currently active filesystem implementation.
FsOperations _activeFs = DartFsOperations();

/// Overrides the filesystem implementation.
/// Note: This function does not automatically update cwd.
void setFsImplementation(FsOperations implementation) {
  _activeFs = implementation;
}

/// Gets the currently active filesystem implementation.
FsOperations getFsImplementation() {
  return _activeFs;
}

/// Resets the filesystem implementation to the default Dart implementation.
/// Note: This function does not automatically update cwd.
void setOriginalFsImplementation() {
  _activeFs = DartFsOperations();
}

// ============================================================================
// ReadFileRangeResult
// ============================================================================

/// Result of reading a file range.
class ReadFileRangeResult {
  final String content;
  final int bytesRead;
  final int bytesTotal;

  ReadFileRangeResult({
    required this.content,
    required this.bytesRead,
    required this.bytesTotal,
  });
}

/// Read up to [maxBytes] from a file starting at [offset].
/// Returns a flat string from bytes -- no sliced string references to a
/// larger parent. Returns null if the file is smaller than the offset.
Future<ReadFileRangeResult?> readFileRange(
  String path,
  int offset,
  int maxBytes,
) async {
  final raf = await File(path).open(mode: FileMode.read);
  try {
    final size = await raf.length();
    if (size <= offset) {
      return null;
    }
    final bytesToRead = min(size - offset, maxBytes);
    final buffer = Uint8List(bytesToRead);
    await raf.setPosition(offset);

    int totalRead = 0;
    while (totalRead < bytesToRead) {
      final bytesRead = await raf.readInto(buffer, totalRead, bytesToRead);
      if (bytesRead == 0) break;
      totalRead += bytesRead;
    }

    return ReadFileRangeResult(
      content: String.fromCharCodes(buffer, 0, totalRead),
      bytesRead: totalRead,
      bytesTotal: size,
    );
  } finally {
    await raf.close();
  }
}

/// Read the last [maxBytes] of a file.
/// Returns the whole file if it's smaller than maxBytes.
Future<ReadFileRangeResult> tailFile(String path, int maxBytes) async {
  final raf = await File(path).open(mode: FileMode.read);
  try {
    final size = await raf.length();
    if (size == 0) {
      return ReadFileRangeResult(content: '', bytesRead: 0, bytesTotal: 0);
    }
    final offset = max(0, size - maxBytes);
    final bytesToRead = size - offset;
    final buffer = Uint8List(bytesToRead);
    await raf.setPosition(offset);

    int totalRead = 0;
    while (totalRead < bytesToRead) {
      final bytesRead = await raf.readInto(buffer, totalRead, bytesToRead);
      if (bytesRead == 0) break;
      totalRead += bytesRead;
    }

    return ReadFileRangeResult(
      content: String.fromCharCodes(buffer, 0, totalRead),
      bytesRead: totalRead,
      bytesTotal: size,
    );
  } finally {
    await raf.close();
  }
}

/// Async generator that yields lines from a file in reverse order.
/// Reads the file backwards in chunks to avoid loading the entire file into memory.
Stream<String> readLinesReverse(String path) async* {
  const chunkSize = 1024 * 4;
  final raf = await File(path).open(mode: FileMode.read);
  try {
    final size = await raf.length();
    int position = size;
    List<int> remainder = [];
    final buffer = Uint8List(chunkSize);

    while (position > 0) {
      final currentChunkSize = min(chunkSize, position);
      position -= currentChunkSize;

      await raf.setPosition(position);
      final readCount = await raf.readInto(buffer, 0, currentChunkSize);

      final combined = <int>[...buffer.sublist(0, readCount), ...remainder];

      final newlineChar = '\n'.codeUnitAt(0);
      final firstNewline = combined.indexOf(newlineChar);
      if (firstNewline == -1) {
        remainder = combined;
        continue;
      }

      remainder = combined.sublist(0, firstNewline);
      final text = String.fromCharCodes(combined, firstNewline + 1);
      final lines = text.split('\n');

      for (int i = lines.length - 1; i >= 0; i--) {
        final line = lines[i];
        if (line.isNotEmpty) {
          yield line;
        }
      }
    }

    if (remainder.isNotEmpty) {
      yield String.fromCharCodes(remainder);
    }
  } finally {
    await raf.close();
  }
}

// ============================================================================
// readFileInRange -- line-oriented file reader
// ============================================================================

const int _fastPathMaxSize = 10 * 1024 * 1024; // 10 MB

/// Result from readFileInRange.
class ReadFileInRangeResult {
  final String content;
  final int lineCount;
  final int totalLines;
  final int totalBytes;
  final int readBytes;
  final double mtimeMs;

  /// True when output was clipped to maxBytes under truncate mode.
  final bool truncatedByBytes;

  ReadFileInRangeResult({
    required this.content,
    required this.lineCount,
    required this.totalLines,
    required this.totalBytes,
    required this.readBytes,
    required this.mtimeMs,
    this.truncatedByBytes = false,
  });
}

/// Error thrown when a file exceeds the maximum allowed size.
class FileTooLargeError implements Exception {
  final int sizeInBytes;
  final int maxSizeBytes;
  late final String message;

  FileTooLargeError(this.sizeInBytes, this.maxSizeBytes) {
    message =
        'File content (${_formatFileSize(sizeInBytes)}) exceeds maximum allowed size '
        '(${_formatFileSize(maxSizeBytes)}). Use offset and limit parameters to read '
        'specific portions of the file, or search for specific content instead of '
        'reading the whole file.';
  }

  @override
  String toString() => 'FileTooLargeError: $message';
}

String _formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Public entry point for line-oriented file reading.
///
/// Returns lines [offset, offset + maxLines) from a file.
///
/// Fast path (regular files < 10 MB):
///   Reads the whole file, then splits lines in memory.
///
/// Streaming path (large files):
///   Reads the file in chunks, only accumulating lines in range.
///
/// Both paths strip UTF-8 BOM and \r (CRLF -> LF).
Future<ReadFileInRangeResult> readFileInRange(
  String filePath, {
  int offset = 0,
  int? maxLines,
  int? maxBytes,
  bool truncateOnByteLimit = false,
}) async {
  final file = File(filePath);
  final ioStat = await file.stat();

  if (ioStat.type == FileSystemEntityType.directory) {
    throw Exception(
      "EISDIR: illegal operation on a directory, read '$filePath'",
    );
  }

  final size = ioStat.size;
  final mtimeMs = ioStat.modified.millisecondsSinceEpoch.toDouble();

  if (ioStat.type == FileSystemEntityType.file && size < _fastPathMaxSize) {
    if (!truncateOnByteLimit && maxBytes != null && size > maxBytes) {
      throw FileTooLargeError(size, maxBytes);
    }

    final text = await file.readAsString();
    return _readFileInRangeFast(
      text,
      mtimeMs,
      offset,
      maxLines,
      truncateOnByteLimit ? maxBytes : null,
    );
  }

  return _readFileInRangeStreaming(
    filePath,
    offset,
    maxLines,
    maxBytes,
    truncateOnByteLimit,
    mtimeMs,
  );
}

/// Fast path -- readFile + in-memory split.
ReadFileInRangeResult _readFileInRangeFast(
  String raw,
  double mtimeMs,
  int offset,
  int? maxLines,
  int? truncateAtBytes,
) {
  final endLine = maxLines != null ? offset + maxLines : double.infinity;

  // Strip BOM.
  final text = (raw.isNotEmpty && raw.codeUnitAt(0) == 0xFEFF)
      ? raw.substring(1)
      : raw;

  // Split lines, strip \r, select range.
  final selectedLines = <String>[];
  int lineIndex = 0;
  int startPos = 0;
  int newlinePos;
  int selectedBytes = 0;
  bool truncatedByBytes = false;

  bool tryPush(String line) {
    if (truncateAtBytes != null) {
      final sep = selectedLines.isNotEmpty ? 1 : 0;
      final nextBytes = selectedBytes + sep + line.length;
      if (nextBytes > truncateAtBytes) {
        truncatedByBytes = true;
        return false;
      }
      selectedBytes = nextBytes;
    }
    selectedLines.add(line);
    return true;
  }

  while ((newlinePos = text.indexOf('\n', startPos)) != -1) {
    if (lineIndex >= offset && lineIndex < endLine && !truncatedByBytes) {
      String line = text.substring(startPos, newlinePos);
      if (line.endsWith('\r')) {
        line = line.substring(0, line.length - 1);
      }
      tryPush(line);
    }
    lineIndex++;
    startPos = newlinePos + 1;
  }

  // Final fragment (no trailing newline).
  if (lineIndex >= offset && lineIndex < endLine && !truncatedByBytes) {
    String line = text.substring(startPos);
    if (line.endsWith('\r')) {
      line = line.substring(0, line.length - 1);
    }
    tryPush(line);
  }
  lineIndex++;

  final content = selectedLines.join('\n');
  return ReadFileInRangeResult(
    content: content,
    lineCount: selectedLines.length,
    totalLines: lineIndex,
    totalBytes: text.length,
    readBytes: content.length,
    mtimeMs: mtimeMs,
    truncatedByBytes: truncatedByBytes,
  );
}

/// Streaming path -- read in chunks for large files.
Future<ReadFileInRangeResult> _readFileInRangeStreaming(
  String filePath,
  int offset,
  int? maxLines,
  int? maxBytes,
  bool truncateOnByteLimit,
  double mtimeMs,
) async {
  final endLine = maxLines != null ? offset + maxLines : double.infinity;
  final selectedLines = <String>[];
  int totalBytesRead = 0;
  int selectedBytes = 0;
  bool truncatedByBytes = false;
  int currentLineIndex = 0;
  String partial = '';
  bool isFirstChunk = true;
  double effectiveEndLine = endLine.toDouble();

  final stream = File(filePath).openRead();

  await for (final chunk in stream) {
    String chunkStr = String.fromCharCodes(chunk);

    if (isFirstChunk) {
      isFirstChunk = false;
      if (chunkStr.isNotEmpty && chunkStr.codeUnitAt(0) == 0xFEFF) {
        chunkStr = chunkStr.substring(1);
      }
    }

    totalBytesRead += chunkStr.length;
    if (!truncateOnByteLimit && maxBytes != null && totalBytesRead > maxBytes) {
      throw FileTooLargeError(totalBytesRead, maxBytes);
    }

    final data = partial.isNotEmpty ? partial + chunkStr : chunkStr;
    partial = '';

    int startPos = 0;
    int newlinePos;
    while ((newlinePos = data.indexOf('\n', startPos)) != -1) {
      if (currentLineIndex >= offset && currentLineIndex < effectiveEndLine) {
        String line = data.substring(startPos, newlinePos);
        if (line.endsWith('\r')) {
          line = line.substring(0, line.length - 1);
        }
        if (truncateOnByteLimit && maxBytes != null) {
          final sep = selectedLines.isNotEmpty ? 1 : 0;
          final nextBytes = selectedBytes + sep + line.length;
          if (nextBytes > maxBytes) {
            truncatedByBytes = true;
            effectiveEndLine = currentLineIndex.toDouble();
          } else {
            selectedBytes = nextBytes;
            selectedLines.add(line);
          }
        } else {
          selectedLines.add(line);
        }
      }
      currentLineIndex++;
      startPos = newlinePos + 1;
    }

    // Keep trailing fragment when inside the selected range.
    if (startPos < data.length) {
      if (currentLineIndex >= offset && currentLineIndex < effectiveEndLine) {
        final fragment = data.substring(startPos);
        if (truncateOnByteLimit && maxBytes != null) {
          final sep = selectedLines.isNotEmpty ? 1 : 0;
          final fragBytes = selectedBytes + sep + fragment.length;
          if (fragBytes > maxBytes) {
            truncatedByBytes = true;
            effectiveEndLine = currentLineIndex.toDouble();
            continue;
          }
        }
        partial = fragment;
      }
    }
  }

  // Handle final partial line
  String line = partial;
  if (line.endsWith('\r')) {
    line = line.substring(0, line.length - 1);
  }
  if (currentLineIndex >= offset && currentLineIndex < effectiveEndLine) {
    if (truncateOnByteLimit && maxBytes != null) {
      final sep = selectedLines.isNotEmpty ? 1 : 0;
      final nextBytes = selectedBytes + sep + line.length;
      if (nextBytes > maxBytes) {
        truncatedByBytes = true;
      } else {
        selectedLines.add(line);
      }
    } else {
      selectedLines.add(line);
    }
  }
  currentLineIndex++;

  final content = selectedLines.join('\n');
  return ReadFileInRangeResult(
    content: content,
    lineCount: selectedLines.length,
    totalLines: currentLineIndex,
    totalBytes: totalBytesRead,
    readBytes: content.length,
    mtimeMs: mtimeMs,
    truncatedByBytes: truncatedByBytes,
  );
}

// ============================================================================
// Generated Files Detection
// ============================================================================

/// Exact file name matches (case-insensitive) for generated/vendored files.
final _excludedFilenames = <String>{
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'bun.lockb',
  'bun.lock',
  'composer.lock',
  'gemfile.lock',
  'cargo.lock',
  'poetry.lock',
  'pipfile.lock',
  'shrinkwrap.json',
  'npm-shrinkwrap.json',
};

/// File extension patterns (case-insensitive).
final _excludedExtensions = <String>{
  '.lock',
  '.min.js',
  '.min.css',
  '.min.html',
  '.bundle.js',
  '.bundle.css',
  '.generated.ts',
  '.generated.js',
  '.d.ts',
};

/// Directory patterns that indicate generated/vendored content.
const _excludedDirectories = [
  '/dist/',
  '/build/',
  '/out/',
  '/output/',
  '/node_modules/',
  '/vendor/',
  '/vendored/',
  '/third_party/',
  '/third-party/',
  '/external/',
  '/.next/',
  '/.nuxt/',
  '/.svelte-kit/',
  '/coverage/',
  '/__pycache__/',
  '/.tox/',
  '/venv/',
  '/.venv/',
  '/target/release/',
  '/target/debug/',
];

/// Filename patterns using regex for more complex matching.
final _excludedFilenamePatterns = [
  RegExp(r'^.*\.min\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*-min\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.bundle\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.generated\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.gen\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.auto\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*_generated\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*_gen\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.pb\.(go|js|ts|py|rb)$', caseSensitive: false),
  RegExp(r'^.*_pb2?\.py$', caseSensitive: false),
  RegExp(r'^.*\.pb\.h$', caseSensitive: false),
  RegExp(r'^.*\.grpc\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.swagger\.[a-z]+$', caseSensitive: false),
  RegExp(r'^.*\.openapi\.[a-z]+$', caseSensitive: false),
];

/// Check if a file should be excluded from attribution based on Linguist-style rules.
///
/// [filePath] - Relative file path from repository root.
/// Returns true if the file should be excluded from attribution.
bool isGeneratedFile(String filePath) {
  // Normalize path separators for consistent pattern matching
  final normalizedPath =
      '/${filePath.replaceAll(Platform.pathSeparator, '/').replaceAll(RegExp(r'^/+'), '')}';
  final fileName = p.basename(filePath).toLowerCase();
  final ext = p.extension(filePath).toLowerCase();

  // Check exact filename matches
  if (_excludedFilenames.contains(fileName)) {
    return true;
  }

  // Check extension matches
  if (_excludedExtensions.contains(ext)) {
    return true;
  }

  // Check for compound extensions like .min.js
  final parts = fileName.split('.');
  if (parts.length > 2) {
    final compoundExt = '.${parts.sublist(parts.length - 2).join('.')}';
    if (_excludedExtensions.contains(compoundExt)) {
      return true;
    }
  }

  // Check directory patterns
  for (final dir in _excludedDirectories) {
    if (normalizedPath.contains(dir)) {
      return true;
    }
  }

  // Check filename patterns
  for (final pattern in _excludedFilenamePatterns) {
    if (pattern.hasMatch(fileName)) {
      return true;
    }
  }

  return false;
}

/// Filter a list of files to exclude generated files.
///
/// [files] - Array of file paths.
/// Returns array of files that are not generated.
List<String> filterGeneratedFiles(List<String> files) {
  return files.where((file) => !isGeneratedFile(file)).toList();
}
