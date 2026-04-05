// Skills Panel — Browse, search, and load skill modules into the session.
// Modeled after SAIA's skills tab with two loading modes:
//   - Load in Session: sends the skill content as a visible prompt
//   - Load in Context: silently injects the skill into the system context

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:sint/sint.dart';

import '../controllers/chat_controller.dart';

// ── Category Metadata ──

class _CategoryMeta {
  final String label;
  final IconData icon;
  const _CategoryMeta(this.label, this.icon);
}

/// Maps asset folder names to display labels and icons.
const Map<String, _CategoryMeta> _categoryMetadata = {
  // Cognitive pillars
  'chain_of_thought': _CategoryMeta('Chain of Thought', Icons.lightbulb_outline),
  'metacognition': _CategoryMeta('Metacognition', Icons.psychology_outlined),
  'distillation': _CategoryMeta('Distillation', Icons.compress),
  'agency': _CategoryMeta('Agency', Icons.precision_manufacturing_outlined),
  'adaptability': _CategoryMeta('Adaptability', Icons.auto_fix_high),
  'coherence': _CategoryMeta('Coherence', Icons.verified_outlined),
  'introspection': _CategoryMeta('Introspection', Icons.self_improvement),
  'consolidation': _CategoryMeta('Consolidation', Icons.bedtime_outlined),
  'personality': _CategoryMeta('Writing & Voice', Icons.edit_note),
  'cognitive_pipeline': _CategoryMeta('Cognitive Pipeline', Icons.account_tree_outlined),
  'memory': _CategoryMeta('Memory', Icons.memory_outlined),

  // Technical categories
  'agents': _CategoryMeta('AI Agents', Icons.smart_toy_outlined),
  'ai_ml': _CategoryMeta('AI & ML', Icons.model_training),
  'api_design': _CategoryMeta('API Design', Icons.api),
  'architecture': _CategoryMeta('Architecture', Icons.architecture),
  'backend': _CategoryMeta('Backend', Icons.dns_outlined),
  'business': _CategoryMeta('Business', Icons.business_outlined),
  'code_quality': _CategoryMeta('Code Quality', Icons.code),
  'content_writing': _CategoryMeta('Content Writing', Icons.article_outlined),
  'context': _CategoryMeta('Context Mgmt', Icons.dashboard_customize),
  'data_storage': _CategoryMeta('Data & Storage', Icons.storage_outlined),
  'debugging': _CategoryMeta('Debugging', Icons.bug_report_outlined),
  'design_ui': _CategoryMeta('UI/UX Design', Icons.design_services_outlined),
  'documentation': _CategoryMeta('Documentation', Icons.description_outlined),
  'documents': _CategoryMeta('Documents', Icons.folder_outlined),
  'evaluation': _CategoryMeta('Evaluation', Icons.assessment_outlined),
  'flutter': _CategoryMeta('Flutter', Icons.flutter_dash),
  'frontend': _CategoryMeta('Frontend', Icons.web_outlined),
  'git_workflow': _CategoryMeta('Git Workflow', Icons.merge_type),
  'internationalization': _CategoryMeta('i18n', Icons.translate),
  'languages': _CategoryMeta('Languages', Icons.code_outlined),
  'performance': _CategoryMeta('Performance', Icons.speed_outlined),
  'planning': _CategoryMeta('Planning', Icons.event_note_outlined),
  'product': _CategoryMeta('Product', Icons.category_outlined),
  'prompting': _CategoryMeta('Prompting', Icons.chat_outlined),
  'research': _CategoryMeta('Research', Icons.science_outlined),
  'security': _CategoryMeta('Security', Icons.security_outlined),
  'testing': _CategoryMeta('Testing', Icons.quiz_outlined),
  'tools': _CategoryMeta('Tools', Icons.build_outlined),
  'workflow': _CategoryMeta('Workflow', Icons.linear_scale),
};

// ── Skill Entry ──

class _SkillEntry {
  final String name;
  final String displayName;
  final String category;
  final String assetPath;

  const _SkillEntry({
    required this.name,
    required this.displayName,
    required this.category,
    required this.assetPath,
  });
}

// ── Skills Panel Widget ──

class SkillsPanel extends StatefulWidget {
  final ColorScheme colorScheme;
  const SkillsPanel({super.key, required this.colorScheme});

  @override
  State<SkillsPanel> createState() => _SkillsPanelState();
}

class _SkillsPanelState extends State<SkillsPanel> {
  final _searchController = TextEditingController();
  final Map<String, List<_SkillEntry>> _categories = {};
  String? _expandedCategory;
  bool _loading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _discoverSkills();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Asset prefix — package assets are accessed via 'packages/neomage/' prefix.
  static const _assetPrefix = 'packages/neomage/assets/skills/';

  /// Discover skills from the AssetManifest.
  Future<void> _discoverSkills() async {
    try {
      // Use the modern AssetManifest API (works with both .json and .bin formats)
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final allAssets = manifest.listAssets();

      // Try package-prefixed path first, fallback to direct path (for standalone use)
      var skillPaths = allAssets
          .where((k) => k.startsWith(_assetPrefix) && k.endsWith('.md'))
          .where((k) => !k.endsWith('README.md'))
          .toList();

      if (skillPaths.isEmpty) {
        // Fallback: direct path (when running as the main app, not as a dependency)
        skillPaths = allAssets
            .where((k) => k.startsWith('assets/skills/') && k.endsWith('.md'))
            .where((k) => !k.endsWith('README.md'))
            .toList();
      }

      skillPaths.sort();

      final categories = <String, List<_SkillEntry>>{};

      for (final path in skillPaths) {
        // path: packages/neomage/assets/skills/{category}/{skill_name}.md
        // or:   assets/skills/{category}/{skill_name}.md
        final segments = path.split('/');
        if (segments.length < 4) continue;

        // Find 'skills' segment to extract category
        final skillsIdx = segments.indexOf('skills');
        if (skillsIdx < 0 || skillsIdx + 2 >= segments.length) continue;

        final category = segments[skillsIdx + 1];
        final fileName = segments.last.replaceAll('.md', '');
        final displayName = _formatDisplayName(fileName);

        categories.putIfAbsent(category, () => []);
        categories[category]!.add(_SkillEntry(
          name: fileName,
          displayName: displayName,
          category: category,
          assetPath: path,
        ));
      }

      // Sort skills within each category
      for (final list in categories.values) {
        list.sort((a, b) => a.displayName.compareTo(b.displayName));
      }

      if (mounted) {
        setState(() {
          _categories.clear();
          _categories.addAll(categories);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _formatDisplayName(String fileName) {
    return fileName
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  /// Load skill into the active chat session (visible to user).
  Future<void> _loadInSession(_SkillEntry skill) async {
    try {
      final content = await rootBundle.loadString(skill.assetPath);
      final chat = Sint.find<ChatController>();

      final prompt = '''I'd like to learn about the "${skill.displayName}" skill.
Please explain it with 5 concrete examples of how to apply it.

Here's the skill content:

$content''';

      chat.sendMessage(prompt);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Loaded "${skill.displayName}" in session'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load skill: $e')),
        );
      }
    }
  }

  /// Load skill silently into context (not visible to user).
  Future<void> _loadInContext(_SkillEntry skill) async {
    try {
      final content = await rootBundle.loadString(skill.assetPath);
      final chat = Sint.find<ChatController>();

      // Send as a context signal — the skill content enhances the
      // next responses without being displayed as a user message.
      final contextSignal =
          '[CONTEXT — Skill loaded: ${skill.displayName}]\n\n$content\n\n'
          'Apply this knowledge to enhance your responses in this session. '
          'Do not mention that a skill was loaded unless the user asks.';

      chat.sendContextSignal(contextSignal);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${skill.displayName}" loaded in context'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load skill: $e')),
        );
      }
    }
  }

  /// Filter categories and skills based on search query.
  Map<String, List<_SkillEntry>> get _filteredCategories {
    if (_searchQuery.isEmpty) return _categories;

    final q = _searchQuery.toLowerCase();
    final filtered = <String, List<_SkillEntry>>{};

    for (final entry in _categories.entries) {
      final categoryMeta = _categoryMetadata[entry.key];
      final categoryMatch = entry.key.toLowerCase().contains(q) ||
          (categoryMeta?.label.toLowerCase().contains(q) ?? false);

      final matchingSkills = entry.value
          .where((s) =>
              s.displayName.toLowerCase().contains(q) ||
              s.name.toLowerCase().contains(q) ||
              categoryMatch)
          .toList();

      if (matchingSkills.isNotEmpty) {
        filtered[entry.key] = matchingSkills;
      }
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_categories.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome,
                  size: 48, color: cs.onSurfaceVariant.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text('No skills found',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 8),
              Text(
                'Add .md files to assets/skills/ to get started.',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredCategories;
    final sortedCategories = filtered.keys.toList()..sort();

    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search skills...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            style: const TextStyle(fontSize: 13),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),

        // Stats bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Icon(Icons.auto_awesome, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                '${_categories.values.fold<int>(0, (sum, list) => sum + list.length)} skills in ${_categories.length} categories',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Category list
        Expanded(
          child: ListView.builder(
            itemCount: sortedCategories.length,
            itemBuilder: (context, index) {
              final category = sortedCategories[index];
              final skills = filtered[category]!;
              final meta = _categoryMetadata[category] ??
                  _CategoryMeta(
                    _formatDisplayName(category),
                    Icons.folder_outlined,
                  );
              final isExpanded = _expandedCategory == category ||
                  (_searchQuery.isNotEmpty && skills.length <= 5);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category header
                  InkWell(
                    onTap: () {
                      setState(() {
                        _expandedCategory =
                            _expandedCategory == category ? null : category;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: Row(
                        children: [
                          Icon(meta.icon, size: 16, color: cs.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              meta.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: cs.onSurface,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${skills.length}',
                              style: TextStyle(
                                fontSize: 10,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            isExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Skills list (expanded)
                  if (isExpanded)
                    ...skills.map((skill) => _SkillTile(
                          skill: skill,
                          colorScheme: cs,
                          onLoadInSession: () => _loadInSession(skill),
                          onLoadInContext: () => _loadInContext(skill),
                        )),

                  if (index < sortedCategories.length - 1)
                    Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Skill Tile ──

class _SkillTile extends StatelessWidget {
  final _SkillEntry skill;
  final ColorScheme colorScheme;
  final VoidCallback onLoadInSession;
  final VoidCallback onLoadInContext;

  const _SkillTile({
    required this.skill,
    required this.colorScheme,
    required this.onLoadInSession,
    required this.onLoadInContext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 36, right: 8, top: 2, bottom: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onLoadInSession,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.article_outlined,
                size: 14,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  skill.displayName,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Load in context button (silent)
              Tooltip(
                message: 'Load in context (silent)',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onLoadInContext,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.visibility_off_outlined,
                      size: 14,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
              // Load in session button (visible)
              Tooltip(
                message: 'Load in session',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onLoadInSession,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.chat_bubble_outline,
                      size: 14,
                      color: colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
