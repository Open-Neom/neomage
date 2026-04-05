// SkillRegistry — port of neomage/src/skills/.
// Manages skill definitions, loading, resolution, and execution.
// Skills are modular prompt-based capabilities (like /commit, /review-pr, /pdf).

import 'dart:async';

import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:neomage/core/platform/neomage_io.dart';

// ─── Types ───

/// Skill source type.
enum SkillSource {
  builtin, // Shipped with app
  project, // .neomage/skills/ in project
  user, // ~/.neomage/skills/ user-global
  mcp, // From MCP server
  remote, // Downloaded from registry
}

/// Skill parameter definition.
class SkillParameter {
  final String name;
  final String description;
  final String type; // 'string', 'number', 'boolean', 'file', 'enum'
  final bool required;
  final dynamic defaultValue;
  final List<String>? enumValues;
  final String? pattern; // Regex validation

  const SkillParameter({
    required this.name,
    required this.description,
    this.type = 'string',
    this.required = false,
    this.defaultValue,
    this.enumValues,
    this.pattern,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description,
    'type': type,
    'required': required,
    if (defaultValue != null) 'default': defaultValue,
    if (enumValues != null) 'enum': enumValues,
    if (pattern != null) 'pattern': pattern,
  };

  factory SkillParameter.fromJson(Map<String, dynamic> json) => SkillParameter(
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    type: json['type'] as String? ?? 'string',
    required: json['required'] as bool? ?? false,
    defaultValue: json['default'],
    enumValues: (json['enum'] as List<dynamic>?)?.cast<String>(),
    pattern: json['pattern'] as String?,
  );
}

/// A skill definition.
class SkillDefinition {
  final String name;
  final String? fullName; // e.g. 'ms-office-suite:pdf'
  final String description;
  final String prompt; // The skill's prompt template
  final SkillSource source;
  final List<SkillParameter> parameters;
  final List<String> tools; // Required tools
  final String? model; // Model override
  final String? icon;
  final List<String> tags;
  final String? author;
  final String? version;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? metadata;

  const SkillDefinition({
    required this.name,
    this.fullName,
    required this.description,
    required this.prompt,
    this.source = SkillSource.builtin,
    this.parameters = const [],
    this.tools = const [],
    this.model,
    this.icon,
    this.tags = const [],
    this.author,
    this.version,
    this.createdAt,
    this.updatedAt,
    this.metadata,
  });

  /// Resolve the prompt with given arguments.
  String resolvePrompt(Map<String, dynamic> args) {
    var resolved = prompt;

    // Replace {{param}} placeholders.
    for (final param in parameters) {
      final value = args[param.name] ?? param.defaultValue ?? '';
      resolved = resolved.replaceAll('{{${param.name}}}', '$value');
      resolved = resolved.replaceAll('{${param.name}}', '$value');
    }

    // Replace $ARGUMENTS with the raw args string.
    final rawArgs = args.entries.map((e) => '${e.key}=${e.value}').join(' ');
    resolved = resolved.replaceAll(r'$ARGUMENTS', rawArgs);

    return resolved;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (fullName != null) 'fullName': fullName,
    'description': description,
    'prompt': prompt,
    'source': source.name,
    'parameters': parameters.map((p) => p.toJson()).toList(),
    'tools': tools,
    if (model != null) 'model': model,
    if (icon != null) 'icon': icon,
    'tags': tags,
    if (author != null) 'author': author,
    if (version != null) 'version': version,
  };

  factory SkillDefinition.fromJson(Map<String, dynamic> json) =>
      SkillDefinition(
        name: json['name'] as String,
        fullName: json['fullName'] as String?,
        description: json['description'] as String? ?? '',
        prompt: json['prompt'] as String? ?? '',
        source: SkillSource.values.byName(
          json['source'] as String? ?? 'builtin',
        ),
        parameters:
            (json['parameters'] as List<dynamic>?)
                ?.map((p) => SkillParameter.fromJson(p as Map<String, dynamic>))
                .toList() ??
            [],
        tools: (json['tools'] as List<dynamic>?)?.cast<String>() ?? [],
        model: json['model'] as String?,
        icon: json['icon'] as String?,
        tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        author: json['author'] as String?,
        version: json['version'] as String?,
      );

  /// Parse a skill definition from a markdown file with frontmatter.
  factory SkillDefinition.fromMarkdown(
    String content, {
    SkillSource source = SkillSource.project,
  }) {
    String prompt = content;
    String name = 'unnamed';
    String description = '';
    String? model;
    List<SkillParameter> parameters = [];
    List<String> tools = [];
    List<String> tags = [];

    // Parse YAML-like frontmatter.
    final frontmatterMatch = RegExp(
      r'^---\s*\n([\s\S]*?)\n---\s*\n',
      multiLine: true,
    ).firstMatch(content);

    if (frontmatterMatch != null) {
      final frontmatter = frontmatterMatch.group(1)!;
      prompt = content.substring(frontmatterMatch.end);

      // Simple YAML parsing (key: value).
      for (final line in frontmatter.split('\n')) {
        final colonIndex = line.indexOf(':');
        if (colonIndex < 0) continue;
        final key = line.substring(0, colonIndex).trim();
        final value = line.substring(colonIndex + 1).trim();

        switch (key) {
          case 'name':
            name = value;
          case 'description':
            description = value;
          case 'model':
            model = value;
          case 'tools':
            tools = value
                .replaceAll('[', '')
                .replaceAll(']', '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
          case 'tags':
            tags = value
                .replaceAll('[', '')
                .replaceAll(']', '')
                .split(',')
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList();
        }
      }
    }

    return SkillDefinition(
      name: name,
      description: description,
      prompt: prompt.trim(),
      source: source,
      parameters: parameters,
      tools: tools,
      model: model,
      tags: tags,
    );
  }
}

/// Result of skill execution.
class SkillResult {
  final String skillName;
  final bool success;
  final String output;
  final Duration duration;
  final Map<String, dynamic>? metadata;

  const SkillResult({
    required this.skillName,
    required this.success,
    required this.output,
    required this.duration,
    this.metadata,
  });
}

// ─── Skill Registry ───

/// Registry for managing and executing skills.
class SkillRegistry {
  final Map<String, SkillDefinition> _skills = {};
  final List<String> _searchPaths = [];
  bool _initialized = false;

  SkillRegistry();

  /// All registered skills.
  List<SkillDefinition> get skills => _skills.values.toList();

  /// Get skill by name (supports both short and full names).
  SkillDefinition? get(String name) {
    // Exact match.
    if (_skills.containsKey(name)) return _skills[name];

    // Full name match.
    for (final skill in _skills.values) {
      if (skill.fullName == name) return skill;
    }

    // Partial match.
    final matches = _skills.entries
        .where(
          (e) =>
              e.key.contains(name) ||
              (e.value.fullName?.contains(name) ?? false),
        )
        .toList();
    if (matches.length == 1) return matches.first.value;

    return null;
  }

  /// Bundled skills loaded from assets (category → list of skills).
  /// Populated by [initialize] from assets/skills/*.md via AssetManifest.
  final Map<String, List<SkillDefinition>> bundledByCategory = {};

  /// Initialize and load skills from all sources.
  Future<void> initialize({String? projectRoot, String? homeDir}) async {
    if (_initialized) return;

    // Register built-in skills.
    _registerBuiltins();

    // Load bundled skills from assets/skills/.
    await _loadBundledSkills();

    // Add search paths.
    if (projectRoot != null) {
      _searchPaths.add('$projectRoot/.neomage/skills');
      _searchPaths.add('$projectRoot/.neomage/commands'); // Legacy path
    }

    final home =
        homeDir ??
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'];
    if (home != null) {
      _searchPaths.add('$home/.neomage/skills');
      _searchPaths.add('$home/.neomage/commands'); // Legacy path
    }

    // Load from file system (project/user overrides bundled).
    await _loadFromPaths();

    _initialized = true;
  }

  /// Register a skill.
  void register(SkillDefinition skill) {
    _skills[skill.name] = skill;
  }

  /// Unregister a skill.
  void unregister(String name) {
    _skills.remove(name);
  }

  /// Search skills by query.
  List<SkillDefinition> search(String query) {
    if (query.isEmpty) return skills;

    final q = query.toLowerCase();
    return _skills.values.where((s) {
      return s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.tags.any((t) => t.toLowerCase().contains(q)) ||
          (s.fullName?.toLowerCase().contains(q) ?? false);
    }).toList()..sort((a, b) {
      // Prefer exact name matches.
      final aExact = a.name.toLowerCase() == q ? 0 : 1;
      final bExact = b.name.toLowerCase() == q ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);
      return a.name.compareTo(b.name);
    });
  }

  /// List skills by source.
  List<SkillDefinition> bySource(SkillSource source) {
    return _skills.values.where((s) => s.source == source).toList();
  }

  /// List skills by tag.
  List<SkillDefinition> byTag(String tag) {
    return _skills.values.where((s) => s.tags.contains(tag)).toList();
  }

  /// Validate skill arguments against parameters.
  List<String> validateArgs(SkillDefinition skill, Map<String, dynamic> args) {
    final errors = <String>[];

    for (final param in skill.parameters) {
      if (param.required && !args.containsKey(param.name)) {
        errors.add('Missing required parameter: ${param.name}');
        continue;
      }

      final value = args[param.name];
      if (value == null) continue;

      // Type check.
      switch (param.type) {
        case 'number':
          if (value is! num && num.tryParse('$value') == null) {
            errors.add('${param.name} must be a number');
          }
        case 'boolean':
          if (value is! bool && value != 'true' && value != 'false') {
            errors.add('${param.name} must be a boolean');
          }
        case 'enum':
          if (param.enumValues != null &&
              !param.enumValues!.contains('$value')) {
            errors.add(
              '${param.name} must be one of: ${param.enumValues!.join(', ')}',
            );
          }
      }

      // Pattern check.
      if (param.pattern != null) {
        if (!RegExp(param.pattern!).hasMatch('$value')) {
          errors.add('${param.name} does not match pattern: ${param.pattern}');
        }
      }
    }

    return errors;
  }

  /// Reload skills from file system.
  Future<void> reload() async {
    // Remove file-based skills.
    _skills.removeWhere(
      (_, v) => v.source == SkillSource.project || v.source == SkillSource.user,
    );
    await _loadFromPaths();
  }

  /// Export a skill to a markdown file.
  Future<void> exportSkill(String name, String outputPath) async {
    final skill = get(name);
    if (skill == null) throw ArgumentError('Skill not found: $name');

    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.writeln('name: ${skill.name}');
    buffer.writeln('description: ${skill.description}');
    if (skill.model != null) buffer.writeln('model: ${skill.model}');
    if (skill.tools.isNotEmpty) {
      buffer.writeln('tools: [${skill.tools.join(', ')}]');
    }
    if (skill.tags.isNotEmpty) {
      buffer.writeln('tags: [${skill.tags.join(', ')}]');
    }
    buffer.writeln('---');
    buffer.writeln();
    buffer.writeln(skill.prompt);

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(buffer.toString());
  }

  /// Import a skill from a markdown file.
  Future<SkillDefinition> importSkill(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw ArgumentError('Skill file not found: $filePath');
    }

    final content = await file.readAsString();
    final skill = SkillDefinition.fromMarkdown(content);
    register(skill);
    return skill;
  }

  // ─── Internal ───

  void _registerBuiltins() {
    // Commit skill.
    register(
      const SkillDefinition(
        name: 'commit',
        description: 'Create a well-formatted git commit',
        prompt:
            '''Look at the current git diff and create a commit with a descriptive message.
Follow conventional commit format. Include a summary of changes.
If there are no staged changes, stage all modified files first.
Do not include unrelated files.''',
        source: SkillSource.builtin,
        tools: ['Bash', 'Read'],
        tags: ['git', 'workflow'],
        icon: 'commit',
      ),
    );

    // Review PR skill.
    register(
      const SkillDefinition(
        name: 'review-pr',
        fullName: 'review-pr',
        description: 'Review a pull request',
        prompt: '''Review the pull request {{pr_number}}.
Look at all changed files, understand the context, and provide feedback.
Check for: bugs, security issues, performance problems, code style, test coverage.
Be constructive and specific in feedback.''',
        source: SkillSource.builtin,
        parameters: [
          SkillParameter(
            name: 'pr_number',
            description: 'Pull request number or URL',
            required: true,
          ),
        ],
        tools: ['Bash', 'Read', 'Grep'],
        tags: ['git', 'review'],
        icon: 'review',
      ),
    );

    // PDF skill.
    register(
      const SkillDefinition(
        name: 'pdf',
        description: 'Read and analyze a PDF file',
        prompt: '''Read the PDF file at {{file_path}} and provide a summary.
Extract key information, structure, and main points.''',
        source: SkillSource.builtin,
        parameters: [
          SkillParameter(
            name: 'file_path',
            description: 'Path to the PDF file',
            type: 'file',
            required: true,
          ),
        ],
        tools: ['Read'],
        tags: ['documents'],
        icon: 'document',
      ),
    );

    // Test skill.
    register(
      const SkillDefinition(
        name: 'test',
        description: 'Run tests and fix failures',
        prompt: '''Run the project tests. If any tests fail:
1. Read the failing test file
2. Understand what the test expects
3. Read the implementation being tested
4. Fix the issue
5. Re-run the tests to verify''',
        source: SkillSource.builtin,
        tools: ['Bash', 'Read', 'Edit'],
        tags: ['testing', 'workflow'],
        icon: 'test',
      ),
    );

    // Explain skill.
    register(
      const SkillDefinition(
        name: 'explain',
        description: 'Explain how code works',
        prompt: '''Explain how {{target}} works in this codebase.
Read the relevant files, trace the execution flow, and explain:
1. What it does at a high level
2. Key components and their roles
3. Data flow
4. Important edge cases
5. How it connects to the rest of the codebase''',
        source: SkillSource.builtin,
        parameters: [
          SkillParameter(
            name: 'target',
            description: 'File, function, or concept to explain',
            required: true,
          ),
        ],
        tools: ['Read', 'Grep', 'Glob'],
        tags: ['learning', 'documentation'],
        icon: 'explain',
      ),
    );

    // Refactor skill.
    register(
      const SkillDefinition(
        name: 'refactor',
        description: 'Refactor code for improvement',
        prompt: '''Refactor {{target}} to improve {{aspect}}.
1. Read the current code
2. Identify specific improvements
3. Make the changes
4. Verify the changes compile/work
5. Summarize what was changed and why''',
        source: SkillSource.builtin,
        parameters: [
          SkillParameter(
            name: 'target',
            description: 'File or function to refactor',
            required: true,
          ),
          SkillParameter(
            name: 'aspect',
            description: 'What to improve',
            required: false,
            defaultValue: 'readability and maintainability',
          ),
        ],
        tools: ['Read', 'Edit', 'Bash'],
        tags: ['refactoring'],
        icon: 'refactor',
      ),
    );

    // Security audit skill.
    register(
      const SkillDefinition(
        name: 'security-audit',
        description: 'Audit codebase for security vulnerabilities',
        prompt: '''Perform a security audit of this codebase.
Check for:
- Hardcoded secrets/credentials
- SQL injection
- XSS vulnerabilities
- Insecure file operations
- Improper input validation
- Dependency vulnerabilities
- Insecure configurations
Report findings with severity, location, and remediation steps.''',
        source: SkillSource.builtin,
        tools: ['Read', 'Grep', 'Glob', 'Bash'],
        tags: ['security'],
        icon: 'security',
      ),
    );

    // Doc skill.
    register(
      const SkillDefinition(
        name: 'doc',
        description: 'Generate documentation',
        prompt: '''Generate documentation for {{target}}.
Include:
- Overview/purpose
- API reference (public methods/properties)
- Usage examples
- Configuration options
- Common patterns''',
        source: SkillSource.builtin,
        parameters: [
          SkillParameter(
            name: 'target',
            description: 'File, module, or API to document',
            required: true,
          ),
        ],
        tools: ['Read', 'Grep', 'Glob'],
        tags: ['documentation'],
        icon: 'document',
      ),
    );
  }

  /// Load bundled skills from assets/skills/ via AssetManifest.
  /// Skills are registered with source=builtin and grouped by category.
  Future<void> _loadBundledSkills() async {
    try {
      final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = assetManifest.listAssets();
      final regex = RegExp(r'assets/skills/([^/]+)/([^/]+\.md)$');

      for (final assetPath in allAssets) {
        final match = regex.firstMatch(assetPath);
        if (match == null) continue;

        final category = match.group(1)!;
        final fileName = match.group(2)!;
        final name = fileName.replaceAll('.md', '');

        // Register as a lightweight definition (prompt loaded on-demand).
        final skill = SkillDefinition(
          name: name,
          description: 'Bundled skill: ${_humanize(name)}',
          prompt: '', // Loaded on-demand via loadSkillContent()
          source: SkillSource.builtin,
          tags: [category],
          metadata: {'assetPath': assetPath, 'category': category},
        );

        register(skill);
        bundledByCategory.putIfAbsent(category, () => []);
        bundledByCategory[category]!.add(skill);
      }

      // Sort each category alphabetically.
      for (final list in bundledByCategory.values) {
        list.sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (_) {
      // AssetManifest may not be available in non-Flutter contexts (CLI, tests).
    }
  }

  /// Load the full markdown content of a bundled skill on-demand.
  /// Returns null if the skill has no asset path or loading fails.
  Future<String?> loadSkillContent(SkillDefinition skill) async {
    final assetPath = skill.metadata?['assetPath'] as String?;
    if (assetPath == null) return skill.prompt.isNotEmpty ? skill.prompt : null;

    try {
      final content = await rootBundle.loadString(assetPath);

      // Update the skill's prompt with full content.
      final parsed = SkillDefinition.fromMarkdown(content, source: skill.source);
      final updated = SkillDefinition(
        name: skill.name,
        fullName: parsed.fullName ?? skill.fullName,
        description: parsed.description.isNotEmpty ? parsed.description : skill.description,
        prompt: parsed.prompt,
        source: skill.source,
        parameters: parsed.parameters.isNotEmpty ? parsed.parameters : skill.parameters,
        tools: parsed.tools.isNotEmpty ? parsed.tools : skill.tools,
        model: parsed.model ?? skill.model,
        tags: skill.tags,
        metadata: skill.metadata,
      );
      _skills[skill.name] = updated;

      return content;
    } catch (_) {
      return null;
    }
  }

  /// All bundled category names in order.
  List<String> get bundledCategories => bundledByCategory.keys.toList()..sort();

  /// Total number of bundled skills.
  int get bundledSkillCount =>
      bundledByCategory.values.fold(0, (sum, list) => sum + list.length);

  static String _humanize(String snakeCase) {
    return snakeCase
        .replaceAll('_', ' ')
        .replaceAllMapped(RegExp(r'(^|\s)\w'), (m) => m[0]!.toUpperCase());
  }

  Future<void> _loadFromPaths() async {
    for (final searchPath in _searchPaths) {
      final dir = Directory(searchPath);
      if (!await dir.exists()) continue;

      final source =
          searchPath.contains('.neomage/skills') &&
              !searchPath.startsWith(Platform.environment['HOME'] ?? '')
          ? SkillSource.project
          : SkillSource.user;

      await for (final entity in dir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.md')) {
          try {
            final content = await entity.readAsString();
            final skill = SkillDefinition.fromMarkdown(content, source: source);

            // Derive name from filename if not in frontmatter.
            final name = skill.name == 'unnamed'
                ? entity.uri.pathSegments.last.replaceAll('.md', '')
                : skill.name;

            register(
              SkillDefinition(
                name: name,
                fullName: skill.fullName,
                description: skill.description.isEmpty
                    ? 'Custom skill: $name'
                    : skill.description,
                prompt: skill.prompt,
                source: source,
                parameters: skill.parameters,
                tools: skill.tools,
                model: skill.model,
                tags: skill.tags,
              ),
            );
          } catch (_) {
            // Skip malformed skill files.
          }
        }
      }
    }
  }
}
