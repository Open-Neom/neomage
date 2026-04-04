// MCP client — port of neom_claw/src/services/mcp/client.ts.
// Manages connections to MCP servers, tool discovery, and execution.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

import '../tools/tool.dart';
import '../tools/tool_registry.dart';
import 'mcp_types.dart';

/// Result of calling an MCP tool.
class McpToolResult {
  final String content;
  final bool isError;
  final Map<String, dynamic>? meta;

  const McpToolResult({
    required this.content,
    this.isError = false,
    this.meta,
  });
}

/// MCP client — manages server connections and tool proxying.
class McpClient {
  final Map<String, McpServerConnection> _connections = {};
  final Map<String, Process> _processes = {};
  final ToolRegistry toolRegistry;

  McpClient({required this.toolRegistry});

  /// All server connections.
  Map<String, McpServerConnection> get connections =>
      Map.unmodifiable(_connections);

  /// Connected servers only.
  List<ConnectedMcpServer> get connectedServers => _connections.values
      .whereType<ConnectedMcpServer>()
      .toList();

  /// Connect to an MCP server.
  Future<McpServerConnection> connect(McpServerConfig config) async {
    final name = config.name;

    // Check if already connected
    final existing = _connections[name];
    if (existing is ConnectedMcpServer) return existing;

    _connections[name] = PendingMcpServer(
      serverName: name,
      config: config,
    );

    try {
      final connection = await _connectTransport(config);
      _connections[name] = connection;

      // Register tools from this server
      if (connection is ConnectedMcpServer) {
        _registerMcpTools(connection);
      }

      return connection;
    } catch (e) {
      final failed = FailedMcpServer(
        serverName: name,
        config: config,
        error: e.toString(),
      );
      _connections[name] = failed;
      return failed;
    }
  }

  /// Disconnect from an MCP server.
  Future<void> disconnect(String serverName) async {
    _unregisterMcpTools(serverName);
    _connections.remove(serverName);

    // Kill process if stdio
    final process = _processes.remove(serverName);
    if (process != null) {
      process.kill(ProcessSignal.sigterm);
      // Wait briefly for clean shutdown
      await Future.delayed(const Duration(milliseconds: 400));
      process.kill(ProcessSignal.sigkill);
    }
  }

  /// Disconnect all servers.
  Future<void> disconnectAll() async {
    final names = _connections.keys.toList();
    for (final name in names) {
      await disconnect(name);
    }
  }

  /// Call a tool on an MCP server.
  Future<McpToolResult> callTool({
    required String serverName,
    required String toolName,
    required Map<String, dynamic> input,
    Duration timeout = const Duration(hours: 1),
  }) async {
    final connection = _connections[serverName];
    if (connection is! ConnectedMcpServer) {
      return McpToolResult(
        content: 'MCP server "$serverName" is not connected',
        isError: true,
      );
    }

    try {
      // Send JSON-RPC request to server
      final request = {
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch,
        'method': 'tools/call',
        'params': {
          'name': toolName,
          'arguments': input,
        },
      };

      final response = await _sendRequest(serverName, request, timeout);

      if (response == null) {
        return const McpToolResult(
          content: 'No response from MCP server',
          isError: true,
        );
      }

      // Parse result
      if (response['error'] != null) {
        final error = response['error'] as Map<String, dynamic>;
        return McpToolResult(
          content: error['message'] as String? ?? 'MCP error',
          isError: true,
        );
      }

      final result = response['result'] as Map<String, dynamic>?;
      if (result == null) {
        return const McpToolResult(content: '', isError: false);
      }

      final content = _extractContent(result);
      final isError = result['isError'] as bool? ?? false;

      return McpToolResult(
        content: content,
        isError: isError,
        meta: result['_meta'] as Map<String, dynamic>?,
      );
    } catch (e) {
      return McpToolResult(
        content: 'MCP tool call error: $e',
        isError: true,
      );
    }
  }

  /// Reload tools from a connected server.
  Future<void> refreshTools(String serverName) async {
    final connection = _connections[serverName];
    if (connection is! ConnectedMcpServer) return;

    _unregisterMcpTools(serverName);

    try {
      final tools = await _fetchTools(serverName);
      _connections[serverName] = ConnectedMcpServer(
        serverName: serverName,
        config: connection.config,
        tools: tools,
        resources: connection.resources,
      );
      _registerMcpTools(_connections[serverName] as ConnectedMcpServer);
    } catch (_) {
      // Keep existing connection state
    }
  }

  // ── Private ──

  Future<McpServerConnection> _connectTransport(McpServerConfig config) async {
    switch (config) {
      case McpStdioConfig():
        return _connectStdio(config);
      case McpSseConfig():
      case McpHttpConfig():
      case McpWebSocketConfig():
        // Network transports — placeholder for full implementation
        return FailedMcpServer(
          serverName: config.name,
          config: config,
          error: 'Network MCP transports not yet implemented. '
              'Use stdio transport.',
        );
      case McpSdkConfig():
        return FailedMcpServer(
          serverName: config.name,
          config: config,
          error: 'SDK transport not available in Flutter.',
        );
    }
  }

  Future<McpServerConnection> _connectStdio(McpStdioConfig config) async {
    final process = await Process.start(
      config.command,
      config.args,
      environment: config.env.isNotEmpty ? config.env : null,
    );

    _processes[config.name] = process;

    // Initialize: send initialize request
    final initRequest = {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': {
        'protocolVersion': '2024-11-05',
        'capabilities': {},
        'clientInfo': {'name': 'flutter_claw', 'version': '0.1.0'},
      },
    };

    process.stdin.writeln(jsonEncode(initRequest));
    await process.stdin.flush();

    // Read initialize response
    final initResponse = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 10));

    final initResult = jsonDecode(initResponse) as Map<String, dynamic>;
    if (initResult['error'] != null) {
      process.kill();
      return FailedMcpServer(
        serverName: config.name,
        config: config,
        error: 'Initialize failed: ${initResult['error']}',
      );
    }

    // Send initialized notification
    final initializedNotif = {
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    };
    process.stdin.writeln(jsonEncode(initializedNotif));
    await process.stdin.flush();

    // Fetch tools
    final tools = await _fetchTools(config.name);

    return ConnectedMcpServer(
      serverName: config.name,
      config: config,
      tools: tools,
    );
  }

  Future<List<McpToolInfo>> _fetchTools(String serverName) async {
    final request = {
      'jsonrpc': '2.0',
      'id': DateTime.now().millisecondsSinceEpoch,
      'method': 'tools/list',
    };

    final response = await _sendRequest(
      serverName,
      request,
      const Duration(seconds: 10),
    );

    if (response == null || response['result'] == null) return [];

    final result = response['result'] as Map<String, dynamic>;
    final toolsList = result['tools'] as List<dynamic>? ?? [];

    return toolsList.map((t) {
      final tool = t as Map<String, dynamic>;
      final annotations = tool['annotations'] as Map<String, dynamic>?;
      return McpToolInfo(
        name: tool['name'] as String,
        description: tool['description'] as String? ?? '',
        inputSchema: tool['inputSchema'] as Map<String, dynamic>? ?? {},
        serverName: serverName,
        readOnly: annotations?['readOnlyHint'] as bool? ?? false,
        destructive: annotations?['destructiveHint'] as bool? ?? false,
      );
    }).toList();
  }

  Future<Map<String, dynamic>?> _sendRequest(
    String serverName,
    Map<String, dynamic> request,
    Duration timeout,
  ) async {
    final process = _processes[serverName];
    if (process == null) return null;

    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();

    final line = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(timeout);

    return jsonDecode(line) as Map<String, dynamic>?;
  }

  void _registerMcpTools(ConnectedMcpServer server) {
    for (final toolInfo in server.tools) {
      final tool = _McpProxyTool(
        info: toolInfo,
        client: this,
      );
      toolRegistry.register(tool);
    }
  }

  void _unregisterMcpTools(String serverName) {
    final prefix = 'mcp__${McpToolInfo.normalize(serverName)}__';
    final toRemove = toolRegistry.all
        .where((t) => t.name.startsWith(prefix))
        .map((t) => t.name)
        .toList();
    for (final name in toRemove) {
      toolRegistry.unregister(name);
    }
  }

  String _extractContent(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is List) {
      return content.map((c) {
        if (c is Map && c['type'] == 'text') return c['text'];
        return c.toString();
      }).join('\n');
    }
    if (content is String) return content;
    return jsonEncode(result);
  }
}

/// Proxy tool that forwards execution to an MCP server.
class _McpProxyTool extends Tool {
  final McpToolInfo info;
  final McpClient client;

  _McpProxyTool({required this.info, required this.client});

  @override
  String get name => info.fullName;

  @override
  String get description => info.description.length > 2048
      ? '${info.description.substring(0, 2048)}...'
      : info.description;

  @override
  Map<String, dynamic> get inputSchema => info.inputSchema;

  @override
  bool get isMcp => true;

  @override
  bool get shouldDefer => true;

  @override
  bool get alwaysLoad => info.alwaysLoad;

  @override
  bool get isReadOnly => info.readOnly;

  @override
  bool get isDestructive => info.destructive;

  @override
  Map<String, dynamic>? get mcpInfo => {
        'serverName': info.serverName,
        'toolName': info.name,
      };

  @override
  String get userFacingName => info.name;

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final result = await client.callTool(
      serverName: info.serverName,
      toolName: info.name,
      input: input,
    );

    return result.isError
        ? ToolResult.error(result.content)
        : ToolResult.success(result.content, metadata: result.meta);
  }
}
