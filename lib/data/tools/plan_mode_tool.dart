// PlanModeTool — port of NeomClaw's plan mode tools.
// EnterPlanModeTool switches to plan mode (read-only tools only).
// ExitPlanModeTool switches back to normal mode with an optional plan.

import 'dart:async';

import 'tool.dart';

// ─── Input ───────────────────────────────────────────────────────────────────

/// Input for plan mode transitions.
class PlanModeInput {
  /// One of: enter, exit.
  final String action;

  /// Plan description when entering, or plan summary when exiting.
  final String? planText;

  const PlanModeInput({required this.action, this.planText});

  factory PlanModeInput.fromMap(Map<String, dynamic> map) {
    return PlanModeInput(
      action:
          map['action'] as String? ??
          map['reason'] as String? ??
          map['plan_summary'] as String? ??
          '',
      planText:
          map['plan_text'] as String? ??
          map['reason'] as String? ??
          map['plan_summary'] as String?,
    );
  }

  List<String> validate(String expectedAction) {
    final errors = <String>[];
    if (expectedAction == 'enter' && (planText == null || planText!.isEmpty)) {
      errors.add('A reason is required when entering plan mode');
    }
    if (expectedAction == 'exit' && (planText == null || planText!.isEmpty)) {
      errors.add('A plan summary is required when exiting plan mode');
    }
    return errors;
  }
}

// ─── State ───────────────────────────────────────────────────────────────────

/// Tracks the current plan mode state across tools.
class PlanModeState {
  bool _isInPlanMode = false;
  String? _currentPlan;
  DateTime? _enteredAt;
  final List<String> _planHistory = [];

  bool get isInPlanMode => _isInPlanMode;
  String? get currentPlan => _currentPlan;
  DateTime? get enteredAt => _enteredAt;
  List<String> get planHistory => List.unmodifiable(_planHistory);

  void enterPlanMode(String reason) {
    _isInPlanMode = true;
    _currentPlan = reason;
    _enteredAt = DateTime.now();
  }

  String? exitPlanMode(String summary) {
    final plan = _currentPlan;
    if (_currentPlan != null) {
      _planHistory.add(summary);
    }
    _isInPlanMode = false;
    _currentPlan = null;
    _enteredAt = null;
    return plan;
  }

  void reset() {
    _isInPlanMode = false;
    _currentPlan = null;
    _enteredAt = null;
  }
}

// ─── Read-only tool names ────────────────────────────────────────────────────

/// Tools that remain available during plan mode (read-only).
const planModeAllowedTools = <String>{
  'Read',
  'Glob',
  'Grep',
  'WebFetch',
  'WebSearch',
  'ToolSearch',
  'TodoWrite',
  'ExitPlanMode',
};

// ─── EnterPlanModeTool ───────────────────────────────────────────────────────

/// Enter plan mode to design an implementation strategy before making changes.
///
/// When plan mode is active:
/// - Only read-only tools are available (Read, Glob, Grep, WebFetch, etc.)
/// - Write/edit/bash tools are restricted
/// - The model develops a plan before executing changes
/// - Exit plan mode to resume normal operations with a plan summary
class EnterPlanModeTool extends Tool with ReadOnlyToolMixin {
  final PlanModeState _state;

  /// Callback invoked when plan mode is entered, so the tool registry
  /// can restrict available tools.
  final void Function(bool planModeActive)? onPlanModeChanged;

  EnterPlanModeTool(this._state, {this.onPlanModeChanged});

  @override
  String get name => 'EnterPlanMode';

  @override
  String get description =>
      'Enter plan mode to design an implementation strategy before making '
      'changes. While in plan mode, only read-only tools are available.';

  @override
  String get prompt =>
      'Enter plan mode to design an implementation strategy before making '
      'changes.\n\n'
      'While in plan mode:\n'
      '- Only read-only tools are available (Read, Glob, Grep, WebFetch, '
      'WebSearch, ToolSearch, TodoWrite)\n'
      '- Write, Edit, Bash, and other modifying tools are restricted\n'
      '- Use ExitPlanMode to leave plan mode and begin execution\n\n'
      'Provide a reason for entering plan mode.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'reason': {
        'type': 'string',
        'description': 'Reason for entering plan mode',
      },
    },
    'required': ['reason'],
    'additionalProperties': false,
  };

  @override
  bool get alwaysLoad => true;

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final reason = input['reason'] as String?;
    if (reason == null || reason.isEmpty) {
      return const ValidationResult.invalid('reason is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    if (_state.isInPlanMode) {
      return ToolResult.error(
        'Already in plan mode. Use ExitPlanMode to leave.',
      );
    }

    final reason = input['reason'] as String? ?? '';
    _state.enterPlanMode(reason);
    onPlanModeChanged?.call(true);

    return ToolResult.success(
      'Entered plan mode.\n'
      'Reason: $reason\n\n'
      'Only read-only tools are now available. '
      'Use ExitPlanMode with a plan summary when ready to execute.',
    );
  }
}

// ─── ExitPlanModeTool ────────────────────────────────────────────────────────

/// Exit plan mode and optionally provide a plan to execute.
///
/// Re-enables all tools and switches back to normal execution mode.
class ExitPlanModeTool extends Tool with ReadOnlyToolMixin {
  final PlanModeState _state;

  /// Callback invoked when plan mode is exited.
  final void Function(bool planModeActive)? onPlanModeChanged;

  ExitPlanModeTool(this._state, {this.onPlanModeChanged});

  @override
  String get name => 'ExitPlanMode';

  @override
  String get description =>
      'Exit plan mode and begin executing the plan that was developed. '
      'Re-enables all tools.';

  @override
  String get prompt =>
      'Exit plan mode and begin executing the plan that was developed.\n\n'
      'Provide a summary of the plan to execute. All tools will be '
      're-enabled after exiting plan mode.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'plan_summary': {
        'type': 'string',
        'description': 'Summary of the plan to execute',
      },
    },
    'required': ['plan_summary'],
    'additionalProperties': false,
  };

  @override
  bool get alwaysLoad => true;

  @override
  ValidationResult validateInput(Map<String, dynamic> input) {
    final summary = input['plan_summary'] as String?;
    if (summary == null || summary.isEmpty) {
      return const ValidationResult.invalid('plan_summary is required');
    }
    return const ValidationResult.valid();
  }

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    if (!_state.isInPlanMode) {
      return ToolResult.error('Not in plan mode. Use EnterPlanMode first.');
    }

    final summary = input['plan_summary'] as String? ?? '';
    final enteredAt = _state.enteredAt;
    final previousPlan = _state.exitPlanMode(summary);
    onPlanModeChanged?.call(false);

    final duration = enteredAt != null
        ? DateTime.now().difference(enteredAt).inSeconds
        : null;

    final buf = StringBuffer();
    buf.writeln('Exited plan mode. All tools are now available.');
    if (previousPlan != null) {
      buf.writeln('Original reason: $previousPlan');
    }
    buf.writeln('Plan summary: $summary');
    if (duration != null) {
      buf.writeln('Time in plan mode: ${duration}s');
    }

    return ToolResult.success(buf.toString());
  }
}
