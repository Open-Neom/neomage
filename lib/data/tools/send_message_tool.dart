// SendMessage tool — port of openclaude/src/tools/SendMessageTool.
// Routes messages between agents in a multi-agent system.

import 'agent_tool.dart';
import 'tool.dart';

/// SendMessage tool — delivers messages to other agents.
class SendMessageTool extends Tool {
  final AgentTool agentTool;

  /// Pending messages queued for agents that aren't ready yet.
  final Map<String, List<_QueuedMessage>> _pendingMessages = {};

  SendMessageTool({required this.agentTool});

  @override
  String get name => 'SendMessage';

  @override
  String get description =>
      'Send a message to another agent. Messages are delivered asynchronously '
      'to the recipient\'s message queue.';

  @override
  bool get isReadOnly => true;

  @override
  bool get shouldDefer => true;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'to': {
            'type': 'string',
            'description': 'Recipient: agent name or ID',
          },
          'message': {
            'type': 'string',
            'description': 'Message content to send',
          },
          'summary': {
            'type': 'string',
            'description': 'Short 5-10 word summary (shown as preview)',
          },
        },
        'required': ['to', 'message'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final to = input['to'] as String?;
    final message = input['message'] as String?;
    final summary = input['summary'] as String?;

    if (to == null || to.isEmpty) {
      return ToolResult.error('Missing required parameter: to');
    }
    if (message == null || message.isEmpty) {
      return ToolResult.error('Missing required parameter: message');
    }

    // Check if target agent exists
    final agentInfo = agentTool.getActiveAgent(to);
    if (agentInfo == null) {
      // Queue for later delivery
      _pendingMessages.putIfAbsent(to, () => []).add(
        _QueuedMessage(
          from: 'parent',
          message: message,
          summary: summary,
          timestamp: DateTime.now(),
        ),
      );

      return ToolResult.success(
        'Message queued for agent "$to" (not currently active). '
        'It will be delivered when the agent is next available.',
        metadata: {
          'routing': 'queued',
          'to': to,
        },
      );
    }

    // Agent is active — queue the message
    _pendingMessages.putIfAbsent(to, () => []).add(
      _QueuedMessage(
        from: 'parent',
        message: message,
        summary: summary,
        timestamp: DateTime.now(),
      ),
    );

    return ToolResult.success(
      'Message sent to agent "$to".',
      metadata: {
        'routing': 'in_process',
        'to': to,
      },
    );
  }

  /// Retrieve and clear pending messages for an agent.
  List<String> consumeMessages(String agentId) {
    final messages = _pendingMessages.remove(agentId);
    if (messages == null) return const [];
    return messages.map((m) => m.message).toList();
  }

  /// Check if there are pending messages for an agent.
  bool hasPendingMessages(String agentId) =>
      _pendingMessages.containsKey(agentId) &&
      _pendingMessages[agentId]!.isNotEmpty;
}

class _QueuedMessage {
  final String from;
  final String message;
  final String? summary;
  final DateTime timestamp;

  const _QueuedMessage({
    required this.from,
    required this.message,
    this.summary,
    required this.timestamp,
  });
}
