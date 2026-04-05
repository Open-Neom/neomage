/// Translation key constants for neomage.
///
/// Usage: `NeomageTranslationConstants.appTitle.tr`
///
/// Every user-facing string in the app should reference a constant here
/// instead of being hardcoded, enabling full i18n support.
class NeomageTranslationConstants {
  NeomageTranslationConstants._();

  // ── App General ──

  static const String appTitle = 'appTitle';
  static const String appSubtitleDesktop = 'appSubtitleDesktop';
  static const String appSubtitleMobile = 'appSubtitleMobile';
  static const String welcomeSubtitle = 'welcomeSubtitle';
  static const String splashTagline2 = 'splashTagline2';
  static const String splashTagline3 = 'splashTagline3';
  static const String language = 'language';
  static const String save = 'save';
  static const String cancel = 'cancel';
  static const String delete = 'delete';
  static const String close = 'close';
  static const String retry = 'retry';
  static const String back = 'back';
  static const String skip = 'skip';
  static const String add = 'add';
  static const String exit = 'exit';
  static const String copiedToClipboard = 'copiedToClipboard';
  static const String notYetImplemented = 'notYetImplemented';

  // ── Chat Screen ──

  static const String newConversation = 'newConversation';
  static const String clearConversation = 'clearConversation';
  static const String conversationCleared = 'conversationCleared';
  static const String exportConversation = 'exportConversation';
  static const String exportNotImplemented = 'exportNotImplemented';
  static const String selectModel = 'selectModel';
  static const String modelChangedTo = 'modelChangedTo';
  static const String typeACommand = 'typeACommand';
  static const String commandPalette = 'commandPalette';
  static const String commandPaletteShortcut = 'commandPaletteShortcut';

  // ── Chat – Top Bar ──

  static const String openSidePanel = 'openSidePanel';
  static const String toggleSidePanel = 'toggleSidePanel';
  static const String settings = 'settings';
  static const String changeModel = 'changeModel';

  // ── Chat – Empty State ──

  static const String explainCodebase = 'explainCodebase';
  static const String findTodoComments = 'findTodoComments';
  static const String writeUnitTests = 'writeUnitTests';
  static const String refactorFunction = 'refactorFunction';
  static const String reviewPR = 'reviewPR';
  static const String debugError = 'debugError';
  static const String summarizeArticle = 'summarizeArticle';
  static const String translateToEnglish = 'translateToEnglish';
  static const String draftQuickReply = 'draftQuickReply';
  static const String brainstormIdeas = 'brainstormIdeas';
  static const String explainConcept = 'explainConcept';
  static const String writeShortNote = 'writeShortNote';

  // ── Chat – Side Panel ──

  static const String agents = 'agents';
  static const String tasks = 'tasks';
  static const String mcp = 'mcp';
  static const String noActiveAgents = 'noActiveAgents';
  static const String agentsWillAppear = 'agentsWillAppear';
  static const String noActiveTasks = 'noActiveTasks';
  static const String tasksWillAppear = 'tasksWillAppear';
  static const String noTasks = 'noTasks';

  // ── Chat – MCP Panel ──

  static const String addMcpServer = 'addMcpServer';
  static const String serverName = 'serverName';
  static const String serverNameHint = 'serverNameHint';
  static const String serverUrl = 'serverUrl';
  static const String serverUrlHint = 'serverUrlHint';
  static const String command = 'command';
  static const String commandHint = 'commandHint';
  static const String stdio = 'stdio';
  static const String sse = 'sse';
  static const String remove = 'remove';
  static const String reconnect = 'reconnect';
  static const String searchTools = 'searchTools';
  static const String server = 'server';
  static const String decline = 'decline';
  static const String submit = 'submit';

  // ── Chat – Streaming ──

  static const String thinking = 'thinking';

  // ── API Key Dialog ──

  static const String apiKey = 'apiKey';
  static const String apiKeyHint = 'apiKeyHint';
  static const String apiKeyRequired = 'apiKeyRequired';
  static const String saveAndContinue = 'saveAndContinue';
  static const String pasteFromClipboard = 'pasteFromClipboard';

  // ── Model Selector ──

  static const String desktopOnly = 'desktopOnly';
  static const String ollamaDesktopNote = 'ollamaDesktopNote';

  // ── Settings Screen ──

  static const String settingsSaved = 'settingsSaved';
  static const String apiProvider = 'apiProvider';
  static const String version = 'version';
  static const String provider = 'provider';
  static const String model = 'model';
  static const String defaultModel = 'defaultModel';
  static const String baseUrl = 'baseUrl';
  static const String baseUrlHint = 'baseUrlHint';
  static const String searchSettings = 'searchSettings';
  static const String diagnostics = 'diagnostics';
  static const String refreshUsageData = 'refreshUsageData';
  static const String noUsageData = 'noUsageData';

  // ── Settings – Toggles ──

  static const String autoCompact = 'autoCompact';
  static const String showTips = 'showTips';
  static const String reduceMotion = 'reduceMotion';
  static const String thinkingMode = 'thinkingMode';
  static const String verboseOutput = 'verboseOutput';
  static const String fileCheckpointing = 'fileCheckpointing';
  static const String notifications = 'notifications';
  static const String toggleTheme = 'toggleTheme';
  static const String themeToggleNotImplemented = 'themeToggleNotImplemented';

  // ── Settings – Status Properties ──

  static const String loginMethod = 'loginMethod';
  static const String authToken = 'authToken';
  static const String organization = 'organization';
  static const String email = 'email';
  static const String apiProviderLabel = 'apiProviderLabel';
  static const String gcpProject = 'gcpProject';
  static const String mcpServers = 'mcpServers';
  static const String settingSources = 'settingSources';
  static const String bashSandbox = 'bashSandbox';
  static const String enabled = 'enabled';
  static const String disabled = 'disabled';

  // ── Ollama Setup ──

  static const String localModelsOllama = 'localModelsOllama';
  static const String localModelsDesktopOnly = 'localModelsDesktopOnly';
  static const String ollamaWebNote = 'ollamaWebNote';
  static const String refresh = 'refresh';
  static const String installedModels = 'installedModels';
  static const String noModelsInstalled = 'noModelsInstalled';
  static const String downloadModelBelow = 'downloadModelBelow';
  static const String downloadModels = 'downloadModels';
  static const String recommendedModels = 'recommendedModels';
  static const String installed = 'installed';
  static const String download = 'download';
  static const String pull = 'pull';
  static const String testModel = 'testModel';
  static const String testing = 'testing';
  static const String useThisModel = 'useThisModel';
  static const String deleteModel = 'deleteModel';
  static const String deleteModelConfirm = 'deleteModelConfirm';
  static const String redownloadLater = 'redownloadLater';
  static const String customModelHint = 'customModelHint';
  static const String activatedAsDefault = 'activatedAsDefault';

  // ── Choose Mode ──

  static const String chooseModeTitle = 'chooseModeTitle';
  static const String chooseModeSubtitle = 'chooseModeSubtitle';
  static const String cloudMode = 'cloudMode';
  static const String cloudModeDesc = 'cloudModeDesc';
  static const String localMode = 'localMode';
  static const String localModeDesc = 'localModeDesc';
  static const String localModeDesktopOnly = 'localModeDesktopOnly';

  // ── API Configuration ──

  static const String apiConfigTitle = 'apiConfigTitle';
  static const String apiConfigSubtitle = 'apiConfigSubtitle';
  static const String apiConfigExplanation = 'apiConfigExplanation';

  // ── Ollama Setup ──

  static const String ollamaSetupTitle = 'ollamaSetupTitle';
  static const String ollamaSetupSubtitle = 'ollamaSetupSubtitle';
  static const String ollamaNotDetected = 'ollamaNotDetected';
  static const String ollamaNotDetectedDesc = 'ollamaNotDetectedDesc';
  static const String ollamaInstallHint = 'ollamaInstallHint';
  static const String ollamaRunning = 'ollamaRunning';
  static const String ollamaCheckStatus = 'ollamaCheckStatus';
  static const String ollamaInstalledModels = 'ollamaInstalledModels';
  static const String ollamaNoModels = 'ollamaNoModels';
  static const String ollamaRecommended = 'ollamaRecommended';
  static const String ollamaSelectModel = 'ollamaSelectModel';
  static const String ollamaPulling = 'ollamaPulling';

  // ── Onboarding ──

  static const String getStarted = 'getStarted';
  static const String codeEditing = 'codeEditing';
  static const String codebaseSearch = 'codebaseSearch';
  static const String shellCommands = 'shellCommands';
  static const String mcpTools = 'mcpTools';
  static const String gitIntegration = 'gitIntegration';
  static const String gitIntegrationDesc = 'gitIntegrationDesc';
  static const String createNeomageMd = 'createNeomageMd';
  static const String createNeomageMdDesc = 'createNeomageMdDesc';
  static const String browse = 'browse';
  static const String backToSettings = 'backToSettings';

  // ── Permissions ──

  static const String permDefault = 'permDefault';
  static const String permAcceptEdits = 'permAcceptEdits';
  static const String permAcceptEditsDesc = 'permAcceptEditsDesc';
  static const String permPlanMode = 'permPlanMode';
  static const String permPlanModeDesc = 'permPlanModeDesc';
  static const String permFullAuto = 'permFullAuto';
  static const String permFullAutoDesc = 'permFullAutoDesc';
  static const String addRule = 'addRule';
  static const String editRule = 'editRule';
  static const String rulePatternHint = 'rulePatternHint';
  static const String behavior = 'behavior';
  static const String allow = 'allow';
  static const String deny = 'deny';
  static const String ask = 'ask';
  static const String scope = 'scope';
  static const String tool = 'tool';
  static const String file = 'file';
  static const String cmd = 'cmd';
  static const String ruleReasonHint = 'ruleReasonHint';
  static const String toolInput = 'toolInput';
  static const String rememberSession = 'rememberSession';
  static const String rememberProject = 'rememberProject';
  static const String trustAndContinue = 'trustAndContinue';

  // ── Input Bar ──

  static const String attachFile = 'attachFile';
  static const String pickAnyFile = 'pickAnyFile';
  static const String image = 'image';
  static const String fromGallery = 'fromGallery';
  static const String camera = 'camera';
  static const String takePhoto = 'takePhoto';
  static const String pdf = 'pdf';
  static const String pickPdf = 'pickPdf';
  static const String attachTooltip = 'attachTooltip';

  // ── Plan Mode ──

  static const String exitPlanMode = 'exitPlanMode';
  static const String execute = 'execute';

  // ── Feedback Survey ──

  static const String bad = 'bad';
  static const String fine = 'fine';
  static const String good = 'good';
  static const String dismiss = 'dismiss';
  static const String share = 'share';
  static const String dontAskAgain = 'dontAskAgain';

  // ── Background Tasks ──

  static const String done = 'done';
  static const String error = 'error';
  static const String stopped = 'stopped';
  static const String idle = 'idle';
  static const String awaitingApproval = 'awaitingApproval';
  static const String shutdownRequested = 'shutdownRequested';
  static const String stop = 'stop';
  static const String status = 'status';
  static const String description = 'description';
  static const String title = 'title';
  static const String agent = 'agent';
  static const String activity = 'activity';
  static const String started = 'started';
  static const String duration = 'duration';
  static const String foreground = 'foreground';
  static const String taskNotFound = 'taskNotFound';

  // ── Memory Panel ──

  static const String openAutoMemory = 'openAutoMemory';
  static const String openAgentMemory = 'openAgentMemory';
  static const String autoMemory = 'autoMemory';
  static const String autoDream = 'autoDream';

  // ── Terminal View ──

  static const String copyAll = 'copyAll';
  static const String scrollToBottom = 'scrollToBottom';
  static const String searchOutput = 'searchOutput';
  static const String logsCopied = 'logsCopied';

  // ── Providers ──

  static const String gemini = 'gemini';
  static const String qwen = 'qwen';
  static const String openai = 'openai';
  static const String deepseek = 'deepseek';
  static const String anthropic = 'anthropic';
  static const String ollama = 'ollama';

  // ── Onboarding – Agents/Tasks ──

  static const String showAgents = 'showAgents';
  static const String showTasks = 'showTasks';
  static const String showMcpServers = 'showMcpServers';
}
