// Message constants — ported from Neomage src/constants/messages.ts.
// All user-facing strings centralised here for consistency and future i18n.

const String noContentMessage = '(no content)';

// ---------------------------------------------------------------------------
// Error messages
// ---------------------------------------------------------------------------

class ErrorMessages {
  ErrorMessages._();

  // API / Auth
  static const String apiKeyMissing =
      'API key is not set. Run /login or set the ANTHROPIC_API_KEY '
      'environment variable.';
  static const String apiKeyInvalid =
      'The provided API key is invalid or has been revoked. '
      'Please check your key and try again.';
  static const String modelNotFound =
      'The requested model was not found. Use /model to see available models.';
  static const String connectionFailed =
      'Unable to connect to the Anthropic API. '
      'Check your network connection and try again.';
  static const String connectionTimeout =
      'The API request timed out. The server may be under heavy load — '
      'please retry in a moment.';
  static const String rateLimited =
      'Rate limit exceeded. Please wait a moment before sending '
      'another request.';
  static const String authRequired =
      'Authentication is required to continue. Run /login to authenticate.';

  // Context / Tokens
  static const String contextWindowExceeded =
      'The conversation has exceeded the model context window. '
      'Use /compact to summarise and free up space.';
  static const String maxTokensExceeded =
      'The response exceeded the maximum token limit. '
      'Try breaking your request into smaller parts.';
  static const String maxTurnsExceeded =
      'Maximum number of conversation turns reached for this agent loop. '
      'The agent will stop and return its progress.';

  // Tools
  static const String toolNotFound =
      'The requested tool was not found in the registry. '
      'Check available tools with /help tools.';
  static const String toolExecutionFailed =
      'Tool execution failed. See the output above for details.';
  static const String toolTimedOut =
      'Tool execution timed out. The command may still be running '
      'in the background.';

  // Permissions / Sandbox
  static const String permissionDenied =
      'Permission denied. The tool requires explicit approval before '
      'it can run this command.';
  static const String sandboxViolation =
      'Sandbox violation: the command attempted to access a path '
      'outside the allowed directory.';

  // File system
  static const String fileNotFound =
      'File not found. Please verify the path and try again.';
  static const String fileReadError =
      'Unable to read the file. It may be locked or have '
      'insufficient permissions.';
  static const String fileWriteError =
      'Unable to write to the file. Check permissions and disk space.';
  static const String directoryNotFound =
      'Directory not found. Please verify the path exists.';
  static const String binaryFileError =
      'Cannot process binary file. Only text-based files are supported.';

  // Git
  static const String gitNotFound =
      'Git is not installed or not found in PATH. '
      'Please install Git and try again.';
  static const String gitNotRepo =
      'The current directory is not a Git repository. '
      'Run "git init" to initialise one.';

  // MCP
  static const String mcpConnectionFailed =
      'Failed to connect to MCP server. Check the server configuration '
      'and ensure the server is running.';
  static const String mcpServerCrashed =
      'The MCP server has crashed unexpectedly. '
      'Check server logs for details.';

  // Session
  static const String sessionNotFound =
      'Session not found. It may have been deleted or expired.';
  static const String sessionCorrupted =
      'Session data is corrupted and cannot be loaded. '
      'Start a new session with /session new.';

  // Config
  static const String configInvalid =
      'Configuration file is invalid. '
      'Check syntax and refer to the documentation.';

  // Hooks
  static const String hookFailed =
      'A hook failed during execution. '
      'Review the hook output above for details.';

  // Compaction
  static const String compactionFailed =
      'Conversation compaction failed. '
      'The conversation may be too large to summarise in one pass.';

  // Input
  static const String invalidInput =
      'Invalid input. Please check the format and try again.';
}

// ---------------------------------------------------------------------------
// Warning messages
// ---------------------------------------------------------------------------

class WarningMessages {
  WarningMessages._();

  static const String largeFile =
      'This file is very large and may slow down processing. '
      'Consider working with smaller sections.';
  static const String longRunningCommand =
      'This command is taking longer than expected. '
      'You can press Ctrl+C to cancel.';
  static const String highTokenUsage =
      'Token usage is high for this session. '
      'Consider using /compact to reduce context size.';
  static const String approachingContextLimit =
      'Approaching context window limit. '
      'Compaction will be triggered automatically soon.';
  static const String deprecatedFeature =
      'This feature is deprecated and will be removed in a future version.';
  static const String unsavedChanges =
      'You have unsaved changes that will be lost. '
      'Consider saving before continuing.';
  static const String destructiveOperation =
      'This is a destructive operation that cannot be undone. '
      'Please confirm before proceeding.';
  static const String unverifiedTool =
      'This tool has not been verified. '
      'Review its permissions before granting access.';
  static const String experimentalFeature =
      'This feature is experimental and may change or be removed '
      'in future releases.';
  static const String outdatedConfig =
      'Your configuration file uses an outdated format. '
      'Run /doctor to migrate to the latest version.';
}

// ---------------------------------------------------------------------------
// Info messages
// ---------------------------------------------------------------------------

class InfoMessages {
  InfoMessages._();

  static const String welcome =
      'Welcome to Neomage — your AI-powered coding assistant.';
  static const String sessionStarted = 'New session started.';
  static const String sessionResumed = 'Session resumed.';
  static const String sessionEnded = 'Session ended.';
  static const String compactionComplete =
      'Conversation compacted successfully.';
  static const String hookRegistered = 'Hook registered successfully.';
  static const String toolRegistered = 'Tool registered successfully.';
  static const String mcpConnected = 'MCP server connected.';
  static const String modelSwitched = 'Model switched successfully.';
  static const String permissionGranted = 'Permission granted.';
  static const String permissionDenied = 'Permission denied.';
  static const String fileCreated = 'File created successfully.';
  static const String fileModified = 'File modified successfully.';
  static const String commitCreated = 'Commit created successfully.';
  static const String configUpdated = 'Configuration updated.';
  static const String exportComplete = 'Export completed successfully.';
  static const String diagnosticsPassed = 'All diagnostics passed.';
}

// ---------------------------------------------------------------------------
// Prompt messages (interactive confirmations)
// ---------------------------------------------------------------------------

class PromptMessages {
  PromptMessages._();

  static const String confirmDelete =
      'Are you sure you want to delete this? This action cannot be undone.';
  static const String confirmOverwrite =
      'A file already exists at this location. Overwrite it?';
  static const String confirmDestructiveGit =
      'This Git operation is destructive and may result in data loss. '
      'Continue?';
  static const String confirmPermission =
      'The tool is requesting permission to perform this action. Allow?';
  static const String enterApiKey = 'Enter your Anthropic API key:';
  static const String selectModel = 'Select a model to use:';
}

// ---------------------------------------------------------------------------
// Help messages
// ---------------------------------------------------------------------------

class HelpMessages {
  HelpMessages._();

  static const String quickStart = '''
Quick Start
-----------
1. Enter a prompt to start chatting with Neomage.
2. Use / commands for special actions (type /help for a list).
3. Neomage can read and edit files, run commands, and search your codebase.
4. Use Shift+Enter for multi-line input.
5. Press Escape to cancel a running operation.
''';

  static const Map<String, String> commandHelp = {
    '/help': 'Show help information and available commands.',
    '/clear': 'Clear the conversation history (start fresh).',
    '/compact': 'Summarise conversation to free up context space.',
    '/model': 'Switch the active model.',
    '/cost': 'Display token usage and estimated cost for this session.',
    '/context': 'Show current context window usage.',
    '/memory': 'View or edit the NEOMAGE.md memory file.',
    '/commit': 'Generate a commit message and create a Git commit.',
    '/review': 'Review recent code changes with AI feedback.',
    '/diff': 'Show a diff of recent file changes.',
    '/plan': 'Toggle plan mode for structured task planning.',
    '/session': 'Manage sessions — list, resume, fork, or delete.',
    '/login': 'Authenticate with the Anthropic API.',
    '/logout': 'Clear stored authentication credentials.',
    '/doctor': 'Run diagnostics and check system health.',
    '/config': 'Open or edit the configuration file.',
    '/export': 'Export the current conversation.',
    '/bug': 'Report a bug with diagnostic information.',
  };

  static const Map<String, String> toolHelp = {
    'Read': 'Read file contents from the local filesystem.',
    'Write': 'Create or overwrite a file with new content.',
    'Edit': 'Apply targeted edits to an existing file.',
    'MultiEdit': 'Apply multiple edits to a file in a single operation.',
    'Bash': 'Execute a shell command and return its output.',
    'Glob': 'Search for files matching a glob pattern.',
    'Grep': 'Search file contents using regular expressions.',
    'LS': 'List directory contents.',
    'WebFetch': 'Fetch and process content from a URL.',
    'WebSearch': 'Search the web and return summarised results.',
    'TodoRead': 'Read the current task list.',
    'TodoWrite': 'Create or update the task list.',
    'NotebookEdit': 'Edit Jupyter notebook cells.',
  };

  static const Map<String, String> keyboardShortcuts = {
    'Enter': 'Send message',
    'Shift+Enter': 'New line',
    'Ctrl+C': 'Cancel current operation',
    'Ctrl+L': 'Clear screen',
    'Up/Down': 'Navigate message history',
    'Tab': 'Autocomplete command or path',
    'Escape': 'Dismiss autocomplete / cancel',
    'Ctrl+D': 'Exit the application',
  };
}
