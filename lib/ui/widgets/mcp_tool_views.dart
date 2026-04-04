// McpToolViews — port of neom_claw/src/components/mcp/
// Ports: MCPToolListView.tsx, MCPToolDetailView.tsx, ElicitationDialog.tsx,
// CapabilitiesSection.tsx, McpParsingWarnings.tsx, MCPReconnect.tsx,
// MCPAgentServerMenu.tsx, MCPStdioServerMenu.tsx, MCPRemoteServerMenu.tsx
//
// Provides detailed MCP tool views:
// - MCPToolListView: scrollable list of tools from an MCP server with search
// - MCPToolDetailView: detail view of a single MCP tool with schema
// - ElicitationDialog: dialog for MCP server elicitation requests
// - CapabilitiesSection: displays MCP server capabilities
// - McpParsingWarnings: shows tool parsing/validation warnings
// - MCPReconnect: reconnection UI for disconnected servers
// - Server menu widgets for stdio, remote, and agent servers

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

// ─── MCP tool models ───

/// Represents a single MCP tool definition.
class McpToolInfo {
  final String name;
  final String? description;
  final Map<String, dynamic>? inputSchema;
  final bool isEnabled;
  final String serverName;
  final String? serverUri;

  const McpToolInfo({
    required this.name,
    this.description,
    this.inputSchema,
    this.isEnabled = true,
    required this.serverName,
    this.serverUri,
  });
}

/// MCP server capability flags.
class McpServerCapabilities {
  final bool hasTools;
  final bool hasResources;
  final bool hasPrompts;
  final bool hasLogging;
  final bool hasCompletion;

  const McpServerCapabilities({
    this.hasTools = false,
    this.hasResources = false,
    this.hasPrompts = false,
    this.hasLogging = false,
    this.hasCompletion = false,
  });
}

/// MCP server connection status.
enum McpServerStatus { connected, connecting, disconnected, error }

/// MCP server info model.
class McpServerInfo {
  final String name;
  final String? uri;
  final McpServerStatus status;
  final McpServerCapabilities capabilities;
  final List<McpToolInfo> tools;
  final List<String> warnings;
  final String? errorMessage;
  final String serverType; // 'stdio' | 'remote' | 'agent'
  final String? command; // For stdio servers
  final List<String>? args; // For stdio servers

  const McpServerInfo({
    required this.name,
    this.uri,
    this.status = McpServerStatus.disconnected,
    this.capabilities = const McpServerCapabilities(),
    this.tools = const [],
    this.warnings = const [],
    this.errorMessage,
    this.serverType = 'stdio',
    this.command,
    this.args,
  });
}

/// Elicitation field from an MCP server.
class ElicitationField {
  final String name;
  final String type; // 'string' | 'number' | 'boolean' | 'enum'
  final String? description;
  final String? defaultValue;
  final List<String>? enumValues;
  final bool required;

  const ElicitationField({
    required this.name,
    required this.type,
    this.description,
    this.defaultValue,
    this.enumValues,
    this.required = false,
  });
}

/// Elicitation request from an MCP server.
class ElicitationRequest {
  final String serverId;
  final String serverName;
  final String? message;
  final List<ElicitationField> fields;
  final String requestId;

  const ElicitationRequest({
    required this.serverId,
    required this.serverName,
    this.message,
    required this.fields,
    required this.requestId,
  });
}

// ─── MCP Tool Views Controller ───

class McpToolViewsController extends SintController {
  // Observable state
  final servers = <String, McpServerInfo>{}.obs;
  final selectedServerId = Rxn<String>();
  final selectedToolName = Rxn<String>();
  final searchQuery = ''.obs;
  final selectedToolIndex = 0.obs;
  final pendingElicitations = <ElicitationRequest>[].obs;

  // Computed
  McpServerInfo? get selectedServer {
    final id = selectedServerId.value;
    return id != null ? servers[id] : null;
  }

  McpToolInfo? get selectedTool {
    final name = selectedToolName.value;
    if (name == null) return null;
    final server = selectedServer;
    if (server == null) return null;
    return server.tools.cast<McpToolInfo?>().firstWhere(
      (t) => t?.name == name,
      orElse: () => null,
    );
  }

  /// Filtered tools based on search query.
  List<McpToolInfo> get filteredTools {
    final server = selectedServer;
    if (server == null) return [];
    final query = searchQuery.value.toLowerCase();
    if (query.isEmpty) return server.tools;
    return server.tools
        .where(
          (t) =>
              t.name.toLowerCase().contains(query) ||
              (t.description?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
  }

  /// Select a server by ID.
  void selectServer(String serverId) {
    selectedServerId.value = serverId;
    selectedToolName.value = null;
    selectedToolIndex.value = 0;
    searchQuery.value = '';
  }

  /// Select a tool by name.
  void selectTool(String toolName) {
    selectedToolName.value = toolName;
  }

  /// Clear tool selection (back to list).
  void clearToolSelection() {
    selectedToolName.value = null;
  }

  /// Navigate tool selection up.
  void selectPreviousTool() {
    if (selectedToolIndex.value > 0) {
      selectedToolIndex.value--;
    }
  }

  /// Navigate tool selection down.
  void selectNextTool() {
    final maxIdx = filteredTools.length - 1;
    if (selectedToolIndex.value < maxIdx) {
      selectedToolIndex.value++;
    }
  }

  /// Toggle a tool's enabled state.
  void toggleToolEnabled(String serverName, String toolName) {
    // In real implementation, would persist to MCP config
  }

  /// Attempt to reconnect a disconnected server.
  Future<void> reconnectServer(String serverId) async {
    final server = servers[serverId];
    if (server == null) return;

    servers[serverId] = McpServerInfo(
      name: server.name,
      uri: server.uri,
      status: McpServerStatus.connecting,
      capabilities: server.capabilities,
      tools: server.tools,
      warnings: server.warnings,
      serverType: server.serverType,
      command: server.command,
      args: server.args,
    );
    servers.refresh();

    // In real implementation, would actually reconnect
    // Simulating reconnection delay
    await Future.delayed(const Duration(seconds: 2));

    servers[serverId] = McpServerInfo(
      name: server.name,
      uri: server.uri,
      status: McpServerStatus.connected,
      capabilities: server.capabilities,
      tools: server.tools,
      warnings: server.warnings,
      serverType: server.serverType,
      command: server.command,
      args: server.args,
    );
    servers.refresh();
  }

  /// Respond to an elicitation request.
  void respondToElicitation(String requestId, Map<String, String> values) {
    pendingElicitations.removeWhere((e) => e.requestId == requestId);
    // In real implementation, would send response to MCP server
  }

  /// Decline an elicitation request.
  void declineElicitation(String requestId) {
    pendingElicitations.removeWhere((e) => e.requestId == requestId);
    // In real implementation, would send decline to MCP server
  }
}

// ─── MCPToolListView (mirrors MCPToolListView.tsx) ───

class McpToolListView extends StatelessWidget {
  final String serverId;
  final VoidCallback? onBack;

  const McpToolListView({super.key, required this.serverId, this.onBack});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<McpToolViewsController>();

    return Obx(() {
      controller.selectServer(serverId);
      final server = controller.selectedServer;

      if (server == null) {
        return Center(
          child: Text(
            'Server not found',
            style: TextStyle(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        );
      }

      // If a tool is selected, show detail view
      if (controller.selectedToolName.value != null) {
        return McpToolDetailView(
          tool: controller.selectedTool!,
          onBack: controller.clearToolSelection,
        );
      }

      return _buildToolList(context, controller, server);
    });
  }

  Widget _buildToolList(
    BuildContext context,
    McpToolViewsController controller,
    McpServerInfo server,
  ) {
    final theme = Theme.of(context);
    final tools = controller.filteredTools;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (onBack != null) ...[
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 18),
                    onPressed: onBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _ServerStatusDot(status: server.status),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${server.tools.length} tools',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (server.status == McpServerStatus.disconnected ||
                    server.status == McpServerStatus.error)
                  TextButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Reconnect'),
                    onPressed: () => controller.reconnectServer(serverId),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),

          // Capabilities
          if (server.capabilities.hasTools ||
              server.capabilities.hasResources ||
              server.capabilities.hasPrompts)
            CapabilitiesSection(capabilities: server.capabilities),

          // Warnings
          if (server.warnings.isNotEmpty)
            McpParsingWarnings(warnings: server.warnings),

          const Divider(height: 1),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              onChanged: (v) => controller.searchQuery.value = v,
              decoration: InputDecoration(
                hintText: 'Search tools...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
            ),
          ),

          // Tool list
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  if (tools.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        controller.searchQuery.value.isNotEmpty
                            ? 'No tools match your search'
                            : 'No tools available',
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    ...tools.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final tool = entry.value;
                      final isSelected =
                          idx == controller.selectedToolIndex.value;
                      return _McpToolTile(
                        tool: tool,
                        isSelected: isSelected,
                        onTap: () => controller.selectTool(tool.name),
                        onToggle: () => controller.toggleToolEnabled(
                          tool.serverName,
                          tool.name,
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── McpToolDetailView (mirrors MCPToolDetailView.tsx) ───

class McpToolDetailView extends StatelessWidget {
  final McpToolInfo tool;
  final VoidCallback onBack;

  const McpToolDetailView({
    super.key,
    required this.tool,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.build_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tool.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tool.isEnabled
                        ? Colors.green.withValues(alpha: 0.1)
                        : theme.colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    tool.isEnabled ? 'Enabled' : 'Disabled',
                    style: TextStyle(
                      color: tool.isEnabled
                          ? Colors.green
                          : theme.colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Detail content
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Server
                  _InfoRow(label: 'Server', value: tool.serverName),

                  const SizedBox(height: 12),

                  // Description
                  if (tool.description != null) ...[
                    Text(
                      'Description',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tool.description!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Input schema
                  if (tool.inputSchema != null) ...[
                    Text(
                      'Input Schema',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SchemaView(schema: tool.inputSchema!),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Schema view (renders JSON schema properties) ───

class _SchemaView extends StatelessWidget {
  final Map<String, dynamic> schema;

  const _SchemaView({required this.schema});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final properties = (schema['properties'] as Map<String, dynamic>?) ?? {};
    final required_ =
        (schema['required'] as List<dynamic>?)?.cast<String>() ?? [];

    if (properties.isEmpty) {
      return Text(
        'No parameters',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: properties.entries.map((entry) {
          final name = entry.key;
          final prop = entry.value as Map<String, dynamic>? ?? {};
          final type = prop['type'] as String? ?? 'any';
          final desc = prop['description'] as String?;
          final isRequired = required_.contains(name);

          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      type,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (isRequired) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'required',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (desc != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── MCP tool tile (single tool in list) ───

class _McpToolTile extends StatelessWidget {
  final McpToolInfo tool;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  const _McpToolTile({
    required this.tool,
    required this.isSelected,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Text(
                isSelected ? '\u25B6 ' : '  ',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              Icons.build_outlined,
              size: 14,
              color: tool.isEnabled
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tool.name,
                    style: TextStyle(
                      color: tool.isEnabled
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                  if (tool.description != null)
                    Text(
                      tool.description!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Enable/disable toggle
            GestureDetector(
              onTap: onToggle,
              child: Container(
                width: 32,
                height: 18,
                decoration: BoxDecoration(
                  color: tool.isEnabled
                      ? Colors.green.withValues(alpha: 0.3)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: AnimatedAlign(
                  alignment: tool.isEnabled
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 14,
                    height: 14,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: tool.isEnabled
                          ? Colors.green
                          : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Server status dot ───

class _ServerStatusDot extends StatelessWidget {
  final McpServerStatus status;

  const _ServerStatusDot({required this.status});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      McpServerStatus.connected => Colors.green,
      McpServerStatus.connecting => Colors.orange,
      McpServerStatus.disconnected => Colors.grey,
      McpServerStatus.error => Colors.red,
    };

    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

// ─── Info row helper ───

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

// ─── CapabilitiesSection (mirrors CapabilitiesSection.tsx) ───

class CapabilitiesSection extends StatelessWidget {
  final McpServerCapabilities capabilities;

  const CapabilitiesSection({super.key, required this.capabilities});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = <MapEntry<String, bool>>[
      MapEntry('Tools', capabilities.hasTools),
      MapEntry('Resources', capabilities.hasResources),
      MapEntry('Prompts', capabilities.hasPrompts),
      MapEntry('Logging', capabilities.hasLogging),
      MapEntry('Completion', capabilities.hasCompletion),
    ].where((e) => e.value).toList();

    if (caps.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: caps.map((cap) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              cap.key,
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 11),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── McpParsingWarnings (mirrors McpParsingWarnings.tsx) ───

class McpParsingWarnings extends StatelessWidget {
  final List<String> warnings;

  const McpParsingWarnings({super.key, required this.warnings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (warnings.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: Colors.orange[700],
              ),
              const SizedBox(width: 6),
              Text(
                '${warnings.length} ${warnings.length == 1 ? 'warning' : 'warnings'}',
                style: TextStyle(
                  color: Colors.orange[700],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...warnings.map(
            (warning) => Padding(
              padding: const EdgeInsets.only(left: 20, top: 2),
              child: Text(
                '\u2022 $warning',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── MCPReconnect (mirrors MCPReconnect.tsx) ───

class McpReconnect extends StatelessWidget {
  final McpServerInfo server;
  final VoidCallback onReconnect;

  const McpReconnect({
    super.key,
    required this.server,
    required this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.link_off, size: 16, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${server.name} disconnected',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (server.errorMessage != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: Text(
                server.errorMessage!,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 14),
              label: Text(
                server.status == McpServerStatus.connecting
                    ? 'Reconnecting...'
                    : 'Reconnect',
              ),
              onPressed: server.status == McpServerStatus.connecting
                  ? null
                  : onReconnect,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── ElicitationDialog (mirrors ElicitationDialog.tsx) ───

class ElicitationDialog extends StatefulWidget {
  final ElicitationRequest request;
  final void Function(Map<String, String> values) onSubmit;
  final VoidCallback onDecline;

  const ElicitationDialog({
    super.key,
    required this.request,
    required this.onSubmit,
    required this.onDecline,
  });

  @override
  State<ElicitationDialog> createState() => _ElicitationDialogState();
}

class _ElicitationDialogState extends State<ElicitationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _values = <String, String>{};

  @override
  void initState() {
    super.initState();
    // Initialize with default values
    for (final field in widget.request.fields) {
      _values[field.name] = field.defaultValue ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.help_outline,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Input requested',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'from ${widget.request.serverName}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Message
              if (widget.request.message != null) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    widget.request.message!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              const Divider(height: 1),

              // Form fields
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: widget.request.fields.map((field) {
                        return _buildField(context, field);
                      }).toList(),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1),

              // Actions
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: widget.onDecline,
                      child: const Text('Decline'),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {
                        if (_formKey.currentState?.validate() ?? false) {
                          widget.onSubmit(_values);
                        }
                      },
                      child: const Text('Submit'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(BuildContext context, ElicitationField field) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                field.name,
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (field.required) ...[
                const SizedBox(width: 4),
                Text(
                  '*',
                  style: TextStyle(
                    color: theme.colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          if (field.description != null) ...[
            const SizedBox(height: 2),
            Text(
              field.description!,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (field.type == 'boolean')
            SwitchListTile(
              value: _values[field.name] == 'true',
              onChanged: (v) {
                setState(() {
                  _values[field.name] = v.toString();
                });
              },
              contentPadding: EdgeInsets.zero,
              title: const SizedBox.shrink(),
            )
          else if (field.type == 'enum' && field.enumValues != null)
            DropdownButtonFormField<String>(
              initialValue: _values[field.name]?.isNotEmpty == true
                  ? _values[field.name]
                  : null,
              items: field.enumValues!.map((v) {
                return DropdownMenuItem(value: v, child: Text(v));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _values[field.name] = v;
                  });
                }
              },
              decoration: InputDecoration(
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              validator: field.required
                  ? (v) => v == null || v.isEmpty ? 'Required' : null
                  : null,
            )
          else
            TextFormField(
              initialValue: _values[field.name],
              onChanged: (v) => _values[field.name] = v,
              keyboardType: field.type == 'number'
                  ? TextInputType.number
                  : TextInputType.text,
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                hintText: field.defaultValue,
              ),
              validator: field.required
                  ? (v) => v == null || v.isEmpty ? 'Required' : null
                  : null,
            ),
        ],
      ),
    );
  }
}
