// Plugin system types — ported from NeomClaw src/types/plugin.ts.

/// Plugin author metadata.
class PluginAuthor {
  final String name;
  final String? email;
  final String? url;

  const PluginAuthor({required this.name, this.email, this.url});
}

/// Plugin manifest — describes a plugin's capabilities.
class PluginManifest {
  final String name;
  final String version;
  final String? description;
  final PluginAuthor? author;
  final List<String> commands;
  final List<String> skills;
  final List<String> hooks;
  final List<String> mcpServers;
  final List<String> outputStyles;

  const PluginManifest({
    required this.name,
    required this.version,
    this.description,
    this.author,
    this.commands = const [],
    this.skills = const [],
    this.hooks = const [],
    this.mcpServers = const [],
    this.outputStyles = const [],
  });
}

/// Plugin component types.
enum PluginComponent { commands, agents, skills, hooks, outputStyles }

/// Repository configuration for a plugin.
class PluginRepository {
  final String url;
  final String? branch;
  final DateTime? lastUpdated;

  const PluginRepository({required this.url, this.branch, this.lastUpdated});
}

/// A loaded plugin with resolved paths.
class LoadedPlugin {
  final PluginManifest manifest;
  final String path;
  final bool enabled;

  const LoadedPlugin({
    required this.manifest,
    required this.path,
    this.enabled = true,
  });
}

/// Plugin loading errors.
sealed class PluginError {
  final String pluginName;
  final String message;
  const PluginError({required this.pluginName, required this.message});
}

class PluginNotFoundError extends PluginError {
  const PluginNotFoundError({required super.pluginName})
    : super(message: 'Plugin not found');
}

class PluginManifestError extends PluginError {
  const PluginManifestError({
    required super.pluginName,
    required super.message,
  });
}

class PluginLoadError extends PluginError {
  const PluginLoadError({required super.pluginName, required super.message});
}

/// Result of loading plugins.
class PluginLoadResult {
  final List<LoadedPlugin> enabled;
  final List<LoadedPlugin> disabled;
  final List<PluginError> errors;

  const PluginLoadResult({
    this.enabled = const [],
    this.disabled = const [],
    this.errors = const [],
  });
}
