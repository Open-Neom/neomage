// Neomage System Prompt — loads personality modules from assets/personality/
// and builds the dynamic system prompt at app initialization.

import 'package:flutter/services.dart' show rootBundle;

/// Loads and assembles the Neomage personality from modular markdown files.
class NeomageSystemPrompt {
  NeomageSystemPrompt._();

  // Personality module contents (loaded once at startup).
  static String _identity = '';
  static String _cognition = '';
  static String _capabilities = '';
  static String _memory = '';
  static String _metacognition = '';
  static String _coherence = '';
  static String _introspection = '';
  static String _consolidation = '';
  static String _agency = '';
  static String _artifacts = '';
  static String _tools = '';
  static String _manus = '';

  static bool _loaded = false;

  /// Load all personality modules from assets. Call once at app init.
  static Future<void> load() async {
    if (_loaded) return;

    final results = await Future.wait([
      _loadAsset('assets/personality/IDENTITY.md'),
      _loadAsset('assets/personality/COGNITION.md'),
      _loadAsset('assets/personality/CAPABILITIES.md'),
      _loadAsset('assets/personality/MEMORY.md'),
      _loadAsset('assets/personality/METACOGNITION.md'),
      _loadAsset('assets/personality/COHERENCE.md'),
      _loadAsset('assets/personality/INTROSPECTION.md'),
      _loadAsset('assets/personality/CONSOLIDATION.md'),
      _loadAsset('assets/personality/AGENCY.md'),
      _loadAsset('assets/personality/ARTIFACTS.md'),
      _loadAsset('assets/personality/TOOLS.md'),
      _loadAsset('assets/personality/MANUS.md'),
    ]);

    _identity = results[0];
    _cognition = results[1];
    _capabilities = results[2];
    _memory = results[3];
    _metacognition = results[4];
    _coherence = results[5];
    _introspection = results[6];
    _consolidation = results[7];
    _agency = results[8];
    _artifacts = results[9];
    _tools = results[10];
    _manus = results[11];

    _loaded = true;
  }

  /// Build the full system prompt with personality + dynamic context.
  static String build({
    required String model,
    required String workingDirectory,
    String? gitBranch,
    String? projectLanguage,
    String? projectFramework,
    String? userInstructions,
    String? memoryContext,
    String? platform,
    bool isGitRepo = false,
    List<String> loadedSkills = const [],
  }) {
    final buffer = StringBuffer();

    // Core personality
    buffer.writeln(_identity);
    buffer.writeln();
    buffer.writeln(_cognition);
    buffer.writeln();
    buffer.writeln(_capabilities);
    buffer.writeln();
    buffer.writeln(_tools);

    // Environment (like OpenClaw's # Environment section)
    buffer.writeln();
    buffer.writeln('# Environment');
    buffer.writeln();
    buffer.writeln('You have been invoked in the following environment:');
    buffer.writeln();
    buffer.writeln('- Primary working directory: $workingDirectory');
    buffer.writeln('- Is a git repository: $isGitRepo');
    if (gitBranch != null) buffer.writeln('- Git branch: $gitBranch');
    if (platform != null) buffer.writeln('- Platform: $platform');
    buffer.writeln('- Date: ${DateTime.now().toIso8601String().split('T').first}');
    buffer.writeln('- Model: $model');
    if (projectLanguage != null) buffer.writeln('- Primary language: $projectLanguage');
    if (projectFramework != null) buffer.writeln('- Framework: $projectFramework');

    // User instructions
    if (userInstructions != null && userInstructions.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<user_instructions>');
      buffer.writeln(userInstructions);
      buffer.writeln('</user_instructions>');
    }

    // Memory protocol
    buffer.writeln();
    buffer.writeln(_memory);

    // Loaded skills
    if (loadedSkills.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<loaded_skills>');
      for (final skill in loadedSkills) {
        buffer.writeln(skill);
        buffer.writeln();
      }
      buffer.writeln('</loaded_skills>');
    }

    // Memory context (from session memory)
    if (memoryContext != null && memoryContext.trim().isNotEmpty) {
      buffer.writeln();
      buffer.writeln('<memory>');
      buffer.writeln(memoryContext);
      buffer.writeln('</memory>');
    }

    // Cognitive protocols (lower priority — appended at end)
    buffer.writeln();
    buffer.writeln(_metacognition);
    buffer.writeln();
    buffer.writeln(_coherence);
    buffer.writeln();
    buffer.writeln(_introspection);
    buffer.writeln();
    buffer.writeln(_consolidation);
    buffer.writeln();
    buffer.writeln(_agency);
    buffer.writeln();
    buffer.writeln(_artifacts);
    buffer.writeln();
    buffer.writeln(_manus);

    return buffer.toString();
  }

  /// Get just the identity section (for display in UI/about).
  static String get identity => _identity;

  /// Whether personality has been loaded.
  static bool get isLoaded => _loaded;

  static Future<String> _loadAsset(String path) async {
    // Try package-prefixed path first (when used as dependency),
    // fallback to direct path (when running as main app).
    try {
      return await rootBundle.loadString('packages/neomage/$path');
    } catch (_) {
      try {
        return await rootBundle.loadString(path);
      } catch (_) {
        return '<!-- $path not found -->';
      }
    }
  }
}
