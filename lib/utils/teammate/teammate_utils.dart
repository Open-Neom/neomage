// Teammate utilities — port of neomage teammate.ts + teammateMailbox.ts +
// teammateContext.ts + teamDiscovery.ts + teamMemoryOps.ts.
// Agent swarm coordination: identity resolution, mailbox messaging,
// in-process teammate context, team discovery, and team memory operations.

import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

// ═══════════════════════════════════════════════════════════════════════════
// Part 1 — TeammateContext (from teammateContext.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Runtime context for in-process teammates.
/// Stored in a zone-based context for concurrent access (Dart equivalent of
/// AsyncLocalStorage).
class TeammateContext {
  TeammateContext({
    required this.agentId,
    required this.agentName,
    required this.teamName,
    this.color,
    required this.planModeRequired,
    required this.parentSessionId,
    required this.isInProcess,
    this.abortController,
  });

  /// Full agent ID, e.g. "researcher@my-team".
  final String agentId;

  /// Display name, e.g. "researcher".
  final String agentName;

  /// Team name this teammate belongs to.
  final String teamName;

  /// UI colour assigned to this teammate.
  final String? color;

  /// Whether teammate must enter plan mode before implementing.
  final bool planModeRequired;

  /// Leader's session ID (for transcript correlation).
  final String parentSessionId;

  /// Discriminator — always true for in-process teammates.
  final bool isInProcess;

  /// Optional abort controller for lifecycle management.
  final Completer<void>? abortController;
}

/// Zone key used to store the current [TeammateContext].
const Symbol _teammateContextKey = #teammateContext;

/// Get the current in-process teammate context, if running as one.
/// Returns `null` if not running within an in-process teammate context.
TeammateContext? getTeammateContext() {
  return Zone.current[_teammateContextKey] as TeammateContext?;
}

/// Run [fn] with [context] set as the current teammate context.
/// Dart equivalent of `AsyncLocalStorage.run()`.
T runWithTeammateContext<T>(TeammateContext context, T Function() fn) {
  return runZoned(fn, zoneValues: {_teammateContextKey: context});
}

/// Check if current execution is within an in-process teammate.
bool isInProcessTeammate() {
  return getTeammateContext() != null;
}

/// Create a [TeammateContext] from spawn configuration.
TeammateContext createTeammateContext({
  required String agentId,
  required String agentName,
  required String teamName,
  String? color,
  required bool planModeRequired,
  required String parentSessionId,
  Completer<void>? abortController,
}) {
  return TeammateContext(
    agentId: agentId,
    agentName: agentName,
    teamName: teamName,
    color: color,
    planModeRequired: planModeRequired,
    parentSessionId: parentSessionId,
    isInProcess: true,
    abortController: abortController,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 2 — Dynamic team context (from teammate.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Dynamic team context for runtime team joining.
class DynamicTeamContext {
  DynamicTeamContext({
    required this.agentId,
    required this.agentName,
    required this.teamName,
    this.color,
    required this.planModeRequired,
    this.parentSessionId,
  });

  final String agentId;
  final String agentName;
  final String teamName;
  final String? color;
  final bool planModeRequired;
  final String? parentSessionId;
}

/// Module-level dynamic team context (set when joining a team at runtime).
DynamicTeamContext? _dynamicTeamContext;

/// Set the dynamic team context (called when joining a team at runtime).
void setDynamicTeamContext(DynamicTeamContext? context) {
  _dynamicTeamContext = context;
}

/// Clear the dynamic team context (called when leaving a team).
void clearDynamicTeamContext() {
  _dynamicTeamContext = null;
}

/// Get the current dynamic team context (for inspection / debugging).
DynamicTeamContext? getDynamicTeamContext() => _dynamicTeamContext;

/// Returns the parent session ID for this teammate.
/// Priority: AsyncLocalStorage (in-process) > dynamicTeamContext (tmux).
String? getParentSessionId() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.parentSessionId;
  return _dynamicTeamContext?.parentSessionId;
}

/// Returns the agent ID if this session is running as a teammate in a swarm,
/// or `null` if running as a standalone session.
String? getAgentId() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.agentId;
  return _dynamicTeamContext?.agentId;
}

/// Returns the agent name if running as a teammate in a swarm.
String? getAgentName() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.agentName;
  return _dynamicTeamContext?.agentName;
}

/// Returns the team name if this session is part of a team.
/// Pass [teamContext] from AppState to support leaders without dynamicTeamContext.
String? getTeamName({String? teamContextTeamName}) {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.teamName;
  if (_dynamicTeamContext?.teamName != null &&
      _dynamicTeamContext!.teamName.isNotEmpty) {
    return _dynamicTeamContext!.teamName;
  }
  return teamContextTeamName;
}

/// Returns `true` if this session is running as a teammate in a swarm.
bool isTeammate() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return true;
  return (_dynamicTeamContext?.agentId != null &&
      _dynamicTeamContext!.agentId.isNotEmpty &&
      _dynamicTeamContext?.teamName != null &&
      _dynamicTeamContext!.teamName.isNotEmpty);
}

/// Returns the teammate's assigned colour, or `null`.
String? getTeammateColor() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.color;
  return _dynamicTeamContext?.color;
}

/// Returns `true` if this teammate session requires plan mode before
/// implementation.
bool isPlanModeRequired() {
  final inProcessCtx = getTeammateContext();
  if (inProcessCtx != null) return inProcessCtx.planModeRequired;
  if (_dynamicTeamContext != null) return _dynamicTeamContext!.planModeRequired;
  return _isEnvTruthy(Platform.environment['MAGE_PLAN_MODE_REQUIRED']);
}

/// Check if this session is a team lead.
bool isTeamLead({String? leadAgentId}) {
  if (leadAgentId == null || leadAgentId.isEmpty) return false;

  final myAgentId = getAgentId();

  // If my agent ID matches the lead agent ID, I'm the lead.
  if (myAgentId == leadAgentId) return true;

  // Backwards compat: if no agent ID is set and we have a team context,
  // this is the original session that created the team (the lead).
  if (myAgentId == null) return true;

  return false;
}

/// Representation of an in-process teammate task.
class InProcessTeammateTask {
  InProcessTeammateTask({
    required this.type,
    required this.status,
    this.isIdle = false,
    List<void Function()>? onIdleCallbacks,
  }) : onIdleCallbacks = onIdleCallbacks ?? [];

  final String type;
  final String status;
  final bool isIdle;
  final List<void Function()> onIdleCallbacks;
}

/// Checks if there are any active in-process teammates running.
bool hasActiveInProcessTeammates(Map<String, InProcessTeammateTask> tasks) {
  for (final task in tasks.values) {
    if (task.type == 'in_process_teammate' && task.status == 'running') {
      return true;
    }
  }
  return false;
}

/// Checks if there are in-process teammates still actively working on tasks.
bool hasWorkingInProcessTeammates(Map<String, InProcessTeammateTask> tasks) {
  for (final task in tasks.values) {
    if (task.type == 'in_process_teammate' &&
        task.status == 'running' &&
        !task.isIdle) {
      return true;
    }
  }
  return false;
}

/// Returns a future that completes when all working in-process teammates
/// become idle. Returns immediately if no teammates are working.
Future<void> waitForTeammatesToBecomeIdle(
  Map<String, InProcessTeammateTask> tasks,
  void Function(
    Map<String, InProcessTeammateTask> Function(
      Map<String, InProcessTeammateTask>,
    )
    updateFn,
  )
  setTasks,
) async {
  final workingTaskIds = <String>[];

  for (final entry in tasks.entries) {
    final task = entry.value;
    if (task.type == 'in_process_teammate' &&
        task.status == 'running' &&
        !task.isIdle) {
      workingTaskIds.add(entry.key);
    }
  }

  if (workingTaskIds.isEmpty) return;

  final completer = Completer<void>();
  var remaining = workingTaskIds.length;

  void onIdle() {
    remaining--;
    if (remaining == 0 && !completer.isCompleted) {
      completer.complete();
    }
  }

  setTasks((prevTasks) {
    final newTasks = Map<String, InProcessTeammateTask>.from(prevTasks);
    for (final taskId in workingTaskIds) {
      final task = newTasks[taskId];
      if (task != null && task.type == 'in_process_teammate') {
        if (task.isIdle) {
          onIdle();
        } else {
          newTasks[taskId] = InProcessTeammateTask(
            type: task.type,
            status: task.status,
            isIdle: task.isIdle,
            onIdleCallbacks: [...task.onIdleCallbacks, onIdle],
          );
        }
      }
    }
    return newTasks;
  });

  return completer.future;
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 3 — Teammate Mailbox (from teammateMailbox.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// A message stored in a teammate's inbox file.
class TeammateMessage {
  TeammateMessage({
    required this.from,
    required this.text,
    required this.timestamp,
    required this.read,
    this.color,
    this.summary,
  });

  factory TeammateMessage.fromJson(Map<String, dynamic> json) {
    return TeammateMessage(
      from: json['from'] as String? ?? '',
      text: json['text'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      read: json['read'] as bool? ?? false,
      color: json['color'] as String?,
      summary: json['summary'] as String?,
    );
  }

  final String from;
  final String text;
  final String timestamp;
  final bool read;
  final String? color;
  final String? summary;

  Map<String, dynamic> toJson() => {
    'from': from,
    'text': text,
    'timestamp': timestamp,
    'read': read,
    if (color != null) 'color': color,
    if (summary != null) 'summary': summary,
  };

  TeammateMessage copyWith({bool? read}) {
    return TeammateMessage(
      from: from,
      text: text,
      timestamp: timestamp,
      read: read ?? this.read,
      color: color,
      summary: summary,
    );
  }
}

/// XML tag used for teammate messages.
const String teammateMessageTag = 'teammate_message';

/// Team lead agent name constant.
const String teamLeadName = 'team-lead';

/// Lock retry options.
const int _lockRetries = 10;
const int _lockMinTimeout = 5;
const int _lockMaxTimeout = 100;

/// Sanitize a path component (replace unsafe chars with underscores).
String _sanitizePathComponent(String component) {
  return component.replaceAll(RegExp(r'[^\w\-.]'), '_');
}

/// Get the teams directory from env or default.
String _getTeamsDir() {
  return Platform.environment['MAGE_TEAMS_DIR'] ??
      p.join(Platform.environment['HOME'] ?? '.', '.neomage', 'teams');
}

/// Get the path to a teammate's inbox file.
String getInboxPath(String agentName, {String? teamName}) {
  final team = teamName ?? getTeamName() ?? 'default';
  final safeTeam = _sanitizePathComponent(team);
  final safeAgentName = _sanitizePathComponent(agentName);
  final inboxDir = p.join(_getTeamsDir(), safeTeam, 'inboxes');
  return p.join(inboxDir, '$safeAgentName.json');
}

/// Ensure the inbox directory exists for a team.
Future<void> _ensureInboxDir({String? teamName}) async {
  final team = teamName ?? getTeamName() ?? 'default';
  final safeTeam = _sanitizePathComponent(team);
  final inboxDir = p.join(_getTeamsDir(), safeTeam, 'inboxes');
  await Directory(inboxDir).create(recursive: true);
}

/// Read all messages from a teammate's inbox.
Future<List<TeammateMessage>> readMailbox(
  String agentName, {
  String? teamName,
}) async {
  final inboxPath = getInboxPath(agentName, teamName: teamName);
  try {
    final content = await File(inboxPath).readAsString();
    final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
    return decoded
        .map((e) => TeammateMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  } on PathNotFoundException {
    return [];
  } catch (e) {
    // Log but don't crash.
    return [];
  }
}

/// Read only unread messages from a teammate's inbox.
Future<List<TeammateMessage>> readUnreadMessages(
  String agentName, {
  String? teamName,
}) async {
  final messages = await readMailbox(agentName, teamName: teamName);
  return messages.where((m) => !m.read).toList();
}

/// Write a message to a teammate's inbox.
/// Uses file locking via a .lock file sentinel to prevent race conditions.
Future<void> writeToMailbox(
  String recipientName,
  TeammateMessage message, {
  String? teamName,
}) async {
  await _ensureInboxDir(teamName: teamName);

  final inboxPath = getInboxPath(recipientName, teamName: teamName);
  final lockFilePath = '$inboxPath.lock';

  // Ensure the inbox file exists before locking.
  final inboxFile = File(inboxPath);
  if (!inboxFile.existsSync()) {
    try {
      await inboxFile.writeAsString('[]');
    } catch (_) {}
  }

  final lock = File(lockFilePath);
  try {
    await _acquireLock(lock);

    final messages = await readMailbox(recipientName, teamName: teamName);
    final newMessage = TeammateMessage(
      from: message.from,
      text: message.text,
      timestamp: message.timestamp,
      read: false,
      color: message.color,
      summary: message.summary,
    );
    messages.add(newMessage);

    final encoder = const JsonEncoder.withIndent('  ');
    await inboxFile.writeAsString(
      encoder.convert(messages.map((m) => m.toJson()).toList()),
    );
  } catch (e) {
    // Silently fail — the message will be lost but the process continues.
  } finally {
    await _releaseLock(lock);
  }
}

/// Mark a specific message as read by index.
Future<void> markMessageAsReadByIndex(
  String agentName,
  int messageIndex, {
  String? teamName,
}) async {
  final inboxPath = getInboxPath(agentName, teamName: teamName);
  final lockFilePath = '$inboxPath.lock';
  final lock = File(lockFilePath);

  try {
    await _acquireLock(lock);

    final messages = await readMailbox(agentName, teamName: teamName);
    if (messageIndex < 0 || messageIndex >= messages.length) return;

    final msg = messages[messageIndex];
    if (msg.read) return;

    messages[messageIndex] = msg.copyWith(read: true);

    final encoder = const JsonEncoder.withIndent('  ');
    await File(
      inboxPath,
    ).writeAsString(encoder.convert(messages.map((m) => m.toJson()).toList()));
  } on PathNotFoundException {
    return;
  } catch (_) {
    // Silently fail.
  } finally {
    await _releaseLock(lock);
  }
}

/// Mark all messages in a teammate's inbox as read.
Future<void> markMessagesAsRead(String agentName, {String? teamName}) async {
  final inboxPath = getInboxPath(agentName, teamName: teamName);
  final lockFilePath = '$inboxPath.lock';
  final lock = File(lockFilePath);

  try {
    await _acquireLock(lock);

    final messages = await readMailbox(agentName, teamName: teamName);
    if (messages.isEmpty) return;

    final updated = messages.map((m) => m.copyWith(read: true)).toList();

    final encoder = const JsonEncoder.withIndent('  ');
    await File(
      inboxPath,
    ).writeAsString(encoder.convert(updated.map((m) => m.toJson()).toList()));
  } on PathNotFoundException {
    return;
  } catch (_) {
    // Silently fail.
  } finally {
    await _releaseLock(lock);
  }
}

/// Clear a teammate's inbox (delete all messages).
Future<void> clearMailbox(String agentName, {String? teamName}) async {
  final inboxPath = getInboxPath(agentName, teamName: teamName);
  try {
    await File(inboxPath).writeAsString('[]');
  } on PathNotFoundException {
    return;
  } catch (_) {}
}

/// Format teammate messages as XML for attachment display.
String formatTeammateMessages(List<TeammateMessage> messages) {
  return messages
      .map((m) {
        final colorAttr = m.color != null ? ' color="${m.color}"' : '';
        final summaryAttr = m.summary != null ? ' summary="${m.summary}"' : '';
        return '<$teammateMessageTag teammate_id="${m.from}"$colorAttr$summaryAttr>\n${m.text}\n</$teammateMessageTag>';
      })
      .join('\n\n');
}

/// Mark messages matching [predicate] as read, leaving others unread.
Future<void> markMessagesAsReadByPredicate(
  String agentName,
  bool Function(TeammateMessage) predicate, {
  String? teamName,
}) async {
  final inboxPath = getInboxPath(agentName, teamName: teamName);
  final lockFilePath = '$inboxPath.lock';
  final lock = File(lockFilePath);

  try {
    await _acquireLock(lock);

    final messages = await readMailbox(agentName, teamName: teamName);
    if (messages.isEmpty) return;

    final updated = messages.map((m) {
      if (!m.read && predicate(m)) return m.copyWith(read: true);
      return m;
    }).toList();

    final encoder = const JsonEncoder.withIndent('  ');
    await File(
      inboxPath,
    ).writeAsString(encoder.convert(updated.map((m) => m.toJson()).toList()));
  } on PathNotFoundException {
    return;
  } catch (_) {
  } finally {
    await _releaseLock(lock);
  }
}

// ── Idle notification messages ──

/// Structured message sent when a teammate becomes idle.
class IdleNotificationMessage {
  IdleNotificationMessage({
    required this.from,
    required this.timestamp,
    this.idleReason,
    this.summary,
    this.completedTaskId,
    this.completedStatus,
    this.failureReason,
  });

  factory IdleNotificationMessage.fromJson(Map<String, dynamic> json) {
    return IdleNotificationMessage(
      from: json['from'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      idleReason: json['idleReason'] as String?,
      summary: json['summary'] as String?,
      completedTaskId: json['completedTaskId'] as String?,
      completedStatus: json['completedStatus'] as String?,
      failureReason: json['failureReason'] as String?,
    );
  }

  static const String messageType = 'idle_notification';

  final String from;
  final String timestamp;
  final String? idleReason; // 'available' | 'interrupted' | 'failed'
  final String? summary;
  final String? completedTaskId;
  final String? completedStatus; // 'resolved' | 'blocked' | 'failed'
  final String? failureReason;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'from': from,
    'timestamp': timestamp,
    if (idleReason != null) 'idleReason': idleReason,
    if (summary != null) 'summary': summary,
    if (completedTaskId != null) 'completedTaskId': completedTaskId,
    if (completedStatus != null) 'completedStatus': completedStatus,
    if (failureReason != null) 'failureReason': failureReason,
  };
}

/// Creates an idle notification message to send to the team leader.
IdleNotificationMessage createIdleNotification(
  String agentId, {
  String? idleReason,
  String? summary,
  String? completedTaskId,
  String? completedStatus,
  String? failureReason,
}) {
  return IdleNotificationMessage(
    from: agentId,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    idleReason: idleReason,
    summary: summary,
    completedTaskId: completedTaskId,
    completedStatus: completedStatus,
    failureReason: failureReason,
  );
}

/// Checks if a message text contains an idle notification.
IdleNotificationMessage? isIdleNotification(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == IdleNotificationMessage.messageType) {
      return IdleNotificationMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Permission request / response messages ──

/// Permission request from worker to leader via mailbox.
class PermissionRequestMessage {
  PermissionRequestMessage({
    required this.requestId,
    required this.agentId,
    required this.toolName,
    required this.toolUseId,
    required this.description,
    required this.input,
    this.permissionSuggestions = const [],
  });

  factory PermissionRequestMessage.fromJson(Map<String, dynamic> json) {
    return PermissionRequestMessage(
      requestId: json['request_id'] as String? ?? '',
      agentId: json['agent_id'] as String? ?? '',
      toolName: json['tool_name'] as String? ?? '',
      toolUseId: json['tool_use_id'] as String? ?? '',
      description: json['description'] as String? ?? '',
      input: json['input'] as Map<String, dynamic>? ?? {},
      permissionSuggestions:
          (json['permission_suggestions'] as List<dynamic>?) ?? [],
    );
  }

  static const String messageType = 'permission_request';

  final String requestId;
  final String agentId;
  final String toolName;
  final String toolUseId;
  final String description;
  final Map<String, dynamic> input;
  final List<dynamic> permissionSuggestions;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'request_id': requestId,
    'agent_id': agentId,
    'tool_name': toolName,
    'tool_use_id': toolUseId,
    'description': description,
    'input': input,
    'permission_suggestions': permissionSuggestions,
  };
}

/// Permission response from leader to worker.
sealed class PermissionResponseMessage {
  PermissionResponseMessage({required this.requestId});

  static const String messageType = 'permission_response';
  final String requestId;
}

class PermissionResponseSuccess extends PermissionResponseMessage {
  PermissionResponseSuccess({
    required super.requestId,
    this.updatedInput,
    this.permissionUpdates,
  });

  final Map<String, dynamic>? updatedInput;
  final List<dynamic>? permissionUpdates;

  Map<String, dynamic> toJson() => {
    'type': PermissionResponseMessage.messageType,
    'request_id': requestId,
    'subtype': 'success',
    'response': {
      if (updatedInput != null) 'updated_input': updatedInput,
      if (permissionUpdates != null) 'permission_updates': permissionUpdates,
    },
  };
}

class PermissionResponseError extends PermissionResponseMessage {
  PermissionResponseError({required super.requestId, required this.error});

  final String error;

  Map<String, dynamic> toJson() => {
    'type': PermissionResponseMessage.messageType,
    'request_id': requestId,
    'subtype': 'error',
    'error': error,
  };
}

/// Creates a permission request message.
PermissionRequestMessage createPermissionRequestMessage({
  required String requestId,
  required String agentId,
  required String toolName,
  required String toolUseId,
  required String description,
  required Map<String, dynamic> input,
  List<dynamic>? permissionSuggestions,
}) {
  return PermissionRequestMessage(
    requestId: requestId,
    agentId: agentId,
    toolName: toolName,
    toolUseId: toolUseId,
    description: description,
    input: input,
    permissionSuggestions: permissionSuggestions ?? [],
  );
}

/// Creates a permission response message.
PermissionResponseMessage createPermissionResponseMessage({
  required String requestId,
  required String subtype,
  String? error,
  Map<String, dynamic>? updatedInput,
  List<dynamic>? permissionUpdates,
}) {
  if (subtype == 'error') {
    return PermissionResponseError(
      requestId: requestId,
      error: error ?? 'Permission denied',
    );
  }
  return PermissionResponseSuccess(
    requestId: requestId,
    updatedInput: updatedInput,
    permissionUpdates: permissionUpdates,
  );
}

/// Checks if a message text contains a permission request.
PermissionRequestMessage? isPermissionRequest(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == PermissionRequestMessage.messageType) {
      return PermissionRequestMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Checks if a message text contains a permission response.
PermissionResponseMessage? isPermissionResponse(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == PermissionResponseMessage.messageType) {
      final subtype = parsed['subtype'] as String?;
      if (subtype == 'error') {
        return PermissionResponseError(
          requestId: parsed['request_id'] as String? ?? '',
          error: parsed['error'] as String? ?? '',
        );
      }
      final resp = parsed['response'] as Map<String, dynamic>?;
      return PermissionResponseSuccess(
        requestId: parsed['request_id'] as String? ?? '',
        updatedInput: resp?['updated_input'] as Map<String, dynamic>?,
        permissionUpdates: resp?['permission_updates'] as List<dynamic>?,
      );
    }
  } catch (_) {}
  return null;
}

// ── Sandbox permission request / response ──

/// Sandbox permission request from worker to leader.
class SandboxPermissionRequestMessage {
  SandboxPermissionRequestMessage({
    required this.requestId,
    required this.workerId,
    required this.workerName,
    this.workerColor,
    required this.hostPattern,
    required this.createdAt,
  });

  factory SandboxPermissionRequestMessage.fromJson(Map<String, dynamic> json) {
    return SandboxPermissionRequestMessage(
      requestId: json['requestId'] as String? ?? '',
      workerId: json['workerId'] as String? ?? '',
      workerName: json['workerName'] as String? ?? '',
      workerColor: json['workerColor'] as String?,
      hostPattern: json['hostPattern'] as Map<String, dynamic>? ?? {},
      createdAt: json['createdAt'] as int? ?? 0,
    );
  }

  static const String messageType = 'sandbox_permission_request';

  final String requestId;
  final String workerId;
  final String workerName;
  final String? workerColor;
  final Map<String, dynamic> hostPattern;
  final int createdAt;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'workerId': workerId,
    'workerName': workerName,
    if (workerColor != null) 'workerColor': workerColor,
    'hostPattern': hostPattern,
    'createdAt': createdAt,
  };
}

/// Sandbox permission response from leader to worker.
class SandboxPermissionResponseMessage {
  SandboxPermissionResponseMessage({
    required this.requestId,
    required this.host,
    required this.allow,
    required this.timestamp,
  });

  factory SandboxPermissionResponseMessage.fromJson(Map<String, dynamic> json) {
    return SandboxPermissionResponseMessage(
      requestId: json['requestId'] as String? ?? '',
      host: json['host'] as String? ?? '',
      allow: json['allow'] as bool? ?? false,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  static const String messageType = 'sandbox_permission_response';

  final String requestId;
  final String host;
  final bool allow;
  final String timestamp;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'host': host,
    'allow': allow,
    'timestamp': timestamp,
  };
}

/// Creates a sandbox permission request.
SandboxPermissionRequestMessage createSandboxPermissionRequestMessage({
  required String requestId,
  required String workerId,
  required String workerName,
  String? workerColor,
  required String host,
}) {
  return SandboxPermissionRequestMessage(
    requestId: requestId,
    workerId: workerId,
    workerName: workerName,
    workerColor: workerColor,
    hostPattern: {'host': host},
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );
}

/// Creates a sandbox permission response.
SandboxPermissionResponseMessage createSandboxPermissionResponseMessage({
  required String requestId,
  required String host,
  required bool allow,
}) {
  return SandboxPermissionResponseMessage(
    requestId: requestId,
    host: host,
    allow: allow,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );
}

/// Checks if a message text contains a sandbox permission request.
SandboxPermissionRequestMessage? isSandboxPermissionRequest(
  String messageText,
) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == SandboxPermissionRequestMessage.messageType) {
      return SandboxPermissionRequestMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Checks if a message text contains a sandbox permission response.
SandboxPermissionResponseMessage? isSandboxPermissionResponse(
  String messageText,
) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == SandboxPermissionResponseMessage.messageType) {
      return SandboxPermissionResponseMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Shutdown messages ──

/// Shutdown request from leader to teammate.
class ShutdownRequestMessage {
  ShutdownRequestMessage({
    required this.requestId,
    required this.from,
    this.reason,
    required this.timestamp,
  });

  factory ShutdownRequestMessage.fromJson(Map<String, dynamic> json) {
    return ShutdownRequestMessage(
      requestId: json['requestId'] as String? ?? '',
      from: json['from'] as String? ?? '',
      reason: json['reason'] as String?,
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  static const String messageType = 'shutdown_request';

  final String requestId;
  final String from;
  final String? reason;
  final String timestamp;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'from': from,
    if (reason != null) 'reason': reason,
    'timestamp': timestamp,
  };
}

/// Shutdown approved from teammate to leader.
class ShutdownApprovedMessage {
  ShutdownApprovedMessage({
    required this.requestId,
    required this.from,
    required this.timestamp,
    this.paneId,
    this.backendType,
  });

  factory ShutdownApprovedMessage.fromJson(Map<String, dynamic> json) {
    return ShutdownApprovedMessage(
      requestId: json['requestId'] as String? ?? '',
      from: json['from'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      paneId: json['paneId'] as String?,
      backendType: json['backendType'] as String?,
    );
  }

  static const String messageType = 'shutdown_approved';

  final String requestId;
  final String from;
  final String timestamp;
  final String? paneId;
  final String? backendType;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'from': from,
    'timestamp': timestamp,
    if (paneId != null) 'paneId': paneId,
    if (backendType != null) 'backendType': backendType,
  };
}

/// Shutdown rejected from teammate to leader.
class ShutdownRejectedMessage {
  ShutdownRejectedMessage({
    required this.requestId,
    required this.from,
    required this.reason,
    required this.timestamp,
  });

  factory ShutdownRejectedMessage.fromJson(Map<String, dynamic> json) {
    return ShutdownRejectedMessage(
      requestId: json['requestId'] as String? ?? '',
      from: json['from'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  static const String messageType = 'shutdown_rejected';

  final String requestId;
  final String from;
  final String reason;
  final String timestamp;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'from': from,
    'reason': reason,
    'timestamp': timestamp,
  };
}

/// Creates a shutdown request message.
ShutdownRequestMessage createShutdownRequestMessage({
  required String requestId,
  required String from,
  String? reason,
}) {
  return ShutdownRequestMessage(
    requestId: requestId,
    from: from,
    reason: reason,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );
}

/// Creates a shutdown approved message.
ShutdownApprovedMessage createShutdownApprovedMessage({
  required String requestId,
  required String from,
  String? paneId,
  String? backendType,
}) {
  return ShutdownApprovedMessage(
    requestId: requestId,
    from: from,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    paneId: paneId,
    backendType: backendType,
  );
}

/// Creates a shutdown rejected message.
ShutdownRejectedMessage createShutdownRejectedMessage({
  required String requestId,
  required String from,
  required String reason,
}) {
  return ShutdownRejectedMessage(
    requestId: requestId,
    from: from,
    reason: reason,
    timestamp: DateTime.now().toUtc().toIso8601String(),
  );
}

/// Sends a shutdown request to a teammate's mailbox.
Future<({String requestId, String target})> sendShutdownRequestToMailbox(
  String targetName, {
  String? teamName,
  String? reason,
}) async {
  final resolvedTeamName = teamName ?? getTeamName();
  final senderName = getAgentName() ?? teamLeadName;
  final requestId =
      'shutdown-$targetName-${DateTime.now().millisecondsSinceEpoch}';

  final shutdownMessage = createShutdownRequestMessage(
    requestId: requestId,
    from: senderName,
    reason: reason,
  );

  await writeToMailbox(
    targetName,
    TeammateMessage(
      from: senderName,
      text: jsonEncode(shutdownMessage.toJson()),
      timestamp: DateTime.now().toUtc().toIso8601String(),
      read: false,
      color: getTeammateColor(),
    ),
    teamName: resolvedTeamName,
  );

  return (requestId: requestId, target: targetName);
}

/// Checks if a message text contains a shutdown request.
ShutdownRequestMessage? isShutdownRequest(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == ShutdownRequestMessage.messageType) {
      return ShutdownRequestMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Checks if a message text contains a shutdown approved message.
ShutdownApprovedMessage? isShutdownApproved(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == ShutdownApprovedMessage.messageType) {
      return ShutdownApprovedMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Checks if a message text contains a shutdown rejected message.
ShutdownRejectedMessage? isShutdownRejected(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == ShutdownRejectedMessage.messageType) {
      return ShutdownRejectedMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Plan approval messages ──

/// Plan approval request from teammate to leader.
class PlanApprovalRequestMessage {
  PlanApprovalRequestMessage({
    required this.from,
    required this.timestamp,
    required this.planFilePath,
    required this.planContent,
    required this.requestId,
  });

  factory PlanApprovalRequestMessage.fromJson(Map<String, dynamic> json) {
    return PlanApprovalRequestMessage(
      from: json['from'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
      planFilePath: json['planFilePath'] as String? ?? '',
      planContent: json['planContent'] as String? ?? '',
      requestId: json['requestId'] as String? ?? '',
    );
  }

  static const String messageType = 'plan_approval_request';

  final String from;
  final String timestamp;
  final String planFilePath;
  final String planContent;
  final String requestId;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'from': from,
    'timestamp': timestamp,
    'planFilePath': planFilePath,
    'planContent': planContent,
    'requestId': requestId,
  };
}

/// Plan approval response from leader to teammate.
class PlanApprovalResponseMessage {
  PlanApprovalResponseMessage({
    required this.requestId,
    required this.approved,
    this.feedback,
    required this.timestamp,
    this.permissionMode,
  });

  factory PlanApprovalResponseMessage.fromJson(Map<String, dynamic> json) {
    return PlanApprovalResponseMessage(
      requestId: json['requestId'] as String? ?? '',
      approved: json['approved'] as bool? ?? false,
      feedback: json['feedback'] as String?,
      timestamp: json['timestamp'] as String? ?? '',
      permissionMode: json['permissionMode'] as String?,
    );
  }

  static const String messageType = 'plan_approval_response';

  final String requestId;
  final bool approved;
  final String? feedback;
  final String timestamp;
  final String? permissionMode;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'requestId': requestId,
    'approved': approved,
    if (feedback != null) 'feedback': feedback,
    'timestamp': timestamp,
    if (permissionMode != null) 'permissionMode': permissionMode,
  };
}

/// Checks if a message text contains a plan approval request.
PlanApprovalRequestMessage? isPlanApprovalRequest(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == PlanApprovalRequestMessage.messageType) {
      return PlanApprovalRequestMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Checks if a message text contains a plan approval response.
PlanApprovalResponseMessage? isPlanApprovalResponse(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == PlanApprovalResponseMessage.messageType) {
      return PlanApprovalResponseMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Task assignment ──

/// Task assignment message.
class TaskAssignmentMessage {
  TaskAssignmentMessage({
    required this.taskId,
    required this.subject,
    required this.description,
    required this.assignedBy,
    required this.timestamp,
  });

  factory TaskAssignmentMessage.fromJson(Map<String, dynamic> json) {
    return TaskAssignmentMessage(
      taskId: json['taskId'] as String? ?? '',
      subject: json['subject'] as String? ?? '',
      description: json['description'] as String? ?? '',
      assignedBy: json['assignedBy'] as String? ?? '',
      timestamp: json['timestamp'] as String? ?? '',
    );
  }

  static const String messageType = 'task_assignment';

  final String taskId;
  final String subject;
  final String description;
  final String assignedBy;
  final String timestamp;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'taskId': taskId,
    'subject': subject,
    'description': description,
    'assignedBy': assignedBy,
    'timestamp': timestamp,
  };
}

/// Checks if a message text contains a task assignment.
TaskAssignmentMessage? isTaskAssignment(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == TaskAssignmentMessage.messageType) {
      return TaskAssignmentMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Team permission update ──

/// Team permission update from leader to teammates.
class TeamPermissionUpdateMessage {
  TeamPermissionUpdateMessage({
    required this.permissionUpdate,
    required this.directoryPath,
    required this.toolName,
  });

  factory TeamPermissionUpdateMessage.fromJson(Map<String, dynamic> json) {
    return TeamPermissionUpdateMessage(
      permissionUpdate: json['permissionUpdate'] as Map<String, dynamic>? ?? {},
      directoryPath: json['directoryPath'] as String? ?? '',
      toolName: json['toolName'] as String? ?? '',
    );
  }

  static const String messageType = 'team_permission_update';

  final Map<String, dynamic> permissionUpdate;
  final String directoryPath;
  final String toolName;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'permissionUpdate': permissionUpdate,
    'directoryPath': directoryPath,
    'toolName': toolName,
  };
}

/// Checks if a message text contains a team permission update.
TeamPermissionUpdateMessage? isTeamPermissionUpdate(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == TeamPermissionUpdateMessage.messageType) {
      return TeamPermissionUpdateMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

// ── Mode set request ──

/// Mode set request from leader to teammate.
class ModeSetRequestMessage {
  ModeSetRequestMessage({required this.mode, required this.from});

  factory ModeSetRequestMessage.fromJson(Map<String, dynamic> json) {
    return ModeSetRequestMessage(
      mode: json['mode'] as String? ?? '',
      from: json['from'] as String? ?? '',
    );
  }

  static const String messageType = 'mode_set_request';

  final String mode;
  final String from;

  Map<String, dynamic> toJson() => {
    'type': messageType,
    'mode': mode,
    'from': from,
  };
}

/// Creates a mode set request message.
ModeSetRequestMessage createModeSetRequestMessage({
  required String mode,
  required String from,
}) {
  return ModeSetRequestMessage(mode: mode, from: from);
}

/// Checks if a message text contains a mode set request.
ModeSetRequestMessage? isModeSetRequest(String messageText) {
  try {
    final parsed = jsonDecode(messageText) as Map<String, dynamic>;
    if (parsed['type'] == ModeSetRequestMessage.messageType) {
      return ModeSetRequestMessage.fromJson(parsed);
    }
  } catch (_) {}
  return null;
}

/// Set of structured protocol message types that should be routed by the
/// inbox poller rather than consumed as raw LLM context.
const Set<String> _structuredProtocolTypes = {
  'permission_request',
  'permission_response',
  'sandbox_permission_request',
  'sandbox_permission_response',
  'shutdown_request',
  'shutdown_approved',
  'team_permission_update',
  'mode_set_request',
  'plan_approval_request',
  'plan_approval_response',
};

/// Checks if a message text is a structured protocol message.
bool isStructuredProtocolMessage(String messageText) {
  try {
    final parsed = jsonDecode(messageText);
    if (parsed is Map<String, dynamic> && parsed.containsKey('type')) {
      return _structuredProtocolTypes.contains(parsed['type']);
    }
  } catch (_) {}
  return false;
}

/// Extracts a "[to {name}] {summary}" string from the last assistant message
/// if it ended with a SendMessage tool_use targeting a peer.
String? getLastPeerDmSummary(List<Map<String, dynamic>> messages) {
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];

    // Stop at wake-up boundary: a user prompt (string content).
    if (msg['type'] == 'user' && msg['message']?['content'] is String) {
      break;
    }

    if (msg['type'] != 'assistant') continue;
    final content = msg['message']?['content'];
    if (content is! List) continue;

    for (final block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'tool_use' &&
          block['name'] == 'SendMessage') {
        final input = block['input'];
        if (input is Map<String, dynamic>) {
          final to = input['to'] as String?;
          if (to != null &&
              to != '*' &&
              to.toLowerCase() != teamLeadName.toLowerCase()) {
            final message = input['message'] as String?;
            if (message != null) {
              final summary = (input['summary'] is String)
                  ? input['summary'] as String
                  : message.length > 80
                  ? message.substring(0, 80)
                  : message;
              return '[to $to] $summary';
            }
          }
        }
      }
    }
  }
  return null;
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 4 — Team Discovery (from teamDiscovery.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Summary info about a team.
class TeamSummary {
  TeamSummary({
    required this.name,
    required this.memberCount,
    required this.runningCount,
    required this.idleCount,
  });

  final String name;
  final int memberCount;
  final int runningCount;
  final int idleCount;
}

/// Backend type for a pane (tmux, ssh, etc).
typedef PaneBackendType = String;

/// Detailed status of a teammate.
class TeammateStatus {
  TeammateStatus({
    required this.name,
    required this.agentId,
    this.agentType,
    this.model,
    this.prompt,
    required this.status,
    this.color,
    this.idleSince,
    required this.tmuxPaneId,
    required this.cwd,
    this.worktreePath,
    this.isHidden,
    this.backendType,
    this.mode,
  });

  final String name;
  final String agentId;
  final String? agentType;
  final String? model;
  final String? prompt;
  final String status; // 'running' | 'idle' | 'unknown'
  final String? color;
  final String? idleSince;
  final String tmuxPaneId;
  final String cwd;
  final String? worktreePath;
  final bool? isHidden;
  final PaneBackendType? backendType;
  final String? mode;
}

/// Get detailed teammate statuses for a team by reading the team file.
List<TeammateStatus> getTeammateStatuses(
  String teamName, {
  Map<String, dynamic>? teamFileOverride,
}) {
  final teamFile = teamFileOverride ?? _readTeamFile(teamName);
  if (teamFile == null) return [];

  final hiddenPaneIds = Set<String>.from(
    (teamFile['hiddenPaneIds'] as List<dynamic>?) ?? [],
  );
  final members = (teamFile['members'] as List<dynamic>?) ?? [];
  final statuses = <TeammateStatus>[];

  for (final raw in members) {
    final member = raw as Map<String, dynamic>;
    final name = member['name'] as String? ?? '';
    if (name == teamLeadName) continue;

    final isActive = (member['isActive'] as bool?) ?? true;
    final status = isActive ? 'running' : 'idle';

    statuses.add(
      TeammateStatus(
        name: name,
        agentId: member['agentId'] as String? ?? '',
        agentType: member['agentType'] as String?,
        model: member['model'] as String?,
        prompt: member['prompt'] as String?,
        status: status,
        color: member['color'] as String?,
        tmuxPaneId: member['tmuxPaneId'] as String? ?? '',
        cwd: member['cwd'] as String? ?? '',
        worktreePath: member['worktreePath'] as String?,
        isHidden: hiddenPaneIds.contains(member['tmuxPaneId'] as String? ?? ''),
        backendType: member['backendType'] as String?,
        mode: member['mode'] as String?,
      ),
    );
  }

  return statuses;
}

/// Read a team file from disk.
Map<String, dynamic>? _readTeamFile(String teamName) {
  final safeTeam = _sanitizePathComponent(teamName);
  final filePath = p.join(_getTeamsDir(), safeTeam, 'team.json');
  try {
    final content = File(filePath).readAsStringSync();
    return jsonDecode(content) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Part 5 — Team Memory Ops (from teamMemoryOps.ts)
// ═══════════════════════════════════════════════════════════════════════════

/// Checks if a path is a team memory file.
bool isTeamMemFile(String path) {
  // Team memory files live under .neomage/teams/<team>/memory/
  return path.contains('.neomage/teams/') && path.contains('/memory/');
}

/// Check if a search tool use targets team memory files.
bool isTeamMemorySearch(Map<String, dynamic>? toolInput) {
  if (toolInput == null) return false;
  final path = toolInput['path'] as String?;
  if (path != null && isTeamMemFile(path)) return true;
  return false;
}

/// Check if a Write or Edit tool use targets a team memory file.
bool isTeamMemoryWriteOrEdit(String toolName, Map<String, dynamic>? toolInput) {
  if (toolName != 'FileWrite' && toolName != 'FileEdit') return false;
  if (toolInput == null) return false;
  final filePath =
      (toolInput['file_path'] as String?) ?? (toolInput['path'] as String?);
  return filePath != null && isTeamMemFile(filePath);
}

/// Append team memory summary parts to the parts array.
void appendTeamMemorySummaryParts(
  Map<String, int> memoryCounts,
  bool isActive,
  List<String> parts,
) {
  final teamReadCount = memoryCounts['teamMemoryReadCount'] ?? 0;
  final teamSearchCount = memoryCounts['teamMemorySearchCount'] ?? 0;
  final teamWriteCount = memoryCounts['teamMemoryWriteCount'] ?? 0;

  if (teamReadCount > 0) {
    final verb = isActive
        ? (parts.isEmpty ? 'Recalling' : 'recalling')
        : (parts.isEmpty ? 'Recalled' : 'recalled');
    final noun = teamReadCount == 1 ? 'memory' : 'memories';
    parts.add('$verb $teamReadCount team $noun');
  }
  if (teamSearchCount > 0) {
    final verb = isActive
        ? (parts.isEmpty ? 'Searching' : 'searching')
        : (parts.isEmpty ? 'Searched' : 'searched');
    parts.add('$verb team memories');
  }
  if (teamWriteCount > 0) {
    final verb = isActive
        ? (parts.isEmpty ? 'Writing' : 'writing')
        : (parts.isEmpty ? 'Wrote' : 'wrote');
    final noun = teamWriteCount == 1 ? 'memory' : 'memories';
    parts.add('$verb $teamWriteCount team $noun');
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Private helpers
// ═══════════════════════════════════════════════════════════════════════════

bool _isEnvTruthy(String? value) {
  if (value == null) return false;
  final v = value.toLowerCase().trim();
  return v == '1' || v == 'true' || v == 'yes';
}

/// Simple file-lock acquire using a sentinel file.
Future<void> _acquireLock(File lock) async {
  for (var i = 0; i < _lockRetries; i++) {
    try {
      await lock.create(exclusive: true);
      return;
    } catch (_) {
      final delay =
          _lockMinTimeout +
          (i * (_lockMaxTimeout - _lockMinTimeout) ~/ _lockRetries);
      await Future<void>.delayed(Duration(milliseconds: delay));
    }
  }
  // Last attempt.
  await lock.create(exclusive: true);
}

/// Simple file-lock release by deleting the sentinel file.
Future<void> _releaseLock(File lock) async {
  try {
    await lock.delete();
  } catch (_) {}
}
