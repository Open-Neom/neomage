// MCP types — port of neom_claw/src/services/mcp/types.ts.
// Model Context Protocol type definitions.

/// MCP transport types.
enum McpTransportType {
  stdio,
  sse,
  http,
  webSocket,
  sdk,
}

/// MCP server configuration.
sealed class McpServerConfig {
  final String name;
  final McpTransportType transport;
  final Map<String, String> env;

  const McpServerConfig({
    required this.name,
    required this.transport,
    this.env = const {},
  });
}

/// Stdio transport — spawns subprocess.
class McpStdioConfig extends McpServerConfig {
  final String command;
  final List<String> args;

  const McpStdioConfig({
    required super.name,
    required this.command,
    this.args = const [],
    super.env,
  }) : super(transport: McpTransportType.stdio);
}

/// SSE transport — server-sent events over HTTP.
class McpSseConfig extends McpServerConfig {
  final String url;
  final Map<String, String> headers;

  const McpSseConfig({
    required super.name,
    required this.url,
    this.headers = const {},
    super.env,
  }) : super(transport: McpTransportType.sse);
}

/// HTTP transport — streamable HTTP.
class McpHttpConfig extends McpServerConfig {
  final String url;
  final Map<String, String> headers;

  const McpHttpConfig({
    required super.name,
    required this.url,
    this.headers = const {},
    super.env,
  }) : super(transport: McpTransportType.http);
}

/// WebSocket transport.
class McpWebSocketConfig extends McpServerConfig {
  final String url;
  final Map<String, String> headers;

  const McpWebSocketConfig({
    required super.name,
    required this.url,
    this.headers = const {},
    super.env,
  }) : super(transport: McpTransportType.webSocket);
}

/// In-process SDK transport.
class McpSdkConfig extends McpServerConfig {
  const McpSdkConfig({required super.name, super.env})
      : super(transport: McpTransportType.sdk);
}

/// Config scope — where the config was loaded from.
enum McpConfigScope {
  local,
  user,
  project,
  dynamic,
  enterprise,
  managed,
}

/// MCP server connection state.
sealed class McpServerConnection {
  final String serverName;
  final McpServerConfig config;
  const McpServerConnection({required this.serverName, required this.config});
}

class ConnectedMcpServer extends McpServerConnection {
  final List<McpToolInfo> tools;
  final List<McpResource> resources;
  final DateTime connectedAt;

  ConnectedMcpServer({
    required super.serverName,
    required super.config,
    required this.tools,
    this.resources = const [],
  }) : connectedAt = DateTime.now();
}

class FailedMcpServer extends McpServerConnection {
  final String error;
  final DateTime failedAt;

  FailedMcpServer({
    required super.serverName,
    required super.config,
    required this.error,
  }) : failedAt = DateTime.now();
}

class PendingMcpServer extends McpServerConnection {
  final int attemptCount;

  const PendingMcpServer({
    required super.serverName,
    required super.config,
    this.attemptCount = 0,
  });
}

class DisabledMcpServer extends McpServerConnection {
  const DisabledMcpServer({
    required super.serverName,
    required super.config,
  });
}

/// Information about an MCP-provided tool.
class McpToolInfo {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final String serverName;
  final bool readOnly;
  final bool destructive;
  final String? searchHint;
  final bool alwaysLoad;

  const McpToolInfo({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.serverName,
    this.readOnly = false,
    this.destructive = false,
    this.searchHint,
    this.alwaysLoad = false,
  });

  /// Full tool name in MCP format: mcp__server__tool.
  String get fullName => 'mcp__${normalize(serverName)}__${normalize(name)}';

  static String normalize(String s) =>
      s.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
}

/// An MCP resource.
class McpResource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;
  final String serverName;

  const McpResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
    required this.serverName,
  });
}
