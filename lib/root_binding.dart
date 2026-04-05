import 'package:sint/sint.dart';

// -- API layer --
import 'package:neomage/data/api/api_provider.dart';
import 'package:neomage/data/api/anthropic_client.dart';

// -- Domain --

// -- Tools --
import 'package:neomage/data/tools/tool_registry.dart';

// -- Commands --
import 'package:neomage/data/commands/command_registry.dart';

// -- Session --
import 'package:neomage/data/session/session_history.dart';
import 'package:neomage/data/services/history_service.dart';

// -- Permissions / Hooks --
import 'package:neomage/data/hooks/hook_executor.dart';

// -- MCP --
import 'package:neomage/data/mcp/mcp_client.dart';

// -- Auth --
import 'package:neomage/data/auth/auth_service.dart';

// -- Services --
import 'package:neomage/data/services/git_service.dart';
import 'package:neomage/data/services/project_service.dart';
import 'package:neomage/data/services/search_service.dart';
import 'package:neomage/data/services/diff_service.dart';
import 'package:neomage/data/services/clipboard_service.dart';
import 'package:neomage/data/services/voice_service.dart';
import 'package:neomage/utils/telemetry/telemetry_service.dart';
import 'package:neomage/data/services/notification_service_full.dart';
import 'package:neomage/data/services/autocomplete_service.dart';
import 'package:neomage/data/services/config_service.dart';
import 'package:neomage/data/services/remote_settings_service.dart';
import 'package:neomage/data/services/memory_extraction_service.dart';
import 'package:neomage/data/services/task_service.dart';
import 'package:neomage/data/bootstrap/bootstrap_service.dart';
import 'package:neomage/data/services/rate_limit_service.dart';

// -- State --
import 'ui/theme/neomage_theme_full.dart';
import 'package:neomage/state/app_state.dart';
import 'package:neomage/utils/auth/feature_gates.dart';

// -- UI --
import 'ui/controllers/chat_controller.dart';
import 'ui/buddy/buddy_widget.dart';

// -- Platform --
import 'package:neomage/data/platform/native_bridge.dart';
import 'package:neomage/utils/constants/system.dart';

/// Root binding — registers all dependencies on app start.
/// Follows Open Neom pattern: Binding + List of Bind.
///
/// Services are grouped by architectural layer. Every service is lazily
/// instantiated (except [ChatController] which is permanent) so that
/// startup cost stays minimal. The `fenix: true` flag means Sint will
/// re-create the instance if it was previously disposed.
class RootBinding extends Binding {
  @override
  List<Bind> dependencies() => [
    // ---------------------------------------------------------------
    // Auth — must be available before API layer and UI controllers
    // ---------------------------------------------------------------
    Bind.put(AuthService(), permanent: true),

    // ---------------------------------------------------------------
    // API layer
    // ---------------------------------------------------------------
    Bind.lazyPut<ApiProvider>(
      () => AnthropicClient(
        ApiConfig.anthropic(apiKey: '', model: 'claude-sonnet-4-20250514'),
      ),
      fenix: true,
    ),

    // ---------------------------------------------------------------
    // Tools
    // ---------------------------------------------------------------
    Bind.lazyPut<ToolRegistry>(() => ToolRegistry(), fenix: true),

    // ---------------------------------------------------------------
    // Commands
    // ---------------------------------------------------------------
    Bind.lazyPut<CommandRegistry>(() => CommandRegistry(), fenix: true),

    // ---------------------------------------------------------------
    // Session
    // ---------------------------------------------------------------
    Bind.lazyPut<SessionHistoryManager>(
      () => SessionHistoryManager(baseDir: SystemConstants.sessionDir),
      fenix: true,
    ),
    Bind.lazyPut<HistoryService>(() => HistoryService(), fenix: true),

    // ---------------------------------------------------------------
    // Permissions / Hooks
    // ---------------------------------------------------------------
    Bind.lazyPut<HookExecutor>(() => HookExecutor(), fenix: true),

    // ---------------------------------------------------------------
    // MCP
    // ---------------------------------------------------------------
    Bind.lazyPut<McpClient>(
      () => McpClient(toolRegistry: Sint.find<ToolRegistry>()),
      fenix: true,
    ),

    // ---------------------------------------------------------------
    // Services — core
    // ---------------------------------------------------------------
    Bind.lazyPut<GitService>(() => GitService(), fenix: true),
    Bind.lazyPut<ProjectService>(() => ProjectService(), fenix: true),
    Bind.lazyPut<SearchService>(
      () => SearchService(projectRoot: '.'),
      fenix: true,
    ),
    Bind.lazyPut<DiffService>(() => DiffService(), fenix: true),
    Bind.lazyPut<ClipboardService>(() => ClipboardService(), fenix: true),
    Bind.lazyPut<VoiceService>(() => VoiceService(), fenix: true),
    Bind.lazyPut<TelemetryService>(
      () => TelemetryService(config: TelemetryConfig()),
      fenix: true,
    ),
    Bind.lazyPut<NotificationServiceFull>(
      () => NotificationServiceFull(),
      fenix: true,
    ),
    Bind.lazyPut<AutocompleteService>(() => AutocompleteService(), fenix: true),
    Bind.lazyPut<ConfigService>(() => ConfigService(), fenix: true),
    Bind.lazyPut<RemoteSettingsService>(
      () => RemoteSettingsService(
        config: RemoteSettingsConfig(
          endpoint: 'https://api.anthropic.com/settings',
          cacheDir: '.',
        ),
      ),
      fenix: true,
    ),
    Bind.lazyPut<MemoryExtractionService>(
      () => MemoryExtractionService(),
      fenix: true,
    ),
    Bind.lazyPut<TaskManager>(() => TaskManager(), fenix: true),
    Bind.lazyPut<BootstrapService>(() => BootstrapService(), fenix: true),
    Bind.lazyPut<RateLimitService>(
      () =>
          RateLimitService(baseUrl: 'https://api.anthropic.com', cacheDir: '.'),
      fenix: true,
    ),

    // ---------------------------------------------------------------
    // State management
    // ---------------------------------------------------------------
    Bind.lazyPut<ThemeManager>(() => ThemeManager.instance, fenix: true),
    Bind.lazyPut<AppStateManager>(() => AppStateManager(), fenix: true),
    Bind.lazyPut<FeatureGateService>(() => FeatureGateService(), fenix: true),

    // ---------------------------------------------------------------
    // UI controllers
    // ---------------------------------------------------------------
    Bind.put(ChatController(), permanent: true),
    Bind.lazyPut<BuddyService>(() => BuddyService(), fenix: true),

    // ---------------------------------------------------------------
    // Platform
    // ---------------------------------------------------------------
    Bind.lazyPut<NativeBridge>(() => DesktopNativeBridge(), fenix: true),
  ];
}
