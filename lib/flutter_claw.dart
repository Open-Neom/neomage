/// Flutter Claw — Flutter port of Claude Code.
/// Multi-platform AI coding assistant.
/// Part of the Open Neom ecosystem.
library;

// Domain
export 'domain/models/ids.dart';
export 'domain/models/message.dart';
export 'domain/models/command.dart'
    show
        LocalCommandResult,
        CommandResultDisplay,
        ResumeSource,
        ResumeEntrypoint,
        CommandAvailability;
export 'domain/models/hooks.dart';
export 'domain/models/logs.dart';
export 'domain/models/entrypoints.dart';
export 'domain/models/hook_schemas.dart';
export 'domain/models/permissions.dart';
export 'domain/models/plugin.dart';
export 'domain/models/tool_definition.dart';

// Data — API
export 'data/api/api_provider.dart';
export 'data/api/anthropic_client.dart';
export 'data/api/openai_shim.dart';
export 'data/api/errors.dart';
export 'data/api/retry.dart';
export 'data/api/streaming.dart';
export 'data/auth/auth_service.dart';
export 'data/auth/oauth_service.dart';
export 'data/bootstrap/app_state.dart';
export 'data/bootstrap/bootstrap_service.dart';
export 'data/engine/query_engine.dart';

// Data — Tools
export 'data/tools/tool.dart';
export 'data/tools/tool_registry.dart';
export 'data/tools/bash_tool.dart';
export 'data/tools/bash_tool_full.dart';
export 'data/tools/file_read_tool.dart';
export 'data/tools/file_write_tool.dart';
export 'data/tools/file_edit_tool.dart';
export 'data/tools/grep_tool.dart';
export 'data/tools/glob_tool.dart';
export 'data/tools/agent_tool.dart';
export 'data/tools/send_message_tool.dart';
export 'data/tools/task_output_tool.dart';
export 'data/tools/todo_write_tool.dart';
export 'data/tools/tool_search_tool.dart';
export 'data/tools/web_fetch_tool.dart';
export 'data/tools/web_search_tool.dart';
export 'data/tools/extended_tools.dart';
export 'data/tools/tool_schemas.dart';

// Data — Compact + Session + Memory
export 'data/compact/compaction_service.dart';
export 'data/memdir/memory_types.dart';
export 'data/memdir/memory_scan.dart';
export 'data/memdir/memdir_paths.dart';
export 'data/memdir/memdir_service.dart';
export 'data/session/session_memory.dart';
export 'data/session/session_history.dart';
export 'data/session/session_restore.dart';

// Data — Commands
export 'data/commands/command.dart';
export 'data/commands/command_registry.dart';
export 'data/commands/builtin/clear_command.dart';
export 'data/commands/builtin/compact_command.dart';
export 'data/commands/builtin/commit_command.dart';
export 'data/commands/builtin/context_command.dart';
export 'data/commands/builtin/cost_command.dart';
export 'data/commands/builtin/diff_command.dart';
export 'data/commands/builtin/help_command.dart';
export 'data/commands/builtin/memory_command.dart';
export 'data/commands/builtin/model_command.dart';
export 'data/commands/builtin/plan_command.dart';
export 'data/commands/builtin/review_command.dart';
export 'data/commands/builtin/session_command.dart';
export 'data/commands/builtin/extended_commands.dart';

// Data — Bridge
export 'data/bridge/ide_bridge.dart';

// Data — MCP
export 'data/mcp/mcp_types.dart';
export 'data/mcp/mcp_client.dart';
export 'data/mcp/mcp_config.dart';
export 'data/mcp/mcp_transport.dart';

// Data — Skills
export 'data/skills/skill.dart';

// Data — Plugins
export 'data/plugins/plugin_loader.dart';

// Data — Server + Proxy
export 'data/server/direct_server.dart';
export 'data/proxy/upstream_proxy.dart';

// Data — Hooks
export 'data/hooks/hook_manager.dart'
    hide HookEvent, PromptHook, HttpHook, HookMatcher, HookResult;

// Data — Platform
export 'data/platform/platform_bridge.dart';
export 'data/platform/remote_session.dart' hide ErrorEvent;
export 'data/platform/notification_service.dart';
export 'data/platform/file_watcher.dart';
export 'data/platform/cli_adapter.dart';

// Data — Engine (extended)
export 'data/engine/system_prompt.dart';
export 'data/engine/conversation_engine.dart';

// Data — Analytics + Services
export 'data/analytics/analytics_service.dart';
export 'data/analytics/feature_flags.dart';
export 'data/services/tips_service.dart';
export 'data/services/prompt_suggestion_service.dart';
export 'data/services/rate_limit_service.dart';
export 'data/services/coordinator_service.dart';
export 'data/services/lsp_service.dart';
export 'data/services/task_service.dart';
export 'data/services/conversation_service.dart';
export 'data/services/history_service.dart';
export 'data/services/autocomplete_service.dart';
export 'data/services/voice_service.dart';
export 'data/services/team_memory_service.dart';
export 'data/services/coordinator_service_full.dart';
export 'data/services/diff_service.dart';
export 'data/services/search_service.dart';
export 'data/services/clipboard_service.dart';
export 'data/services/git_service.dart';
export 'data/services/project_service.dart';
export 'data/services/notification_service_full.dart';
export 'data/services/config_service.dart';
export 'data/services/remote_settings_service.dart';
export 'data/services/memory_extraction_service.dart';

// Data — Platform (extended)
export 'data/platform/remote_bridge.dart';
export 'data/platform/native_bridge.dart';

// Data — Skills (extended)
export 'data/skills/skill_registry.dart';

// Data — Testing
export 'data/testing/test_helpers.dart';

// UI — Widgets
export 'ui/controllers/chat_controller.dart';
export 'ui/widgets/permission_dialog.dart';
export 'ui/widgets/tool_output_widget.dart';
export 'ui/widgets/diff_view.dart';
export 'ui/widgets/syntax_highlight.dart';
export 'ui/widgets/message_renderer.dart';
export 'ui/widgets/prompt_input.dart';
export 'ui/widgets/agent_panel.dart';
export 'ui/widgets/design_system.dart';
export 'ui/widgets/command_palette.dart';
export 'ui/widgets/terminal_view.dart';
export 'ui/widgets/input_bar.dart';
export 'ui/widgets/message_bubble.dart';
export 'ui/widgets/streaming_text.dart';
export 'ui/widgets/permission_manager.dart';
export 'ui/widgets/status_bar.dart';
export 'ui/widgets/log_panel.dart';
export 'ui/widgets/plan_mode_view.dart';
export 'ui/widgets/markdown_preview.dart';

// UI — Screens
export 'ui/screens/chat_screen.dart';
export 'ui/screens/settings_screen.dart';
export 'ui/screens/onboarding_screen.dart';
export 'ui/screens/mcp_panel_screen.dart';
export 'ui/screens/session_browser_screen.dart';
export 'ui/screens/doctor_screen.dart';
export 'ui/screens/splash_screen.dart';

// UI — Theme
export 'ui/theme/claw_theme_full.dart';
export 'ui/theme/app_theme.dart';

// UI — Buddy
export 'ui/buddy/buddy_widget.dart';

// UI — Styles
export 'ui/styles/output_styles.dart';

// UI — Vim
export 'ui/vim/vim_mode.dart';

// UI — Keybindings
export 'ui/keybindings/keybinding_types.dart';
export 'ui/keybindings/keybinding_resolver.dart';
export 'ui/keybindings/default_bindings.dart';

// Utils — Permissions, Model, Shell, Settings
export 'utils/permissions/permission_rule.dart'
    hide PermissionRule, PermissionBehavior, PermissionMode;
export 'utils/model/model_catalog.dart' hide TokenUsage;
export 'utils/shell/shell_provider.dart';
export 'utils/settings/settings_schema.dart' hide SandboxSettings;

// Utils — Bash, Input, Telemetry, Swarm
export 'utils/bash/bash_parser.dart';
export 'utils/input/process_user_input.dart';
export 'utils/telemetry/telemetry_service.dart';
export 'utils/swarm/swarm_orchestrator.dart';

// Utils
export 'utils/config/settings.dart';
export 'utils/constants/api_limits.dart';
export 'utils/constants/betas.dart';
export 'utils/constants/error_ids.dart';
export 'utils/constants/figures.dart';
export 'utils/constants/messages.dart';
export 'utils/constants/tool_limits.dart';
export 'utils/constants/tool_names.dart';
export 'utils/constants/files.dart';
export 'utils/constants/oauth.dart';
export 'utils/constants/system.dart';
export 'utils/constants/xml_tags.dart';
export 'utils/constants/spinner_verbs.dart';
export 'utils/constants/full_constants.dart';
export 'utils/git_utils.dart';
export 'utils/process_utils.dart';
export 'utils/encoding_utils.dart';

// Utils — Auth
export 'utils/auth/feature_gates.dart';

// Utils — Error, File, Migration, Context
export 'utils/error/error_handler.dart';
export 'utils/file/file_operations.dart';
export 'utils/migration/migration_service.dart';
export 'utils/context/context_builder.dart';
export 'utils/markdown/markdown_utils.dart';

// State
export 'state/app_state.dart';

// App
export 'claw_routes.dart';
export 'root_binding.dart';
