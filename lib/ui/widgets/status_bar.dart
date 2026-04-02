// StatusBar — port of openclaude/src/components/StatusBar/.
// Bottom status bar with model, tokens, cost, git branch, connection status.

import 'dart:async';

import 'package:flutter/material.dart';

// ─── Types ───

/// Connection status.
enum ConnectionStatus { connected, connecting, disconnected, error }

/// Status bar data.
class StatusBarData {
  final String model;
  final int inputTokens;
  final int outputTokens;
  final int cacheReadTokens;
  final int cacheCreationTokens;
  final double cost;
  final String? gitBranch;
  final String? gitStatus; // 'clean', 'dirty', 'ahead', 'behind'
  final ConnectionStatus apiStatus;
  final int activeMcpServers;
  final int totalMcpServers;
  final int activeAgents;
  final int pendingTasks;
  final String? permissionMode;
  final bool vimMode;
  final String? workingDirectory;
  final Duration? sessionDuration;

  const StatusBarData({
    required this.model,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheReadTokens = 0,
    this.cacheCreationTokens = 0,
    this.cost = 0.0,
    this.gitBranch,
    this.gitStatus,
    this.apiStatus = ConnectionStatus.connected,
    this.activeMcpServers = 0,
    this.totalMcpServers = 0,
    this.activeAgents = 0,
    this.pendingTasks = 0,
    this.permissionMode,
    this.vimMode = false,
    this.workingDirectory,
    this.sessionDuration,
  });
}

// ─── StatusBar widget ───

/// Bottom status bar for the chat interface.
class StatusBar extends StatelessWidget {
  final StatusBarData data;
  final VoidCallback? onModelTap;
  final VoidCallback? onGitTap;
  final VoidCallback? onMcpTap;
  final VoidCallback? onAgentsTap;
  final VoidCallback? onPermissionsTap;
  final VoidCallback? onCostTap;

  const StatusBar({
    super.key,
    required this.data,
    this.onModelTap,
    this.onGitTap,
    this.onMcpTap,
    this.onAgentsTap,
    this.onPermissionsTap,
    this.onCostTap,
  });

  String _formatTokens(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  String _formatCost(double cost) {
    if (cost < 0.001) return '\$0.00';
    if (cost < 0.01) return '\$${cost.toStringAsFixed(3)}';
    return '\$${cost.toStringAsFixed(2)}';
  }

  String _formatDuration(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  String _modelShort(String model) {
    if (model.contains('opus')) return 'Opus';
    if (model.contains('sonnet-4-5') || model.contains('sonnet-4.5')) return 'Sonnet 4.5';
    if (model.contains('sonnet')) return 'Sonnet';
    if (model.contains('haiku')) return 'Haiku';
    if (model.contains('gpt-4o-mini')) return '4o-mini';
    if (model.contains('gpt-4o')) return 'GPT-4o';
    if (model.contains('gemini')) return 'Gemini';
    if (model.length > 15) return '${model.substring(0, 12)}...';
    return model;
  }

  Color _connectionColor(ConnectionStatus status) {
    switch (status) {
      case ConnectionStatus.connected:
        return Colors.green;
      case ConnectionStatus.connecting:
        return Colors.amber;
      case ConnectionStatus.disconnected:
        return Colors.grey;
      case ConnectionStatus.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark ? Colors.white38 : Colors.black38;
    final textStyle = TextStyle(
      fontSize: 11,
      fontFamily: 'monospace',
      color: muted,
    );

    return Container(
      height: 24,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF0F0F5),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 8),

          // Connection status dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _connectionColor(data.apiStatus),
            ),
          ),
          const SizedBox(width: 6),

          // Model
          _StatusItem(
            onTap: onModelTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined,
                    size: 12, color: muted),
                const SizedBox(width: 3),
                Text(_modelShort(data.model), style: textStyle),
              ],
            ),
          ),

          _divider(isDark),

          // Tokens
          _StatusItem(
            onTap: onCostTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.token, size: 12, color: muted),
                const SizedBox(width: 3),
                Text(
                  '${_formatTokens(data.inputTokens)}↑ ${_formatTokens(data.outputTokens)}↓',
                  style: textStyle,
                ),
                if (data.cacheReadTokens > 0) ...[
                  Text(
                    ' (${_formatTokens(data.cacheReadTokens)} cached)',
                    style: textStyle.copyWith(
                      color: isDark ? Colors.green.shade700 : Colors.green.shade300,
                    ),
                  ),
                ],
              ],
            ),
          ),

          _divider(isDark),

          // Cost
          _StatusItem(
            onTap: onCostTap,
            child: Text(_formatCost(data.cost), style: textStyle),
          ),

          // Git branch
          if (data.gitBranch != null) ...[
            _divider(isDark),
            _StatusItem(
              onTap: onGitTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fork_right, size: 12, color: muted),
                  const SizedBox(width: 3),
                  Text(data.gitBranch!, style: textStyle),
                  if (data.gitStatus == 'dirty')
                    Text(' *',
                        style: textStyle.copyWith(
                            color: Colors.orange.shade300)),
                ],
              ),
            ),
          ],

          // MCP servers
          if (data.totalMcpServers > 0) ...[
            _divider(isDark),
            _StatusItem(
              onTap: onMcpTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined, size: 12, color: muted),
                  const SizedBox(width: 3),
                  Text(
                    '${data.activeMcpServers}/${data.totalMcpServers}',
                    style: textStyle,
                  ),
                ],
              ),
            ),
          ],

          // Active agents
          if (data.activeAgents > 0) ...[
            _divider(isDark),
            _StatusItem(
              onTap: onAgentsTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.groups_outlined, size: 12, color: muted),
                  const SizedBox(width: 3),
                  Text('${data.activeAgents}', style: textStyle),
                  if (data.pendingTasks > 0)
                    Text(' +${data.pendingTasks}',
                        style: textStyle.copyWith(
                            color: Colors.amber.shade300)),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Right side: Permission mode, Vim, Duration

          // Permission mode
          if (data.permissionMode != null) ...[
            _StatusItem(
              onTap: onPermissionsTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    data.permissionMode == 'full-auto'
                        ? Icons.flash_on
                        : data.permissionMode == 'plan'
                            ? Icons.architecture
                            : Icons.security,
                    size: 12,
                    color: data.permissionMode == 'full-auto'
                        ? Colors.red.shade300
                        : muted,
                  ),
                  const SizedBox(width: 3),
                  Text(data.permissionMode!, style: textStyle),
                ],
              ),
            ),
            _divider(isDark),
          ],

          // Vim mode
          if (data.vimMode) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.shade900
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                'VIM',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? Colors.green.shade300
                      : Colors.green.shade800,
                ),
              ),
            ),
            _divider(isDark),
          ],

          // Session duration
          if (data.sessionDuration != null)
            Text(
              _formatDuration(data.sessionDuration!),
              style: textStyle,
            ),

          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _divider(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 1,
        height: 12,
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.1),
      ),
    );
  }
}

/// Tappable status item.
class _StatusItem extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _StatusItem({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: child,
      ),
    );
  }
}

// ─── Toast notifications ───

/// Toast position.
enum ToastPosition { top, bottom, topRight, bottomRight }

/// Toast severity.
enum ToastSeverity { info, success, warning, error }

/// Show a toast notification.
void showClawToast(
  BuildContext context, {
  required String message,
  String? detail,
  ToastSeverity severity = ToastSeverity.info,
  ToastPosition position = ToastPosition.bottomRight,
  Duration duration = const Duration(seconds: 3),
  VoidCallback? onAction,
  String? actionLabel,
}) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (ctx) => _ToastWidget(
      message: message,
      detail: detail,
      severity: severity,
      position: position,
      duration: duration,
      onDismiss: () => entry.remove(),
      onAction: onAction,
      actionLabel: actionLabel,
    ),
  );

  overlay.insert(entry);
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final String? detail;
  final ToastSeverity severity;
  final ToastPosition position;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  final String? actionLabel;

  const _ToastWidget({
    required this.message,
    this.detail,
    required this.severity,
    required this.position,
    required this.duration,
    required this.onDismiss,
    this.onAction,
    this.actionLabel,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _slide = Tween<Offset>(
      begin: const Offset(0.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto dismiss
    Future.delayed(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _severityColor() {
    switch (widget.severity) {
      case ToastSeverity.info:
        return Colors.blue;
      case ToastSeverity.success:
        return Colors.green;
      case ToastSeverity.warning:
        return Colors.orange;
      case ToastSeverity.error:
        return Colors.red;
    }
  }

  IconData _severityIcon() {
    switch (widget.severity) {
      case ToastSeverity.info:
        return Icons.info_outline;
      case ToastSeverity.success:
        return Icons.check_circle_outline;
      case ToastSeverity.warning:
        return Icons.warning_amber;
      case ToastSeverity.error:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned(
      right: widget.position == ToastPosition.topRight ||
              widget.position == ToastPosition.bottomRight
          ? 16
          : null,
      left: widget.position == ToastPosition.top ||
              widget.position == ToastPosition.bottom
          ? 16
          : null,
      top: widget.position == ToastPosition.top ||
              widget.position == ToastPosition.topRight
          ? 16
          : null,
      bottom: widget.position == ToastPosition.bottom ||
              widget.position == ToastPosition.bottomRight
          ? 40
          : null,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _opacity,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: isDark ? const Color(0xFF252540) : Colors.white,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border(
                  left: BorderSide(
                    width: 4,
                    color: _severityColor(),
                  ),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_severityIcon(),
                      size: 18, color: _severityColor()),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.message,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: isDark
                                ? Colors.white
                                : Colors.black87,
                          ),
                        ),
                        if (widget.detail != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.detail!,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark
                                  ? Colors.white54
                                  : Colors.black45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onAction != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        widget.onAction!();
                        widget.onDismiss();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                      ),
                      child: Text(
                        widget.actionLabel ?? 'Action',
                        style: TextStyle(
                          fontSize: 12,
                          color: _severityColor(),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: widget.onDismiss,
                    child: Icon(Icons.close, size: 14, color: Colors.grey),
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
