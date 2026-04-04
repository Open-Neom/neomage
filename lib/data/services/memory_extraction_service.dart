// Memory extraction service — port of neom_claw/src/services/extractMemories/.
// Extracts, classifies, deduplicates, and ranks memory candidates from
// conversations, tool output, and code changes.

import 'dart:math';

// Re-use the canonical MemoryCategory from the team memory service.
// If the import path differs in your tree, adjust accordingly.
import 'package:neom_claw/data/services/team_memory_service.dart'
    show MemoryCategory;

// ── Enums ──────────────────────────────────────────────────────────────────

/// Where a memory candidate was extracted from.
enum ExtractionSource {
  /// Extracted from conversation messages.
  conversation,

  /// Extracted from tool output (bash, file read, etc.).
  toolOutput,

  /// Extracted from a code diff / change description.
  codeChange,

  /// Explicitly provided by the user (e.g. "remember that ...").
  userExplicit,
}

// ── Data classes ───────────────────────────────────────────────────────────

/// A potential memory extracted from some source, awaiting approval.
class MemoryCandidate {
  final String content;
  final ExtractionSource source;
  final MemoryCategory category;

  /// Confidence score in [0, 1] — how likely this is a useful memory.
  final double confidence;

  /// Short explanation of why this was extracted.
  final String reasoning;

  /// Optional related file path.
  final String? relatedFile;

  final DateTime timestamp;

  MemoryCandidate({
    required this.content,
    required this.source,
    required this.category,
    required this.confidence,
    required this.reasoning,
    this.relatedFile,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  @override
  String toString() =>
      'MemoryCandidate(${category.name}, conf=$confidence, "$content")';
}

/// Configuration for the extraction pipeline.
class ExtractionConfig {
  /// Minimum confidence to even consider a candidate.
  final double minConfidence;

  /// Maximum number of candidates surfaced per session.
  final int maxPerSession;

  /// Which categories to extract.  Empty means all.
  final Set<MemoryCategory> categories;

  /// Automatically add to NEOMCLAW.md if confidence >= this threshold.
  /// Set to `null` to disable auto-approval.
  final double? autoApproveThreshold;

  const ExtractionConfig({
    this.minConfidence = 0.4,
    this.maxPerSession = 15,
    this.categories = const {},
    this.autoApproveThreshold,
  });

  /// Whether [category] is enabled.
  bool isCategoryEnabled(MemoryCategory category) =>
      categories.isEmpty || categories.contains(category);
}

// ── Pattern matchers ───────────────────────────────────────────────────────

/// A pattern rule that can recognise a particular kind of memory in text.
class _PatternRule {
  final RegExp pattern;
  final MemoryCategory category;
  final double baseConfidence;
  final String label;

  const _PatternRule({
    required this.pattern,
    required this.category,
    required this.baseConfidence,
    required this.label,
  });
}

/// Built-in pattern rules.
final List<_PatternRule> _builtInPatterns = [
  // Coding conventions
  _PatternRule(
    pattern: RegExp(r'\b(always|never|prefer|avoid|must|should)\b.*\b(use|import|write|name|format|indent|style)\b', caseSensitive: false),
    category: MemoryCategory.codingConventions,
    baseConfidence: 0.7,
    label: 'coding convention',
  ),
  _PatternRule(
    pattern: RegExp(r'\b(naming convention|code style|lint rule|formatter)\b', caseSensitive: false),
    category: MemoryCategory.codingConventions,
    baseConfidence: 0.75,
    label: 'coding convention (explicit)',
  ),

  // Build instructions
  _PatternRule(
    pattern: RegExp(r'\b(npm run|yarn |pnpm |make |gradle |cargo |flutter |dart |go build|mvn |bazel )\b', caseSensitive: false),
    category: MemoryCategory.buildInstructions,
    baseConfidence: 0.65,
    label: 'build command',
  ),
  _PatternRule(
    pattern: RegExp(r'\b(build step|build command|compile with|to build)\b', caseSensitive: false),
    category: MemoryCategory.buildInstructions,
    baseConfidence: 0.7,
    label: 'build instruction',
  ),

  // Test patterns
  _PatternRule(
    pattern: RegExp(r'\b(test with|run tests|test command|pytest|jest|vitest|flutter test)\b', caseSensitive: false),
    category: MemoryCategory.testingGuidelines,
    baseConfidence: 0.7,
    label: 'test pattern',
  ),
  _PatternRule(
    pattern: RegExp(r'\b(test coverage|unit test|integration test|e2e test|snapshot test)\b', caseSensitive: false),
    category: MemoryCategory.testingGuidelines,
    baseConfidence: 0.6,
    label: 'testing guideline',
  ),

  // Architecture
  _PatternRule(
    pattern: RegExp(r'\b(architecture|design pattern|layer|module|boundary|separation of concerns)\b', caseSensitive: false),
    category: MemoryCategory.architecture,
    baseConfidence: 0.6,
    label: 'architecture note',
  ),
  _PatternRule(
    pattern: RegExp(r'\b(monorepo|microservice|MVC|MVVM|clean architecture|hexagonal|domain.driven)\b', caseSensitive: false),
    category: MemoryCategory.architecture,
    baseConfidence: 0.7,
    label: 'architecture pattern',
  ),

  // Known issues
  _PatternRule(
    pattern: RegExp(r'\b(known issue|known bug|workaround|hack|TODO|FIXME|HACK|XXX)\b', caseSensitive: false),
    category: MemoryCategory.knownIssues,
    baseConfidence: 0.65,
    label: 'known issue',
  ),
  _PatternRule(
    pattern: RegExp(r"\b(breaks when|fails if|do not|don\'t|careful with|watch out)\b", caseSensitive: false),
    category: MemoryCategory.knownIssues,
    baseConfidence: 0.55,
    label: 'potential issue',
  ),

  // Team preferences
  _PatternRule(
    pattern: RegExp(r'\b(we prefer|team uses|our convention|our standard|company policy)\b', caseSensitive: false),
    category: MemoryCategory.teamPreferences,
    baseConfidence: 0.75,
    label: 'team preference',
  ),

  // Deployment
  _PatternRule(
    pattern: RegExp(r'\b(deploy to|deployment|CI/CD|pipeline|staging|production|release process)\b', caseSensitive: false),
    category: MemoryCategory.deploymentProcess,
    baseConfidence: 0.65,
    label: 'deployment info',
  ),

  // Project structure
  _PatternRule(
    pattern: RegExp(r'\b(project structure|directory layout|folder structure|monorepo layout)\b', caseSensitive: false),
    category: MemoryCategory.projectStructure,
    baseConfidence: 0.7,
    label: 'project structure',
  ),

  // Dependencies
  _PatternRule(
    pattern: RegExp(r'\b(depends on|dependency|required package|peer dep|version constraint)\b', caseSensitive: false),
    category: MemoryCategory.dependencies,
    baseConfidence: 0.55,
    label: 'dependency info',
  ),
];

// ── Service ────────────────────────────────────────────────────────────────

/// Extracts structured memory candidates from various sources.
class MemoryExtractionService {
  final ExtractionConfig config;

  /// Running count of candidates produced this session.
  int _sessionCount = 0;

  MemoryExtractionService({this.config = const ExtractionConfig()});

  // ── Extraction entry points ───────────────────────────────────────────

  /// Extract memory candidates from a list of conversation messages.
  ///
  /// Each message is expected to be a map with at least a `role` and
  /// `content` key.
  List<MemoryCandidate> extractFromConversation(
    List<Map<String, dynamic>> messages,
  ) {
    final candidates = <MemoryCandidate>[];

    for (final msg in messages) {
      final content = msg['content']?.toString() ?? '';
      if (content.length < 10) continue;

      // User-explicit memories.
      if (_isExplicitMemory(content)) {
        candidates.add(MemoryCandidate(
          content: _cleanExplicitMemory(content),
          source: ExtractionSource.userExplicit,
          category: classifyMemory(content).category,
          confidence: 0.95,
          reasoning: 'User explicitly asked to remember this.',
        ));
        continue;
      }

      candidates.addAll(_matchPatterns(content, ExtractionSource.conversation));
    }

    return _filterAndCap(candidates);
  }

  /// Extract from a tool's output.
  List<MemoryCandidate> extractFromToolOutput(
    String toolName,
    String output,
  ) {
    if (output.length < 20) return [];

    final candidates =
        _matchPatterns(output, ExtractionSource.toolOutput);

    // Boost confidence for build/test tool output.
    if (toolName == 'bash' || toolName == 'shell') {
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        if (c.category == MemoryCategory.buildInstructions ||
            c.category == MemoryCategory.testingGuidelines) {
          candidates[i] = MemoryCandidate(
            content: c.content,
            source: c.source,
            category: c.category,
            confidence: min(c.confidence + 0.1, 1.0),
            reasoning: '${c.reasoning} (from $toolName output)',
            relatedFile: c.relatedFile,
          );
        }
      }
    }

    return _filterAndCap(candidates);
  }

  /// Extract from a code diff with an optional description.
  List<MemoryCandidate> extractFromCodeChange(
    String diff,
    String description,
  ) {
    final combined = '$description\n$diff';
    final candidates =
        _matchPatterns(combined, ExtractionSource.codeChange);

    // Try to pull the file path from the diff header.
    final fileMatch = RegExp(r'^[+\-]{3} [ab]/(.+)$', multiLine: true)
        .firstMatch(diff);
    final relatedFile = fileMatch?.group(1);

    if (relatedFile != null) {
      for (var i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        candidates[i] = MemoryCandidate(
          content: c.content,
          source: c.source,
          category: c.category,
          confidence: c.confidence,
          reasoning: c.reasoning,
          relatedFile: relatedFile,
        );
      }
    }

    return _filterAndCap(candidates);
  }

  // ── Classification ────────────────────────────────────────────────────

  /// Classify a piece of text into a [MemoryCategory] with confidence.
  ({MemoryCategory category, double confidence}) classifyMemory(String text) {
    MemoryCategory best = MemoryCategory.other;
    double bestConf = 0.0;

    for (final rule in _builtInPatterns) {
      if (rule.pattern.hasMatch(text) && rule.baseConfidence > bestConf) {
        best = rule.category;
        bestConf = rule.baseConfidence;
      }
    }

    return (category: best, confidence: bestConf);
  }

  // ── Deduplication ─────────────────────────────────────────────────────

  /// Remove candidates whose content is already present in [existing].
  List<MemoryCandidate> deduplicateMemories(
    List<MemoryCandidate> candidates,
    List<String> existing,
  ) {
    final normalised =
        existing.map((e) => _normalise(e)).toSet();

    return candidates.where((c) {
      final norm = _normalise(c.content);
      // Exact match or high-overlap substring.
      if (normalised.contains(norm)) return false;
      return !normalised.any((e) => _similarity(e, norm) > 0.85);
    }).toList();
  }

  // ── Ranking ───────────────────────────────────────────────────────────

  /// Sort candidates by usefulness (highest first).
  List<MemoryCandidate> rankMemories(List<MemoryCandidate> candidates) {
    final sorted = List<MemoryCandidate>.from(candidates);
    sorted.sort((a, b) {
      // Primary: confidence descending.
      final confCmp = b.confidence.compareTo(a.confidence);
      if (confCmp != 0) return confCmp;
      // Secondary: explicit > conversation > codeChange > toolOutput.
      return _sourceRank(b.source).compareTo(_sourceRank(a.source));
    });
    return sorted;
  }

  // ── Formatting ────────────────────────────────────────────────────────

  /// Format a candidate as a markdown bullet suitable for NEOMCLAW.md.
  String formatForStorage(MemoryCandidate candidate) {
    final prefix = candidate.relatedFile != null
        ? '(`${candidate.relatedFile}`) '
        : '';
    return '- $prefix${candidate.content}';
  }

  /// Suggest which NEOMCLAW.md section a candidate should go into.
  String suggestSection(MemoryCandidate candidate) {
    return switch (candidate.category) {
      MemoryCategory.codingConventions => 'Coding Conventions',
      MemoryCategory.buildInstructions => 'Build & Run',
      MemoryCategory.testingGuidelines => 'Testing',
      MemoryCategory.architecture => 'Architecture',
      MemoryCategory.knownIssues => 'Known Issues',
      MemoryCategory.teamPreferences => 'Team Preferences',
      MemoryCategory.deploymentProcess => 'Deployment',
      MemoryCategory.projectStructure => 'Project Structure',
      MemoryCategory.dependencies => 'Dependencies',
      MemoryCategory.other => 'Notes',
    };
  }

  // ── Batch ─────────────────────────────────────────────────────────────

  /// Run extraction over an entire session history and return ranked,
  /// deduplicated candidates.
  List<MemoryCandidate> batchExtract(
    List<Map<String, dynamic>> sessionHistory, {
    List<String> existingMemories = const [],
  }) {
    final all = <MemoryCandidate>[];

    for (final entry in sessionHistory) {
      final type = entry['type']?.toString();

      switch (type) {
        case 'message':
          final messages = entry['messages'];
          if (messages is List<Map<String, dynamic>>) {
            all.addAll(extractFromConversation(messages));
          }
        case 'tool_output':
          final tool = entry['tool']?.toString() ?? '';
          final output = entry['output']?.toString() ?? '';
          all.addAll(extractFromToolOutput(tool, output));
        case 'code_change':
          final diff = entry['diff']?.toString() ?? '';
          final desc = entry['description']?.toString() ?? '';
          all.addAll(extractFromCodeChange(diff, desc));
      }
    }

    final deduped = deduplicateMemories(all, existingMemories);
    return rankMemories(deduped);
  }

  // ── Private helpers ───────────────────────────────────────────────────

  bool _isExplicitMemory(String text) {
    final lower = text.toLowerCase();
    return lower.startsWith('remember that') ||
        lower.startsWith('remember:') ||
        lower.startsWith('note:') ||
        lower.startsWith('please remember') ||
        lower.contains('add to memory') ||
        lower.contains('save to neomclaw.md') ||
        lower.contains('add this to neomclaw.md');
  }

  String _cleanExplicitMemory(String text) {
    return text
        .replaceFirst(RegExp(r'^(remember that|remember:|note:|please remember)\s*', caseSensitive: false), '')
        .trim();
  }

  List<MemoryCandidate> _matchPatterns(String text, ExtractionSource source) {
    final candidates = <MemoryCandidate>[];
    final lines = text.split('\n');

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.length < 10 || trimmed.length > 300) continue;

      for (final rule in _builtInPatterns) {
        if (!config.isCategoryEnabled(rule.category)) continue;
        if (!rule.pattern.hasMatch(trimmed)) continue;

        candidates.add(MemoryCandidate(
          content: trimmed,
          source: source,
          category: rule.category,
          confidence: rule.baseConfidence,
          reasoning: 'Matched pattern: ${rule.label}',
        ));
        break; // One category per line.
      }
    }

    return candidates;
  }

  List<MemoryCandidate> _filterAndCap(List<MemoryCandidate> candidates) {
    final filtered = candidates
        .where((c) => c.confidence >= config.minConfidence)
        .toList();

    final remaining = config.maxPerSession - _sessionCount;
    if (remaining <= 0) return [];

    final capped =
        filtered.length > remaining ? filtered.sublist(0, remaining) : filtered;
    _sessionCount += capped.length;
    return capped;
  }

  static String _normalise(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Jaccard-ish word-level similarity in [0, 1].
  static double _similarity(String a, String b) {
    final wordsA = a.split(' ').toSet();
    final wordsB = b.split(' ').toSet();
    if (wordsA.isEmpty && wordsB.isEmpty) return 1.0;
    final intersection = wordsA.intersection(wordsB).length;
    final union = wordsA.union(wordsB).length;
    return intersection / union;
  }

  static int _sourceRank(ExtractionSource source) {
    return switch (source) {
      ExtractionSource.userExplicit => 3,
      ExtractionSource.conversation => 2,
      ExtractionSource.codeChange => 1,
      ExtractionSource.toolOutput => 0,
    };
  }
}
