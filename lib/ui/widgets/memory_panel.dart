// MemoryPanel — port of openneomclaw/src/components/memory/
// Ports: MemoryFileSelector.tsx, MemoryUpdateNotification.tsx
//
// Provides:
// - MemoryFileSelector: a list/select widget for browsing and selecting
//   memory files (NEOMCLAW.md files at user, project, and nested scopes).
//   Supports auto-memory and auto-dream toggles, agent memory folders,
//   and opening folders in the OS file manager.
// - MemoryUpdateNotification: inline notification shown when a memory
//   file has been updated.
// - MemoryPanelController: manages memory file discovery, toggle state,
//   and dream status.

import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

// ─── Memory file info model (mirrors MemoryFileInfo in utils/neomclawmd.ts) ───

class MemoryFileInfo {
  final String path;
  final String type; // 'User' | 'Project' | 'Nested'
  final String content;
  final bool exists;
  final String? parent; // Path of parent memory file (for @-imported)
  final bool isNested;

  const MemoryFileInfo({
    required this.path,
    required this.type,
    this.content = '',
    this.exists = true,
    this.parent,
    this.isNested = false,
  });
}

// ─── Memory select option ───

class MemorySelectOption {
  final String label;
  final String value;
  final String description;
  final bool isFolder;

  const MemorySelectOption({
    required this.label,
    required this.value,
    this.description = '',
    this.isFolder = false,
  });
}

// ─── Agent definition info ───

class AgentDefinitionInfo {
  final String agentType;
  final String? memory; // memory scope
  final bool isActive;

  const AgentDefinitionInfo({
    required this.agentType,
    this.memory,
    this.isActive = true,
  });
}

// ─── Path display utilities (mirrors MemoryUpdateNotification.tsx getRelativeMemoryPath) ───

/// Get a short relative display path for a memory file.
/// Prefers ~/... or ./... notation, returns the shorter one.
String getRelativeMemoryPath(String filePath) {
  final homeDir = Platform.environment['HOME'] ?? '';
  final cwd = Directory.current.path;

  // Calculate relative paths
  final relativeToHome = filePath.startsWith(homeDir)
      ? '~${filePath.substring(homeDir.length)}'
      : null;

  final relativeToCwd = filePath.startsWith(cwd)
      ? './${_relativePath(cwd, filePath)}'
      : null;

  // Return the shorter path, or absolute if neither is applicable
  if (relativeToHome != null && relativeToCwd != null) {
    return relativeToHome.length <= relativeToCwd.length
        ? relativeToHome
        : relativeToCwd;
  }

  return relativeToHome ?? relativeToCwd ?? filePath;
}

/// Compute relative path from base to target.
String _relativePath(String base, String target) {
  if (!target.startsWith(base)) return target;
  var relative = target.substring(base.length);
  if (relative.startsWith('/')) relative = relative.substring(1);
  return relative;
}

/// Get display path (shorten home dir to ~).
String getDisplayPath(String filePath) {
  final homeDir = Platform.environment['HOME'] ?? '';
  if (filePath.startsWith(homeDir)) {
    return '~${filePath.substring(homeDir.length)}';
  }
  return filePath;
}

// ─── Format relative time ago (mirrors utils/format.ts) ───

String formatRelativeTimeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);

  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return '${(diff.inDays / 7).floor()}w ago';
}

// ─── MemoryPanelController (SintController) ───

class MemoryPanelController extends SintController {
  // Observable state
  final memoryFiles = <MemoryFileInfo>[].obs;
  final selectedIndex = 0.obs;
  final autoMemoryOn = false.obs;
  final autoDreamOn = false.obs;
  final showDreamRow = false.obs;
  final isDreamRunning = false.obs;
  final lastDreamAt = Rxn<DateTime>();
  final focusedToggle = Rxn<int>(); // null = no toggle focused, 0 = auto-memory, 1 = auto-dream
  final agentDefinitions = <AgentDefinitionInfo>[].obs;

  // Last selected path (persisted across opens)
  static String? _lastSelectedPath;

  // Folder prefix sentinel
  static const _openFolderPrefix = '__open_folder__';

  // Computed paths
  String get userMemoryPath {
    final homeDir = Platform.environment['HOME'] ?? '';
    return '$homeDir/.neomclaw/NEOMCLAW.md';
  }

  String get projectMemoryPath {
    return '${Directory.current.path}/NEOMCLAW.md';
  }

  bool get hasUserMemory =>
      memoryFiles.any((f) => f.path == userMemoryPath);

  bool get hasProjectMemory =>
      memoryFiles.any((f) => f.path == projectMemoryPath);

  bool get toggleFocused => focusedToggle.value != null;

  int get lastToggleIndex => showDreamRow.value ? 1 : 0;

  /// Build the full list of memory options for the select widget.
  List<MemorySelectOption> get memoryOptions {
    final options = <MemorySelectOption>[];
    final depths = <String, int>{};

    // All memory files (existing + placeholders for missing user/project)
    final allFiles = <MemoryFileInfo>[
      ...memoryFiles.where((f) => f.path != userMemoryPath && f.path != projectMemoryPath),
      if (!hasUserMemory)
        MemoryFileInfo(
          path: userMemoryPath,
          type: 'User',
          exists: false,
        ),
      if (!hasProjectMemory)
        MemoryFileInfo(
          path: projectMemoryPath,
          type: 'Project',
          exists: false,
        ),
      // Include existing user and project files
      ...memoryFiles.where(
        (f) => f.path == userMemoryPath || f.path == projectMemoryPath,
      ),
    ];

    for (final file in allFiles) {
      final displayPath = getDisplayPath(file.path);
      final existsLabel = file.exists ? '' : ' (new)';
      final depth = file.parent != null
          ? (depths[file.parent] ?? 0) + 1
          : 0;
      depths[file.path] = depth;
      final indent = depth > 0 ? '  ' * (depth - 1) : '';

      String label;
      if (file.type == 'User' && !file.isNested && file.path == userMemoryPath) {
        label = 'User memory';
      } else if (file.type == 'Project' &&
          !file.isNested &&
          file.path == projectMemoryPath) {
        label = 'Project memory';
      } else if (depth > 0) {
        label = '$indent\u2514 $displayPath$existsLabel';
      } else {
        label = displayPath;
      }

      String description;
      if (file.type == 'User' && !file.isNested) {
        description = 'Saved in ~/.neomclaw/NEOMCLAW.md';
      } else if (file.type == 'Project' &&
          !file.isNested &&
          file.path == projectMemoryPath) {
        description = 'Saved in ./NEOMCLAW.md';
      } else if (file.parent != null) {
        description = '@-imported';
      } else if (file.isNested) {
        description = 'dynamically loaded';
      } else {
        description = '';
      }

      options.add(MemorySelectOption(
        label: label,
        value: file.path,
        description: description,
      ));
    }

    // Folder options (auto-memory, team memory, agent memory)
    if (autoMemoryOn.value) {
      final autoMemPath = _getAutoMemPath();
      options.add(MemorySelectOption(
        label: 'Open auto-memory folder',
        value: '$_openFolderPrefix$autoMemPath',
        isFolder: true,
      ));

      // Agent memory folders
      for (final agent in agentDefinitions) {
        if (agent.memory != null) {
          final agentDir = _getAgentMemoryDir(agent.agentType, agent.memory!);
          options.add(MemorySelectOption(
            label: 'Open ${agent.agentType} agent memory',
            value: '$_openFolderPrefix$agentDir',
            description: '${agent.memory} scope',
            isFolder: true,
          ));
        }
      }
    }

    return options;
  }

  /// Initial path to focus in the select widget.
  String get initialPath {
    final opts = memoryOptions;
    if (_lastSelectedPath != null &&
        opts.any((o) => o.value == _lastSelectedPath)) {
      return _lastSelectedPath!;
    }
    return opts.isNotEmpty ? opts.first.value : '';
  }

  /// Dream status text.
  String get dreamStatus {
    if (isDreamRunning.value) return 'running';
    final last = lastDreamAt.value;
    if (last == null) return '';
    if (last.millisecondsSinceEpoch == 0) return 'never';
    return 'last ran ${formatRelativeTimeAgo(last)}';
  }

  @override
  void onInit() {
    super.onInit();
    // In real implementation, would load memory files from disk
    // and check auto-memory / auto-dream settings
  }

  /// Handle selecting a memory file or folder.
  void handleSelect(String value) {
    if (value.startsWith(_openFolderPrefix)) {
      final folderPath = value.substring(_openFolderPrefix.length);
      _openFolder(folderPath);
      return;
    }
    _lastSelectedPath = value;
  }

  /// Toggle auto-memory on/off.
  void toggleAutoMemory() {
    autoMemoryOn.value = !autoMemoryOn.value;
    // In real implementation, would persist to settings
    // logEvent('tengu_auto_memory_toggled', { enabled: autoMemoryOn.value })
  }

  /// Toggle auto-dream on/off.
  void toggleAutoDream() {
    autoDreamOn.value = !autoDreamOn.value;
    // In real implementation, would persist to settings
    // logEvent('tengu_auto_dream_toggled', { enabled: autoDreamOn.value })
  }

  /// Handle toggle focus (for keyboard navigation between toggles).
  void handleToggleConfirm() {
    if (focusedToggle.value == 0) {
      toggleAutoMemory();
    } else if (focusedToggle.value == 1) {
      toggleAutoDream();
    }
  }

  /// Move toggle focus to next.
  void focusNextToggle() {
    final current = focusedToggle.value;
    if (current != null && current < lastToggleIndex) {
      focusedToggle.value = current + 1;
    } else {
      focusedToggle.value = null;
    }
  }

  /// Move toggle focus to previous.
  void focusPreviousToggle() {
    final current = focusedToggle.value;
    if (current != null && current > 0) {
      focusedToggle.value = current - 1;
    }
  }

  /// Enter toggle mode from the select list.
  void enterToggleMode() {
    focusedToggle.value = lastToggleIndex;
  }

  String _getAutoMemPath() {
    final homeDir = Platform.environment['HOME'] ?? '';
    return '$homeDir/.neomclaw/auto-memory';
  }

  String _getAgentMemoryDir(String agentType, String scope) {
    final homeDir = Platform.environment['HOME'] ?? '';
    return '$homeDir/.neomclaw/agent-memory/$agentType/$scope';
  }

  Future<void> _openFolder(String path) async {
    try {
      await Directory(path).create(recursive: true);
      // In real implementation, would use openPath() to open in file manager
      // For now, just ensure directory exists
    } catch (_) {
      // Ignore errors
    }
  }
}

// ─── MemoryFileSelector widget (mirrors MemoryFileSelector.tsx) ───

class MemoryFileSelector extends StatelessWidget {
  final void Function(String path) onSelect;
  final VoidCallback onCancel;

  const MemoryFileSelector({
    super.key,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final controller = Sint.find<MemoryPanelController>();

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: (event) => _handleKeyEvent(event, controller),
      child: Obx(() => _buildContent(context, controller)),
    );
  }

  void _handleKeyEvent(KeyEvent event, MemoryPanelController controller) {
    if (event is! KeyDownEvent) return;

    if (controller.toggleFocused) {
      // In toggle mode
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter:
          controller.handleToggleConfirm();
        case LogicalKeyboardKey.arrowDown:
          controller.focusNextToggle();
        case LogicalKeyboardKey.arrowUp:
          controller.focusPreviousToggle();
        case LogicalKeyboardKey.escape:
          onCancel();
        default:
          break;
      }
    } else {
      // In select mode
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowUp:
          if (controller.selectedIndex.value > 0) {
            controller.selectedIndex.value--;
          } else {
            // At top of list, enter toggle mode
            controller.enterToggleMode();
          }
        case LogicalKeyboardKey.arrowDown:
          final maxIdx = controller.memoryOptions.length - 1;
          if (controller.selectedIndex.value < maxIdx) {
            controller.selectedIndex.value++;
          }
        case LogicalKeyboardKey.enter:
          final options = controller.memoryOptions;
          if (controller.selectedIndex.value < options.length) {
            final selected = options[controller.selectedIndex.value];
            controller.handleSelect(selected.value);
            if (!selected.isFolder) {
              onSelect(selected.value);
            }
          }
        case LogicalKeyboardKey.escape:
          onCancel();
        default:
          break;
      }
    }
  }

  Widget _buildContent(BuildContext context, MemoryPanelController controller) {
    final theme = Theme.of(context);
    final options = controller.memoryOptions;

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
          // Toggle section
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Auto-memory toggle
                _ToggleRow(
                  label: 'Auto-memory',
                  value: controller.autoMemoryOn.value,
                  isFocused: controller.focusedToggle.value == 0,
                  onToggle: controller.toggleAutoMemory,
                ),

                // Auto-dream toggle (conditional)
                if (controller.showDreamRow.value)
                  _ToggleRow(
                    label: 'Auto-dream',
                    value: controller.autoDreamOn.value,
                    isFocused: controller.focusedToggle.value == 1,
                    onToggle: controller.toggleAutoDream,
                    trailing: controller.dreamStatus.isNotEmpty
                        ? Text(
                            ' \u00B7 ${controller.dreamStatus}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.4),
                              fontSize: 12,
                            ),
                          )
                        : null,
                    secondaryTrailing:
                        !controller.isDreamRunning.value &&
                                controller.autoDreamOn.value
                            ? Text(
                                ' \u00B7 /dream to run',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.4),
                                  fontSize: 12,
                                ),
                              )
                            : null,
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Memory file list
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...options.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final option = entry.value;
                    final isSelected = !controller.toggleFocused &&
                        idx == controller.selectedIndex.value;

                    return _MemoryOptionTile(
                      option: option,
                      isSelected: isSelected,
                      onTap: () {
                        controller.selectedIndex.value = idx;
                        controller.handleSelect(option.value);
                        if (!option.isFolder) {
                          onSelect(option.value);
                        }
                      },
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

// ─── Toggle row widget ───

class _ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final bool isFocused;
  final VoidCallback onToggle;
  final Widget? trailing;
  final Widget? secondaryTrailing;

  const _ToggleRow({
    required this.label,
    required this.value,
    required this.isFocused,
    required this.onToggle,
    this.trailing,
    this.secondaryTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFocused
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onToggle,
        child: Row(
          children: [
            if (isFocused)
              Text(
                '\u25B6 ',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                ),
              ),
            Text(
              '$label: ${value ? 'on' : 'off'}',
              style: TextStyle(
                color: isFocused
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
            if (trailing != null) trailing!,
            if (secondaryTrailing != null) secondaryTrailing!,
          ],
        ),
      ),
    );
  }
}

// ─── Memory option tile ───

class _MemoryOptionTile extends StatelessWidget {
  final MemorySelectOption option;
  final bool isSelected;
  final VoidCallback onTap;

  const _MemoryOptionTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
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
              option.isFolder ? Icons.folder_open : Icons.description_outlined,
              size: 16,
              color: isSelected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      color: isSelected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface,
                      fontSize: 13,
                    ),
                  ),
                  if (option.description.isNotEmpty)
                    Text(
                      option.description,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── MemoryUpdateNotification (mirrors MemoryUpdateNotification.tsx) ───

class MemoryUpdateNotification extends StatelessWidget {
  final String memoryPath;

  const MemoryUpdateNotification({super.key, required this.memoryPath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPath = getRelativeMemoryPath(memoryPath);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.memory,
            size: 14,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 6),
          Text(
            'Memory updated in $displayPath',
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 13,
            ),
          ),
          Text(
            ' \u00B7 /memory to edit',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
