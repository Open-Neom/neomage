/// Plugin Schemas and Validation
///
/// Ported from neom_claw/src/utils/plugins/schemas.ts and validatePlugin.ts
///
/// This module provides:
/// - Plugin manifest schema definitions and validation
/// - Marketplace manifest schema definitions and validation
/// - Plugin component file (skill/agent/command) frontmatter validation
/// - Hooks.json validation
/// - Official marketplace name impersonation detection
/// - Path traversal security checks
library;

import 'dart:convert' show jsonDecode;
import 'package:neom_claw/core/platform/claw_io.dart';
import 'package:path/path.dart' as path;

// ---------------------------------------------------------------------------
// Official marketplace name protection
// ---------------------------------------------------------------------------

/// Official marketplace names reserved for Anthropic/NeomClaw official use.
/// These names are allowed ONLY for official marketplaces and blocked for third parties.
const Set<String> allowedOfficialMarketplaceNames = {
  'neom-claw-marketplace',
  'neom-claw-plugins',
  'neom-claw-plugins-official',
  'anthropic-marketplace',
  'anthropic-plugins',
  'agent-skills',
  'life-sciences',
  'knowledge-work-plugins',
};

/// Official marketplaces that should NOT auto-update by default.
const Set<String> _noAutoUpdateOfficialMarketplaces = {
  'knowledge-work-plugins',
};

/// Check if auto-update is enabled for a marketplace.
/// Uses the stored value if set, otherwise defaults based on whether
/// it's an official Anthropic marketplace (true) or not (false).
bool isMarketplaceAutoUpdate(String marketplaceName, {bool? autoUpdate}) {
  final normalizedName = marketplaceName.toLowerCase();
  return autoUpdate ??
      (allowedOfficialMarketplaceNames.contains(normalizedName) &&
          !_noAutoUpdateOfficialMarketplaces.contains(normalizedName));
}

/// Pattern to detect names that impersonate official Anthropic/NeomClaw marketplaces.
final RegExp blockedOfficialNamePattern = RegExp(
  r'(?:official[^a-z0-9]*(anthropic|neomclaw)|(?:anthropic|neomclaw)[^a-z0-9]*official|^(?:anthropic|neomclaw)[^a-z0-9]*(marketplace|plugins|official))',
  caseSensitive: false,
);

/// Pattern to detect non-ASCII characters for homograph attack prevention.
final RegExp _nonAsciiPattern = RegExp(r'[^\u0020-\u007E]');

/// Check if a marketplace name impersonates an official Anthropic/NeomClaw marketplace.
bool isBlockedOfficialName(String name) {
  if (allowedOfficialMarketplaceNames.contains(name.toLowerCase())) {
    return false;
  }
  if (_nonAsciiPattern.hasMatch(name)) {
    return true;
  }
  return blockedOfficialNamePattern.hasMatch(name);
}

/// The official GitHub organization for Anthropic marketplaces.
const String officialGithubOrg = 'anthropics';

/// Validate that a marketplace with a reserved name comes from the official source.
String? validateOfficialNameSource(String name, PluginSourceConfig source) {
  final normalizedName = name.toLowerCase();
  if (!allowedOfficialMarketplaceNames.contains(normalizedName)) {
    return null;
  }

  if (source.type == 'github') {
    final repo = source.repo ?? '';
    if (!repo.toLowerCase().startsWith('$officialGithubOrg/')) {
      return "The name '$name' is reserved for official Anthropic marketplaces. "
          "Only repositories from 'github.com/$officialGithubOrg/' can use this name.";
    }
    return null;
  }

  if (source.type == 'git' && source.url != null) {
    final url = source.url!.toLowerCase();
    final isHttpsAnthropics = url.contains('github.com/anthropics/');
    final isSshAnthropics = url.contains('git@github.com:anthropics/');
    if (isHttpsAnthropics || isSshAnthropics) {
      return null;
    }
    return "The name '$name' is reserved for official Anthropic marketplaces. "
        "Only repositories from 'github.com/$officialGithubOrg/' can use this name.";
  }

  return "The name '$name' is reserved for official Anthropic marketplaces and "
      "can only be used with GitHub sources from the '$officialGithubOrg' organization.";
}

// ---------------------------------------------------------------------------
// Data models (ported from Zod schemas)
// ---------------------------------------------------------------------------

/// Plugin source configuration for marketplace validation.
class PluginSourceConfig {
  final String type;
  final String? repo;
  final String? url;

  const PluginSourceConfig({required this.type, this.repo, this.url});
}

/// Plugin author information.
class PluginAuthor {
  final String name;
  final String? email;
  final String? url;

  const PluginAuthor({required this.name, this.email, this.url});

  factory PluginAuthor.fromJson(Map<String, dynamic> json) {
    return PluginAuthor(
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      url: json['url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (email != null) 'email': email,
    if (url != null) 'url': url,
  };
}

/// User-configurable option in plugin manifest.
class PluginUserConfigOption {
  final String type;
  final String title;
  final String description;
  final bool? required;
  final dynamic defaultValue;
  final bool? multiple;
  final bool? sensitive;
  final num? min;
  final num? max;

  const PluginUserConfigOption({
    required this.type,
    required this.title,
    required this.description,
    this.required,
    this.defaultValue,
    this.multiple,
    this.sensitive,
    this.min,
    this.max,
  });

  factory PluginUserConfigOption.fromJson(Map<String, dynamic> json) {
    return PluginUserConfigOption(
      type: json['type'] as String? ?? 'string',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      required: json['required'] as bool?,
      defaultValue: json['default'],
      multiple: json['multiple'] as bool?,
      sensitive: json['sensitive'] as bool?,
      min: json['min'] as num?,
      max: json['max'] as num?,
    );
  }

  Map<String, dynamic> toJson() => {
    'type': type,
    'title': title,
    'description': description,
    if (required != null) 'required': required,
    if (defaultValue != null) 'default': defaultValue,
    if (multiple != null) 'multiple': multiple,
    if (sensitive != null) 'sensitive': sensitive,
    if (min != null) 'min': min,
    if (max != null) 'max': max,
  };

  static const validTypes = [
    'string',
    'number',
    'boolean',
    'directory',
    'file',
  ];
}

/// Command metadata for plugin manifest or marketplace entry.
class CommandMetadata {
  final String? source;
  final String? content;
  final String? description;
  final String? argumentHint;
  final String? model;
  final List<String>? allowedTools;

  const CommandMetadata({
    this.source,
    this.content,
    this.description,
    this.argumentHint,
    this.model,
    this.allowedTools,
  });

  factory CommandMetadata.fromJson(Map<String, dynamic> json) {
    return CommandMetadata(
      source: json['source'] as String?,
      content: json['content'] as String?,
      description: json['description'] as String?,
      argumentHint: json['argumentHint'] as String?,
      model: json['model'] as String?,
      allowedTools: (json['allowedTools'] as List?)?.cast<String>(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (source != null) 'source': source,
    if (content != null) 'content': content,
    if (description != null) 'description': description,
    if (argumentHint != null) 'argumentHint': argumentHint,
    if (model != null) 'model': model,
    if (allowedTools != null) 'allowedTools': allowedTools,
  };

  /// Validate that exactly one of source or content is present.
  bool get isValid =>
      (source != null && content == null) ||
      (source == null && content != null);
}

/// Plugin manifest (plugin.json) data model.
class PluginManifest {
  final String name;
  final String? version;
  final String? description;
  final PluginAuthor? author;
  final String? homepage;
  final String? repository;
  final String? license;
  final List<String>? keywords;
  final List<String>? dependencies;
  final Map<String, dynamic>? hooks;
  final dynamic commands;
  final dynamic agents;
  final dynamic skills;
  final dynamic outputStyles;
  final Map<String, dynamic>? mcpServers;
  final Map<String, PluginUserConfigOption>? userConfig;
  final List<Map<String, dynamic>>? channels;

  const PluginManifest({
    required this.name,
    this.version,
    this.description,
    this.author,
    this.homepage,
    this.repository,
    this.license,
    this.keywords,
    this.dependencies,
    this.hooks,
    this.commands,
    this.agents,
    this.skills,
    this.outputStyles,
    this.mcpServers,
    this.userConfig,
    this.channels,
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    return PluginManifest(
      name: json['name'] as String? ?? '',
      version: json['version'] as String?,
      description: json['description'] as String?,
      author: json['author'] is Map<String, dynamic>
          ? PluginAuthor.fromJson(json['author'] as Map<String, dynamic>)
          : null,
      homepage: json['homepage'] as String?,
      repository: json['repository'] as String?,
      license: json['license'] as String?,
      keywords: (json['keywords'] as List?)?.cast<String>(),
      dependencies: (json['dependencies'] as List?)?.cast<String>(),
      hooks: json['hooks'] as Map<String, dynamic>?,
      commands: json['commands'],
      agents: json['agents'],
      skills: json['skills'],
      outputStyles: json['outputStyles'],
      mcpServers: json['mcpServers'] as Map<String, dynamic>?,
      userConfig: json['userConfig'] is Map<String, dynamic>
          ? (json['userConfig'] as Map<String, dynamic>).map(
              (k, v) => MapEntry(
                k,
                PluginUserConfigOption.fromJson(v as Map<String, dynamic>),
              ),
            )
          : null,
      channels: (json['channels'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
  }
}

/// Marketplace entry for a plugin.
class PluginMarketplaceEntry {
  final String name;
  final String? description;
  final String? version;
  final dynamic source;
  final String? category;
  final List<String>? tags;
  final bool? strict;
  final String? id;
  final bool? autoUpdate;

  const PluginMarketplaceEntry({
    required this.name,
    this.description,
    this.version,
    this.source,
    this.category,
    this.tags,
    this.strict,
    this.id,
    this.autoUpdate,
  });

  factory PluginMarketplaceEntry.fromJson(Map<String, dynamic> json) {
    return PluginMarketplaceEntry(
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      version: json['version'] as String?,
      source: json['source'],
      category: json['category'] as String?,
      tags: (json['tags'] as List?)?.cast<String>(),
      strict: json['strict'] as bool?,
      id: json['id'] as String?,
      autoUpdate: json['autoUpdate'] as bool?,
    );
  }
}

/// Marketplace manifest data model.
class PluginMarketplace {
  final String name;
  final List<PluginMarketplaceEntry> plugins;
  final MarketplaceMetadata? metadata;

  const PluginMarketplace({
    required this.name,
    required this.plugins,
    this.metadata,
  });

  factory PluginMarketplace.fromJson(Map<String, dynamic> json) {
    return PluginMarketplace(
      name: json['name'] as String? ?? '',
      plugins:
          (json['plugins'] as List?)
              ?.map(
                (e) =>
                    PluginMarketplaceEntry.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      metadata: json['metadata'] is Map<String, dynamic>
          ? MarketplaceMetadata.fromJson(
              json['metadata'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

/// Marketplace metadata.
class MarketplaceMetadata {
  final String? description;
  final String? homepage;

  const MarketplaceMetadata({this.description, this.homepage});

  factory MarketplaceMetadata.fromJson(Map<String, dynamic> json) {
    return MarketplaceMetadata(
      description: json['description'] as String?,
      homepage: json['homepage'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// Validation types
// ---------------------------------------------------------------------------

/// Type of file being validated.
enum PluginFileType { plugin, marketplace, skill, agent, command, hooks }

/// A single validation error.
class ValidationError {
  final String path;
  final String message;
  final String? code;

  const ValidationError({required this.path, required this.message, this.code});

  @override
  String toString() => '$path: $message';
}

/// A single validation warning.
class ValidationWarning {
  final String path;
  final String message;

  const ValidationWarning({required this.path, required this.message});

  @override
  String toString() => '$path: $message';
}

/// Result of validating a plugin file.
class ValidationResult {
  final bool success;
  final List<ValidationError> errors;
  final List<ValidationWarning> warnings;
  final String filePath;
  final PluginFileType fileType;

  const ValidationResult({
    required this.success,
    required this.errors,
    required this.warnings,
    required this.filePath,
    required this.fileType,
  });
}

// ---------------------------------------------------------------------------
// Marketplace-only fields (warn in plugin.json)
// ---------------------------------------------------------------------------

/// Fields that belong in marketplace.json but not plugin.json.
const Set<String> _marketplaceOnlyManifestFields = {
  'category',
  'source',
  'tags',
  'strict',
  'id',
};

// ---------------------------------------------------------------------------
// Path traversal checking
// ---------------------------------------------------------------------------

/// Check for parent-directory segments ('..') in a path string.
void _checkPathTraversal(
  String p,
  String field,
  List<ValidationError> errors, {
  String? hint,
}) {
  if (p.contains('..')) {
    errors.add(
      ValidationError(
        path: field,
        message: hint != null
            ? 'Path contains "..": $p. $hint'
            : 'Path contains ".." which could be a path traversal attempt: $p',
      ),
    );
  }
}

/// Compute a tailored hint for marketplace source path traversal.
String _marketplaceSourceHint(String p) {
  final stripped = p.replaceAll(RegExp(r'^(\.\./)+'), '');
  final corrected = stripped != p ? './$stripped' : './plugins/my-plugin';
  return 'Plugin source paths are resolved relative to the marketplace root '
      '(the directory containing .neomclaw-plugin/), not relative to marketplace.json. '
      'Use "$corrected" instead of "$p".';
}

// ---------------------------------------------------------------------------
// Manifest name validation
// ---------------------------------------------------------------------------

/// Validate a marketplace name string.
List<ValidationError> validateMarketplaceName(String name) {
  final errors = <ValidationError>[];

  if (name.isEmpty) {
    errors.add(
      const ValidationError(
        path: 'name',
        message: 'Marketplace must have a name',
      ),
    );
    return errors;
  }

  if (name.contains(' ')) {
    errors.add(
      const ValidationError(
        path: 'name',
        message:
            'Marketplace name cannot contain spaces. Use kebab-case (e.g., "my-marketplace")',
      ),
    );
  }

  if (name.contains('/') ||
      name.contains(r'\') ||
      name.contains('..') ||
      name == '.') {
    errors.add(
      const ValidationError(
        path: 'name',
        message:
            'Marketplace name cannot contain path separators (/ or \\), ".." sequences, or be "."',
      ),
    );
  }

  if (isBlockedOfficialName(name)) {
    errors.add(
      const ValidationError(
        path: 'name',
        message:
            'Marketplace name impersonates an official Anthropic/NeomClaw marketplace',
      ),
    );
  }

  if (name.toLowerCase() == 'inline') {
    errors.add(
      const ValidationError(
        path: 'name',
        message:
            'Marketplace name "inline" is reserved for --plugin-dir session plugins',
      ),
    );
  }

  if (name.toLowerCase() == 'builtin') {
    errors.add(
      const ValidationError(
        path: 'name',
        message: 'Marketplace name "builtin" is reserved for built-in plugins',
      ),
    );
  }

  return errors;
}

// ---------------------------------------------------------------------------
// Plugin manifest validation
// ---------------------------------------------------------------------------

/// Validate a plugin manifest file (plugin.json).
Future<ValidationResult> validatePluginManifest(String filePath) async {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final absolutePath = path.absolute(filePath);

  // Read file
  String content;
  try {
    content = await File(absolutePath).readAsString();
  } on FileSystemException catch (e) {
    final message = e.osError?.errorCode == 2
        ? 'File not found: $absolutePath'
        : 'Failed to read file: ${e.message}';
    return ValidationResult(
      success: false,
      errors: [ValidationError(path: 'file', message: message)],
      warnings: [],
      filePath: absolutePath,
      fileType: PluginFileType.plugin,
    );
  }

  // Parse JSON
  Map<String, dynamic> parsed;
  try {
    final decoded = _jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return ValidationResult(
        success: false,
        errors: [
          const ValidationError(
            path: 'json',
            message: 'Root must be a JSON object',
          ),
        ],
        warnings: [],
        filePath: absolutePath,
        fileType: PluginFileType.plugin,
      );
    }
    parsed = decoded;
  } catch (e) {
    return ValidationResult(
      success: false,
      errors: [
        ValidationError(path: 'json', message: 'Invalid JSON syntax: $e'),
      ],
      warnings: [],
      filePath: absolutePath,
      fileType: PluginFileType.plugin,
    );
  }

  // Check path traversal before schema validation
  _checkPathTraversalInManifest(parsed, errors);

  // Strip marketplace-only fields and warn
  final strayKeys = parsed.keys
      .where(_marketplaceOnlyManifestFields.contains)
      .toList();
  for (final key in strayKeys) {
    warnings.add(
      ValidationWarning(
        path: key,
        message:
            "Field '$key' belongs in the marketplace entry (marketplace.json), "
            "not plugin.json. It's harmless here but unused -- NeomClaw "
            "ignores it at load time.",
      ),
    );
  }

  // Validate required fields
  if (!parsed.containsKey('name') || parsed['name'] is! String) {
    errors.add(
      const ValidationError(
        path: 'name',
        message: 'Plugin name is required and must be a string',
      ),
    );
  } else {
    final name = parsed['name'] as String;
    if (name.isEmpty) {
      errors.add(
        const ValidationError(
          path: 'name',
          message: 'Plugin name cannot be empty',
        ),
      );
    }
    if (name.contains(' ')) {
      errors.add(
        const ValidationError(
          path: 'name',
          message:
              'Plugin name cannot contain spaces. Use kebab-case (e.g., "my-plugin")',
        ),
      );
    }
    // Kebab-case warning
    if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name)) {
      warnings.add(
        ValidationWarning(
          path: 'name',
          message:
              'Plugin name "$name" is not kebab-case. NeomClaw accepts '
              'it, but the NeomClaw.ai marketplace sync requires kebab-case '
              '(lowercase letters, digits, and hyphens only, e.g., "my-plugin").',
        ),
      );
    }
  }

  // Warn for missing optional fields
  if (!parsed.containsKey('version') || parsed['version'] == null) {
    warnings.add(
      const ValidationWarning(
        path: 'version',
        message:
            'No version specified. Consider adding a version following semver (e.g., "1.0.0")',
      ),
    );
  }

  if (!parsed.containsKey('description') || parsed['description'] == null) {
    warnings.add(
      const ValidationWarning(
        path: 'description',
        message:
            'No description provided. Adding a description helps users understand what your plugin does',
      ),
    );
  }

  if (!parsed.containsKey('author') || parsed['author'] == null) {
    warnings.add(
      const ValidationWarning(
        path: 'author',
        message:
            'No author information provided. Consider adding author details for plugin attribution',
      ),
    );
  }

  return ValidationResult(
    success: errors.isEmpty,
    errors: errors,
    warnings: warnings,
    filePath: absolutePath,
    fileType: PluginFileType.plugin,
  );
}

/// Check path traversal in manifest commands, agents, and skills arrays.
void _checkPathTraversalInManifest(
  Map<String, dynamic> obj,
  List<ValidationError> errors,
) {
  void checkArray(String fieldName) {
    if (!obj.containsKey(fieldName)) return;
    final items = obj[fieldName] is List
        ? obj[fieldName] as List
        : [obj[fieldName]];
    for (var i = 0; i < items.length; i++) {
      if (items[i] is String) {
        _checkPathTraversal(items[i] as String, '$fieldName[$i]', errors);
      }
    }
  }

  checkArray('commands');
  checkArray('agents');
  checkArray('skills');
}

// ---------------------------------------------------------------------------
// Marketplace manifest validation
// ---------------------------------------------------------------------------

/// Validate a marketplace manifest file (marketplace.json).
Future<ValidationResult> validateMarketplaceManifest(String filePath) async {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];
  final absolutePath = path.absolute(filePath);

  // Read file
  String content;
  try {
    content = await File(absolutePath).readAsString();
  } on FileSystemException catch (e) {
    final code = e.osError?.errorCode == 2 ? 'ENOENT' : null;
    final message = code == 'ENOENT'
        ? 'File not found: $absolutePath'
        : 'Failed to read file: ${e.message}';
    return ValidationResult(
      success: false,
      errors: [ValidationError(path: 'file', message: message, code: code)],
      warnings: [],
      filePath: absolutePath,
      fileType: PluginFileType.marketplace,
    );
  }

  // Parse JSON
  Map<String, dynamic> parsed;
  try {
    final decoded = _jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      return ValidationResult(
        success: false,
        errors: [
          const ValidationError(
            path: 'json',
            message: 'Root must be a JSON object',
          ),
        ],
        warnings: [],
        filePath: absolutePath,
        fileType: PluginFileType.marketplace,
      );
    }
    parsed = decoded;
  } catch (e) {
    return ValidationResult(
      success: false,
      errors: [
        ValidationError(path: 'json', message: 'Invalid JSON syntax: $e'),
      ],
      warnings: [],
      filePath: absolutePath,
      fileType: PluginFileType.marketplace,
    );
  }

  // Check path traversal in plugin sources
  if (parsed['plugins'] is List) {
    final plugins = parsed['plugins'] as List;
    for (var i = 0; i < plugins.length; i++) {
      final plugin = plugins[i];
      if (plugin is Map && plugin.containsKey('source')) {
        final source = plugin['source'];
        if (source is String) {
          _checkPathTraversal(
            source,
            'plugins[$i].source',
            errors,
            hint: _marketplaceSourceHint(source),
          );
        }
        if (source is Map &&
            source.containsKey('path') &&
            source['path'] is String) {
          _checkPathTraversal(
            source['path'] as String,
            'plugins[$i].source.path',
            errors,
          );
        }
      }
    }
  }

  // Validate marketplace name
  if (parsed.containsKey('name') && parsed['name'] is String) {
    errors.addAll(validateMarketplaceName(parsed['name'] as String));
  } else {
    errors.add(
      const ValidationError(
        path: 'name',
        message: 'Marketplace must have a name',
      ),
    );
  }

  // Validate plugins array
  if (!parsed.containsKey('plugins') || parsed['plugins'] is! List) {
    warnings.add(
      const ValidationWarning(
        path: 'plugins',
        message: 'Marketplace has no plugins defined',
      ),
    );
  } else {
    final plugins = (parsed['plugins'] as List)
        .map(
          (e) => PluginMarketplaceEntry.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();

    // Check for duplicates
    for (var i = 0; i < plugins.length; i++) {
      final duplicates = plugins.where((p) => p.name == plugins[i].name);
      if (duplicates.length > 1) {
        errors.add(
          ValidationError(
            path: 'plugins[$i].name',
            message:
                'Duplicate plugin name "${plugins[i].name}" found in marketplace',
          ),
        );
      }
    }
  }

  // Warn if no description in metadata
  if (parsed['metadata'] is! Map ||
      (parsed['metadata'] as Map?)?['description'] == null) {
    warnings.add(
      const ValidationWarning(
        path: 'metadata.description',
        message:
            'No marketplace description provided. Adding a description helps users understand what this marketplace offers',
      ),
    );
  }

  return ValidationResult(
    success: errors.isEmpty,
    errors: errors,
    warnings: warnings,
    filePath: absolutePath,
    fileType: PluginFileType.marketplace,
  );
}

// ---------------------------------------------------------------------------
// Component file validation (skill/agent/command frontmatter)
// ---------------------------------------------------------------------------

/// Regex for detecting YAML frontmatter blocks.
final RegExp _frontmatterRegex = RegExp(r'^---\s*\n([\s\S]*?)\n---\s*\n');

/// Validate the YAML frontmatter in a plugin component markdown file.
ValidationResult validateComponentFile(
  String filePath,
  String content,
  PluginFileType fileType,
) {
  final errors = <ValidationError>[];
  final warnings = <ValidationWarning>[];

  final match = _frontmatterRegex.firstMatch(content);
  if (match == null) {
    warnings.add(
      ValidationWarning(
        path: 'frontmatter',
        message:
            'No frontmatter block found. Add YAML frontmatter between --- delimiters '
            'at the top of the file to set description and other metadata.',
      ),
    );
    return ValidationResult(
      success: true,
      errors: errors,
      warnings: warnings,
      filePath: filePath,
      fileType: fileType,
    );
  }

  // Note: Full YAML parsing would require a yaml package dependency.
  // Here we do basic key-value extraction for validation purposes.
  final frontmatterText = match.group(1) ?? '';
  final lines = frontmatterText.split('\n');
  final fields = <String, String>{};
  for (final line in lines) {
    final colonIdx = line.indexOf(':');
    if (colonIdx > 0) {
      final key = line.substring(0, colonIdx).trim();
      final value = line.substring(colonIdx + 1).trim();
      fields[key] = value;
    }
  }

  // Check description
  if (!fields.containsKey('description')) {
    final typeStr = fileType.name;
    warnings.add(
      ValidationWarning(
        path: 'description',
        message:
            'No description in frontmatter. A description helps users and NeomClaw '
            'understand when to use this $typeStr.',
      ),
    );
  }

  // Check shell field
  if (fields.containsKey('shell')) {
    final sh = fields['shell']!.trim().toLowerCase();
    if (sh != 'bash' && sh != 'powershell') {
      errors.add(
        ValidationError(
          path: 'shell',
          message:
              "shell must be 'bash' or 'powershell', got '${fields['shell']}'.",
        ),
      );
    }
  }

  return ValidationResult(
    success: errors.isEmpty,
    errors: errors,
    warnings: warnings,
    filePath: filePath,
    fileType: fileType,
  );
}

// ---------------------------------------------------------------------------
// Hooks.json validation
// ---------------------------------------------------------------------------

/// Validate a plugin's hooks.json file.
Future<ValidationResult> validateHooksJson(String filePath) async {
  String content;
  try {
    content = await File(filePath).readAsString();
  } on FileSystemException catch (e) {
    if (e.osError?.errorCode == 2) {
      // ENOENT is fine -- hooks are optional
      return ValidationResult(
        success: true,
        errors: const [],
        warnings: const [],
        filePath: filePath,
        fileType: PluginFileType.hooks,
      );
    }
    return ValidationResult(
      success: false,
      errors: [
        ValidationError(
          path: 'file',
          message: 'Failed to read file: ${e.message}',
        ),
      ],
      warnings: const [],
      filePath: filePath,
      fileType: PluginFileType.hooks,
    );
  }

  try {
    final parsed = _jsonDecode(content);
    if (parsed is! Map<String, dynamic>) {
      return ValidationResult(
        success: false,
        errors: [
          const ValidationError(
            path: 'json',
            message: 'hooks.json root must be a JSON object',
          ),
        ],
        warnings: const [],
        filePath: filePath,
        fileType: PluginFileType.hooks,
      );
    }
    // Validate hooks field presence
    if (!parsed.containsKey('hooks')) {
      return ValidationResult(
        success: false,
        errors: [
          const ValidationError(
            path: 'hooks',
            message: 'hooks.json must contain a "hooks" field',
          ),
        ],
        warnings: const [],
        filePath: filePath,
        fileType: PluginFileType.hooks,
      );
    }
  } catch (e) {
    return ValidationResult(
      success: false,
      errors: [
        ValidationError(
          path: 'json',
          message:
              'Invalid JSON syntax: $e. '
              'At runtime this breaks the entire plugin load.',
        ),
      ],
      warnings: const [],
      filePath: filePath,
      fileType: PluginFileType.hooks,
    );
  }

  return ValidationResult(
    success: true,
    errors: const [],
    warnings: const [],
    filePath: filePath,
    fileType: PluginFileType.hooks,
  );
}

// ---------------------------------------------------------------------------
// Plugin contents validation
// ---------------------------------------------------------------------------

/// Recursively collect .md files under a directory.
Future<List<String>> _collectMarkdown(String dir, bool isSkillsDir) async {
  List<FileSystemEntity> entries;
  try {
    entries = await Directory(dir).list().toList();
  } on FileSystemException {
    return [];
  }

  if (isSkillsDir) {
    return entries
        .whereType<Directory>()
        .map((e) => path.join(e.path, 'SKILL.md'))
        .toList();
  }

  final out = <String>[];
  for (final entry in entries) {
    if (entry is Directory) {
      out.addAll(await _collectMarkdown(entry.path, false));
    } else if (entry is File && entry.path.toLowerCase().endsWith('.md')) {
      out.add(entry.path);
    }
  }
  return out;
}

/// Validate the content files inside a plugin directory.
Future<List<ValidationResult>> validatePluginContents(String pluginDir) async {
  final results = <ValidationResult>[];

  final dirs = <PluginFileType, String>{
    PluginFileType.skill: path.join(pluginDir, 'skills'),
    PluginFileType.agent: path.join(pluginDir, 'agents'),
    PluginFileType.command: path.join(pluginDir, 'commands'),
  };

  for (final entry in dirs.entries) {
    final fileType = entry.key;
    final dir = entry.value;
    final files = await _collectMarkdown(dir, fileType == PluginFileType.skill);
    for (final filePath in files) {
      String content;
      try {
        content = await File(filePath).readAsString();
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 2) continue; // ENOENT expected for skills
        results.add(
          ValidationResult(
            success: false,
            errors: [
              ValidationError(
                path: 'file',
                message: 'Failed to read: ${e.message}',
              ),
            ],
            warnings: const [],
            filePath: filePath,
            fileType: fileType,
          ),
        );
        continue;
      }
      final r = validateComponentFile(filePath, content, fileType);
      if (r.errors.isNotEmpty || r.warnings.isNotEmpty) {
        results.add(r);
      }
    }
  }

  final hooksResult = await validateHooksJson(
    path.join(pluginDir, 'hooks', 'hooks.json'),
  );
  if (hooksResult.errors.isNotEmpty || hooksResult.warnings.isNotEmpty) {
    results.add(hooksResult);
  }

  return results;
}

// ---------------------------------------------------------------------------
// Auto-detect and validate manifest
// ---------------------------------------------------------------------------

/// Detect whether a file is a plugin manifest or marketplace manifest.
String _detectManifestType(String filePath) {
  final fileName = path.basename(filePath);
  final dirName = path.basename(path.dirname(filePath));

  if (fileName == 'plugin.json') return 'plugin';
  if (fileName == 'marketplace.json') return 'marketplace';
  if (dirName == '.neomclaw-plugin') return 'plugin';

  return 'unknown';
}

/// Validate a manifest file or directory (auto-detects type).
Future<ValidationResult> validateManifest(String filePath) async {
  final absolutePath = path.absolute(filePath);

  // Check if it's a directory
  final entityType = await FileSystemEntity.type(absolutePath);
  if (entityType == FileSystemEntityType.directory) {
    // Look for manifest files in .neomclaw-plugin directory
    final marketplacePath = path.join(
      absolutePath,
      '.neomclaw-plugin',
      'marketplace.json',
    );
    final marketplaceResult = await validateMarketplaceManifest(
      marketplacePath,
    );
    if (marketplaceResult.errors.isEmpty ||
        marketplaceResult.errors.first.code != 'ENOENT') {
      return marketplaceResult;
    }

    final pluginPath = path.join(
      absolutePath,
      '.neomclaw-plugin',
      'plugin.json',
    );
    final pluginResult = await validatePluginManifest(pluginPath);
    if (pluginResult.errors.isEmpty ||
        pluginResult.errors.first.code != 'ENOENT') {
      return pluginResult;
    }

    return ValidationResult(
      success: false,
      errors: [
        const ValidationError(
          path: 'directory',
          message:
              'No manifest found in directory. Expected .neomclaw-plugin/marketplace.json or .neomclaw-plugin/plugin.json',
        ),
      ],
      warnings: const [],
      filePath: absolutePath,
      fileType: PluginFileType.plugin,
    );
  }

  final manifestType = _detectManifestType(filePath);

  switch (manifestType) {
    case 'plugin':
      return validatePluginManifest(filePath);
    case 'marketplace':
      return validateMarketplaceManifest(filePath);
    case 'unknown':
    default:
      // Try to parse and guess based on content
      try {
        final content = await File(absolutePath).readAsString();
        final parsed = _jsonDecode(content);
        if (parsed is Map<String, dynamic> && parsed['plugins'] is List) {
          return validateMarketplaceManifest(filePath);
        }
      } on FileSystemException catch (e) {
        if (e.osError?.errorCode == 2) {
          return ValidationResult(
            success: false,
            errors: [
              ValidationError(
                path: 'file',
                message: 'File not found: $absolutePath',
              ),
            ],
            warnings: const [],
            filePath: absolutePath,
            fileType: PluginFileType.plugin,
          );
        }
      } catch (_) {
        // Fall through to default
      }
      return validatePluginManifest(filePath);
  }
}

// ---------------------------------------------------------------------------
// JSON decode helper
// ---------------------------------------------------------------------------

/// Safe JSON decode that handles errors consistently.
/// Wraps dart:convert jsonDecode to mirror the TS jsonParse behavior.
dynamic _jsonDecode(String source) {
  return jsonDecode(source);
}
