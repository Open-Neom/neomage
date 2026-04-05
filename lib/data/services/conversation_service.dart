// ConversationService — port of neomage/src/services/conversation/.
// Higher-level conversation management: history, sessions, forking, export.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

import '../engine/conversation_engine.dart';

// ─── Types ───

/// Conversation summary for listing.
class ConversationSummary {
  final String sessionId;
  final String? title;
  final DateTime startedAt;
  final DateTime lastActiveAt;
  final int messageCount;
  final int turnCount;
  final String model;
  final int totalInputTokens;
  final int totalOutputTokens;
  final double totalCost;
  final List<String> toolsUsed;
  final String? lastUserMessage;
  final String? lastAssistantMessage;

  const ConversationSummary({
    required this.sessionId,
    this.title,
    required this.startedAt,
    required this.lastActiveAt,
    required this.messageCount,
    required this.turnCount,
    required this.model,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    this.totalCost = 0.0,
    this.toolsUsed = const [],
    this.lastUserMessage,
    this.lastAssistantMessage,
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'title': title,
    'startedAt': startedAt.toIso8601String(),
    'lastActiveAt': lastActiveAt.toIso8601String(),
    'messageCount': messageCount,
    'turnCount': turnCount,
    'model': model,
    'totalInputTokens': totalInputTokens,
    'totalOutputTokens': totalOutputTokens,
    'totalCost': totalCost,
    'toolsUsed': toolsUsed,
    'lastUserMessage': lastUserMessage,
    'lastAssistantMessage': lastAssistantMessage,
  };

  factory ConversationSummary.fromJson(Map<String, dynamic> json) {
    return ConversationSummary(
      sessionId: json['sessionId'] as String,
      title: json['title'] as String?,
      startedAt: DateTime.parse(json['startedAt'] as String),
      lastActiveAt: DateTime.parse(json['lastActiveAt'] as String),
      messageCount: json['messageCount'] as int? ?? 0,
      turnCount: json['turnCount'] as int? ?? 0,
      model: json['model'] as String? ?? 'unknown',
      totalInputTokens: json['totalInputTokens'] as int? ?? 0,
      totalOutputTokens: json['totalOutputTokens'] as int? ?? 0,
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0.0,
      toolsUsed: (json['toolsUsed'] as List?)?.cast<String>() ?? [],
      lastUserMessage: json['lastUserMessage'] as String?,
      lastAssistantMessage: json['lastAssistantMessage'] as String?,
    );
  }
}

/// Conversation fork point.
class ForkPoint {
  final String parentSessionId;
  final int messageIndex;
  final String forkSessionId;
  final DateTime forkedAt;
  final String? reason;

  const ForkPoint({
    required this.parentSessionId,
    required this.messageIndex,
    required this.forkSessionId,
    required this.forkedAt,
    this.reason,
  });

  Map<String, dynamic> toJson() => {
    'parentSessionId': parentSessionId,
    'messageIndex': messageIndex,
    'forkSessionId': forkSessionId,
    'forkedAt': forkedAt.toIso8601String(),
    'reason': reason,
  };
}

/// Export format options.
enum ExportFormat { markdown, json, html, plainText }

/// Conversation stats.
class ConversationStats {
  final int totalSessions;
  final int totalMessages;
  final int totalTokens;
  final double totalCost;
  final Duration totalDuration;
  final Map<String, int> toolUsageCounts;
  final Map<String, int> modelUsageCounts;
  final int averageMessagesPerSession;
  final double averageCostPerSession;

  const ConversationStats({
    required this.totalSessions,
    required this.totalMessages,
    required this.totalTokens,
    required this.totalCost,
    required this.totalDuration,
    required this.toolUsageCounts,
    required this.modelUsageCounts,
    required this.averageMessagesPerSession,
    required this.averageCostPerSession,
  });
}

// ─── ConversationService ───

/// Manages conversation persistence, history, forking, and export.
class ConversationService {
  final String _sessionsDir;

  ConversationService({String? sessionsDir})
    : _sessionsDir =
          sessionsDir ??
          '${Platform.environment['HOME'] ?? '.'}/.neomage/sessions';

  /// List all conversations, newest first.
  Future<List<ConversationSummary>> listConversations({
    int? limit,
    int offset = 0,
    String? searchQuery,
  }) async {
    final dir = Directory(_sessionsDir);
    if (!await dir.exists()) return [];

    final summaries = <ConversationSummary>[];

    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final summaryFile = File(p.join(entity.path, 'summary.json'));
        if (await summaryFile.exists()) {
          try {
            final content = await summaryFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;
            final summary = ConversationSummary.fromJson(json);

            // Apply search filter
            if (searchQuery != null && searchQuery.isNotEmpty) {
              final q = searchQuery.toLowerCase();
              if (!(summary.title?.toLowerCase().contains(q) ?? false) &&
                  !(summary.lastUserMessage?.toLowerCase().contains(q) ??
                      false)) {
                continue;
              }
            }

            summaries.add(summary);
          } catch (_) {
            // Skip corrupted summaries
          }
        }
      }
    }

    // Sort by last active time, newest first
    summaries.sort((a, b) => b.lastActiveAt.compareTo(a.lastActiveAt));

    // Apply pagination
    final start = offset.clamp(0, summaries.length);
    final end = limit != null
        ? (start + limit).clamp(0, summaries.length)
        : summaries.length;

    return summaries.sublist(start, end);
  }

  /// Save conversation state.
  Future<void> saveConversation({
    required String sessionId,
    required List<Map<String, dynamic>> messages,
    required String model,
    required List<ConversationTurn> turns,
    String? title,
  }) async {
    final sessionDir = Directory(p.join(_sessionsDir, sessionId));
    await sessionDir.create(recursive: true);

    // Save full messages
    final messagesFile = File(p.join(sessionDir.path, 'messages.jsonl'));
    final sink = messagesFile.openWrite();
    for (final msg in messages) {
      sink.writeln(jsonEncode(msg));
    }
    await sink.close();

    // Save summary
    final summary = ConversationSummary(
      sessionId: sessionId,
      title: title ?? _generateTitle(messages),
      startedAt: turns.isNotEmpty
          ? DateTime.now().subtract(
              turns.fold(Duration.zero, (sum, t) => sum + t.duration),
            )
          : DateTime.now(),
      lastActiveAt: DateTime.now(),
      messageCount: messages.length,
      turnCount: turns.length,
      model: model,
      totalInputTokens: turns.fold(0, (sum, t) => sum + t.inputTokens),
      totalOutputTokens: turns.fold(0, (sum, t) => sum + t.outputTokens),
      totalCost: turns.fold(0.0, (sum, t) => sum + t.cost),
      toolsUsed: turns
          .expand((t) => t.toolExecutions.map((e) => e.toolName))
          .toSet()
          .toList(),
      lastUserMessage: _extractLastUserMessage(messages),
      lastAssistantMessage: _extractLastAssistantMessage(messages),
    );

    final summaryFile = File(p.join(sessionDir.path, 'summary.json'));
    await summaryFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(summary.toJson()),
    );
  }

  /// Load a conversation by session ID.
  Future<List<Map<String, dynamic>>?> loadConversation(String sessionId) async {
    final messagesFile = File(
      p.join(_sessionsDir, sessionId, 'messages.jsonl'),
    );
    if (!await messagesFile.exists()) return null;

    final messages = <Map<String, dynamic>>[];
    final lines = await messagesFile.readAsLines();
    for (final line in lines) {
      if (line.trim().isNotEmpty) {
        messages.add(jsonDecode(line) as Map<String, dynamic>);
      }
    }
    return messages;
  }

  /// Delete a conversation.
  Future<bool> deleteConversation(String sessionId) async {
    final sessionDir = Directory(p.join(_sessionsDir, sessionId));
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
      return true;
    }
    return false;
  }

  /// Fork a conversation at a specific message index.
  Future<String> forkConversation({
    required String parentSessionId,
    required int atMessageIndex,
    String? reason,
  }) async {
    final messages = await loadConversation(parentSessionId);
    if (messages == null || atMessageIndex >= messages.length) {
      throw ArgumentError('Invalid message index or session not found.');
    }

    // Create new session with messages up to the fork point
    final forkId = 'fork-${DateTime.now().millisecondsSinceEpoch}';
    final forkedMessages = messages.sublist(0, atMessageIndex + 1);

    await saveConversation(
      sessionId: forkId,
      messages: forkedMessages,
      model: 'unknown',
      turns: [],
      title: 'Fork of $parentSessionId',
    );

    // Save fork metadata
    final forkPoint = ForkPoint(
      parentSessionId: parentSessionId,
      messageIndex: atMessageIndex,
      forkSessionId: forkId,
      forkedAt: DateTime.now(),
      reason: reason,
    );
    final forkFile = File(p.join(_sessionsDir, forkId, 'fork.json'));
    await forkFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(forkPoint.toJson()),
    );

    return forkId;
  }

  /// Export a conversation to a given format.
  Future<String> exportConversation(
    String sessionId, {
    ExportFormat format = ExportFormat.markdown,
  }) async {
    final messages = await loadConversation(sessionId);
    if (messages == null) return 'Session not found.';

    switch (format) {
      case ExportFormat.markdown:
        return _exportAsMarkdown(messages, sessionId);
      case ExportFormat.json:
        return const JsonEncoder.withIndent('  ').convert(messages);
      case ExportFormat.html:
        return _exportAsHtml(messages, sessionId);
      case ExportFormat.plainText:
        return _exportAsPlainText(messages);
    }
  }

  /// Get aggregate stats across all conversations.
  Future<ConversationStats> getStats() async {
    final conversations = await listConversations();

    final toolCounts = <String, int>{};
    final modelCounts = <String, int>{};

    for (final conv in conversations) {
      for (final tool in conv.toolsUsed) {
        toolCounts[tool] = (toolCounts[tool] ?? 0) + 1;
      }
      modelCounts[conv.model] = (modelCounts[conv.model] ?? 0) + 1;
    }

    final totalMessages = conversations.fold(
      0,
      (sum, c) => sum + c.messageCount,
    );
    final totalCost = conversations.fold(0.0, (sum, c) => sum + c.totalCost);

    return ConversationStats(
      totalSessions: conversations.length,
      totalMessages: totalMessages,
      totalTokens: conversations.fold(
        0,
        (sum, c) => sum + c.totalInputTokens + c.totalOutputTokens,
      ),
      totalCost: totalCost,
      totalDuration: conversations.fold(
        Duration.zero,
        (sum, c) => sum + c.lastActiveAt.difference(c.startedAt),
      ),
      toolUsageCounts: toolCounts,
      modelUsageCounts: modelCounts,
      averageMessagesPerSession: conversations.isEmpty
          ? 0
          : totalMessages ~/ conversations.length,
      averageCostPerSession: conversations.isEmpty
          ? 0.0
          : totalCost / conversations.length,
    );
  }

  // ─── Private helpers ───

  String _generateTitle(List<Map<String, dynamic>> messages) {
    // Use first user message as title
    for (final msg in messages) {
      if (msg['role'] == 'user') {
        final content = msg['content'];
        String? text;
        if (content is String) {
          text = content;
        } else if (content is List) {
          text = content
              .whereType<Map<String, dynamic>>()
              .where((c) => c['type'] == 'text')
              .map((c) => c['text'] as String?)
              .whereType<String>()
              .firstOrNull;
        }
        if (text != null) {
          // Take first 60 chars
          return text.length > 60 ? '${text.substring(0, 57)}...' : text;
        }
      }
    }
    return 'Untitled conversation';
  }

  String? _extractLastUserMessage(List<Map<String, dynamic>> messages) {
    for (final msg in messages.reversed) {
      if (msg['role'] == 'user') {
        final content = msg['content'];
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map<String, dynamic>>()
              .where((c) => c['type'] == 'text')
              .map((c) => c['text'] as String?)
              .whereType<String>()
              .firstOrNull;
        }
      }
    }
    return null;
  }

  String? _extractLastAssistantMessage(List<Map<String, dynamic>> messages) {
    for (final msg in messages.reversed) {
      if (msg['role'] == 'assistant') {
        final content = msg['content'];
        if (content is String) return content;
        if (content is List) {
          return content
              .whereType<Map<String, dynamic>>()
              .where((c) => c['type'] == 'text')
              .map((c) => c['text'] as String?)
              .whereType<String>()
              .firstOrNull;
        }
      }
    }
    return null;
  }

  String _exportAsMarkdown(
    List<Map<String, dynamic>> messages,
    String sessionId,
  ) {
    final buffer = StringBuffer();
    buffer.writeln('# Conversation $sessionId');
    buffer.writeln();
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('---');
    buffer.writeln();

    for (final msg in messages) {
      final role = msg['role'] as String? ?? 'unknown';
      final icon = role == 'user' ? 'Human' : 'Assistant';
      buffer.writeln('## $icon');
      buffer.writeln();

      final content = msg['content'];
      if (content is String) {
        buffer.writeln(content);
      } else if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic>) {
            switch (block['type']) {
              case 'text':
                buffer.writeln(block['text']);
                break;
              case 'tool_use':
                buffer.writeln(
                  '**Tool call**: `${block['name']}` (${block['id']})',
                );
                buffer.writeln('```json');
                buffer.writeln(
                  const JsonEncoder.withIndent('  ').convert(block['input']),
                );
                buffer.writeln('```');
                break;
              case 'tool_result':
                buffer.writeln('**Tool result** (${block['tool_use_id']}):');
                buffer.writeln('```');
                buffer.writeln(block['content']);
                buffer.writeln('```');
                break;
            }
          }
        }
      }
      buffer.writeln();
      buffer.writeln('---');
      buffer.writeln();
    }

    return buffer.toString();
  }

  String _exportAsHtml(List<Map<String, dynamic>> messages, String sessionId) {
    final buffer = StringBuffer();
    buffer.writeln('<!DOCTYPE html>');
    buffer.writeln('<html><head><meta charset="utf-8">');
    buffer.writeln('<title>Conversation $sessionId</title>');
    buffer.writeln('<style>');
    buffer.writeln(
      'body { font-family: system-ui; max-width: 800px; margin: auto; padding: 20px; }',
    );
    buffer.writeln(
      '.message { margin: 16px 0; padding: 12px; border-radius: 8px; }',
    );
    buffer.writeln('.user { background: #e3f2fd; }');
    buffer.writeln('.assistant { background: #f3e5f5; }');
    buffer.writeln('.role { font-weight: bold; margin-bottom: 8px; }');
    buffer.writeln(
      'pre { background: #f5f5f5; padding: 12px; border-radius: 4px; overflow-x: auto; }',
    );
    buffer.writeln('</style></head><body>');
    buffer.writeln('<h1>Conversation $sessionId</h1>');

    for (final msg in messages) {
      final role = msg['role'] as String? ?? 'unknown';
      buffer.writeln('<div class="message $role">');
      buffer.writeln(
        '<div class="role">${role == 'user' ? 'Human' : 'Assistant'}</div>',
      );

      final content = msg['content'];
      if (content is String) {
        buffer.writeln('<p>${_escapeHtml(content)}</p>');
      } else if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            buffer.writeln(
              '<p>${_escapeHtml(block['text'] as String? ?? '')}</p>',
            );
          }
        }
      }

      buffer.writeln('</div>');
    }

    buffer.writeln('</body></html>');
    return buffer.toString();
  }

  String _exportAsPlainText(List<Map<String, dynamic>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] as String? ?? 'unknown';
      buffer.writeln('[$role]');

      final content = msg['content'];
      if (content is String) {
        buffer.writeln(content);
      } else if (content is List) {
        for (final block in content) {
          if (block is Map<String, dynamic> && block['type'] == 'text') {
            buffer.writeln(block['text']);
          }
        }
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }
}
