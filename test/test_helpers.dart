/// Test infrastructure stubs for Neom Claw.
///
/// Provides mocks, fixtures, custom matchers, and utility helpers that make
/// it easy to write isolated unit and widget tests without depending on real
/// services, file systems, or network connections.
library;

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Common domain types (lightweight stubs so the test helpers compile
// standalone — in production these would be imported from the real models).
// ---------------------------------------------------------------------------

/// Represents a single message in a conversation.
class Message {
  const Message({
    required this.id,
    required this.role,
    required this.content,
    this.toolUse,
    this.toolResult,
    this.timestamp,
  });

  final String id;
  final String role; // 'user', 'assistant', 'system'
  final String content;
  final ToolUse? toolUse;
  final ToolResult? toolResult;
  final DateTime? timestamp;

  Map<String, dynamic> toMap() => {
    'id': id,
    'role': role,
    'content': content,
    if (toolUse != null) 'toolUse': toolUse!.toMap(),
    if (toolResult != null) 'toolResult': toolResult!.toMap(),
    'timestamp': (timestamp ?? DateTime.now()).toIso8601String(),
  };
}

/// A request to invoke a tool.
class ToolUse {
  const ToolUse({required this.id, required this.name, this.input = const {}});
  final String id;
  final String name;
  final Map<String, dynamic> input;
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'input': input};
}

/// The result returned from a tool invocation.
class ToolResult {
  const ToolResult({
    required this.toolUseId,
    required this.output,
    this.isError = false,
  });
  final String toolUseId;
  final String output;
  final bool isError;
  Map<String, dynamic> toMap() => {
    'toolUseId': toolUseId,
    'output': output,
    'isError': isError,
  };
}

/// A streaming event emitted by the conversation engine.
class StreamUpdate {
  const StreamUpdate({required this.type, this.text, this.toolUse, this.usage});
  final String type; // 'text_delta', 'tool_use', 'message_stop', 'error'
  final String? text;
  final ToolUse? toolUse;
  final Map<String, int>? usage;
  Map<String, dynamic> toMap() => {
    'type': type,
    if (text != null) 'text': text,
    if (toolUse != null) 'toolUse': toolUse!.toMap(),
    if (usage != null) 'usage': usage,
  };
}

/// Permission request metadata.
class PermissionRequest {
  const PermissionRequest({
    required this.tool,
    required this.input,
    this.riskLevel = 'low',
  });
  final String tool;
  final Map<String, dynamic> input;
  final String riskLevel;
}

/// Basic MCP server descriptor.
class McpServer {
  const McpServer({
    required this.name,
    required this.url,
    this.tools = const [],
  });
  final String name;
  final String url;
  final List<String> tools;
}

/// Minimal project descriptor.
class Project {
  const Project({required this.name, required this.root, this.language});
  final String name;
  final String root;
  final String? language;
}

/// A unified diff.
class Diff {
  const Diff({required this.path, required this.hunks});
  final String path;
  final String hunks;
}

/// Status bar data model.
class StatusBarData {
  const StatusBarData({
    this.model = '',
    this.tokensUsed = 0,
    this.tokensLimit = 0,
    this.latencyMs = 0,
    this.isStreaming = false,
  });
  final String model;
  final int tokensUsed;
  final int tokensLimit;
  final int latencyMs;
  final bool isStreaming;
}

// ---------------------------------------------------------------------------
// MockApiProvider
// ---------------------------------------------------------------------------

/// A mock API provider that returns configurable responses without hitting the
/// real Anthropic API.
///
/// Use [enqueue] to push responses onto an internal queue; calls to [complete]
/// or [stream] will pop them in FIFO order.
class MockApiProvider {
  final List<Message> _responseQueue = [];
  final List<List<StreamUpdate>> _streamQueue = [];
  final List<Map<String, dynamic>> _requests = [];

  /// Number of requests received.
  int get requestCount => _requests.length;

  /// All requests captured so far.
  List<Map<String, dynamic>> get requests => List.unmodifiable(_requests);

  /// Enqueue a plain [Message] response.
  void enqueue(Message response) => _responseQueue.add(response);

  /// Enqueue a list of [StreamUpdate]s for streaming responses.
  void enqueueStream(List<StreamUpdate> events) => _streamQueue.add(events);

  /// Simulate a non-streaming completion. Returns the next queued response or
  /// a default assistant message.
  Future<Message> complete(
    List<Message> messages, {
    Map<String, dynamic>? params,
  }) async {
    _requests.add({
      'messages': messages.map((m) => m.toMap()).toList(),
      ...?params,
    });
    if (_responseQueue.isNotEmpty) return _responseQueue.removeAt(0);
    return Message(
      id: 'mock-${DateTime.now().millisecondsSinceEpoch}',
      role: 'assistant',
      content: 'Mock response',
      timestamp: DateTime.now(),
    );
  }

  /// Simulate a streaming completion. Yields queued [StreamUpdate]s or a
  /// single text delta followed by a stop event.
  Stream<StreamUpdate> stream(
    List<Message> messages, {
    Map<String, dynamic>? params,
  }) async* {
    _requests.add({
      'messages': messages.map((m) => m.toMap()).toList(),
      ...?params,
    });
    if (_streamQueue.isNotEmpty) {
      for (final event in _streamQueue.removeAt(0)) {
        yield event;
      }
      return;
    }
    yield const StreamUpdate(
      type: 'text_delta',
      text: 'Mock streamed response',
    );
    yield const StreamUpdate(
      type: 'message_stop',
      usage: {'input_tokens': 10, 'output_tokens': 5},
    );
  }

  /// Clear queues and request history.
  void reset() {
    _responseQueue.clear();
    _streamQueue.clear();
    _requests.clear();
  }
}

// ---------------------------------------------------------------------------
// MockToolRegistry
// ---------------------------------------------------------------------------

/// Holds mock tool implementations keyed by tool name.
class MockToolRegistry {
  final Map<String, Future<ToolResult> Function(Map<String, dynamic> input)>
  _tools = {};

  /// Register a mock tool handler.
  void register(
    String name,
    Future<ToolResult> Function(Map<String, dynamic> input) handler,
  ) {
    _tools[name] = handler;
  }

  /// Register a tool that always returns a fixed output.
  void registerFixed(String name, String output) {
    _tools[name] = (_) async =>
        ToolResult(toolUseId: 'tu-$name', output: output);
  }

  /// Register a tool that always fails with [error].
  void registerFailing(String name, String error) {
    _tools[name] = (_) async =>
        ToolResult(toolUseId: 'tu-$name', output: error, isError: true);
  }

  /// Invoke a registered mock tool. Throws if not registered.
  Future<ToolResult> invoke(String name, Map<String, dynamic> input) async {
    final handler = _tools[name];
    if (handler == null)
      throw StateError('No mock tool registered for "$name"');
    return handler(input);
  }

  /// Whether [name] has a registered mock handler.
  bool has(String name) => _tools.containsKey(name);

  /// All registered tool names.
  List<String> get registeredTools => _tools.keys.toList();

  void reset() => _tools.clear();
}

// ---------------------------------------------------------------------------
// MockConversationEngine
// ---------------------------------------------------------------------------

/// A conversation engine mock that supports replaying a fixed sequence of
/// assistant responses.
class MockConversationEngine {
  MockConversationEngine({List<Message>? replayMessages})
    : _replay = replayMessages ?? [];

  final List<Message> _replay;
  final List<Message> _history = [];
  int _replayIndex = 0;

  /// All messages sent and received so far.
  List<Message> get history => List.unmodifiable(_history);

  /// Send a user message and get the next replayed assistant message.
  Future<Message> send(String text) async {
    final userMsg = Message(
      id: 'user-${_history.length}',
      role: 'user',
      content: text,
      timestamp: DateTime.now(),
    );
    _history.add(userMsg);

    Message response;
    if (_replayIndex < _replay.length) {
      response = _replay[_replayIndex++];
    } else {
      response = Message(
        id: 'assistant-${_history.length}',
        role: 'assistant',
        content: 'Mock reply to: $text',
        timestamp: DateTime.now(),
      );
    }
    _history.add(response);
    return response;
  }

  /// Stream the next replayed response as character-level text deltas.
  Stream<StreamUpdate> sendStreaming(String text) async* {
    final response = await send(text);
    for (var i = 0; i < response.content.length; i++) {
      yield StreamUpdate(type: 'text_delta', text: response.content[i]);
    }
    yield const StreamUpdate(
      type: 'message_stop',
      usage: {'input_tokens': 10, 'output_tokens': 5},
    );
  }

  void reset() {
    _history.clear();
    _replayIndex = 0;
  }
}

// ---------------------------------------------------------------------------
// MockSessionService
// ---------------------------------------------------------------------------

/// In-memory session storage.
class MockSessionService {
  final Map<String, List<Message>> _sessions = {};
  String? _activeSessionId;

  String get activeSessionId => _activeSessionId ?? 'default';

  /// Create a new session and return its ID.
  String createSession({String? id}) {
    final sid = id ?? 'session-${_sessions.length}';
    _sessions[sid] = [];
    _activeSessionId = sid;
    return sid;
  }

  /// Add a message to the active session.
  void addMessage(Message message) {
    _sessions.putIfAbsent(activeSessionId, () => []);
    _sessions[activeSessionId]!.add(message);
  }

  /// Retrieve all messages for a session.
  List<Message> getMessages({String? sessionId}) {
    return List.unmodifiable(_sessions[sessionId ?? activeSessionId] ?? []);
  }

  /// List all session IDs.
  List<String> listSessions() => _sessions.keys.toList();

  /// Delete a session.
  void deleteSession(String id) {
    _sessions.remove(id);
    if (_activeSessionId == id) _activeSessionId = null;
  }

  void reset() {
    _sessions.clear();
    _activeSessionId = null;
  }
}

// ---------------------------------------------------------------------------
// MockGitService
// ---------------------------------------------------------------------------

/// Mock git operations with preset responses.
class MockGitService {
  String statusOutput = 'On branch main\nnothing to commit, working tree clean';
  List<String> logEntries = [
    'abc1234 feat: initial commit',
    'def5678 fix: resolve issue #1',
  ];
  String diffOutput = '';
  String currentBranch = 'main';
  bool isRepo = true;

  Future<String> status() async => statusOutput;

  Future<List<String>> log({int count = 10}) async =>
      logEntries.take(count).toList();

  Future<String> diff({String? ref}) async => diffOutput;

  Future<String> branch() async => currentBranch;

  Future<bool> isGitRepository() async => isRepo;

  /// Simulate a commit — just returns a fake hash.
  Future<String> commit(String message) async =>
      'aaa${DateTime.now().millisecondsSinceEpoch.toRadixString(16)}';

  void reset() {
    statusOutput = 'On branch main\nnothing to commit, working tree clean';
    logEntries = ['abc1234 feat: initial commit'];
    diffOutput = '';
    currentBranch = 'main';
    isRepo = true;
  }
}

// ---------------------------------------------------------------------------
// MockFileSystem
// ---------------------------------------------------------------------------

/// In-memory file system for deterministic testing.
class MockFileSystem {
  final Map<String, String> _files = {};
  final Set<String> _directories = {};

  /// Create (or overwrite) a file with [content].
  void writeFile(String path, String content) {
    _files[path] = content;
    // Ensure parent directories exist.
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      _directories.add(parts.sublist(0, i).join('/'));
    }
  }

  /// Read a file's content, or `null` if it does not exist.
  String? readFile(String path) => _files[path];

  /// Whether the path exists as a file.
  bool fileExists(String path) => _files.containsKey(path);

  /// Whether the path exists as a directory.
  bool directoryExists(String path) => _directories.contains(path);

  /// Delete a file.
  void deleteFile(String path) => _files.remove(path);

  /// Create a directory (and parents).
  void createDirectory(String path) {
    _directories.add(path);
    final parts = path.split('/');
    for (var i = 1; i < parts.length; i++) {
      _directories.add(parts.sublist(0, i).join('/'));
    }
  }

  /// List files directly under [directory].
  List<String> listDirectory(String directory) {
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    return _files.keys
        .where(
          (p) =>
              p.startsWith(prefix) && !p.substring(prefix.length).contains('/'),
        )
        .toList();
  }

  /// List files recursively under [directory].
  List<String> listRecursive(String directory) {
    final prefix = directory.endsWith('/') ? directory : '$directory/';
    return _files.keys.where((p) => p.startsWith(prefix)).toList();
  }

  /// Total number of files stored.
  int get fileCount => _files.length;

  void reset() {
    _files.clear();
    _directories.clear();
  }
}

// ---------------------------------------------------------------------------
// TestFixtures
// ---------------------------------------------------------------------------

/// Factory methods that produce commonly needed domain objects for tests.
class TestFixtures {
  TestFixtures._();

  static int _counter = 0;
  static String _nextId(String prefix) => '$prefix-${_counter++}';

  /// A simple user message.
  static Message sampleMessage({String? content, String? id}) {
    return Message(
      id: id ?? _nextId('msg'),
      role: 'user',
      content: content ?? 'Hello, NeomClaw.',
      timestamp: DateTime(2026, 1, 15, 10, 30),
    );
  }

  /// An assistant text response.
  static Message sampleAssistantMessage({String? content, String? id}) {
    return Message(
      id: id ?? _nextId('asst'),
      role: 'assistant',
      content: content ?? 'Hello! How can I help you today?',
      timestamp: DateTime(2026, 1, 15, 10, 30, 5),
    );
  }

  /// An assistant message containing a tool use block.
  static Message sampleToolUseMessage({
    String toolName = 'bash',
    Map<String, dynamic>? input,
    String? id,
  }) {
    return Message(
      id: id ?? _nextId('tool'),
      role: 'assistant',
      content: '',
      toolUse: ToolUse(
        id: _nextId('tu'),
        name: toolName,
        input: input ?? {'command': 'ls -la'},
      ),
      timestamp: DateTime(2026, 1, 15, 10, 31),
    );
  }

  /// Generate a multi-turn conversation with [turns] user/assistant pairs.
  static List<Message> sampleConversation({int turns = 3}) {
    final messages = <Message>[];
    for (var i = 0; i < turns; i++) {
      messages.add(
        Message(
          id: _nextId('user'),
          role: 'user',
          content: 'User message $i',
          timestamp: DateTime(2026, 1, 15, 10, i),
        ),
      );
      messages.add(
        Message(
          id: _nextId('asst'),
          role: 'assistant',
          content: 'Assistant response to message $i',
          timestamp: DateTime(2026, 1, 15, 10, i, 30),
        ),
      );
    }
    return messages;
  }

  /// A tool result with configurable success / failure.
  static ToolResult sampleToolResult(
    String toolName, {
    bool success = true,
    String? output,
  }) {
    return ToolResult(
      toolUseId: 'tu-$toolName',
      output:
          output ??
          (success
              ? 'Tool $toolName completed successfully'
              : 'Error in $toolName'),
      isError: !success,
    );
  }

  /// A typical sequence of stream events for a text response.
  static List<StreamUpdate> sampleStreamEvents({
    String text = 'Hello from streaming!',
  }) {
    return [
      const StreamUpdate(type: 'message_start'),
      StreamUpdate(type: 'text_delta', text: text),
      const StreamUpdate(
        type: 'message_stop',
        usage: {'input_tokens': 12, 'output_tokens': 8},
      ),
    ];
  }

  /// Sample status bar data.
  static StatusBarData sampleStatusBarData() {
    return const StatusBarData(
      model: 'claude-sonnet-4-20250514',
      tokensUsed: 1500,
      tokensLimit: 200000,
      latencyMs: 320,
      isStreaming: false,
    );
  }

  /// A sample permission request for a bash command.
  static PermissionRequest samplePermissionRequest({
    String tool = 'bash',
    String? command,
    String riskLevel = 'medium',
  }) {
    return PermissionRequest(
      tool: tool,
      input: {'command': command ?? 'rm -rf /tmp/test'},
      riskLevel: riskLevel,
    );
  }

  /// A sample MCP server descriptor.
  static McpServer sampleMcpServer({String? name, String? url}) {
    return McpServer(
      name: name ?? 'test-server',
      url: url ?? 'http://localhost:3000',
      tools: ['read_file', 'write_file', 'search'],
    );
  }

  /// A sample project descriptor.
  static Project sampleProject({String? name, String? root}) {
    return Project(
      name: name ?? 'my-project',
      root: root ?? '/home/user/my-project',
      language: 'dart',
    );
  }

  /// A sample unified diff.
  static Diff sampleDiff({String? path}) {
    return Diff(
      path: path ?? 'lib/main.dart',
      hunks: '''
@@ -1,5 +1,6 @@
 import 'package:flutter/material.dart';
+import 'package:my_app/config.dart';

 void main() {
-  runApp(MyApp());
+  runApp(const MyApp());
 }
''',
    );
  }

  /// A full multi-turn conversation that exercises tool use, streaming, and
  /// multiple assistant responses — useful for integration-style golden tests.
  static List<Message> goldenConversation() {
    return [
      Message(
        id: 'g-1',
        role: 'user',
        content: 'Show me the files in the current directory.',
        timestamp: DateTime(2026, 1, 15, 9, 0),
      ),
      Message(
        id: 'g-2',
        role: 'assistant',
        content: '',
        toolUse: const ToolUse(
          id: 'tu-g-2',
          name: 'bash',
          input: {'command': 'ls -la'},
        ),
        timestamp: DateTime(2026, 1, 15, 9, 0, 2),
      ),
      Message(
        id: 'g-3',
        role: 'assistant',
        content:
            'Here are the files:\n- main.dart\n- pubspec.yaml\n- README.md',
        toolResult: const ToolResult(
          toolUseId: 'tu-g-2',
          output:
              'total 3\n-rw-r--r-- main.dart\n-rw-r--r-- pubspec.yaml\n-rw-r--r-- README.md',
        ),
        timestamp: DateTime(2026, 1, 15, 9, 0, 4),
      ),
      Message(
        id: 'g-4',
        role: 'user',
        content: 'Read main.dart for me.',
        timestamp: DateTime(2026, 1, 15, 9, 1),
      ),
      Message(
        id: 'g-5',
        role: 'assistant',
        content: '',
        toolUse: const ToolUse(
          id: 'tu-g-5',
          name: 'read_file',
          input: {'path': 'main.dart'},
        ),
        timestamp: DateTime(2026, 1, 15, 9, 1, 1),
      ),
      Message(
        id: 'g-6',
        role: 'assistant',
        content: 'The file contains a simple Flutter app entry point.',
        toolResult: const ToolResult(
          toolUseId: 'tu-g-5',
          output:
              "import 'package:flutter/material.dart';\nvoid main() => runApp(MyApp());",
        ),
        timestamp: DateTime(2026, 1, 15, 9, 1, 3),
      ),
      Message(
        id: 'g-7',
        role: 'user',
        content: 'Add a const constructor call.',
        timestamp: DateTime(2026, 1, 15, 9, 2),
      ),
      Message(
        id: 'g-8',
        role: 'assistant',
        content:
            'Done. I updated `runApp(MyApp())` to `runApp(const MyApp())`.',
        toolUse: const ToolUse(
          id: 'tu-g-8',
          name: 'edit_file',
          input: {
            'path': 'main.dart',
            'old': 'runApp(MyApp())',
            'new': 'runApp(const MyApp())',
          },
        ),
        timestamp: DateTime(2026, 1, 15, 9, 2, 2),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Custom Test Matchers
// ---------------------------------------------------------------------------

/// Custom matchers for Claw domain objects.
class TestMatchers {
  TestMatchers._();

  /// Matches any [Message] with a non-empty id, a valid role, and non-null
  /// content.
  static Matcher get isValidMessage => _IsValidMessage();

  /// Matches a [Message] that contains a [ToolUse] block.
  static Matcher get isToolUseMessage => _IsToolUseMessage();

  /// Matches a [StreamUpdate] with type `'message_stop'`.
  static Matcher get isStreamComplete => _IsStreamComplete();

  /// Matches a [Map] (or object with a `usage` field) whose input + output
  /// token count falls within [min]..[max].
  static Matcher hasTokenCount({int min = 0, int max = 999999}) =>
      _HasTokenCount(min, max);

  /// Matches a [PermissionRequest] whose tool matches [pattern].
  static Matcher matchesPermissionRule(Pattern pattern) =>
      _MatchesPermissionRule(pattern);
}

class _IsValidMessage extends Matcher {
  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Message) return false;
    if (item.id.isEmpty) return false;
    if (!{'user', 'assistant', 'system'}.contains(item.role)) return false;
    return true;
  }

  @override
  Description describe(Description description) =>
      description.add('a valid Message with non-empty id and valid role');
}

class _IsToolUseMessage extends Matcher {
  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! Message) return false;
    return item.toolUse != null;
  }

  @override
  Description describe(Description description) =>
      description.add('a Message containing a ToolUse block');
}

class _IsStreamComplete extends Matcher {
  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! StreamUpdate) return false;
    return item.type == 'message_stop';
  }

  @override
  Description describe(Description description) =>
      description.add('a StreamUpdate with type message_stop');
}

class _HasTokenCount extends Matcher {
  _HasTokenCount(this.min, this.max);
  final int min;
  final int max;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is StreamUpdate && item.usage != null) {
      final total =
          (item.usage!['input_tokens'] ?? 0) +
          (item.usage!['output_tokens'] ?? 0);
      return total >= min && total <= max;
    }
    if (item is Map) {
      final total =
          ((item['input_tokens'] as int?) ?? 0) +
          ((item['output_tokens'] as int?) ?? 0);
      return total >= min && total <= max;
    }
    return false;
  }

  @override
  Description describe(Description description) =>
      description.add('has token count between $min and $max');
}

class _MatchesPermissionRule extends Matcher {
  _MatchesPermissionRule(this.pattern);
  final Pattern pattern;

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is! PermissionRequest) return false;
    return item.tool.contains(pattern);
  }

  @override
  Description describe(Description description) =>
      description.add('PermissionRequest with tool matching $pattern');
}

// ---------------------------------------------------------------------------
// pumpClawApp
// ---------------------------------------------------------------------------

/// Helper that builds and pumps a minimal Claw application widget tree,
/// injecting service overrides for testing.
///
/// ```dart
/// await pumpClawApp(tester, overrides: {
///   'api': MockApiProvider(),
///   'session': MockSessionService(),
/// });
/// ```
Future<void> pumpClawApp(
  WidgetTester tester, {
  Map<String, Object>? overrides,
  Widget? child,
}) async {
  final effectiveOverrides = overrides ?? {};

  // Wrap in a simple MaterialApp. In a full implementation this would wire up
  // dependency injection using InheritedWidget or a service locator.
  await tester.pumpWidget(
    MaterialApp(
      home: _TestServiceScope(
        services: effectiveOverrides,
        child: child ?? const Scaffold(body: Center(child: Text('Claw Test'))),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Inherited widget used by [pumpClawApp] to expose overrides down the tree.
class _TestServiceScope extends InheritedWidget {
  const _TestServiceScope({required this.services, required super.child});

  final Map<String, Object> services;

  /// Retrieve a service override by key.
  static T? of<T>(BuildContext context, String key) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_TestServiceScope>();
    return scope?.services[key] as T?;
  }

  @override
  bool updateShouldNotify(covariant _TestServiceScope oldWidget) =>
      services != oldWidget.services;
}

// ---------------------------------------------------------------------------
// FakeProcessRunner
// ---------------------------------------------------------------------------

/// Replaces `Process.run` in tests, returning pre-configured results keyed by
/// the executable name or the full command string.
class FakeProcessRunner {
  final Map<String, FakeProcessResult> _results = {};
  final List<FakeProcessInvocation> _invocations = [];

  /// All invocations recorded so far.
  List<FakeProcessInvocation> get invocations =>
      List.unmodifiable(_invocations);

  /// Register a result for a given [executable] (or full command string).
  void register(
    String executable, {
    int exitCode = 0,
    String stdout = '',
    String stderr = '',
  }) {
    _results[executable] = FakeProcessResult(
      exitCode: exitCode,
      stdout: stdout,
      stderr: stderr,
    );
  }

  /// Simulate running a process. If no result is registered the default is
  /// exit code 0 with empty output.
  Future<FakeProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    _invocations.add(
      FakeProcessInvocation(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
      ),
    );
    final key = _results.containsKey(executable)
        ? executable
        : '$executable ${arguments.join(' ')}';
    return _results[key] ??
        const FakeProcessResult(exitCode: 0, stdout: '', stderr: '');
  }

  void reset() {
    _results.clear();
    _invocations.clear();
  }
}

/// The result of a faked process invocation.
class FakeProcessResult {
  const FakeProcessResult({
    this.exitCode = 0,
    this.stdout = '',
    this.stderr = '',
  });
  final int exitCode;
  final String stdout;
  final String stderr;
}

/// A recorded invocation from [FakeProcessRunner].
class FakeProcessInvocation {
  const FakeProcessInvocation({
    required this.executable,
    required this.arguments,
    this.workingDirectory,
  });
  final String executable;
  final List<String> arguments;
  final String? workingDirectory;

  String get fullCommand => '$executable ${arguments.join(' ')}'.trim();
}

// ---------------------------------------------------------------------------
// TestClock
// ---------------------------------------------------------------------------

/// A controllable clock for time-dependent tests.
///
/// Starts at [initialTime] (defaults to 2026-01-15 10:00 UTC) and only
/// advances when explicitly told to via [advance] or [set].
class TestClock {
  TestClock({DateTime? initialTime})
    : _now = initialTime ?? DateTime.utc(2026, 1, 15, 10, 0);

  DateTime _now;
  final _controller = StreamController<DateTime>.broadcast();

  /// The current time according to this clock.
  DateTime get now => _now;

  /// Stream that emits whenever the clock is advanced or set.
  Stream<DateTime> get onAdvance => _controller.stream;

  /// Advance the clock by [duration].
  void advance(Duration duration) {
    _now = _now.add(duration);
    _controller.add(_now);
  }

  /// Set the clock to an absolute [time].
  void set(DateTime time) {
    _now = time;
    _controller.add(_now);
  }

  /// A [Stopwatch]-like elapsed helper: returns the duration between the
  /// initial time and [now].
  Duration elapsed(DateTime since) => _now.difference(since);

  /// Create a timer-like future that completes when [advance] moves the clock
  /// past [duration] from the current time.
  Future<void> waitFor(Duration duration) {
    final target = _now.add(duration);
    if (_now.isAfter(target) || _now.isAtSameMomentAs(target)) {
      return Future.value();
    }
    final completer = Completer<void>();
    late StreamSubscription<DateTime> sub;
    sub = _controller.stream.listen((t) {
      if (t.isAfter(target) || t.isAtSameMomentAs(target)) {
        completer.complete();
        sub.cancel();
      }
    });
    return completer.future;
  }

  void dispose() {
    _controller.close();
  }
}
