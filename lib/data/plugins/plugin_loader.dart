// Plugin loader — port of neomage/src/plugins.
// Discovers, loads, and manages plugins.

import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import '../../domain/models/plugin.dart';
import '../mcp/mcp_types.dart';
import '../skills/skill.dart';

const int _maxPluginJsonBytes = 1024 * 1024;
final RegExp _controlChars = RegExp(r'[\x00-\x1F\x7F]');

bool _isSafePluginMcpCommand(String rawCommand) {
  final cmd = rawCommand.trim();
  if (cmd.isEmpty || cmd.length > 512) return false;
  if (_controlChars.hasMatch(cmd)) return false;
  if (cmd.startsWith('-')) return false;
  final segments = cmd.split(RegExp(r'[/\\]'));
  if (segments.contains('..')) return false;
  return true;
}

/// Load plugins from a directory.
Future<List<LoadedPlugin>> loadPluginsFromDir(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists() || await FileSystemEntity.isLink(dir.path)) {
    return const [];
  }

  final plugins = <LoadedPlugin>[];

  await for (final entity in dir.list(followLinks: false)) {
    if (entity is! Directory) continue;
    if (await FileSystemEntity.isLink(entity.path)) continue;

    try {
      final plugin = await _loadPlugin(entity.path);
      if (plugin != null) plugins.add(plugin);
    } catch (_) {
      // Skip invalid plugins
    }
  }

  return plugins;
}

/// Load all plugins from standard locations.
Future<List<LoadedPlugin>> loadAllPlugins({String? projectRoot}) async {
  final plugins = <LoadedPlugin>[];
  final homeDir =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/tmp';

  // 1. User plugins: ~/.neomage/plugins/
  plugins.addAll(await loadPluginsFromDir('$homeDir/.neomage/plugins'));

  // 2. Project plugins: .neomage/plugins/
  if (projectRoot != null) {
    plugins.addAll(await loadPluginsFromDir('$projectRoot/.neomage/plugins'));
  }

  return plugins;
}

/// Load skills from all enabled plugins.
Future<List<SkillDefinition>> loadPluginSkills(
  List<LoadedPlugin> plugins,
) async {
  final skills = <SkillDefinition>[];

  for (final plugin in plugins) {
    final skillsDir = '${plugin.path}/skills';
    final dir = Directory(skillsDir);
    if (!await dir.exists()) continue;

    final pluginSkills = await loadSkillsFromDir(
      skillsDir,
      source: SkillSource.plugin,
    );
    skills.addAll(pluginSkills);
  }

  return skills;
}

/// Load MCP server configs from all enabled plugins.
Future<List<McpServerConfig>> loadPluginMcpConfigs(
  List<LoadedPlugin> plugins,
) async {
  final configs = <McpServerConfig>[];

  for (final plugin in plugins) {
    final mcpFile = File('${plugin.path}/mcp.json');
    if (!await mcpFile.exists() || await FileSystemEntity.isLink(mcpFile.path)) {
      continue;
    }

    try {
      if (await mcpFile.length() > _maxPluginJsonBytes) continue;
      final json = jsonDecode(await mcpFile.readAsString());
      if (json is Map<String, dynamic>) {
        for (final entry in json.entries) {
          final value = entry.value;
          if (value is! Map<String, dynamic>) continue;
          final rawCommand = value['command'];
          if (rawCommand is String && _isSafePluginMcpCommand(rawCommand)) {
            configs.add(
              McpStdioConfig(
                name: entry.key,
                command: rawCommand.trim(),
                args:
                    (value['args'] as List?)
                        ?.where((a) => !_controlChars.hasMatch(a.toString()))
                        .map((a) => a.toString())
                        .toList() ??
                    [],
              ),
            );
          }
        }
      }
    } catch (_) {}
  }

  return configs;
}

// ── Private ──

Future<LoadedPlugin?> _loadPlugin(String pluginPath) async {
  if (await FileSystemEntity.isLink(pluginPath)) return null;
  final manifestFile = File('$pluginPath/plugin.json');

  PluginManifest? manifest;
  if (await manifestFile.exists()) {
    if (await FileSystemEntity.isLink(manifestFile.path)) return null;
    try {
      if (await manifestFile.length() > _maxPluginJsonBytes) return null;
      final json = jsonDecode(await manifestFile.readAsString());
      manifest = _parseManifest(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  final dirName = pluginPath.split('/').last;

  return LoadedPlugin(
    manifest:
        manifest ??
        PluginManifest(name: dirName, version: '0.0.0', description: ''),
    path: pluginPath,
  );
}

PluginManifest _parseManifest(Map<String, dynamic> json) {
  final authorRaw = json['author'];
  PluginAuthor? author;
  if (authorRaw is String) {
    author = PluginAuthor(name: authorRaw);
  } else if (authorRaw is Map<String, dynamic>) {
    author = PluginAuthor(
      name: authorRaw['name'] as String? ?? 'unknown',
      email: authorRaw['email'] as String?,
      url: authorRaw['url'] as String?,
    );
  }

  return PluginManifest(
    name: json['name'] as String? ?? 'unknown',
    version: json['version'] as String? ?? '0.0.0',
    description: json['description'] as String? ?? '',
    author: author,
  );
}
