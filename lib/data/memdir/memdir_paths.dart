// Memdir path resolution — port of neom_claw/src/memdir/paths.ts.
// Resolves memory directory locations with security validation.

import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

/// Default memory base directory (~/.neomclaw).
String getMemoryBaseDir() {
  final envOverride = Platform.environment['NEOMCLAW_REMOTE_MEMORY_DIR'];
  if (envOverride != null && envOverride.isNotEmpty) return envOverride;
  return p.join(_homeDir, '.neomclaw');
}

/// Get the auto-memory directory for the current project.
/// Pattern: `~/.neomclaw/projects/{sanitized-path}/memory/`
String getAutoMemPath({String? projectRoot}) {
  final envOverride =
      Platform.environment['NEOMCLAW_COWORK_MEMORY_PATH_OVERRIDE'];
  if (envOverride != null && envOverride.isNotEmpty) return envOverride;

  final root = projectRoot ?? Directory.current.path;
  final sanitized = _sanitizePath(root);
  return p.join(getMemoryBaseDir(), 'projects', sanitized, 'memory');
}

/// Path to the MEMORY.md entrypoint.
String getAutoMemEntrypoint({String? projectRoot}) {
  return p.join(getAutoMemPath(projectRoot: projectRoot), 'MEMORY.md');
}

/// Check if a file path is within the auto-memory directory.
bool isAutoMemPath(String filePath, {String? projectRoot}) {
  final memPath = getAutoMemPath(projectRoot: projectRoot);
  return p.normalize(filePath).startsWith(p.normalize(memPath));
}

/// Validate a memory path for security.
/// Rejects relative paths, root paths, null bytes, etc.
String? validateMemoryPath(String path) {
  // Reject null bytes
  if (path.contains('\x00')) return null;

  // Reject relative paths
  if (!p.isAbsolute(path)) return null;

  // Reject root or near-root paths
  final normalized = p.normalize(path);
  final parts = p.split(normalized);
  if (parts.length < 3) return null;

  // Reject path traversal
  if (normalized.contains('..')) return null;

  return normalized;
}

/// Ensure the memory directory exists, creating it if needed.
Future<void> ensureMemoryDirExists({String? projectRoot}) async {
  final memPath = getAutoMemPath(projectRoot: projectRoot);
  final dir = Directory(memPath);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
}

/// Maximum lines from MEMORY.md to include in prompt.
const int maxEntrypointLines = 200;

/// Maximum bytes from MEMORY.md to include in prompt.
const int maxEntrypointBytes = 25000;

/// Entrypoint file name.
const String entrypointName = 'MEMORY.md';

// ── Private helpers ──

String get _homeDir {
  final home =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/tmp';
  return home;
}

/// Sanitize a path for use as a directory name.
/// Replaces path separators with dashes, removes leading slash.
String _sanitizePath(String path) {
  return path
      .replaceAll(RegExp(r'^[/\\]+'), '')
      .replaceAll(RegExp(r'[/\\]'), '-');
}
