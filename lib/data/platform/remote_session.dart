// Remote session service — port of neomage headless/remote mode.
// Enables API-driven sessions without UI (CI/CD, teammate, automation).

import 'dart:async';
import 'dart:convert';

import '../../domain/models/message.dart';
import '../engine/query_engine.dart';

/// Remote session status.
enum RemoteSessionStatus {
  idle,
  processing,
  waitingPermission,
  error,
  completed,
}

/// A permission request from the remote session.
class RemotePermissionRequest {
  final String id;
  final String toolName;
  final Map<String, dynamic> toolInput;
  final DateTime requestedAt;
  final Completer<bool> _completer;

  RemotePermissionRequest({
    required this.id,
    required this.toolName,
    required this.toolInput,
  }) : requestedAt = DateTime.now(),
       _completer = Completer<bool>();

  Future<bool> get response => _completer.future;

  void approve() {
    if (!_completer.isCompleted) _completer.complete(true);
  }

  void deny() {
    if (!_completer.isCompleted) _completer.complete(false);
  }
}

/// Remote session event for streaming updates.
sealed class RemoteSessionEvent {
  final DateTime timestamp;
  RemoteSessionEvent() : timestamp = DateTime.now();
}

class MessageAddedEvent extends RemoteSessionEvent {
  final Message message;
  MessageAddedEvent(this.message);
}

class StatusChangedEvent extends RemoteSessionEvent {
  final RemoteSessionStatus status;
  StatusChangedEvent(this.status);
}

class ToolExecutionEvent extends RemoteSessionEvent {
  final String toolName;
  final Map<String, dynamic> input;
  final String? output;
  final bool isError;

  ToolExecutionEvent({
    required this.toolName,
    required this.input,
    this.output,
    this.isError = false,
  });
}

class PermissionRequestEvent extends RemoteSessionEvent {
  final RemotePermissionRequest request;
  PermissionRequestEvent(this.request);
}

class ErrorEvent extends RemoteSessionEvent {
  final String message;
  final String? code;
  ErrorEvent(this.message, {this.code});
}

class CompletionEvent extends RemoteSessionEvent {
  final int totalTokens;
  final int toolCalls;
  final Duration elapsed;

  CompletionEvent({
    required this.totalTokens,
    required this.toolCalls,
    required this.elapsed,
  });
}

/// Remote session — headless AI session driven by API calls.
class RemoteSession {
  final String id;
  final QueryEngine _engine;
  final StreamController<RemoteSessionEvent> _events =
      StreamController.broadcast();
  final List<Message> _messages = [];
  final List<RemotePermissionRequest> _pendingPermissions = [];

  RemoteSessionStatus _status = RemoteSessionStatus.idle;
  DateTime? _startedAt;
  int _totalTokens = 0;
  int _toolCalls = 0;

  RemoteSession({required this.id, required QueryEngine engine})
    : _engine = engine;

  /// Event stream for real-time updates.
  Stream<RemoteSessionEvent> get events => _events.stream;

  /// Current status.
  RemoteSessionStatus get status => _status;

  /// All messages in the session.
  List<Message> get messages => List.unmodifiable(_messages);

  /// Pending permission requests.
  List<RemotePermissionRequest> get pendingPermissions =>
      List.unmodifiable(_pendingPermissions);

  /// Total tokens used.
  int get totalTokens => _totalTokens;

  /// Total tool calls made.
  int get toolCalls => _toolCalls;

  /// Submit a user message and process the response.
  Future<Message> submit(String prompt) async {
    if (_status == RemoteSessionStatus.processing) {
      throw StateError('Session is already processing a request');
    }

    _startedAt = DateTime.now();
    _setStatus(RemoteSessionStatus.processing);

    final userMessage = Message.user(prompt);
    _addMessage(userMessage);

    try {
      final response = await _engine.query(
        messages: _messages,
        onPermissionRequest: _handlePermissionRequest,
      );

      _addMessage(response);
      _totalTokens += _estimateTokens(response);
      _setStatus(RemoteSessionStatus.idle);

      _events.add(
        CompletionEvent(
          totalTokens: _totalTokens,
          toolCalls: _toolCalls,
          elapsed: DateTime.now().difference(_startedAt!),
        ),
      );

      return response;
    } catch (e) {
      _setStatus(RemoteSessionStatus.error);
      _events.add(ErrorEvent(e.toString()));
      rethrow;
    }
  }

  /// Respond to a permission request.
  void respondToPermission(String requestId, bool approved) {
    final request = _pendingPermissions.firstWhere(
      (r) => r.id == requestId,
      orElse: () =>
          throw ArgumentError('Unknown permission request: $requestId'),
    );

    if (approved) {
      request.approve();
    } else {
      request.deny();
    }
    _pendingPermissions.removeWhere((r) => r.id == requestId);

    if (_pendingPermissions.isEmpty &&
        _status == RemoteSessionStatus.waitingPermission) {
      _setStatus(RemoteSessionStatus.processing);
    }
  }

  /// Cancel the current operation.
  void cancel() {
    for (final request in _pendingPermissions) {
      request.deny();
    }
    _pendingPermissions.clear();
    _setStatus(RemoteSessionStatus.idle);
  }

  /// Serialize session state for persistence.
  Map<String, dynamic> toJson() => {
    'id': id,
    'status': _status.name,
    'totalTokens': _totalTokens,
    'toolCalls': _toolCalls,
    'messageCount': _messages.length,
    'startedAt': _startedAt?.toIso8601String(),
  };

  /// Dispose resources.
  void dispose() {
    cancel();
    _events.close();
  }

  // ── Private ──

  void _setStatus(RemoteSessionStatus newStatus) {
    _status = newStatus;
    _events.add(StatusChangedEvent(newStatus));
  }

  void _addMessage(Message message) {
    _messages.add(message);
    _events.add(MessageAddedEvent(message));
  }

  Future<bool> _handlePermissionRequest(
    String toolName,
    Map<String, dynamic> input,
    Object? explanation,
  ) async {
    _toolCalls++;
    final request = RemotePermissionRequest(
      id: 'perm_${_toolCalls}_${DateTime.now().millisecondsSinceEpoch}',
      toolName: toolName,
      toolInput: input,
    );

    _pendingPermissions.add(request);
    _setStatus(RemoteSessionStatus.waitingPermission);
    _events.add(PermissionRequestEvent(request));

    return request.response;
  }

  int _estimateTokens(Message message) {
    var chars = 0;
    for (final block in message.content) {
      switch (block) {
        case TextBlock(text: final t):
          chars += t.length;
        case ToolUseBlock(input: final input):
          chars += jsonEncode(input).length;
        case ToolResultBlock(content: final c):
          chars += c.length;
        case ImageBlock():
          chars += 1000; // Rough estimate
      }
    }
    return (chars / 4).ceil(); // ~4 chars per token
  }
}

/// Remote session manager — creates and tracks multiple sessions.
class RemoteSessionManager {
  final Map<String, RemoteSession> _sessions = {};
  final QueryEngine Function() _engineFactory;

  RemoteSessionManager({required QueryEngine Function() engineFactory})
    : _engineFactory = engineFactory;

  /// Create a new session.
  RemoteSession createSession({String? id}) {
    final sessionId = id ?? 'session_${DateTime.now().millisecondsSinceEpoch}';
    final session = RemoteSession(id: sessionId, engine: _engineFactory());
    _sessions[sessionId] = session;
    return session;
  }

  /// Get an existing session.
  RemoteSession? getSession(String id) => _sessions[id];

  /// All active sessions.
  List<RemoteSession> get activeSessions => _sessions.values.toList();

  /// Remove a session.
  void removeSession(String id) {
    _sessions.remove(id)?.dispose();
  }

  /// Dispose all sessions.
  void disposeAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
