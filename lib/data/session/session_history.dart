// Session history — port of neomage/src/assistant/sessionHistory.ts.
// Persistence and resume for conversation sessions.

import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import '../../domain/models/message.dart';

/// A serialized session that can be stored and restored.
class SessionSnapshot {
  final String sessionId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Message> messages;
  final Map<String, dynamic> metadata;

  const SessionSnapshot({
    required this.sessionId,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    this.metadata = const {},
  });

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'messages': messages.map((m) => _messageToJson(m)).toList(),
    'metadata': metadata,
  };

  factory SessionSnapshot.fromJson(Map<String, dynamic> json) {
    return SessionSnapshot(
      sessionId: json['sessionId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      messages: (json['messages'] as List)
          .map((m) => _messageFromJson(m as Map<String, dynamic>))
          .toList(),
      metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

/// Session history manager — saves and loads conversation transcripts.
class SessionHistoryManager {
  final String baseDir;

  SessionHistoryManager({required this.baseDir});

  /// Save a session snapshot to disk.
  Future<void> saveSession(SessionSnapshot snapshot) async {
    final file = File(_sessionPath(snapshot.sessionId));
    await file.parent.create(recursive: true);
    final json = jsonEncode(snapshot.toJson());
    await file.writeAsString(json);
  }

  /// Load a session snapshot from disk.
  Future<SessionSnapshot?> loadSession(String sessionId) async {
    final file = File(_sessionPath(sessionId));
    if (!await file.exists()) return null;

    try {
      final json = jsonDecode(await file.readAsString());
      return SessionSnapshot.fromJson(json as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// List all saved session IDs, newest first.
  Future<List<String>> listSessions() async {
    final dir = Directory(baseDir);
    if (!await dir.exists()) return const [];

    final sessions = <_SessionEntry>[];

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      if (!entity.path.endsWith('.json')) continue;

      final name = entity.path.split('/').last;
      final sessionId = name.replaceAll('.json', '');
      final stat = await entity.stat();
      sessions.add(_SessionEntry(sessionId, stat.modified));
    }

    sessions.sort((a, b) => b.modified.compareTo(a.modified));
    return sessions.map((s) => s.id).toList();
  }

  /// Delete a session.
  Future<bool> deleteSession(String sessionId) async {
    final file = File(_sessionPath(sessionId));
    if (await file.exists()) {
      await file.delete();
      return true;
    }
    return false;
  }

  /// Get the most recent session ID, if any.
  Future<String?> getMostRecentSession() async {
    final sessions = await listSessions();
    return sessions.isNotEmpty ? sessions.first : null;
  }

  String _sessionPath(String sessionId) => '$baseDir/$sessionId.json';
}

class _SessionEntry {
  final String id;
  final DateTime modified;
  _SessionEntry(this.id, this.modified);
}

// ── Serialization helpers ──

Map<String, dynamic> _messageToJson(Message m) => {
  'id': m.id,
  'role': m.role.name,
  'content': m.content.map(_blockToJson).toList(),
  'timestamp': m.timestamp.toIso8601String(),
  if (m.stopReason != null) 'stopReason': m.stopReason!.name,
  if (m.usage != null)
    'usage': {
      'input_tokens': m.usage!.inputTokens,
      'output_tokens': m.usage!.outputTokens,
    },
};

Map<String, dynamic> _blockToJson(ContentBlock block) => switch (block) {
  TextBlock(text: final t) => {'type': 'text', 'text': t},
  ToolUseBlock(id: final id, name: final n, input: final i) => {
    'type': 'tool_use',
    'id': id,
    'name': n,
    'input': i,
  },
  ToolResultBlock(toolUseId: final tid, content: final c, isError: final e) => {
    'type': 'tool_result',
    'tool_use_id': tid,
    'content': c,
    if (e) 'is_error': true,
  },
  ImageBlock(mediaType: final m, base64Data: final d) => {
    'type': 'image',
    'media_type': m,
    'data': d,
  },
};

Message _messageFromJson(Map<String, dynamic> json) {
  final role = switch (json['role'] as String) {
    'assistant' => MessageRole.assistant,
    'system' => MessageRole.system,
    _ => MessageRole.user,
  };

  final content = (json['content'] as List)
      .map((b) => _blockFromJson(b as Map<String, dynamic>))
      .toList();

  final stopReason = json['stopReason'] != null
      ? StopReason.values.firstWhere(
          (s) => s.name == json['stopReason'],
          orElse: () => StopReason.endTurn,
        )
      : null;

  TokenUsage? usage;
  if (json['usage'] is Map) {
    usage = TokenUsage.fromJson(json['usage'] as Map<String, dynamic>);
  }

  return Message(
    id: json['id'] as String?,
    role: role,
    content: content,
    timestamp: json['timestamp'] != null
        ? DateTime.tryParse(json['timestamp'] as String)
        : null,
    stopReason: stopReason,
    usage: usage,
  );
}

ContentBlock _blockFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  return switch (type) {
    'text' => TextBlock(json['text'] as String),
    'tool_use' => ToolUseBlock(
      id: json['id'] as String,
      name: json['name'] as String,
      input: json['input'] as Map<String, dynamic>,
    ),
    'tool_result' => ToolResultBlock(
      toolUseId: json['tool_use_id'] as String,
      content: json['content'] as String,
      isError: json['is_error'] as bool? ?? false,
    ),
    'image' => ImageBlock(
      mediaType: json['media_type'] as String,
      base64Data: json['data'] as String,
    ),
    _ => TextBlock('[Unknown block type: $type]'),
  };
}
