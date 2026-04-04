// Memdir service — port of neom_claw/src/memdir/memdir.ts.
// Core orchestration for persistent memory: loading, building prompts,
// and managing MEMORY.md entrypoint content.

import 'package:neom_claw/core/platform/claw_io.dart';

import 'memdir_paths.dart';
import 'memory_scan.dart';
import 'memory_types.dart';

/// Result of loading the memory prompt.
class MemoryPromptResult {
  final String prompt;
  final int memoryFileCount;
  final bool memoryDirExists;

  const MemoryPromptResult({
    required this.prompt,
    required this.memoryFileCount,
    required this.memoryDirExists,
  });
}

/// Memdir service — manages persistent memory for the session.
class MemdirService {
  final String? projectRoot;
  bool _initialized = false;

  MemdirService({this.projectRoot});

  /// Ensure the memory directory structure exists.
  Future<void> initialize() async {
    if (_initialized) return;
    await ensureMemoryDirExists(projectRoot: projectRoot);
    _initialized = true;
  }

  /// Build the memory prompt to inject into the system prompt.
  /// Loads MEMORY.md content and constructs behavioral instructions.
  Future<MemoryPromptResult> loadMemoryPrompt() async {
    await initialize();

    final memPath = getAutoMemPath(projectRoot: projectRoot);
    final entrypoint = getAutoMemEntrypoint(projectRoot: projectRoot);
    final entrypointFile = File(entrypoint);

    String? entrypointContent;
    if (await entrypointFile.exists()) {
      entrypointContent = await _readEntrypoint(entrypointFile);
    }

    // Count memory files for analytics
    final headers = await scanMemoryFiles(memPath);

    final prompt = _buildMemoryPrompt(
      memoryDir: memPath,
      entrypointContent: entrypointContent,
      memoryFileCount: headers.length,
    );

    return MemoryPromptResult(
      prompt: prompt,
      memoryFileCount: headers.length,
      memoryDirExists: true,
    );
  }

  /// Read a specific memory file by path.
  Future<String?> readMemoryFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Write a memory file with frontmatter.
  Future<void> writeMemoryFile({
    required String filename,
    required String name,
    required String description,
    required MemoryType type,
    required String content,
  }) async {
    await initialize();
    final memPath = getAutoMemPath(projectRoot: projectRoot);
    final filePath = '$memPath/$filename';
    final file = File(filePath);

    final fullContent = '''---
name: $name
description: $description
type: ${type.name}
---

$content
''';

    await file.writeAsString(fullContent);
  }

  /// Update the MEMORY.md entrypoint index.
  Future<void> writeEntrypoint(String content) async {
    await initialize();
    final entrypoint = getAutoMemEntrypoint(projectRoot: projectRoot);
    await File(entrypoint).writeAsString(content);
  }

  /// Read MEMORY.md entrypoint content.
  Future<String?> readEntrypoint() async {
    final entrypoint = getAutoMemEntrypoint(projectRoot: projectRoot);
    final file = File(entrypoint);
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// Scan all memory files in the directory.
  Future<List<MemoryHeader>> scanMemories() async {
    await initialize();
    final memPath = getAutoMemPath(projectRoot: projectRoot);
    return scanMemoryFiles(memPath);
  }

  /// Delete a memory file.
  Future<bool> deleteMemoryFile(String filename) async {
    final memPath = getAutoMemPath(projectRoot: projectRoot);
    final file = File('$memPath/$filename');
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  // ── Private ──

  Future<String> _readEntrypoint(File file) async {
    final content = await file.readAsString();

    // Truncate by lines
    final lines = content.split('\n');
    final truncatedLines = lines.length > maxEntrypointLines
        ? lines.sublist(0, maxEntrypointLines)
        : lines;
    var result = truncatedLines.join('\n');

    // Truncate by bytes
    if (result.length > maxEntrypointBytes) {
      result = result.substring(0, maxEntrypointBytes);
    }

    return result;
  }

  String _buildMemoryPrompt({
    required String memoryDir,
    required String? entrypointContent,
    required int memoryFileCount,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# auto memory');
    buffer.writeln();
    buffer.writeln(
        'You have a persistent, file-based memory system at `$memoryDir`. '
        'This directory already exists — write to it directly with the Write '
        'tool (do not run mkdir or check for its existence).');
    buffer.writeln();
    buffer.writeln(
        'You should build up this memory system over time so that future '
        'conversations can have a complete picture of who the user is, how '
        'they\'d like to collaborate with you, what behaviors to avoid or '
        'repeat, and the context behind the work the user gives you.');
    buffer.writeln();

    // Memory types section
    buffer.writeln('## Types of memory');
    buffer.writeln();
    buffer.writeln('There are several discrete types of memory:');
    buffer.writeln('- **user**: Information about the user\'s role, goals, '
        'preferences');
    buffer.writeln('- **feedback**: Guidance about approach — corrections '
        'and confirmations');
    buffer.writeln('- **project**: Information about ongoing work, goals, '
        'initiatives');
    buffer.writeln('- **reference**: Pointers to external systems and '
        'resources');
    buffer.writeln();

    // How to save
    buffer.writeln('## How to save memories');
    buffer.writeln();
    buffer.writeln('Write each memory to its own file with YAML frontmatter:');
    buffer.writeln('```markdown');
    buffer.writeln('---');
    buffer.writeln('name: {{memory name}}');
    buffer.writeln('description: {{one-line description}}');
    buffer.writeln('type: {{user, feedback, project, reference}}');
    buffer.writeln('---');
    buffer.writeln('{{memory content}}');
    buffer.writeln('```');
    buffer.writeln();
    buffer.writeln(
        'Then add a pointer to that file in `$entrypointName`. '
        '$entrypointName is an index — each entry should be one line, '
        'under ~150 characters.');
    buffer.writeln();

    // MEMORY.md content
    if (entrypointContent != null && entrypointContent.isNotEmpty) {
      buffer.writeln('## Current MEMORY.md');
      buffer.writeln();
      buffer.writeln(entrypointContent);
    }

    return buffer.toString();
  }
}
