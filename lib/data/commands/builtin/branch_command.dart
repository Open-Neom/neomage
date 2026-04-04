// /branch command — conversation branching (fork) command.
// Faithful port of neom_claw/src/commands/branch/branch.ts (296 TS LOC).
//
// Creates a fork of the current conversation by copying from the transcript
// file. Preserves all original metadata (timestamps, gitBranch, etc.) while
// updating sessionId and adding forkedFrom traceability. Handles unique fork
// naming with collision detection (appending " (Branch N)" suffixes).

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// TranscriptEntry — represents a transcript message with optional fork info.
// ============================================================================

/// A transcript entry extended with fork provenance metadata.
class TranscriptEntry {
  final String sessionId;
  final String uuid;
  final String type;
  final String? parentUuid;
  final bool isSidechain;
  final Map<String, dynamic> rawData;

  /// Fork provenance: which session/message this was forked from.
  final ForkOrigin? forkedFrom;

  const TranscriptEntry({
    required this.sessionId,
    required this.uuid,
    required this.type,
    this.parentUuid,
    this.isSidechain = false,
    required this.rawData,
    this.forkedFrom,
  });

  /// Create from a raw JSON map.
  factory TranscriptEntry.fromJson(Map<String, dynamic> json) {
    ForkOrigin? origin;
    if (json.containsKey('forkedFrom') && json['forkedFrom'] is Map) {
      final fork = json['forkedFrom'] as Map<String, dynamic>;
      origin = ForkOrigin(
        sessionId: fork['sessionId'] as String,
        messageUuid: fork['messageUuid'] as String,
      );
    }
    return TranscriptEntry(
      sessionId: json['sessionId'] as String? ?? '',
      uuid: json['uuid'] as String? ?? '',
      type: json['type'] as String? ?? '',
      parentUuid: json['parentUuid'] as String?,
      isSidechain: json['isSidechain'] as bool? ?? false,
      rawData: json,
      forkedFrom: origin,
    );
  }

  /// Serialize to JSON map, applying fork overrides.
  Map<String, dynamic> toJson({
    String? overrideSessionId,
    String? overrideParentUuid,
    bool? overrideIsSidechain,
    ForkOrigin? overrideForkedFrom,
  }) {
    final result = Map<String, dynamic>.from(rawData);
    if (overrideSessionId != null) result['sessionId'] = overrideSessionId;
    if (overrideParentUuid != null) result['parentUuid'] = overrideParentUuid;
    if (overrideIsSidechain != null) {
      result['isSidechain'] = overrideIsSidechain;
    }
    if (overrideForkedFrom != null) {
      result['forkedFrom'] = overrideForkedFrom.toJson();
    }
    return result;
  }
}

/// Represents the origin of a forked transcript message.
class ForkOrigin {
  final String sessionId;
  final String messageUuid;

  const ForkOrigin({required this.sessionId, required this.messageUuid});

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'messageUuid': messageUuid,
  };
}

// ============================================================================
// ContentReplacementEntry — records which tool_result blocks were replaced.
// ============================================================================

/// Represents a content-replacement record from the transcript.
/// Without these in the fork JSONL, resume reconstructs state with an empty
/// replacements Map, causing prompt cache misses and permanent overages.
class ContentReplacementEntry {
  final String sessionId;
  final List<Map<String, dynamic>> replacements;

  const ContentReplacementEntry({
    required this.sessionId,
    required this.replacements,
  });

  factory ContentReplacementEntry.fromJson(Map<String, dynamic> json) {
    return ContentReplacementEntry(
      sessionId: json['sessionId'] as String? ?? '',
      replacements:
          (json['replacements'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'type': 'content-replacement',
    'sessionId': sessionId,
    'replacements': replacements,
  };
}

// ============================================================================
// SerializedMessage — a simplified transcript message for resume/LogOption.
// ============================================================================

/// Lightweight representation of a serialized message for the fork log.
class SerializedMessage {
  final String type;
  final String sessionId;
  final Map<String, dynamic> rawData;

  const SerializedMessage({
    required this.type,
    required this.sessionId,
    required this.rawData,
  });

  factory SerializedMessage.fromJson(Map<String, dynamic> json) {
    return SerializedMessage(
      type: json['type'] as String? ?? '',
      sessionId: json['sessionId'] as String? ?? '',
      rawData: json,
    );
  }

  Map<String, dynamic> toJson() {
    final result = Map<String, dynamic>.from(rawData);
    result['sessionId'] = sessionId;
    return result;
  }
}

// ============================================================================
// ForkResult — the result of creating a conversation fork.
// ============================================================================

/// Result returned after successfully creating a fork.
class ForkResult {
  final String sessionId;
  final String? title;
  final String forkPath;
  final List<SerializedMessage> serializedMessages;
  final List<Map<String, dynamic>> contentReplacementRecords;

  const ForkResult({
    required this.sessionId,
    this.title,
    required this.forkPath,
    required this.serializedMessages,
    required this.contentReplacementRecords,
  });
}

// ============================================================================
// SessionStorage utilities — project dir, transcript paths, title management.
// ============================================================================

/// Get the project directory for session storage.
String getProjectDir(String cwd) {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return p.join(home, '.neomclaw', 'projects', _sanitizePath(cwd));
}

/// Sanitize a file path for use as a directory name.
String _sanitizePath(String path) {
  return path.replaceAll(RegExp(r'[/\\:]'), '_').replaceAll(RegExp(r'^_+'), '');
}

/// Get the transcript path for a specific session ID.
String getTranscriptPathForSession(String projectDir, String sessionId) {
  return p.join(projectDir, '$sessionId.jsonl');
}

/// Parse JSONL content into a list of JSON maps.
List<Map<String, dynamic>> parseJsonl(String content) {
  final lines = content.split('\n').where((l) => l.trim().isNotEmpty);
  final results = <Map<String, dynamic>>[];
  for (final line in lines) {
    try {
      final parsed = jsonDecode(line);
      if (parsed is Map<String, dynamic>) {
        results.add(parsed);
      }
    } catch (_) {
      // Skip malformed lines
    }
  }
  return results;
}

/// Check if an entry is a transcript message (not metadata like
/// content-replacement).
bool isTranscriptMessage(Map<String, dynamic> entry) {
  final type = entry['type'] as String?;
  return type != null && type != 'content-replacement';
}

// ============================================================================
// Title / naming utilities.
// ============================================================================

/// Derive a single-line title base from the first user message.
/// Collapses whitespace so multiline first messages (pasted stacks, code)
/// don't flow into the saved title and break the resume hint.
String deriveFirstPrompt(SerializedMessage? firstUserMessage) {
  if (firstUserMessage == null) return 'Branched conversation';

  final message = firstUserMessage.rawData['message'];
  if (message == null) return 'Branched conversation';

  final content = message is Map ? message['content'] : null;
  if (content == null) return 'Branched conversation';

  String? raw;
  if (content is String) {
    raw = content;
  } else if (content is List) {
    for (final block in content) {
      if (block is Map && block['type'] == 'text') {
        raw = block['text'] as String?;
        break;
      }
    }
  }

  if (raw == null || raw.isEmpty) return 'Branched conversation';

  final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return 'Branched conversation';

  return collapsed.length > 100 ? collapsed.substring(0, 100) : collapsed;
}

/// Save a custom title for a session by writing a metadata file.
Future<void> saveCustomTitle(
  String projectDir,
  String sessionId,
  String title,
  String forkPath,
) async {
  final metaPath = p.join(projectDir, '$sessionId.meta.json');
  final meta = {
    'customTitle': title,
    'forkPath': forkPath,
    'savedAt': DateTime.now().toIso8601String(),
  };
  await File(
    metaPath,
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(meta));
}

/// Search for sessions matching a custom title pattern.
/// Returns a list of maps with sessionId and customTitle fields.
Future<List<Map<String, String>>> searchSessionsByCustomTitle(
  String projectDir,
  String pattern, {
  bool exact = false,
}) async {
  final results = <Map<String, String>>[];
  final dir = Directory(projectDir);
  if (!await dir.exists()) return results;

  await for (final entity in dir.list()) {
    if (entity is File && entity.path.endsWith('.meta.json')) {
      try {
        final content = await entity.readAsString();
        final meta = jsonDecode(content) as Map<String, dynamic>;
        final customTitle = meta['customTitle'] as String?;
        if (customTitle == null) continue;

        if (exact) {
          if (customTitle == pattern) {
            final sessionId = p
                .basenameWithoutExtension(entity.path)
                .replaceAll('.meta', '');
            results.add({'sessionId': sessionId, 'customTitle': customTitle});
          }
        } else {
          if (customTitle.contains(pattern)) {
            final sessionId = p
                .basenameWithoutExtension(entity.path)
                .replaceAll('.meta', '');
            results.add({'sessionId': sessionId, 'customTitle': customTitle});
          }
        }
      } catch (_) {
        // Skip malformed meta files
      }
    }
  }
  return results;
}

// ============================================================================
// Unique fork name generation.
// ============================================================================

/// Generate a unique fork name by checking for collisions with existing
/// session names. If "baseName (Branch)" already exists, tries
/// "baseName (Branch 2)", "baseName (Branch 3)", etc.
Future<String> getUniqueForkName(String projectDir, String baseName) async {
  final candidateName = '$baseName (Branch)';

  // Check if this exact name already exists
  final existingWithExactName = await searchSessionsByCustomTitle(
    projectDir,
    candidateName,
    exact: true,
  );

  if (existingWithExactName.isEmpty) {
    return candidateName;
  }

  // Name collision — find a unique numbered suffix.
  // Search for all sessions that start with the base pattern.
  final existingForks = await searchSessionsByCustomTitle(
    projectDir,
    '$baseName (Branch',
  );

  // Extract existing fork numbers to find the next available.
  final usedNumbers = <int>{1}; // Consider " (Branch)" as number 1
  final escapedBase = RegExp.escape(baseName);
  final forkNumberPattern = RegExp('^$escapedBase \\(Branch(?: (\\d+))?\\)\$');

  for (final session in existingForks) {
    final title = session['customTitle'];
    if (title == null) continue;
    final match = forkNumberPattern.firstMatch(title);
    if (match != null) {
      final numberStr = match.group(1);
      if (numberStr != null) {
        usedNumbers.add(int.parse(numberStr));
      } else {
        usedNumbers.add(1); // " (Branch)" without number is treated as 1
      }
    }
  }

  // Find the next available number.
  var nextNumber = 2;
  while (usedNumbers.contains(nextNumber)) {
    nextNumber++;
  }

  return '$baseName (Branch $nextNumber)';
}

// ============================================================================
// UUID generation (simple v4 for fork session IDs).
// ============================================================================

/// Generate a v4 UUID string.
String generateUuid() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  // Set version 4
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  // Set variant 1
  bytes[8] = (bytes[8] & 0x3f) | 0x80;

  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
      '${hex.substring(20)}';
}

// ============================================================================
// createFork — core fork logic.
// ============================================================================

/// Creates a fork of the current conversation by copying from the transcript
/// file. Preserves all original metadata (timestamps, gitBranch, etc.) while
/// updating sessionId and adding forkedFrom traceability.
Future<ForkResult> createFork({
  required String currentTranscriptPath,
  required String originalSessionId,
  required String projectDir,
  String? customTitle,
}) async {
  final forkSessionId = generateUuid();
  final forkSessionPath = getTranscriptPathForSession(
    projectDir,
    forkSessionId,
  );

  // Ensure project directory exists
  await Directory(projectDir).create(recursive: true);

  // Read current transcript file
  final transcriptFile = File(currentTranscriptPath);
  String transcriptContent;
  try {
    transcriptContent = await transcriptFile.readAsString();
  } catch (_) {
    throw StateError('No conversation to branch');
  }

  if (transcriptContent.trim().isEmpty) {
    throw StateError('No conversation to branch');
  }

  // Parse all transcript entries (messages + metadata entries like
  // content-replacement).
  final entries = parseJsonl(transcriptContent);

  // Filter to only main conversation messages (exclude sidechains and
  // non-message entries).
  final mainConversationEntries = entries
      .where(
        (entry) =>
            isTranscriptMessage(entry) &&
            (entry['isSidechain'] as bool? ?? false) == false,
      )
      .toList();

  // Content-replacement entries for the original session. These record which
  // tool_result blocks were replaced with previews by the per-message budget.
  // Without them in the fork JSONL, resume reconstructs state with an empty
  // replacements Map -> previously-replaced results are classified as FROZEN
  // and sent as full content (prompt cache miss + permanent overage).
  // sessionId must be rewritten since loadTranscriptFile keys lookup by the
  // session's messages' sessionId.
  final contentReplacementRecords = entries
      .where(
        (entry) =>
            entry['type'] == 'content-replacement' &&
            entry['sessionId'] == originalSessionId,
      )
      .expand(
        (entry) =>
            (entry['replacements'] as List<dynamic>?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ??
            <Map<String, dynamic>>[],
      )
      .toList();

  if (mainConversationEntries.isEmpty) {
    throw StateError('No messages to branch');
  }

  // Build forked entries with new sessionId and preserved metadata.
  String? parentUuid;
  final lines = <String>[];
  final serializedMessages = <SerializedMessage>[];

  for (final entry in mainConversationEntries) {
    final entryData = Map<String, dynamic>.from(entry);
    entryData['sessionId'] = forkSessionId;
    entryData['parentUuid'] = parentUuid;
    entryData['isSidechain'] = false;
    entryData['forkedFrom'] = {
      'sessionId': originalSessionId,
      'messageUuid': entry['uuid'] ?? '',
    };

    // Build serialized message for LogOption.
    final serialized = Map<String, dynamic>.from(entry);
    serialized['sessionId'] = forkSessionId;

    serializedMessages.add(
      SerializedMessage(
        type: entry['type'] as String? ?? '',
        sessionId: forkSessionId,
        rawData: serialized,
      ),
    );

    lines.add(jsonEncode(entryData));

    if (entry['type'] != 'progress') {
      parentUuid = entry['uuid'] as String?;
    }
  }

  // Append content-replacement entry (if any) with the fork's sessionId.
  // Written as a SINGLE entry (same shape as insertContentReplacement) so
  // loadTranscriptFile's content-replacement branch picks it up.
  if (contentReplacementRecords.isNotEmpty) {
    final forkedReplacementEntry = {
      'type': 'content-replacement',
      'sessionId': forkSessionId,
      'replacements': contentReplacementRecords,
    };
    lines.add(jsonEncode(forkedReplacementEntry));
  }

  // Write the fork session file.
  await File(
    forkSessionPath,
  ).writeAsString('${lines.join('\n')}\n', flush: true);

  return ForkResult(
    sessionId: forkSessionId,
    title: customTitle,
    forkPath: forkSessionPath,
    serializedMessages: serializedMessages,
    contentReplacementRecords: contentReplacementRecords,
  );
}

// ============================================================================
// BranchCommand
// ============================================================================

/// The /branch command — creates a fork (branch) of the current conversation.
///
/// Copies all main-conversation messages from the current transcript into a new
/// session file, updates session IDs, preserves content-replacement records,
/// generates a unique fork name, and (when the resume callback is available)
/// switches the user into the forked session.
class BranchCommand extends LocalCommand {
  /// Callback to get the current session ID.
  final String Function() getSessionId;

  /// Callback to get the current working directory.
  final String Function() getCwd;

  /// Callback to get the current transcript path.
  final String Function() getTranscriptPath;

  /// Callback to resume into a different session.
  /// Signature: (sessionId, forkPath, mode) => Future<void>.
  final Future<void> Function(String sessionId, String forkPath, String mode)?
  onResume;

  BranchCommand({
    required this.getSessionId,
    required this.getCwd,
    required this.getTranscriptPath,
    this.onResume,
  });

  @override
  String get name => 'branch';

  @override
  String get description =>
      'Create a branch (fork) of the current conversation';

  @override
  String? get argumentHint => '[custom title]';

  @override
  bool get supportsNonInteractive => false;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    final customTitle = args.trim().isEmpty ? null : args.trim();
    final originalSessionId = getSessionId();

    try {
      final cwd = getCwd();
      final projectDir = getProjectDir(cwd);

      final result = await createFork(
        currentTranscriptPath: getTranscriptPath(),
        originalSessionId: originalSessionId,
        projectDir: projectDir,
        customTitle: customTitle,
      );

      // Derive first prompt for title fallback.
      final firstUser = result.serializedMessages
          .where((m) => m.type == 'user')
          .firstOrNull;
      final firstPrompt = deriveFirstPrompt(firstUser);

      // Save custom title — use provided title or firstPrompt as default.
      // This ensures /status and /resume show the same session name.
      // Always add " (Branch)" suffix to make it clear this is a branched
      // session. Handle collisions by adding a number suffix.
      final baseName = result.title ?? firstPrompt;
      final effectiveTitle = await getUniqueForkName(projectDir, baseName);
      await saveCustomTitle(
        projectDir,
        result.sessionId,
        effectiveTitle,
        result.forkPath,
      );

      // Resume into the fork if callback is available.
      final titleInfo = result.title != null ? ' "${result.title}"' : '';
      final resumeHint =
          '\nTo resume the original: neomclaw -r $originalSessionId';
      final successMessage =
          'Branched conversation$titleInfo. '
          'You are now in the branch.$resumeHint';

      if (onResume != null) {
        await onResume!(result.sessionId, result.forkPath, 'fork');
        return TextCommandResult(successMessage);
      } else {
        // Fallback if resume not available.
        return TextCommandResult(
          'Branched conversation$titleInfo. '
          'Resume with: /resume ${result.sessionId}',
        );
      }
    } catch (e) {
      final message = e is StateError ? e.message : 'Unknown error occurred';
      return TextCommandResult('Failed to branch conversation: $message');
    }
  }
}
