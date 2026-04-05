// MemoryPanel — port of neomage/src/components/memory/
// Ports: MemoryFileSelector.tsx, MemoryUpdateNotification.tsx
//
// Provides:
// - MemoryFileSelector: a list/select widget for browsing and selecting
//   memory files (NEOMAGE.md files at user, project, and nested scopes).
//   Supports auto-memory and auto-dream toggles, agent memory folders,
//   and opening folders in the OS file manager.
// - MemoryUpdateNotification: inline notification shown when a memory
//   file has been updated.
// - MemoryPanelController: manages memory file discovery, toggle state,
//   and dream status.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/data/memdir/memdir_service.dart';
import 'package:neomage/data/memdir/memdir_paths.dart';
import 'package:neomage/data/memdir/memory_scan.dart';
import 'package:neomage/data/memdir/memory_types.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

import '../controllers/chat_controller.dart';
import '../../utils/constants/neomage_translation_constants.dart';

// ─── Memory file info model (mirrors MemoryFileInfo in utils/neomagemd.ts) ───

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
  final focusedToggle =
      Rxn<int>(); // null = no toggle focused, 0 = auto-memory, 1 = auto-dream
  final agentDefinitions = <AgentDefinitionInfo>[].obs;

  // Real memory data from MemdirService
  final memoryHeaders = <MemoryHeader>[].obs;
  final entrypointContent = Rxn<String>();
  final memoryDirPath = Rxn<String>();
  final isMemdirAvailable = false.obs;
  final isLoadingMemories = false.obs;
  final loadError = Rxn<String>();

  // Last selected path (persisted across opens)
  static String? _lastSelectedPath;

  // Folder prefix sentinel
  static const _openFolderPrefix = '__open_folder__';

  /// Get the MemdirService from ChatController.
  MemdirService? get _memdirService {
    try {
      return Sint.find<ChatController>().memdirService;
    } catch (_) {
      return null;
    }
  }

  // Computed paths
  String get userMemoryPath {
    final homeDir = Platform.environment['HOME'] ?? '';
    return '$homeDir/.neomage/NEOMAGE.md';
  }

  String get projectMemoryPath {
    return '${Directory.current.path}/NEOMAGE.md';
  }

  bool get hasUserMemory => memoryFiles.any((f) => f.path == userMemoryPath);

  bool get hasProjectMemory =>
      memoryFiles.any((f) => f.path == projectMemoryPath);

  bool get toggleFocused => focusedToggle.value != null;

  int get lastToggleIndex => showDreamRow.value ? 1 : 0;

  /// Memory headers grouped by MemoryType.
  Map<MemoryType, List<MemoryHeader>> get memoriesByType {
    final grouped = <MemoryType, List<MemoryHeader>>{};
    for (final type in MemoryType.values) {
      grouped[type] = [];
    }
    for (final header in memoryHeaders) {
      final type = header.type ?? MemoryType.reference;
      grouped[type]!.add(header);
    }
    // Remove empty groups
    grouped.removeWhere((_, v) => v.isEmpty);
    return grouped;
  }

  /// Build the full list of memory options for the select widget.
  List<MemorySelectOption> get memoryOptions {
    final options = <MemorySelectOption>[];
    final depths = <String, int>{};

    // All memory files (existing + placeholders for missing user/project)
    final allFiles = <MemoryFileInfo>[
      ...memoryFiles.where(
        (f) => f.path != userMemoryPath && f.path != projectMemoryPath,
      ),
      if (!hasUserMemory)
        MemoryFileInfo(path: userMemoryPath, type: 'User', exists: false),
      if (!hasProjectMemory)
        MemoryFileInfo(path: projectMemoryPath, type: 'Project', exists: false),
      // Include existing user and project files
      ...memoryFiles.where(
        (f) => f.path == userMemoryPath || f.path == projectMemoryPath,
      ),
    ];

    for (final file in allFiles) {
      final displayPath = getDisplayPath(file.path);
      final existsLabel = file.exists ? '' : ' (new)';
      final depth = file.parent != null ? (depths[file.parent] ?? 0) + 1 : 0;
      depths[file.path] = depth;
      final indent = depth > 0 ? '  ' * (depth - 1) : '';

      String label;
      if (file.type == 'User' &&
          !file.isNested &&
          file.path == userMemoryPath) {
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
        description = 'Saved in ~/.neomage/NEOMAGE.md';
      } else if (file.type == 'Project' &&
          !file.isNested &&
          file.path == projectMemoryPath) {
        description = 'Saved in ./NEOMAGE.md';
      } else if (file.parent != null) {
        description = '@-imported';
      } else if (file.isNested) {
        description = 'dynamically loaded';
      } else {
        description = '';
      }

      options.add(
        MemorySelectOption(
          label: label,
          value: file.path,
          description: description,
        ),
      );
    }

    // Folder options (auto-memory, team memory, agent memory)
    if (autoMemoryOn.value) {
      final autoMemPath = _getAutoMemPath();
      options.add(
        MemorySelectOption(
          label: NeomageTranslationConstants.openAutoMemory.tr,
          value: '$_openFolderPrefix$autoMemPath',
          isFolder: true,
        ),
      );

      // Agent memory folders
      for (final agent in agentDefinitions) {
        if (agent.memory != null) {
          final agentDir = _getAgentMemoryDir(agent.agentType, agent.memory!);
          options.add(
            MemorySelectOption(
              label: 'Open ${agent.agentType} agent memory',
              value: '$_openFolderPrefix$agentDir',
              description: '${agent.memory} scope',
              isFolder: true,
            ),
          );
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
    _loadRealMemories();
  }

  /// Load real memory data from the MemdirService.
  Future<void> _loadRealMemories() async {
    final service = _memdirService;
    if (service == null) {
      isMemdirAvailable.value = false;
      return;
    }

    isMemdirAvailable.value = true;
    isLoadingMemories.value = true;
    loadError.value = null;

    try {
      memoryDirPath.value = getAutoMemPath(projectRoot: service.projectRoot);

      final results = await Future.wait([
        service.scanMemories(),
        service.readEntrypoint(),
      ]);

      memoryHeaders.assignAll(results[0] as List<MemoryHeader>);
      entrypointContent.value = results[1] as String?;
    } catch (e) {
      loadError.value = e.toString();
    } finally {
      isLoadingMemories.value = false;
    }
  }

  /// Refresh memory data from disk.
  Future<void> refreshMemories() async {
    await _loadRealMemories();
  }

  /// Read a specific memory file's content.
  Future<String?> readMemoryFileContent(String filePath) async {
    final service = _memdirService;
    if (service == null) return null;
    return service.readMemoryFile(filePath);
  }

  /// Delete a memory file by filename.
  Future<bool> deleteMemoryFileByName(String filename) async {
    final service = _memdirService;
    if (service == null) return false;

    final deleted = await service.deleteMemoryFile(filename);
    if (deleted) {
      await refreshMemories();
    }
    return deleted;
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
  }

  /// Toggle auto-dream on/off.
  void toggleAutoDream() {
    autoDreamOn.value = !autoDreamOn.value;
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
    return '$homeDir/.neomage/auto-memory';
  }

  String _getAgentMemoryDir(String agentType, String scope) {
    final homeDir = Platform.environment['HOME'] ?? '';
    return '$homeDir/.neomage/agent-memory/$agentType/$scope';
  }

  Future<void> _openFolder(String path) async {
    try {
      await Directory(path).create(recursive: true);
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
                  label: NeomageTranslationConstants.autoMemory.tr,
                  value: controller.autoMemoryOn.value,
                  isFocused: controller.focusedToggle.value == 0,
                  onToggle: controller.toggleAutoMemory,
                ),

                // Auto-dream toggle (conditional)
                if (controller.showDreamRow.value)
                  _ToggleRow(
                    label: NeomageTranslationConstants.autoDream.tr,
                    value: controller.autoDreamOn.value,
                    isFocused: controller.focusedToggle.value == 1,
                    onToggle: controller.toggleAutoDream,
                    trailing: controller.dreamStatus.isNotEmpty
                        ? Text(
                            ' \u00B7 ${controller.dreamStatus}',
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
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
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.4,
                              ),
                              fontSize: 12,
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Real memory files section
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Memdir status / real memory content
                  _MemdirSection(controller: controller),

                  const Divider(height: 1),

                  // Legacy memory file list
                  ...options.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final option = entry.value;
                    final isSelected =
                        !controller.toggleFocused &&
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

// ─── Memdir section showing real persistent memory files ───

class _MemdirSection extends StatelessWidget {
  final MemoryPanelController controller;

  const _MemdirSection({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      if (!controller.isMemdirAvailable.value) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'Persistent memory is not available on this platform.',
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              fontSize: 12,
            ),
          ),
        );
      }

      if (controller.isLoadingMemories.value) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        );
      }

      if (controller.loadError.value != null) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Failed to load memories',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                controller.loadError.value!,
                style: TextStyle(
                  color: theme.colorScheme.error.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: controller.refreshMemories,
                child: Text(
                  'Retry',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      final dirPath = controller.memoryDirPath.value;
      final entrypoint = controller.entrypointContent.value;
      final grouped = controller.memoriesByType;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Memory directory path
          if (dirPath != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      getDisplayPath(dirPath),
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  InkWell(
                    onTap: controller.refreshMemories,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.refresh,
                        size: 14,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // MEMORY.md entrypoint content
          if (entrypoint != null && entrypoint.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MEMORY.md',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      entrypoint,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 10,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),

          // Grouped memory files
          if (grouped.isEmpty && entrypoint == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'No memory files yet.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
            )
          else
            ...grouped.entries.map(
              (entry) => _MemoryTypeGroup(
                type: entry.key,
                headers: entry.value,
                controller: controller,
              ),
            ),
        ],
      );
    });
  }
}

// ─── Memory type group (displays headers grouped by type) ───

class _MemoryTypeGroup extends StatelessWidget {
  final MemoryType type;
  final List<MemoryHeader> headers;
  final MemoryPanelController controller;

  const _MemoryTypeGroup({
    required this.type,
    required this.headers,
    required this.controller,
  });

  String get _typeLabel => switch (type) {
    MemoryType.user => 'User',
    MemoryType.feedback => 'Feedback',
    MemoryType.project => 'Project',
    MemoryType.reference => 'Reference',
  };

  IconData get _typeIcon => switch (type) {
    MemoryType.user => Icons.person_outline,
    MemoryType.feedback => Icons.rate_review_outlined,
    MemoryType.project => Icons.work_outline,
    MemoryType.reference => Icons.link,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Type header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Icon(
                _typeIcon,
                size: 14,
                color: theme.colorScheme.primary.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 6),
              Text(
                '$_typeLabel (${headers.length})',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Memory file entries
        ...headers.map(
          (header) => _MemoryHeaderTile(
            header: header,
            controller: controller,
          ),
        ),
      ],
    );
  }
}

// ─── Memory header tile (single memory file entry) ───

class _MemoryHeaderTile extends StatelessWidget {
  final MemoryHeader header;
  final MemoryPanelController controller;

  const _MemoryHeaderTile({
    required this.header,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final age = _formatAge(header.modified);

    return InkWell(
      onTap: () => _showContentDialog(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    header.filename,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface,
                      fontSize: 12,
                    ),
                  ),
                  if (header.description != null)
                    Text(
                      header.description!,
                      style: TextStyle(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.5,
                        ),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              age,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAge(DateTime modified) {
    final days = DateTime.now().difference(modified).inDays;
    if (days == 0) return 'today';
    if (days == 1) return 'yesterday';
    if (days < 7) return '${days}d ago';
    return '${(days / 7).floor()}w ago';
  }

  Future<void> _showContentDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final content = await controller.readMemoryFileContent(header.filePath);

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Expanded(
              child: Text(
                header.filename,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            if (header.type != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  header.type!.name,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontSize: 11,
                  ),
                ),
              ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (header.description != null) ...[
                  Text(
                    header.description!,
                    style: TextStyle(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(),
                  const SizedBox(height: 8),
                ],
                Text(
                  content ?? '(unable to read file)',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  getDisplayPath(header.filePath),
                  style: TextStyle(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: dialogContext,
                builder: (confirmContext) => AlertDialog(
                  title: const Text('Delete memory file?'),
                  content: Text(
                    'This will permanently delete "${header.filename}".',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          Navigator.of(confirmContext).pop(false),
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.of(confirmContext).pop(true),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                await controller.deleteMemoryFileByName(header.filename);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
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
            ?trailing,
            ?secondaryTrailing,
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
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.4,
                        ),
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
            style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 13),
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
