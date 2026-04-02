import 'package:sint/sint.dart';

import 'ui/controllers/chat_controller.dart';

/// Root binding — registers all dependencies on app start.
/// Follows Open Neom pattern: Binding + List of Bind.
class RootBinding extends Binding {
  @override
  List<Bind> dependencies() => [
        // Chat controller (permanent — lives for app lifetime)
        Bind.put(ChatController(), permanent: true),

        // Future phases will add:
        // Bind.lazyPut(() => AnalyticsController(), fenix: true),
        // Bind.lazyPut(() => GrowthBookController(), fenix: true),
        // Bind.lazyPut(() => TelemetryController(), fenix: true),
        // Bind.lazyPut(() => SessionMemoryController(), fenix: true),
        // Bind.lazyPut(() => McpClientController(), fenix: true),
        // Bind.lazyPut(() => ToolRegistryController(), fenix: true),
      ];
}
