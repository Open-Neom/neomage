/// Describes a plugin's setup requirements declaratively.
///
/// Plugins declare auth, pairing, and configuration steps in
/// their manifest instead of requiring core hardcoded special cases.
class PluginSetupDescriptor {
  /// Unique plugin identifier.
  final String pluginId;

  /// Human-readable display name.
  final String displayName;

  /// Setup steps required for activation.
  final List<PluginSetupStep> steps;

  /// Provider IDs this plugin registers.
  final List<String> providerIds;

  /// CLI backend IDs this plugin registers.
  final List<String> cliBackendIds;

  /// Dependencies on other plugins (by ID).
  final List<String> dependsOn;

  /// Whether this plugin can be hot-reloaded.
  final bool hotReloadable;

  const PluginSetupDescriptor({
    required this.pluginId,
    required this.displayName,
    this.steps = const [],
    this.providerIds = const [],
    this.cliBackendIds = const [],
    this.dependsOn = const [],
    this.hotReloadable = false,
  });

  bool get requiresAuth => steps.any((s) => s.type == SetupStepType.auth);
  bool get requiresPairing => steps.any((s) => s.type == SetupStepType.pairing);
}

/// A single step in a plugin's setup flow.
class PluginSetupStep {
  final SetupStepType type;
  final String label;
  final bool required;
  final Map<String, dynamic> config;

  const PluginSetupStep({
    required this.type,
    required this.label,
    this.required = true,
    this.config = const {},
  });
}

/// Types of setup steps a plugin can declare.
enum SetupStepType {
  auth,
  apiKey,
  pairing,
  oauth,
  config,
  webhook,
  test,
}
