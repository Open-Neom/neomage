import '../models/plugin_activation_plan.dart';
import '../models/plugin_setup_descriptor.dart';

/// Service contract for plugin activation planning.
///
/// Resolves plugin dependencies and produces an ordered activation
/// plan that respects setup step requirements.
abstract class PluginActivationService {
  /// Resolve descriptors into an ordered activation plan.
  PluginActivationPlan resolve(List<PluginSetupDescriptor> descriptors);

  /// Extract provider IDs from a set of descriptors.
  List<String> listSetupProviderIds(List<PluginSetupDescriptor> descriptors);

  /// Extract CLI backend IDs from a set of descriptors.
  List<String> listSetupCliBackendIds(List<PluginSetupDescriptor> descriptors);
}
