// Migration service — port of neom_claw/src/utils/migration/.
// Settings migration, session format upgrades, version checks.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

/// Current configuration format version.
const currentConfigVersion = 3;

/// Current session format version.
const currentSessionVersion = 2;

/// Migration step definition.
class Migration {
  final int fromVersion;
  final int toVersion;
  final String description;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> data) migrate;

  const Migration({
    required this.fromVersion,
    required this.toVersion,
    required this.description,
    required this.migrate,
  });
}

/// Result of running migrations.
class MigrationResult {
  final bool success;
  final int fromVersion;
  final int toVersion;
  final List<String> migrationsApplied;
  final List<String> errors;
  final String? backupPath;

  const MigrationResult({
    required this.success,
    required this.fromVersion,
    required this.toVersion,
    this.migrationsApplied = const [],
    this.errors = const [],
    this.backupPath,
  });
}

// ─── Settings migrations ───

/// All settings migrations in order.
final settingsMigrations = <Migration>[
  // v1 → v2: Flatten permission rules, add sandbox settings
  Migration(
    fromVersion: 1,
    toVersion: 2,
    description: 'Flatten permission rules, add sandbox config',
    migrate: (data) async {
      final result = Map<String, dynamic>.from(data);
      // Move nested permissions to flat structure
      if (result.containsKey('permissions')) {
        final perms = result['permissions'];
        if (perms is Map && perms.containsKey('rules')) {
          result['permissionRules'] = perms['rules'];
          result['permissionMode'] = perms['mode'] ?? 'default';
        }
      }
      // Add default sandbox settings
      result.putIfAbsent('sandbox', () => {
            'enabled': false,
            'writePaths': <String>['.'],
            'readPaths': <String>['/'],
          });
      result['configVersion'] = 2;
      return result;
    },
  ),
  // v2 → v3: Add model overrides, MCP server configs
  Migration(
    fromVersion: 2,
    toVersion: 3,
    description: 'Add model overrides, MCP server configs',
    migrate: (data) async {
      final result = Map<String, dynamic>.from(data);
      result.putIfAbsent('modelOverrides', () => <String, dynamic>{});
      result.putIfAbsent('mcpServers', () => <String, dynamic>{});
      result.putIfAbsent('hooks', () => <String, dynamic>{});
      // Migrate old model names
      if (result['model'] is String) {
        result['model'] = _remapModelName(result['model'] as String);
      }
      result['configVersion'] = 3;
      return result;
    },
  ),
];

/// All session migrations in order.
final sessionMigrations = <Migration>[
  // v1 → v2: Add token tracking, cost field
  Migration(
    fromVersion: 1,
    toVersion: 2,
    description: 'Add token tracking and cost fields',
    migrate: (data) async {
      final result = Map<String, dynamic>.from(data);
      result.putIfAbsent('totalInputTokens', () => 0);
      result.putIfAbsent('totalOutputTokens', () => 0);
      result.putIfAbsent('totalCost', () => 0.0);
      result.putIfAbsent('cacheReadTokens', () => 0);
      result.putIfAbsent('cacheCreationTokens', () => 0);
      // Add model field to each message if missing
      final messages = result['messages'] as List?;
      if (messages != null) {
        for (final msg in messages) {
          if (msg is Map && !msg.containsKey('model')) {
            msg['model'] = result['model'] ?? 'unknown';
          }
        }
      }
      result['sessionVersion'] = 2;
      return result;
    },
  ),
];

/// Remap deprecated model names.
String _remapModelName(String model) {
  const remap = {
    'claude-3-opus-20240229': 'claude-opus-4-20250514',
    'claude-3-sonnet-20240229': 'claude-sonnet-4-20250514',
    'claude-3-haiku-20240307': 'claude-haiku-3-5-20241022',
    'claude-3.5-sonnet-20240620': 'claude-sonnet-4-5-20250514',
    'claude-3.5-sonnet-20241022': 'claude-sonnet-4-5-20250514',
    'claude-3.5-haiku-20241022': 'claude-haiku-3-5-20241022',
  };
  return remap[model] ?? model;
}

/// Run migrations on settings data.
Future<MigrationResult> migrateSettings(
    Map<String, dynamic> data) async {
  final fromVersion =
      (data['configVersion'] as int?) ?? 1;
  if (fromVersion >= currentConfigVersion) {
    return MigrationResult(
      success: true,
      fromVersion: fromVersion,
      toVersion: fromVersion,
    );
  }

  var current = Map<String, dynamic>.from(data);
  final applied = <String>[];
  final errors = <String>[];

  for (final migration in settingsMigrations) {
    if (migration.fromVersion >= fromVersion &&
        migration.toVersion <= currentConfigVersion) {
      try {
        current = await migration.migrate(current);
        applied.add(
            'v${migration.fromVersion}→v${migration.toVersion}: ${migration.description}');
      } catch (e) {
        errors.add(
            'v${migration.fromVersion}→v${migration.toVersion} failed: $e');
        break;
      }
    }
  }

  return MigrationResult(
    success: errors.isEmpty,
    fromVersion: fromVersion,
    toVersion: (current['configVersion'] as int?) ?? currentConfigVersion,
    migrationsApplied: applied,
    errors: errors,
  );
}

/// Run migrations on session data.
Future<MigrationResult> migrateSession(
    Map<String, dynamic> data) async {
  final fromVersion =
      (data['sessionVersion'] as int?) ?? 1;
  if (fromVersion >= currentSessionVersion) {
    return MigrationResult(
      success: true,
      fromVersion: fromVersion,
      toVersion: fromVersion,
    );
  }

  var current = Map<String, dynamic>.from(data);
  final applied = <String>[];
  final errors = <String>[];

  for (final migration in sessionMigrations) {
    if (migration.fromVersion >= fromVersion &&
        migration.toVersion <= currentSessionVersion) {
      try {
        current = await migration.migrate(current);
        applied.add(
            'v${migration.fromVersion}→v${migration.toVersion}: ${migration.description}');
      } catch (e) {
        errors.add(
            'v${migration.fromVersion}→v${migration.toVersion} failed: $e');
        break;
      }
    }
  }

  return MigrationResult(
    success: errors.isEmpty,
    fromVersion: fromVersion,
    toVersion: (current['sessionVersion'] as int?) ?? currentSessionVersion,
    migrationsApplied: applied,
    errors: errors,
  );
}

/// Migrate a settings file in place (with backup).
Future<MigrationResult> migrateSettingsFile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    return MigrationResult(
      success: false,
      fromVersion: 0,
      toVersion: 0,
      errors: ['File not found: $path'],
    );
  }

  final content = await file.readAsString();
  final data = jsonDecode(content) as Map<String, dynamic>;
  final fromVersion = (data['configVersion'] as int?) ?? 1;

  if (fromVersion >= currentConfigVersion) {
    return MigrationResult(
      success: true,
      fromVersion: fromVersion,
      toVersion: fromVersion,
    );
  }

  // Create backup
  final backupPath = '$path.backup.v$fromVersion';
  await file.copy(backupPath);

  final result = await migrateSettings(data);
  if (result.success) {
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data));
  }

  return MigrationResult(
    success: result.success,
    fromVersion: result.fromVersion,
    toVersion: result.toVersion,
    migrationsApplied: result.migrationsApplied,
    errors: result.errors,
    backupPath: backupPath,
  );
}

// ─── Version checks ───

/// Application version info.
class VersionInfo {
  final String version;
  final String buildDate;
  final String dartVersion;
  final String flutterVersion;
  final String platform;

  const VersionInfo({
    required this.version,
    required this.buildDate,
    required this.dartVersion,
    required this.flutterVersion,
    required this.platform,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'buildDate': buildDate,
        'dartVersion': dartVersion,
        'flutterVersion': flutterVersion,
        'platform': platform,
      };

  @override
  String toString() => 'Neom Claw v$version ($platform)';
}

/// Parse a semantic version string.
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final String? preRelease;

  const SemVer(this.major, this.minor, this.patch, [this.preRelease]);

  factory SemVer.parse(String version) {
    final cleaned =
        version.startsWith('v') ? version.substring(1) : version;
    final parts = cleaned.split('-');
    final numbers = parts[0].split('.');
    return SemVer(
      int.tryParse(numbers.elementAtOrNull(0) ?? '') ?? 0,
      int.tryParse(numbers.elementAtOrNull(1) ?? '') ?? 0,
      int.tryParse(numbers.elementAtOrNull(2) ?? '') ?? 0,
      parts.length > 1 ? parts.sublist(1).join('-') : null,
    );
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    // Pre-release versions have lower precedence
    if (preRelease != null && other.preRelease == null) return -1;
    if (preRelease == null && other.preRelease != null) return 1;
    return 0;
  }

  bool operator >(SemVer other) => compareTo(other) > 0;
  bool operator <(SemVer other) => compareTo(other) < 0;
  bool operator >=(SemVer other) => compareTo(other) >= 0;
  bool operator <=(SemVer other) => compareTo(other) <= 0;

  @override
  String toString() {
    final base = '$major.$minor.$patch';
    return preRelease != null ? '$base-$preRelease' : base;
  }
}

/// Check if an update is available.
Future<({bool available, String? latestVersion, String? releaseNotes})>
    checkForUpdate(String currentVersion) async {
  // In a real implementation, this would check a release API
  // For now, return no update available
  return (available: false, latestVersion: null, releaseNotes: null);
}

/// Import settings from an existing NeomClaw (Node.js) installation.
Future<Map<String, dynamic>?> importFromNeomClaw() async {
  final home = Platform.environment['HOME'] ?? '';
  final configPath = '$home/.neomclaw/settings.json';
  final file = File(configPath);

  if (!await file.exists()) return null;

  try {
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    // Convert Node.js NeomClaw settings to Neom Claw format
    return _convertNodeSettings(data);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _convertNodeSettings(Map<String, dynamic> nodeSettings) {
  return {
    'configVersion': currentConfigVersion,
    if (nodeSettings.containsKey('model'))
      'model': _remapModelName(nodeSettings['model'] as String),
    if (nodeSettings.containsKey('permissions'))
      'permissions': nodeSettings['permissions'],
    if (nodeSettings.containsKey('env'))
      'envVars': nodeSettings['env'],
    if (nodeSettings.containsKey('hooks'))
      'hooks': nodeSettings['hooks'],
    if (nodeSettings.containsKey('mcpServers'))
      'mcpServers': nodeSettings['mcpServers'],
    'importedFrom': 'neom-claw-node',
    'importedAt': DateTime.now().toIso8601String(),
  };
}

/// Export Neom Claw settings for backup.
Future<String> exportSettings() async {
  final home = Platform.environment['HOME'] ?? '';
  final paths = [
    '$home/.neomclaw/settings.json',
    '$home/.neomclaw/settings.local.json',
  ];

  final export = <String, dynamic>{
    'exportVersion': 1,
    'exportDate': DateTime.now().toIso8601String(),
    'settings': <String, dynamic>{},
  };

  for (final path in paths) {
    final file = File(path);
    if (await file.exists()) {
      final content = await file.readAsString();
      export['settings']![p.basename(path)] = jsonDecode(content);
    }
  }

  return const JsonEncoder.withIndent('  ').convert(export);
}

/// Import settings from an export.
Future<void> importSettings(String exportJson) async {
  final data = jsonDecode(exportJson) as Map<String, dynamic>;
  final settings = data['settings'] as Map<String, dynamic>?;
  if (settings == null) return;

  final home = Platform.environment['HOME'] ?? '';
  final configDir = Directory('/.neomclaw');
  await configDir.create(recursive: true);

  for (final entry in settings.entries) {
    final file = File('$home/.neomclaw/${entry.key}');
    await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(entry.value));
  }
}
