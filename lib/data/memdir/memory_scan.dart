// Memory file discovery — port of neom_claw/src/memdir/memoryScan.ts.
// Scans memory directory for .md files and parses their frontmatter.

import 'package:flutter_claw/core/platform/claw_io.dart';

import 'memory_types.dart';

/// Header information for a discovered memory file.
class MemoryHeader {
  final String filename;
  final String filePath;
  final DateTime modified;
  final String? description;
  final MemoryType? type;

  const MemoryHeader({
    required this.filename,
    required this.filePath,
    required this.modified,
    this.description,
    this.type,
  });
}

/// Maximum number of memory files to scan.
const int maxMemoryFiles = 200;

/// Maximum frontmatter lines to read per file.
const int maxFrontmatterLines = 30;

/// Scan a memory directory for .md files (excluding MEMORY.md entrypoint).
/// Returns headers sorted newest-first, capped at [maxMemoryFiles].
Future<List<MemoryHeader>> scanMemoryFiles(String memoryDir) async {
  final dir = Directory(memoryDir);
  if (!await dir.exists()) return const [];

  final headers = <MemoryHeader>[];

  await for (final entity in dir.list(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;

    // Skip the entrypoint
    final filename = entity.path.split('/').last;
    if (filename == 'MEMORY.md') continue;

    try {
      final stat = await entity.stat();
      final content = await entity.readAsString();
      final frontmatter = parseFrontmatter(content);

      headers.add(MemoryHeader(
        filename: filename,
        filePath: entity.path,
        modified: stat.modified,
        description: frontmatter?.description,
        type: frontmatter?.type,
      ));
    } catch (_) {
      // Skip unreadable files
    }

    if (headers.length >= maxMemoryFiles) break;
  }

  // Sort newest first
  headers.sort((a, b) => b.modified.compareTo(a.modified));
  return headers;
}

/// Format memory headers as a human-readable manifest.
String formatMemoryManifest(List<MemoryHeader> headers) {
  if (headers.isEmpty) return '(no memory files)';

  final buffer = StringBuffer();
  for (final h in headers) {
    final type = h.type != null ? '[${h.type!.name}]' : '[?]';
    final age = _memoryAge(h.modified);
    final desc = h.description ?? '(no description)';
    buffer.writeln('$type ${h.filename} ($age): $desc');
  }
  return buffer.toString();
}

String _memoryAge(DateTime modified) {
  final days = DateTime.now().difference(modified).inDays;
  if (days == 0) return 'today';
  if (days == 1) return 'yesterday';
  return '$days days ago';
}
