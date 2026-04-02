// Log and transcript types — ported from OpenClaude src/types/logs.ts.

import 'ids.dart';
import 'message.dart';

/// Serialized message with session metadata.
class SerializedMessage {
  final Message message;
  final String? cwd;
  final String? userType;
  final SessionId? sessionId;
  final DateTime? timestamp;
  final String? gitBranch;
  final String? slug;
  final String? entrypoint;
  final String? parentUuid;
  final bool? isSidechain;

  const SerializedMessage({
    required this.message,
    this.cwd,
    this.userType,
    this.sessionId,
    this.timestamp,
    this.gitBranch,
    this.slug,
    this.entrypoint,
    this.parentUuid,
    this.isSidechain,
  });
}

/// Session log option with metadata.
class LogOption {
  final String path;
  final DateTime created;
  final DateTime modified;
  final int messageCount;
  final int? fileSize;
  final String? title;
  final String? summary;
  final String? teamName;
  final AgentId? agentId;
  final List<String> tags;

  const LogOption({
    required this.path,
    required this.created,
    required this.modified,
    this.messageCount = 0,
    this.fileSize,
    this.title,
    this.summary,
    this.teamName,
    this.agentId,
    this.tags = const [],
  });
}

/// AI-generated session summary.
class SummaryMessage {
  final String summary;
  final DateTime timestamp;

  const SummaryMessage({required this.summary, required this.timestamp});
}

/// User-set custom session title.
class CustomTitleMessage {
  final String title;
  const CustomTitleMessage({required this.title});
}

/// AI-generated session title.
class AiTitleMessage {
  final String title;
  const AiTitleMessage({required this.title});
}

/// Persisted last prompt in session.
class LastPromptMessage {
  final String prompt;
  const LastPromptMessage({required this.prompt});
}

/// Periodic fork-generated summary of agent activity.
class TaskSummaryMessage {
  final String summary;
  final AgentId? agentId;
  final DateTime timestamp;

  const TaskSummaryMessage({
    required this.summary,
    this.agentId,
    required this.timestamp,
  });
}

/// Session tag for searching/filtering.
class TagMessage {
  final String tag;
  const TagMessage({required this.tag});
}

/// Agent's custom name.
class AgentNameMessage {
  final String name;
  final AgentId agentId;
  const AgentNameMessage({required this.name, required this.agentId});
}

/// Agent's color assignment.
class AgentColorMessage {
  final String color;
  final AgentId agentId;
  const AgentColorMessage({required this.color, required this.agentId});
}

/// GitHub PR link metadata.
class PRLinkMessage {
  final String url;
  final String? title;
  const PRLinkMessage({required this.url, this.title});
}

/// Session mode.
enum SessionMode { coordinator, normal }

/// Worktree session state at session end.
class PersistedWorktreeSession {
  final String path;
  final String branch;
  final SessionId? sessionId;
  const PersistedWorktreeSession({
    required this.path,
    required this.branch,
    this.sessionId,
  });
}

/// Per-file Claude contribution tracking.
class FileAttributionState {
  final String filePath;
  final int totalCharacters;
  final int claudeCharacters;
  final DateTime lastModified;

  const FileAttributionState({
    required this.filePath,
    required this.totalCharacters,
    required this.claudeCharacters,
    required this.lastModified,
  });

  double get attributionPercentage =>
      totalCharacters > 0 ? claudeCharacters / totalCharacters : 0.0;
}

/// Context collapse commit entry.
class ContextCollapseCommitEntry {
  final String commitHash;
  final String message;
  final DateTime timestamp;

  const ContextCollapseCommitEntry({
    required this.commitHash,
    required this.message,
    required this.timestamp,
  });
}

/// Discriminated union of all log entry types.
sealed class LogEntry {
  const LogEntry();
}

class MessageEntry extends LogEntry {
  final SerializedMessage message;
  const MessageEntry(this.message);
}

class SummaryEntry extends LogEntry {
  final SummaryMessage summary;
  const SummaryEntry(this.summary);
}

class TitleEntry extends LogEntry {
  final String title;
  final bool isCustom;
  const TitleEntry({required this.title, required this.isCustom});
}

class TagEntry extends LogEntry {
  final TagMessage tag;
  const TagEntry(this.tag);
}

class PRLinkEntry extends LogEntry {
  final PRLinkMessage prLink;
  const PRLinkEntry(this.prLink);
}

class AttributionEntry extends LogEntry {
  final List<FileAttributionState> attributions;
  const AttributionEntry(this.attributions);
}

/// Sort logs by modified date (newest first), then created date.
int sortLogs(LogOption a, LogOption b) {
  final modCompare = b.modified.compareTo(a.modified);
  if (modCompare != 0) return modCompare;
  return b.created.compareTo(a.created);
}
