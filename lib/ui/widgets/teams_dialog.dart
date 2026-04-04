// TeamsDialog — faithful port of neom_claw/src/components/teams/
// Ports: TeamsDialog.tsx (teammate list + detail view), TeamStatus.tsx
// (footer status indicator).
//
// Provides a dialog for viewing and managing teammates in the current team:
// - List view with keyboard navigation
// - Detail view for individual teammates showing prompt, tasks, cwd
// - Kill / shutdown / hide/show / foreground actions
// - Permission mode display and cycling
// - Team status footer indicator

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import 'design_system.dart';

// ─── Permission mode (port of PermissionMode) ───────────────────────────

enum PermissionMode {
  defaultMode,
  plan,
  autoEdit,
  fullAutoMode,
  bypassPermissions,
}

extension PermissionModeExt on PermissionMode {
  String get title {
    switch (this) {
      case PermissionMode.defaultMode:
        return 'Default';
      case PermissionMode.plan:
        return 'Plan';
      case PermissionMode.autoEdit:
        return 'Auto-edit';
      case PermissionMode.fullAutoMode:
        return 'Full auto';
      case PermissionMode.bypassPermissions:
        return 'Bypass';
    }
  }

  String get symbol {
    switch (this) {
      case PermissionMode.defaultMode:
        return '\u25CB'; // ○
      case PermissionMode.plan:
        return '\u25D4'; // ◔
      case PermissionMode.autoEdit:
        return '\u25D1'; // ◑
      case PermissionMode.fullAutoMode:
        return '\u25CF'; // ●
      case PermissionMode.bypassPermissions:
        return '\u26A0'; // ⚠
    }
  }

  Color get color {
    switch (this) {
      case PermissionMode.defaultMode:
        return ClawColors.darkTextSecondary;
      case PermissionMode.plan:
        return ClawColors.info;
      case PermissionMode.autoEdit:
        return ClawColors.warning;
      case PermissionMode.fullAutoMode:
        return ClawColors.success;
      case PermissionMode.bypassPermissions:
        return ClawColors.error;
    }
  }

  PermissionMode get next {
    final modes = PermissionMode.values;
    final idx = modes.indexOf(this);
    return modes[(idx + 1) % modes.length];
  }
}

PermissionMode permissionModeFromString(String mode) {
  switch (mode) {
    case 'plan':
      return PermissionMode.plan;
    case 'autoEdit':
      return PermissionMode.autoEdit;
    case 'fullAutoMode':
      return PermissionMode.fullAutoMode;
    case 'bypassPermissions':
      return PermissionMode.bypassPermissions;
    default:
      return PermissionMode.defaultMode;
  }
}

// ─── Teammate status model (port of TeammateStatus from teamDiscovery.ts) ──

class TeammateStatus {
  final String agentId;
  final String name;
  final String? model;
  final String? color;
  final String? mode;
  final String status; // 'running', 'idle', 'exited'
  final String? currentTask;
  final String? cwd;
  final String? worktreePath;
  final String? tmuxPaneId;
  final String? backendType;
  final bool isHidden;
  final String? prompt;
  final List<TeamTask> tasks;

  const TeammateStatus({
    required this.agentId,
    required this.name,
    this.model,
    this.color,
    this.mode,
    this.status = 'running',
    this.currentTask,
    this.cwd,
    this.worktreePath,
    this.tmuxPaneId,
    this.backendType,
    this.isHidden = false,
    this.prompt,
    this.tasks = const [],
  });
}

/// Task assigned to a teammate.
class TeamTask {
  final String id;
  final String title;
  final String? owner;
  final String status;

  const TeamTask({
    required this.id,
    required this.title,
    this.owner,
    this.status = 'pending',
  });
}

/// Summary of a team.
class TeamSummary {
  final String name;
  final int memberCount;

  const TeamSummary({required this.name, required this.memberCount});
}

// ─── Dialog level state ──────────────────────────────────────────────────

enum _DialogLevelType { teammateList, teammateDetail }

class _DialogLevel {
  final _DialogLevelType type;
  final String teamName;
  final String? memberName;

  const _DialogLevel({
    required this.type,
    required this.teamName,
    this.memberName,
  });
}

// ─── TeamsDialogController ───────────────────────────────────────────────

class TeamsDialogController extends SintController {
  final List<TeamSummary>? initialTeams;
  final VoidCallback onDone;

  TeamsDialogController({this.initialTeams, required this.onDone});

  late final Rx<_DialogLevel> dialogLevel;
  final selectedIndex = 0.obs;
  final refreshKey = 0.obs;
  final teammateStatuses = <TeammateStatus>[].obs;
  Timer? _refreshTimer;

  @override
  void onInit() {
    super.onInit();
    final firstTeamName = initialTeams?.isNotEmpty == true
        ? initialTeams!.first.name
        : '';
    dialogLevel = _DialogLevel(
      type: _DialogLevelType.teammateList,
      teamName: firstTeamName,
    ).obs;

    _loadTeammateStatuses();

    // Periodically refresh to pick up mode changes from teammates.
    // Port of useInterval(() => setRefreshKey(...), 1000)
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      refreshKey.value++;
      _loadTeammateStatuses();
    });
  }

  @override
  void onClose() {
    _refreshTimer?.cancel();
    super.onClose();
  }

  void _loadTeammateStatuses() {
    // In a real implementation, this calls getTeammateStatuses(teamName).
    // For now, the list is sourced from the initial teams data.
  }

  TeammateStatus? get currentTeammate {
    final level = dialogLevel.value;
    if (level.type != _DialogLevelType.teammateDetail) return null;
    return teammateStatuses.cast<TeammateStatus?>().firstWhere(
      (t) => t!.name == level.memberName,
      orElse: () => null,
    );
  }

  void goBackToList() {
    dialogLevel.value = _DialogLevel(
      type: _DialogLevelType.teammateList,
      teamName: dialogLevel.value.teamName,
    );
    selectedIndex.value = 0;
  }

  void selectTeammate(int index) {
    if (index >= 0 && index < teammateStatuses.length) {
      dialogLevel.value = _DialogLevel(
        type: _DialogLevelType.teammateDetail,
        teamName: dialogLevel.value.teamName,
        memberName: teammateStatuses[index].name,
      );
    }
  }

  void handleCycleMode() {
    final level = dialogLevel.value;
    if (level.type == _DialogLevelType.teammateDetail) {
      final teammate = currentTeammate;
      if (teammate != null) {
        _cycleTeammateMode(teammate);
      }
    } else if (level.type == _DialogLevelType.teammateList &&
        teammateStatuses.isNotEmpty) {
      _cycleAllTeammateModes();
    }
    refreshKey.value++;
  }

  void _cycleTeammateMode(TeammateStatus teammate) {
    final currentMode = teammate.mode != null
        ? permissionModeFromString(teammate.mode!)
        : PermissionMode.defaultMode;
    final nextMode = currentMode.next;
    // In production: setMemberMode(teammate.name, teamName, nextMode)
    debugPrint('Cycle mode for ${teammate.name}: $currentMode -> $nextMode');
  }

  void _cycleAllTeammateModes() {
    for (final t in teammateStatuses) {
      _cycleTeammateMode(t);
    }
  }

  Future<void> killTeammate(TeammateStatus teammate) async {
    // In production: kill via tmux pane or backend
    debugPrint('Kill teammate: ${teammate.name}');
    _loadTeammateStatuses();
    final maxIdx = teammateStatuses.length - 2;
    selectedIndex.value = selectedIndex.value.clamp(0, maxIdx.clamp(0, maxIdx));
  }

  Future<void> shutdownTeammate(TeammateStatus teammate) async {
    // In production: sendShutdownRequestToMailbox
    debugPrint('Shutdown teammate: ${teammate.name}');
  }

  Future<void> toggleTeammateVisibility(TeammateStatus teammate) async {
    // In production: hide/show pane via backend
    debugPrint('Toggle visibility: ${teammate.name}');
    refreshKey.value++;
  }

  Future<void> pruneIdleTeammates() async {
    final idle = teammateStatuses.where((t) => t.status == 'idle').toList();
    for (final t in idle) {
      await killTeammate(t);
    }
  }

  void handleKeyAction(String key) {
    final level = dialogLevel.value;

    switch (key) {
      case 'up':
        if (selectedIndex.value > 0) selectedIndex.value--;
        break;
      case 'down':
        final maxIdx = level.type == _DialogLevelType.teammateList
            ? teammateStatuses.length - 1
            : 0;
        if (selectedIndex.value < maxIdx) selectedIndex.value++;
        break;
      case 'enter':
        if (level.type == _DialogLevelType.teammateList) {
          selectTeammate(selectedIndex.value);
        }
        break;
      case 'left':
        if (level.type == _DialogLevelType.teammateDetail) {
          goBackToList();
        }
        break;
      case 'escape':
        if (level.type == _DialogLevelType.teammateDetail) {
          goBackToList();
        } else {
          onDone();
        }
        break;
      case 'k':
        final target = level.type == _DialogLevelType.teammateList
            ? (teammateStatuses.isNotEmpty
                  ? teammateStatuses[selectedIndex.value]
                  : null)
            : currentTeammate;
        if (target != null) {
          killTeammate(target);
          if (level.type == _DialogLevelType.teammateDetail) {
            goBackToList();
          }
        }
        break;
      case 's':
        final shutdownTarget = level.type == _DialogLevelType.teammateList
            ? (teammateStatuses.isNotEmpty
                  ? teammateStatuses[selectedIndex.value]
                  : null)
            : currentTeammate;
        if (shutdownTarget != null) {
          shutdownTeammate(shutdownTarget);
          if (level.type == _DialogLevelType.teammateDetail) {
            goBackToList();
          }
        }
        break;
      case 'h':
        final hideTarget = level.type == _DialogLevelType.teammateList
            ? (teammateStatuses.isNotEmpty
                  ? teammateStatuses[selectedIndex.value]
                  : null)
            : currentTeammate;
        if (hideTarget != null) {
          toggleTeammateVisibility(hideTarget);
          if (level.type == _DialogLevelType.teammateDetail) {
            goBackToList();
          }
        }
        break;
      case 'p':
        if (level.type == _DialogLevelType.teammateList) {
          pruneIdleTeammates();
        }
        break;
    }
  }
}

// ─── TeamsDialog widget (port of TeamsDialog from TeamsDialog.tsx) ───────

class TeamsDialog extends StatelessWidget {
  final List<TeamSummary>? initialTeams;
  final VoidCallback onDone;

  const TeamsDialog({super.key, this.initialTeams, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(
      TeamsDialogController(initialTeams: initialTeams, onDone: onDone),
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          controller.handleKeyAction('up');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          controller.handleKeyAction('down');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter) {
          controller.handleKeyAction('enter');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowLeft) {
          controller.handleKeyAction('left');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          controller.handleKeyAction('escape');
          return KeyEventResult.handled;
        }
        if (event.character != null) {
          controller.handleKeyAction(event.character!);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Obx(() {
        final level = controller.dialogLevel.value;

        if (level.type == _DialogLevelType.teammateList) {
          return _TeamDetailView(controller: controller);
        }
        if (level.type == _DialogLevelType.teammateDetail &&
            controller.currentTeammate != null) {
          return _TeammateDetailView(
            controller: controller,
            teammate: controller.currentTeammate!,
          );
        }
        return const SizedBox.shrink();
      }),
    );
  }
}

// ─── Team list view (port of TeamDetailView from TeamsDialog.tsx) ────────

class _TeamDetailView extends StatelessWidget {
  final TeamsDialogController controller;

  const _TeamDetailView({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final teamName = controller.dialogLevel.value.teamName;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Team $teamName',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Obx(
                        () => Text(
                          '${controller.teammateStatuses.length} '
                          '${controller.teammateStatuses.length == 1 ? "teammate" : "teammates"}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: controller.onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Teammate list ──
            Expanded(
              child: Obx(() {
                if (controller.teammateStatuses.isEmpty) {
                  return Center(
                    child: Text(
                      'No teammates',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: controller.teammateStatuses.length,
                  itemBuilder: (context, index) {
                    final teammate = controller.teammateStatuses[index];
                    final isSelected = index == controller.selectedIndex.value;

                    return _TeammateListItem(
                      teammate: teammate,
                      isSelected: isSelected,
                      onTap: () => controller.selectTeammate(index),
                    );
                  },
                );
              }),
            ),

            const SizedBox(height: 12),

            // ── Actions hint ──
            Wrap(
              spacing: 8,
              children: [
                _KeyHint(shortcut: '\u2191/\u2193', action: 'select'),
                _KeyHint(shortcut: 'Enter', action: 'view'),
                _KeyHint(shortcut: 'k', action: 'kill'),
                _KeyHint(shortcut: 's', action: 'shutdown'),
                _KeyHint(shortcut: 'p', action: 'prune idle'),
                _KeyHint(shortcut: 'h', action: 'hide/show'),
                _KeyHint(shortcut: 'Esc', action: 'close'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Teammate list item (port of TeammateListItem from TeamsDialog.tsx) ──

class _TeammateListItem extends StatelessWidget {
  final TeammateStatus teammate;
  final bool isSelected;
  final VoidCallback? onTap;

  const _TeammateListItem({
    required this.teammate,
    required this.isSelected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIdle = teammate.status == 'idle';
    final shouldDim = isIdle && !isSelected;
    final mode = teammate.mode != null
        ? permissionModeFromString(teammate.mode!)
        : PermissionMode.defaultMode;
    final agentColor = _parseTeammateColor(teammate.color);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: Row(
          children: [
            // Selection indicator
            SizedBox(
              width: 20,
              child: Text(
                isSelected ? '\u276F' : '',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 14,
                ),
              ),
            ),

            // Hidden badge
            if (teammate.isHidden)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '[hidden]',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),

            // Idle badge
            if (isIdle)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '[idle]',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),

            // Mode symbol
            Text(
              '${mode.symbol} ',
              style: TextStyle(color: mode.color, fontSize: 14),
            ),

            // Name
            Text(
              '@${teammate.name}',
              style: TextStyle(
                color: shouldDim
                    ? theme.colorScheme.onSurfaceVariant
                    : agentColor,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),

            // Model
            if (teammate.model != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  '(${teammate.model})',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _parseTeammateColor(String? color) {
    if (color == null) return ClawColors.info;
    switch (color) {
      case 'blue':
        return ClawColors.info;
      case 'green':
        return ClawColors.success;
      case 'yellow':
        return ClawColors.warning;
      case 'red':
        return ClawColors.error;
      case 'purple':
        return ClawColors.agentOpus;
      default:
        return ClawColors.info;
    }
  }
}

// ─── Teammate detail view (port of TeammateDetailView) ──────────────────

class _TeammateDetailView extends StatelessWidget {
  final TeamsDialogController controller;
  final TeammateStatus teammate;

  const _TeammateDetailView({required this.controller, required this.teammate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = teammate.mode != null
        ? permissionModeFromString(teammate.mode!)
        : PermissionMode.defaultMode;
    final workingPath = teammate.worktreePath ?? teammate.cwd;
    final subtitleParts = <String>[];
    if (teammate.model != null) subtitleParts.add(teammate.model!);
    if (workingPath != null) {
      subtitleParts.add(
        teammate.worktreePath != null ? 'worktree: $workingPath' : workingPath,
      );
    }

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Title ──
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 18),
                  onPressed: controller.goBackToList,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Text(
                  '${mode.symbol} ',
                  style: TextStyle(color: mode.color, fontSize: 16),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${teammate.name}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitleParts.isNotEmpty)
                        Text(
                          subtitleParts.join(' \u00B7 '),
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: controller.onDone,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Status ──
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(
                      teammate.status,
                    ).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    teammate.status,
                    style: TextStyle(
                      color: _statusColor(teammate.status),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Mode: ${mode.title}',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── Current task ──
            if (teammate.currentTask != null) ...[
              Text(
                'Current Task:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(teammate.currentTask!, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 12),
            ],

            // ── Prompt ──
            if (teammate.prompt != null) ...[
              Text(
                'Prompt:',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ClawColors.codeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  teammate.prompt!.length > 500
                      ? '${teammate.prompt!.substring(0, 497)}...'
                      : teammate.prompt!,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: ClawColors.codeText,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // ── Tasks ──
            if (teammate.tasks.isNotEmpty) ...[
              Text(
                'Tasks (${teammate.tasks.length}):',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              ...teammate.tasks
                  .take(5)
                  .map(
                    (task) => Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Row(
                        children: [
                          Icon(
                            task.status == 'completed'
                                ? Icons.check_circle
                                : task.status == 'running'
                                ? Icons.play_circle
                                : Icons.circle_outlined,
                            size: 14,
                            color: task.status == 'completed'
                                ? ClawColors.success
                                : task.status == 'running'
                                ? ClawColors.info
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              task.title,
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: 12),
            ],

            const Spacer(),

            // ── Actions ──
            Wrap(
              spacing: 8,
              children: [
                _KeyHint(shortcut: '\u2190', action: 'back'),
                _KeyHint(shortcut: 'k', action: 'kill'),
                _KeyHint(shortcut: 's', action: 'shutdown'),
                _KeyHint(shortcut: 'h', action: 'hide/show'),
                _KeyHint(shortcut: 'p', action: 'toggle prompt'),
                _KeyHint(shortcut: 'Esc', action: 'close'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'running':
        return ClawColors.success;
      case 'idle':
        return ClawColors.darkTextSecondary;
      case 'exited':
        return ClawColors.error;
      default:
        return ClawColors.darkTextSecondary;
    }
  }
}

// ─── KeyHint widget ──────────────────────────────────────────────────────

class _KeyHint extends StatelessWidget {
  final String shortcut;
  final String action;

  const _KeyHint({required this.shortcut, required this.action});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            shortcut,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 3),
        Text(
          action,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// ─── TeamStatus footer widget (port of TeamStatus.tsx) ───────────────────

class TeamStatusWidget extends StatelessWidget {
  final bool teamsSelected;
  final bool showHint;
  final int teammateCount;

  const TeamStatusWidget({
    super.key,
    required this.teamsSelected,
    this.showHint = false,
    this.teammateCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (teammateCount == 0) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final statusText =
        '$teammateCount ${teammateCount == 1 ? "teammate" : "teammates"}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: teamsSelected
                ? theme.colorScheme.onSurface
                : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            statusText,
            style: TextStyle(
              color: teamsSelected
                  ? theme.colorScheme.surface
                  : theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        if (showHint && teamsSelected) ...[
          Text(
            ' \u00B7 ',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          Text(
            'Enter to view',
            style: TextStyle(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}
