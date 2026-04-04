// Attachment manager — port of neom_claw/src/utils/attachments.ts.
// File attachments, IDE selections, hook attachments, queued commands,
// memory references, MCP resources, and attachment normalization for API.

import '../messages/message_utils.dart';

// ─── Constants ───

/// Header prefix for memory file attachments.
const String memoryHeader = '# Memory';

/// Config for todo reminder frequency.
const todoReminderConfig = (turnsSinceWrite: 10, turnsBetweenReminders: 10);

/// Config for plan mode attachment frequency.
const planModeAttachmentConfig = (
  turnsBetweenAttachments: 5,
  fullReminderEveryNAttachments: 5,
);

/// Config for auto mode attachment frequency.
const autoModeAttachmentConfig = (
  turnsBetweenAttachments: 5,
  fullReminderEveryNAttachments: 5,
);

/// Max lines from a memory file to inject.
const int maxMemoryLines = 200;

/// Max bytes from a memory file to inject.
const int maxMemoryBytes = 4096;

/// Config for relevant memories injection.
const relevantMemoriesConfig = (maxSessionBytes: 60 * 1024);

/// Config for plan verification reminders.
const verifyPlanReminderConfig = (turnsBetweenReminders: 10);

// ─── Attachment Types ───

/// Base attachment type.
abstract class Attachment {
  String get type;
  Map<String, dynamic> toJson();

  /// Normalize this attachment into user messages for the API.
  List<UserMessage> normalizeForAPI();
}

/// File attachment (user at-mentioned a file).
class FileAttachment extends Attachment {
  final String filename;
  final String content;
  final bool truncated;
  final String displayPath;

  FileAttachment({
    required this.filename,
    required this.content,
    this.truncated = false,
    required this.displayPath,
  });

  @override
  String get type => 'file';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'filename': filename,
    'content': content,
    'truncated': truncated,
    'displayPath': displayPath,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    final text = truncated
        ? '<file path="$displayPath">\n$content\n[truncated]\n</file>'
        : '<file path="$displayPath">\n$content\n</file>';
    return [createUserMessage(content: text, isMeta: true)];
  }
}

/// Compact file reference (file was already in context, just reference it).
class CompactFileReferenceAttachment extends Attachment {
  final String filename;
  final String displayPath;

  CompactFileReferenceAttachment({
    required this.filename,
    required this.displayPath,
  });

  @override
  String get type => 'compact_file_reference';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'filename': filename,
    'displayPath': displayPath,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content: '<file_reference path="$displayPath" />',
        isMeta: true,
      ),
    ];
  }
}

/// PDF reference attachment.
class PDFReferenceAttachment extends Attachment {
  final String filename;
  final int pageCount;
  final int fileSize;
  final String displayPath;

  PDFReferenceAttachment({
    required this.filename,
    required this.pageCount,
    required this.fileSize,
    required this.displayPath,
  });

  @override
  String get type => 'pdf_reference';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'filename': filename,
    'pageCount': pageCount,
    'fileSize': fileSize,
    'displayPath': displayPath,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<pdf_reference path="$displayPath" pages="$pageCount" size="$fileSize" />',
        isMeta: true,
      ),
    ];
  }
}

/// Directory listing attachment.
class DirectoryAttachment extends Attachment {
  final String path;
  final String content;
  final String displayPath;

  DirectoryAttachment({
    required this.path,
    required this.content,
    required this.displayPath,
  });

  @override
  String get type => 'directory';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'path': path,
    'content': content,
    'displayPath': displayPath,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content: '<directory path="$displayPath">\n$content\n</directory>',
        isMeta: true,
      ),
    ];
  }
}

/// IDE selection attachment (lines selected in an IDE).
class SelectedLinesInIdeAttachment extends Attachment {
  final String ideName;
  final int lineStart;
  final int lineEnd;
  final String filename;
  final String content;
  final String displayPath;

  SelectedLinesInIdeAttachment({
    required this.ideName,
    required this.lineStart,
    required this.lineEnd,
    required this.filename,
    required this.content,
    required this.displayPath,
  });

  @override
  String get type => 'selected_lines_in_ide';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'ideName': ideName,
    'lineStart': lineStart,
    'lineEnd': lineEnd,
    'filename': filename,
    'content': content,
    'displayPath': displayPath,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<selected_lines ide="$ideName" path="$displayPath" '
            'lines="$lineStart-$lineEnd">\n$content\n</selected_lines>',
        isMeta: true,
      ),
    ];
  }
}

/// Opened file in IDE attachment.
class OpenedFileInIdeAttachment extends Attachment {
  final String filename;

  OpenedFileInIdeAttachment({required this.filename});

  @override
  String get type => 'opened_file_in_ide';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'filename': filename};

  @override
  List<UserMessage> normalizeForAPI() => [];
}

/// Edited text file attachment.
class EditedTextFileAttachment extends Attachment {
  final String filename;
  final String snippet;

  EditedTextFileAttachment({required this.filename, required this.snippet});

  @override
  String get type => 'edited_text_file';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'filename': filename,
    'snippet': snippet,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content: '<edited_file path="$filename">\n$snippet\n</edited_file>',
        isMeta: true,
      ),
    ];
  }
}

/// Todo reminder attachment.
class TodoReminderAttachment extends Attachment {
  final List<Map<String, dynamic>> content;
  final int itemCount;

  TodoReminderAttachment({required this.content, required this.itemCount});

  @override
  String get type => 'todo_reminder';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
    'itemCount': itemCount,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    final buf = StringBuffer();
    buf.writeln('<system-reminder>');
    buf.writeln('Current todo list ($itemCount items):');
    for (final item in content) {
      final status = item['status'] ?? 'pending';
      final text = item['content'] ?? '';
      buf.writeln('- [$status] $text');
    }
    buf.writeln('</system-reminder>');
    return [createUserMessage(content: buf.toString(), isMeta: true)];
  }
}

/// Queued command attachment (user typed while model was working).
class QueuedCommandAttachment extends Attachment {
  final dynamic prompt; // String or List<ContentBlock>
  final String? sourceUuid;
  final List<int>? imagePasteIds;
  final String? commandMode;
  final MessageOrigin? origin;
  final bool? isMeta;

  QueuedCommandAttachment({
    required this.prompt,
    this.sourceUuid,
    this.imagePasteIds,
    this.commandMode,
    this.origin,
    this.isMeta,
  });

  @override
  String get type => 'queued_command';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'prompt': prompt,
    if (sourceUuid != null) 'source_uuid': sourceUuid,
    if (imagePasteIds != null) 'imagePasteIds': imagePasteIds,
    if (commandMode != null) 'commandMode': commandMode,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content: prompt,
        isMeta: isMeta,
        imagePasteIds: imagePasteIds,
        origin: origin,
      ),
    ];
  }
}

/// Output style attachment.
class OutputStyleAttachment extends Attachment {
  final String style;

  OutputStyleAttachment({required this.style});

  @override
  String get type => 'output_style';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'style': style};

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content: '<system-reminder>\nOutput style: $style\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

/// Diagnostics attachment (LSP or other diagnostic files).
class DiagnosticsAttachment extends Attachment {
  final List<Map<String, dynamic>> files;
  final bool isNew;

  DiagnosticsAttachment({required this.files, this.isNew = false});

  @override
  String get type => 'diagnostics';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'files': files,
    'isNew': isNew,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    final buf = StringBuffer();
    buf.writeln('<system-reminder>');
    buf.writeln(isNew ? 'New diagnostics:' : 'Current diagnostics:');
    for (final file in files) {
      buf.writeln('  ${file['path']}: ${file['message']}');
    }
    buf.writeln('</system-reminder>');
    return [createUserMessage(content: buf.toString(), isMeta: true)];
  }
}

/// Plan mode attachment.
class PlanModeAttachment extends Attachment {
  final String reminderType; // 'full' or 'sparse'
  final bool isSubAgent;
  final String planFilePath;
  final bool planExists;

  PlanModeAttachment({
    required this.reminderType,
    this.isSubAgent = false,
    required this.planFilePath,
    required this.planExists,
  });

  @override
  String get type => 'plan_mode';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'reminderType': reminderType,
    'isSubAgent': isSubAgent,
    'planFilePath': planFilePath,
    'planExists': planExists,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    final buf = StringBuffer();
    buf.writeln('<system-reminder>');
    if (reminderType == 'full') {
      buf.writeln('You are in PLAN MODE. Do not write code or make changes.');
      buf.writeln(
        'Instead, analyze the task, ask clarifying questions, and create a plan.',
      );
      if (planExists) {
        buf.writeln('Plan file: $planFilePath');
      }
    } else {
      buf.writeln('Reminder: You are in plan mode.');
    }
    buf.writeln('</system-reminder>');
    return [createUserMessage(content: buf.toString(), isMeta: true)];
  }
}

/// MCP resource attachment.
class McpResourceAttachment extends Attachment {
  final String server;
  final String uri;
  final String name;
  final String? description;
  final Map<String, dynamic> content;

  McpResourceAttachment({
    required this.server,
    required this.uri,
    required this.name,
    this.description,
    required this.content,
  });

  @override
  String get type => 'mcp_resource';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'server': server,
    'uri': uri,
    'name': name,
    if (description != null) 'description': description,
    'content': content,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    final contentStr = content.toString();
    return [
      createUserMessage(
        content:
            '<mcp_resource server="$server" uri="$uri" name="$name">\n'
            '$contentStr\n</mcp_resource>',
        isMeta: true,
      ),
    ];
  }
}

/// Relevant memories attachment.
class RelevantMemoriesAttachment extends Attachment {
  final List<MemoryEntry> memories;

  RelevantMemoriesAttachment({required this.memories});

  @override
  String get type => 'relevant_memories';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'memories': memories.map((m) => m.toJson()).toList(),
  };

  @override
  List<UserMessage> normalizeForAPI() {
    if (memories.isEmpty) return [];

    final buf = StringBuffer();
    buf.writeln('<system-reminder>');
    buf.writeln('Relevant memories:');
    for (final memory in memories) {
      final header = memory.header ?? memory.path;
      buf.writeln('\n--- $header ---');
      buf.writeln(memory.content);
    }
    buf.writeln('</system-reminder>');
    return [createUserMessage(content: buf.toString(), isMeta: true)];
  }
}

/// A single memory entry.
class MemoryEntry {
  final String path;
  final String content;
  final int mtimeMs;
  final String? header;
  final int? limit;

  const MemoryEntry({
    required this.path,
    required this.content,
    required this.mtimeMs,
    this.header,
    this.limit,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'content': content,
    'mtimeMs': mtimeMs,
    if (header != null) 'header': header,
    if (limit != null) 'limit': limit,
  };
}

/// Token usage attachment.
class TokenUsageAttachment extends Attachment {
  final int used;
  final int total;
  final int remaining;

  TokenUsageAttachment({
    required this.used,
    required this.total,
    required this.remaining,
  });

  @override
  String get type => 'token_usage';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'used': used,
    'total': total,
    'remaining': remaining,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<system-reminder>\nToken usage: $used / $total '
            '($remaining remaining)\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

/// Budget (USD) attachment.
class BudgetUsdAttachment extends Attachment {
  final double used;
  final double total;
  final double remaining;

  BudgetUsdAttachment({
    required this.used,
    required this.total,
    required this.remaining,
  });

  @override
  String get type => 'budget_usd';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'used': used,
    'total': total,
    'remaining': remaining,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<system-reminder>\nBudget: \$${used.toStringAsFixed(2)} / '
            '\$${total.toStringAsFixed(2)} '
            '(\$${remaining.toStringAsFixed(2)} remaining)\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

/// Date change attachment.
class DateChangeAttachment extends Attachment {
  final String newDate;

  DateChangeAttachment({required this.newDate});

  @override
  String get type => 'date_change';

  @override
  Map<String, dynamic> toJson() => {'type': type, 'newDate': newDate};

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<system-reminder>\nThe date has changed to $newDate.\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

/// Max turns reached attachment.
class MaxTurnsReachedAttachment extends Attachment {
  final int maxTurns;
  final int turnCount;

  MaxTurnsReachedAttachment({required this.maxTurns, required this.turnCount});

  @override
  String get type => 'max_turns_reached';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'maxTurns': maxTurns,
    'turnCount': turnCount,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    return [
      createUserMessage(
        content:
            '<system-reminder>\nMax turns reached ($turnCount / $maxTurns). '
            'Please wrap up your current task.\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

// ─── Hook Attachment Types ───

/// Hook attachment base.
abstract class HookAttachment extends Attachment {
  String get hookEvent;
  String get toolUseID;
}

/// Hook cancelled attachment.
class HookCancelledAttachment extends HookAttachment {
  final String hookName;
  @override
  final String toolUseID;
  @override
  final String hookEvent;
  final String? command;
  final int? durationMs;

  HookCancelledAttachment({
    required this.hookName,
    required this.toolUseID,
    required this.hookEvent,
    this.command,
    this.durationMs,
  });

  @override
  String get type => 'hook_cancelled';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'hookName': hookName,
    'toolUseID': toolUseID,
    'hookEvent': hookEvent,
    if (command != null) 'command': command,
    if (durationMs != null) 'durationMs': durationMs,
  };

  @override
  List<UserMessage> normalizeForAPI() => [];
}

/// Hook success attachment.
class HookSuccessAttachment extends HookAttachment {
  final String content;
  final String hookName;
  @override
  final String toolUseID;
  @override
  final String hookEvent;
  final String? stdout;
  final String? stderr;
  final int? exitCode;
  final String? command;
  final int? durationMs;

  HookSuccessAttachment({
    required this.content,
    required this.hookName,
    required this.toolUseID,
    required this.hookEvent,
    this.stdout,
    this.stderr,
    this.exitCode,
    this.command,
    this.durationMs,
  });

  @override
  String get type => 'hook_success';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'content': content,
    'hookName': hookName,
    'toolUseID': toolUseID,
    'hookEvent': hookEvent,
    if (stdout != null) 'stdout': stdout,
    if (stderr != null) 'stderr': stderr,
    if (exitCode != null) 'exitCode': exitCode,
    if (command != null) 'command': command,
    if (durationMs != null) 'durationMs': durationMs,
  };

  @override
  List<UserMessage> normalizeForAPI() {
    if (content.isEmpty) return [];
    return [
      createUserMessage(
        content: '<system-reminder>\n$content\n</system-reminder>',
        isMeta: true,
      ),
    ];
  }
}

/// Hook permission decision attachment.
class HookPermissionDecisionAttachment extends HookAttachment {
  final String decision; // 'allow' or 'deny'
  @override
  final String toolUseID;
  @override
  final String hookEvent;

  HookPermissionDecisionAttachment({
    required this.decision,
    required this.toolUseID,
    required this.hookEvent,
  });

  @override
  String get type => 'hook_permission_decision';

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'decision': decision,
    'toolUseID': toolUseID,
    'hookEvent': hookEvent,
  };

  @override
  List<UserMessage> normalizeForAPI() => [];
}

// ─── Attachment Normalization ───

/// Normalize an attachment map into the typed attachment.
Attachment? parseAttachment(Map<String, dynamic> json) {
  final type = json['type'] as String?;
  return switch (type) {
    'file' => FileAttachment(
      filename: json['filename'] as String,
      content: json['content'] as String? ?? '',
      truncated: json['truncated'] as bool? ?? false,
      displayPath: json['displayPath'] as String? ?? json['filename'] as String,
    ),
    'compact_file_reference' => CompactFileReferenceAttachment(
      filename: json['filename'] as String,
      displayPath: json['displayPath'] as String? ?? json['filename'] as String,
    ),
    'pdf_reference' => PDFReferenceAttachment(
      filename: json['filename'] as String,
      pageCount: json['pageCount'] as int? ?? 0,
      fileSize: json['fileSize'] as int? ?? 0,
      displayPath: json['displayPath'] as String? ?? json['filename'] as String,
    ),
    'directory' => DirectoryAttachment(
      path: json['path'] as String,
      content: json['content'] as String? ?? '',
      displayPath: json['displayPath'] as String? ?? json['path'] as String,
    ),
    'queued_command' => QueuedCommandAttachment(
      prompt: json['prompt'],
      sourceUuid: json['source_uuid'] as String?,
      commandMode: json['commandMode'] as String?,
    ),
    'output_style' => OutputStyleAttachment(style: json['style'] as String),
    'date_change' => DateChangeAttachment(newDate: json['newDate'] as String),
    _ => null,
  };
}

/// Normalize a list of attachment maps into user messages for API.
List<UserMessage> normalizeAttachmentsForAPI(
  List<Map<String, dynamic>> attachments,
) {
  final messages = <UserMessage>[];
  for (final json in attachments) {
    final attachment = parseAttachment(json);
    if (attachment != null) {
      messages.addAll(attachment.normalizeForAPI());
    }
  }
  return messages;
}

/// Get queued command attachments from a list of queued commands.
List<Attachment> getQueuedCommandAttachments(
  List<Map<String, dynamic>> queuedCommands,
) {
  return queuedCommands
      .map(
        (cmd) => QueuedCommandAttachment(
          prompt: cmd['prompt'],
          sourceUuid: cmd['source_uuid'] as String?,
          imagePasteIds: (cmd['imagePasteIds'] as List?)?.cast<int>(),
          commandMode: cmd['commandMode'] as String?,
        ),
      )
      .toList();
}
