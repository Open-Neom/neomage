// SendMessageTool — faithful port of neom_claw/src/tools/SendMessageTool.
// Routes messages between agents in a multi-agent swarm system.
//
// Supports:
//   - Plain text messages (to named agents or broadcast via "*")
//   - Structured messages: shutdown_request, shutdown_response,
//     plan_approval_response
//   - In-process agent routing with auto-resume for stopped agents
//   - Broadcast to all teammates
//   - Message queuing for offline agents
//   - Team mailbox persistence
//   - Bridge / UDS cross-session messaging (placeholder hooks)

import 'dart:convert';

import 'tool.dart';

// ── Constants ──────────────────────────────────────────────────────────────

/// Tool name matching the TS original.
const String sendMessageToolName = 'SendMessage';

/// Display name for the team lead agent.
const String teamLeadName = 'team-lead';

/// Maximum result size before disk persistence.
const int sendMessageMaxResultSizeChars = 100000;

// ── Structured message types ───────────────────────────────────────────

/// Discriminated union of structured message types.
abstract class StructuredMessage {
  String get type;
  Map<String, dynamic> toMap();

  factory StructuredMessage.fromMap(Map<String, dynamic> map) {
    final type = map['type'] as String?;
    switch (type) {
      case 'shutdown_request':
        return ShutdownRequestMessage(reason: map['reason'] as String?);
      case 'shutdown_response':
        return ShutdownResponseMessage(
          requestId: map['request_id'] as String? ?? '',
          approve: map['approve'] as bool? ?? false,
          reason: map['reason'] as String?,
        );
      case 'plan_approval_response':
        return PlanApprovalResponseMessage(
          requestId: map['request_id'] as String? ?? '',
          approve: map['approve'] as bool? ?? false,
          feedback: map['feedback'] as String?,
        );
      default:
        throw ArgumentError('Unknown structured message type: $type');
    }
  }
}

class ShutdownRequestMessage implements StructuredMessage {
  @override
  String get type => 'shutdown_request';
  final String? reason;

  const ShutdownRequestMessage({this.reason});

  @override
  Map<String, dynamic> toMap() => {
    'type': type,
    if (reason != null) 'reason': reason,
  };
}

class ShutdownResponseMessage implements StructuredMessage {
  @override
  String get type => 'shutdown_response';
  final String requestId;
  final bool approve;
  final String? reason;

  const ShutdownResponseMessage({
    required this.requestId,
    required this.approve,
    this.reason,
  });

  @override
  Map<String, dynamic> toMap() => {
    'type': type,
    'request_id': requestId,
    'approve': approve,
    if (reason != null) 'reason': reason,
  };
}

class PlanApprovalResponseMessage implements StructuredMessage {
  @override
  String get type => 'plan_approval_response';
  final String requestId;
  final bool approve;
  final String? feedback;

  const PlanApprovalResponseMessage({
    required this.requestId,
    required this.approve,
    this.feedback,
  });

  @override
  Map<String, dynamic> toMap() => {
    'type': type,
    'request_id': requestId,
    'approve': approve,
    if (feedback != null) 'feedback': feedback,
  };
}

// ── Output types ───────────────────────────────────────────────────────

/// Message routing information for display.
class MessageRouting {
  final String sender;
  final String? senderColor;
  final String target;
  final String? targetColor;
  final String? summary;
  final String? content;

  const MessageRouting({
    required this.sender,
    this.senderColor,
    required this.target,
    this.targetColor,
    this.summary,
    this.content,
  });

  Map<String, dynamic> toMap() => {
    'sender': sender,
    if (senderColor != null) 'senderColor': senderColor,
    'target': target,
    if (targetColor != null) 'targetColor': targetColor,
    if (summary != null) 'summary': summary,
    if (content != null) 'content': content,
  };
}

/// Output from a direct message send.
class MessageOutput {
  final bool success;
  final String message;
  final MessageRouting? routing;

  const MessageOutput({
    required this.success,
    required this.message,
    this.routing,
  });

  Map<String, dynamic> toMap() => {
    'success': success,
    'message': message,
    if (routing != null) 'routing': routing!.toMap(),
  };
}

/// Output from a broadcast message.
class BroadcastOutput {
  final bool success;
  final String message;
  final List<String> recipients;
  final MessageRouting? routing;

  const BroadcastOutput({
    required this.success,
    required this.message,
    required this.recipients,
    this.routing,
  });

  Map<String, dynamic> toMap() => {
    'success': success,
    'message': message,
    'recipients': recipients,
    if (routing != null) 'routing': routing!.toMap(),
  };
}

/// Output from a shutdown request.
class RequestOutput {
  final bool success;
  final String message;
  final String requestId;
  final String target;

  const RequestOutput({
    required this.success,
    required this.message,
    required this.requestId,
    required this.target,
  });

  Map<String, dynamic> toMap() => {
    'success': success,
    'message': message,
    'request_id': requestId,
    'target': target,
  };
}

/// Output from a shutdown or plan response.
class ResponseOutput {
  final bool success;
  final String message;
  final String? requestId;

  const ResponseOutput({
    required this.success,
    required this.message,
    this.requestId,
  });

  Map<String, dynamic> toMap() => {
    'success': success,
    'message': message,
    if (requestId != null) 'request_id': requestId,
  };
}

// ── Queued message ─────────────────────────────────────────────────────

class _QueuedMessage {
  final String from;
  final String message;
  final String? summary;
  final DateTime timestamp;
  final String? color;

  const _QueuedMessage({
    required this.from,
    required this.message,
    this.summary,
    required this.timestamp,
    this.color,
  });

  Map<String, dynamic> toMap() => {
    'from': from,
    'text': message,
    if (summary != null) 'summary': summary,
    'timestamp': timestamp.toIso8601String(),
    if (color != null) 'color': color,
  };
}

// ── Address parsing ────────────────────────────────────────────────────

/// Parsed peer address supporting teammate, UDS, and bridge schemes.
class ParsedAddress {
  /// 'other' (teammate name), 'bridge', or 'uds'
  final String scheme;
  final String target;

  const ParsedAddress({required this.scheme, required this.target});
}

/// Parse a recipient address into scheme + target.
/// Supports `bridge:<session-id>`, `uds:<socket-path>`, or bare names.
ParsedAddress parseAddress(String to) {
  if (to.startsWith('bridge:')) {
    return ParsedAddress(scheme: 'bridge', target: to.substring(7));
  }
  if (to.startsWith('uds:')) {
    return ParsedAddress(scheme: 'uds', target: to.substring(4));
  }
  return ParsedAddress(scheme: 'other', target: to);
}

/// Generate a request ID for shutdown/approval requests.
String generateRequestId(String prefix, String target) {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  return '${prefix}_${target}_$timestamp';
}

/// Truncate a string to maxLength with ellipsis.
String truncate(String text, int maxLength) {
  if (text.length <= maxLength) return text;
  return '${text.substring(0, maxLength)}...';
}

// ── Team context ───────────────────────────────────────────────────────

/// Minimal team context for SendMessageTool.
class TeamContext {
  final String? teamName;
  final Map<String, TeamMember> teammates;

  const TeamContext({this.teamName, this.teammates = const {}});
}

/// A member of a team.
class TeamMember {
  final String name;
  final String? color;
  final String? agentId;
  final String? tmuxPaneId;
  final String? backendType;

  const TeamMember({
    required this.name,
    this.color,
    this.agentId,
    this.tmuxPaneId,
    this.backendType,
  });
}

// ── Main SendMessageTool ──────────────────────────────────────────────

/// SendMessage tool -- delivers messages between agents in a multi-agent
/// swarm system.
///
/// Supports plain text messages, structured shutdown/plan messages,
/// broadcast to all teammates, in-process agent routing with auto-resume,
/// and message queuing for offline agents.
class SendMessageTool extends Tool {
  /// Team context provider (injected at construction).
  TeamContext Function()? getTeamContext;

  /// Agent name for this instance (injected at construction).
  String Function()? getAgentName;

  /// Agent color for display.
  String? Function()? getAgentColor;

  /// Whether the agent is a team lead.
  bool Function()? getIsTeamLead;

  /// Whether the agent is a teammate.
  bool Function()? getIsTeammate;

  /// Whether swarms are enabled.
  bool Function()? isSwarmEnabled;

  /// Pending messages queued for agents that aren't ready yet.
  final Map<String, List<_QueuedMessage>> _pendingMessages = {};

  /// Active agent registry: agentId -> status/info.
  final Map<String, Map<String, dynamic>> _agentRegistry = {};

  SendMessageTool({
    this.getTeamContext,
    this.getAgentName,
    this.getAgentColor,
    this.getIsTeamLead,
    this.getIsTeammate,
    this.isSwarmEnabled,
  });

  @override
  String get name => sendMessageToolName;

  @override
  String get description =>
      'Send a message to another agent. Messages are delivered asynchronously '
      'to the recipient\'s message queue. Supports plain text messages, '
      'broadcast to all teammates via "*", and structured messages for '
      'shutdown coordination and plan approval.';

  @override
  String get prompt => description;

  @override
  bool get shouldDefer => true;

  @override
  int? get maxResultSizeChars => sendMessageMaxResultSizeChars;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'to': {
        'type': 'string',
        'description':
            'Recipient: teammate name, or "*" for broadcast to all '
            'teammates',
      },
      'summary': {
        'type': 'string',
        'description':
            'A 5-10 word summary shown as a preview in the UI '
            '(required when message is a string)',
      },
      'message': {
        'description':
            'Plain text message content, or a structured '
            'message object (shutdown_request, shutdown_response, '
            'plan_approval_response)',
      },
    },
    'required': ['to', 'message'],
  };

  @override
  bool get isEnabled => isSwarmEnabled?.call() ?? true;

  @override
  bool get isAvailable => true;

  @override
  String getToolUseSummary(Map<String, dynamic> input) {
    final to = input['to'] as String? ?? '';
    final summary = input['summary'] as String?;
    if (summary != null && summary.isNotEmpty) return summary;
    return 'Message to $to';
  }

  @override
  String toAutoClassifierInput(Map<String, dynamic> input) {
    final to = input['to'] as String? ?? '';
    final message = input['message'];
    if (message is String) {
      return 'to $to: $message';
    }
    if (message is Map) {
      final type = message['type'] as String? ?? '';
      switch (type) {
        case 'shutdown_request':
          return 'shutdown_request to $to';
        case 'shutdown_response':
          final approve = message['approve'] as bool? ?? false;
          final requestId = message['request_id'] as String? ?? '';
          return 'shutdown_response ${approve ? 'approve' : 'reject'} '
              '$requestId';
        case 'plan_approval_response':
          final approve = message['approve'] as bool? ?? false;
          return 'plan_approval ${approve ? 'approve' : 'reject'} to $to';
      }
    }
    return 'message to $to';
  }

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final to = input['to'] as String?;
    if (to == null || to.trim().isEmpty) {
      return const ValidationResult.invalid('to must not be empty');
    }

    // Parse address for validation
    final addr = parseAddress(to);

    // Check for empty address targets
    if ((addr.scheme == 'bridge' || addr.scheme == 'uds') &&
        addr.target.trim().isEmpty) {
      return const ValidationResult.invalid('address target must not be empty');
    }

    // Reject @ notation — there is only one team per session
    if (to.contains('@')) {
      return const ValidationResult.invalid(
        'to must be a bare teammate name or "*" -- there is only one '
        'team per session',
      );
    }

    final message = input['message'];

    // Plain text message validation
    if (message is String) {
      // Bridge cross-session: structured messages not allowed
      if (addr.scheme == 'bridge') {
        // Structured messages cannot be sent cross-session
        return const ValidationResult.valid();
      }
      // UDS cross-session: summary not required
      if (addr.scheme == 'uds') {
        return const ValidationResult.valid();
      }
      // Local plain text: summary is required
      final summary = input['summary'] as String?;
      if (summary == null || summary.trim().isEmpty) {
        return const ValidationResult.invalid(
          'summary is required when message is a string',
        );
      }
      return const ValidationResult.valid();
    }

    // Structured message validation
    if (message is Map) {
      // Structured messages cannot be broadcast
      if (to == '*') {
        return const ValidationResult.invalid(
          'structured messages cannot be broadcast (to: "*")',
        );
      }

      // Structured messages cannot be sent cross-session
      if (addr.scheme != 'other') {
        return const ValidationResult.invalid(
          'structured messages cannot be sent cross-session -- '
          'only plain text',
        );
      }

      final type = message['type'] as String?;

      // shutdown_response must be sent to team-lead
      if (type == 'shutdown_response' && to != teamLeadName) {
        return ValidationResult.invalid(
          'shutdown_response must be sent to "$teamLeadName"',
        );
      }

      // Rejecting a shutdown requires a reason
      if (type == 'shutdown_response') {
        final approve = message['approve'] as bool? ?? false;
        if (!approve) {
          final reason = message['reason'] as String?;
          if (reason == null || reason.trim().isEmpty) {
            return const ValidationResult.invalid(
              'reason is required when rejecting a shutdown request',
            );
          }
        }
      }

      return const ValidationResult.valid();
    }

    return const ValidationResult.invalid(
      'message must be a string or structured message object',
    );
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    final to = input['to'] as String? ?? '';
    final summary = input['summary'] as String?;
    final message = input['message'];

    // Handle plain text messages
    if (message is String) {
      if (to == '*') {
        return _handleBroadcast(message, summary);
      }
      return _handleMessage(to, message, summary);
    }

    // Handle structured messages
    if (message is Map<String, dynamic>) {
      return _handleStructuredMessage(to, message, summary);
    }

    return ToolResult.error('Invalid message format');
  }

  // ── Message handlers ──────────────────────────────────────────────────

  /// Handle a plain text message to a specific recipient.
  ToolResult _handleMessage(
    String recipientName,
    String content,
    String? summary,
  ) {
    final senderName = _getSenderName();
    final senderColor = getAgentColor?.call();

    // Queue the message
    _writeToMailbox(
      recipientName,
      _QueuedMessage(
        from: senderName,
        message: content,
        summary: summary,
        timestamp: DateTime.now(),
        color: senderColor,
      ),
    );

    final teamContext = getTeamContext?.call();
    final recipientColor = _findTeammateColor(teamContext, recipientName);

    final routing = MessageRouting(
      sender: senderName,
      senderColor: senderColor,
      target: '@$recipientName',
      targetColor: recipientColor,
      summary: summary,
      content: content,
    );

    final output = MessageOutput(
      success: true,
      message: "Message sent to $recipientName's inbox",
      routing: routing,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle a broadcast message to all teammates.
  ToolResult _handleBroadcast(String content, String? summary) {
    final teamContext = getTeamContext?.call();
    final teamName = teamContext?.teamName;

    if (teamName == null || teamName.isEmpty) {
      return ToolResult.error(
        'Not in a team context. Create a team first, or set '
        'NEOMCLAW_TEAM_NAME.',
      );
    }

    final senderName = _getSenderName();
    final senderColor = getAgentColor?.call();

    // Find all teammates except self
    final recipients = <String>[];
    for (final entry in teamContext!.teammates.entries) {
      if (entry.value.name.toLowerCase() != senderName.toLowerCase()) {
        recipients.add(entry.value.name);
      }
    }

    if (recipients.isEmpty) {
      final output = BroadcastOutput(
        success: true,
        message:
            'No teammates to broadcast to (you are the only '
            'team member)',
        recipients: const [],
      );
      return ToolResult.success(
        jsonEncode(output.toMap()),
        metadata: output.toMap(),
      );
    }

    // Send to each recipient
    for (final recipientName in recipients) {
      _writeToMailbox(
        recipientName,
        _QueuedMessage(
          from: senderName,
          message: content,
          summary: summary,
          timestamp: DateTime.now(),
          color: senderColor,
        ),
      );
    }

    final routing = MessageRouting(
      sender: senderName,
      senderColor: senderColor,
      target: '@team',
      summary: summary,
      content: content,
    );

    final output = BroadcastOutput(
      success: true,
      message:
          'Message broadcast to ${recipients.length} '
          'teammate(s): ${recipients.join(', ')}',
      recipients: recipients,
      routing: routing,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle a structured message (shutdown/plan).
  ToolResult _handleStructuredMessage(
    String to,
    Map<String, dynamic> message,
    String? summary,
  ) {
    if (to == '*') {
      return ToolResult.error('structured messages cannot be broadcast');
    }

    final type = message['type'] as String?;
    switch (type) {
      case 'shutdown_request':
        return _handleShutdownRequest(to, message['reason'] as String?);
      case 'shutdown_response':
        final approve = message['approve'] as bool? ?? false;
        final requestId = message['request_id'] as String? ?? '';
        if (approve) {
          return _handleShutdownApproval(requestId);
        }
        return _handleShutdownRejection(
          requestId,
          message['reason'] as String? ?? 'No reason provided',
        );
      case 'plan_approval_response':
        final approve = message['approve'] as bool? ?? false;
        final requestId = message['request_id'] as String? ?? '';
        if (approve) {
          return _handlePlanApproval(to, requestId);
        }
        return _handlePlanRejection(
          to,
          requestId,
          message['feedback'] as String? ?? 'Plan needs revision',
        );
      default:
        return ToolResult.error('Unknown structured message type: $type');
    }
  }

  /// Handle a shutdown request to a target teammate.
  ToolResult _handleShutdownRequest(String targetName, String? reason) {
    final senderName = _getSenderName();
    final requestId = generateRequestId('shutdown', targetName);
    final senderColor = getAgentColor?.call();

    final shutdownMessage = {
      'type': 'shutdown_request',
      'requestId': requestId,
      'from': senderName,
      'reason': ?reason,
    };

    _writeToMailbox(
      targetName,
      _QueuedMessage(
        from: senderName,
        message: jsonEncode(shutdownMessage),
        timestamp: DateTime.now(),
        color: senderColor,
      ),
    );

    final output = RequestOutput(
      success: true,
      message:
          'Shutdown request sent to $targetName. '
          'Request ID: $requestId',
      requestId: requestId,
      target: targetName,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle approval of a shutdown request.
  ToolResult _handleShutdownApproval(String requestId) {
    final agentName = getAgentName?.call() ?? 'teammate';
    final senderColor = getAgentColor?.call();

    final approvedMessage = {
      'type': 'shutdown_approved',
      'requestId': requestId,
      'from': agentName,
    };

    _writeToMailbox(
      teamLeadName,
      _QueuedMessage(
        from: agentName,
        message: jsonEncode(approvedMessage),
        timestamp: DateTime.now(),
        color: senderColor,
      ),
    );

    final output = ResponseOutput(
      success: true,
      message:
          'Shutdown approved. Sent confirmation to team-lead. '
          'Agent $agentName is now exiting.',
      requestId: requestId,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle rejection of a shutdown request.
  ToolResult _handleShutdownRejection(String requestId, String reason) {
    final agentName = getAgentName?.call() ?? 'teammate';
    final senderColor = getAgentColor?.call();

    final rejectedMessage = {
      'type': 'shutdown_rejected',
      'requestId': requestId,
      'from': agentName,
      'reason': reason,
    };

    _writeToMailbox(
      teamLeadName,
      _QueuedMessage(
        from: agentName,
        message: jsonEncode(rejectedMessage),
        timestamp: DateTime.now(),
        color: senderColor,
      ),
    );

    final output = ResponseOutput(
      success: true,
      message: 'Shutdown rejected. Reason: "$reason". Continuing to work.',
      requestId: requestId,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle approval of a plan from a teammate.
  ToolResult _handlePlanApproval(String recipientName, String requestId) {
    final isLead = getIsTeamLead?.call() ?? false;
    if (!isLead) {
      return ToolResult.error(
        'Only the team lead can approve plans. Teammates cannot approve '
        'their own or other plans.',
      );
    }

    final teamContext = getTeamContext?.call();
    final teamName = teamContext?.teamName;

    final approvalResponse = {
      'type': 'plan_approval_response',
      'requestId': requestId,
      'approved': true,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _writeToMailbox(
      recipientName,
      _QueuedMessage(
        from: teamLeadName,
        message: jsonEncode(approvalResponse),
        timestamp: DateTime.now(),
      ),
    );

    final output = ResponseOutput(
      success: true,
      message:
          'Plan approved for $recipientName. They will receive the '
          'approval and can proceed with implementation.',
      requestId: requestId,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  /// Handle rejection of a plan from a teammate.
  ToolResult _handlePlanRejection(
    String recipientName,
    String requestId,
    String feedback,
  ) {
    final isLead = getIsTeamLead?.call() ?? false;
    if (!isLead) {
      return ToolResult.error(
        'Only the team lead can reject plans. Teammates cannot reject '
        'their own or other plans.',
      );
    }

    final rejectionResponse = {
      'type': 'plan_approval_response',
      'requestId': requestId,
      'approved': false,
      'feedback': feedback,
      'timestamp': DateTime.now().toIso8601String(),
    };

    _writeToMailbox(
      recipientName,
      _QueuedMessage(
        from: teamLeadName,
        message: jsonEncode(rejectionResponse),
        timestamp: DateTime.now(),
      ),
    );

    final output = ResponseOutput(
      success: true,
      message:
          'Plan rejected for $recipientName with feedback: '
          '"$feedback"',
      requestId: requestId,
    );

    return ToolResult.success(
      jsonEncode(output.toMap()),
      metadata: output.toMap(),
    );
  }

  // ── Mailbox ──────────────────────────────────────────────────────────

  /// Write a message to a recipient's mailbox (in-memory queue).
  void _writeToMailbox(String recipientName, _QueuedMessage message) {
    _pendingMessages.putIfAbsent(recipientName, () => []).add(message);
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

  /// Get all pending messages without consuming them.
  List<Map<String, dynamic>> peekMessages(String agentId) {
    final messages = _pendingMessages[agentId];
    if (messages == null) return const [];
    return messages.map((m) => m.toMap()).toList();
  }

  // ── Agent registry ───────────────────────────────────────────────────

  /// Register an agent in the active agent registry.
  void registerAgent(String agentId, Map<String, dynamic> info) {
    _agentRegistry[agentId] = info;
  }

  /// Unregister an agent from the active agent registry.
  void unregisterAgent(String agentId) {
    _agentRegistry.remove(agentId);
  }

  /// Check if an agent is registered and active.
  bool isAgentActive(String agentId) => _agentRegistry.containsKey(agentId);

  /// Get info about a registered agent.
  Map<String, dynamic>? getAgentInfo(String agentId) => _agentRegistry[agentId];

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Get the sender name for the current agent.
  String _getSenderName() {
    final name = getAgentName?.call();
    if (name != null && name.isNotEmpty) return name;
    final isTeammate = getIsTeammate?.call() ?? false;
    return isTeammate ? 'teammate' : teamLeadName;
  }

  /// Find a teammate's color by name.
  String? _findTeammateColor(TeamContext? teamContext, String name) {
    if (teamContext == null) return null;
    for (final teammate in teamContext.teammates.values) {
      if (teammate.name == name) return teammate.color;
    }
    return null;
  }
}
