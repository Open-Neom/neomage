// TeamMemoryService — port of neom_claw/src/services/teamMemorySync/.
// Manages shared team memory files (NEOMCLAW.md) sync, conflict resolution,
// and collaborative memory management.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

// ─── Types ───

/// Memory file type.
enum MemoryFileType {
  neomClawMd, // NEOMCLAW.md — project-level instructions
  neomClawLocalMd, // NEOMCLAW.local.md — personal instructions
  teamMd, // TEAM.md — shared team instructions
  ruleset, // .neomclaw/rules/*.md — modular rules
}

/// Sync status for a memory file.
enum SyncStatus {
  synced,
  localChanges,
  remoteChanges,
  conflict,
  notTracked,
  error,
}

/// A memory file entry.
class MemoryFile {
  final String path;
  final MemoryFileType type;
  final String content;
  final DateTime lastModified;
  final String? hash; // Content hash for change detection
  final SyncStatus syncStatus;
  final String? remoteHash;
  final String? author;
  final int version;

  const MemoryFile({
    required this.path,
    required this.type,
    required this.content,
    required this.lastModified,
    this.hash,
    this.syncStatus = SyncStatus.notTracked,
    this.remoteHash,
    this.author,
    this.version = 1,
  });

  MemoryFile copyWith({
    String? content,
    DateTime? lastModified,
    String? hash,
    SyncStatus? syncStatus,
    String? remoteHash,
    int? version,
  }) =>
      MemoryFile(
        path: path,
        type: type,
        content: content ?? this.content,
        lastModified: lastModified ?? this.lastModified,
        hash: hash ?? this.hash,
        syncStatus: syncStatus ?? this.syncStatus,
        remoteHash: remoteHash ?? this.remoteHash,
        author: author,
        version: version ?? this.version,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'type': type.name,
        'content': content,
        'lastModified': lastModified.toIso8601String(),
        'hash': hash,
        'syncStatus': syncStatus.name,
        'remoteHash': remoteHash,
        'author': author,
        'version': version,
      };

  factory MemoryFile.fromJson(Map<String, dynamic> json) => MemoryFile(
        path: json['path'] as String,
        type: MemoryFileType.values.byName(json['type'] as String),
        content: json['content'] as String,
        lastModified: DateTime.parse(json['lastModified'] as String),
        hash: json['hash'] as String?,
        syncStatus:
            SyncStatus.values.byName(json['syncStatus'] as String? ?? 'notTracked'),
        remoteHash: json['remoteHash'] as String?,
        author: json['author'] as String?,
        version: json['version'] as int? ?? 1,
      );
}

/// A memory section within a file (parsed from markdown).
class MemorySection {
  final String heading;
  final int level; // h1=1, h2=2, etc.
  final String content;
  final List<MemorySection> children;
  final List<String> tags;
  final DateTime? addedAt;
  final String? addedBy;

  const MemorySection({
    required this.heading,
    required this.level,
    required this.content,
    this.children = const [],
    this.tags = const [],
    this.addedAt,
    this.addedBy,
  });
}

/// A memory extraction from a conversation.
class ExtractedMemory {
  final String content;
  final String source; // 'conversation', 'user_request', 'auto_detected'
  final MemoryCategory category;
  final double confidence;
  final String? sessionId;
  final DateTime extractedAt;

  const ExtractedMemory({
    required this.content,
    required this.source,
    required this.category,
    this.confidence = 1.0,
    this.sessionId,
    required this.extractedAt,
  });
}

/// Category for extracted memories.
enum MemoryCategory {
  projectStructure,
  codingConventions,
  buildInstructions,
  testingGuidelines,
  deploymentProcess,
  teamPreferences,
  knownIssues,
  architecture,
  dependencies,
  other,
}

/// Conflict between local and remote memory.
class MemoryConflict {
  final String path;
  final String localContent;
  final String remoteContent;
  final String? baseContent; // Common ancestor
  final DateTime localModified;
  final DateTime remoteModified;
  final String? localAuthor;
  final String? remoteAuthor;

  const MemoryConflict({
    required this.path,
    required this.localContent,
    required this.remoteContent,
    this.baseContent,
    required this.localModified,
    required this.remoteModified,
    this.localAuthor,
    this.remoteAuthor,
  });
}

/// Resolution strategy for conflicts.
enum ConflictResolution {
  keepLocal,
  keepRemote,
  merge,
  manual,
}

/// Change event for memory files.
sealed class MemoryEvent {
  const MemoryEvent();
}

class MemoryFileChanged extends MemoryEvent {
  final MemoryFile file;
  const MemoryFileChanged(this.file);
}

class MemoryFileSynced extends MemoryEvent {
  final String path;
  const MemoryFileSynced(this.path);
}

class MemoryConflictDetected extends MemoryEvent {
  final MemoryConflict conflict;
  const MemoryConflictDetected(this.conflict);
}

class MemoryExtracted extends MemoryEvent {
  final ExtractedMemory memory;
  const MemoryExtracted(this.memory);
}

// ─── Memory Parser ───

/// Parses markdown memory files into sections.
class MemoryParser {
  /// Parse a markdown file into sections.
  static List<MemorySection> parse(String content) {
    final sections = <MemorySection>[];
    final lines = content.split('\n');
    String? currentHeading;
    int currentLevel = 0;
    final buffer = StringBuffer();

    for (final line in lines) {
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);

      if (headingMatch != null) {
        // Save previous section.
        if (currentHeading != null) {
          sections.add(MemorySection(
            heading: currentHeading,
            level: currentLevel,
            content: buffer.toString().trim(),
            tags: _extractTags(buffer.toString()),
          ));
        }

        currentHeading = headingMatch.group(2)!;
        currentLevel = headingMatch.group(1)!.length;
        buffer.clear();
      } else {
        buffer.writeln(line);
      }
    }

    // Save last section.
    if (currentHeading != null) {
      sections.add(MemorySection(
        heading: currentHeading,
        level: currentLevel,
        content: buffer.toString().trim(),
        tags: _extractTags(buffer.toString()),
      ));
    } else if (buffer.toString().trim().isNotEmpty) {
      sections.add(MemorySection(
        heading: 'General',
        level: 1,
        content: buffer.toString().trim(),
      ));
    }

    return sections;
  }

  /// Build sections back into markdown.
  static String build(List<MemorySection> sections) {
    final buffer = StringBuffer();

    for (final section in sections) {
      final prefix = '#' * section.level;
      buffer.writeln('$prefix ${section.heading}');
      buffer.writeln();
      buffer.writeln(section.content);
      buffer.writeln();

      if (section.children.isNotEmpty) {
        buffer.write(build(section.children));
      }
    }

    return buffer.toString().trimRight();
  }

  static List<String> _extractTags(String content) {
    final tags = <String>[];
    final tagPattern = RegExp(r'#(\w+)');
    for (final match in tagPattern.allMatches(content)) {
      tags.add(match.group(1)!);
    }
    return tags;
  }
}

// ─── Team Memory Service ───

/// Service for managing team and project memory files.
class TeamMemoryService {
  final String _projectRoot;
  final Map<String, MemoryFile> _files = {};
  final StreamController<MemoryEvent> _eventController =
      StreamController<MemoryEvent>.broadcast();
  final List<ExtractedMemory> _extractedMemories = [];
  Timer? _watchTimer;
  final Map<String, String> _lastKnownHashes = {};

  TeamMemoryService({required String projectRoot})
      : _projectRoot = projectRoot;

  /// Event stream.
  Stream<MemoryEvent> get events => _eventController.stream;

  /// All tracked memory files.
  List<MemoryFile> get files => _files.values.toList();

  // ─── Loading ───

  /// Scan and load all memory files in the project.
  Future<List<MemoryFile>> loadAll() async {
    final paths = <String, MemoryFileType>{};

    // NEOMCLAW.md at project root.
    paths['$_projectRoot/NEOMCLAW.md'] = MemoryFileType.neomClawMd;

    // NEOMCLAW.local.md.
    paths['$_projectRoot/NEOMCLAW.local.md'] = MemoryFileType.neomClawLocalMd;

    // TEAM.md.
    paths['$_projectRoot/TEAM.md'] = MemoryFileType.teamMd;

    // Walk parent directories for NEOMCLAW.md files.
    var dir = Directory(_projectRoot).parent;
    for (int i = 0; i < 5; i++) {
      // Max 5 levels up.
      final claudeMd = File('${dir.path}/NEOMCLAW.md');
      if (await claudeMd.exists()) {
        paths[claudeMd.path] = MemoryFileType.neomClawMd;
      }
      if (dir.path == dir.parent.path) break; // Reached root.
      dir = dir.parent;
    }

    // .neomclaw/rules/*.md files.
    final rulesDir = Directory('$_projectRoot/.neomclaw/rules');
    if (await rulesDir.exists()) {
      await for (final entity in rulesDir.list()) {
        if (entity is File && entity.path.endsWith('.md')) {
          paths[entity.path] = MemoryFileType.ruleset;
        }
      }
    }

    // Home directory NEOMCLAW.md.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final homeNeomClaw = '$home/.neomclaw/NEOMCLAW.md';
      paths[homeNeomClaw] = MemoryFileType.neomClawMd;
    }

    // Load each file.
    for (final entry in paths.entries) {
      final file = File(entry.key);
      if (await file.exists()) {
        final content = await file.readAsString();
        final stat = await file.stat();
        final hash = _hashContent(content);

        _files[entry.key] = MemoryFile(
          path: entry.key,
          type: entry.value,
          content: content,
          lastModified: stat.modified,
          hash: hash,
        );

        _lastKnownHashes[entry.key] = hash;
      }
    }

    return _files.values.toList();
  }

  /// Load a specific memory file.
  Future<MemoryFile?> load(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;

    final content = await file.readAsString();
    final stat = await file.stat();
    final hash = _hashContent(content);

    final type = _inferType(path);
    final memFile = MemoryFile(
      path: path,
      type: type,
      content: content,
      lastModified: stat.modified,
      hash: hash,
    );

    _files[path] = memFile;
    _lastKnownHashes[path] = hash;
    return memFile;
  }

  // ─── Writing ───

  /// Save content to a memory file.
  Future<MemoryFile> save(String path, String content) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);

    final stat = await file.stat();
    final hash = _hashContent(content);

    final memFile = MemoryFile(
      path: path,
      type: _inferType(path),
      content: content,
      lastModified: stat.modified,
      hash: hash,
      version: (_files[path]?.version ?? 0) + 1,
    );

    _files[path] = memFile;
    _lastKnownHashes[path] = hash;
    _eventController.add(MemoryFileChanged(memFile));

    return memFile;
  }

  /// Add a section to a memory file.
  Future<MemoryFile> addSection(
    String path, {
    required String heading,
    required String content,
    int level = 2,
  }) async {
    final existing = _files[path];
    final currentContent = existing?.content ?? '';

    final newSection = '\n\n${'#' * level} $heading\n\n$content';
    final updated = currentContent + newSection;

    return save(path, updated);
  }

  /// Remove a section from a memory file by heading.
  Future<MemoryFile?> removeSection(String path, String heading) async {
    final existing = _files[path];
    if (existing == null) return null;

    final sections = MemoryParser.parse(existing.content);
    final filtered = sections.where((s) => s.heading != heading).toList();

    if (filtered.length == sections.length) return existing; // Not found.

    final newContent = MemoryParser.build(filtered);
    return save(path, newContent);
  }

  /// Update a section's content in a memory file.
  Future<MemoryFile?> updateSection(
    String path, {
    required String heading,
    required String newContent,
  }) async {
    final existing = _files[path];
    if (existing == null) return null;

    final sections = MemoryParser.parse(existing.content);
    bool found = false;
    final updated = sections.map((s) {
      if (s.heading == heading) {
        found = true;
        return MemorySection(
          heading: s.heading,
          level: s.level,
          content: newContent,
          tags: s.tags,
          addedAt: s.addedAt,
          addedBy: s.addedBy,
        );
      }
      return s;
    }).toList();

    if (!found) return existing;

    final content = MemoryParser.build(updated);
    return save(path, content);
  }

  // ─── Memory Extraction ───

  /// Extract potential memories from a conversation message.
  List<ExtractedMemory> extractFromMessage(
    String message, {
    String? sessionId,
  }) {
    final extracted = <ExtractedMemory>[];
    final now = DateTime.now();

    // Pattern: "always/never do X" — coding conventions.
    final conventionPatterns = [
      RegExp(r'(?:always|never|prefer|avoid)\s+(?:use|using|do|doing)\s+(.+)', caseSensitive: false),
      RegExp(r'(?:the|our)\s+(?:convention|standard|pattern|rule)\s+is\s+(.+)', caseSensitive: false),
      RegExp(r'(?:we|you should)\s+(?:always|never)\s+(.+)', caseSensitive: false),
    ];

    for (final pattern in conventionPatterns) {
      for (final match in pattern.allMatches(message)) {
        extracted.add(ExtractedMemory(
          content: match.group(0)!.trim(),
          source: 'auto_detected',
          category: MemoryCategory.codingConventions,
          confidence: 0.7,
          sessionId: sessionId,
          extractedAt: now,
        ));
      }
    }

    // Pattern: build/run/test commands.
    final commandPatterns = [
      RegExp(r'(?:run|build|test|deploy|install)\s+(?:with|using|via)\s+[`"]?(.+?)[`"]?$', caseSensitive: false, multiLine: true),
      RegExp(r'(?:use|run)\s+[`"](.+?)[`"]\s+to\s+(?:build|test|deploy)', caseSensitive: false),
    ];

    for (final pattern in commandPatterns) {
      for (final match in pattern.allMatches(message)) {
        extracted.add(ExtractedMemory(
          content: match.group(0)!.trim(),
          source: 'auto_detected',
          category: MemoryCategory.buildInstructions,
          confidence: 0.6,
          sessionId: sessionId,
          extractedAt: now,
        ));
      }
    }

    // Pattern: architecture/structure mentions.
    final archPatterns = [
      RegExp(r'(?:the architecture|the structure|organized as|follows?\s+(?:MVC|MVVM|clean architecture|hexagonal))', caseSensitive: false),
    ];

    for (final pattern in archPatterns) {
      for (final match in pattern.allMatches(message)) {
        extracted.add(ExtractedMemory(
          content: match.group(0)!.trim(),
          source: 'auto_detected',
          category: MemoryCategory.architecture,
          confidence: 0.5,
          sessionId: sessionId,
          extractedAt: now,
        ));
      }
    }

    _extractedMemories.addAll(extracted);
    for (final e in extracted) {
      _eventController.add(MemoryExtracted(e));
    }

    return extracted;
  }

  /// Get all extracted memories, optionally filtered.
  List<ExtractedMemory> getExtractedMemories({
    MemoryCategory? category,
    double minConfidence = 0.0,
  }) {
    return _extractedMemories.where((m) {
      if (category != null && m.category != category) return false;
      if (m.confidence < minConfidence) return false;
      return true;
    }).toList();
  }

  /// Accept an extracted memory and add it to a memory file.
  Future<MemoryFile> acceptMemory(
    ExtractedMemory memory, {
    String? targetPath,
    String? heading,
  }) async {
    final path = targetPath ?? '$_projectRoot/NEOMCLAW.md';
    final sectionHeading = heading ?? _categoryHeading(memory.category);

    // Check if section exists.
    final existing = _files[path];
    if (existing != null) {
      final sections = MemoryParser.parse(existing.content);
      final section = sections.where((s) => s.heading == sectionHeading).firstOrNull;

      if (section != null) {
        // Append to existing section.
        final newContent = '${section.content}\n- ${memory.content}';
        return updateSection(path, heading: sectionHeading, newContent: newContent)
            .then((f) => f!);
      }
    }

    // Create new section.
    return addSection(
      path,
      heading: sectionHeading,
      content: '- ${memory.content}',
    );
  }

  // ─── Conflict Resolution ───

  /// Merge two versions of a memory file.
  String mergeContent(String local, String remote, {String? base}) {
    final localSections = MemoryParser.parse(local);
    final remoteSections = MemoryParser.parse(remote);
    final baseSections =
        base != null ? MemoryParser.parse(base) : <MemorySection>[];

    final mergedSections = <MemorySection>[];
    final processedHeadings = <String>{};

    // Process local sections.
    for (final ls in localSections) {
      final rs = remoteSections.where((s) => s.heading == ls.heading).firstOrNull;
      final bs = baseSections.where((s) => s.heading == ls.heading).firstOrNull;

      processedHeadings.add(ls.heading);

      if (rs == null) {
        // Only in local — keep if new (not in base) or if modified.
        if (bs == null || ls.content != bs.content) {
          mergedSections.add(ls);
        }
      } else if (ls.content == rs.content) {
        // Same in both — keep.
        mergedSections.add(ls);
      } else if (bs != null) {
        // Three-way merge.
        if (ls.content == bs.content) {
          // Only remote changed.
          mergedSections.add(MemorySection(
            heading: ls.heading,
            level: ls.level,
            content: rs.content,
          ));
        } else if (rs.content == bs.content) {
          // Only local changed.
          mergedSections.add(ls);
        } else {
          // Both changed — concatenate with markers.
          mergedSections.add(MemorySection(
            heading: ls.heading,
            level: ls.level,
            content: '${ls.content}\n\n<!-- Remote changes -->\n${rs.content}',
          ));
        }
      } else {
        // No base — concatenate.
        mergedSections.add(MemorySection(
          heading: ls.heading,
          level: ls.level,
          content: '${ls.content}\n\n${rs.content}',
        ));
      }
    }

    // Add remote-only sections.
    for (final rs in remoteSections) {
      if (!processedHeadings.contains(rs.heading)) {
        mergedSections.add(rs);
      }
    }

    return MemoryParser.build(mergedSections);
  }

  // ─── File Watching ───

  /// Start watching memory files for external changes.
  void startWatching({Duration interval = const Duration(seconds: 5)}) {
    _watchTimer?.cancel();
    _watchTimer = Timer.periodic(interval, (_) => _checkForChanges());
  }

  /// Stop watching.
  void stopWatching() {
    _watchTimer?.cancel();
  }

  Future<void> _checkForChanges() async {
    for (final entry in _files.entries) {
      final file = File(entry.key);
      if (!await file.exists()) continue;

      try {
        final content = await file.readAsString();
        final hash = _hashContent(content);
        final lastHash = _lastKnownHashes[entry.key];

        if (lastHash != null && hash != lastHash) {
          final stat = await file.stat();
          final updated = entry.value.copyWith(
            content: content,
            lastModified: stat.modified,
            hash: hash,
          );
          _files[entry.key] = updated;
          _lastKnownHashes[entry.key] = hash;
          _eventController.add(MemoryFileChanged(updated));
        }
      } catch (_) {}
    }
  }

  // ─── Build Context ───

  /// Build the combined memory context for the system prompt.
  String buildContext({
    bool includeLocal = true,
    bool includeTeam = true,
    bool includeRules = true,
    int? maxTokens,
  }) {
    final buffer = StringBuffer();
    final sorted = _files.values.toList()
      ..sort((a, b) {
        // Order: project NEOMCLAW.md first, then parent dirs, then rules, then team, then local.
        final typeOrder = {
          MemoryFileType.neomClawMd: 0,
          MemoryFileType.ruleset: 1,
          MemoryFileType.teamMd: 2,
          MemoryFileType.neomClawLocalMd: 3,
        };
        return (typeOrder[a.type] ?? 99).compareTo(typeOrder[b.type] ?? 99);
      });

    for (final file in sorted) {
      if (!includeLocal && file.type == MemoryFileType.neomClawLocalMd) continue;
      if (!includeTeam && file.type == MemoryFileType.teamMd) continue;
      if (!includeRules && file.type == MemoryFileType.ruleset) continue;

      buffer.writeln('<!-- ${file.path} -->');
      buffer.writeln(file.content);
      buffer.writeln();

      // Check token budget (rough estimate: ~4 chars per token).
      if (maxTokens != null && buffer.length ~/ 4 > maxTokens) {
        buffer.writeln('<!-- truncated: token budget exceeded -->');
        break;
      }
    }

    return buffer.toString().trim();
  }

  // ─── Utilities ───

  MemoryFileType _inferType(String path) {
    final name = path.split('/').last;
    if (name == 'NEOMCLAW.local.md') return MemoryFileType.neomClawLocalMd;
    if (name == 'NEOMCLAW.md') return MemoryFileType.neomClawMd;
    if (name == 'TEAM.md') return MemoryFileType.teamMd;
    if (path.contains('.neomclaw/rules/')) return MemoryFileType.ruleset;
    return MemoryFileType.neomClawMd;
  }

  String _categoryHeading(MemoryCategory category) {
    return switch (category) {
      MemoryCategory.projectStructure => 'Project Structure',
      MemoryCategory.codingConventions => 'Coding Conventions',
      MemoryCategory.buildInstructions => 'Build Instructions',
      MemoryCategory.testingGuidelines => 'Testing Guidelines',
      MemoryCategory.deploymentProcess => 'Deployment',
      MemoryCategory.teamPreferences => 'Team Preferences',
      MemoryCategory.knownIssues => 'Known Issues',
      MemoryCategory.architecture => 'Architecture',
      MemoryCategory.dependencies => 'Dependencies',
      MemoryCategory.other => 'Notes',
    };
  }

  String _hashContent(String content) {
    // Simple hash for change detection (not cryptographic).
    int hash = 0;
    for (int i = 0; i < content.length; i++) {
      hash = (hash * 31 + content.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Dispose resources.
  void dispose() {
    _watchTimer?.cancel();
    _eventController.close();
  }
}
