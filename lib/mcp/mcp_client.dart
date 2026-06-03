import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'mcp_models.dart';

/// Abstract transport layer for MCP communication.
abstract class McpTransport {
  Stream<String> get messageStream;
  Future<void> send(String message);
  Future<void> close();
}

/// Transport implementation using stdio pipes for a local subprocess.
class StdioMcpTransport implements McpTransport {
  final String command;
  final List<String> args;
  final Map<String, String>? environment;
  Process? _process;
  final _messageController = StreamController<String>.broadcast();
  StreamSubscription? _stdoutSubscription;
  StreamSubscription? _stderrSubscription;

  StdioMcpTransport({
    required this.command,
    this.args = const [],
    this.environment,
  });

  Future<void> start() async {
    _process = await Process.start(
      command,
      args,
      environment: environment,
    );

    // Read stdout line by line
    _stdoutSubscription = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isNotEmpty) {
          _messageController.add(line);
        }
      },
      onError: (err) => _messageController.addError(err),
      onDone: () => _messageController.close(),
    );

    // Pipe stderr to system error stream to avoid hanging
    _stderrSubscription = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln('[MCP SERVER STDERR] $line');
    });
  }

  @override
  Stream<String> get messageStream => _messageController.stream;

  @override
  Future<void> send(String message) async {
    if (_process == null) throw StateError('Transport not started');
    _process!.stdin.writeln(message);
    await _process!.stdin.flush();
  }

  @override
  Future<void> close() async {
    await _stdoutSubscription?.cancel();
    await _stderrSubscription?.cancel();
    _process?.kill();
    _process = null;
    await _messageController.close();
  }
}

/// Main Model Context Protocol (MCP) Client.
class McpClient {
  final McpTransport transport;
  final _pendingRequests = <dynamic, Completer<McpResponse>>{};
  StreamSubscription? _messageSubscription;
  int _requestIdCounter = 1;

  McpClient({required this.transport});

  /// Connects to the MCP server.
  Future<void> connect() async {
    if (transport is StdioMcpTransport) {
      await (transport as StdioMcpTransport).start();
    }

    _messageSubscription = transport.messageStream.listen(
      _handleIncomingMessage,
      onError: (err) {
        stderr.writeln('[MCP CLIENT ERROR] $err');
      },
    );

    // Perform handshake/initialize if needed (MCP standard)
    await _sendRequest('initialize', {
      'protocolVersion': '2024-11-05',
      'capabilities': {},
      'clientInfo': {'name': 'Itzli-MCP-Client', 'version': '1.0.0'}
    });
  }

  /// Lists all tools exposed by the MCP server.
  Future<List<McpTool>> listTools() async {
    final response = await _sendRequest('tools/list', {});
    if (response.isError) {
      throw Exception('Failed to list tools: ${response.error}');
    }
    final result = response.result as Map<String, dynamic>?;
    final toolsList = (result?['tools'] as List?) ?? [];
    return toolsList
        .map((t) => McpTool.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  /// Calls a specific tool with the provided arguments.
  Future<McpResponse> callTool(String name, Map<String, dynamic> arguments) async {
    return _sendRequest('tools/call', {
      'name': name,
      if (arguments.isNotEmpty) 'arguments': arguments,
    });
  }

  /// Lists resources exposed by the MCP server.
  Future<List<McpResource>> listResources() async {
    final response = await _sendRequest('resources/list', {});
    if (response.isError) {
      throw Exception('Failed to list resources: ${response.error}');
    }
    final result = response.result as Map<String, dynamic>?;
    final resourcesList = (result?['resources'] as List?) ?? [];
    return resourcesList
        .map((r) => McpResource.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Closes the client and its transport.
  Future<void> disconnect() async {
    await _messageSubscription?.cancel();
    await transport.close();
    for (final completer in _pendingRequests.values) {
      completer.completeError(TimeoutException('MCP client disconnected'));
    }
    _pendingRequests.clear();
  }

  // ═══════════════════════════════════════════
  // Internal Helpers
  // ═══════════════════════════════════════════

  Future<McpResponse> _sendRequest(String method, Map<String, dynamic> params) async {
    final id = _requestIdCounter++;
    final completer = Completer<McpResponse>();
    _pendingRequests[id] = completer;

    final request = McpRequest(
      method: method,
      params: params,
      id: id,
    );

    try {
      await transport.send(request.toJsonString());
    } catch (e) {
      _pendingRequests.remove(id);
      completer.completeError(e);
    }

    // Set a default timeout of 30 seconds for tool execution/response
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('MCP Request timed out for method: $method');
      },
    );
  }

  void _handleIncomingMessage(String rawLine) {
    try {
      final json = jsonDecode(rawLine);
      if (json is! Map<String, dynamic>) return;

      // Handle JSON-RPC response
      if (json.containsKey('id') && (json.containsKey('result') || json.containsKey('error'))) {
        final id = json['id'];
        final completer = _pendingRequests.remove(id);
        if (completer != null) {
          final response = McpResponse.fromJson(json);
          completer.complete(response);
        }
      }
    } catch (e) {
      stderr.writeln('[MCP CLIENT PARSE ERROR] $e on message: $rawLine');
    }
  }
}
