// Session restore — port of openclaude/src/utils/sessionRestore.ts.
// Restores session state from a saved transcript including todos,
// file history, and agent definitions.

import '../../domain/models/message.dart';
import '../tools/todo_write_tool.dart';
import 'session_history.dart';

/// Restored session state.
class RestoredSession {
  final SessionSnapshot snapshot;
  final List<TodoItem> todos;
  final Set<String> referencedFiles;
  final String? lastWorkingDirectory;
  final Map<String, dynamic> agentSettings;

  const RestoredSession({
    required this.snapshot,
    this.todos = const [],
    this.referencedFiles = const {},
    this.lastWorkingDirectory,
    this.agentSettings = const {},
  });
}

/// Restore a session from a snapshot, extracting embedded state.
RestoredSession restoreSession(SessionSnapshot snapshot) {
  final todos = _extractTodos(snapshot.messages);
  final files = _extractFileReferences(snapshot.messages);
  final cwd = _extractWorkingDirectory(snapshot.messages);

  return RestoredSession(
    snapshot: snapshot,
    todos: todos,
    referencedFiles: files,
    lastWorkingDirectory: cwd,
    agentSettings: snapshot.metadata,
  );
}

/// Extract the last set of todos from TodoWrite tool_use blocks.
List<TodoItem> _extractTodos(List<Message> messages) {
  List<TodoItem>? lastTodos;

  for (final msg in messages) {
    for (final block in msg.content) {
      if (block is ToolUseBlock && block.name == 'TodoWrite') {
        final todosJson = block.input['todos'] as List<dynamic>?;
        if (todosJson != null) {
          lastTodos = todosJson
              .map((t) => TodoItem.fromJson(t as Map<String, dynamic>))
              .toList();
        }
      }
    }
  }

  // If all completed, return empty
  if (lastTodos != null &&
      lastTodos.every((t) => t.status == TodoStatus.completed)) {
    return const [];
  }

  return lastTodos ?? const [];
}

/// Extract file paths referenced in conversation.
Set<String> _extractFileReferences(List<Message> messages) {
  final files = <String>{};
  final filePattern = RegExp(r'(?:^|[\s"])([/~]\S+\.\w+)');

  for (final msg in messages) {
    // From text content
    for (final match in filePattern.allMatches(msg.textContent)) {
      files.add(match.group(1)!);
    }

    // From tool uses
    for (final block in msg.content) {
      if (block is ToolUseBlock) {
        final filePath = block.input['file_path'] as String?;
        if (filePath != null) files.add(filePath);
        final path = block.input['path'] as String?;
        if (path != null) files.add(path);
      }
    }
  }

  return files;
}

/// Extract the last working directory from Bash tool uses.
String? _extractWorkingDirectory(List<Message> messages) {
  String? lastCwd;

  for (final msg in messages) {
    for (final block in msg.content) {
      if (block is ToolUseBlock && block.name == 'Bash') {
        final command = block.input['command'] as String?;
        if (command != null && command.startsWith('cd ')) {
          // Simple extraction — just get the directory argument
          final dir = command.substring(3).trim().replaceAll('"', '');
          if (dir.startsWith('/')) {
            lastCwd = dir;
          }
        }
      }
    }
  }

  return lastCwd;
}
