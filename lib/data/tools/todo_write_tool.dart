// TodoWrite tool — port of openclaude/src/tools/TodoWriteTool.
// Manages structured task lists for tracking multi-step work.

import 'tool.dart';

/// A single todo item.
class TodoItem {
  final String content;
  final String activeForm;
  final TodoStatus status;

  const TodoItem({
    required this.content,
    required this.activeForm,
    required this.status,
  });

  factory TodoItem.fromJson(Map<String, dynamic> json) => TodoItem(
        content: json['content'] as String,
        activeForm: json['activeForm'] as String? ?? json['content'] as String,
        status: TodoStatus.fromString(json['status'] as String? ?? 'pending'),
      );

  Map<String, dynamic> toJson() => {
        'content': content,
        'activeForm': activeForm,
        'status': status.name,
      };

  TodoItem copyWith({TodoStatus? status}) => TodoItem(
        content: content,
        activeForm: activeForm,
        status: status ?? this.status,
      );
}

/// Status of a todo item.
enum TodoStatus {
  pending,
  inProgress,
  completed;

  static TodoStatus fromString(String s) => switch (s) {
        'in_progress' => TodoStatus.inProgress,
        'inProgress' => TodoStatus.inProgress,
        'completed' => TodoStatus.completed,
        _ => TodoStatus.pending,
      };

  @override
  String toString() => switch (this) {
        TodoStatus.pending => 'pending',
        TodoStatus.inProgress => 'in_progress',
        TodoStatus.completed => 'completed',
      };
}

/// Callback for persisting todos.
typedef TodoStore = void Function(String key, List<TodoItem> todos);

/// TodoWrite tool — manages structured task lists.
class TodoWriteTool extends Tool {
  /// In-memory todo storage keyed by session/agent ID.
  final Map<String, List<TodoItem>> _store = {};

  /// Optional persistence callback.
  TodoStore? onTodosChanged;

  @override
  String get name => 'TodoWrite';

  @override
  String get description =>
      'Creates and manages a structured task list for tracking '
      'multi-step work. Supports pending, in_progress, and completed states.';

  @override
  bool get shouldDefer => true;

  @override
  Map<String, dynamic> get inputSchema => {
        'type': 'object',
        'properties': {
          'todos': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'content': {
                  'type': 'string',
                  'description': 'Task description (imperative form)',
                },
                'activeForm': {
                  'type': 'string',
                  'description': 'Task description (present continuous form)',
                },
                'status': {
                  'type': 'string',
                  'enum': ['pending', 'in_progress', 'completed'],
                  'description': 'Current task status',
                },
              },
              'required': ['content', 'status'],
            },
          },
        },
        'required': ['todos'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async {
    return _executeWithKey(input, 'default');
  }

  /// Execute with a specific todo key (session/agent ID).
  Future<ToolResult> executeForKey(
    Map<String, dynamic> input,
    String todoKey,
  ) {
    return _executeWithKey(input, todoKey);
  }

  Future<ToolResult> _executeWithKey(
    Map<String, dynamic> input,
    String todoKey,
  ) async {
    final todosJson = input['todos'] as List<dynamic>?;
    if (todosJson == null) {
      return ToolResult.error('Missing required parameter: todos');
    }

    try {
      final oldTodos = List<TodoItem>.from(_store[todoKey] ?? []);
      final newTodos = todosJson
          .map((t) => TodoItem.fromJson(t as Map<String, dynamic>))
          .toList();

      // If all are completed, clear the list
      final allDone = newTodos.every((t) => t.status == TodoStatus.completed);
      final effectiveTodos = allDone ? <TodoItem>[] : newTodos;

      _store[todoKey] = effectiveTodos;
      onTodosChanged?.call(todoKey, effectiveTodos);

      return ToolResult.success(
        'Todos have been modified successfully. '
        'Ensure that you continue to use the todo list to track your progress. '
        'Please proceed with the current tasks if applicable',
        metadata: {
          'oldTodos': oldTodos.map((t) => t.toJson()).toList(),
          'newTodos': effectiveTodos.map((t) => t.toJson()).toList(),
        },
      );
    } catch (e) {
      return ToolResult.error('Error updating todos: $e');
    }
  }

  /// Get todos for a key.
  List<TodoItem> getTodos(String key) =>
      List.unmodifiable(_store[key] ?? const []);

  /// Get all todo keys.
  Set<String> get keys => _store.keys.toSet();
}
