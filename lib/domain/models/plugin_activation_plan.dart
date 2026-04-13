import 'plugin_setup_descriptor.dart';

/// Resolved activation plan for a set of plugins.
///
/// Determines the order in which plugins should be initialized
/// based on dependency resolution.
class PluginActivationPlan {
  /// Plugins in resolved activation order.
  final List<PluginSetupDescriptor> orderedPlugins;

  /// Plugins that could not be resolved (circular deps, missing deps).
  final List<PluginActivationError> errors;

  /// Total setup steps across all plugins.
  final int totalSteps;

  const PluginActivationPlan({
    required this.orderedPlugins,
    this.errors = const [],
    this.totalSteps = 0,
  });

  bool get hasErrors => errors.isNotEmpty;
  int get pluginCount => orderedPlugins.length;
}

/// Error during plugin activation planning.
class PluginActivationError {
  final String pluginId;
  final ActivationErrorType type;
  final String message;

  const PluginActivationError({
    required this.pluginId,
    required this.type,
    required this.message,
  });
}

enum ActivationErrorType {
  missingDependency,
  circularDependency,
  setupStepFailed,
  manifestInvalid,
}
