/// Neomage — Multi-provider AI agent engine for Flutter.
/// API clients, tool system, skills, commands, and MCP support.
/// Part of the Open Neom ecosystem.
///
/// See the `example/` directory for a full multi-provider AI agent app
/// built with this package.
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
export 'domain/models/entrypoints_full.dart';
export 'domain/models/hook_schemas.dart';
export 'domain/models/permissions.dart';
export 'domain/models/plugin.dart';
export 'domain/models/tool_definition.dart';
export 'domain/models/text_input_types.dart'
    hide VimMode, PromptInputMode, QueuePriority, QueuedCommand, isValidImagePaste;

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
export 'data/tools/extended_tools.dart'
    hide
        getToolSchema,
        NotebookEditInput,
        NotebookEditOutput,
        NotebookEditTool,
        ExitPlanModeTool,
        PowerShellInput,
        PowerShellOutput,
        PowerShellTool,
        ConfigToolInput,
        ConfigToolOutput,
        ConfigTool,
        LspToolInput,
        LspToolOutput,
        LspTool,
        SkillTool,
        McpTool;
export 'data/tools/tool_schemas.dart';
export 'data/tools/notebook_edit_tool.dart';
export 'data/tools/plan_mode_tool.dart';
export 'data/tools/powershell_tool.dart';
export 'data/tools/mcp_tool.dart';
export 'data/tools/config_tool.dart';
export 'data/tools/lsp_tool.dart';
export 'data/tools/bash_security.dart';
export 'data/tools/task_update_tool.dart' hide TaskStatus;
export 'data/tools/skill_tool.dart'
    hide
        PluginManifest,
        SkillCommand,
        parseFrontmatter,
        parsePluginIdentifier,
        PermissionRule,
        SkillRegistry;

// Data — Compact + Session + Memory
export 'data/compact/compaction_service.dart'
    show
        CompactionService,
        CompactionStrategy,
        CompactionException,
        OnCompactProgress;
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
export 'data/commands/builtin/ultraplan_command.dart' hide RemoteSession;
export 'data/commands/builtin/bridge_command.dart'
    hide remoteControlDisconnectedMsg, BridgeConnectionState;
export 'data/commands/builtin/insights_command.dart';
export 'data/commands/builtin/thinkback_command.dart';
export 'data/commands/builtin/terminal_setup_command.dart';
export 'data/commands/builtin/extended_commands.dart'
    hide TerminalSetupCommand, PromptCommand, VimCommand;
export 'data/commands/builtin/branch_command.dart'
    hide SerializedMessage, generateUuid;
export 'data/commands/builtin/security_review_command.dart';
export 'data/commands/builtin/xaa_idp_command.dart';
export 'data/commands/builtin/init_verifiers_command.dart';
export 'data/commands/builtin/mcp_add_command.dart'
    hide McpServerConfig, McpTransport, McpConfigScope, parseEnvVars;

// Data — Bridge
export 'data/bridge/ide_bridge.dart';
export 'data/bridge/bridge_protocol.dart';
export 'data/bridge/vscode_bridge.dart';
export 'data/bridge/jetbrains_bridge.dart';

// Data — MCP
export 'data/mcp/mcp_types.dart';
export 'data/mcp/mcp_client.dart';
export 'data/mcp/mcp_config.dart';
export 'data/mcp/mcp_transport.dart' hide McpCapabilities, McpPromptArgument;

// Data — Skills
export 'data/skills/skill.dart';

// Data — Plugins
export 'data/plugins/plugin_loader.dart';

// Data — Remote
export 'data/remote/remote_session_manager.dart'
    hide RemoteSessionManager;
export 'data/remote/sessions_websocket.dart';
export 'data/remote/remote_permission_bridge.dart';
export 'data/remote/sdk_message_adapter.dart';

// Data — Voice
export 'data/voice/voice_service.dart' hide VoiceState, VoiceService;

// Data — Server + Proxy
export 'data/server/direct_server.dart';
export 'data/proxy/upstream_proxy.dart';

// Data — Hooks
export 'data/hooks/hook_manager.dart'
    hide HookEvent, PromptHook, HttpHook, HookMatcher, HookResult;
export 'data/hooks/hook_types.dart' hide HookResult, HookMatcher;
export 'data/hooks/hook_executor.dart';
export 'data/hooks/permission_hooks.dart'
    hide RiskLevel, PermissionDecision, PermissionRule;
export 'data/hooks/lifecycle_hooks.dart';

// Data — Platform
export 'data/platform/platform_bridge.dart';
export 'data/platform/remote_session.dart' hide ErrorEvent, ToolExecutionEvent;
export 'data/platform/notification_service.dart';
export 'data/platform/file_watcher.dart';
export 'data/platform/cli_adapter.dart';

// Data — Engine (extended)
export 'data/engine/system_prompt.dart';
export 'data/engine/conversation_engine.dart'
    hide PermissionDecision, StreamingText;

// Data — Analytics + Services
export 'data/analytics/analytics_service.dart';
export 'data/analytics/feature_flags.dart';
export 'data/services/tips_service.dart';
export 'data/services/prompt_suggestion_service.dart';
export 'data/services/rate_limit_service.dart';
export 'data/services/coordinator_service.dart';
export 'data/services/lsp_service.dart'
    hide DiagnosticSeverity, LspServerManager;
export 'data/services/task_service.dart' hide TaskStatus;
export 'data/services/conversation_service.dart';
export 'data/services/history_service.dart';
export 'data/services/autocomplete_service.dart';
export 'data/services/voice_service.dart';
export 'data/services/ollama_service.dart';
export 'data/services/team_memory_service.dart' hide MemoryFile;
export 'data/services/coordinator_service_full.dart'
    hide TaskStatus, TaskPriority, CoordinatorTask, TaskStarted, TaskCompleted;
export 'data/services/diff_service.dart';
export 'data/services/search_service.dart' hide SearchResult;
export 'data/services/clipboard_service.dart';
export 'data/services/git_service.dart';
export 'data/services/project_service.dart' hide ProjectInfo;
export 'data/services/notification_service_full.dart'
    hide NotificationPriority, NotificationAction;
export 'data/services/config_service.dart';
export 'data/services/remote_settings_service.dart';
export 'data/services/memory_extraction_service.dart';
export 'data/services/tool_execution_service.dart'
    hide
        ToolUseBlock,
        ToolResultBlock,
        PermissionBehavior,
        PermissionResult,
        PermissionRule,
        PermissionDecisionReason,
        ToolDefinition,
        cancelMessage,
        ToolUseContext,
        rejectMessage;
export 'data/services/compact_service.dart'
    hide
        MessageRole,
        ContentBlock,
        CompactionResult,
        estimateMessageTokens,
        maxOutputTokensForSummary,
        autocompactBufferTokens,
        compactableTools,
        manualCompactBufferTokens;
export 'data/services/oauth_service.dart'
    hide OAuthTokens, OAuthConfig, neomageAiInferenceScope;
export 'data/services/analytics_service.dart'
    hide AnalyticsSink, sanitizeToolNameForAnalytics;
export 'data/services/plugin_service.dart' hide LoadedPlugin;
export 'data/services/settings_sync_service.dart';
export 'data/services/session_memory_service.dart'
    hide SessionMemoryConfig, SessionMemoryState, roughTokenCountEstimation;
export 'data/services/auto_dream_service.dart';

// Data — Platform (extended)
export 'data/platform/remote_bridge.dart';
export 'data/platform/native_bridge.dart';

// Data — Skills (extended)
export 'data/skills/skill_registry.dart' hide SkillSource, SkillDefinition;

// Data — Testing (moved to test/ — not exported for pub.dev)

// NOTE: UI widgets, screens, themes, keybindings, and localization
// are NOT exported from the package. They live in the example/ app.
// Import individual files from the package if you need specific logic.

// Utils — Permissions, Model, Shell, Settings
export 'utils/permissions/permission_rule.dart'
    hide
        PermissionRule,
        PermissionBehavior,
        PermissionMode,
        PermissionRuleSource;
export 'utils/model/model_catalog.dart' hide TokenUsage;
export 'utils/shell/shell_provider.dart' hide detectShell;
export 'utils/settings/settings_schema.dart' hide SandboxSettings;

// Utils — Bash, Input, Telemetry, Swarm
export 'utils/bash/bash_parser.dart'
    hide CommandCategory, classifyCommand, truncateOutput, interpretExitCode;
export 'utils/input/process_user_input.dart' hide detectLanguage;
export 'utils/telemetry/telemetry_service.dart';
export 'utils/swarm/swarm_orchestrator.dart' hide TaskStatus;

// Utils
export 'utils/config/settings.dart';
export 'utils/constants/api_limits.dart';
export 'utils/constants/betas.dart';
export 'utils/constants/error_ids.dart';
export 'utils/constants/figures.dart' hide diamondOpen;
export 'utils/constants/messages.dart';
export 'utils/constants/tool_limits.dart';
export 'utils/constants/tool_names.dart'
    hide
        fileEditToolName,
        grepToolName,
        sendMessageToolName,
        taskUpdateToolName,
        skillToolName;
export 'utils/constants/files.dart';
export 'utils/constants/oauth.dart';
export 'utils/constants/system.dart';
export 'utils/constants/xml_tags.dart';
export 'utils/constants/spinner_verbs.dart';
// NOTE: neomage_assets, neomage_translation_constants, and app_translations
// are app-specific — see example/lib/utils/constants/ and example/lib/localization/
export 'utils/constants/full_constants.dart'
    hide ErrorMessages, binaryExtensions, defaultIgnorePatterns;
export 'utils/git_utils.dart' hide GitFileStatus;
export 'utils/process_utils.dart';
export 'utils/encoding_utils.dart'
    hide truncate, estimateTokens, base64Encode, formatDuration, base64Decode;

// Utils — Auth
export 'utils/auth/feature_gates.dart' hide Plan;

// Utils — Path, Tokens, Diff, Text, Process, Crypto
export 'utils/path/path_utils.dart';
export 'utils/tokens/token_counter.dart' hide ModelPricing;
export 'utils/diff/diff_utils.dart' hide DiffStats;
export 'utils/text/text_utils.dart' hide truncate, extractCodeBlocks, stripAnsi;
export 'utils/process/process_manager.dart' hide ProcessOutput;
export 'utils/crypto/crypto_utils.dart';

// Utils — Messages, Config, Attachments, Session
export 'utils/messages/message_utils.dart'
    hide
        noContentMessage,
        MessageType,
        syntheticModel,
        PermissionMode,
        interruptMessage,
        HookEvent,
        MessageOrigin,
        ContentBlock,
        TextBlock,
        ToolUseBlock,
        ToolResultBlock,
        ImageBlock,
        Message,
        AssistantMessage,
        hasToolCallsInLastAssistantTurn,
        createUserMessage,
        NormalizedMessage;
export 'utils/config/config_manager.dart'
    hide HistoryEntry, AccountInfo, NotificationChannel;
export 'utils/attachments/attachment_manager.dart';
export 'utils/session/session_storage.dart' hide LogEntry, isTranscriptMessage;

// Utils — Error, File, Migration, Context
export 'utils/error/error_handler.dart'
    hide ApiError, DiagnosticCheck, DiagnosticStatus;
export 'utils/file/file_operations.dart'
    hide FileEdit, DiffHunk, DiffLine, DiffLineType, parseUnifiedDiff;
export 'utils/migration/migration_service.dart';
export 'utils/context/context_builder.dart';
export 'utils/markdown/markdown_utils.dart' hide extractCodeBlocks, wordWrap;

// Utils — Plugins, Hooks, Native, ComputerUse, DeepLink
export 'utils/plugins/plugin_schemas.dart'
    hide PluginAuthor, PluginManifest, PluginMarketplaceEntry, ValidationResult;
export 'utils/hooks/hook_manager.dart'
    hide
        HookEvent,
        HookCommand,
        CommandHook,
        PromptHook,
        AgentHook,
        HttpHook,
        FunctionHook,
        AggregatedHookResult,
        HookExecutionEvent;
export 'utils/computer_use/computer_use_manager.dart';
export 'utils/deep_link/deep_link_handler.dart'
    hide longPrefillThreshold, detectTerminal;
export 'utils/native_installer/native_installer.dart' hide PackageManager;

// Utils — Worktree, IDE, NeomageMD, Analyze, Image
export 'utils/worktree/worktree_manager.dart';
export 'utils/ide/ide_utils.dart' hide IdeType;
export 'utils/neomagemd/neomagemd_parser.dart'
    hide MemoryType, MemoryFileInfo;
export 'utils/analyze/analyze_context.dart'
    hide autocompactBufferTokens, MemoryFile, SkillInfo;
export 'utils/image/image_utils.dart'
    hide
        apiImageMaxBase64Size,
        imageMaxWidth,
        imageMaxHeight,
        imageTargetRawSize,
        ImageDimensions,
        formatFileSize;

// Utils — Stats, ToolResult, FileHistory, Collapse, Commit
export 'utils/stats/stats_manager.dart';
export 'utils/tool_result/tool_result_storage.dart'
    hide
        bytesPerToken,
        defaultMaxResultSizeChars,
        maxToolResultBytes,
        maxToolResultsPerMessageChars,
        ToolResultBlock,
        Message,
        TextContentBlock;
export 'utils/file_history/file_history.dart' hide DiffStats;
export 'utils/collapse/collapse_utils.dart'
    hide
        bashToolName,
        fileEditToolName,
        fileWriteToolName,
        taskNotificationTag,
        toolSearchToolName,
        statusTag,
        summaryTag;
export 'utils/commit/commit_attribution.dart'
    hide FileAttributionState, FileChange;

// Utils — Conversation, Cron, Ripgrep, FastMode, Effort
export 'utils/conversation/conversation_recovery.dart'
    hide
        FileHistorySnapshot,
        AttributionSnapshotMessage,
        ContextCollapseCommitEntry,
        PersistedWorktreeSession,
        Message,
        Attachment,
        SerializedMessage,
        LogOption,
        ContentReplacementRecord,
        SessionMode,
        createUserMessage,
        isToolUseResultMessage,
        createAssistantMessage;
export 'utils/cron/cron_manager.dart';
export 'utils/ripgrep/ripgrep_utils.dart';
export 'utils/fast_mode/fast_mode.dart';
export 'utils/effort/effort_manager.dart';

// Utils — Teammate, Cleanup, Session, Query, Doctor
export 'utils/teammate/teammate_utils.dart'
    hide
        teammateMessageTag,
        teamLeadName,
        ShutdownRequestMessage,
        PlanApprovalResponseMessage,
        TeamSummary,
        TeammateStatus;
export 'utils/cleanup/cleanup_manager.dart' hide ExitReason;
export 'utils/session/session_utils_full.dart';
export 'utils/query/query_helpers.dart';
export 'utils/doctor/doctor_diagnostic.dart'
    hide
        RipgrepStatus,
        InstallMethod,
        maxMemoryCharacterCount,
        MemoryFileInfo,
        AgentDefinitionInfo,
        McpToolInfo;

// Utils — Env, Git, Format, Theme, Proxy
export 'utils/env/env_manager.dart' hide NeomagePlatform, detectTerminal;
export 'utils/git/git_diff_utils.dart' hide GitFileStatus;
export 'utils/format/format_utils.dart'
    hide formatFileSize, formatRelativeTimeAgo, truncate, parseFrontmatter;
export 'utils/theme/theme_utils.dart' hide NeomageTheme, ThemeSetting;
export 'utils/proxy/proxy_utils.dart';

// Utils — Auth, Config, Prompt, Provider, Billing
export 'utils/auth/auth_utils.dart'
    hide
        neomageAiProfileScope,
        OAuthTokens,
        SubscriptionType,
        AccountInfo,
        isBareMode,
        isRunningOnHomespace;
export 'utils/config/config_full.dart'
    hide
        ImageDimensions,
        PastedContent,
        HistoryEntry,
        ReleaseChannel,
        InstallMethod,
        ThemeSetting,
        EditorMode,
        DiffTool,
        NotificationChannel,
        MemoryType,
        AccountInfo,
        FeedbackSurveyState,
        ProjectConfig,
        GlobalConfig,
        globalConfigKeys,
        isGlobalConfigKey,
        projectConfigKeys,
        isProjectConfigKey;
export 'utils/handle_prompt/handle_prompt_submit.dart'
    hide
        EffortValue,
        AppNotification,
        MessageOrigin,
        FrontmatterShell,
        ShellError;
export 'utils/provider/provider_profile.dart';
export 'utils/billing/billing_utils.dart'
    hide
        SubscriptionType,
        AttributionData,
        AttributionState,
        terminalOutputTags,
        TranscriptEntry;
export 'utils/release/release_utils.dart'
    hide SemVer, ReleaseChannel, OAuthAccountInfo;

// Utils — FS, ToolSearch, MessageQueue, Heatmap
export 'utils/fs/fs_operations.dart';
export 'utils/tool_search/tool_search_utils.dart'
    hide
        ToolDefinition,
        AgentDefinition,
        ToolPermissionContext,
        toolSearchToolName,
        toolTokenCountOverhead,
        interruptMessageForToolUse,
        ShellError,
        AbortError;
export 'utils/message_queue/message_queue_manager.dart'
    hide
        PromptInputMode,
        PastedContent,
        ContentBlock,
        QueuedCommand,
        Signal,
        TextContentBlock,
        ImageContentBlock;
export 'utils/heatmap/heatmap_utils.dart'
    hide DailyActivity, LogOption, RenderableMessage;

// Agent — Personality & System Prompt
export 'core/agent/neomage_system_prompt.dart';

// State
export 'state/app_state.dart'
    hide PermissionMode, ConnectionStatus, SessionState, SessionMessage;
