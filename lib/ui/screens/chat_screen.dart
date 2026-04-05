// Chat screen — primary UI of neomage.
// Port of neomage's main chat interface with side panel, command palette,
// toast notifications, keyboard shortcuts, and responsive layout.

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_assets.dart';
import '../../utils/constants/neomage_translation_constants.dart';
import '../../neomage_routes.dart';
import 'package:neomage/data/auth/auth_service.dart';
import 'package:neomage/data/api/api_provider.dart';
import 'package:neomage/data/api/anthropic_client.dart';
import 'package:neomage/data/api/gemini_client.dart';
import 'package:neomage/data/api/openai_shim.dart';
import 'package:neomage/data/services/ollama_service.dart';
import 'package:neomage/domain/models/message.dart';
import 'package:neomage/utils/config/settings.dart';
import '../controllers/chat_controller.dart';
import '../widgets/input_bar.dart';
import '../widgets/message_renderer.dart';
import '../widgets/skills_panel.dart';
import '../widgets/streaming_text.dart';

/// Returns true if running on a mobile device (phone/tablet, not web).
bool get _isMobilePlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
     defaultTargetPlatform == TargetPlatform.android);

/// Returns true if running on a desktop platform (not web, not mobile).
bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
     defaultTargetPlatform == TargetPlatform.windows ||
     defaultTargetPlatform == TargetPlatform.linux);

/// Resolve the [ApiProviderType] from a model name string.
ApiProviderType _providerFromModel(String model) {
  // Ollama models typically have a ':' tag (e.g. 'llama3.1:8b', 'qwen2.5-coder:7b')
  // or are common local model names. Check this first to avoid mismatches with cloud.
  if (model.contains(':') &&
      !model.contains('claude') &&
      !model.startsWith('anthropic.')) {
    return ApiProviderType.ollama;
  }
  if (model.contains('llama') || model.contains('mistral') ||
      model.contains('codestral') || model.contains('phi')) {
    return ApiProviderType.ollama;
  }
  if (model.contains('gemini')) return ApiProviderType.gemini;
  if (model.contains('qwen')) return ApiProviderType.qwen;
  if (model.contains('gpt') || model.contains('o1') || model.contains('o3')) {
    return ApiProviderType.openai;
  }
  if (model.contains('deepseek')) return ApiProviderType.deepseek;
  if (model.contains('claude') || model.contains('opus') ||
      model.contains('sonnet') || model.contains('haiku')) {
    return ApiProviderType.anthropic;
  }
  return ApiProviderType.openai; // fallback
}

// ── Side Panel Tab Enum ──

enum SidePanelTab { agents, tasks, skills, mcpServers }

// ── Toast Notification ──

class _ToastEntry {
  final String message;
  final IconData icon;
  final Color color;
  final DateTime created;

  _ToastEntry({
    required this.message,
    this.icon = Icons.info_outline,
    this.color = Colors.blue,
    DateTime? created,
  }) : created = created ?? DateTime.now();
}

// ── Command Palette Entry ──

class _CommandEntry {
  final String label;
  final String? shortcut;
  final IconData icon;
  final VoidCallback action;

  const _CommandEntry({
    required this.label,
    this.shortcut,
    required this.icon,
    required this.action,
  });
}

// ── Main Chat Screen ──

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();

  // Side panel state
  bool _sidePanelOpen = false;
  SidePanelTab _sidePanelTab = SidePanelTab.agents;

  // Command palette
  bool _commandPaletteOpen = false;
  final _commandSearchController = TextEditingController();
  final _commandPaletteFocusNode = FocusNode();

  // Toast notifications
  final List<_ToastEntry> _toasts = [];
  Timer? _toastTimer;

  // Model selector — actual value loaded from persisted config in _loadSettings.
  String _selectedModel = '';
  // ignore: unused_field
  final bool _modelDropdownOpen = false;

  // Session info
  int _turnCount = 0;
  double _sessionCost = 0.0;

  // Layout
  static const double _sidePanelWidth = 300.0;
  static const double _mobileBreakpoint = 768.0;
  static const double _wideBreakpoint = 1200.0;

  /// Max chat content width — prevents messages from stretching full screen.
  static double _chatMaxWidth(double screenWidth) {
    if (screenWidth > 1400) return 860;
    if (screenWidth > 1100) return 780;
    if (screenWidth > 900) return 700;
    return screenWidth;
  }

  // Streaming animation
  late final AnimationController _streamingDotController;

  @override
  void initState() {
    super.initState();
    _streamingDotController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _loadSettings();
  }

  /// Navigate to settings and reload config when returning.
  void _goToSettings() {
    Sint.toNamed(NeomageRouteConstants.settings)?.then((_) => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    // Load the actually configured model from auth service.
    final authService = Sint.find<AuthService>();
    final config = await authService.loadApiConfig();
    if (config != null && mounted) {
      setState(() {
        _selectedModel = config.model;
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _focusNode.dispose();
    _commandSearchController.dispose();
    _commandPaletteFocusNode.dispose();
    _toastTimer?.cancel();
    _streamingDotController.dispose();
    super.dispose();
  }

  // ── Scroll ──

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  // ── Toast ──

  void _showToast(
    String message, {
    IconData icon = Icons.info_outline,
    Color color = Colors.blue,
  }) {
    setState(() {
      _toasts.add(_ToastEntry(message: message, icon: icon, color: color));
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _toasts.removeWhere(
            (t) => DateTime.now().difference(t.created).inSeconds >= 4,
          );
        });
      }
    });
  }

  // ── Command Palette ──

  List<_CommandEntry> _buildCommands() {
    final chat = Sint.find<ChatController>();
    return [
      _CommandEntry(
        label: NeomageTranslationConstants.newConversation.tr,
        shortcut: 'Ctrl+N',
        icon: Icons.add_comment,
        action: () {
          chat.clearConversation();
          _closeCommandPalette();
          _showToast(NeomageTranslationConstants.conversationCleared.tr);
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.toggleSidePanel.tr,
        shortcut: 'Ctrl+B',
        icon: Icons.view_sidebar,
        action: () {
          setState(() => _sidePanelOpen = !_sidePanelOpen);
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.settings.tr,
        shortcut: 'Ctrl+,',
        icon: Icons.settings,
        action: () {
          _closeCommandPalette();
          _goToSettings();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.changeModel.tr,
        icon: Icons.smart_toy,
        action: () {
          _closeCommandPalette();
          _showModelSelector();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.clearConversation.tr,
        icon: Icons.delete_sweep,
        action: () {
          chat.clearConversation();
          _closeCommandPalette();
          _showToast(NeomageTranslationConstants.conversationCleared.tr);
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.showAgents.tr,
        icon: Icons.group,
        action: () {
          setState(() {
            _sidePanelOpen = true;
            _sidePanelTab = SidePanelTab.agents;
          });
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.showTasks.tr,
        icon: Icons.task_alt,
        action: () {
          setState(() {
            _sidePanelOpen = true;
            _sidePanelTab = SidePanelTab.tasks;
          });
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.showMcpServers.tr,
        icon: Icons.dns,
        action: () {
          setState(() {
            _sidePanelOpen = true;
            _sidePanelTab = SidePanelTab.mcpServers;
          });
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: 'Skills',
        icon: Icons.auto_awesome,
        action: () {
          setState(() {
            _sidePanelOpen = true;
            _sidePanelTab = SidePanelTab.skills;
          });
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.toggleTheme.tr,
        icon: Icons.dark_mode,
        action: () {
          _closeCommandPalette();
          _showToast(NeomageTranslationConstants.themeToggleNotImplemented.tr);
        },
      ),
      _CommandEntry(
        label: NeomageTranslationConstants.exportConversation.tr,
        icon: Icons.download,
        action: () {
          _closeCommandPalette();
          _showToast(NeomageTranslationConstants.exportNotImplemented.tr);
        },
      ),
    ];
  }

  void _openCommandPalette() {
    setState(() {
      _commandPaletteOpen = true;
      _commandSearchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _commandPaletteFocusNode.requestFocus();
    });
  }

  void _closeCommandPalette() {
    setState(() => _commandPaletteOpen = false);
  }

  void _showModelSelector() {
    showDialog(
      context: context,
      builder: (ctx) => _ModelSelectorDialog(
        currentModel: _selectedModel,
        onSelect: (model) => _switchToModel(model),
      ),
    );
  }

  /// Switch to [model], checking if the provider has an API key first.
  /// If not, shows a modal dialog to request the key before proceeding.
  Future<void> _switchToModel(String model) async {
    final provider = _providerFromModel(model);

    // Ollama doesn't need a key
    if (!AuthService.requiresApiKey(provider)) {
      _applyModelSwitch(model, provider);
      return;
    }

    // Check if key already exists
    final authService = Sint.find<AuthService>();
    final existingKey = await authService.getApiKeyForProvider(provider);

    if (existingKey != null && existingKey.isNotEmpty) {
      _applyModelSwitch(model, provider);
      return;
    }

    // No key — show modal to request it
    if (!mounted) return;
    final key = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ApiKeyRequestDialog(
        providerName: AuthService.providerDisplayName(provider),
        providerType: provider,
      ),
    );

    if (key != null && key.isNotEmpty) {
      await authService.setApiKeyForProvider(provider, key);
      if (mounted) _applyModelSwitch(model, provider);
    }
  }

  void _applyModelSwitch(String model, ApiProviderType provider) {
    setState(() => _selectedModel = model);
    // Persist the selection
    final authService = Sint.find<AuthService>();
    authService.saveProviderConfig(type: provider, model: model);
    _showToast('${NeomageTranslationConstants.modelChangedTo.tr} $model', icon: Icons.smart_toy);
  }

  // ── Keyboard Shortcuts ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    // Ctrl+K — command palette
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyK) {
      if (_commandPaletteOpen) {
        _closeCommandPalette();
      } else {
        _openCommandPalette();
      }
      return KeyEventResult.handled;
    }

    // Ctrl+B — toggle side panel
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyB) {
      setState(() => _sidePanelOpen = !_sidePanelOpen);
      return KeyEventResult.handled;
    }

    // Ctrl+N — new conversation
    if (ctrl && event.logicalKey == LogicalKeyboardKey.keyN) {
      final chat = Sint.find<ChatController>();
      chat.clearConversation();
      _showToast(NeomageTranslationConstants.conversationCleared.tr);
      return KeyEventResult.handled;
    }

    // Ctrl+, — settings
    if (ctrl && event.logicalKey == LogicalKeyboardKey.comma) {
      _goToSettings();
      return KeyEventResult.handled;
    }

    // Escape — close overlays
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (_commandPaletteOpen) {
        _closeCommandPalette();
        return KeyEventResult.handled;
      }
      if (_sidePanelOpen) {
        setState(() => _sidePanelOpen = false);
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ── Cost Calculation ──

  String _formatCost(double cost) {
    if (cost < 0.01) return '<\$0.01';
    return '\$${cost.toStringAsFixed(2)}';
  }

  void _updateSessionCost(TokenUsage? usage) {
    if (usage == null) return;
    // Rough cost estimate: $3/MTok input, $15/MTok output for Sonnet
    final inputCost = usage.inputTokens * 3.0 / 1_000_000;
    final outputCost = usage.outputTokens * 15.0 / 1_000_000;
    _sessionCost += inputCost + outputCost;
    _turnCount++;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final chat = Sint.find<ChatController>();
    final isMobile = MediaQuery.of(context).size.width < _mobileBreakpoint;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      autofocus: true,
      child: Scaffold(
        // Mobile drawer for side panel
        drawer: isMobile
            ? Drawer(
                width: _sidePanelWidth,
                child: _SidePanelContent(
                  selectedTab: _sidePanelTab,
                  onTabChanged: (tab) => setState(() => _sidePanelTab = tab),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
              )
            : null,
        body: SafeArea(
          child: Stack(
          children: [
            // Main content row
            Row(
              children: [
                // Side panel (desktop only)
                if (!isMobile && _sidePanelOpen)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: _sidePanelWidth,
                    child: _SidePanelContent(
                      selectedTab: _sidePanelTab,
                      onTabChanged: (tab) =>
                          setState(() => _sidePanelTab = tab),
                      isDark: isDark,
                      colorScheme: colorScheme,
                    ),
                  ),

                // Chat area
                Expanded(
                  child: Column(
                    children: [
                      // Top bar
                      _buildTopBar(chat, isMobile, isDark, colorScheme),

                      // Messages
                      Expanded(
                        child: Obx(() {
                          final msgs = chat.messages;
                          final streaming = chat.isStreaming.value;

                          // Update cost tracking
                          if (chat.lastUsage.value != null &&
                              msgs.length ~/ 2 > _turnCount) {
                            _updateSessionCost(chat.lastUsage.value);
                          }

                          if (msgs.isEmpty && !streaming) {
                            return Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: _chatMaxWidth(MediaQuery.of(context).size.width)),
                                child: _EmptyState(onSuggestion: chat.handleInput),
                              ),
                            );
                          }

                          if (streaming || msgs.isNotEmpty) {
                            _scrollToBottom();
                          }

                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: _chatMaxWidth(MediaQuery.of(context).size.width),
                              ),
                              child: ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                itemCount: msgs.length + (streaming ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == msgs.length && streaming) {
                                    return _buildStreamingIndicator(
                                      chat,
                                      isDark,
                                      colorScheme,
                                    );
                                  }
                                  return ConversationMessage(message: msgs[index]);
                                },
                              ),
                            ),
                          );
                        }),
                      ),

                      // Error banner
                      Obx(() {
                        final err = chat.error.value;
                        if (err == null) {
                          return const SizedBox.shrink();
                        }
                        return _ErrorBanner(
                          error: err,
                          onDismiss: () => chat.error.value = null,
                        );
                      }),

                      // Input area
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _chatMaxWidth(MediaQuery.of(context).size.width),
                          ),
                          child: Obx(
                            () => InputBar(
                              onSubmit: (text, {attachments = const []}) {
                                chat.handleInput(text, attachments: attachments);
                              },
                              isLoading: chat.isLoading.value,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // Command palette overlay
            if (_commandPaletteOpen)
              _CommandPaletteOverlay(
                commands: _buildCommands(),
                searchController: _commandSearchController,
                focusNode: _commandPaletteFocusNode,
                onClose: _closeCommandPalette,
                isDark: isDark,
                colorScheme: colorScheme,
              ),

            // Toast notifications
            Positioned(
              bottom: 100,
              right: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _toasts.map((t) => _ToastWidget(entry: t)).toList(),
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  // ── Top Bar ──

  Widget _buildTopBar(
    ChatController chat,
    bool isMobile,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // Side panel toggle
          if (isMobile)
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu, size: 20),
                onPressed: () => Scaffold.of(ctx).openDrawer(),
                tooltip: NeomageTranslationConstants.openSidePanel.tr,
              ),
            )
          else
            IconButton(
              icon: Icon(
                _sidePanelOpen ? Icons.view_sidebar : Icons.menu,
                size: 20,
              ),
              onPressed: () => setState(() => _sidePanelOpen = !_sidePanelOpen),
              tooltip: NeomageTranslationConstants.toggleSidePanel.tr,
            ),

          const SizedBox(width: 4),

          // Logo
          Icon(Icons.terminal, size: 18, color: colorScheme.primary),
          const SizedBox(width: 6),
          if (!isMobile)
            Text(
              NeomageTranslationConstants.appTitle.tr,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: colorScheme.onSurface,
              ),
            ),

          if (!isMobile) const SizedBox(width: 16),

          // Model selector
          Flexible(
            child: _ModelChip(
              model: _selectedModel,
              onTap: _showModelSelector,
              colorScheme: colorScheme,
            ),
          ),

          const Spacer(),

          // Session info
          if (!isMobile)
            Obx(() {
              final usage = chat.lastUsage.value;
              if (usage == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Token count
                    _InfoChip(
                      icon: Icons.token,
                      label: '${usage.totalTokens}',
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    // Cost estimate
                    _InfoChip(
                      icon: Icons.attach_money,
                      label: _formatCost(_sessionCost),
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    _InfoChip(
                      icon: Icons.chat_bubble_outline,
                      label: '$_turnCount',
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
              );
            }),

          // Actions
          if (!isMobile)
            IconButton(
              icon: const Icon(Icons.search, size: 20),
              onPressed: _openCommandPalette,
              tooltip: NeomageTranslationConstants.commandPaletteShortcut.tr,
            ),
          Obx(
            () => IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: chat.messages.isEmpty
                  ? null
                  : () {
                      chat.clearConversation();
                      _turnCount = 0;
                      _sessionCost = 0.0;
                      _showToast(NeomageTranslationConstants.conversationCleared.tr);
                    },
              tooltip: NeomageTranslationConstants.clearConversation.tr,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            onPressed: () => _goToSettings(),
            tooltip: NeomageTranslationConstants.settings.tr,
          ),
        ],
      ),
    );
  }

  // ── Streaming Indicator ──

  Widget _buildStreamingIndicator(
    ChatController chat,
    bool isDark,
    ColorScheme colorScheme,
  ) {
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth < 600
        ? screenWidth * 0.82
        : screenWidth * 0.65;

    return Obx(() {
      final text = chat.streamingText.value;
      final toolName = chat.currentToolName.value;

      if (text.isEmpty && toolName == null) {
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            margin: const EdgeInsets.only(top: 8, bottom: 4, right: 48, left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _AnimatedThinkingDots(
              controller: _streamingDotController,
              colorScheme: colorScheme,
            ),
          ),
        );
      }

      return StreamingText(text: text, toolName: toolName);
    });
  }
}

// ── Model Chip ──

class _ModelChip extends StatelessWidget {
  final String model;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ModelChip({
    required this.model,
    required this.onTap,
    required this.colorScheme,
  });

  String get _shortName {
    if (model.isEmpty) return '...';
    if (model.contains('gemini')) return 'Gemini';
    if (model.contains('qwen')) return 'Qwen';
    if (model.contains('deepseek')) return 'DeepSeek';
    if (model.contains('opus')) return 'Opus';
    if (model.contains('sonnet')) return 'Sonnet';
    if (model.contains('haiku')) return 'Haiku';
    if (model.contains('gpt-4o')) return 'GPT-4o';
    if (model.contains('o1')) return 'o1';
    if (model.contains('o3')) return 'o3';
    if (model.contains('llama')) return 'Llama';
    if (model.contains('mistral')) return 'Mistral';
    if (model.contains('codestral')) return 'Codestral';
    if (model.length > 20) return '${model.substring(0, 18)}...';
    return model;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy, size: 14, color: colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              _shortName,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

// ── Info Chip ──

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ColorScheme colorScheme;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Model Selector Dialog ──

class _ModelSelectorDialog extends StatefulWidget {
  final String currentModel;
  final ValueChanged<String> onSelect;

  const _ModelSelectorDialog({
    required this.currentModel,
    required this.onSelect,
  });

  @override
  State<_ModelSelectorDialog> createState() => _ModelSelectorDialogState();
}

class _ModelSelectorDialogState extends State<_ModelSelectorDialog> {
  // Cloud models — static catalog.
  static const _cloudModels = <String, List<String>>{
    'Gemini': [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-1.5-pro',
    ],
    'Qwen': [
      'qwen-plus',
      'qwen-max',
      'qwen-turbo',
      'qwen2.5-coder-32b-instruct',
    ],
    'OpenAI': ['gpt-4o', 'gpt-4o-mini', 'o1-preview', 'o3-mini'],
    'DeepSeek': ['deepseek-chat', 'deepseek-coder', 'deepseek-reasoner'],
    'Anthropic': [
      'claude-opus-4-20250514',
      'claude-sonnet-4-20250514',
      'claude-haiku-3-5-20241022',
    ],
  };

  // Ollama models — loaded dynamically.
  List<OllamaModel>? _ollamaModels;
  bool _loadingOllama = false;

  @override
  void initState() {
    super.initState();
    // Check if current provider is Ollama or if on desktop, load Ollama models.
    if (_isDesktopPlatform) {
      _loadOllamaModels();
    }
  }

  Future<void> _loadOllamaModels() async {
    setState(() => _loadingOllama = true);
    try {
      final service = OllamaService();
      final status = await service.checkStatus();
      if (status == OllamaStatus.running) {
        final models = await service.listModels();
        if (mounted) setState(() => _ollamaModels = models);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingOllama = false);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Build the model map: cloud + ollama (if available).
    final models = <String, List<String>>{};

    // Add cloud models (hide on mobile only Ollama, but cloud is always visible).
    models.addAll(_cloudModels);

    // Add Ollama section for desktop.
    if (_isDesktopPlatform) {
      if (_ollamaModels != null && _ollamaModels!.isNotEmpty) {
        models['Ollama (Local)'] =
            _ollamaModels!.map((m) => m.name).toList();
      } else if (_loadingOllama) {
        models['Ollama (Local)'] = []; // Will show loading indicator.
      }
    } else if (kIsWeb) {
      // On web, show Ollama as disabled.
      models['Ollama'] = ['llama3.1', 'mistral', 'codestral'];
    }

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                NeomageTranslationConstants.selectModel.tr,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: models.entries.expand((provider) {
                  final isOllamaOnWeb =
                      provider.key == 'Ollama' && kIsWeb;
                  final isOllamaLocal =
                      provider.key == 'Ollama (Local)';
                  return [
                    // Provider header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          Text(
                            provider.key,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                          if (isOllamaOnWeb) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                NeomageTranslationConstants.desktopOnly.tr,
                                style: TextStyle(
                                  fontSize: 9,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                          if (isOllamaLocal && _loadingOllama) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isOllamaOnWeb)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          NeomageTranslationConstants.ollamaDesktopNote.tr,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    if (isOllamaLocal && provider.value.isEmpty && !_loadingOllama)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Text(
                          NeomageTranslationConstants.ollamaDesktopNote.tr,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    // Model tiles
                    ...provider.value.map(
                      (model) => ListTile(
                        dense: true,
                        enabled: !isOllamaOnWeb,
                        leading: model == widget.currentModel
                            ? Icon(
                                Icons.check,
                                size: 18,
                                color: colorScheme.primary,
                              )
                            : const SizedBox(width: 18),
                        title: Text(
                          model,
                          style: TextStyle(
                            fontSize: 13,
                            color: isOllamaOnWeb
                                ? colorScheme.onSurface.withValues(alpha: 0.4)
                                : null,
                          ),
                        ),
                        trailing: isOllamaLocal
                            ? Icon(Icons.computer, size: 14,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4))
                            : null,
                        onTap: isOllamaOnWeb
                            ? null
                            : () {
                                widget.onSelect(model);
                                Navigator.of(context).pop();
                              },
                      ),
                    ),
                  ];
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── API Key Request Dialog (with Test Connection) ──

class _ApiKeyRequestDialog extends StatefulWidget {
  final String providerName;
  final ApiProviderType providerType;

  const _ApiKeyRequestDialog({
    required this.providerName,
    required this.providerType,
  });

  @override
  State<_ApiKeyRequestDialog> createState() => _ApiKeyRequestDialogState();
}

class _ApiKeyRequestDialogState extends State<_ApiKeyRequestDialog> {
  final _keyController = TextEditingController();
  bool _obscure = true;
  bool _testing = false;
  bool _testPassed = false;
  String? _testError;

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      setState(() {
        _testError = NeomageTranslationConstants.apiKeyRequired.tr
            .replaceAll('@provider', widget.providerName);
        _testPassed = false;
      });
      return;
    }

    setState(() {
      _testing = true;
      _testError = null;
      _testPassed = false;
    });

    try {
      final model = AuthService.defaultModel(widget.providerType);
      final baseUrl = AuthService.defaultBaseUrl(widget.providerType);

      final provider = switch (widget.providerType) {
        ApiProviderType.anthropic => AnthropicClient(
            ApiConfig.anthropic(apiKey: key, model: model)),
        ApiProviderType.gemini => GeminiClient(
            ApiConfig.gemini(apiKey: key, model: model)),
        _ => OpenAiShim(ApiConfig(
            type: widget.providerType,
            baseUrl: baseUrl,
            apiKey: key,
            model: model,
          )),
      };

      final stream = provider.createMessageStream(
        messages: [
          Message(role: MessageRole.user, content: [TextBlock('Hi')]),
        ],
        systemPrompt: 'Reply with "ok".',
        maxTokens: 8,
      );

      final firstEvent = await stream.first.timeout(
        const Duration(seconds: 10),
      );

      if (firstEvent is ErrorEvent) {
        final msg = firstEvent.message;
        setState(() {
          _testing = false;
          _testPassed = false;
          _testError = msg.contains('401') || msg.contains('Unauthorized')
              ? 'Invalid API key'
              : msg.contains('403')
                  ? 'Access denied for this model'
                  : 'Error: ${msg.length > 100 ? '${msg.substring(0, 100)}...' : msg}';
        });
        return;
      }

      setState(() {
        _testing = false;
        _testPassed = true;
        _testError = null;
      });
    } catch (e) {
      final msg = e.toString();
      setState(() {
        _testing = false;
        _testPassed = false;
        _testError = msg.contains('TimeoutException')
            ? 'Connection timed out'
            : msg.contains('SocketException')
                ? 'Cannot reach API server'
                : 'Error: ${msg.length > 100 ? '${msg.substring(0, 100)}...' : msg}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.key, size: 22, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${widget.providerName} API Key',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              NeomageTranslationConstants.apiKeyRequired.tr
                  .replaceAll('@provider', widget.providerName),
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),

            // API key input
            TextField(
              controller: _keyController,
              obscureText: _obscure,
              autofocus: true,
              onChanged: (_) {
                // Reset test state when key changes
                if (_testPassed || _testError != null) {
                  setState(() {
                    _testPassed = false;
                    _testError = null;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: NeomageTranslationConstants.apiKey.tr,
                hintText: NeomageTranslationConstants.apiKeyHint.tr,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.vpn_key, size: 18),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 14),

            // Test connection button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : _testPassed
                        ? const Icon(Icons.check_circle, size: 18,
                            color: Colors.green)
                        : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(
                  _testing
                      ? 'Testing...'
                      : _testPassed
                          ? 'Connection OK ✓'
                          : 'Test Connection',
                ),
              ),
            ),

            // Test result feedback
            if (_testPassed)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, size: 16,
                          color: Colors.green),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'API key verified — ready to save.',
                          style: TextStyle(
                              fontSize: 12, color: Colors.green),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_testError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: cs.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, size: 16,
                          color: cs.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testError!,
                          style: TextStyle(
                              fontSize: 12, color: cs.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(NeomageTranslationConstants.cancel.tr),
        ),
        FilledButton(
          // Only allow save if test passed
          onPressed: _testPassed ? _submit : null,
          child: Text(NeomageTranslationConstants.saveAndContinue.tr),
        ),
      ],
    );
  }

  void _submit() {
    final key = _keyController.text.trim();
    if (key.isNotEmpty && _testPassed) {
      Navigator.of(context).pop(key);
    }
  }
}

// ── Side Panel Content ──

class _SidePanelContent extends StatelessWidget {
  final SidePanelTab selectedTab;
  final ValueChanged<SidePanelTab> onTabChanged;
  final bool isDark;
  final ColorScheme colorScheme;

  const _SidePanelContent({
    required this.selectedTab,
    required this.onTabChanged,
    required this.isDark,
    required this.colorScheme,
  });

  static const _tabs = [
    (SidePanelTab.agents, Icons.smart_toy_outlined, 'Agents'),
    (SidePanelTab.tasks, Icons.task_alt_outlined, 'Tasks'),
    (SidePanelTab.skills, Icons.auto_awesome_outlined, 'Skills'),
    (SidePanelTab.mcpServers, Icons.dns_outlined, 'MCP'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Tab bar — horizontal pill buttons
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              children: _tabs.map((tab) {
                final isSelected = selectedTab == tab.$1;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: InkWell(
                      onTap: () => onTabChanged(tab.$1),
                      borderRadius: BorderRadius.circular(8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? colorScheme.primary.withValues(alpha: 0.3)
                                : Colors.transparent,
                            width: 0.5,
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(tab.$2, size: 18,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            const SizedBox(height: 3),
                            Text(tab.$3, style: TextStyle(
                              fontSize: 10,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            )),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.3)),

          // Tab content
          Expanded(
            child: switch (selectedTab) {
              SidePanelTab.agents => _AgentsPanel(colorScheme: colorScheme),
              SidePanelTab.tasks => _TasksPanel(colorScheme: colorScheme),
              SidePanelTab.skills => SkillsPanel(colorScheme: colorScheme),
              SidePanelTab.mcpServers => _McpServersPanel(
                colorScheme: colorScheme,
              ),
            },
          ),
        ],
      ),
    );
  }
}

// ── Agents Panel ──

class _AgentsPanel extends StatelessWidget {
  final ColorScheme colorScheme;
  const _AgentsPanel({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No active agents',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Agents will appear here when spawned during a conversation.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tasks Panel ──

class _TasksPanel extends StatelessWidget {
  final ColorScheme colorScheme;
  const _TasksPanel({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.task_alt,
              size: 48,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No active tasks',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'Tasks created via TodoWrite will be tracked here.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── MCP Servers Panel ──

class _McpServersPanel extends StatefulWidget {
  final ColorScheme colorScheme;
  const _McpServersPanel({required this.colorScheme});

  @override
  State<_McpServersPanel> createState() => _McpServersPanelState();
}

class _McpServersPanelState extends State<_McpServersPanel> {
  final List<_McpServerEntry> _servers = [];

  void _showAddServerDialog() {
    final nameCtrl = TextEditingController();
    final commandCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    var transportType = 'stdio'; // stdio | sse

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add MCP Server'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Server Name',
                    hintText: 'e.g. filesystem, github',
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Transport',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'stdio', label: Text('stdio')),
                    ButtonSegment(value: 'sse', label: Text('SSE')),
                  ],
                  selected: {transportType},
                  onSelectionChanged: (s) {
                    setDialogState(() => transportType = s.first);
                  },
                ),
                const SizedBox(height: 12),
                if (transportType == 'stdio')
                  TextField(
                    controller: commandCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Command',
                      hintText:
                          'e.g. npx -y @modelcontextprotocol/server-filesystem /path',
                      isDense: true,
                    ),
                    maxLines: 2,
                  )
                else
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Server URL',
                      hintText: 'e.g. http://localhost:3001/sse',
                      isDense: true,
                    ),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          transportType == 'stdio'
                              ? 'The command will be executed as a subprocess.\n'
                                    'Example: npx -y @modelcontextprotocol/server-github'
                              : 'Connect to a running MCP server via SSE.\n'
                                    'The server must be accessible at the given URL.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final config = transportType == 'stdio'
                    ? commandCtrl.text.trim()
                    : urlCtrl.text.trim();
                if (config.isEmpty) return;

                setState(() {
                  _servers.add(
                    _McpServerEntry(
                      name: name,
                      transport: transportType,
                      config: config,
                    ),
                  );
                });
                Navigator.of(ctx).pop();
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  void _removeServer(int index) {
    setState(() => _servers.removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Text(
                'MCP Servers',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: _showAddServerDialog,
                tooltip: 'Add MCP server',
              ),
            ],
          ),
        ),
        Expanded(
          child: _servers.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.dns,
                          size: 48,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No MCP servers configured',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Click + to add an MCP server and extend\n'
                          'Neomage with custom tools and resources.',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _servers.length,
                  itemBuilder: (context, index) {
                    final server = _servers[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    server.name,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${server.transport} · ${server.config}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: cs.error,
                              ),
                              onPressed: () => _removeServer(index),
                              tooltip: 'Remove',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _McpServerEntry {
  final String name;
  final String transport;
  final String config;

  const _McpServerEntry({
    required this.name,
    required this.transport,
    required this.config,
  });
}

// ── Command Palette Overlay ──

class _CommandPaletteOverlay extends StatelessWidget {
  final List<_CommandEntry> commands;
  final TextEditingController searchController;
  final FocusNode focusNode;
  final VoidCallback onClose;
  final bool isDark;
  final ColorScheme colorScheme;

  const _CommandPaletteOverlay({
    required this.commands,
    required this.searchController,
    required this.focusNode,
    required this.onClose,
    required this.isDark,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onClose,
      child: Container(
        color: Colors.black54,
        child: Center(
          child: GestureDetector(
            onTap: () {}, // Absorb taps on the dialog
            child: Container(
              width: 480,
              constraints: const BoxConstraints(maxHeight: 400),
              margin: const EdgeInsets.only(bottom: 120),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search field
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: searchController,
                      focusNode: focusNode,
                      decoration: InputDecoration(
                        hintText: 'Type a command...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) {
                        // Execute first matching command
                        final query = searchController.text.toLowerCase();
                        final match = commands.where(
                          (c) => c.label.toLowerCase().contains(query),
                        );
                        if (match.isNotEmpty) {
                          match.first.action();
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  // Command list
                  Flexible(
                    child: ValueListenableBuilder<TextEditingValue>(
                      valueListenable: searchController,
                      builder: (_, value, _) {
                        final query = value.text.toLowerCase();
                        final filtered = query.isEmpty
                            ? commands
                            : commands
                                  .where(
                                    (c) =>
                                        c.label.toLowerCase().contains(query),
                                  )
                                  .toList();

                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final cmd = filtered[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(cmd.icon, size: 18),
                              title: Text(
                                cmd.label,
                                style: const TextStyle(fontSize: 13),
                              ),
                              trailing: cmd.shortcut != null
                                  ? Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        cmd.shortcut!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colorScheme.onSurfaceVariant,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    )
                                  : null,
                              onTap: cmd.action,
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error Banner ──

class _ErrorBanner extends StatelessWidget {
  final String error;
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.error, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        border: Border(
          top: BorderSide(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onErrorContainer,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

// ── Toast Widget ──

class _ToastWidget extends StatelessWidget {
  final _ToastEntry entry;

  const _ToastWidget({required this.entry});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon, size: 16, color: colorScheme.onInverseSurface),
              const SizedBox(width: 8),
              Text(
                entry.message,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onInverseSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Animated Thinking Dots ──

class _AnimatedThinkingDots extends StatelessWidget {
  final AnimationController controller;
  final ColorScheme colorScheme;

  const _AnimatedThinkingDots({
    required this.controller,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (_, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final offset = ((controller.value * 3 - i) % 3).clamp(
                    0.0,
                    1.0,
                  );
                  final opacity = 0.3 + 0.7 * offset;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Opacity(
                      opacity: opacity,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
          const SizedBox(width: 8),
          Text(
            'Generating...',
            style: TextStyle(
              fontSize: 13,
              fontStyle: FontStyle.italic,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty State ──

class _EmptyState extends StatelessWidget {
  final void Function(String) onSuggestion;

  const _EmptyState({required this.onSuggestion});

  // Desktop / Web suggestions — coding-oriented (translation keys + icons)
  static final _desktopSuggestionKeys = [
    (NeomageTranslationConstants.explainCodebase, Icons.description),
    (NeomageTranslationConstants.findTodoComments, Icons.search),
    (NeomageTranslationConstants.writeUnitTests, Icons.science),
    (NeomageTranslationConstants.refactorFunction, Icons.build),
    (NeomageTranslationConstants.reviewPR, Icons.rate_review),
    (NeomageTranslationConstants.debugError, Icons.bug_report),
  ];

  // Mobile suggestions — quick, on-the-go tasks (translation keys + icons)
  static final _mobileSuggestionKeys = [
    (NeomageTranslationConstants.summarizeArticle, Icons.article),
    (NeomageTranslationConstants.translateToEnglish, Icons.translate),
    (NeomageTranslationConstants.draftQuickReply, Icons.reply),
    (NeomageTranslationConstants.brainstormIdeas, Icons.lightbulb_outline),
    (NeomageTranslationConstants.explainConcept, Icons.school),
    (NeomageTranslationConstants.writeShortNote, Icons.edit_note),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile =
        MediaQuery.of(context).size.width < _ChatScreenState._mobileBreakpoint;

    final suggestionKeys =
        isMobile ? _mobileSuggestionKeys : _desktopSuggestionKeys;
    final subtitle = isMobile
        ? NeomageTranslationConstants.appSubtitleMobile.tr
        : NeomageTranslationConstants.appSubtitleDesktop.tr;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // App icon (real asset instead of generic Material icon)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  NeomageAssets.icon,
                  package: 'neomage',
                  width: isMobile ? 56 : 72,
                  height: isMobile ? 56 : 72,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.auto_awesome,
                    size: isMobile ? 48 : 64,
                    color: colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                NeomageTranslationConstants.appTitle.tr,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: suggestionKeys.map((s) {
                  final label = s.$1.tr;
                  return ActionChip(
                    avatar: Icon(s.$2, size: 16),
                    label: Text(label, style: const TextStyle(fontSize: 12)),
                    onPressed: () => onSuggestion(label),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Text(
                NeomageTranslationConstants.commandPaletteShortcut.tr,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
