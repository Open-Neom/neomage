// SessionBrowserScreen — browse, resume, and delete saved sessions
// using ChatController's session history (SessionHistoryManager).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'package:neomage/data/session/session_history.dart';
import 'package:neomage/domain/models/message.dart';

import '../../neomage_routes.dart';
import '../controllers/chat_controller.dart';

// ─── SessionBrowserScreen ───

/// Full-screen session browser that lists saved sessions from the
/// ChatController's SessionHistoryManager and allows loading/deleting them.
class SessionBrowserScreen extends StatefulWidget {
  const SessionBrowserScreen({super.key});

  @override
  State<SessionBrowserScreen> createState() => _SessionBrowserScreenState();
}

class _SessionBrowserScreenState extends State<SessionBrowserScreen> {
  late final ChatController _chat;

  List<_SessionInfo> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _chat = Sint.find<ChatController>();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _loading = true);

    final ids = await _chat.listSessions();
    final infos = <_SessionInfo>[];

    for (final id in ids) {
      // Load snapshot to extract metadata for display.
      final snapshot = await _chat.sessionHistoryManager?.loadSession(id);
      infos.add(_SessionInfo(id: id, snapshot: snapshot));
    }

    if (!mounted) return;
    setState(() {
      _sessions = infos;
      _loading = false;
    });
  }

  Future<void> _loadSession(String id) async {
    final success = await _chat.loadSession(id);
    if (success && mounted) {
      Sint.offNamed(NeomageRouteConstants.chat);
    }
  }

  Future<void> _deleteSession(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Session'),
        content: Text(
          'Delete session ${_truncateId(id)}? This cannot be undone.',
        ),
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
      await _chat.deleteSession(id);
      _loadSessions(); // Refresh list after delete
    }
  }

  String _truncateId(String id) {
    return id.length > 12 ? '${id.substring(0, 12)}...' : id;
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

  String _formatTokens(int tokens) {
    if (tokens >= 1000000) return '${(tokens / 1000000).toStringAsFixed(1)}M';
    if (tokens >= 1000) return '${(tokens / 1000).toStringAsFixed(1)}K';
    return '$tokens';
  }

  /// Extract the first user text from a message list for preview.
  String? _extractFirstUserText(List<Message> messages) {
    for (final msg in messages) {
      if (msg.role == MessageRole.user) {
        for (final block in msg.content) {
          if (block is TextBlock) {
            return block.text;
          }
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sessions'),
        actions: [
          IconButton(
            onPressed: _loadSessions,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _loading
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
                        'No saved sessions',
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Start a conversation and it will appear here.',
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  itemCount: _sessions.length,
                  itemBuilder: (context, index) {
                    final info = _sessions[index];
                    return _buildSessionCard(info, isDark);
                  },
                ),
    );
  }

  Widget _buildSessionCard(_SessionInfo info, bool isDark) {
    final snapshot = info.snapshot;
    final messageCount =
        snapshot?.metadata['messageCount'] as int? ??
        snapshot?.messages.length ??
        0;
    final inputTokens =
        snapshot?.metadata['totalInputTokens'] as int? ?? 0;
    final outputTokens =
        snapshot?.metadata['totalOutputTokens'] as int? ?? 0;
    final totalTokens = inputTokens + outputTokens;
    final updatedAt = snapshot?.updatedAt;
    final createdAt = snapshot?.createdAt;
    final preview = snapshot != null
        ? _extractFirstUserText(snapshot.messages)
        : null;

    return Dismissible(
      key: ValueKey(info.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete Session'),
            content: Text(
              'Delete session ${_truncateId(info.id)}? '
              'This cannot be undone.',
            ),
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
      },
      onDismissed: (_) async {
        await _chat.deleteSession(info.id);
        _loadSessions();
      },
      child: Card(
        margin: const EdgeInsets.only(bottom: 8),
        color: isDark ? const Color(0xFF1E1E36) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          onTap: () => _loadSession(info.id),
          onLongPress: () => _deleteSession(info.id),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row: session ID + date
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Session ${_truncateId(info.id)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (updatedAt != null)
                      Text(
                        _formatDate(updatedAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                  ],
                ),

                // Preview text
                if (preview != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 8),

                // Stats row
                Row(
                  children: [
                    _badge(
                      Icons.chat_outlined,
                      '$messageCount msgs',
                      isDark,
                    ),
                    const SizedBox(width: 8),
                    _badge(
                      Icons.token,
                      _formatTokens(totalTokens),
                      isDark,
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(width: 8),
                      _badge(
                        Icons.schedule,
                        _formatDate(createdAt),
                        isDark,
                      ),
                    ],
                    const Spacer(),
                    // Action buttons
                    IconButton(
                      onPressed: () => _loadSession(info.id),
                      icon: Icon(
                        Icons.play_arrow,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      tooltip: 'Load session',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                    IconButton(
                      onPressed: () => _deleteSession(info.id),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.red.shade300,
                      ),
                      tooltip: 'Delete session',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String text, bool isDark) {
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

/// Internal model holding a session ID and its loaded snapshot (if available).
class _SessionInfo {
  final String id;
  final SessionSnapshot? snapshot;

  const _SessionInfo({required this.id, this.snapshot});
}
