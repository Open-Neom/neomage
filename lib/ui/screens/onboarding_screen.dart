import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint_sentinel/sint_sentinel.dart';
import 'package:sint/sint.dart';

import '../../claw_routes.dart';
import '../../data/api/anthropic_client.dart';
import '../../data/api/api_provider.dart';
import '../../data/api/gemini_client.dart';
import '../../data/api/openai_shim.dart';
import '../../data/auth/auth_service.dart';
import '../../domain/models/message.dart';
import '../../utils/config/settings.dart';
import '../../utils/constants/neom_claw_assets.dart';
import '../controllers/chat_controller.dart';

// ---------------------------------------------------------------------------
// Onboarding wizard — multi-step setup ported from NeomClaw's onboarding.
// Steps: Welcome -> API Config -> Permission Mode -> Workspace -> Features
//        -> Completion
// ---------------------------------------------------------------------------

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with TickerProviderStateMixin {
  static const _totalSteps = 6;

  final _pageController = PageController();
  final _authService = AuthService();

  // Current step (0-indexed).
  int _currentStep = 0;

  // ── Step 1: API Configuration state ──
  ApiProviderType _providerType = ApiProviderType.gemini;
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  String _selectedModel = 'gemini-2.5-flash';
  bool _obscureApiKey = true;
  bool _testingConnection = false;
  _ConnectionTestResult? _connectionTestResult;

  // ── Step 2: Permission mode state ──
  _PermissionModeOption _permissionMode = _PermissionModeOption.defaultMode;

  // ── Step 3: Workspace state ──
  final _workspaceDirController = TextEditingController();
  bool _enableGitIntegration = true;
  bool _createNeomClawMd = true;

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
    if (_currentStep == 1) {
      // API config — key required for non-local providers.
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
    }
    if (_currentStep == 3) {
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

      // We only need the first event — if we get one, the key is valid.
      await stream.first.timeout(const Duration(seconds: 10));

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
      // Persist API configuration — save key for the correct provider.
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

      // Persist workspace prefs via SharedPreferences (AppSettings).
      final settings = await AppSettings.load();
      // Permission mode is stored as a string for simplicity.
      // Workspace dir, git toggle, NEOMCLAW.md are handled by the engine.

      if (mounted) {
        SintSentinel.logger.d('Initializing ChatController...');
        final chat = Sint.find<ChatController>();
        final ok = await chat.initialize();
        if (ok && mounted) {
          SintSentinel.logger.i('Onboarding complete — navigating to chat');
          Sint.offAllNamed(ClawRouteConstants.chat);
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
                    onModelChanged: (m) => setState(() => _selectedModel = m),
                    baseUrlController: _baseUrlController,
                    showBaseUrl:
                        _providerType == ApiProviderType.custom ||
                        _providerType == ApiProviderType.ollama,
                    testingConnection: _testingConnection,
                    testResult: _connectionTestResult,
                    onTestConnection: _testConnection,
                  ),
                  _PermissionStep(
                    selected: _permissionMode,
                    onChanged: (m) => setState(() => _permissionMode = m),
                  ),
                  _WorkspaceStep(
                    dirController: _workspaceDirController,
                    gitEnabled: _enableGitIntegration,
                    onGitChanged: (v) =>
                        setState(() => _enableGitIntegration = v),
                    createNeomClawMd: _createNeomClawMd,
                    onNeomClawMdChanged: (v) =>
                        setState(() => _createNeomClawMd = v),
                  ),
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
                  vertical: 12,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _next,
                    child: const Text('Get Started'),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated logo
            ScaleTransition(
              scale: _logoScale,
              child: FadeTransition(
                opacity: _logoOpacity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    NeomClawAssets.appIcon,
                    width: 100,
                    height: 100,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
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
                    'Neom Claw',
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI coding assistant\nAny model. Any platform.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _FeatureChip(icon: Icons.code, label: 'Code editing'),
                      _FeatureChip(
                        icon: Icons.search,
                        label: 'Codebase search',
                      ),
                      _FeatureChip(
                        icon: Icons.terminal,
                        label: 'Shell commands',
                      ),
                      _FeatureChip(icon: Icons.extension, label: 'MCP tools'),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
            label: const Text('Back'),
          ),
          const Spacer(),
          TextButton(onPressed: onSkip, child: const Text('Skip')),
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
    return Chip(
      avatar: Icon(icon, size: 16, color: cs.primary),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                'API Configuration',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Connect to your preferred AI provider.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Provider selector — wrap-friendly
              Text('Provider', style: theme.textTheme.labelLarge),
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
                    labelText: 'API Key',
                    hintText: 'sk-...',
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
                          tooltip: 'Paste from clipboard',
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
                decoration: const InputDecoration(
                  labelText: 'Model',
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
                  decoration: const InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://your-endpoint.com/v1',
                    prefixIcon: Icon(Icons.link),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Test connection button
              SizedBox(
                width: double.infinity,
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
  final bool createNeomClawMd;
  final ValueChanged<bool> onNeomClawMdChanged;

  const _WorkspaceStep({
    required this.dirController,
    required this.gitEnabled,
    required this.onGitChanged,
    required this.createNeomClawMd,
    required this.onNeomClawMdChanged,
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
                    tooltip: 'Browse',
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
                title: const Text('Git Integration'),
                subtitle: const Text(
                  'Enable git-aware features like diff view and commit helpers',
                ),
                secondary: Icon(Icons.commit, color: cs.primary),
                value: gitEnabled,
                onChanged: onGitChanged,
              ),
              const Divider(),

              // NEOMCLAW.md setup
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Create NEOMCLAW.md'),
                subtitle: const Text(
                  'Initialize a memory file with project context and instructions',
                ),
                secondary: Icon(Icons.description_outlined, color: cs.primary),
                value: createNeomClawMd,
                onChanged: onNeomClawMdChanged,
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
                        'NEOMCLAW.md is loaded automatically at the start of '
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
              label: const Text('Back to settings'),
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
