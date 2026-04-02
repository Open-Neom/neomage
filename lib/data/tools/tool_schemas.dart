// Tool schemas — port of openclaude/src/tools/schemas/.
// Complete JSON Schema definitions for all Claude Code tools.
// Used for API tool_use definitions and input validation.

/// Get the complete tool schema for any tool by name.
Map<String, dynamic> getToolSchema(String toolName) {
  return _schemas[toolName] ?? _unknownToolSchema(toolName);
}

/// Get all tool schemas.
Map<String, Map<String, dynamic>> getAllToolSchemas() =>
    Map.unmodifiable(_schemas);

/// Get tool names.
List<String> getAllToolNames() => _schemas.keys.toList();

Map<String, dynamic> _unknownToolSchema(String name) => {
      'name': name,
      'description': 'Unknown tool: $name',
      'input_schema': {
        'type': 'object',
        'properties': {},
      },
    };

final _schemas = <String, Map<String, dynamic>>{
  // ── Read ──
  'Read': {
    'name': 'Read',
    'description':
        'Reads a file from the local filesystem. '
        'Assume this tool is able to read all files on the machine. '
        'The file_path parameter must be an absolute path, not a relative path. '
        'By default, it reads up to 2000 lines starting from the beginning of the file. '
        'This tool can read images (PNG, JPG), PDFs, and Jupyter notebooks.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'file_path': {
          'type': 'string',
          'description': 'The absolute path to the file to read',
        },
        'offset': {
          'type': 'number',
          'description':
              'The line number to start reading from. Only provide if the file is too large.',
        },
        'limit': {
          'type': 'number',
          'description': 'The number of lines to read.',
        },
        'pages': {
          'type': 'string',
          'description': 'Page range for PDF files (e.g., "1-5", "3", "10-20").',
        },
      },
      'required': ['file_path'],
    },
  },

  // ── Edit ──
  'Edit': {
    'name': 'Edit',
    'description':
        'Performs exact string replacements in files. '
        'The edit will FAIL if old_string is not unique in the file. '
        'ALWAYS prefer editing existing files. NEVER write new files unless explicitly required.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'file_path': {
          'type': 'string',
          'description': 'The absolute path to the file to modify',
        },
        'old_string': {
          'type': 'string',
          'description': 'The text to replace',
        },
        'new_string': {
          'type': 'string',
          'description': 'The text to replace it with (must be different from old_string)',
        },
        'replace_all': {
          'type': 'boolean',
          'description': 'Replace all occurrences of old_string (default false)',
          'default': false,
        },
      },
      'required': ['file_path', 'old_string', 'new_string'],
    },
  },

  // ── Write ──
  'Write': {
    'name': 'Write',
    'description':
        'Writes a file to the local filesystem. This tool will overwrite the existing file if there is one. '
        'If this is an existing file, you MUST use the Read tool first.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'file_path': {
          'type': 'string',
          'description': 'The absolute path to the file to write (must be absolute)',
        },
        'content': {
          'type': 'string',
          'description': 'The content to write to the file',
        },
      },
      'required': ['file_path', 'content'],
    },
  },

  // ── Bash ──
  'Bash': {
    'name': 'Bash',
    'description':
        'Executes a given bash command and returns its output. '
        'The working directory persists between commands, but shell state does not.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'command': {
          'type': 'string',
          'description': 'The command to execute',
        },
        'description': {
          'type': 'string',
          'description': 'Clear, concise description of what this command does',
        },
        'timeout': {
          'type': 'number',
          'description': 'Optional timeout in milliseconds (max 600000)',
        },
        'run_in_background': {
          'type': 'boolean',
          'description': 'Set to true to run in the background',
        },
      },
      'required': ['command'],
    },
  },

  // ── Glob ──
  'Glob': {
    'name': 'Glob',
    'description':
        'Fast file pattern matching tool that works with any codebase size. '
        'Supports glob patterns like "**/*.js" or "src/**/*.ts". '
        'Returns matching file paths sorted by modification time.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'pattern': {
          'type': 'string',
          'description': 'The glob pattern to match files against',
        },
        'path': {
          'type': 'string',
          'description': 'The directory to search in',
        },
      },
      'required': ['pattern'],
    },
  },

  // ── Grep ──
  'Grep': {
    'name': 'Grep',
    'description':
        'A powerful search tool built on ripgrep. '
        'Supports full regex syntax. Filter files with glob parameter or type parameter.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'pattern': {
          'type': 'string',
          'description': 'The regular expression pattern to search for',
        },
        'path': {
          'type': 'string',
          'description': 'File or directory to search in',
        },
        'glob': {
          'type': 'string',
          'description': 'Glob pattern to filter files (e.g. "*.js")',
        },
        'type': {
          'type': 'string',
          'description': 'File type to search (e.g., "js", "py", "rust")',
        },
        'output_mode': {
          'type': 'string',
          'enum': ['content', 'files_with_matches', 'count'],
          'description': 'Output mode. Defaults to "files_with_matches".',
        },
        'multiline': {
          'type': 'boolean',
          'description': 'Enable multiline mode. Default: false.',
        },
        'head_limit': {
          'type': 'number',
          'description': 'Limit output to first N lines/entries.',
        },
        '-i': {
          'type': 'boolean',
          'description': 'Case insensitive search',
        },
        '-n': {
          'type': 'boolean',
          'description': 'Show line numbers in output',
        },
        '-A': {
          'type': 'number',
          'description': 'Lines to show after each match',
        },
        '-B': {
          'type': 'number',
          'description': 'Lines to show before each match',
        },
        '-C': {
          'type': 'number',
          'description': 'Lines to show before and after each match',
        },
      },
      'required': ['pattern'],
    },
  },

  // ── Agent ──
  'Agent': {
    'name': 'Agent',
    'description':
        'Launch a new agent to handle complex, multi-step tasks autonomously. '
        'Each agent type has specific capabilities and tools available to it.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'prompt': {
          'type': 'string',
          'description': 'The task for the agent to perform',
        },
        'description': {
          'type': 'string',
          'description': 'A short (3-5 word) description of the task',
        },
        'subagent_type': {
          'type': 'string',
          'description': 'The type of specialized agent to use',
        },
        'model': {
          'type': 'string',
          'enum': ['sonnet', 'opus', 'haiku'],
          'description': 'Optional model override for this agent',
        },
        'run_in_background': {
          'type': 'boolean',
          'description': 'Set to true to run in the background',
        },
        'isolation': {
          'type': 'string',
          'enum': ['worktree'],
          'description': 'Isolation mode for the agent',
        },
      },
      'required': ['description', 'prompt'],
    },
  },

  // ── SendMessage ──
  'SendMessage': {
    'name': 'SendMessage',
    'description':
        'Send a message to a previously spawned agent to continue its work.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'to': {
          'type': 'string',
          'description': "The agent's ID or name to send the message to",
        },
        'message': {
          'type': 'string',
          'description': 'The message content to send',
        },
      },
      'required': ['to', 'message'],
    },
  },

  // ── TodoWrite ──
  'TodoWrite': {
    'name': 'TodoWrite',
    'description':
        'Create and manage a structured task list for the current coding session.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'todos': {
          'type': 'array',
          'description': 'The updated todo list',
          'items': {
            'type': 'object',
            'properties': {
              'content': {
                'type': 'string',
                'description': 'Task description in imperative form',
              },
              'status': {
                'type': 'string',
                'enum': ['pending', 'in_progress', 'completed'],
              },
              'activeForm': {
                'type': 'string',
                'description': 'Task description in present continuous form',
              },
            },
            'required': ['content', 'status', 'activeForm'],
          },
        },
      },
      'required': ['todos'],
    },
  },

  // ── TaskOutput ──
  'TaskOutput': {
    'name': 'TaskOutput',
    'description': 'Read the output of a background task.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'task_id': {
          'type': 'string',
          'description': 'The task ID to read output from',
        },
      },
      'required': ['task_id'],
    },
  },

  // ── ToolSearch ──
  'ToolSearch': {
    'name': 'ToolSearch',
    'description':
        'Fetches full schema definitions for deferred tools so they can be called.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description':
              'Query to find deferred tools. Use "select:<tool_name>" for direct selection.',
        },
        'max_results': {
          'type': 'number',
          'description': 'Maximum number of results to return (default: 5)',
          'default': 5,
        },
      },
      'required': ['query'],
    },
  },

  // ── WebFetch ──
  'WebFetch': {
    'name': 'WebFetch',
    'description':
        'Fetches content from a URL and returns it as markdown.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'url': {
          'type': 'string',
          'description': 'The URL to fetch',
        },
        'prompt': {
          'type': 'string',
          'description': 'Optional prompt to apply to the fetched content',
        },
      },
      'required': ['url'],
    },
  },

  // ── WebSearch ──
  'WebSearch': {
    'name': 'WebSearch',
    'description': 'Performs a web search and returns results.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': 'The search query',
        },
        'max_results': {
          'type': 'number',
          'description': 'Maximum number of results (default: 5)',
          'default': 5,
        },
      },
      'required': ['query'],
    },
  },

  // ── NotebookEdit ──
  'NotebookEdit': {
    'name': 'NotebookEdit',
    'description': 'Edit Jupyter notebooks — add, edit, delete, or move cells.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'notebook_path': {
          'type': 'string',
          'description': 'The path to the notebook file',
        },
        'command': {
          'type': 'string',
          'enum': ['add', 'edit', 'delete', 'move'],
          'description': 'The operation to perform',
        },
        'cell_index': {
          'type': 'number',
          'description': 'The index of the cell to operate on',
        },
        'content': {
          'type': 'string',
          'description': 'The new cell content',
        },
        'cell_type': {
          'type': 'string',
          'enum': ['code', 'markdown', 'raw'],
          'description': 'The cell type',
        },
        'target_index': {
          'type': 'number',
          'description': 'Target index for move operations',
        },
      },
      'required': ['notebook_path', 'command'],
    },
  },

  // ── Skill ──
  'Skill': {
    'name': 'Skill',
    'description':
        'Execute a skill within the main conversation. '
        'Skills provide specialized capabilities and domain knowledge.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'skill': {
          'type': 'string',
          'description': 'The skill name (e.g., "commit", "review-pr", "pdf")',
        },
        'args': {
          'type': 'string',
          'description': 'Optional arguments for the skill',
        },
      },
      'required': ['skill'],
    },
  },

  // ── ExitPlanMode ──
  'ExitPlanMode': {
    'name': 'ExitPlanMode',
    'description':
        'Exit plan mode and begin executing the plan that was developed.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'plan_summary': {
          'type': 'string',
          'description': 'Summary of the plan to execute',
        },
      },
      'required': ['plan_summary'],
    },
  },

  // ── EnterPlanMode ──
  'EnterPlanMode': {
    'name': 'EnterPlanMode',
    'description':
        'Enter plan mode to design an implementation strategy before making changes.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'reason': {
          'type': 'string',
          'description': 'Reason for entering plan mode',
        },
      },
      'required': ['reason'],
    },
  },
};

/// Validate tool input against schema.
List<String> validateToolInput(
    String toolName, Map<String, dynamic> input) {
  final schema = _schemas[toolName];
  if (schema == null) return ['Unknown tool: $toolName'];

  final inputSchema =
      schema['input_schema'] as Map<String, dynamic>? ?? {};
  final required =
      (inputSchema['required'] as List?)?.cast<String>() ?? [];
  final properties =
      inputSchema['properties'] as Map<String, dynamic>? ?? {};

  final errors = <String>[];

  // Check required fields
  for (final field in required) {
    if (!input.containsKey(field) || input[field] == null) {
      errors.add('Missing required field: $field');
    }
  }

  // Type checking
  for (final entry in input.entries) {
    final prop = properties[entry.key] as Map<String, dynamic>?;
    if (prop == null) continue; // Extra fields are ok

    final expectedType = prop['type'] as String?;
    if (expectedType != null) {
      final valid = switch (expectedType) {
        'string' => entry.value is String,
        'number' => entry.value is num,
        'boolean' => entry.value is bool,
        'array' => entry.value is List,
        'object' => entry.value is Map,
        _ => true,
      };
      if (!valid) {
        errors.add(
            'Field "${entry.key}" expected $expectedType but got ${entry.value.runtimeType}');
      }
    }

    // Enum validation
    final enumValues = prop['enum'] as List?;
    if (enumValues != null && !enumValues.contains(entry.value)) {
      errors.add(
          'Field "${entry.key}" must be one of: ${enumValues.join(", ")}');
    }
  }

  return errors;
}

/// Format a tool schema for display.
String formatToolSchema(String toolName) {
  final schema = _schemas[toolName];
  if (schema == null) return 'Unknown tool: $toolName';

  final buffer = StringBuffer();
  buffer.writeln('Tool: ${schema['name']}');
  buffer.writeln('Description: ${schema['description']}');

  final inputSchema =
      schema['input_schema'] as Map<String, dynamic>? ?? {};
  final properties =
      inputSchema['properties'] as Map<String, dynamic>? ?? {};
  final required =
      (inputSchema['required'] as List?)?.cast<String>() ?? [];

  if (properties.isNotEmpty) {
    buffer.writeln('Parameters:');
    for (final entry in properties.entries) {
      final prop = entry.value as Map<String, dynamic>;
      final isRequired = required.contains(entry.key);
      final type = prop['type'] ?? 'any';
      buffer.write('  ${entry.key} ($type)');
      if (isRequired) buffer.write(' [required]');
      if (prop['description'] != null) {
        buffer.write(' — ${prop['description']}');
      }
      buffer.writeln();
    }
  }

  return buffer.toString();
}
