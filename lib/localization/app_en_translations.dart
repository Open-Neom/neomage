import '../utils/constants/neomage_translation_constants.dart';

/// English translations for neomage.
class AppEnTranslations {
  AppEnTranslations._();

  static Map<String, String> keys = {
    // ── App General ──
    NeomageTranslationConstants.appTitle: 'Neomage',
    NeomageTranslationConstants.appSubtitleDesktop:
        'Your AI agent to create, explore, and execute',
    NeomageTranslationConstants.splashTagline2:
        'Any model. Any platform.',
    NeomageTranslationConstants.splashTagline3:
        'Intelligence that amplifies yours.',
    NeomageTranslationConstants.appSubtitleMobile:
        'Multi-model AI to create and execute',
    NeomageTranslationConstants.welcomeSubtitle:
        'Your AI ally to create, explore, and execute.\nAny model. Any platform.',
    NeomageTranslationConstants.language: 'Language',
    NeomageTranslationConstants.save: 'Save',
    NeomageTranslationConstants.cancel: 'Cancel',
    NeomageTranslationConstants.delete: 'Delete',
    NeomageTranslationConstants.close: 'Close',
    NeomageTranslationConstants.retry: 'Retry',
    NeomageTranslationConstants.back: 'Back',
    NeomageTranslationConstants.skip: 'Skip',
    NeomageTranslationConstants.add: 'Add',
    NeomageTranslationConstants.exit: 'Exit',
    NeomageTranslationConstants.copiedToClipboard: 'Copied to clipboard',
    NeomageTranslationConstants.notYetImplemented: 'Not yet implemented',

    // ── Chat Screen ──
    NeomageTranslationConstants.newConversation: 'New Conversation',
    NeomageTranslationConstants.clearConversation: 'Clear Conversation',
    NeomageTranslationConstants.conversationCleared: 'Conversation cleared',
    NeomageTranslationConstants.exportConversation: 'Export Conversation',
    NeomageTranslationConstants.exportNotImplemented:
        'Export not yet implemented',
    NeomageTranslationConstants.selectModel: 'Select Model',
    NeomageTranslationConstants.modelChangedTo: 'Model changed to',
    NeomageTranslationConstants.typeACommand: 'Type a command...',
    NeomageTranslationConstants.commandPalette: 'Command palette',
    NeomageTranslationConstants.commandPaletteShortcut:
        'Ctrl+K for command palette',

    // ── Chat – Top Bar ──
    NeomageTranslationConstants.openSidePanel: 'Open side panel',
    NeomageTranslationConstants.toggleSidePanel: 'Toggle Side Panel',
    NeomageTranslationConstants.settings: 'Settings',
    NeomageTranslationConstants.changeModel: 'Change Model',

    // ── Chat – Empty State (Desktop) ──
    NeomageTranslationConstants.explainCodebase: 'Explain this codebase',
    NeomageTranslationConstants.findTodoComments: 'Find all TODO comments',
    NeomageTranslationConstants.writeUnitTests: 'Write unit tests',
    NeomageTranslationConstants.refactorFunction: 'Refactor this function',
    NeomageTranslationConstants.reviewPR: 'Review this PR',
    NeomageTranslationConstants.debugError: 'Debug this error',

    // ── Chat – Empty State (Mobile) ──
    NeomageTranslationConstants.summarizeArticle: 'Summarize this article',
    NeomageTranslationConstants.translateToEnglish: 'Translate to English',
    NeomageTranslationConstants.draftQuickReply: 'Draft a quick reply',
    NeomageTranslationConstants.brainstormIdeas: 'Brainstorm ideas',
    NeomageTranslationConstants.explainConcept: 'Explain a concept',
    NeomageTranslationConstants.writeShortNote: 'Write a short note',

    // ── Chat – Side Panel ──
    NeomageTranslationConstants.agents: 'Agents',
    NeomageTranslationConstants.tasks: 'Tasks',
    NeomageTranslationConstants.mcp: 'MCP',
    NeomageTranslationConstants.noActiveAgents: 'No active agents',
    NeomageTranslationConstants.agentsWillAppear:
        'Agents will appear here when spawned during a conversation.',
    NeomageTranslationConstants.noActiveTasks: 'No active tasks',
    NeomageTranslationConstants.tasksWillAppear:
        'Tasks created via TodoWrite will be tracked here.',
    NeomageTranslationConstants.noTasks: 'No tasks',

    // ── Chat – MCP Panel ──
    NeomageTranslationConstants.addMcpServer: 'Add MCP Server',
    NeomageTranslationConstants.serverName: 'Server Name',
    NeomageTranslationConstants.serverNameHint: 'e.g. filesystem, github',
    NeomageTranslationConstants.serverUrl: 'Server URL',
    NeomageTranslationConstants.serverUrlHint:
        'e.g. http://localhost:3001/sse',
    NeomageTranslationConstants.command: 'Command',
    NeomageTranslationConstants.commandHint:
        'e.g. npx -y @modelcontextprotocol/server-filesystem /path',
    NeomageTranslationConstants.stdio: 'stdio',
    NeomageTranslationConstants.sse: 'SSE',
    NeomageTranslationConstants.remove: 'Remove',
    NeomageTranslationConstants.reconnect: 'Reconnect',
    NeomageTranslationConstants.searchTools: 'Search tools...',
    NeomageTranslationConstants.server: 'Server',
    NeomageTranslationConstants.decline: 'Decline',
    NeomageTranslationConstants.submit: 'Submit',

    // ── Chat – Streaming ──
    NeomageTranslationConstants.thinking: 'Thinking',

    // ── API Key Dialog ──
    NeomageTranslationConstants.apiKey: 'API Key',
    NeomageTranslationConstants.apiKeyHint: 'sk-...',
    NeomageTranslationConstants.apiKeyRequired:
        'An API key is required to use @provider models. '
            'Enter your key below to continue.',
    NeomageTranslationConstants.saveAndContinue: 'Save & Continue',
    NeomageTranslationConstants.pasteFromClipboard: 'Paste from clipboard',

    // ── Model Selector ──
    NeomageTranslationConstants.desktopOnly: 'Desktop only',
    NeomageTranslationConstants.ollamaDesktopNote:
        'Ollama runs locally \u2014 use the desktop app to manage and run models.',

    // ── Settings Screen ──
    NeomageTranslationConstants.settingsSaved: 'Settings saved',
    NeomageTranslationConstants.apiProvider: 'API Provider',
    NeomageTranslationConstants.version: 'Version',
    NeomageTranslationConstants.provider: 'Provider',
    NeomageTranslationConstants.model: 'Model',
    NeomageTranslationConstants.defaultModel: 'Default model',
    NeomageTranslationConstants.baseUrl: 'Base URL',
    NeomageTranslationConstants.baseUrlHint: 'https://your-endpoint.com/v1',
    NeomageTranslationConstants.searchSettings: 'Search settings...',
    NeomageTranslationConstants.diagnostics: 'Diagnostics',
    NeomageTranslationConstants.refreshUsageData: 'Refresh usage data',
    NeomageTranslationConstants.noUsageData: 'No usage data available',

    // ── Settings – Toggles ──
    NeomageTranslationConstants.autoCompact: 'Auto-compact',
    NeomageTranslationConstants.showTips: 'Show tips',
    NeomageTranslationConstants.reduceMotion: 'Reduce motion',
    NeomageTranslationConstants.thinkingMode: 'Thinking mode',
    NeomageTranslationConstants.verboseOutput: 'Verbose output',
    NeomageTranslationConstants.fileCheckpointing: 'File checkpointing',
    NeomageTranslationConstants.notifications: 'Notifications',
    NeomageTranslationConstants.toggleTheme: 'Toggle Theme',
    NeomageTranslationConstants.themeToggleNotImplemented:
        'Theme toggle not yet implemented',

    // ── Settings – Status Properties ──
    NeomageTranslationConstants.loginMethod: 'Login method',
    NeomageTranslationConstants.authToken: 'Auth token',
    NeomageTranslationConstants.organization: 'Organization',
    NeomageTranslationConstants.email: 'Email',
    NeomageTranslationConstants.apiProviderLabel: 'API provider',
    NeomageTranslationConstants.gcpProject: 'GCP project',
    NeomageTranslationConstants.mcpServers: 'MCP servers',
    NeomageTranslationConstants.settingSources: 'Setting sources',
    NeomageTranslationConstants.bashSandbox: 'Bash Sandbox',
    NeomageTranslationConstants.enabled: 'Enabled',
    NeomageTranslationConstants.disabled: 'Disabled',

    // ── Ollama Setup ──
    NeomageTranslationConstants.localModelsOllama: 'Local Models (Ollama)',
    NeomageTranslationConstants.localModelsDesktopOnly:
        'Local Models (Ollama) \u2014 Desktop Only',
    NeomageTranslationConstants.ollamaWebNote:
        'Ollama runs locally on your machine. Use the macOS, Windows, or Linux app to manage local models.',
    NeomageTranslationConstants.refresh: 'Refresh',
    NeomageTranslationConstants.installedModels: 'Installed Models',
    NeomageTranslationConstants.noModelsInstalled: 'No models installed yet',
    NeomageTranslationConstants.downloadModelBelow:
        'Download a model below to get started',
    NeomageTranslationConstants.downloadModels: 'Download Models',
    NeomageTranslationConstants.recommendedModels:
        'Recommended models for coding tasks',
    NeomageTranslationConstants.installed: 'Installed',
    NeomageTranslationConstants.download: 'Download',
    NeomageTranslationConstants.pull: 'Pull',
    NeomageTranslationConstants.testModel: 'Test Model',
    NeomageTranslationConstants.testing: 'Testing...',
    NeomageTranslationConstants.useThisModel: 'Use This Model',
    NeomageTranslationConstants.deleteModel: 'Delete Model',
    NeomageTranslationConstants.deleteModelConfirm:
        'Delete @model (@size)?\n\nYou can re-download it later.',
    NeomageTranslationConstants.redownloadLater:
        'You can re-download it later.',
    NeomageTranslationConstants.customModelHint:
        'Custom model name (e.g. phi3:mini)',
    NeomageTranslationConstants.activatedAsDefault:
        '@model activated as default model',

    // ── Choose Mode ──
    NeomageTranslationConstants.chooseModeTitle: 'How do you want to use AI?',
    NeomageTranslationConstants.chooseModeSubtitle:
        'Choose between cloud providers or running models locally.',
    NeomageTranslationConstants.cloudMode: 'Cloud',
    NeomageTranslationConstants.cloudModeDesc:
        'Connect to Gemini, OpenAI, Anthropic, and others. '
            'Requires an API key (free tier available).',
    NeomageTranslationConstants.localMode: 'Local',
    NeomageTranslationConstants.localModeDesc:
        'Run AI models on your own machine with Ollama. '
            'No API key needed, fully offline and private.',
    NeomageTranslationConstants.localModeDesktopOnly:
        'Local models require the desktop app',

    // ── API Configuration ──
    NeomageTranslationConstants.apiConfigTitle: 'API Configuration',
    NeomageTranslationConstants.apiConfigSubtitle:
        'Connect to your preferred AI provider.',
    NeomageTranslationConstants.apiConfigExplanation:
        'Neomage connects directly to AI providers using your own API key. '
            'You only pay for what you use \u2014 billing is on-demand based on '
            'the tokens consumed per conversation. No subscriptions, '
            'no intermediaries.',

    // ── Ollama Setup ──
    NeomageTranslationConstants.ollamaSetupTitle: 'Local Setup (Ollama)',
    NeomageTranslationConstants.ollamaSetupSubtitle:
        'Run AI models on your own machine.',
    NeomageTranslationConstants.ollamaNotDetected: 'Ollama not detected',
    NeomageTranslationConstants.ollamaNotDetectedDesc:
        'Install Ollama to run models locally. It\u2019s free and takes under a minute.',
    NeomageTranslationConstants.ollamaInstallHint:
        'Visit ollama.com to download and install, then click Retry.',
    NeomageTranslationConstants.ollamaRunning: 'Ollama is running',
    NeomageTranslationConstants.ollamaCheckStatus: 'Check status',
    NeomageTranslationConstants.ollamaInstalledModels: 'Installed models',
    NeomageTranslationConstants.ollamaNoModels:
        'No models installed yet. Download one below to get started.',
    NeomageTranslationConstants.ollamaRecommended: 'Recommended models',
    NeomageTranslationConstants.ollamaSelectModel: 'Select a model to continue',
    NeomageTranslationConstants.ollamaPulling: 'Downloading...',

    // ── Onboarding ──
    NeomageTranslationConstants.getStarted: 'Get Started',
    NeomageTranslationConstants.codeEditing: 'Create & edit files',
    NeomageTranslationConstants.codebaseSearch: 'Search & organize',
    NeomageTranslationConstants.shellCommands: 'Run commands',
    NeomageTranslationConstants.mcpTools: 'Connect tools',
    NeomageTranslationConstants.gitIntegration: 'Git Integration',
    NeomageTranslationConstants.gitIntegrationDesc:
        'Enable git-aware features like diff view and commit helpers',
    NeomageTranslationConstants.createNeomageMd: 'Create NEOMAGE.md',
    NeomageTranslationConstants.createNeomageMdDesc:
        'Initialize a memory file with project context and instructions',
    NeomageTranslationConstants.browse: 'Browse',
    NeomageTranslationConstants.backToSettings: 'Back to settings',

    // ── Permissions ──
    NeomageTranslationConstants.permDefault: 'Default',
    NeomageTranslationConstants.permAcceptEdits: 'Accept Edits',
    NeomageTranslationConstants.permAcceptEditsDesc:
        'Auto-approve file edits. Still ask for shell commands.',
    NeomageTranslationConstants.permPlanMode: 'Plan Mode',
    NeomageTranslationConstants.permPlanModeDesc:
        'Only plan, never execute. All modifications are blocked.',
    NeomageTranslationConstants.permFullAuto: 'Full Auto',
    NeomageTranslationConstants.permFullAutoDesc:
        'Auto-approve everything. Use with caution!',
    NeomageTranslationConstants.addRule: 'Add Rule',
    NeomageTranslationConstants.editRule: 'Edit Rule',
    NeomageTranslationConstants.rulePatternHint:
        'e.g., Bash(npm:*), Edit(src/**/*.dart)',
    NeomageTranslationConstants.behavior: 'Behavior',
    NeomageTranslationConstants.allow: 'Allow',
    NeomageTranslationConstants.deny: 'Deny',
    NeomageTranslationConstants.ask: 'Ask',
    NeomageTranslationConstants.scope: 'Scope',
    NeomageTranslationConstants.tool: 'Tool',
    NeomageTranslationConstants.file: 'File',
    NeomageTranslationConstants.cmd: 'Cmd',
    NeomageTranslationConstants.ruleReasonHint: 'Why this rule exists',
    NeomageTranslationConstants.toolInput: 'Tool Input:',
    NeomageTranslationConstants.rememberSession:
        'Remember for this session',
    NeomageTranslationConstants.rememberProject:
        'Remember for this project',
    NeomageTranslationConstants.trustAndContinue: 'Trust & Continue',

    // ── Input Bar ──
    NeomageTranslationConstants.attachFile: 'File',
    NeomageTranslationConstants.pickAnyFile: 'Pick any file',
    NeomageTranslationConstants.image: 'Image',
    NeomageTranslationConstants.fromGallery: 'From gallery',
    NeomageTranslationConstants.camera: 'Camera',
    NeomageTranslationConstants.takePhoto: 'Take a photo',
    NeomageTranslationConstants.pdf: 'PDF',
    NeomageTranslationConstants.pickPdf: 'Pick a PDF document',
    NeomageTranslationConstants.attachTooltip: 'Attach file, image, or PDF',

    // ── Plan Mode ──
    NeomageTranslationConstants.exitPlanMode: 'Exit Plan Mode',
    NeomageTranslationConstants.execute: 'Execute',

    // ── Feedback Survey ──
    NeomageTranslationConstants.bad: 'Bad',
    NeomageTranslationConstants.fine: 'Fine',
    NeomageTranslationConstants.good: 'Good',
    NeomageTranslationConstants.dismiss: 'Dismiss',
    NeomageTranslationConstants.share: 'Share',
    NeomageTranslationConstants.dontAskAgain: "Don't ask again",

    // ── Background Tasks ──
    NeomageTranslationConstants.done: 'done',
    NeomageTranslationConstants.error: 'error',
    NeomageTranslationConstants.stopped: 'stopped',
    NeomageTranslationConstants.idle: 'Idle',
    NeomageTranslationConstants.awaitingApproval: 'Awaiting Approval',
    NeomageTranslationConstants.shutdownRequested: 'Shutdown Requested',
    NeomageTranslationConstants.stop: 'Stop',
    NeomageTranslationConstants.status: 'Status',
    NeomageTranslationConstants.description: 'Description',
    NeomageTranslationConstants.title: 'Title',
    NeomageTranslationConstants.agent: 'Agent',
    NeomageTranslationConstants.activity: 'Activity',
    NeomageTranslationConstants.started: 'Started',
    NeomageTranslationConstants.duration: 'Duration',
    NeomageTranslationConstants.foreground: 'Foreground',
    NeomageTranslationConstants.taskNotFound: 'Task not found',

    // ── Memory Panel ──
    NeomageTranslationConstants.openAutoMemory: 'Open auto-memory folder',
    NeomageTranslationConstants.openAgentMemory: 'Open @agent agent memory',
    NeomageTranslationConstants.autoMemory: 'Auto-memory',
    NeomageTranslationConstants.autoDream: 'Auto-dream',

    // ── Terminal View ──
    NeomageTranslationConstants.copyAll: 'Copy all',
    NeomageTranslationConstants.scrollToBottom: 'Scroll to bottom',
    NeomageTranslationConstants.searchOutput: 'Search output...',
    NeomageTranslationConstants.logsCopied: 'Logs copied to clipboard',

    // ── Providers ──
    NeomageTranslationConstants.gemini: 'Gemini',
    NeomageTranslationConstants.qwen: 'Qwen',
    NeomageTranslationConstants.openai: 'OpenAI',
    NeomageTranslationConstants.deepseek: 'DeepSeek',
    NeomageTranslationConstants.anthropic: 'Anthropic',
    NeomageTranslationConstants.ollama: 'Ollama',

    // ── Side Panel Commands ──
    NeomageTranslationConstants.showAgents: 'Show Agents',
    NeomageTranslationConstants.showTasks: 'Show Tasks',
    NeomageTranslationConstants.showMcpServers: 'Show MCP Servers',
  };
}
