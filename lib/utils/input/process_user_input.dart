// Process user input — port of neom_claw/src/utils/processUserInput/.
// Input parsing, @-mentions, file references, command detection, context extraction.

import 'package:neom_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Segment types
// ---------------------------------------------------------------------------

/// Types of user input segments.
sealed class InputSegment {
  const InputSegment();
}

/// Plain text segment.
class TextSegment extends InputSegment {
  final String text;
  const TextSegment(this.text);

  @override
  String toString() => 'TextSegment("$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TextSegment && other.text == text;

  @override
  int get hashCode => text.hashCode;
}

/// @-mention of a file or directory.
class FileMention extends InputSegment {
  final String path; // resolved path
  final String originalText; // as typed by user
  final bool isDirectory;

  const FileMention({
    required this.path,
    required this.originalText,
    this.isDirectory = false,
  });

  @override
  String toString() => 'FileMention(path: "$path", dir: $isDirectory)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileMention &&
          other.path == path &&
          other.originalText == originalText &&
          other.isDirectory == isDirectory;

  @override
  int get hashCode => Object.hash(path, originalText, isDirectory);
}

/// @-mention of a URL.
class UrlMention extends InputSegment {
  final String url;
  const UrlMention(this.url);

  @override
  String toString() => 'UrlMention("$url")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UrlMention && other.url == url;

  @override
  int get hashCode => url.hashCode;
}

/// @-mention of a git ref (branch, commit, tag).
class GitRefMention extends InputSegment {
  final String ref;
  const GitRefMention(this.ref);

  @override
  String toString() => 'GitRefMention("$ref")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is GitRefMention && other.ref == ref;

  @override
  int get hashCode => ref.hashCode;
}

/// Slash command reference.
class CommandReference extends InputSegment {
  final String commandName;
  final String? args;
  const CommandReference({required this.commandName, this.args});

  @override
  String toString() =>
      'CommandReference(/$commandName${args != null ? ' $args' : ''})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CommandReference &&
          other.commandName == commandName &&
          other.args == args;

  @override
  int get hashCode => Object.hash(commandName, args);
}

// ---------------------------------------------------------------------------
// Parsed user input
// ---------------------------------------------------------------------------

/// Parsed user input.
class ParsedUserInput {
  final String rawInput;
  final List<InputSegment> segments;
  final List<String> mentionedFiles;
  final List<String> mentionedUrls;
  final bool isCommand;
  final String? commandName;
  final String? commandArgs;
  final bool isEmpty;
  final bool isMultiline;
  final int lineCount;

  const ParsedUserInput({
    required this.rawInput,
    required this.segments,
    required this.mentionedFiles,
    required this.mentionedUrls,
    required this.isCommand,
    this.commandName,
    this.commandArgs,
    required this.isEmpty,
    required this.isMultiline,
    required this.lineCount,
  });

  /// Plain text content with mentions removed.
  String get plainText {
    final buf = StringBuffer();
    for (final seg in segments) {
      if (seg is TextSegment) {
        buf.write(seg.text);
      }
    }
    return buf.toString().trim();
  }

  /// All implicit + explicit file references found in input.
  List<String> get allFileReferences {
    final explicit = mentionedFiles;
    final implicit = detectImplicitFileReferences(rawInput);
    final seen = <String>{...explicit};
    final result = [...explicit];
    for (final f in implicit) {
      if (seen.add(f)) result.add(f);
    }
    return result;
  }

  @override
  String toString() =>
      'ParsedUserInput(segments: ${segments.length}, files: ${mentionedFiles.length}, '
      'urls: ${mentionedUrls.length}, isCmd: $isCommand)';
}

// ---------------------------------------------------------------------------
// Regex patterns
// ---------------------------------------------------------------------------

/// Pattern for file mentions: @path/to/file or @./relative/path
final fileMentionPattern = RegExp(
  r'@((?:\./|/|~/)[\w./-]+|[\w][\w./-]*\.[a-zA-Z]+)',
  multiLine: true,
);

/// Pattern for URL mentions: @https://... or @http://...
final urlMentionPattern = RegExp(r'@(https?://[^\s]+)', multiLine: true);

/// Pattern for git ref mentions: @branch:name or @commit:hash
final gitRefPattern = RegExp(r'@(branch|commit|tag):(\S+)', multiLine: true);

/// Slash command at the beginning of input.
final _slashCommandPattern = RegExp(r'^\s*/([a-z][\w-]*)\s*(.*)', dotAll: true);

/// Implicit file reference patterns — "in file.ts", "the foo.dart file", bare paths.
final _implicitFilePatterns = [
  RegExp(
    r'''(?:in|from|at|see|open|edit|modify|update|check|read|the)\s+[`"']?([a-zA-Z][\w./-]*\.\w{1,10})[`"']?''',
    caseSensitive: false,
  ),
  RegExp(r'''[`"']([a-zA-Z][\w./-]*\.\w{1,10})[`"']'''),
  RegExp(
    r'(?:^|\s)((?:src|lib|test|bin|build|packages?|config)(?:/[\w.-]+)+)',
    multiLine: true,
  ),
];

/// Code block pattern.
final _codeBlockPattern = RegExp(r'```(\w*)\n([\s\S]*?)```');

// ---------------------------------------------------------------------------
// Core parsing
// ---------------------------------------------------------------------------

/// Parse user input into structured segments.
ParsedUserInput parseUserInput(String input, {String? workingDirectory}) {
  final wd = workingDirectory ?? Directory.current.path;
  final normalized = normalizeInput(input);

  if (normalized.isEmpty) {
    return ParsedUserInput(
      rawInput: input,
      segments: const [],
      mentionedFiles: const [],
      mentionedUrls: const [],
      isCommand: false,
      isEmpty: true,
      isMultiline: false,
      lineCount: 0,
    );
  }

  // Detect slash command.
  final isCmd = isSlashCommand(normalized);
  String? cmdName;
  String? cmdArgs;
  if (isCmd) {
    final parsed = parseSlashCommand(normalized);
    if (parsed != null) {
      cmdName = parsed.command;
      cmdArgs = parsed.args.isEmpty ? null : parsed.args;
    }
  }

  // Build segments by scanning for @-mentions.
  final segments = <InputSegment>[];
  final mentionedFiles = <String>[];
  final mentionedUrls = <String>[];

  // Collect all mention matches with their spans.
  final mentions = <_MentionMatch>[];

  for (final m in gitRefPattern.allMatches(normalized)) {
    final kind = m.group(1)!; // branch, commit, tag
    final ref = m.group(2)!;
    mentions.add(
      _MentionMatch(
        start: m.start,
        end: m.end,
        segment: GitRefMention('$kind:$ref'),
      ),
    );
  }

  for (final m in urlMentionPattern.allMatches(normalized)) {
    final url = m.group(1)!;
    // Skip if overlapping with an earlier match.
    if (_overlaps(mentions, m.start, m.end)) continue;
    mentionedUrls.add(url);
    mentions.add(
      _MentionMatch(start: m.start, end: m.end, segment: UrlMention(url)),
    );
  }

  for (final m in fileMentionPattern.allMatches(normalized)) {
    if (_overlaps(mentions, m.start, m.end)) continue;
    final raw = m.group(1)!;
    final resolved = resolveFilePath(raw, wd);
    final isDir = _looksLikeDirectory(raw);
    mentionedFiles.add(resolved);
    mentions.add(
      _MentionMatch(
        start: m.start,
        end: m.end,
        segment: FileMention(
          path: resolved,
          originalText: '@$raw',
          isDirectory: isDir,
        ),
      ),
    );
  }

  // Sort mentions by position.
  mentions.sort((a, b) => a.start.compareTo(b.start));

  // Interleave text and mention segments.
  var cursor = 0;
  for (final mm in mentions) {
    if (mm.start > cursor) {
      segments.add(TextSegment(normalized.substring(cursor, mm.start)));
    }
    segments.add(mm.segment);
    cursor = mm.end;
  }
  if (cursor < normalized.length) {
    segments.add(TextSegment(normalized.substring(cursor)));
  }

  // If the input is a command and we haven't added a CommandReference segment,
  // wrap the whole thing.
  if (isCmd && cmdName != null) {
    segments.insert(0, CommandReference(commandName: cmdName, args: cmdArgs));
  }

  final lines = normalized.split('\n');

  return ParsedUserInput(
    rawInput: input,
    segments: segments,
    mentionedFiles: mentionedFiles,
    mentionedUrls: mentionedUrls,
    isCommand: isCmd,
    commandName: cmdName,
    commandArgs: cmdArgs,
    isEmpty: false,
    isMultiline: lines.length > 1,
    lineCount: lines.length,
  );
}

class _MentionMatch {
  final int start;
  final int end;
  final InputSegment segment;
  const _MentionMatch({
    required this.start,
    required this.end,
    required this.segment,
  });
}

bool _overlaps(List<_MentionMatch> existing, int start, int end) {
  for (final m in existing) {
    if (start < m.end && end > m.start) return true;
  }
  return false;
}

bool _looksLikeDirectory(String raw) {
  if (raw.endsWith('/')) return true;
  // No file extension after last segment → likely directory.
  final lastPart = raw.split('/').last;
  return !lastPart.contains('.');
}

// ---------------------------------------------------------------------------
// File path resolution
// ---------------------------------------------------------------------------

/// Resolve a file mention to an absolute path.
String resolveFilePath(String mention, String workingDirectory) {
  var p = mention;

  // Expand ~.
  if (p.startsWith('~/')) {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/';
    p = '$home${p.substring(1)}';
  }

  // Already absolute.
  if (p.startsWith('/')) return _normalizePath(p);

  // Starts with ./ or ../ → relative to workingDirectory.
  if (p.startsWith('./') || p.startsWith('../')) {
    return _normalizePath('$workingDirectory/$p');
  }

  // Bare relative path.
  return _normalizePath('$workingDirectory/$p');
}

/// Normalize a path — resolve . and .. segments, collapse repeated /.
String _normalizePath(String path) {
  final parts = path.split('/');
  final resolved = <String>[];
  for (final part in parts) {
    if (part == '.' || part.isEmpty) {
      if (resolved.isEmpty) resolved.add(''); // preserve leading /
      continue;
    }
    if (part == '..') {
      if (resolved.length > 1) resolved.removeLast();
    } else {
      resolved.add(part);
    }
  }
  final result = resolved.join('/');
  if (result.isEmpty) return '/';
  return result;
}

/// Check if a string looks like a file path.
bool looksLikeFilePath(String input) {
  if (input.isEmpty) return false;
  // Starts with common path prefixes.
  if (input.startsWith('/') ||
      input.startsWith('./') ||
      input.startsWith('~/') ||
      input.startsWith('../')) {
    return true;
  }
  // Contains path separator and has a file extension.
  if (input.contains('/') && RegExp(r'\.\w{1,10}$').hasMatch(input)) {
    return true;
  }
  // Single filename with extension.
  if (RegExp(r'^[\w.-]+\.\w{1,10}$').hasMatch(input)) {
    return true;
  }
  // Starts with common source directories.
  if (RegExp(
    r'^(?:src|lib|test|bin|build|packages?|config)/',
  ).hasMatch(input)) {
    return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Autocomplete suggestions
// ---------------------------------------------------------------------------

enum MentionType { file, directory, url, gitBranch, gitTag, command }

/// Autocomplete suggestion for @-mentions.
class MentionSuggestion {
  final String display; // What to show in autocomplete
  final String completion; // What to insert
  final MentionType type;
  final String? description; // File type, branch info, etc.

  const MentionSuggestion({
    required this.display,
    required this.completion,
    required this.type,
    this.description,
  });

  @override
  String toString() => 'MentionSuggestion($display, $type)';
}

/// Generate autocomplete suggestions for a partial @-mention.
Future<List<MentionSuggestion>> getCompletions(
  String partial, {
  required String workingDirectory,
  int maxResults = 20,
}) async {
  final suggestions = <MentionSuggestion>[];

  // Determine if it looks like a git ref.
  if (partial.startsWith('branch:') ||
      partial.startsWith('commit:') ||
      partial.startsWith('tag:')) {
    final colonIdx = partial.indexOf(':');
    final refType = partial.substring(0, colonIdx);
    final refPartial = partial.substring(colonIdx + 1);
    final branches = await _getGitRefs(refType, refPartial, workingDirectory);
    suggestions.addAll(branches);
    return suggestions.take(maxResults).toList();
  }

  // URL partial — no completions.
  if (partial.startsWith('http://') || partial.startsWith('https://')) {
    return [];
  }

  // File / directory completion.
  final resolved = _resolvePartialForCompletion(partial, workingDirectory);
  final parentDir = _parentDirectory(resolved);
  final prefix = _baseName(resolved).toLowerCase();

  try {
    final dir = Directory(parentDir);
    if (await dir.exists()) {
      await for (final entity in dir.list(followLinks: true)) {
        final name = _baseName(entity.path);
        if (name.startsWith('.') && !partial.contains('/.')) {
          continue; // skip hidden
        }
        if (prefix.isNotEmpty && !name.toLowerCase().startsWith(prefix)) {
          continue;
        }

        final isDir = entity is Directory;
        final relativePath = _makeRelative(entity.path, workingDirectory);
        final ext = isDir ? null : _extension(name);
        suggestions.add(
          MentionSuggestion(
            display: name + (isDir ? '/' : ''),
            completion: '@$relativePath${isDir ? '/' : ''}',
            type: isDir ? MentionType.directory : MentionType.file,
            description: isDir ? 'directory' : ext,
          ),
        );
      }
    }
  } catch (_) {
    // Permission denied or other FS error — return empty.
  }

  // Also suggest matching commands if partial looks like one.
  if (!partial.contains('/') && !partial.contains('.')) {
    for (final cmd in knownCommands) {
      if (cmd.startsWith(partial.toLowerCase())) {
        suggestions.add(
          MentionSuggestion(
            display: '/$cmd',
            completion: '/$cmd ',
            type: MentionType.command,
            description: 'command',
          ),
        );
      }
    }
  }

  // Sort: directories first, then files, then commands.
  suggestions.sort((a, b) {
    final typeOrder = a.type.index.compareTo(b.type.index);
    if (typeOrder != 0) return typeOrder;
    return a.display.toLowerCase().compareTo(b.display.toLowerCase());
  });

  return suggestions.take(maxResults).toList();
}

Future<List<MentionSuggestion>> _getGitRefs(
  String refType,
  String partial,
  String workingDirectory,
) async {
  final suggestions = <MentionSuggestion>[];
  try {
    String command;
    MentionType mentionType;
    switch (refType) {
      case 'branch':
        command = 'git branch --list --format=%(refname:short)';
        mentionType = MentionType.gitBranch;
      case 'tag':
        command = 'git tag --list';
        mentionType = MentionType.gitTag;
      case 'commit':
        command = 'git log --oneline -20 --format=%h';
        mentionType = MentionType.gitBranch; // reuse for commits
      default:
        return [];
    }
    final result = await Process.run('bash', [
      '-c',
      command,
    ], workingDirectory: workingDirectory);
    if (result.exitCode == 0) {
      final output = (result.stdout as String).trim();
      for (final line in output.split('\n')) {
        final ref = line.trim();
        if (ref.isEmpty) continue;
        if (partial.isNotEmpty &&
            !ref.toLowerCase().startsWith(partial.toLowerCase())) {
          continue;
        }
        suggestions.add(
          MentionSuggestion(
            display: '$refType:$ref',
            completion: '@$refType:$ref',
            type: mentionType,
            description: refType,
          ),
        );
      }
    }
  } catch (_) {
    // Not a git repo or git not installed.
  }
  return suggestions;
}

String _resolvePartialForCompletion(String partial, String wd) {
  if (partial.startsWith('~/')) {
    final home = Platform.environment['HOME'] ?? '/';
    return '$home${partial.substring(1)}';
  }
  if (partial.startsWith('/')) return partial;
  if (partial.startsWith('./') || partial.startsWith('../')) {
    return '$wd/$partial';
  }
  return '$wd/$partial';
}

String _parentDirectory(String path) {
  final idx = path.lastIndexOf('/');
  if (idx <= 0) return '/';
  return path.substring(0, idx);
}

String _baseName(String path) {
  final idx = path.lastIndexOf('/');
  if (idx < 0) return path;
  return path.substring(idx + 1);
}

String _makeRelative(String absPath, String wd) {
  if (absPath.startsWith('$wd/')) return absPath.substring(wd.length + 1);
  return absPath;
}

String? _extension(String name) {
  final idx = name.lastIndexOf('.');
  if (idx < 0 || idx == name.length - 1) return null;
  return name.substring(idx + 1);
}

// ---------------------------------------------------------------------------
// Command detection and parsing
// ---------------------------------------------------------------------------

/// Check if input is a slash command.
bool isSlashCommand(String input) {
  return input.trimLeft().startsWith('/');
}

/// Parse a slash command.
({String command, String args})? parseSlashCommand(String input) {
  final match = _slashCommandPattern.firstMatch(input);
  if (match == null) return null;
  final command = match.group(1)!;
  final args = match.group(2)?.trim() ?? '';
  return (command: command, args: args);
}

/// Known command names for autocomplete.
const knownCommands = [
  'help',
  'clear',
  'compact',
  'cost',
  'model',
  'memory',
  'session',
  'plan',
  'commit',
  'review',
  'diff',
  'config',
  'context',
  'tasks',
  'agents',
  'bug',
  'init',
  'login',
  'logout',
  'doctor',
  'listen',
  'resume',
  'status',
  'permissions',
  'hooks',
  'mcp',
  'vim',
  'terminal-setup',
  'ide',
  'add-dir',
  'release-notes',
];

// ---------------------------------------------------------------------------
// Input preprocessing
// ---------------------------------------------------------------------------

/// Strip leading/trailing whitespace and normalize newlines.
String normalizeInput(String input) {
  // Normalize CRLF and bare CR to LF.
  var result = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

  // Strip trailing whitespace per line.
  result = result.split('\n').map((line) => line.trimRight()).join('\n');

  // Strip leading/trailing blank lines but preserve internal structure.
  result = result.trim();

  return result;
}

/// Detect if input contains code blocks.
bool containsCodeBlock(String input) {
  return input.contains('```');
}

/// Extract code blocks from input.
List<({String language, String code})> extractCodeBlocks(String input) {
  final results = <({String language, String code})>[];
  for (final match in _codeBlockPattern.allMatches(input)) {
    final language = match.group(1) ?? '';
    final code = match.group(2) ?? '';
    results.add((language: language, code: code.trim()));
  }
  return results;
}

/// Detect if input is asking about a specific file.
List<String> detectImplicitFileReferences(String input) {
  final refs = <String>{};
  for (final pattern in _implicitFilePatterns) {
    for (final match in pattern.allMatches(input)) {
      final ref = match.group(1);
      if (ref != null && ref.isNotEmpty && _isPlausibleFilePath(ref)) {
        refs.add(ref);
      }
    }
  }
  return refs.toList();
}

/// Heuristic check that a matched string is actually a plausible file path
/// rather than a regular English word that happened to match.
bool _isPlausibleFilePath(String candidate) {
  // Must contain a dot with an alphanumeric extension, or contain a slash.
  if (candidate.contains('/')) return true;
  if (RegExp(r'\.\w{1,10}$').hasMatch(candidate)) {
    // Reject very common English words with dots (e.g. "e.g", "vs.").
    if (candidate.length < 3) return false;
    // Reject if the "extension" is just a single letter following a period
    // that doesn't look like a real extension.
    final ext = candidate.split('.').last;
    const commonExtensions = {
      'dart',
      'ts',
      'tsx',
      'js',
      'jsx',
      'py',
      'rb',
      'rs',
      'go',
      'java',
      'kt',
      'swift',
      'c',
      'cpp',
      'h',
      'hpp',
      'cs',
      'php',
      'vue',
      'svelte',
      'html',
      'css',
      'scss',
      'sass',
      'less',
      'json',
      'yaml',
      'yml',
      'toml',
      'xml',
      'md',
      'txt',
      'sh',
      'bash',
      'zsh',
      'fish',
      'ps1',
      'bat',
      'cmd',
      'sql',
      'graphql',
      'proto',
      'lock',
      'log',
      'env',
      'cfg',
      'ini',
      'conf',
      'dockerfile',
      'makefile',
      'gradle',
      'cmake',
      'tf',
      'hcl',
    };
    return commonExtensions.contains(ext.toLowerCase());
  }
  return false;
}

// ---------------------------------------------------------------------------
// Input history management
// ---------------------------------------------------------------------------

/// Input history management.
class InputHistory {
  final List<String> _entries;
  final int maxEntries;
  int _currentIndex;
  String? _savedInput; // Current unsaved input

  InputHistory({this.maxEntries = 500}) : _entries = [], _currentIndex = -1;

  /// Add a new entry. Resets navigation index. Deduplicates consecutive entries.
  void add(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    // Don't add duplicates of the last entry.
    if (_entries.isNotEmpty && _entries.last == trimmed) {
      _resetNavigation();
      return;
    }

    _entries.add(trimmed);

    // Enforce max size.
    while (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }

    _resetNavigation();
  }

  /// Navigate to previous entry (older). Returns null if at the beginning.
  String? previous() {
    if (_entries.isEmpty) return null;

    if (_currentIndex < 0) {
      // Start navigating from the end.
      _currentIndex = _entries.length - 1;
    } else if (_currentIndex > 0) {
      _currentIndex--;
    } else {
      return _entries[0]; // Already at oldest.
    }
    return _entries[_currentIndex];
  }

  /// Navigate to next entry (newer). Returns null if past the end (back to current input).
  String? next() {
    if (_currentIndex < 0) return null; // Not navigating.

    if (_currentIndex < _entries.length - 1) {
      _currentIndex++;
      return _entries[_currentIndex];
    } else {
      // Past the end — restore saved input.
      _resetNavigation();
      return _savedInput;
    }
  }

  /// Save the current (unsaved) input before navigating history.
  void saveCurrentInput(String input) {
    _savedInput = input;
  }

  /// Restore the saved current input.
  String? restoreCurrentInput() {
    final saved = _savedInput;
    _savedInput = null;
    return saved;
  }

  /// Search history for entries containing the query.
  List<String> search(String query) {
    if (query.isEmpty) return List.unmodifiable(_entries);
    final lower = query.toLowerCase();
    return _entries.where((e) => e.toLowerCase().contains(lower)).toList();
  }

  /// Clear all history.
  void clear() {
    _entries.clear();
    _resetNavigation();
  }

  /// Number of entries.
  int get length => _entries.length;

  /// All entries (oldest first).
  List<String> get entries => List.unmodifiable(_entries);

  void _resetNavigation() {
    _currentIndex = -1;
    _savedInput = null;
  }
}

// ---------------------------------------------------------------------------
// Multi-turn context extraction
// ---------------------------------------------------------------------------

/// Extract key entities from a conversation for context.
class ConversationContext {
  final Set<String> mentionedFiles;
  final Set<String> mentionedUrls;
  final Set<String> mentionedCommands;
  final String? currentTopic;
  final String? currentLanguage; // Programming language being discussed

  const ConversationContext({
    this.mentionedFiles = const {},
    this.mentionedUrls = const {},
    this.mentionedCommands = const {},
    this.currentTopic,
    this.currentLanguage,
  });

  /// Merge another context into this one, preferring the other's topic/language.
  ConversationContext merge(ConversationContext other) {
    return ConversationContext(
      mentionedFiles: {...mentionedFiles, ...other.mentionedFiles},
      mentionedUrls: {...mentionedUrls, ...other.mentionedUrls},
      mentionedCommands: {...mentionedCommands, ...other.mentionedCommands},
      currentTopic: other.currentTopic ?? currentTopic,
      currentLanguage: other.currentLanguage ?? currentLanguage,
    );
  }

  @override
  String toString() =>
      'ConversationContext(files: ${mentionedFiles.length}, urls: ${mentionedUrls.length}, '
      'cmds: ${mentionedCommands.length}, lang: $currentLanguage)';
}

/// Build context from conversation history.
ConversationContext buildContext(List<String> userMessages) {
  final files = <String>{};
  final urls = <String>{};
  final commands = <String>{};
  String? lastLanguage;
  String? lastTopic;

  for (final msg in userMessages) {
    // Parse each message for mentions.
    final parsed = parseUserInput(msg);
    files.addAll(parsed.mentionedFiles);
    urls.addAll(parsed.mentionedUrls);

    if (parsed.isCommand && parsed.commandName != null) {
      commands.add(parsed.commandName!);
    }

    // Detect language from message.
    final lang = detectLanguage(msg);
    if (lang != null) lastLanguage = lang;

    // Extract a rough topic from the last substantive message.
    final trimmed = msg.trim();
    if (trimmed.length > 10 && !trimmed.startsWith('/')) {
      lastTopic = _extractTopic(trimmed);
    }
  }

  return ConversationContext(
    mentionedFiles: files,
    mentionedUrls: urls,
    mentionedCommands: commands,
    currentTopic: lastTopic,
    currentLanguage: lastLanguage,
  );
}

/// Extract a rough topic summary — first sentence or first N words.
String _extractTopic(String input) {
  // Strip code blocks for topic detection.
  var clean = input.replaceAll(_codeBlockPattern, '').trim();
  if (clean.isEmpty) clean = input;

  // First sentence (up to period, question mark, or exclamation).
  final sentenceEnd = RegExp(r'[.!?](?:\s|$)').firstMatch(clean);
  if (sentenceEnd != null && sentenceEnd.start < 200) {
    return clean.substring(0, sentenceEnd.start + 1).trim();
  }

  // Otherwise first 15 words.
  final words = clean.split(RegExp(r'\s+'));
  if (words.length <= 15) return clean;
  return '${words.take(15).join(' ')}...';
}

/// Detect programming language from input content.
String? detectLanguage(String input) {
  // Check for explicit code blocks with language tags.
  final codeBlocks = extractCodeBlocks(input);
  for (final block in codeBlocks) {
    if (block.language.isNotEmpty) {
      final normalized = _normalizeLanguageName(block.language);
      if (normalized != null) return normalized;
    }
  }

  // Check for file extension mentions.
  final extensionMap = <String, String>{
    '.dart': 'Dart',
    '.ts': 'TypeScript',
    '.tsx': 'TypeScript',
    '.js': 'JavaScript',
    '.jsx': 'JavaScript',
    '.py': 'Python',
    '.rb': 'Ruby',
    '.rs': 'Rust',
    '.go': 'Go',
    '.java': 'Java',
    '.kt': 'Kotlin',
    '.swift': 'Swift',
    '.c': 'C',
    '.cpp': 'C++',
    '.cs': 'C#',
    '.php': 'PHP',
    '.vue': 'Vue',
    '.svelte': 'Svelte',
    '.html': 'HTML',
    '.css': 'CSS',
    '.sql': 'SQL',
    '.sh': 'Shell',
  };

  for (final entry in extensionMap.entries) {
    if (input.contains(entry.key)) return entry.value;
  }

  // Check for language keyword hints in the text.
  final keywordMap = <RegExp, String>{
    RegExp(r'\b(?:flutter|dart|pubspec)\b', caseSensitive: false): 'Dart',
    RegExp(r'\b(?:typescript|tsx?)\b', caseSensitive: false): 'TypeScript',
    RegExp(r'\b(?:javascript|nodejs|node\.js)\b', caseSensitive: false):
        'JavaScript',
    RegExp(r'\b(?:python|pip|django|flask|fastapi)\b', caseSensitive: false):
        'Python',
    RegExp(r'\b(?:rust|cargo|crate)\b', caseSensitive: false): 'Rust',
    RegExp(r'\b(?:golang|go\s+module)\b', caseSensitive: false): 'Go',
    RegExp(r'\b(?:java|spring\s*boot|maven|gradle)\b', caseSensitive: false):
        'Java',
    RegExp(r'\b(?:kotlin|ktor)\b', caseSensitive: false): 'Kotlin',
    RegExp(r'\b(?:swift|swiftui|xcode)\b', caseSensitive: false): 'Swift',
    RegExp(r'\b(?:ruby|rails|bundler|gem)\b', caseSensitive: false): 'Ruby',
    RegExp(r'\b(?:c\+\+|cpp|cmake)\b', caseSensitive: false): 'C++',
    RegExp(r'\b(?:c#|csharp|dotnet|\.net)\b', caseSensitive: false): 'C#',
    RegExp(r'\bphp\b', caseSensitive: false): 'PHP',
  };

  for (final entry in keywordMap.entries) {
    if (entry.key.hasMatch(input)) return entry.value;
  }

  return null;
}

/// Normalize a code-block language tag to a display name.
String? _normalizeLanguageName(String tag) {
  const map = {
    'dart': 'Dart',
    'typescript': 'TypeScript',
    'ts': 'TypeScript',
    'tsx': 'TypeScript',
    'javascript': 'JavaScript',
    'js': 'JavaScript',
    'jsx': 'JavaScript',
    'python': 'Python',
    'py': 'Python',
    'rust': 'Rust',
    'rs': 'Rust',
    'go': 'Go',
    'golang': 'Go',
    'java': 'Java',
    'kotlin': 'Kotlin',
    'kt': 'Kotlin',
    'swift': 'Swift',
    'ruby': 'Ruby',
    'rb': 'Ruby',
    'c': 'C',
    'cpp': 'C++',
    'csharp': 'C#',
    'cs': 'C#',
    'php': 'PHP',
    'html': 'HTML',
    'css': 'CSS',
    'scss': 'SCSS',
    'sql': 'SQL',
    'shell': 'Shell',
    'bash': 'Shell',
    'sh': 'Shell',
    'zsh': 'Shell',
    'json': 'JSON',
    'yaml': 'YAML',
    'yml': 'YAML',
    'xml': 'XML',
    'toml': 'TOML',
    'graphql': 'GraphQL',
    'proto': 'Protobuf',
    'dockerfile': 'Dockerfile',
    'makefile': 'Makefile',
    'vue': 'Vue',
    'svelte': 'Svelte',
    'markdown': 'Markdown',
    'md': 'Markdown',
  };
  return map[tag.toLowerCase()];
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

/// Check if input exceeds length limits.
String? validateInputLength(
  String input, {
  int maxChars = 100000,
  int maxLines = 10000,
}) {
  if (input.length > maxChars) {
    return 'Input too long: ${input.length} characters exceeds the $maxChars character limit.';
  }
  final lineCount = '\n'.allMatches(input).length + 1;
  if (lineCount > maxLines) {
    return 'Input has too many lines: $lineCount exceeds the $maxLines line limit.';
  }
  return null;
}

/// Check for potentially harmful input patterns.
List<String> checkInputSafety(String input) {
  final warnings = <String>[];

  // Check for common prompt injection patterns.
  final injectionPatterns = <RegExp, String>{
    RegExp(
      r'ignore\s+(all\s+)?previous\s+instructions',
      caseSensitive: false,
    ): 'Potential prompt injection: "ignore previous instructions" pattern detected.',
    RegExp(r'you\s+are\s+now\s+(?:a|an|in)\s+', caseSensitive: false):
        'Potential prompt injection: role reassignment pattern detected.',
    RegExp(r'system\s*:\s*', caseSensitive: false):
        'Potential prompt injection: system message impersonation detected.',
    RegExp(r'<\s*(?:system|admin|root)\s*>', caseSensitive: false):
        'Potential prompt injection: system/admin tag detected.',
    RegExp(
      r'(?:ADMIN|SYSTEM|ROOT)\s*(?:MODE|ACCESS|OVERRIDE)',
      caseSensitive: false,
    ): 'Potential prompt injection: privilege escalation pattern detected.',
    RegExp(r'forget\s+(?:everything|all|your)\s+', caseSensitive: false):
        'Potential prompt injection: memory reset pattern detected.',
    RegExp(r'(?:execute|run|eval)\s*\(', caseSensitive: false):
        'Potential code execution pattern detected.',
  };

  for (final entry in injectionPatterns.entries) {
    if (entry.key.hasMatch(input)) {
      warnings.add(entry.value);
    }
  }

  // Check for very long single lines (possible binary data or minified code).
  final lines = input.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].length > 10000) {
      warnings.add(
        'Line ${i + 1} is very long (${lines[i].length} characters). '
        'This may be minified code or binary data.',
      );
      break; // Only warn once.
    }
  }

  // Check for excessive repetition.
  if (input.length > 100) {
    final sample = input.substring(0, input.length.clamp(0, 1000));
    final words = sample.split(RegExp(r'\s+'));
    if (words.length > 10) {
      final freq = <String, int>{};
      for (final w in words) {
        freq[w] = (freq[w] ?? 0) + 1;
      }
      final maxFreq = freq.values.fold(0, (a, b) => a > b ? a : b);
      if (maxFreq > words.length * 0.5) {
        warnings.add(
          'Input contains excessive repetition, which may indicate '
          'garbled or auto-generated text.',
        );
      }
    }
  }

  // Check for null bytes or other control characters.
  if (RegExp(r'[\x00-\x08\x0e-\x1f]').hasMatch(input)) {
    warnings.add(
      'Input contains control characters that may indicate binary data.',
    );
  }

  return warnings;
}
