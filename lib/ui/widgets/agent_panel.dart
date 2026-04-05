// AgentPanel — port of neomage/src/components/AgentPanel/.
// Shows spawned agents, their status, tasks, logs, and swarm overview.

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ─── Agent display data ───

/// Agent status for display.
enum AgentDisplayStatus { idle, running, completed, failed, cancelled, waiting }

/// Agent info for display in the panel.
class AgentDisplayInfo {
  final String id;
  final String name;
  final String role;
  final String model;
  final AgentDisplayStatus status;
  final String? currentTask;
  final double? progress; // 0.0–1.0
  final Duration? elapsed;
  final int tokensUsed;
  final double cost;
  final List<AgentLogEntry> logs;
  final List<TaskDisplayInfo> tasks;

  const AgentDisplayInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.model,
    required this.status,
    this.currentTask,
    this.progress,
    this.elapsed,
    this.tokensUsed = 0,
    this.cost = 0.0,
    this.logs = const [],
    this.tasks = const [],
  });
}

/// Log entry for an agent.
class AgentLogEntry {
  final DateTime timestamp;
  final String message;
  final AgentLogLevel level;

  const AgentLogEntry({
    required this.timestamp,
    required this.message,
    this.level = AgentLogLevel.info,
  });
}

enum AgentLogLevel { debug, info, warning, error }

/// Task info for display.
class TaskDisplayInfo {
  final String id;
  final String name;
  final String status;
  final double? progress;
  final Duration? elapsed;
  final String? result;
  final List<String> dependencies;

  const TaskDisplayInfo({
    required this.id,
    required this.name,
    required this.status,
    this.progress,
    this.elapsed,
    this.result,
    this.dependencies = const [],
  });
}

/// Swarm overview data.
class SwarmDisplayInfo {
  final int totalAgents;
  final int activeAgents;
  final int completedTasks;
  final int totalTasks;
  final int failedTasks;
  final Duration elapsed;
  final double totalCost;
  final List<AgentDisplayInfo> agents;
  final List<({String from, String to})> dependencies;

  const SwarmDisplayInfo({
    required this.totalAgents,
    required this.activeAgents,
    required this.completedTasks,
    required this.totalTasks,
    required this.failedTasks,
    required this.elapsed,
    required this.totalCost,
    required this.agents,
    this.dependencies = const [],
  });

  double get completionRate =>
      totalTasks > 0 ? completedTasks / totalTasks : 0.0;
}

// ─── AgentPanel widget ───

/// Side panel showing all active agents, tasks, and swarm status.
class AgentPanel extends StatefulWidget {
  final List<AgentDisplayInfo> agents;
  final SwarmDisplayInfo? swarm;
  final VoidCallback? onClose;
  final ValueChanged<String>? onCancelAgent;
  final ValueChanged<String>? onCancelTask;

  const AgentPanel({
    super.key,
    required this.agents,
    this.swarm,
    this.onClose,
    this.onCancelAgent,
    this.onCancelTask,
  });

  @override
  State<AgentPanel> createState() => _AgentPanelState();
}

class _AgentPanelState extends State<AgentPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _expandedAgentId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: widget.swarm != null ? 3 : 2,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141428) : const Color(0xFFFAFAFC),
        border: Border(
          left: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.groups_outlined,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                const SizedBox(width: 8),
                Text(
                  'Agents',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const Spacer(),
                // Active count badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blue.shade900 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.agents.where((a) => a.status == AgentDisplayStatus.running).length} active',
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (widget.onClose != null)
                  IconButton(
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                  ),
              ],
            ),
          ),

          // Tabs
          TabBar(
            controller: _tabController,
            labelStyle: const TextStyle(fontSize: 12),
            tabs: [
              const Tab(text: 'Agents'),
              const Tab(text: 'Tasks'),
              if (widget.swarm != null) const Tab(text: 'Swarm'),
            ],
          ),

          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAgentList(),
                _buildTaskList(),
                if (widget.swarm != null) _buildSwarmView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentList() {
    if (widget.agents.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.smart_toy_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No agents spawned',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Use the Agent tool to spawn sub-agents',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: widget.agents.length,
      itemBuilder: (context, index) {
        final agent = widget.agents[index];
        return AgentCard(
          agent: agent,
          isExpanded: _expandedAgentId == agent.id,
          onToggle: () {
            setState(() {
              _expandedAgentId = _expandedAgentId == agent.id ? null : agent.id;
            });
          },
          onCancel: widget.onCancelAgent != null
              ? () => widget.onCancelAgent!(agent.id)
              : null,
        );
      },
    );
  }

  Widget _buildTaskList() {
    final allTasks = widget.agents.expand((a) => a.tasks).toList();
    if (allTasks.isEmpty) {
      return Center(
        child: Text(NeomageTranslationConstants.noTasks.tr, style: TextStyle(color: Colors.grey.shade500)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: allTasks.length,
      itemBuilder: (context, index) {
        final task = allTasks[index];
        return TaskTile(
          task: task,
          onCancel: widget.onCancelTask != null
              ? () => widget.onCancelTask!(task.id)
              : null,
        );
      },
    );
  }

  Widget _buildSwarmView() {
    final swarm = widget.swarm!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Swarm overview
          SwarmOverviewCard(swarm: swarm),
          const SizedBox(height: 12),

          // Progress bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Overall Progress',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  Text(
                    '${(swarm.completionRate * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: swarm.completionRate,
                backgroundColor: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation(
                  swarm.failedTasks > 0 ? Colors.orange : Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Agent list within swarm
          Text(
            'Swarm Agents',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          ...swarm.agents.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AgentCard(
                agent: a,
                isExpanded: _expandedAgentId == a.id,
                onToggle: () => setState(() {
                  _expandedAgentId = _expandedAgentId == a.id ? null : a.id;
                }),
                compact: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── AgentCard ───

/// Card displaying individual agent info.
class AgentCard extends StatelessWidget {
  final AgentDisplayInfo agent;
  final bool isExpanded;
  final VoidCallback onToggle;
  final VoidCallback? onCancel;
  final bool compact;

  const AgentCard({
    super.key,
    required this.agent,
    required this.isExpanded,
    required this.onToggle,
    this.onCancel,
    this.compact = false,
  });

  Color _statusColor(AgentDisplayStatus status) {
    switch (status) {
      case AgentDisplayStatus.idle:
        return Colors.grey;
      case AgentDisplayStatus.running:
        return Colors.blue;
      case AgentDisplayStatus.completed:
        return Colors.green;
      case AgentDisplayStatus.failed:
        return Colors.red;
      case AgentDisplayStatus.cancelled:
        return Colors.orange;
      case AgentDisplayStatus.waiting:
        return Colors.amber;
    }
  }

  String _statusLabel(AgentDisplayStatus status) {
    switch (status) {
      case AgentDisplayStatus.idle:
        return 'Idle';
      case AgentDisplayStatus.running:
        return 'Running';
      case AgentDisplayStatus.completed:
        return 'Done';
      case AgentDisplayStatus.failed:
        return 'Failed';
      case AgentDisplayStatus.cancelled:
        return 'Cancelled';
      case AgentDisplayStatus.waiting:
        return 'Waiting';
    }
  }

  String _formatDuration(Duration? d) {
    if (d == null) return '';
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sColor = _statusColor(agent.status);

    return Card(
      margin: EdgeInsets.only(bottom: compact ? 4 : 8),
      color: isDark ? const Color(0xFF1E1E36) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: sColor.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // Status dot
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: sColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      agent.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    _statusLabel(agent.status),
                    style: TextStyle(fontSize: 10, color: sColor),
                  ),
                ],
              ),

              if (!compact) ...[
                const SizedBox(height: 4),
                // Model + role
                Row(
                  children: [
                    Text(
                      agent.role,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      agent.model,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                  ],
                ),
              ],

              // Progress bar
              if (agent.progress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: agent.progress!,
                  backgroundColor: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.black.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation(sColor),
                  minHeight: 3,
                ),
              ],

              // Current task
              if (agent.currentTask != null && !compact) ...[
                const SizedBox(height: 4),
                Text(
                  agent.currentTask!,
                  style: TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Expanded details
              if (isExpanded) ...[
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 8),

                // Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _stat('Tokens', '${agent.tokensUsed}'),
                    _stat('Cost', '\$${agent.cost.toStringAsFixed(4)}'),
                    _stat('Time', _formatDuration(agent.elapsed)),
                  ],
                ),

                // Log entries
                if (agent.logs.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  AgentLogView(logs: agent.logs, maxHeight: 150),
                ],

                // Cancel button
                if (onCancel != null &&
                    agent.status == AgentDisplayStatus.running) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.cancel_outlined, size: 14),
                      label: const Text(
                        'Cancel',
                        style: TextStyle(fontSize: 12),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}

// ─── TaskTile ───

/// List tile for a single task.
class TaskTile extends StatelessWidget {
  final TaskDisplayInfo task;
  final VoidCallback? onCancel;

  const TaskTile({super.key, required this.task, this.onCancel});

  IconData get _statusIcon {
    switch (task.status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'running':
        return Icons.play_circle_outline;
      case 'failed':
        return Icons.error_outline;
      case 'cancelled':
        return Icons.cancel_outlined;
      case 'blocked':
        return Icons.block;
      default:
        return Icons.radio_button_unchecked;
    }
  }

  Color get _statusColor {
    switch (task.status) {
      case 'completed':
        return Colors.green;
      case 'running':
        return Colors.blue;
      case 'failed':
        return Colors.red;
      case 'cancelled':
        return Colors.orange;
      case 'blocked':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      color: isDark ? const Color(0xFF1E1E36) : Colors.white,
      child: ListTile(
        dense: true,
        leading: Icon(_statusIcon, size: 18, color: _statusColor),
        title: Text(
          task.name,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: task.dependencies.isNotEmpty
            ? Text(
                'depends on: ${task.dependencies.join(", ")}',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
              )
            : null,
        trailing: task.progress != null
            ? SizedBox(
                width: 40,
                child: Text(
                  '${(task.progress! * 100).toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 11, color: _statusColor),
                  textAlign: TextAlign.right,
                ),
              )
            : null,
      ),
    );
  }
}

// ─── AgentLogView ───

/// Scrollable log view for agent activity.
class AgentLogView extends StatelessWidget {
  final List<AgentLogEntry> logs;
  final double maxHeight;

  const AgentLogView({super.key, required this.logs, this.maxHeight = 200});

  Color _levelColor(AgentLogLevel level) {
    switch (level) {
      case AgentLogLevel.debug:
        return Colors.grey;
      case AgentLogLevel.info:
        return Colors.blue;
      case AgentLogLevel.warning:
        return Colors.orange;
      case AgentLogLevel.error:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0D1A) : const Color(0xFFF5F5F8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(6),
        itemCount: logs.length,
        reverse: true,
        itemBuilder: (context, index) {
          final log = logs[logs.length - 1 - index];
          final time =
              '${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                children: [
                  TextSpan(text: '$time '),
                  TextSpan(
                    text: '[${log.level.name.toUpperCase()}] ',
                    style: TextStyle(color: _levelColor(log.level)),
                  ),
                  TextSpan(text: log.message),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── SwarmOverviewCard ───

/// Summary card for swarm overview.
class SwarmOverviewCard extends StatelessWidget {
  final SwarmDisplayInfo swarm;

  const SwarmOverviewCard({super.key, required this.swarm});

  String _formatDuration(Duration d) {
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m ${d.inSeconds % 60}s';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A1A3E), const Color(0xFF2A1A4E)]
              : [const Color(0xFFE8E8FF), const Color(0xFFF0E8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Swarm Overview',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _metric(
                'Agents',
                '${swarm.activeAgents}/${swarm.totalAgents}',
                Colors.blue,
              ),
              _metric(
                'Tasks',
                '${swarm.completedTasks}/${swarm.totalTasks}',
                Colors.green,
              ),
              _metric(
                'Failed',
                '${swarm.failedTasks}',
                swarm.failedTasks > 0 ? Colors.red : Colors.grey,
              ),
              _metric(
                'Cost',
                '\$${swarm.totalCost.toStringAsFixed(3)}',
                Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Elapsed: ${_formatDuration(swarm.elapsed)}',
            style: TextStyle(
              fontSize: 10,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
        ),
      ],
    );
  }
}
