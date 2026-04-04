// MCP Panel Screen — port of neom_claw/src/components/McpPanel/.
// Shows MCP server status, tools, resources, prompts.

import 'dart:async';

import 'package:flutter/material.dart';

// ─── Types ───

/// MCP server status for display.
enum McpServerStatus {
  disconnected,
  connecting,
  connected,
  error,
  restarting,
}

/// MCP server display info.
class McpServerDisplayInfo {
  final String name;
  final McpServerStatus status;
  final String? version;
  final String? transport; // stdio, sse, http, websocket
  final List<McpToolDisplay> tools;
  final List<McpResourceDisplay> resources;
  final List<McpPromptDisplay> prompts;
  final String? errorMessage;
  final DateTime? connectedSince;
  final int restartCount;

  const McpServerDisplayInfo({
    required this.name,
    required this.status,
    this.version,
    this.transport,
    this.tools = const [],
    this.resources = const [],
    this.prompts = const [],
    this.errorMessage,
    this.connectedSince,
    this.restartCount = 0,
  });
}

/// MCP tool display info.
class McpToolDisplay {
  final String name;
  final String? description;
  final Map<String, dynamic>? schema;
  final int usageCount;

  const McpToolDisplay({
    required this.name,
    this.description,
    this.schema,
    this.usageCount = 0,
  });
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

/// MCP prompt display info.
class McpPromptDisplay {
  final String name;
  final String? description;
  final List<String> argumentNames;

  const McpPromptDisplay({
    required this.name,
    this.description,
    this.argumentNames = const [],
  });
}

// ─── McpPanelScreen widget ───

/// Full MCP management screen.
class McpPanelScreen extends StatefulWidget {
  final List<McpServerDisplayInfo> servers;
  final ValueChanged<String>? onConnect;
  final ValueChanged<String>? onDisconnect;
  final ValueChanged<String>? onRestart;
  final VoidCallback? onAddServer;
  final ValueChanged<String>? onRemoveServer;
  final void Function(String server, String tool, Map<String, dynamic> input)?
      onTestTool;

  const McpPanelScreen({
    super.key,
    required this.servers,
    this.onConnect,
    this.onDisconnect,
    this.onRestart,
    this.onAddServer,
    this.onRemoveServer,
    this.onTestTool,
  });

  @override
  State<McpPanelScreen> createState() => _McpPanelScreenState();
}

class _McpPanelScreenState extends State<McpPanelScreen> {
  String? _expandedServer;
  int _selectedTab = 0; // 0=tools, 1=resources, 2=prompts

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
      case McpServerStatus.restarting:
        return Colors.orange;
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
      case McpServerStatus.restarting:
        return 'Restarting...';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('MCP Servers'),
        actions: [
          if (widget.onAddServer != null)
            IconButton(
              onPressed: widget.onAddServer,
              icon: const Icon(Icons.add),
              tooltip: 'Add MCP Server',
            ),
        ],
      ),
      body: widget.servers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'No MCP servers configured',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add servers in settings or via /mcp command',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (widget.onAddServer != null)
                    ElevatedButton.icon(
                      onPressed: widget.onAddServer,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Server'),
                    ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.servers.length,
              itemBuilder: (context, index) {
                final server = widget.servers[index];
                final isExpanded = _expandedServer == server.name;

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  color: isDark
                      ? const Color(0xFF1E1E36)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: _statusColor(server.status)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Server header
                      InkWell(
                        onTap: () {
                          setState(() {
                            _expandedServer =
                                isExpanded ? null : server.name;
                          });
                        },
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(10)),
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                            color: _statusColor(
                                                server.status),
                                          ),
                                        ),
                                        if (server.transport != null) ...[
                                          Text(
                                            ' · ${server.transport}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white30
                                                  : Colors.black26,
                                            ),
                                          ),
                                        ],
                                        if (server.version != null) ...[
                                          Text(
                                            ' · v${server.version}',
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
                                crossAxisAlignment:
                                    CrossAxisAlignment.end,
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
                                      widget.onRestart?.call(server.name);
                                      break;
                                    case 'disconnect':
                                      widget.onDisconnect
                                          ?.call(server.name);
                                      break;
                                    case 'connect':
                                      widget.onConnect
                                          ?.call(server.name);
                                      break;
                                    case 'remove':
                                      widget.onRemoveServer
                                          ?.call(server.name);
                                      break;
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
                                      McpServerStatus.disconnected)
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
                                        Icon(Icons.delete_outline,
                                            size: 16, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Remove',
                                            style: TextStyle(
                                                color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
                                icon: const Icon(Icons.more_vert,
                                    size: 18),
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
                              horizontal: 12, vertical: 6),
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

                      // Expanded content: tabs for tools/resources/prompts
                      if (isExpanded) ...[
                        const Divider(height: 1),
                        // Tab bar
                        Row(
                          children: [
                            _tab('Tools (${server.tools.length})', 0),
                            _tab(
                                'Resources (${server.resources.length})',
                                1),
                            _tab(
                                'Prompts (${server.prompts.length})', 2),
                          ],
                        ),
                        const Divider(height: 1),
                        // Tab content
                        ConstrainedBox(
                          constraints:
                              const BoxConstraints(maxHeight: 300),
                          child: _selectedTab == 0
                              ? _buildToolsList(server)
                              : _selectedTab == 1
                                  ? _buildResourcesList(server)
                                  : _buildPromptsList(server),
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
        child: Text('No tools exposed by this server.',
            style: TextStyle(color: Colors.grey)),
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
          leading: Icon(Icons.build_outlined,
              size: 16,
              color: isDark ? Colors.white54 : Colors.black45),
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
          trailing: tool.usageCount > 0
              ? Text(
                  '${tool.usageCount}x',
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

  Widget _buildResourcesList(McpServerDisplayInfo server) {
    if (server.resources.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No resources exposed by this server.',
            style: TextStyle(color: Colors.grey)),
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
          leading: Icon(Icons.storage_outlined,
              size: 16,
              color: isDark ? Colors.white54 : Colors.black45),
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

  Widget _buildPromptsList(McpServerDisplayInfo server) {
    if (server.prompts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No prompts exposed by this server.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      padding: const EdgeInsets.all(8),
      itemCount: server.prompts.length,
      itemBuilder: (context, index) {
        final prompt = server.prompts[index];
        final isDark = Theme.of(context).brightness == Brightness.dark;

        return ListTile(
          dense: true,
          leading: Icon(Icons.chat_outlined,
              size: 16,
              color: isDark ? Colors.white54 : Colors.black45),
          title: Text(
            prompt.name,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (prompt.description != null)
                Text(
                  prompt.description!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              if (prompt.argumentNames.isNotEmpty)
                Text(
                  'args: ${prompt.argumentNames.join(", ")}',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: isDark ? Colors.white30 : Colors.black26,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
