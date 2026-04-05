// MCP Panel Screen — port of neomage/src/components/McpPanel/.
// Shows MCP server status, tools, resources, prompts.
// Wired to the real McpClient service via Sint DI.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import 'package:neomage/data/mcp/mcp_client.dart';
import 'package:neomage/data/mcp/mcp_types.dart';

// ─── Types ───

/// MCP server status for display.
enum McpServerStatus { disconnected, connecting, connected, error }

/// MCP server display info.
class McpServerDisplayInfo {
  final String name;
  final McpServerStatus status;
  final String? transport;
  final List<McpToolDisplay> tools;
  final List<McpResourceDisplay> resources;
  final String? errorMessage;
  final DateTime? connectedSince;
  final McpServerConfig? config;

  const McpServerDisplayInfo({
    required this.name,
    required this.status,
    this.transport,
    this.tools = const [],
    this.resources = const [],
    this.errorMessage,
    this.connectedSince,
    this.config,
  });
}

/// MCP tool display info.
class McpToolDisplay {
  final String name;
  final String? description;
  final Map<String, dynamic>? schema;

  const McpToolDisplay({required this.name, this.description, this.schema});
}

/// MCP resource display info.
class McpResourceDisplay {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;

  const McpResourceDisplay({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
  });
}

// ─── McpPanelScreen widget ───

/// Full MCP management screen, wired to the real [McpClient] service.
class McpPanelScreen extends StatefulWidget {
  /// Optional pre-supplied server list (ignored when McpClient is available).
  final List<McpServerDisplayInfo> servers;

  const McpPanelScreen({super.key, this.servers = const []});

  @override
  State<McpPanelScreen> createState() => _McpPanelScreenState();
}

class _McpPanelScreenState extends State<McpPanelScreen> {
  String? _expandedServer;
  int _selectedTab = 0; // 0=tools, 1=resources
  late McpClient _mcpClient;
  List<McpServerDisplayInfo> _servers = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _mcpClient = Sint.find<McpClient>();
    _refreshServers();
    // Poll for connection-state changes every 2 seconds.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshServers(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // ── Mapping from McpClient state to display models ──

  void _refreshServers() {
    final connections = _mcpClient.connections;
    final list = <McpServerDisplayInfo>[];

    for (final entry in connections.entries) {
      final conn = entry.value;
      list.add(_connectionToDisplay(conn));
    }

    if (!mounted) return;
    setState(() => _servers = list);
  }

  McpServerDisplayInfo _connectionToDisplay(McpServerConnection conn) {
    final transport = conn.config.transport.name;

    switch (conn) {
      case ConnectedMcpServer():
        return McpServerDisplayInfo(
          name: conn.serverName,
          status: McpServerStatus.connected,
          transport: transport,
          connectedSince: conn.connectedAt,
          config: conn.config,
          tools: conn.tools
              .map(
                (t) => McpToolDisplay(
                  name: t.name,
                  description:
                      t.description.isNotEmpty ? t.description : null,
                  schema: t.inputSchema,
                ),
              )
              .toList(),
          resources: conn.resources
              .map(
                (r) => McpResourceDisplay(
                  uri: r.uri,
                  name: r.name,
                  description: r.description,
                  mimeType: r.mimeType,
                ),
              )
              .toList(),
        );
      case PendingMcpServer():
        return McpServerDisplayInfo(
          name: conn.serverName,
          status: McpServerStatus.connecting,
          transport: transport,
          config: conn.config,
        );
      case FailedMcpServer():
        return McpServerDisplayInfo(
          name: conn.serverName,
          status: McpServerStatus.error,
          transport: transport,
          errorMessage: conn.error,
          config: conn.config,
        );
      case DisabledMcpServer():
        return McpServerDisplayInfo(
          name: conn.serverName,
          status: McpServerStatus.disconnected,
          transport: transport,
          config: conn.config,
        );
    }
  }

  // ── Actions ──

  Future<void> _connectServer(McpServerConfig config) async {
    await _mcpClient.connect(config);
    _refreshServers();
  }

  Future<void> _disconnectServer(String name) async {
    await _mcpClient.disconnect(name);
    _refreshServers();
  }

  Future<void> _restartServer(McpServerDisplayInfo server) async {
    final config = server.config;
    if (config == null) return;
    await _mcpClient.disconnect(server.name);
    await _mcpClient.connect(config);
    _refreshServers();
  }

  Future<void> _removeServer(String name) async {
    await _mcpClient.disconnect(name);
    _refreshServers();
  }

  void _showAddServerDialog() {
    final nameCtrl = TextEditingController();
    final commandCtrl = TextEditingController();
    final argsCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Add MCP Server'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Server name',
                    hintText: 'e.g. my-server',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commandCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Command',
                    hintText: 'e.g. npx or python',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: argsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Arguments (space-separated)',
                    hintText: 'e.g. -m my_mcp_server',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final command = commandCtrl.text.trim();
                if (name.isEmpty || command.isEmpty) return;
                final args = argsCtrl.text
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((s) => s.isNotEmpty)
                    .toList();
                final config = McpStdioConfig(
                  name: name,
                  command: command,
                  args: args,
                );
                Navigator.of(ctx).pop();
                _connectServer(config);
              },
              child: const Text('Connect'),
            ),
          ],
        );
      },
    );
  }

  // ── UI helpers ──

  Color _statusColor(McpServerStatus status) {
    switch (status) {
      case McpServerStatus.disconnected:
        return Colors.grey;
      case McpServerStatus.connecting:
        return Colors.amber;
      case McpServerStatus.connected:
        return Colors.green;
      case McpServerStatus.error:
        return Colors.red;
    }
  }

  String _statusLabel(McpServerStatus status) {
    switch (status) {
      case McpServerStatus.disconnected:
        return 'Disconnected';
      case McpServerStatus.connecting:
        return 'Connecting...';
      case McpServerStatus.connected:
        return 'Connected';
      case McpServerStatus.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Servers'),
        actions: [
          IconButton(
            onPressed: _showAddServerDialog,
            icon: const Icon(Icons.add),
            tooltip: 'Add MCP Server',
          ),
        ],
      ),
      body: _servers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.dns_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No MCP servers configured',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add servers in settings or via /mcp command',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _showAddServerDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Server'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _servers.length,
              itemBuilder: (context, index) {
                final server = _servers[index];
                final isExpanded = _expandedServer == server.name;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isDark ? const Color(0xFF1E1E36) : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: _statusColor(server.status).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Server header
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedServer = isExpanded ? null : server.name;
                          });
                        },
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(10),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Status dot
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _statusColor(server.status),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      server.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Text(
                                          _statusLabel(server.status),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: _statusColor(server.status),
                                          ),
                                        ),
                                        if (server.transport != null) ...[
                                          Text(
                                            ' \u00b7 ${server.transport}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white30
                                                  : Colors.black26,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              // Stats
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${server.tools.length} tools',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black45,
                                    ),
                                  ),
                                  Text(
                                    '${server.resources.length} resources',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? Colors.white38
                                          : Colors.black26,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 8),
                              // Actions
                              PopupMenuButton<String>(
                                onSelected: (action) {
                                  switch (action) {
                                    case 'restart':
                                      _restartServer(server);
                                    case 'disconnect':
                                      _disconnectServer(server.name);
                                    case 'connect':
                                      if (server.config != null) {
                                        _connectServer(server.config!);
                                      }
                                    case 'remove':
                                      _removeServer(server.name);
                                  }
                                },
                                itemBuilder: (_) => [
                                  if (server.status ==
                                      McpServerStatus.connected)
                                    const PopupMenuItem(
                                      value: 'restart',
                                      child: Row(
                                        children: [
                                          Icon(Icons.refresh, size: 16),
                                          SizedBox(width: 8),
                                          Text('Restart'),
                                        ],
                                      ),
                                    ),
                                  if (server.status ==
                                      McpServerStatus.connected)
                                    const PopupMenuItem(
                                      value: 'disconnect',
                                      child: Row(
                                        children: [
                                          Icon(Icons.link_off, size: 16),
                                          SizedBox(width: 8),
                                          Text('Disconnect'),
                                        ],
                                      ),
                                    ),
                                  if (server.status ==
                                          McpServerStatus.disconnected ||
                                      server.status == McpServerStatus.error)
                                    const PopupMenuItem(
                                      value: 'connect',
                                      child: Row(
                                        children: [
                                          Icon(Icons.link, size: 16),
                                          SizedBox(width: 8),
                                          Text('Connect'),
                                        ],
                                      ),
                                    ),
                                  const PopupMenuItem(
                                    value: 'remove',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Remove',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Error message
                      if (server.errorMessage != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          color: Colors.red.withValues(alpha: 0.1),
                          child: Text(
                            server.errorMessage!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade300,
                            ),
                          ),
                        ),
                      ],

                      // Expanded content: tabs for tools/resources
                      if (isExpanded) ...[
                        const Divider(height: 1),
                        // Tab bar
                        Row(
                          children: [
                            _tab('Tools (${server.tools.length})', 0),
                            _tab(
                              'Resources (${server.resources.length})',
                              1,
                            ),
                          ],
                        ),
                        const Divider(height: 1),
                        // Tab content
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: _selectedTab == 0
                              ? _buildToolsList(server)
                              : _buildResourcesList(server),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _tab(String label, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isSelected = _selectedTab == index;

    return InkWell(
      onTap: () => setState(() => _selectedTab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              width: 2,
              color: isSelected
                  ? (isDark ? Colors.blue.shade400 : Colors.blue)
                  : Colors.transparent,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected
                ? (isDark ? Colors.blue.shade300 : Colors.blue)
                : (isDark ? Colors.white54 : Colors.black45),
          ),
        ),
      ),
    );
  }

  Widget _buildToolsList(McpServerDisplayInfo server) {
    if (server.tools.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No tools exposed by this server.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      itemCount: server.tools.length,
      itemBuilder: (context, index) {
        final tool = server.tools[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ListTile(
          dense: true,
          leading: Icon(
            Icons.build_outlined,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
          title: Text(
            tool.name,
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: tool.description != null
              ? Text(
                  tool.description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
        );
      },
    );
  }

  Widget _buildResourcesList(McpServerDisplayInfo server) {
    if (server.resources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'No resources exposed by this server.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      itemCount: server.resources.length,
      itemBuilder: (context, index) {
        final resource = server.resources[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ListTile(
          dense: true,
          leading: Icon(
            Icons.storage_outlined,
            size: 16,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
          title: Text(
            resource.name,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            resource.uri,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: isDark ? Colors.white30 : Colors.black26,
            ),
          ),
          trailing: resource.mimeType != null
              ? Text(
                  resource.mimeType!,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                )
              : null,
        );
      },
    );
  }
}
