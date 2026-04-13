import '../../domain/models/plugin_activation_plan.dart';
import '../../domain/models/plugin_setup_descriptor.dart';
import '../../domain/services/plugin_activation_service.dart';

/// Default plugin activation service with topological dependency resolution.
class PluginActivationServiceImpl implements PluginActivationService {
  @override
  PluginActivationPlan resolve(List<PluginSetupDescriptor> descriptors) {
    final byId = {for (final d in descriptors) d.pluginId: d};
    final errors = <PluginActivationError>[];
    final ordered = <PluginSetupDescriptor>[];
    final visited = <String>{};
    final visiting = <String>{};

    void visit(String id) {
      if (visited.contains(id)) return;
      if (visiting.contains(id)) {
        errors.add(PluginActivationError(
          pluginId: id,
          type: ActivationErrorType.circularDependency,
          message: 'Circular dependency detected for plugin: $id',
        ));
        return;
      }

      final descriptor = byId[id];
      if (descriptor == null) return;

      visiting.add(id);

      for (final dep in descriptor.dependsOn) {
        if (!byId.containsKey(dep)) {
          errors.add(PluginActivationError(
            pluginId: id,
            type: ActivationErrorType.missingDependency,
            message: 'Missing dependency: $dep required by $id',
          ));
          continue;
        }
        visit(dep);
      }

      visiting.remove(id);
      visited.add(id);
      ordered.add(descriptor);
    }

    for (final d in descriptors) {
      visit(d.pluginId);
    }

    int totalSteps = 0;
    for (final d in ordered) {
      totalSteps += d.steps.length;
    }

    return PluginActivationPlan(
      orderedPlugins: ordered,
      errors: errors,
      totalSteps: totalSteps,
    );
  }

  @override
  List<String> listSetupProviderIds(List<PluginSetupDescriptor> descriptors) {
    return descriptors.expand((d) => d.providerIds).toSet().toList();
  }

  @override
  List<String> listSetupCliBackendIds(List<PluginSetupDescriptor> descriptors) {
    return descriptors.expand((d) => d.cliBackendIds).toSet().toList();
  }
}
