// SessionBrowserScreen — port of neom_claw/src/components/SessionBrowser/.
// Browse, search, resume, fork, export, and delete past sessions.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/services/conversation_service.dart';

// ─── SessionBrowserScreen ───

/// Full-screen session browser with search, filter, and actions.
class SessionBrowserScreen extends StatefulWidget {
  final ConversationService conversationService;
  final ValueChanged<String>? onResume;
  final ValueChanged<String>? onFork;
  final ValueChanged<String>? onExport;

  const SessionBrowserScreen({
    super.key,
    required this.conversationService,
    this.onResume,
    this.onFork,
    this.onExport,
  });

  @override
  State<SessionBrowserScreen> createState() => _SessionBrowserScreenState();
}

class _SessionBrowserScreenState extends State<SessionBrowserScreen> {
  List<ConversationSummary> _sessions = [];
  bool _loading = true;
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.lastActive;
  bool _sortAscending = false;
  final Set<String> _selectedSessions = {};
  bool _multiSelectMode = false;
  ConversationStats? _stats;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sessions = await widget.conversationService.listConversations(
      searchQuery: _searchQuery,
    );
    final stats = await widget.conversationService.getStats();

    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _stats = stats;
      _loading = false;
      _sortSessions();
    });
  }

  void _sortSessions() {
    _sessions.sort((a, b) {
      int cmp;
      switch (_sortMode) {
        case _SortMode.lastActive:
          cmp = a.lastActiveAt.compareTo(b.lastActiveAt);
          break;
        case _SortMode.created:
          cmp = a.startedAt.compareTo(b.startedAt);
          break;
        case _SortMode.messages:
          cmp = a.messageCount.compareTo(b.messageCount);
          break;
        case _SortMode.cost:
          cmp = a.totalCost.compareTo(b.totalCost);
          break;
        case _SortMode.tokens:
          cmp = (a.totalInputTokens + a.totalOutputTokens).compareTo(
            b.totalInputTokens + b.totalOutputTokens,
          );
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });
  }

  Future<void> _deleteSession(String sessionId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text('Delete session $sessionId? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.conversationService.deleteConversation(sessionId);
      _load();
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedSessions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Sessions'),
        content: Text(
          'Delete ${_selectedSessions.length} sessions? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedSessions) {
        await widget.conversationService.deleteConversation(id);
      }
      _selectedSessions.clear();
      _multiSelectMode = false;
      _load();
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatCost(double cost) {
    if (cost < 0.01) return '<\$0.01';
    return '\$${cost.toStringAsFixed(2)}';
  }

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return '$tokens';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          if (_multiSelectMode && _selectedSessions.isNotEmpty)
            IconButton(
              onPressed: _deleteSelected,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete selected',
              color: Colors.red,
            ),
          IconButton(
            onPressed: () {
              setState(() {
                _multiSelectMode = !_multiSelectMode;
                _selectedSessions.clear();
              });
            },
            icon: Icon(_multiSelectMode ? Icons.close : Icons.checklist),
            tooltip: _multiSelectMode ? 'Cancel selection' : 'Select multiple',
          ),
          PopupMenuButton<_SortMode>(
            onSelected: (mode) {
              setState(() {
                if (_sortMode == mode) {
                  _sortAscending = !_sortAscending;
                } else {
                  _sortMode = mode;
                  _sortAscending = false;
                }
                _sortSessions();
              });
            },
            icon: const Icon(Icons.sort),
            tooltip: 'Sort by',
            itemBuilder: (_) => [
              _sortItem('Last Active', _SortMode.lastActive),
              _sortItem('Created', _SortMode.created),
              _sortItem('Messages', _SortMode.messages),
              _sortItem('Cost', _SortMode.cost),
              _sortItem('Tokens', _SortMode.tokens),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Stats bar
          if (_stats != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A1A30)
                    : const Color(0xFFF5F5FA),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statChip('${_stats!.totalSessions}', 'sessions', Icons.chat),
                  _statChip(
                    _formatTokens(_stats!.totalTokens),
                    'tokens',
                    Icons.token,
                  ),
                  _statChip(
                    _formatCost(_stats!.totalCost),
                    'total',
                    Icons.attach_money,
                  ),
                ],
              ),
            ),

          // Search bar
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: (q) {
                _searchQuery = q;
                _load();
              },
              decoration: InputDecoration(
                hintText: 'Search sessions...',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                isDense: true,
              ),
            ),
          ),

          // Session list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.history,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No sessions matching "$_searchQuery"'
                              : 'No sessions yet',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      return _SessionCard(
                        session: session,
                        isDark: isDark,
                        isSelected: _selectedSessions.contains(
                          session.sessionId,
                        ),
                        multiSelectMode: _multiSelectMode,
                        onTap: () {
                          if (_multiSelectMode) {
                            setState(() {
                              if (_selectedSessions.contains(
                                session.sessionId,
                              )) {
                                _selectedSessions.remove(session.sessionId);
                              } else {
                                _selectedSessions.add(session.sessionId);
                              }
                            });
                          } else {
                            widget.onResume?.call(session.sessionId);
                          }
                        },
                        onResume: () =>
                            widget.onResume?.call(session.sessionId),
                        onFork: () => widget.onFork?.call(session.sessionId),
                        onExport: () =>
                            widget.onExport?.call(session.sessionId),
                        onDelete: () => _deleteSession(session.sessionId),
                        formatDate: _formatDate,
                        formatCost: _formatCost,
                        formatTokens: _formatTokens,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  PopupMenuItem<_SortMode> _sortItem(String label, _SortMode mode) {
    final isActive = _sortMode == mode;
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (isActive)
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 14,
            ),
          if (isActive) const SizedBox(width: 4),
          Text(label),
        ],
      ),
    );
  }

  Widget _statChip(String value, String label, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: isDark ? Colors.white38 : Colors.black38),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black54,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white30 : Colors.black26,
          ),
        ),
      ],
    );
  }
}

enum _SortMode { lastActive, created, messages, cost, tokens }

// ─── Session card ───

class _SessionCard extends StatelessWidget {
  final ConversationSummary session;
  final bool isDark;
  final bool isSelected;
  final bool multiSelectMode;
  final VoidCallback onTap;
  final VoidCallback onResume;
  final VoidCallback onFork;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final String Function(DateTime) formatDate;
  final String Function(double) formatCost;
  final String Function(int) formatTokens;

  const _SessionCard({
    required this.session,
    required this.isDark,
    required this.isSelected,
    required this.multiSelectMode,
    required this.onTap,
    required this.onResume,
    required this.onFork,
    required this.onExport,
    required this.onDelete,
    required this.formatDate,
    required this.formatCost,
    required this.formatTokens,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? (isDark
                ? Colors.blue.shade900.withValues(alpha: 0.3)
                : Colors.blue.shade50)
          : (isDark ? const Color(0xFF1E1E36) : Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: Colors.blue.shade400)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  if (multiSelectMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(
                        isSelected
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                        color: isSelected ? Colors.blue : Colors.grey,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      session.title ?? 'Untitled',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatDate(session.lastActiveAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Preview text
              if (session.lastUserMessage != null)
                Text(
                  session.lastUserMessage!,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 8),

              // Stats row
              Row(
                children: [
                  _badge(Icons.chat_outlined, '${session.messageCount} msgs'),
                  const SizedBox(width: 8),
                  _badge(Icons.smart_toy_outlined, session.model),
                  const SizedBox(width: 8),
                  _badge(
                    Icons.token,
                    formatTokens(
                      session.totalInputTokens + session.totalOutputTokens,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _badge(Icons.attach_money, formatCost(session.totalCost)),
                  const Spacer(),

                  // Actions
                  if (!multiSelectMode)
                    PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'resume':
                            onResume();
                            break;
                          case 'fork':
                            onFork();
                            break;
                          case 'export':
                            onExport();
                            break;
                          case 'delete':
                            onDelete();
                            break;
                        }
                      },
                      icon: Icon(
                        Icons.more_horiz,
                        size: 16,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      padding: EdgeInsets.zero,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'resume',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow, size: 16),
                              SizedBox(width: 8),
                              Text('Resume'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'fork',
                          child: Row(
                            children: [
                              Icon(Icons.fork_right, size: 16),
                              SizedBox(width: 8),
                              Text('Fork'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'export',
                          child: Row(
                            children: [
                              Icon(Icons.download, size: 16),
                              SizedBox(width: 8),
                              Text('Export'),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Delete',
                                style: TextStyle(color: Colors.red),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),

              // Tools used
              if (session.toolsUsed.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 2,
                  children: session.toolsUsed.take(5).map((tool) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.black.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        tool,
                        style: TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: isDark ? Colors.white30 : Colors.black26,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: isDark ? Colors.white30 : Colors.black26),
        const SizedBox(width: 2),
        Text(
          text,
          style: TextStyle(
            fontSize: 10,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }
}
