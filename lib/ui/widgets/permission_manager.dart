// PermissionManager — port of neomage/src/components/PermissionManager/.
// Permission rule editor, review, and management UI.

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../utils/constants/neomage_translation_constants.dart';

// ─── Types ───

/// Display info for a permission rule.
class PermissionRuleDisplay {
  final String pattern;
  final String behavior; // 'allow', 'deny', 'ask'
  final String scope; // 'tool', 'file', 'command', 'mcp'
  final String source; // 'user', 'project', 'local', 'policy'
  final String? description;
  final DateTime? createdAt;
  final int hitCount;

  const PermissionRuleDisplay({
    required this.pattern,
    required this.behavior,
    required this.scope,
    required this.source,
    this.description,
    this.createdAt,
    this.hitCount = 0,
  });
}

/// Permission mode display info.
class PermissionModeDisplay {
  final String mode; // 'default', 'accept-edits', 'plan', 'full-auto'
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  const PermissionModeDisplay({
    required this.mode,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });

  static List<PermissionModeDisplay> get modes => [
    PermissionModeDisplay(
      mode: 'default',
      label: NeomageTranslationConstants.permDefault.tr,
      description:
          'Ask permission for file writes and commands. Reads are always allowed.',
      icon: Icons.security,
      color: Colors.blue,
    ),
    PermissionModeDisplay(
      mode: 'accept-edits',
      label: NeomageTranslationConstants.permAcceptEdits.tr,
      description: NeomageTranslationConstants.permAcceptEditsDesc.tr,
      icon: Icons.edit_note,
      color: Colors.orange,
    ),
    PermissionModeDisplay(
      mode: 'plan',
      label: NeomageTranslationConstants.permPlanMode.tr,
      description: NeomageTranslationConstants.permPlanModeDesc.tr,
      icon: Icons.architecture,
      color: Colors.purple,
    ),
    PermissionModeDisplay(
      mode: 'full-auto',
      label: NeomageTranslationConstants.permFullAuto.tr,
      description: NeomageTranslationConstants.permFullAutoDesc.tr,
      icon: Icons.flash_on,
      color: Colors.red,
    ),
  ];
}

// ─── PermissionManagerWidget ───

/// Full permission management UI with mode selector and rule editor.
class PermissionManagerWidget extends StatefulWidget {
  final String currentMode;
  final List<PermissionRuleDisplay> rules;
  final ValueChanged<String> onModeChanged;
  final void Function(PermissionRuleDisplay rule) onAddRule;
  final void Function(int index) onDeleteRule;
  final void Function(int index, PermissionRuleDisplay rule) onEditRule;

  const PermissionManagerWidget({
    super.key,
    required this.currentMode,
    required this.rules,
    required this.onModeChanged,
    required this.onAddRule,
    required this.onDeleteRule,
    required this.onEditRule,
  });

  @override
  State<PermissionManagerWidget> createState() =>
      _PermissionManagerWidgetState();
}

class _PermissionManagerWidgetState extends State<PermissionManagerWidget> {
  String _filterScope = 'all';
  final String _filterSource = 'all';
  String _filterBehavior = 'all';

  List<PermissionRuleDisplay> get _filteredRules {
    return widget.rules.where((r) {
      if (_filterScope != 'all' && r.scope != _filterScope) return false;
      if (_filterSource != 'all' && r.source != _filterSource) return false;
      if (_filterBehavior != 'all' && r.behavior != _filterBehavior) {
        return false;
      }
      return true;
    }).toList();
  }

  void _showAddRuleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => _RuleEditorDialog(
        onSave: (rule) {
          widget.onAddRule(rule);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showEditRuleDialog(int index, PermissionRuleDisplay rule) {
    showDialog(
      context: context,
      builder: (ctx) => _RuleEditorDialog(
        existingRule: rule,
        onSave: (updated) {
          widget.onEditRule(index, updated);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  Color _behaviorColor(String behavior) {
    switch (behavior) {
      case 'allow':
        return Colors.green;
      case 'deny':
        return Colors.red;
      case 'ask':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  IconData _behaviorIcon(String behavior) {
    switch (behavior) {
      case 'allow':
        return Icons.check_circle_outline;
      case 'deny':
        return Icons.block;
      case 'ask':
        return Icons.help_outline;
      default:
        return Icons.help;
    }
  }

  IconData _scopeIcon(String scope) {
    switch (scope) {
      case 'tool':
        return Icons.build_outlined;
      case 'file':
        return Icons.insert_drive_file_outlined;
      case 'command':
        return Icons.terminal;
      case 'mcp':
        return Icons.dns_outlined;
      default:
        return Icons.security;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode selector
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Permission Mode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PermissionModeDisplay.modes.map((mode) {
                  final isActive = widget.currentMode == mode.mode;
                  return InkWell(
                    onTap: () => widget.onModeChanged(mode.mode),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 160,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isActive
                            ? mode.color.withValues(alpha: 0.15)
                            : (isDark
                                  ? Colors.white.withValues(alpha: 0.04)
                                  : Colors.black.withValues(alpha: 0.03)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? mode.color
                              : (isDark
                                    ? Colors.white.withValues(alpha: 0.1)
                                    : Colors.black.withValues(alpha: 0.1)),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(mode.icon, size: 18, color: mode.color),
                              const SizedBox(width: 6),
                              Text(
                                mode.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            mode.description,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const Divider(),

        // Rules section
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Text(
                'Permission Rules',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '(${widget.rules.length})',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showAddRuleDialog,
                icon: const Icon(Icons.add, size: 16),
                label: Text(NeomageTranslationConstants.addRule.tr, style: const TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Filters
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _filterChip('All', 'all', _filterScope, (v) {
                setState(() => _filterScope = v);
              }),
              const SizedBox(width: 4),
              _filterChip(NeomageTranslationConstants.tool.tr, 'tool', _filterScope, (v) {
                setState(() => _filterScope = v);
              }),
              _filterChip(NeomageTranslationConstants.file.tr, 'file', _filterScope, (v) {
                setState(() => _filterScope = v);
              }),
              _filterChip(NeomageTranslationConstants.cmd.tr, 'command', _filterScope, (v) {
                setState(() => _filterScope = v);
              }),
              const SizedBox(width: 12),
              _filterChip(NeomageTranslationConstants.allow.tr, 'allow', _filterBehavior, (v) {
                setState(
                  () => _filterBehavior = v == _filterBehavior ? 'all' : v,
                );
              }),
              _filterChip(NeomageTranslationConstants.deny.tr, 'deny', _filterBehavior, (v) {
                setState(
                  () => _filterBehavior = v == _filterBehavior ? 'all' : v,
                );
              }),
              _filterChip(NeomageTranslationConstants.ask.tr, 'ask', _filterBehavior, (v) {
                setState(
                  () => _filterBehavior = v == _filterBehavior ? 'all' : v,
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Rules list
        Expanded(
          child: _filteredRules.isEmpty
              ? Center(
                  child: Text(
                    'No rules match filters',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filteredRules.length,
                  itemBuilder: (context, index) {
                    final rule = _filteredRules[index];
                    final originalIndex = widget.rules.indexOf(rule);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 4),
                      color: isDark ? const Color(0xFF1E1E36) : Colors.white,
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          _behaviorIcon(rule.behavior),
                          color: _behaviorColor(rule.behavior),
                          size: 20,
                        ),
                        title: Row(
                          children: [
                            Icon(
                              _scopeIcon(rule.scope),
                              size: 14,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                rule.pattern,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 13,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _behaviorColor(
                                  rule.behavior,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                rule.behavior.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: _behaviorColor(rule.behavior),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'from ${rule.source}',
                              style: TextStyle(
                                fontSize: 10,
                                color: isDark ? Colors.white30 : Colors.black26,
                              ),
                            ),
                            if (rule.hitCount > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${rule.hitCount} hits',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () =>
                                  _showEditRuleDialog(originalIndex, rule),
                              icon: const Icon(Icons.edit, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  widget.onDeleteRule(originalIndex),
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 16,
                                color: Colors.red,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 28,
                                minHeight: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _filterChip(
    String label,
    String value,
    String current,
    ValueChanged<String> onSelected,
  ) {
    final isActive = current == value;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: isActive,
        onSelected: (_) => onSelected(value),
        padding: EdgeInsets.zero,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ─── Rule Editor Dialog ───

class _RuleEditorDialog extends StatefulWidget {
  final PermissionRuleDisplay? existingRule;
  final ValueChanged<PermissionRuleDisplay> onSave;

  const _RuleEditorDialog({this.existingRule, required this.onSave});

  @override
  State<_RuleEditorDialog> createState() => _RuleEditorDialogState();
}

class _RuleEditorDialogState extends State<_RuleEditorDialog> {
  late final TextEditingController _patternController;
  late final TextEditingController _descriptionController;
  late String _behavior;
  late String _scope;

  @override
  void initState() {
    super.initState();
    _patternController = TextEditingController(
      text: widget.existingRule?.pattern ?? '',
    );
    _descriptionController = TextEditingController(
      text: widget.existingRule?.description ?? '',
    );
    _behavior = widget.existingRule?.behavior ?? 'allow';
    _scope = widget.existingRule?.scope ?? 'tool';
  }

  @override
  void dispose() {
    _patternController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existingRule != null ? NeomageTranslationConstants.editRule.tr : NeomageTranslationConstants.addRule.tr),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pattern
            TextField(
              controller: _patternController,
              decoration: InputDecoration(
                labelText: 'Pattern',
                hintText: NeomageTranslationConstants.rulePatternHint.tr,
              ),
            ),
            const SizedBox(height: 12),

            // Behavior
            Text(NeomageTranslationConstants.behavior.tr, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'allow', label: Text(NeomageTranslationConstants.allow.tr)),
                ButtonSegment(value: 'deny', label: Text(NeomageTranslationConstants.deny.tr)),
                ButtonSegment(value: 'ask', label: Text(NeomageTranslationConstants.ask.tr)),
              ],
              selected: {_behavior},
              onSelectionChanged: (s) => setState(() => _behavior = s.first),
            ),
            const SizedBox(height: 12),

            // Scope
            Text(NeomageTranslationConstants.scope.tr, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'tool', label: Text(NeomageTranslationConstants.tool.tr)),
                ButtonSegment(value: 'file', label: Text(NeomageTranslationConstants.file.tr)),
                ButtonSegment(value: 'command', label: Text(NeomageTranslationConstants.cmd.tr)),
                ButtonSegment(value: 'mcp', label: Text(NeomageTranslationConstants.mcp.tr)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(height: 12),

            // Description
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: '${NeomageTranslationConstants.description.tr} (optional)',
                hintText: NeomageTranslationConstants.ruleReasonHint.tr,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(NeomageTranslationConstants.cancel.tr),
        ),
        ElevatedButton(
          onPressed: () {
            final pattern = _patternController.text.trim();
            if (pattern.isEmpty) return;

            widget.onSave(
              PermissionRuleDisplay(
                pattern: pattern,
                behavior: _behavior,
                scope: _scope,
                source: 'user',
                description: _descriptionController.text.trim().isEmpty
                    ? null
                    : _descriptionController.text.trim(),
                createdAt: DateTime.now(),
              ),
            );
          },
          child: Text(NeomageTranslationConstants.save.tr),
        ),
      ],
    );
  }
}
