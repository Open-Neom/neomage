import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint_sentinel/sint_sentinel.dart';
import 'package:sint/sint.dart';

import '../../neomage_routes.dart';
import 'package:neomage/data/api/anthropic_client.dart';
import 'package:neomage/data/api/api_provider.dart';
import 'package:neomage/data/api/gemini_client.dart';
import 'package:neomage/data/api/openai_shim.dart';
import 'package:neomage/data/auth/auth_service.dart';
import 'package:neomage/data/services/ollama_service.dart';
import 'package:neomage/domain/models/message.dart';
import 'package:neomage/utils/config/settings.dart';
import '../../utils/constants/neomage_translation_constants.dart';
import '../../utils/constants/neomage_assets.dart';
import '../controllers/chat_controller.dart';

// ---------------------------------------------------------------------------
// Onboarding wizard — multi-step setup.
// Steps: Welcome -> Choose Mode (Cloud/Local) -> Config -> Permission Mode
//        -> [Desktop: Workspace -> Features] -> Completion
// ---------------------------------------------------------------------------

/// Setup mode: Cloud (API key) or Local (Ollama).
enum _SetupMode { cloud, local }

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  /// Workspace/Features steps only on desktop platforms.
  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
       defaultTargetPlatform == TargetPlatform.windows ||
       defaultTargetPlatform == TargetPlatform.linux);

  /// Total steps varies by platform:
  /// Desktop: Welcome, ChooseMode, Config, Permission, Workspace, Features, Completion = 7
  /// Mobile/Web: Welcome, ChooseMode, Config, Permission, Completion = 5
  /// (Local mode on non-desktop is hidden — Ollama only works on desktop)
  static int get _totalSteps => _isDesktop ? 7 : 5;

  final _pageController = PageController();
  final _authService = AuthService();

  // Current step (0-indexed).
  int _currentStep = 0;

  // ── Step 1: Choose Mode ──
  _SetupMode _setupMode = _SetupMode.cloud;

  // ── Step 2 (Cloud): API Configuration state ──
  ApiProviderType _providerType = ApiProviderType.gemini;
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _selectedModel = 'gemini-2.5-flash';
  bool _obscureApiKey = true;
  bool _testingConnection = false;
  _ConnectionTestResult? _connectionTestResult;

  // ── Step 2 (Local): Ollama state ──
  final _ollamaService = OllamaClient();
  OllamaStatus _ollamaStatus = OllamaStatus.unknown;
  List<OllamaModel> _ollamaModels = [];
  String? _selectedOllamaModel;
  bool _ollamaChecking = false;
  String? _pullingModel;
  double? _pullProgress;

  // ── Step 3: Permission mode state ──
  _PermissionModeOption _permissionMode = _PermissionModeOption.defaultMode;

  // ── Step 3: Workspace state ──
  final _workspaceDirController = TextEditingController();
  bool _enableGitIntegration = true;
  bool _createNeomageMd = true;

  // ── Step 4: Features carousel ──
  final _featuresPageController = PageController();
  int _featuresPage = 0;

  // ── Animation controllers ──
  late final AnimationController _logoAnimController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final AnimationController _titleAnimController;
  late final Animation<double> _titleSlide;
  late final Animation<double> _titleOpacity;

  // ── Finalising ──
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _workspaceDirController.text = _getDefaultWorkspacePath();

    // Logo animation
    _logoAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = CurvedAnimation(
      parent: _logoAnimController,
      curve: Curves.elasticOut,
    );
    _logoOpacity = CurvedAnimation(
      parent: _logoAnimController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
    );

    // Title animation
    _titleAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _titleSlide = Tween<double>(begin: 30, end: 0).animate(
      CurvedAnimation(parent: _titleAnimController, curve: Curves.easeOut),
    );
    _titleOpacity = CurvedAnimation(
      parent: _titleAnimController,
      curve: Curves.easeIn,
    );

    // Fire welcome animations.
    _logoAnimController.forward();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _titleAnimController.forward();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _workspaceDirController.dispose();
    _featuresPageController.dispose();
    _logoAnimController.dispose();
    _titleAnimController.dispose();
    super.dispose();
  }

  // ── Navigation helpers ──

  void _goToPage(int page) {
    setState(() => _currentStep = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _next() {
    if (_currentStep < _totalSteps - 1) {
      if (!_validateCurrentStep()) return;
      _goToPage(_currentStep + 1);
    }
  }

  void _back() {
    if (_currentStep > 0) _goToPage(_currentStep - 1);
  }

  void _skip() {
    _goToPage(_totalSteps - 1);
  }

  bool _validateCurrentStep() {
    if (_currentStep == 2) {
      if (_setupMode == _SetupMode.cloud) {
        // Cloud API config — key required for non-local providers.
        final needsKey = _providerType != ApiProviderType.ollama;
        if (needsKey && _apiKeyController.text.trim().isEmpty) {
          _showSnack('Please enter an API key');
          return false;
        }
        if (_providerType == ApiProviderType.custom &&
            _baseUrlController.text.trim().isEmpty) {
          _showSnack('Custom endpoint requires a base URL');
          return false;
        }
      } else {
        // Local — must have selected an Ollama model.
        if (_selectedOllamaModel == null || _selectedOllamaModel!.isEmpty) {
          _showSnack(NeomageTranslationConstants.ollamaSelectModel.tr);
          return false;
        }
      }
    }
    if (_isDesktop && _currentStep == 4) {
      if (_workspaceDirController.text.trim().isEmpty) {
        _showSnack('Please select a workspace directory');
        return false;
      }
    }
    return true;
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Ollama helpers ──

  Future<void> _checkOllama() async {
    setState(() => _ollamaChecking = true);
    try {
      final status = await _ollamaService.checkStatus();
      final models = status == OllamaStatus.running
          ? await _ollamaService.listModels()
          : <OllamaModel>[];
      if (mounted) {
        setState(() {
          _ollamaStatus = status;
          _ollamaModels = models;
          _ollamaChecking = false;
          // Auto-select first model if available and none selected.
          if (_selectedOllamaModel == null && models.isNotEmpty) {
            _selectedOllamaModel = models.first.name;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ollamaStatus = OllamaStatus.error;
          _ollamaChecking = false;
        });
      }
    }
  }

  Future<void> _pullOllamaModel(String model) async {
    setState(() {
      _pullingModel = model;
      _pullProgress = 0;
    });

    await for (final progress in _ollamaService.pullModel(model)) {
      if (!mounted) return;
      if (progress.isDone) {
        setState(() {
          _pullingModel = null;
          _pullProgress = null;
        });
        // Refresh model list after download.
        await _checkOllama();
        if (mounted) {
          setState(() => _selectedOllamaModel = model);
        }
        return;
      }
      if (progress.isError) {
        setState(() {
          _pullingModel = null;
          _pullProgress = null;
        });
        _showSnack('Error: ${progress.status}');
        return;
      }
      setState(() => _pullProgress = progress.progress);
    }
  }

  // ── API test connection ──

  Future<void> _testConnection() async {
    SintSentinel.logger.d('Testing connection for provider: ${_providerType.name}');
    setState(() {
      _testingConnection = true;
      _connectionTestResult = null;
    });

    try {
      final key = _apiKeyController.text.trim();
      final hasKey = key.isNotEmpty;
      final isLocal = _providerType == ApiProviderType.ollama;

      if (!hasKey && !isLocal) {
        setState(() {
          _testingConnection = false;
          _connectionTestResult = _ConnectionTestResult.failure(
            'API key is empty',
          );
        });
        return;
      }

      // Build a real ApiConfig and provider, then send a minimal request.
      final baseUrl = _providerType == ApiProviderType.custom
          ? _baseUrlController.text.trim()
          : null;

      final config = _buildApiConfig(
        type: _providerType,
        apiKey: key,
        model: _selectedModel,
        baseUrl: baseUrl,
      );

      final provider = switch (_providerType) {
        ApiProviderType.anthropic => AnthropicClient(config),
        ApiProviderType.gemini => GeminiClient(config),
        _ => OpenAiShim(config),
      };

      // Send a tiny completion to verify the key works.
      final stream = provider.createMessageStream(
        messages: [
          Message(
            role: MessageRole.user,
            content: [TextBlock('Hi')],
          ),
        ],
        systemPrompt: 'Reply with "ok".',
        maxTokens: 8,
      );

      // We need to check the first event — if it's an error, the key is invalid.
      final firstEvent = await stream.first.timeout(const Duration(seconds: 10));

      if (firstEvent is ErrorEvent) {
        final errMsg = firstEvent.message;
        SintSentinel.logger.w('Connection test got error event for ${_providerType.name}: $errMsg');
        final friendlyMsg = errMsg.contains('401') || errMsg.contains('Unauthorized') || errMsg.contains('invalid')
            ? 'Invalid API key'
            : errMsg.contains('403') || errMsg.contains('Forbidden')
                ? 'API key does not have access to this model'
                : 'API error: ${errMsg.length > 120 ? '${errMsg.substring(0, 120)}...' : errMsg}';
        setState(() {
          _testingConnection = false;
          _connectionTestResult = _ConnectionTestResult.failure(friendlyMsg);
        });
        return;
      }

      SintSentinel.logger.i('Connection test succeeded for ${_providerType.name}');
      setState(() {
        _testingConnection = false;
        _connectionTestResult = _ConnectionTestResult.success();
      });
    } catch (e) {
      SintSentinel.logger.w('Connection test failed for ${_providerType.name}', error: e);
      final msg = e.toString();
      // Make common errors user-friendly.
      final friendlyMsg = msg.contains('401') || msg.contains('Unauthorized')
          ? 'Invalid API key'
          : msg.contains('403') || msg.contains('Forbidden')
              ? 'API key does not have access to this model'
              : msg.contains('TimeoutException')
                  ? 'Connection timed out — check your network'
                  : msg.contains('SocketException')
                      ? 'Cannot reach API server — check your network'
                      : 'Connection failed: ${msg.length > 100 ? '${msg.substring(0, 100)}...' : msg}';

      setState(() {
        _testingConnection = false;
        _connectionTestResult = _ConnectionTestResult.failure(friendlyMsg);
      });
    }
  }

  ApiConfig _buildApiConfig({
    required ApiProviderType type,
    required String apiKey,
    required String model,
    String? baseUrl,
  }) => switch (type) {
    ApiProviderType.gemini => ApiConfig.gemini(
      apiKey: apiKey,
      model: model,
    ),
    ApiProviderType.qwen => ApiConfig.qwen(
      apiKey: apiKey,
      model: model,
    ),
    ApiProviderType.deepseek => ApiConfig.deepseek(
      apiKey: apiKey,
      model: model,
    ),
    ApiProviderType.anthropic => ApiConfig.anthropic(
      apiKey: apiKey,
      model: model,
    ),
    ApiProviderType.openai => ApiConfig.openai(
      apiKey: apiKey,
      model: model,
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
    ),
    ApiProviderType.ollama => ApiConfig.ollama(
      model: model,
      baseUrl: baseUrl ?? 'http://localhost:11434/v1',
    ),
    _ => ApiConfig(
      type: type,
      baseUrl: baseUrl ?? 'https://api.openai.com/v1',
      apiKey: apiKey,
      model: model,
    ),
  };

  // ── Finish onboarding ──

  Future<void> _finish() async {
    SintSentinel.logger.i('Finishing onboarding — persisting configuration...');
    setState(() => _finishing = true);

    try {
      if (_setupMode == _SetupMode.local) {
        // Local (Ollama) — configure as Ollama provider.
        await _authService.saveProviderConfig(
          type: ApiProviderType.ollama,
          model: _selectedOllamaModel ?? 'llama3.1',
          baseUrl: _ollamaService.openAiBaseUrl,
        );
      } else {
        // Cloud — persist API key and provider config.
        final key = _apiKeyController.text.trim();

        if (key.isNotEmpty) {
          await _authService.setApiKeyForProvider(_providerType, key);
        }

        final model = _selectedModel;
        final baseUrl = _providerType == ApiProviderType.custom
            ? _baseUrlController.text.trim()
            : null;

        await _authService.saveProviderConfig(
          type: _providerType,
          model: model,
          baseUrl: baseUrl,
        );
      }

      // Mark onboarding as complete so splash screen won't show it again.
      await _authService.setOnboardingComplete();

      // Persist workspace prefs via SharedPreferences (AppSettings).
      final settings = await AppSettings.load();
      // Permission mode is stored as a string for simplicity.
      // Workspace dir, git toggle, NEOMAGE.md are handled by the engine.

      if (mounted) {
        SintSentinel.logger.d('Initializing ChatController...');
        final chat = Sint.find<ChatController>();
        final ok = await chat.initialize();
        if (ok && mounted) {
          SintSentinel.logger.i('Onboarding complete — navigating to chat');
          Sint.offAllNamed(NeomageRouteConstants.chat);
        } else if (mounted) {
          SintSentinel.logger.w('ChatController initialization failed');
          _showSnack('Initialization failed. Check your API key.');
          setState(() => _finishing = false);
        }
      }
    } catch (e) {
      SintSentinel.logger.e('Onboarding finish error', error: e);
      if (mounted) {
        _showSnack('Error: $e');
        setState(() => _finishing = false);
      }
    }
  }

  // ── Model lists per provider ──

  List<String> _modelsForProvider(ApiProviderType type) => switch (type) {
    ApiProviderType.gemini => [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-1.5-pro',
    ],
    ApiProviderType.qwen => [
      'qwen-plus',
      'qwen-max',
      'qwen-turbo',
      'qwen-long',
    ],
    ApiProviderType.openai => [
      'gpt-4o',
      'gpt-4o-mini',
      'gpt-4-turbo',
      'o3-mini',
    ],
    ApiProviderType.deepseek => [
      'deepseek-chat',
      'deepseek-coder',
      'deepseek-reasoner',
    ],
    ApiProviderType.anthropic => [
      'claude-sonnet-4-20250514',
      'claude-opus-4-20250514',
      'claude-haiku-3-5-20241022',
    ],
    ApiProviderType.ollama => [
      'llama3.1',
      'codellama',
      'mistral',
      'deepseek-coder',
    ],
    ApiProviderType.bedrock => [
      'anthropic.claude-sonnet-4-20250514-v1:0',
      'anthropic.claude-haiku-3-5-20241022-v1:0',
    ],
    ApiProviderType.vertex => [
      'claude-sonnet-4@20250514',
      'claude-haiku-3-5@20241022',
    ],
    ApiProviderType.custom => ['gpt-4o', 'custom-model'],
  };

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Step indicator
            _StepIndicator(
              totalSteps: _totalSteps,
              currentStep: _currentStep,
              color: cs.primary,
            ),

            // Pages
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _currentStep = i),
                children: [
                  _buildWelcomePage(theme, cs),
                  // Step 1: Choose Mode (Cloud vs Local)
                  _ChooseModeStep(
                    mode: _setupMode,
                    onModeChanged: (m) => setState(() => _setupMode = m),
                    isDesktop: _isDesktop,
                  ),
                  // Step 2: Config (Cloud API or Ollama depending on mode)
                  // Uses IndexedStack to keep both widgets alive and avoid
                  // the render-tree crash caused by swapping children in a
                  // PageView via if/else.
                  IndexedStack(
                    index: _setupMode == _SetupMode.cloud ? 0 : 1,
                    children: [
                      _ApiConfigStep(
                        providerType: _providerType,
                        onProviderChanged: (t) {
                          setState(() {
                            _providerType = t;
                            _selectedModel = _modelsForProvider(t).first;
                            _connectionTestResult = null;
                          });
                        },
                        apiKeyController: _apiKeyController,
                        obscureApiKey: _obscureApiKey,
                        onToggleObscure: () =>
                            setState(() => _obscureApiKey = !_obscureApiKey),
                        selectedModel: _selectedModel,
                        models: _modelsForProvider(_providerType),
                        onModelChanged: (m) =>
                            setState(() => _selectedModel = m),
                        baseUrlController: _baseUrlController,
                        showBaseUrl:
                            _providerType == ApiProviderType.custom ||
                            _providerType == ApiProviderType.ollama,
                        testingConnection: _testingConnection,
                        testResult: _connectionTestResult,
                        onTestConnection: _testConnection,
                      ),
                      _OllamaSetupStep(
                        ollamaService: _ollamaService,
                        status: _ollamaStatus,
                        models: _ollamaModels,
                        selectedModel: _selectedOllamaModel,
                        checking: _ollamaChecking,
                        pullingModel: _pullingModel,
                        pullProgress: _pullProgress,
                        onCheckStatus: _checkOllama,
                        onSelectModel: (m) =>
                            setState(() => _selectedOllamaModel = m),
                        onPullModel: _pullOllamaModel,
                      ),
                    ],
                  ),
                  _PermissionStep(
                    selected: _permissionMode,
                    onChanged: (m) => setState(() => _permissionMode = m),
                  ),
                  // Workspace step only on desktop (macOS, Windows, Linux).
                  if (_isDesktop)
                    _WorkspaceStep(
                      dirController: _workspaceDirController,
                      gitEnabled: _enableGitIntegration,
                      onGitChanged: (v) =>
                          setState(() => _enableGitIntegration = v),
                      createNeomageMd: _createNeomageMd,
                      onNeomageMdChanged: (v) =>
                          setState(() => _createNeomageMd = v),
                    ),
                  // Features step only on desktop (macOS, Windows, Linux).
                  if (_isDesktop)
                    _FeaturesStep(
                      pageController: _featuresPageController,
                      currentPage: _featuresPage,
                      onPageChanged: (p) => setState(() => _featuresPage = p),
                    ),
                  _CompletionStep(
                    finishing: _finishing,
                    onStart: _finish,
                    onBack: _back,
                  ),
                ],
              ),
            ),

            // Navigation row
            if (_currentStep > 0 && _currentStep < _totalSteps - 1)
              _BottomNav(
                onBack: _back,
                onNext: _next,
                onSkip: _skip,
                isLast: _currentStep == _totalSteps - 2,
              )
            else if (_currentStep == 0)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _next,
                        style: FilledButton.styleFrom(
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(NeomageTranslationConstants.getStarted.tr),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Welcome page (step 0) ──

  Widget _buildWelcomePage(ThemeData theme, ColorScheme cs) {
    final isWeb = kIsWeb;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Language toggle ──
              _LanguageToggle(
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 32),

              // Animated logo — bigger for web
              ScaleTransition(
                scale: _logoScale,
                child: FadeTransition(
                  opacity: _logoOpacity,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: Image.asset(
                      NeomageAssets.icon,
                      package: 'neomage',
                      width: isWeb ? 180 : 140,
                      height: isWeb ? 180 : 140,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              // Animated title
              AnimatedBuilder(
                animation: _titleAnimController,
                builder: (_, child) => Opacity(
                  opacity: _titleOpacity.value,
                  child: Transform.translate(
                    offset: Offset(0, _titleSlide.value),
                    child: child,
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      NeomageTranslationConstants.appTitle.tr,
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      NeomageTranslationConstants.welcomeSubtitle.tr,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Wrap(
                      spacing: 16,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        _FeatureChip(icon: Icons.code, label: NeomageTranslationConstants.codeEditing.tr),
                        _FeatureChip(
                          icon: Icons.search,
                          label: NeomageTranslationConstants.codebaseSearch.tr,
                        ),
                        _FeatureChip(
                          icon: Icons.terminal,
                          label: NeomageTranslationConstants.shellCommands.tr,
                        ),
                        _FeatureChip(icon: Icons.extension, label: NeomageTranslationConstants.mcpTools.tr),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Private helper widgets
// ===========================================================================

/// Dot step indicator at the top.
class _StepIndicator extends StatelessWidget {
  final int totalSteps;
  final int currentStep;
  final Color color;

  const _StepIndicator({
    required this.totalSteps,
    required this.currentStep,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(totalSteps, (i) {
          final active = i == currentStep;
          final completed = i < currentStep;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 28 : 10,
            height: 10,
            decoration: BoxDecoration(
              color: active
                  ? color
                  : completed
                  ? color.withAlpha(150)
                  : color.withAlpha(50),
              borderRadius: BorderRadius.circular(5),
            ),
          );
        }),
      ),
    );
  }
}

/// Bottom navigation bar with Back / Next / Skip.
class _BottomNav extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final bool isLast;

  const _BottomNav({
    required this.onBack,
    required this.onNext,
    required this.onSkip,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: Text(NeomageTranslationConstants.back.tr),
          ),
          const Spacer(),
          TextButton(onPressed: onSkip, child: Text(NeomageTranslationConstants.skip.tr)),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onNext,
            child: Text(isLast ? 'Finish' : 'Next'),
          ),
        ],
      ),
    );
  }
}

/// Small chip used on the welcome page.
class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language toggle — allows switching between Spanish and English on welcome page
// ---------------------------------------------------------------------------

class _LanguageToggle extends StatelessWidget {
  final VoidCallback onChanged;

  const _LanguageToggle({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final currentLocale = Sint.locale?.languageCode ?? 'es';
    final isSpanish = currentLocale == 'es';

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.language, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        // Spanish button
        _LangButton(
          label: 'ES',
          isSelected: isSpanish,
          colorScheme: cs,
          onTap: () {
            Sint.updateLocale(const Locale('es'));
            onChanged();
          },
        ),
        const SizedBox(width: 8),
        // English button
        _LangButton(
          label: 'EN',
          isSelected: !isSpanish,
          colorScheme: cs,
          onTap: () {
            Sint.updateLocale(const Locale('en'));
            onChanged();
          },
        ),
      ],
    );
  }
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _LangButton({
    required this.label,
    required this.isSelected,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: API Configuration
// ---------------------------------------------------------------------------

class _ApiConfigStep extends StatelessWidget {
  final ApiProviderType providerType;
  final ValueChanged<ApiProviderType> onProviderChanged;
  final TextEditingController apiKeyController;
  final bool obscureApiKey;
  final VoidCallback onToggleObscure;
  final String selectedModel;
  final List<String> models;
  final ValueChanged<String> onModelChanged;
  final TextEditingController baseUrlController;
  final bool showBaseUrl;
  final bool testingConnection;
  final _ConnectionTestResult? testResult;
  final VoidCallback onTestConnection;

  const _ApiConfigStep({
    required this.providerType,
    required this.onProviderChanged,
    required this.apiKeyController,
    required this.obscureApiKey,
    required this.onToggleObscure,
    required this.selectedModel,
    required this.models,
    required this.onModelChanged,
    required this.baseUrlController,
    required this.showBaseUrl,
    required this.testingConnection,
    required this.testResult,
    required this.onTestConnection,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                NeomageTranslationConstants.apiConfigTitle.tr,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                NeomageTranslationConstants.apiConfigSubtitle.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),

              // Explanatory info card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: cs.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        NeomageTranslationConstants.apiConfigExplanation.tr,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Provider selector — wrap-friendly
              Text(NeomageTranslationConstants.provider.tr, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    ApiProviderType.gemini: 'Gemini',
                    ApiProviderType.qwen: 'Qwen',
                    ApiProviderType.openai: 'OpenAI',
                    ApiProviderType.deepseek: 'DeepSeek',
                    ApiProviderType.custom: 'Custom',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: providerType == entry.key,
                      onSelected: (_) => onProviderChanged(entry.key),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              // API key
              if (providerType != ApiProviderType.ollama) ...[
                TextField(
                  controller: apiKeyController,
                  obscureText: obscureApiKey,
                  decoration: InputDecoration(
                    labelText: NeomageTranslationConstants.apiKey.tr,
                    hintText: NeomageTranslationConstants.apiKeyHint.tr,
                    prefixIcon: const Icon(Icons.key),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            obscureApiKey
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: onToggleObscure,
                          tooltip: obscureApiKey ? 'Show key' : 'Hide key',
                        ),
                        IconButton(
                          icon: const Icon(Icons.content_paste),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            if (data?.text != null) {
                              apiKeyController.text = data!.text!;
                            }
                          },
                          tooltip: NeomageTranslationConstants.pasteFromClipboard.tr,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Model dropdown
              DropdownButtonFormField<String>(
                initialValue: models.contains(selectedModel)
                    ? selectedModel
                    : models.first,
                decoration: InputDecoration(
                  labelText: NeomageTranslationConstants.model.tr,
                  prefixIcon: Icon(Icons.smart_toy),
                ),
                items: models
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) onModelChanged(v);
                },
              ),
              const SizedBox(height: 16),

              // Base URL (custom / ollama)
              if (showBaseUrl) ...[
                TextField(
                  controller: baseUrlController,
                  decoration: InputDecoration(
                    labelText: NeomageTranslationConstants.baseUrl.tr,
                    hintText: NeomageTranslationConstants.baseUrlHint.tr,
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Test connection button
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: testingConnection ? null : onTestConnection,
                      icon: testingConnection
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_tethering),
                      label: Text(
                        testingConnection ? 'Testing...' : 'Test Connection',
                      ),
                    ),
                  ),
                ),
              ),

              // Test result
              if (testResult != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: testResult!.success
                        ? Colors.green.withAlpha(25)
                        : Colors.red.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: testResult!.success ? Colors.green : Colors.red,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        testResult!.success ? Icons.check_circle : Icons.error,
                        color: testResult!.success ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          testResult!.success
                              ? 'Connection successful'
                              : testResult!.message!,
                          style: TextStyle(
                            color: testResult!.success
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Permission Mode
// ---------------------------------------------------------------------------

enum _PermissionModeOption { defaultMode, acceptEdits, plan, fullAuto }

class _PermissionStep extends StatelessWidget {
  final _PermissionModeOption selected;
  final ValueChanged<_PermissionModeOption> onChanged;

  const _PermissionStep({required this.selected, required this.onChanged});

  static const _modes = <_PermissionModeData>[
    _PermissionModeData(
      mode: _PermissionModeOption.defaultMode,
      icon: Icons.shield_outlined,
      title: 'Default',
      description:
          'Ask permission for file writes and shell commands. '
          'Recommended for new users.',
      risk: 'Low risk',
      riskColor: Colors.green,
    ),
    _PermissionModeData(
      mode: _PermissionModeOption.acceptEdits,
      icon: Icons.edit_note,
      title: 'Accept Edits',
      description:
          'Auto-approve file edits but ask before running shell commands.',
      risk: 'Medium risk',
      riskColor: Colors.orange,
    ),
    _PermissionModeData(
      mode: _PermissionModeOption.plan,
      icon: Icons.map_outlined,
      title: 'Plan Mode',
      description:
          'Generate a plan but do not execute any tools. '
          'Read-only exploration.',
      risk: 'No risk',
      riskColor: Colors.blue,
    ),
    _PermissionModeData(
      mode: _PermissionModeOption.fullAuto,
      icon: Icons.bolt,
      title: 'Full Auto',
      description:
          'Bypass all permission prompts. Only use in sandboxed '
          'environments or trusted repos.',
      risk: 'High risk',
      riskColor: Colors.red,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permission Mode',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how much autonomy the assistant has.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              ..._modes.map(
                (data) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _PermissionCard(
                    data: data,
                    isSelected: selected == data.mode,
                    onTap: () => onChanged(data.mode),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionModeData {
  final _PermissionModeOption mode;
  final IconData icon;
  final String title;
  final String description;
  final String risk;
  final Color riskColor;

  const _PermissionModeData({
    required this.mode,
    required this.icon,
    required this.title,
    required this.description,
    required this.risk,
    required this.riskColor,
  });
}

class _PermissionCard extends StatelessWidget {
  final _PermissionModeData data;
  final bool isSelected;
  final VoidCallback onTap;

  const _PermissionCard({
    required this.data,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? cs.primaryContainer.withAlpha(100)
          : cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? cs.primary : cs.outlineVariant,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(data.icon, size: 32, color: cs.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          data.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: data.riskColor.withAlpha(30),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            data.risk,
                            style: TextStyle(
                              fontSize: 11,
                              color: data.riskColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.description,
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Workspace Setup
// ---------------------------------------------------------------------------

class _WorkspaceStep extends StatelessWidget {
  final TextEditingController dirController;
  final bool gitEnabled;
  final ValueChanged<bool> onGitChanged;
  final bool createNeomageMd;
  final ValueChanged<bool> onNeomageMdChanged;

  const _WorkspaceStep({
    required this.dirController,
    required this.gitEnabled,
    required this.onGitChanged,
    required this.createNeomageMd,
    required this.onNeomageMdChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Workspace Setup',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Configure your project workspace.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Directory picker
              TextField(
                controller: dirController,
                decoration: InputDecoration(
                  labelText: 'Working Directory',
                  prefixIcon: const Icon(Icons.folder_open),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.drive_file_move_outline),
                    tooltip: NeomageTranslationConstants.browse.tr,
                    onPressed: () {
                      // In a full implementation this would open a
                      // native directory picker.
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The root directory for file operations and search.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Git integration toggle
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(NeomageTranslationConstants.gitIntegration.tr),
                subtitle: Text(
                  NeomageTranslationConstants.gitIntegrationDesc.tr,
                ),
                secondary: Icon(Icons.commit, color: cs.primary),
                value: gitEnabled,
                onChanged: onGitChanged,
              ),
              const Divider(),

              // NEOMAGE.md setup
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(NeomageTranslationConstants.createNeomageMd.tr),
                subtitle: Text(
                  NeomageTranslationConstants.createNeomageMdDesc.tr,
                ),
                secondary: Icon(Icons.description_outlined, color: cs.primary),
                value: createNeomageMd,
                onChanged: onNeomageMdChanged,
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Info card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer.withAlpha(50),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 20, color: cs.tertiary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'NEOMAGE.md is loaded automatically at the start of '
                        'each conversation. It can contain coding standards, '
                        'repo structure notes, and custom instructions.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Feature Overview Carousel
// ---------------------------------------------------------------------------

class _FeaturesStep extends StatelessWidget {
  final PageController pageController;
  final int currentPage;
  final ValueChanged<int> onPageChanged;

  const _FeaturesStep({
    required this.pageController,
    required this.currentPage,
    required this.onPageChanged,
  });

  static const _features = <_FeatureSlide>[
    _FeatureSlide(
      icon: Icons.build_outlined,
      title: 'Built-in Tools',
      description:
          'Read, write, edit, and search files. Run shell commands. '
          'All tools follow the permission rules you configured.',
    ),
    _FeatureSlide(
      icon: Icons.extension_outlined,
      title: 'MCP Servers',
      description:
          'Connect external tools via the Model Context Protocol. '
          'Add database access, web search, or custom integrations.',
    ),
    _FeatureSlide(
      icon: Icons.keyboard_outlined,
      title: 'Vim Mode & Keybindings',
      description:
          'Full vim keybinding support in the input bar. '
          'Customizable key mappings via keybindings.json.',
    ),
    _FeatureSlide(
      icon: Icons.flash_on_outlined,
      title: 'Slash Commands',
      description:
          'Type / to access built-in commands: /compact, /model, '
          '/cost, /memory, /clear, and more.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Features',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Swipe to explore what you can do.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: PageView.builder(
            controller: pageController,
            itemCount: _features.length,
            onPageChanged: onPageChanged,
            itemBuilder: (_, i) {
              final f = _features[i];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        f.icon,
                        size: 40,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      f.title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      f.description,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        // Dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _features.length,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              width: i == currentPage ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: i == currentPage ? cs.primary : cs.outlineVariant,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeatureSlide {
  final IconData icon;
  final String title;
  final String description;
  const _FeatureSlide({
    required this.icon,
    required this.title,
    required this.description,
  });
}

// ---------------------------------------------------------------------------
// Step 5: Completion
// ---------------------------------------------------------------------------

class _CompletionStep extends StatelessWidget {
  final bool finishing;
  final VoidCallback onStart;
  final VoidCallback onBack;

  const _CompletionStep({
    required this.finishing,
    required this.onStart,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 48,
                color: Colors.green,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              "You're all set!",
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your assistant is configured and ready to go.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: 240,
              height: 52,
              child: FilledButton.icon(
                onPressed: finishing ? null : onStart,
                icon: finishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.chat_bubble_outline),
                label: Text(finishing ? 'Initializing...' : 'Start Chatting'),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: finishing ? null : onBack,
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(NeomageTranslationConstants.backToSettings.tr),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper data class for connection test result
// ---------------------------------------------------------------------------

// Platform-safe initial workspace path.
// On web, Uri.base gives the page URL; toFilePath() may throw, so we fallback.
String _getDefaultWorkspacePath() {
  if (kIsWeb) {
    // Use the URL path as a reasonable default on web.
    final path = Uri.base.path;
    return path.isEmpty || path == '/' ? '/workspace' : path;
  }
  // On native platforms, try Directory.current via path_provider or fallback.
  try {
    return Uri.base.toFilePath();
  } catch (_) {
    return '/workspace';
  }
}

class _ConnectionTestResult {
  final bool success;
  final String? message;

  const _ConnectionTestResult._({required this.success, this.message});

  factory _ConnectionTestResult.success() =>
      const _ConnectionTestResult._(success: true);

  factory _ConnectionTestResult.failure(String msg) =>
      _ConnectionTestResult._(success: false, message: msg);
}

// ---------------------------------------------------------------------------
// Step 1: Choose Mode (Cloud vs Local)
// ---------------------------------------------------------------------------

class _ChooseModeStep extends StatelessWidget {
  final _SetupMode mode;
  final ValueChanged<_SetupMode> onModeChanged;
  final bool isDesktop;

  const _ChooseModeStep({
    required this.mode,
    required this.onModeChanged,
    required this.isDesktop,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                NeomageTranslationConstants.chooseModeTitle.tr,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                NeomageTranslationConstants.chooseModeSubtitle.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),

              // Cloud option
              _ModeCard(
                icon: Icons.cloud_outlined,
                title: NeomageTranslationConstants.cloudMode.tr,
                description: NeomageTranslationConstants.cloudModeDesc.tr,
                selected: mode == _SetupMode.cloud,
                onTap: () => onModeChanged(_SetupMode.cloud),
                colorScheme: cs,
              ),
              const SizedBox(height: 16),

              // Local option
              _ModeCard(
                icon: Icons.computer,
                title: NeomageTranslationConstants.localMode.tr,
                description: NeomageTranslationConstants.localModeDesc.tr,
                selected: mode == _SetupMode.local,
                onTap: isDesktop ? () => onModeChanged(_SetupMode.local) : null,
                colorScheme: cs,
                badge: isDesktop
                    ? null
                    : NeomageTranslationConstants.localModeDesktopOnly.tr,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool selected;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;
  final String? badge;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
    required this.colorScheme,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final theme = Theme.of(context);

    return Opacity(
      opacity: disabled ? 0.45 : 1.0,
      child: Material(
        color: selected
            ? colorScheme.primaryContainer.withAlpha(80)
            : colorScheme.surfaceContainerHighest.withAlpha(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withAlpha(60),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected
                        ? colorScheme.primary.withAlpha(30)
                        : colorScheme.surfaceContainerHighest.withAlpha(80),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 28,
                    color: selected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle,
                                size: 18, color: colorScheme.primary),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.errorContainer.withAlpha(60),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2-alt: Ollama Setup (Local Mode)
// ---------------------------------------------------------------------------

class _OllamaSetupStep extends StatelessWidget {
  final OllamaClient ollamaService;
  final OllamaStatus status;
  final List<OllamaModel> models;
  final String? selectedModel;
  final bool checking;
  final String? pullingModel;
  final double? pullProgress;
  final VoidCallback onCheckStatus;
  final ValueChanged<String> onSelectModel;
  final ValueChanged<String> onPullModel;

  const _OllamaSetupStep({
    required this.ollamaService,
    required this.status,
    required this.models,
    required this.selectedModel,
    required this.checking,
    required this.pullingModel,
    required this.pullProgress,
    required this.onCheckStatus,
    required this.onSelectModel,
    required this.onPullModel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Auto-check on first build if status is unknown.
    if (status == OllamaStatus.unknown && !checking) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onCheckStatus());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                NeomageTranslationConstants.ollamaSetupTitle.tr,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                NeomageTranslationConstants.ollamaSetupSubtitle.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Status card
              _buildStatusCard(theme, cs),
              const SizedBox(height: 24),

              // Installed models
              if (status == OllamaStatus.running) ...[
                if (models.isNotEmpty) ...[
                  Text(
                    NeomageTranslationConstants.ollamaInstalledModels.tr,
                    style: theme.textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  ...models.map((m) => _buildModelTile(m, theme, cs)),
                  const SizedBox(height: 24),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withAlpha(40),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: 20, color: cs.tertiary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            NeomageTranslationConstants.ollamaNoModels.tr,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Recommended models
                Text(
                  NeomageTranslationConstants.ollamaRecommended.tr,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                ...ollamaRecommendedModels.map(
                    (r) => _buildRecommendedTile(r, theme, cs)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme, ColorScheme cs) {
    final isRunning = status == OllamaStatus.running;
    final isChecking = checking;

    if (isChecking) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Checking Ollama...'),
          ],
        ),
      );
    }

    if (isRunning) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(20),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.withAlpha(60)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                NeomageTranslationConstants.ollamaRunning.tr,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onCheckStatus,
              child: Text(NeomageTranslationConstants.refresh.tr),
            ),
          ],
        ),
      );
    }

    // Not running / error
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withAlpha(40),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withAlpha(40)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.error, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  NeomageTranslationConstants.ollamaNotDetected.tr,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            NeomageTranslationConstants.ollamaNotDetectedDesc.tr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () {
                  // Open ollama.com — in a real app, use url_launcher.
                },
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('ollama.com'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onCheckStatus,
                icon: const Icon(Icons.refresh, size: 16),
                label: Text(NeomageTranslationConstants.retry.tr),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModelTile(OllamaModel model, ThemeData theme, ColorScheme cs) {
    final isSelected = selectedModel == model.name;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outlineVariant.withAlpha(40),
            width: isSelected ? 2 : 1,
          ),
        ),
        tileColor: isSelected ? cs.primaryContainer.withAlpha(40) : null,
        leading: Icon(
          isSelected ? Icons.check_circle : Icons.circle_outlined,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        ),
        title: Text(model.displayName,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(
          [
            if (model.sizeLabel.isNotEmpty) model.sizeLabel,
            if (model.family != null) model.family!,
            if (model.parameterSize != null) model.parameterSize!,
          ].join(' \u2022 '),
          style: theme.textTheme.bodySmall,
        ),
        onTap: () => onSelectModel(model.name),
      ),
    );
  }

  Widget _buildRecommendedTile(
    ({String name, String desc, String size}) rec,
    ThemeData theme,
    ColorScheme cs,
  ) {
    final isInstalled = models.any((m) => m.name == rec.name);
    final isPulling = pullingModel == rec.name;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        title: Text(rec.name,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${rec.desc} \u2022 ${rec.size}',
                style: theme.textTheme.bodySmall),
            if (isPulling && pullProgress != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: LinearProgressIndicator(
                  value: pullProgress,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
        trailing: isInstalled
            ? Chip(
                label: Text(NeomageTranslationConstants.installed.tr),
                visualDensity: VisualDensity.compact,
              )
            : isPulling
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: NeomageTranslationConstants.download.tr,
                    onPressed: () => onPullModel(rec.name),
                  ),
      ),
    );
  }
}
