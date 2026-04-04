import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

/// Status of a plan step.
enum PlanStepStatus {
  pending,
  active,
  completed,
  skipped,
  failed;

  String get label {
    switch (this) {
      case PlanStepStatus.pending:
        return 'Pending';
      case PlanStepStatus.active:
        return 'Active';
      case PlanStepStatus.completed:
        return 'Completed';
      case PlanStepStatus.skipped:
        return 'Skipped';
      case PlanStepStatus.failed:
        return 'Failed';
    }
  }

  Color get color {
    switch (this) {
      case PlanStepStatus.pending:
        return Colors.grey;
      case PlanStepStatus.active:
        return Colors.cyanAccent;
      case PlanStepStatus.completed:
        return Colors.green;
      case PlanStepStatus.skipped:
        return Colors.orange;
      case PlanStepStatus.failed:
        return Colors.red;
    }
  }

  IconData get icon {
    switch (this) {
      case PlanStepStatus.pending:
        return Icons.radio_button_unchecked;
      case PlanStepStatus.active:
        return Icons.play_circle_outline;
      case PlanStepStatus.completed:
        return Icons.check_circle;
      case PlanStepStatus.skipped:
        return Icons.skip_next;
      case PlanStepStatus.failed:
        return Icons.cancel;
    }
  }
}

/// A single step in the plan, possibly with substeps and dependencies.
class PlanStep {
  PlanStep({
    required this.id,
    required this.title,
    this.description = '',
    this.status = PlanStepStatus.pending,
    List<PlanStep>? substeps,
    List<String>? dependencies,
  }) : substeps = substeps ?? [],
       dependencies = dependencies ?? [];

  final String id;
  final String title;
  final String description;
  PlanStepStatus status;
  final List<PlanStep> substeps;
  final List<String> dependencies;

  bool get isTerminal =>
      status == PlanStepStatus.completed ||
      status == PlanStepStatus.skipped ||
      status == PlanStepStatus.failed;
}

/// A phase groups related steps.
class PlanPhase {
  PlanPhase({required this.name, required this.steps});

  final String name;
  final List<PlanStep> steps;

  double get progress {
    if (steps.isEmpty) return 0;
    final done = steps.where((s) => s.isTerminal).length;
    return done / steps.length;
  }

  int get completedCount => steps.where((s) => s.isTerminal).length;
}

/// Top-level plan model.
class Plan {
  Plan({
    required this.title,
    required this.phases,
    DateTime? createdAt,
    this.estimatedDuration,
  }) : createdAt = createdAt ?? DateTime.now();

  final String title;
  final List<PlanPhase> phases;
  final DateTime createdAt;
  final Duration? estimatedDuration;

  int get totalSteps {
    int count = 0;
    for (final p in phases) {
      count += p.steps.length;
      for (final s in p.steps) {
        count += _countSubsteps(s);
      }
    }
    return count;
  }

  int get completedSteps {
    int count = 0;
    for (final p in phases) {
      for (final s in p.steps) {
        if (s.isTerminal) count++;
        count += _countCompletedSubsteps(s);
      }
    }
    return count;
  }

  double get overallProgress {
    final t = totalSteps;
    return t == 0 ? 0 : completedSteps / t;
  }

  Duration? get estimatedTimeRemaining {
    if (estimatedDuration == null) return null;
    final remaining = 1.0 - overallProgress;
    return Duration(
      milliseconds: (estimatedDuration!.inMilliseconds * remaining).round(),
    );
  }

  static int _countSubsteps(PlanStep step) {
    int c = step.substeps.length;
    for (final s in step.substeps) {
      c += _countSubsteps(s);
    }
    return c;
  }

  static int _countCompletedSubsteps(PlanStep step) {
    int c = 0;
    for (final s in step.substeps) {
      if (s.isTerminal) c++;
      c += _countCompletedSubsteps(s);
    }
    return c;
  }
}

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

typedef PlanStepCallback = void Function(PlanStep step);
typedef PlanStepReorderCallback =
    void Function(PlanPhase phase, int oldIndex, int newIndex);

// ---------------------------------------------------------------------------
// PlanModeView widget
// ---------------------------------------------------------------------------

/// Displays and controls the execution of a [Plan] with phases, steps,
/// substeps, dependency indicators, drag-to-reorder, and status controls.
class PlanModeView extends StatefulWidget {
  const PlanModeView({
    super.key,
    required this.plan,
    this.onExecuteNext,
    this.onSkipStep,
    this.onExitPlanMode,
    this.onReorderStep,
  });

  final Plan plan;
  final PlanStepCallback? onExecuteNext;
  final PlanStepCallback? onSkipStep;
  final VoidCallback? onExitPlanMode;
  final PlanStepReorderCallback? onReorderStep;

  @override
  State<PlanModeView> createState() => _PlanModeViewState();
}

class _PlanModeViewState extends State<PlanModeView>
    with TickerProviderStateMixin {
  final Set<String> _collapsedPhases = {};
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  PlanStep? get _activeStep {
    for (final phase in widget.plan.phases) {
      for (final step in phase.steps) {
        if (step.status == PlanStepStatus.active) return step;
        final sub = _findActive(step.substeps);
        if (sub != null) return sub;
      }
    }
    return null;
  }

  PlanStep? _findActive(List<PlanStep> steps) {
    for (final s in steps) {
      if (s.status == PlanStepStatus.active) return s;
      final sub = _findActive(s.substeps);
      if (sub != null) return sub;
    }
    return null;
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;

    return Column(
      children: [
        _buildHeader(plan),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              for (final phase in plan.phases) _buildPhaseSection(phase),
              const SizedBox(height: 16),
              _buildStatusLegend(),
            ],
          ),
        ),
      ],
    );
  }

  // ---- header ----

  Widget _buildHeader(Plan plan) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.grey.shade900,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.map_outlined,
                color: Colors.cyanAccent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  plan.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (widget.onExitPlanMode != null)
                TextButton.icon(
                  onPressed: widget.onExitPlanMode,
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Exit Plan Mode'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white70,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: plan.overallProgress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade700,
              valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${plan.completedSteps} / ${plan.totalSteps} steps',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(width: 12),
              Text(
                '${(plan.overallProgress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              if (plan.estimatedTimeRemaining != null)
                Text(
                  'ETA: ${_formatDuration(plan.estimatedTimeRemaining!)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ---- phase section ----

  Widget _buildPhaseSection(PlanPhase phase) {
    final collapsed = _collapsedPhases.contains(phase.name);
    final allDone = phase.steps.every((s) => s.isTerminal);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase header
          InkWell(
            onTap: () {
              setState(() {
                if (collapsed) {
                  _collapsedPhases.remove(phase.name);
                } else {
                  _collapsedPhases.add(phase.name);
                }
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    collapsed ? Icons.chevron_right : Icons.expand_more,
                    color: Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      phase.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Mini progress
                  SizedBox(
                    width: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: phase.progress,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade700,
                        valueColor: const AlwaysStoppedAnimation(
                          Colors.cyanAccent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${phase.completedCount}/${phase.steps.length}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          // Collapsed summary
          if (collapsed && allDone)
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 4),
              child: Text(
                'All ${phase.steps.length} steps completed',
                style: const TextStyle(color: Colors.green, fontSize: 12),
              ),
            ),
          // Steps
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: phase.steps.length,
                onReorder: (oldIndex, newIndex) {
                  widget.onReorderStep?.call(phase, oldIndex, newIndex);
                },
                itemBuilder: (context, index) {
                  return _buildStepCard(
                    key: ValueKey(phase.steps[index].id),
                    step: phase.steps[index],
                    phase: phase,
                    index: index,
                    depth: 0,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  // ---- step card ----

  Widget _buildStepCard({
    required Key key,
    required PlanStep step,
    required PlanPhase phase,
    required int index,
    required int depth,
  }) {
    final isActive = step.status == PlanStepStatus.active;

    return Padding(
      key: key,
      padding: EdgeInsets.only(left: depth * 24.0, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dependency lines
          if (step.dependencies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 32, bottom: 2),
              child: Row(
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right,
                    size: 14,
                    color: Colors.white30,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'depends on: ${step.dependencies.join(", ")}',
                    style: const TextStyle(
                      color: Colors.white30,
                      fontSize: 10,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (context, child) {
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.cyanAccent.withOpacity(0.06)
                      : const Color(0xFF303030),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isActive
                        ? Colors.cyanAccent.withOpacity(
                            0.3 + _pulseAnimation.value * 0.5,
                          )
                        : Colors.grey.shade700,
                    width: isActive ? 1.5 : 0.5,
                  ),
                ),
                child: child,
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Drag handle
                    if (depth == 0)
                      ReorderableDragStartListener(
                        index: index,
                        child: const Icon(
                          Icons.drag_indicator,
                          size: 16,
                          color: Colors.white30,
                        ),
                      ),
                    if (depth == 0) const SizedBox(width: 4),
                    // Tree line for substeps
                    if (depth > 0) ...[
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.white24,
                        margin: const EdgeInsets.only(right: 8),
                      ),
                    ],
                    Icon(step.status.icon, size: 18, color: step.status.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        step.title,
                        style: TextStyle(
                          color: step.isTerminal
                              ? Colors.white54
                              : Colors.white,
                          fontSize: 13,
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                          decoration: step.status == PlanStepStatus.skipped
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                    // Action buttons for active step
                    if (isActive) ...[
                      _ActionButton(
                        label: 'Execute',
                        icon: Icons.play_arrow,
                        color: Colors.cyanAccent,
                        onTap: () => widget.onExecuteNext?.call(step),
                      ),
                      const SizedBox(width: 4),
                      _ActionButton(
                        label: 'Skip',
                        icon: Icons.skip_next,
                        color: Colors.orange,
                        onTap: () => widget.onSkipStep?.call(step),
                      ),
                    ],
                  ],
                ),
                if (step.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
                    child: Text(
                      step.description,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Substeps
          if (step.substeps.isNotEmpty)
            ...step.substeps.asMap().entries.map((e) {
              return _buildStepCard(
                key: ValueKey(e.value.id),
                step: e.value,
                phase: phase,
                index: e.key,
                depth: depth + 1,
              );
            }),
        ],
      ),
    );
  }

  // ---- status legend ----

  Widget _buildStatusLegend() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF303030),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade700, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Legend',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: PlanStepStatus.values.map((s) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.icon, size: 14, color: s.color),
                  const SizedBox(width: 4),
                  Text(s.label, style: TextStyle(color: s.color, fontSize: 11)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AnimatedBuilder helper (alias for AnimatedBuilder)
// ---------------------------------------------------------------------------

/// Small action button used on active steps.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
