/// NEOMCLAW.md file parsing, loading, merging.
///
/// Ported from openneomclaw/src/utils/neomclawmd.ts (1479 LOC).
///
/// Files are loaded in the following order:
///
/// 1. Managed memory (eg. /etc/neom-claw/NEOMCLAW.md) - Global instructions for all users
/// 2. User memory (~/.neomclaw/NEOMCLAW.md) - Private global instructions for all projects
/// 3. Project memory (NEOMCLAW.md, .neomclaw/NEOMCLAW.md, and .neomclaw/rules/*.md in project roots)
/// 4. Local memory (NEOMCLAW.local.md in project roots) - Private project-specific instructions
///
/// Files are loaded in reverse order of priority, i.e. the latest files are highest priority.
///
/// Memory @include directive:
/// - Memory files can include other files using @ notation
/// - Syntax: @path, @./relative/path, @~/home/path, or @/absolute/path
/// - Works in leaf text nodes only (not inside code blocks or code strings)
/// - Included files are added as separate entries before the including file
/// - Circular references are prevented by tracking processed files
/// - Non-existent files are silently ignored
library;

import 'dart:async';
import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:sint/sint.dart';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const String _memoryInstructionPrompt =
    'Codebase and user instructions are shown below. Be sure to adhere to '
    'these instructions. IMPORTANT: These instructions OVERRIDE any default '
    'behavior and you MUST follow them exactly as written.';

/// Recommended max character count for a memory file.
const int maxMemoryCharacterCount = 40000;

const int _maxIncludeDepth = 5;

/// File extensions that are allowed for @include directives.
/// This prevents binary files from being loaded into memory.
const Set<String> _textFileExtensions = {
  // Markdown and text
  '.md', '.txt', '.text',
  // Data formats
  '.json', '.yaml', '.yml', '.toml', '.xml', '.csv',
  // Web
  '.html', '.htm', '.css', '.scss', '.sass', '.less',
  // JavaScript/TypeScript
  '.js', '.ts', '.tsx', '.jsx', '.mjs', '.cjs', '.mts', '.cts',
  // Python
  '.py', '.pyi', '.pyw',
  // Ruby
  '.rb', '.erb', '.rake',
  // Go
  '.go',
  // Rust
  '.rs',
  // Java/Kotlin/Scala
  '.java', '.kt', '.kts', '.scala',
  // C/C++
  '.c', '.cpp', '.cc', '.cxx', '.h', '.hpp', '.hxx',
  // C#
  '.cs',
  // Swift
  '.swift',
  // Shell
  '.sh', '.bash', '.zsh', '.fish', '.ps1', '.bat', '.cmd',
  // Config
  '.env', '.ini', '.cfg', '.conf', '.config', '.properties',
  // Database
  '.sql', '.graphql', '.gql',
  // Protocol
  '.proto',
  // Frontend frameworks
  '.vue', '.svelte', '.astro',
  // Templating
  '.ejs', '.hbs', '.pug', '.jade',
  // Other languages
  '.php', '.pl', '.pm', '.lua', '.r', '.R', '.dart',
  '.ex', '.exs', '.erl', '.hrl', '.clj', '.cljs', '.cljc', '.edn',
  '.hs', '.lhs', '.elm', '.ml', '.mli', '.f', '.f90', '.f95', '.for',
  // Build files
  '.cmake', '.make', '.makefile', '.gradle', '.sbt',
  // Documentation
  '.rst', '.adoc', '.asciidoc', '.org', '.tex', '.latex',
  // Lock files
  '.lock',
  // Misc
  '.log', '.diff', '.patch',
};

// ---------------------------------------------------------------------------
// Memory type
// ---------------------------------------------------------------------------

/// The type of a memory file.
enum MemoryType {
  managed,
  user,
  project,
  local,
  autoMem,
  teamMem,
}

// ---------------------------------------------------------------------------
// MemoryFileInfo
// ---------------------------------------------------------------------------

/// Information about a loaded memory file.
class MemoryFileInfo {
  /// Absolute path to the file.
  final String path;

  /// The type of memory file.
  final MemoryType type;

  /// The processed content of the file.
  final String content;

  /// Path of the file that included this one (via @include).
  final String? parent;

  /// Glob patterns for file paths this rule applies to (from frontmatter).
  final List<String>? globs;

  /// True when auto-injection transformed content so it no longer matches disk bytes.
  final bool contentDiffersFromDisk;

  /// The unmodified disk bytes when contentDiffersFromDisk is true.
  final String? rawContent;

  const MemoryFileInfo({
    required this.path,
    required this.type,
    required this.content,
    this.parent,
    this.globs,
    this.contentDiffersFromDisk = false,
    this.rawContent,
  });

  MemoryFileInfo copyWith({
    String? path,
    MemoryType? type,
    String? content,
    String? parent,
    List<String>? globs,
    bool? contentDiffersFromDisk,
    String? rawContent,
  }) {
    return MemoryFileInfo(
      path: path ?? this.path,
      type: type ?? this.type,
      content: content ?? this.content,
      parent: parent ?? this.parent,
      globs: globs ?? this.globs,
      contentDiffersFromDisk:
          contentDiffersFromDisk ?? this.contentDiffersFromDisk,
      rawContent: rawContent ?? this.rawContent,
    );
  }
}

/// External NEOMCLAW.md include reference.
class ExternalNeomClawMdInclude {
  final String path;
  final String parent;

  const ExternalNeomClawMdInclude({required this.path, required this.parent});
}

// ---------------------------------------------------------------------------
// Frontmatter parsing
// ---------------------------------------------------------------------------

/// Parsed frontmatter result.
class _FrontmatterResult {
  final Map<String, dynamic> frontmatter;
  final String content;

  const _FrontmatterResult({
    required this.frontmatter,
    required this.content,
  });
}

/// Parses YAML-like frontmatter from markdown content.
_FrontmatterResult _parseFrontmatter(String rawContent) {
  if (!rawContent.startsWith('---')) {
    return _FrontmatterResult(frontmatter: {}, content: rawContent);
  }

  final endIndex = rawContent.indexOf('\n---', 3);
  if (endIndex == -1) {
    return _FrontmatterResult(frontmatter: {}, content: rawContent);
  }

  final frontmatterStr = rawContent.substring(3, endIndex).trim();
  final content = rawContent.substring(endIndex + 4).trimLeft();

  // Simple YAML-like parsing for frontmatter
  final frontmatter = <String, dynamic>{};
  for (final line in frontmatterStr.split('\n')) {
    final colonIndex = line.indexOf(':');
    if (colonIndex == -1) continue;
    final key = line.substring(0, colonIndex).trim();
    final value = line.substring(colonIndex + 1).trim();
    frontmatter[key] = value;
  }

  return _FrontmatterResult(frontmatter: frontmatter, content: content);
}

/// Splits frontmatter path patterns.
List<String> _splitPathInFrontmatter(String paths) {
  // Handle comma-separated or newline-separated patterns
  return paths
      .split(RegExp(r'[,\n]'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

/// Parses raw content to extract both content and glob patterns from frontmatter.
({String content, List<String>? paths}) _parseFrontmatterPaths(
    String rawContent) {
  final result = _parseFrontmatter(rawContent);

  final pathsValue = result.frontmatter['paths'];
  if (pathsValue == null) {
    return (content: result.content, paths: null);
  }

  final patterns = _splitPathInFrontmatter(pathsValue as String)
      .map((pattern) {
        return pattern.endsWith('/**') ? pattern.substring(0, pattern.length - 3) : pattern;
      })
      .where((p) => p.isNotEmpty)
      .toList();

  // If all patterns are ** (match-all), treat as no globs
  if (patterns.isEmpty || patterns.every((p) => p == '**')) {
    return (content: result.content, paths: null);
  }

  return (content: result.content, paths: patterns);
}

// ---------------------------------------------------------------------------
// HTML comment stripping
// ---------------------------------------------------------------------------

/// Strip block-level HTML comments from markdown content.
///
/// Uses simple detection to identify comments at the block level only.
/// Inline HTML comments inside a paragraph are left intact.
/// Unclosed comments are left in place.
({String content, bool stripped}) stripHtmlComments(String content) {
  if (!content.contains('<!--')) {
    return (content: content, stripped: false);
  }

  final commentPattern = RegExp(r'<!--[\s\S]*?-->');
  final lines = content.split('\n');
  final result = StringBuffer();
  bool stripped = false;

  for (int i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('<!--') && trimmed.contains('-->')) {
      final residue = line.replaceAll(commentPattern, '');
      stripped = true;
      if (residue.trim().isNotEmpty) {
        result.writeln(residue);
      }
    } else {
      result.writeln(line);
    }
  }

  return (content: result.toString(), stripped: stripped);
}

// ---------------------------------------------------------------------------
// @include path extraction
// ---------------------------------------------------------------------------

/// Regex for @include references.
final RegExp _includeRegex = RegExp(r'(?:^|\s)@((?:[^\s\\]|\\ )+)');

/// Extracts @path include references from content and resolves them to absolute paths.
List<String> _extractIncludePaths(String content, String basePath) {
  final absolutePaths = <String>{};

  void extractPathsFromText(String textContent) {
    for (final match in _includeRegex.allMatches(textContent)) {
      var path = match.group(1);
      if (path == null) continue;

      // Strip fragment identifiers
      final hashIndex = path.indexOf('#');
      if (hashIndex != -1) path = path.substring(0, hashIndex);
      if (path.isEmpty) continue;

      // Unescape spaces
      path = path.replaceAll(r'\ ', ' ');

      // Accept @path, @./path, @~/path, or @/path
      final isValidPath = path.startsWith('./') ||
          path.startsWith('~/') ||
          (path.startsWith('/') && path != '/') ||
          (!path.startsWith('@') &&
              !RegExp(r'^[#%^&*()]+').hasMatch(path) &&
              RegExp(r'^[a-zA-Z0-9._-]').hasMatch(path));

      if (isValidPath) {
        final resolvedPath = _expandPath(path, basePath);
        absolutePaths.add(resolvedPath);
      }
    }
  }

  // Simple content extraction: skip code blocks and extract from text
  final codeBlockPattern = RegExp(r'```[\s\S]*?```|`[^`]+`');
  final withoutCode = content.replaceAll(codeBlockPattern, '');
  extractPathsFromText(withoutCode);

  return absolutePaths.toList();
}

/// Expands a path that may be relative, home-relative, or absolute.
String _expandPath(String path, String basePath) {
  if (path.startsWith('~/')) {
    final home = Platform.environment['HOME'] ?? '';
    return '$home${path.substring(1)}';
  }
  if (path.startsWith('/')) return path;
  if (path.startsWith('./')) path = path.substring(2);

  // Relative to basePath's directory
  final baseDir =
      basePath.endsWith('/') ? basePath : basePath.substring(0, basePath.lastIndexOf('/'));
  return '$baseDir/$path';
}

// ---------------------------------------------------------------------------
// NeomClawMdParser SintController
// ---------------------------------------------------------------------------

/// Manages NEOMCLAW.md file discovery, parsing, loading, and merging.
class NeomClawMdParser extends SintController {
  /// Cached memory files.
  final RxList<MemoryFileInfo> _cachedFiles = <MemoryFileInfo>[].obs;

  /// Whether initial load has been logged.
  bool _hasLoggedInitialLoad = false;

  /// Hook fire control.
  bool _shouldFireHook = true;
  String _nextEagerLoadReason = 'session_start';

  /// Callback for getting the original CWD.
  String Function() _getOriginalCwd = () => Directory.current.path;

  /// Callback for getting the claude config home dir.
  String Function() _getNeomClawConfigHomeDir =
      () => '${Platform.environment['HOME'] ?? ''}/.neomclaw';

  /// Callback for getting managed NEOMCLAW.md path.
  String Function() _getManagedNeomClawMdPath =
      () => '/etc/neom-claw/NEOMCLAW.md';

  /// Callback for getting user NEOMCLAW.md path.
  String Function() _getUserNeomClawMdPath =
      () => '${Platform.environment['HOME'] ?? ''}/.neomclaw/NEOMCLAW.md';

  /// Callback for getting managed rules dir.
  String Function() _getManagedNeomClawRulesDir =
      () => '/etc/neom-claw/.neomclaw/rules';

  /// Callback for getting user rules dir.
  String Function() _getUserNeomClawRulesDir =
      () => '${Platform.environment['HOME'] ?? ''}/.neomclaw/rules';

  /// Callback for finding git root.
  String? Function(String) _findGitRoot = (_) => null;

  /// Callback for finding canonical git root.
  String? Function(String) _findCanonicalGitRoot = (_) => null;

  /// Callback for checking if a path is inside the working path.
  bool Function(String path, String workingPath) _pathInWorkingPath =
      (path, workingPath) => path.startsWith(workingPath);

  /// Callback for checking if a setting source is enabled.
  bool Function(String source) _isSettingSourceEnabled = (_) => true;

  /// Callback for getting neomClawMdExcludes patterns.
  List<String> Function() _getNeomClawMdExcludes = () => [];

  /// Logging callback.
  void Function(String message, {String? level}) _logForDebugging =
      (message, {level}) {};

  /// Event logging callback.
  void Function(String event, Map<String, dynamic> data) _logEvent =
      (event, data) {};

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  void configure({
    String Function()? getOriginalCwd,
    String Function()? getNeomClawConfigHomeDir,
    String Function()? getManagedNeomClawMdPath,
    String Function()? getUserNeomClawMdPath,
    String Function()? getManagedNeomClawRulesDir,
    String Function()? getUserNeomClawRulesDir,
    String? Function(String)? findGitRoot,
    String? Function(String)? findCanonicalGitRoot,
    bool Function(String, String)? pathInWorkingPath,
    bool Function(String)? isSettingSourceEnabled,
    List<String> Function()? getNeomClawMdExcludes,
    void Function(String, {String? level})? logForDebugging,
    void Function(String, Map<String, dynamic>)? logEvent,
  }) {
    if (getOriginalCwd != null) _getOriginalCwd = getOriginalCwd;
    if (getNeomClawConfigHomeDir != null) {
      _getNeomClawConfigHomeDir = getNeomClawConfigHomeDir;
    }
    if (getManagedNeomClawMdPath != null) {
      _getManagedNeomClawMdPath = getManagedNeomClawMdPath;
    }
    if (getUserNeomClawMdPath != null) _getUserNeomClawMdPath = getUserNeomClawMdPath;
    if (getManagedNeomClawRulesDir != null) {
      _getManagedNeomClawRulesDir = getManagedNeomClawRulesDir;
    }
    if (getUserNeomClawRulesDir != null) {
      _getUserNeomClawRulesDir = getUserNeomClawRulesDir;
    }
    if (findGitRoot != null) _findGitRoot = findGitRoot;
    if (findCanonicalGitRoot != null) {
      _findCanonicalGitRoot = findCanonicalGitRoot;
    }
    if (pathInWorkingPath != null) _pathInWorkingPath = pathInWorkingPath;
    if (isSettingSourceEnabled != null) {
      _isSettingSourceEnabled = isSettingSourceEnabled;
    }
    if (getNeomClawMdExcludes != null) _getNeomClawMdExcludes = getNeomClawMdExcludes;
    if (logForDebugging != null) _logForDebugging = logForDebugging;
    if (logEvent != null) _logEvent = logEvent;
  }

  // ---------------------------------------------------------------------------
  // Core parsing
  // ---------------------------------------------------------------------------

  /// Parses raw memory file content into a MemoryFileInfo. Pure function -- no I/O.
  static ({MemoryFileInfo? info, List<String> includePaths})
      parseMemoryFileContent(
    String rawContent,
    String filePath,
    MemoryType type, {
    String? includeBasePath,
  }) {
    // Skip non-text files
    final ext = _getFileExtension(filePath);
    if (ext.isNotEmpty && !_textFileExtensions.contains(ext)) {
      return (info: null, includePaths: <String>[]);
    }

    final parsed = _parseFrontmatterPaths(rawContent);

    // Strip HTML comments
    final strippedResult = stripHtmlComments(parsed.content);
    final strippedContent = strippedResult.content;

    // Extract include paths
    final includePaths = includeBasePath != null
        ? _extractIncludePaths(parsed.content, includeBasePath)
        : <String>[];

    final finalContent = strippedContent;
    final contentDiffersFromDisk = finalContent != rawContent;

    return (
      info: MemoryFileInfo(
        path: filePath,
        type: type,
        content: finalContent,
        globs: parsed.paths,
        contentDiffersFromDisk: contentDiffersFromDisk,
        rawContent: contentDiffersFromDisk ? rawContent : null,
      ),
      includePaths: includePaths,
    );
  }

  /// Safely reads and parses a memory file async.
  Future<({MemoryFileInfo? info, List<String> includePaths})>
      _safelyReadMemoryFileAsync(
    String filePath,
    MemoryType type, {
    String? includeBasePath,
  }) async {
    try {
      final rawContent = await File(filePath).readAsString();
      return parseMemoryFileContent(
        rawContent,
        filePath,
        type,
        includeBasePath: includeBasePath,
      );
    } on FileSystemException catch (e) {
      _handleMemoryFileReadError(e, filePath);
      return (info: null, includePaths: <String>[]);
    }
  }

  void _handleMemoryFileReadError(FileSystemException error, String filePath) {
    // ENOENT, EISDIR are expected
    final message = error.message.toLowerCase();
    if (message.contains('no such file') ||
        message.contains('is a directory')) {
      return;
    }
    if (message.contains('permission denied')) {
      _logEvent('tengu_neomclaw_md_permission_error', {
        'is_access_error': 1,
        'has_home_dir':
            filePath.contains(_getNeomClawConfigHomeDir()) ? 1 : 0,
      });
    }
  }

  /// Check if a path is excluded by neomClawMdExcludes setting.
  bool _isNeomClawMdExcluded(String filePath, MemoryType type) {
    if (type != MemoryType.user &&
        type != MemoryType.project &&
        type != MemoryType.local) {
      return false;
    }

    final patterns = _getNeomClawMdExcludes();
    if (patterns.isEmpty) return false;

    final normalizedPath = filePath.replaceAll('\\', '/');

    for (final pattern in patterns) {
      final normalized = pattern.replaceAll('\\', '/');
      if (_matchesGlob(normalizedPath, normalized)) return true;
    }
    return false;
  }

  /// Simple glob matching.
  static bool _matchesGlob(String path, String pattern) {
    final regexStr = pattern
        .replaceAll('.', r'\.')
        .replaceAll('**/', '(.+/)?')
        .replaceAll('**', '.*')
        .replaceAll('*', '[^/]*')
        .replaceAll('?', '[^/]');
    return RegExp('^$regexStr\$').hasMatch(path);
  }

  // ---------------------------------------------------------------------------
  // Recursive file processing
  // ---------------------------------------------------------------------------

  /// Recursively processes a memory file and all its @include references.
  Future<List<MemoryFileInfo>> processMemoryFile(
    String filePath,
    MemoryType type,
    Set<String> processedPaths,
    bool includeExternal, {
    int depth = 0,
    String? parent,
  }) async {
    final normalizedPath = filePath.toLowerCase();
    if (processedPaths.contains(normalizedPath) || depth >= _maxIncludeDepth) {
      return [];
    }

    if (_isNeomClawMdExcluded(filePath, type)) return [];

    processedPaths.add(normalizedPath);

    final readResult = await _safelyReadMemoryFileAsync(
      filePath,
      type,
      includeBasePath: filePath,
    );

    final memoryFile = readResult.info;
    if (memoryFile == null || memoryFile.content.trim().isEmpty) return [];

    final withParent =
        parent != null ? memoryFile.copyWith(parent: parent) : memoryFile;

    final result = <MemoryFileInfo>[withParent];

    for (final resolvedIncludePath in readResult.includePaths) {
      final isExternal =
          !_pathInWorkingPath(resolvedIncludePath, _getOriginalCwd());
      if (isExternal && !includeExternal) continue;

      final includedFiles = await processMemoryFile(
        resolvedIncludePath,
        type,
        processedPaths,
        includeExternal,
        depth: depth + 1,
        parent: filePath,
      );
      result.addAll(includedFiles);
    }

    return result;
  }

  /// Processes all .md files in a .neomclaw/rules/ directory and its subdirectories.
  Future<List<MemoryFileInfo>> processMdRules({
    required String rulesDir,
    required MemoryType type,
    required Set<String> processedPaths,
    required bool includeExternal,
    required bool conditionalRule,
    Set<String>? visitedDirs,
  }) async {
    visitedDirs ??= {};
    if (visitedDirs.contains(rulesDir)) return [];
    visitedDirs.add(rulesDir);

    final result = <MemoryFileInfo>[];

    try {
      final dir = Directory(rulesDir);
      if (!await dir.exists()) return [];

      await for (final entry in dir.list()) {
        if (entry is Directory) {
          result.addAll(await processMdRules(
            rulesDir: entry.path,
            type: type,
            processedPaths: processedPaths,
            includeExternal: includeExternal,
            conditionalRule: conditionalRule,
            visitedDirs: visitedDirs,
          ));
        } else if (entry is File && entry.path.endsWith('.md')) {
          final files = await processMemoryFile(
            entry.path,
            type,
            processedPaths,
            includeExternal,
          );
          result.addAll(
            files.where((f) => conditionalRule ? f.globs != null : f.globs == null),
          );
        }
      }
    } on FileSystemException catch (e) {
      final message = e.message.toLowerCase();
      if (!message.contains('no such file') &&
          !message.contains('permission denied') &&
          !message.contains('not a directory')) {
        rethrow;
      }
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Main discovery: getMemoryFiles
  // ---------------------------------------------------------------------------

  /// Discovers and loads all memory files from managed, user, project, and local sources.
  Future<List<MemoryFileInfo>> getMemoryFiles({
    bool forceIncludeExternal = false,
  }) async {
    final result = <MemoryFileInfo>[];
    final processedPaths = <String>{};
    final includeExternal = forceIncludeExternal;

    // 1. Managed memory
    result.addAll(await processMemoryFile(
      _getManagedNeomClawMdPath(),
      MemoryType.managed,
      processedPaths,
      includeExternal,
    ));
    result.addAll(await processMdRules(
      rulesDir: _getManagedNeomClawRulesDir(),
      type: MemoryType.managed,
      processedPaths: processedPaths,
      includeExternal: includeExternal,
      conditionalRule: false,
    ));

    // 2. User memory
    if (_isSettingSourceEnabled('userSettings')) {
      result.addAll(await processMemoryFile(
        _getUserNeomClawMdPath(),
        MemoryType.user,
        processedPaths,
        true,
      ));
      result.addAll(await processMdRules(
        rulesDir: _getUserNeomClawRulesDir(),
        type: MemoryType.user,
        processedPaths: processedPaths,
        includeExternal: true,
        conditionalRule: false,
      ));
    }

    // 3. Project and Local files (traverse from CWD up to root)
    final originalCwd = _getOriginalCwd();
    final dirs = <String>[];
    var currentDir = originalCwd;
    while (true) {
      dirs.add(currentDir);
      final parent =
          currentDir.substring(0, currentDir.lastIndexOf('/'));
      if (parent == currentDir || parent.isEmpty) break;
      currentDir = parent;
    }

    // Detect nested worktree to skip duplicated Project files
    final gitRoot = _findGitRoot(originalCwd);
    final canonicalRoot = _findCanonicalGitRoot(originalCwd);
    final isNestedWorktree = gitRoot != null &&
        canonicalRoot != null &&
        gitRoot.toLowerCase() != canonicalRoot.toLowerCase() &&
        _pathInWorkingPath(gitRoot, canonicalRoot);

    // Process from root downward to CWD
    for (final dir in dirs.reversed) {
      final skipProject = isNestedWorktree &&
          _pathInWorkingPath(dir, canonicalRoot!) &&
          !_pathInWorkingPath(dir, gitRoot!);

      // Project memory
      if (_isSettingSourceEnabled('projectSettings') && !skipProject) {
        result.addAll(await processMemoryFile(
          '$dir/NEOMCLAW.md',
          MemoryType.project,
          processedPaths,
          includeExternal,
        ));
        result.addAll(await processMemoryFile(
          '$dir/.neomclaw/NEOMCLAW.md',
          MemoryType.project,
          processedPaths,
          includeExternal,
        ));
        result.addAll(await processMdRules(
          rulesDir: '$dir/.neomclaw/rules',
          type: MemoryType.project,
          processedPaths: processedPaths,
          includeExternal: includeExternal,
          conditionalRule: false,
        ));
      }

      // Local memory
      if (_isSettingSourceEnabled('localSettings')) {
        result.addAll(await processMemoryFile(
          '$dir/NEOMCLAW.local.md',
          MemoryType.local,
          processedPaths,
          includeExternal,
        ));
      }
    }

    _cachedFiles.value = result;
    return result;
  }

  // ---------------------------------------------------------------------------
  // Cache management
  // ---------------------------------------------------------------------------

  /// Clears the getMemoryFiles cache without firing hooks.
  void clearMemoryFileCaches() {
    _cachedFiles.clear();
  }

  /// Resets the cache and marks hooks as needing to fire.
  void resetGetMemoryFilesCache({String reason = 'session_start'}) {
    _nextEagerLoadReason = reason;
    _shouldFireHook = true;
    clearMemoryFileCaches();
  }

  // ---------------------------------------------------------------------------
  // Conditional rules
  // ---------------------------------------------------------------------------

  /// Gets managed and user conditional rules that match the target path.
  Future<List<MemoryFileInfo>> getManagedAndUserConditionalRules(
    String targetPath,
    Set<String> processedPaths,
  ) async {
    final result = <MemoryFileInfo>[];

    result.addAll(await _processConditionedMdRules(
      targetPath,
      _getManagedNeomClawRulesDir(),
      MemoryType.managed,
      processedPaths,
      false,
    ));

    if (_isSettingSourceEnabled('userSettings')) {
      result.addAll(await _processConditionedMdRules(
        targetPath,
        _getUserNeomClawRulesDir(),
        MemoryType.user,
        processedPaths,
        true,
      ));
    }

    return result;
  }

  /// Gets memory files for a single nested directory.
  Future<List<MemoryFileInfo>> getMemoryFilesForNestedDirectory(
    String dir,
    String targetPath,
    Set<String> processedPaths,
  ) async {
    final result = <MemoryFileInfo>[];

    if (_isSettingSourceEnabled('projectSettings')) {
      result.addAll(await processMemoryFile(
        '$dir/NEOMCLAW.md',
        MemoryType.project,
        processedPaths,
        false,
      ));
      result.addAll(await processMemoryFile(
        '$dir/.neomclaw/NEOMCLAW.md',
        MemoryType.project,
        processedPaths,
        false,
      ));
    }

    if (_isSettingSourceEnabled('localSettings')) {
      result.addAll(await processMemoryFile(
        '$dir/NEOMCLAW.local.md',
        MemoryType.local,
        processedPaths,
        false,
      ));
    }

    final rulesDir = '$dir/.neomclaw/rules';

    // Unconditional rules
    final unconditionalPaths = Set<String>.from(processedPaths);
    result.addAll(await processMdRules(
      rulesDir: rulesDir,
      type: MemoryType.project,
      processedPaths: unconditionalPaths,
      includeExternal: false,
      conditionalRule: false,
    ));

    // Conditional rules
    result.addAll(await _processConditionedMdRules(
      targetPath,
      rulesDir,
      MemoryType.project,
      processedPaths,
      false,
    ));

    for (final path in unconditionalPaths) {
      processedPaths.add(path);
    }

    return result;
  }

  /// Gets conditional rules for a CWD-level directory.
  Future<List<MemoryFileInfo>> getConditionalRulesForCwdLevelDirectory(
    String dir,
    String targetPath,
    Set<String> processedPaths,
  ) async {
    final rulesDir = '$dir/.neomclaw/rules';
    return _processConditionedMdRules(
      targetPath,
      rulesDir,
      MemoryType.project,
      processedPaths,
      false,
    );
  }

  /// Processes conditioned (glob-filtered) .md rules.
  Future<List<MemoryFileInfo>> _processConditionedMdRules(
    String targetPath,
    String rulesDir,
    MemoryType type,
    Set<String> processedPaths,
    bool includeExternal,
  ) async {
    final conditioned = await processMdRules(
      rulesDir: rulesDir,
      type: type,
      processedPaths: processedPaths,
      includeExternal: includeExternal,
      conditionalRule: true,
    );

    return conditioned.where((file) {
      if (file.globs == null || file.globs!.isEmpty) return false;
      return file.globs!.any((pattern) => _matchesGlob(targetPath, pattern));
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Rendering helpers
  // ---------------------------------------------------------------------------

  /// Renders memory files into a single prompt string.
  String getNeomClawMds(
    List<MemoryFileInfo> memoryFiles, {
    bool Function(MemoryType type)? filter,
  }) {
    final memories = <String>[];

    for (final file in memoryFiles) {
      if (filter != null && !filter(file.type)) continue;
      if (file.content.isEmpty) continue;

      String description;
      switch (file.type) {
        case MemoryType.project:
          description = ' (project instructions, checked into the codebase)';
        case MemoryType.local:
          description =
              " (user's private project instructions, not checked in)";
        case MemoryType.autoMem:
          description =
              " (user's auto-memory, persists across conversations)";
        case MemoryType.teamMem:
          description =
              ' (shared team memory, synced across the organization)';
        case MemoryType.user:
          description =
              " (user's private global instructions for all projects)";
        case MemoryType.managed:
          description = ' (managed instructions)';
      }

      final content = file.content.trim();
      memories.add('Contents of ${file.path}$description:\n\n$content');
    }

    if (memories.isEmpty) return '';
    return '$_memoryInstructionPrompt\n\n${memories.join('\n\n')}';
  }

  // ---------------------------------------------------------------------------
  // Query helpers
  // ---------------------------------------------------------------------------

  /// Returns memory files whose content exceeds the max character count.
  List<MemoryFileInfo> getLargeMemoryFiles(List<MemoryFileInfo> files) {
    return files.where((f) => f.content.length > maxMemoryCharacterCount).toList();
  }

  /// Gets external @include references.
  List<ExternalNeomClawMdInclude> getExternalNeomClawMdIncludes(
    List<MemoryFileInfo> files,
  ) {
    final externals = <ExternalNeomClawMdInclude>[];
    for (final file in files) {
      if (file.type != MemoryType.user &&
          file.parent != null &&
          !_pathInWorkingPath(file.path, _getOriginalCwd())) {
        externals.add(
          ExternalNeomClawMdInclude(path: file.path, parent: file.parent!),
        );
      }
    }
    return externals;
  }

  /// Check if there are external @include references.
  bool hasExternalNeomClawMdIncludes(List<MemoryFileInfo> files) {
    return getExternalNeomClawMdIncludes(files).isNotEmpty;
  }

  /// Check if a file path is a memory file.
  bool isMemoryFilePath(String filePath) {
    final name = filePath.split('/').last;
    if (name == 'NEOMCLAW.md' || name == 'NEOMCLAW.local.md') return true;
    if (name.endsWith('.md') && filePath.contains('/.neomclaw/rules/')) {
      return true;
    }
    return false;
  }

  /// Get all memory file paths from both standard discovery and readFileState.
  List<String> getAllMemoryFilePaths(
    List<MemoryFileInfo> files, {
    Set<String>? readFileStatePaths,
  }) {
    final paths = <String>{};
    for (final file in files) {
      if (file.content.trim().isNotEmpty) {
        paths.add(file.path);
      }
    }
    if (readFileStatePaths != null) {
      for (final filePath in readFileStatePaths) {
        if (isMemoryFilePath(filePath)) {
          paths.add(filePath);
        }
      }
    }
    return paths.toList();
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void onInit() {
    super.onInit();
  }

  @override
  void onClose() {
    super.onClose();
  }
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

/// Extracts file extension from a path.
String _getFileExtension(String path) {
  final dotIndex = path.lastIndexOf('.');
  if (dotIndex == -1 || dotIndex == path.length - 1) return '';
  return path.substring(dotIndex).toLowerCase();
}
