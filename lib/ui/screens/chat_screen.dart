// Chat screen — primary UI of flutter_claw.
// Port of openclaude's main chat interface with side panel, command palette,
// toast notifications, keyboard shortcuts, and responsive layout.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../../claw_routes.dart';
import '../../domain/models/message.dart';
import '../../domain/models/permissions.dart';
import '../../utils/config/settings.dart';
import '../../utils/constants/tool_names.dart';
import '../controllers/chat_controller.dart';
import '../widgets/input_bar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_renderer.dart';
import '../widgets/permission_dialog.dart';
import '../widgets/streaming_text.dart';

// ── Side Panel Tab Enum ──

enum SidePanelTab { agents, tasks, mcpServers }

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

  // Model selector
  String _selectedModel = 'claude-sonnet-4-20250514';
  bool _modelDropdownOpen = false;

  // Session info
  int _turnCount = 0;
  double _sessionCost = 0.0;

  // Layout
  static const double _sidePanelWidth = 320.0;
  static const double _mobileBreakpoint = 768.0;

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

  Future<void> _loadSettings() async {
    final settings = await AppSettings.load();
    setState(() {
      _selectedModel = 'claude-sonnet-4-20250514';
    });
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

  void _showToast(String message,
      {IconData icon = Icons.info_outline, Color color = Colors.blue}) {
    setState(() {
      _toasts.add(_ToastEntry(message: message, icon: icon, color: color));
    });
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _toasts.removeWhere((t) =>
              DateTime.now().difference(t.created).inSeconds >= 4);
        });
      }
    });
  }

  // ── Command Palette ──

  List<_CommandEntry> _buildCommands() {
    final chat = Sint.find<ChatController>();
    return [
      _CommandEntry(
        label: 'New Conversation',
        shortcut: 'Ctrl+N',
        icon: Icons.add_comment,
        action: () {
          chat.clearConversation();
          _closeCommandPalette();
          _showToast('Conversation cleared');
        },
      ),
      _CommandEntry(
        label: 'Toggle Side Panel',
        shortcut: 'Ctrl+B',
        icon: Icons.side_navigation,
        action: () {
          setState(() => _sidePanelOpen = !_sidePanelOpen);
          _closeCommandPalette();
        },
      ),
      _CommandEntry(
        label: 'Settings',
        shortcut: 'Ctrl+,',
        icon: Icons.settings,
        action: () {
          _closeCommandPalette();
          Sint.toNamed(ClawRouteConstants.settings);
        },
      ),
      _CommandEntry(
        label: 'Change Model',
        icon: Icons.smart_toy,
        action: () {
          _closeCommandPalette();
          _showModelSelector();
        },
      ),
      _CommandEntry(
        label: 'Clear Conversation',
        icon: Icons.delete_sweep,
        action: () {
          chat.clearConversation();
          _closeCommandPalette();
          _showToast('Conversation cleared');
        },
      ),
      _CommandEntry(
        label: 'Show Agents',
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
        label: 'Show Tasks',
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
        label: 'Show MCP Servers',
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
        label: 'Toggle Theme',
        icon: Icons.dark_mode,
        action: () {
          _closeCommandPalette();
          _showToast('Theme toggle not yet implemented');
        },
      ),
      _CommandEntry(
        label: 'Export Conversation',
        icon: Icons.download,
        action: () {
          _closeCommandPalette();
          _showToast('Export not yet implemented');
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
        onSelect: (model) {
          setState(() => _selectedModel = model);
          _showToast('Model changed to $model', icon: Icons.smart_toy);
        },
      ),
    );
  }

  // ── Keyboard Shortcuts ──

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final ctrl = HardwareKeyboard.instance.isControlPressed ||
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
      _showToast('Conversation cleared');
      return KeyEventResult.handled;
    }

    // Ctrl+, — settings
    if (ctrl && event.logicalKey == LogicalKeyboardKey.comma) {
      Sint.toNamed(ClawRouteConstants.settings);
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
    final isMobile =
        MediaQuery.of(context).size.width < _mobileBreakpoint;
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
                  onTabChanged: (tab) =>
                      setState(() => _sidePanelTab = tab),
                  isDark: isDark,
                  colorScheme: colorScheme,
                ),
              )
            : null,
        body: Stack(
          children: [
            // Main content row
            Row(
              children: [
                // Side panel (desktop only)
                if (!isMobile && _sidePanelOpen)
                  SizedBox(
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
                            return _EmptyState(
                              onSuggestion: chat.sendMessage,
                            );
                          }

                          if (streaming || msgs.isNotEmpty) {
                            _scrollToBottom();
                          }

                          return ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.only(
                                top: 8, bottom: 8),
                            itemCount:
                                msgs.length + (streaming ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index == msgs.length && streaming) {
                                return _buildStreamingIndicator(
                                    chat, isDark, colorScheme);
                              }
                              return MessageBubble(
                                  message: msgs[index]);
                            },
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
                      Obx(() => InputBar(
                            onSubmit: chat.sendMessage,
                            isLoading: chat.isLoading.value,
                          )),
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
                children: _toasts
                    .map((t) => _ToastWidget(entry: t))
                    .toList(),
              ),
            ),
          ],
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
          bottom:
              BorderSide(color: colorScheme.outlineVariant, width: 0.5),
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
                tooltip: 'Open side panel',
              ),
            )
          else
            IconButton(
              icon: Icon(
                _sidePanelOpen
                    ? Icons.side_navigation
                    : Icons.menu,
                size: 20,
              ),
              onPressed: () =>
                  setState(() => _sidePanelOpen = !_sidePanelOpen),
              tooltip: 'Toggle side panel',
            ),

          const SizedBox(width: 4),

          // Logo
          Icon(Icons.terminal, size: 18, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'Flutter Claw',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: colorScheme.onSurface,
            ),
          ),

          const SizedBox(width: 16),

          // Model selector
          _ModelChip(
            model: _selectedModel,
            onTap: _showModelSelector,
            colorScheme: colorScheme,
          ),

          const Spacer(),

          // Session info
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
                  if (!isMobile) ...[
                    const SizedBox(width: 6),
                    _InfoChip(
                      icon: Icons.chat_bubble_outline,
                      label: '$_turnCount',
                      colorScheme: colorScheme,
                    ),
                  ],
                ],
              ),
            );
          }),

          // Actions
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            onPressed: _openCommandPalette,
            tooltip: 'Command palette (Ctrl+K)',
          ),
          Obx(() => IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: chat.messages.isEmpty
                    ? null
                    : () {
                        chat.clearConversation();
                        _turnCount = 0;
                        _sessionCost = 0.0;
                        _showToast('Conversation cleared');
                      },
                tooltip: 'Clear conversation',
              )),
          IconButton(
            icon: const Icon(Icons.settings, size: 20),
            onPressed: () =>
                Sint.toNamed(ClawRouteConstants.settings),
            tooltip: 'Settings',
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
    return Obx(() {
      final text = chat.streamingText.value;
      final toolName = chat.currentToolName.value;

      if (text.isEmpty && toolName == null) {
        return _AnimatedThinkingDots(
          controller: _streamingDotController,
          colorScheme: colorScheme,
        );
      }

      return StreamingText(
        text: text,
        toolName: toolName,
      );
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
    if (model.contains('opus')) return 'Opus';
    if (model.contains('sonnet')) return 'Sonnet';
    if (model.contains('haiku')) return 'Haiku';
    if (model.contains('gpt-4o')) return 'GPT-4o';
    if (model.contains('o1')) return 'o1';
    if (model.contains('o3')) return 'o3';
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
            Icon(Icons.arrow_drop_down,
                size: 16, color: colorScheme.primary),
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
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Model Selector Dialog ──

class _ModelSelectorDialog extends StatelessWidget {
  final String currentModel;
  final ValueChanged<String> onSelect;

  const _ModelSelectorDialog({
    required this.currentModel,
    required this.onSelect,
  });

  static const _models = <String, List<String>>{
    'Anthropic': [
      'claude-opus-4-20250514',
      'claude-sonnet-4-20250514',
      'claude-haiku-3-5-20241022',
    ],
    'OpenAI': [
      'gpt-4o',
      'gpt-4o-mini',
      'o1-preview',
      'o3-mini',
    ],
    'Ollama': [
      'llama3.1',
      'llama3.1:70b',
      'mistral',
      'codestral',
      'deepseek-coder-v2',
    ],
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
                'Select Model',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: _models.entries.expand((provider) {
                  return [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Text(
                        provider.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    ...provider.value.map((model) => ListTile(
                          dense: true,
                          leading: model == currentModel
                              ? Icon(Icons.check,
                                  size: 18, color: colorScheme.primary)
                              : const SizedBox(width: 18),
                          title: Text(model, style: const TextStyle(fontSize: 13)),
                          onTap: () {
                            onSelect(model);
                            Navigator.of(context).pop();
                          },
                        )),
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
              color: colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Column(
        children: [
          // Tab bar
          Container(
            padding: const EdgeInsets.all(8),
            child: SegmentedButton<SidePanelTab>(
              segments: const [
                ButtonSegment(
                  value: SidePanelTab.agents,
                  icon: Icon(Icons.group, size: 16),
                  label: Text('Agents', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: SidePanelTab.tasks,
                  icon: Icon(Icons.task_alt, size: 16),
                  label: Text('Tasks', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: SidePanelTab.mcpServers,
                  icon: Icon(Icons.dns, size: 16),
                  label: Text('MCP', style: TextStyle(fontSize: 11)),
                ),
              ],
              selected: {selectedTab},
              onSelectionChanged: (s) => onTabChanged(s.first),
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),

          const Divider(height: 1),

          // Tab content
          Expanded(
            child: switch (selectedTab) {
              SidePanelTab.agents => _AgentsPanel(colorScheme: colorScheme),
              SidePanelTab.tasks => _TasksPanel(colorScheme: colorScheme),
              SidePanelTab.mcpServers =>
                _McpServersPanel(colorScheme: colorScheme),
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
            Icon(Icons.group, size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
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
            Icon(Icons.task_alt, size: 48,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
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

class _McpServersPanel extends StatelessWidget {
  final ColorScheme colorScheme;
  const _McpServersPanel({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
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
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 18),
                onPressed: () {},
                tooltip: 'Add MCP server',
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns, size: 48,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3)),
                  const SizedBox(height: 12),
                  Text(
                    'No MCP servers configured',
                    style:
                        TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add servers in Settings > MCP to extend capabilities.',
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
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
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        isDense: true,
                      ),
                      style: const TextStyle(fontSize: 14),
                      onSubmitted: (_) {
                        // Execute first matching command
                        final query =
                            searchController.text.toLowerCase();
                        final match = commands.where((c) =>
                            c.label.toLowerCase().contains(query));
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
                      builder: (_, value, __) {
                        final query = value.text.toLowerCase();
                        final filtered = query.isEmpty
                            ? commands
                            : commands
                                .where((c) => c.label
                                    .toLowerCase()
                                    .contains(query))
                                .toList();

                        return ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(
                              vertical: 4),
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final cmd = filtered[i];
                            return ListTile(
                              dense: true,
                              leading: Icon(cmd.icon, size: 18),
                              title: Text(cmd.label,
                                  style:
                                      const TextStyle(fontSize: 13)),
                              trailing: cmd.shortcut != null
                                  ? Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                      decoration: BoxDecoration(
                                        color: colorScheme
                                            .surfaceContainerHighest,
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        cmd.shortcut!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: colorScheme
                                              .onSurfaceVariant,
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
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(entry.icon,
                  size: 16, color: colorScheme.onInverseSurface),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: controller,
            builder: (_, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final offset =
                      ((controller.value * 3 - i) % 3).clamp(0.0, 1.0);
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

  static const _suggestions = [
    ('Explain this codebase', Icons.description),
    ('Find all TODO comments', Icons.search),
    ('Write unit tests', Icons.science),
    ('Refactor this function', Icons.build),
    ('Review this PR', Icons.rate_review),
    ('Debug this error', Icons.bug_report),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isMobile =
        MediaQuery.of(context).size.width < _ChatScreenState._mobileBreakpoint;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.code,
                size: isMobile ? 48 : 64,
                color: colorScheme.primary.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 16),
              Text(
                'Flutter Claw',
                style:
                    Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI coding assistant -- any model, any platform',
                style:
                    Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: _suggestions.map((s) {
                  return ActionChip(
                    avatar: Icon(s.$2, size: 16),
                    label:
                        Text(s.$1, style: const TextStyle(fontSize: 12)),
                    onPressed: () => onSuggestion(s.$1),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Text(
                'Ctrl+K for command palette',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
