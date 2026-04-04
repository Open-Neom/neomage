// Full constants — port of remaining neom_claw/src/constants/.
// All constants not already in individual constant files.

/// Maximum conversation turns before suggesting compaction.
const maxConversationTurns = 40;

/// Maximum tool output length in characters.
const maxToolOutputLength = 100000;

/// Maximum file read size in characters.
const maxFileReadLength = 2000000;

/// Maximum search results from grep/glob.
const maxSearchResults = 500;

/// Maximum search results displayed.
const maxSearchResultsDisplay = 250;

/// Default command timeout in milliseconds.
const defaultCommandTimeoutMs = 120000;

/// Maximum command timeout in milliseconds (10 minutes).
const maxCommandTimeoutMs = 600000;

/// Maximum concurrent agents.
const maxAgents = 10;

/// Maximum agent depth (nested agents).
const maxAgentDepth = 5;

/// Maximum MCP servers.
const maxMcpServers = 20;

/// Maximum MCP server restart attempts.
const maxMcpRestarts = 3;

/// Session ID length.
const sessionIdLength = 36;

/// Maximum attachments per message.
const maxAttachments = 10;

/// Maximum image size in bytes (20MB).
const maxImageSizeBytes = 20 * 1024 * 1024;

/// Maximum PDF size in bytes (32MB).
const maxPdfSizeBytes = 32 * 1024 * 1024;

/// Maximum notebook cells.
const maxNotebookCells = 500;

/// Maximum skill file size in bytes.
const maxSkillFileSize = 100000;

/// Supported image formats for multimodal input.
const supportedImageFormats = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'svg',
};

/// Supported audio formats for voice input.
const supportedAudioFormats = {
  'mp3',
  'wav',
  'ogg',
  'flac',
  'm4a',
  'aac',
  'webm',
};

/// Supported document formats.
const supportedDocFormats = {
  'pdf',
  'txt',
  'md',
  'csv',
  'tsv',
  'json',
  'yaml',
  'yml',
  'xml',
  'html',
  'htm',
  'rst',
  'tex',
  'log',
};

/// Model context window sizes (in tokens).
const modelContextWindows = <String, int>{
  'claude-opus-4-20250514': 200000,
  'claude-sonnet-4-20250514': 200000,
  'claude-sonnet-4-5-20250514': 200000,
  'claude-haiku-3-5-20241022': 200000,
  'gpt-4o': 128000,
  'gpt-4o-mini': 128000,
  'gpt-4-turbo': 128000,
  'gemini-2.5-pro': 1048576,
  'gemini-2.0-flash': 1048576,
};

/// Maximum output tokens per model.
const modelMaxOutputTokens = <String, int>{
  'claude-opus-4-20250514': 32000,
  'claude-sonnet-4-20250514': 16000,
  'claude-sonnet-4-5-20250514': 16000,
  'claude-haiku-3-5-20241022': 8192,
  'gpt-4o': 16384,
  'gpt-4o-mini': 16384,
  'gemini-2.5-pro': 65536,
};

/// Default .gitignore patterns for .neomclaw/ directory.
const neomClawGitignorePatterns = [
  '# NeomClaw local files',
  '.neomclaw/settings.local.json',
  '.neomclaw/sessions/',
  '.neomclaw/telemetry/',
  '.neomclaw/todos/',
  '.neomclaw/cache/',
  '.neomclaw/logs/',
];

/// Commands that ALWAYS require explicit permission.
const dangerousCommands = <String>{
  'rm',
  'rmdir',
  'del',
  'mkfs',
  'fdisk',
  'dd',
  'chmod',
  'chown',
  'chgrp',
  'kill',
  'killall',
  'pkill',
  'shutdown',
  'reboot',
  'halt',
  'init',
  'iptables',
  'ufw',
  'useradd',
  'userdel',
  'usermod',
  'passwd',
  'su',
  'sudo',
  'mount',
  'umount',
  'systemctl',
  'service',
  'crontab',
  'eval',
  'exec',
};

/// Commands that are always safe (read-only, no side effects).
const safeCommands = <String>{
  'ls',
  'dir',
  'pwd',
  'whoami',
  'hostname',
  'uname',
  'cat',
  'head',
  'tail',
  'less',
  'more',
  'wc',
  'echo',
  'printf',
  'date',
  'cal',
  'which',
  'where',
  'whereis',
  'whatis',
  'type',
  'file',
  'stat',
  'du',
  'df',
  'env',
  'printenv',
  'set',
  'id',
  'groups',
  'true',
  'false',
  'basename',
  'dirname',
  'realpath',
  'readlink',
  'md5sum',
  'sha256sum',
  'sha1sum',
  'sort',
  'uniq',
  'tr',
  'cut',
  'paste',
  'fold',
  'column',
  'diff',
  'comm',
  'cmp',
  'tee',
  'xargs',
  'seq',
  'yes',
};

/// Safe git subcommands (read-only).
const safeGitCommands = <String>{
  'status',
  'log',
  'diff',
  'show',
  'branch',
  'tag',
  'describe',
  'rev-parse',
  'rev-list',
  'ls-files',
  'ls-tree',
  'ls-remote',
  'shortlog',
  'blame',
  'bisect',
  'config',
  'remote',
  'stash',
  'reflog',
  'cherry',
  'name-rev',
  'verify-commit',
  'verify-tag',
  'count-objects',
  'fsck',
  'for-each-ref',
  'merge-base',
};

/// Standard permission prompt templates.
class PermissionPrompts {
  static const fileWrite =
      'NeomClaw wants to write to file: {path}\nAllow this operation?';
  static const fileDelete =
      'NeomClaw wants to delete file: {path}\nAllow this operation?';
  static const shellCommand =
      'NeomClaw wants to run: {command}\nAllow this operation?';
  static const networkAccess =
      'NeomClaw wants to access: {url}\nAllow this operation?';
  static const mcpConnect =
      'NeomClaw wants to connect to MCP server: {name}\nAllow this connection?';
  static const agentSpawn =
      'NeomClaw wants to spawn agent: {name} with model {model}\nAllow?';

  static String format(String template, Map<String, String> params) {
    var result = template;
    for (final entry in params.entries) {
      result = result.replaceAll('{${entry.key}}', entry.value);
    }
    return result;
  }
}

/// Standard error messages.
class ErrorMessages {
  static const apiKeyMissing =
      'No API key configured. Set ANTHROPIC_API_KEY or use /login.';
  static const apiKeyInvalid = 'Invalid API key. Check your credentials.';
  static const rateLimited = 'Rate limited. Retrying in {seconds} seconds...';
  static const contextWindowExceeded =
      'Context window exceeded. Use /compact to compress the conversation.';
  static const modelNotAvailable =
      'Model {model} is not available. Use /model to select a different model.';
  static const toolNotFound =
      'Tool {tool} not found. Use /tools to list available tools.';
  static const commandNotFound =
      'Unknown command: {command}. Use /help to see available commands.';
  static const fileNotFound = 'File not found: {path}';
  static const permissionDenied =
      'Permission denied for operation: {operation}';
  static const networkError =
      'Network error: {message}. Check your connection.';
  static const timeoutError = 'Operation timed out after {seconds} seconds.';
  static const sandboxViolation = 'Operation blocked by sandbox: {reason}';
  static const mcpServerError = 'MCP server {name} error: {message}';
  static const sessionCorrupted =
      'Session data is corrupted. Starting fresh session.';
  static const diskFull = 'Disk space is low. Free up space to continue.';
  static const maxAgentsReached =
      'Maximum agent limit ($maxAgents) reached. Wait for agents to complete.';
}

/// Release info.
const releaseVersion = '1.0.0-beta.1';
const releaseName = 'Neom Claw';
const releaseCodename = 'Garuda';
const buildDate = '2026-04-01';
const protocolVersion = '2024-11-05';

/// Supported MCP protocol versions.
const supportedMcpVersions = ['2024-11-05', '2024-10-07'];

/// Default API endpoints per provider.
const apiEndpoints = <String, String>{
  'anthropic': 'https://api.anthropic.com/v1',
  'openai': 'https://api.openai.com/v1',
  'bedrock': 'https://bedrock-runtime.{region}.amazonaws.com',
  'vertex': 'https://{region}-aiplatform.googleapis.com/v1',
  'gemini': 'https://generativelanguage.googleapis.com/v1beta',
  'ollama': 'http://localhost:11434/api',
};

/// HTTP user agent string.
const userAgent = 'FlutterClaw/$releaseVersion (Dart)';

/// API version headers.
const anthropicVersion = '2023-06-01';
const anthropicBetaVersion = 'prompt-caching-2024-07-31';

/// Animation durations.
class AnimationDurations {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
  static const toast = Duration(seconds: 3);
  static const tooltip = Duration(milliseconds: 800);
  static const splash = Duration(seconds: 2);
}

/// Size constants.
class SizeConstants {
  static const sidebarWidth = 320.0;
  static const sidebarCollapsedWidth = 48.0;
  static const maxChatWidth = 800.0;
  static const maxCodeWidth = 900.0;
  static const minWindowWidth = 400.0;
  static const minWindowHeight = 300.0;
  static const mobileBreakpoint = 600.0;
  static const tabletBreakpoint = 900.0;
  static const desktopBreakpoint = 1200.0;
  static const toolbarHeight = 48.0;
  static const statusBarHeight = 24.0;
  static const inputMinHeight = 56.0;
  static const inputMaxHeight = 300.0;
  static const avatarSize = 32.0;
  static const iconSize = 20.0;
  static const chipHeight = 28.0;
  static const scrollbarWidth = 8.0;
}

/// Keyboard shortcut labels.
class ShortcutLabels {
  static const submit = 'Enter';
  static const submitMultiline = 'Ctrl+Enter';
  static const cancel = 'Escape';
  static const newLine = 'Shift+Enter';
  static const commandPalette = 'Ctrl+K';
  static const toggleSidebar = 'Ctrl+B';
  static const focusInput = 'Ctrl+L';
  static const clearChat = 'Ctrl+Shift+K';
  static const previousMessage = 'Up';
  static const nextMessage = 'Down';
  static const acceptSuggestion = 'Tab';
  static const toggleVim = 'Ctrl+Shift+V';
  static const undo = 'Ctrl+Z';
  static const redo = 'Ctrl+Shift+Z';
  static const copy = 'Ctrl+C';
  static const paste = 'Ctrl+V';
  static const selectAll = 'Ctrl+A';
  static const find = 'Ctrl+F';
}

/// Telemetry event names.
class TelemetryEvents {
  static const sessionStart = 'session.start';
  static const sessionEnd = 'session.end';
  static const messageSubmit = 'message.submit';
  static const messageReceive = 'message.receive';
  static const toolUse = 'tool.use';
  static const toolResult = 'tool.result';
  static const commandRun = 'command.run';
  static const permissionRequest = 'permission.request';
  static const permissionGrant = 'permission.grant';
  static const permissionDeny = 'permission.deny';
  static const modelSwitch = 'model.switch';
  static const compaction = 'compaction';
  static const memoryWrite = 'memory.write';
  static const mcpConnect = 'mcp.connect';
  static const mcpDisconnect = 'mcp.disconnect';
  static const agentSpawn = 'agent.spawn';
  static const agentComplete = 'agent.complete';
  static const error = 'error';
  static const apiLatency = 'api.latency';
}

/// Default memory file content.
const defaultNeomClawMd = '''
# Project Instructions

This file provides guidance to NeomClaw when working with this project.

## Overview

<!-- Describe the project briefly -->

## Build & Test Commands

<!-- Add common commands, e.g.:
- `dart run` — run the application
- `dart test` — run tests
- `dart analyze` — check for issues
-->

## Code Style

<!-- Describe coding conventions, naming, etc. -->

## Architecture

<!-- Describe the project structure and key patterns -->
''';

/// MIME types for common file extensions.
const mimeTypes = <String, String>{
  'dart': 'text/x-dart',
  'ts': 'text/typescript',
  'tsx': 'text/typescript',
  'js': 'text/javascript',
  'jsx': 'text/javascript',
  'py': 'text/x-python',
  'rb': 'text/x-ruby',
  'go': 'text/x-go',
  'rs': 'text/x-rust',
  'java': 'text/x-java',
  'kt': 'text/x-kotlin',
  'swift': 'text/x-swift',
  'c': 'text/x-c',
  'cpp': 'text/x-c++',
  'h': 'text/x-c',
  'hpp': 'text/x-c++',
  'cs': 'text/x-csharp',
  'html': 'text/html',
  'css': 'text/css',
  'scss': 'text/x-scss',
  'json': 'application/json',
  'yaml': 'text/yaml',
  'yml': 'text/yaml',
  'xml': 'text/xml',
  'md': 'text/markdown',
  'txt': 'text/plain',
  'sql': 'text/x-sql',
  'sh': 'text/x-shellscript',
  'bash': 'text/x-shellscript',
  'zsh': 'text/x-shellscript',
  'fish': 'text/x-shellscript',
  'ps1': 'text/x-powershell',
  'toml': 'text/x-toml',
  'ini': 'text/x-ini',
  'cfg': 'text/x-ini',
  'env': 'text/plain',
  'dockerfile': 'text/x-dockerfile',
  'makefile': 'text/x-makefile',
  'cmake': 'text/x-cmake',
  'gradle': 'text/x-gradle',
  'svg': 'image/svg+xml',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'pdf': 'application/pdf',
  'zip': 'application/zip',
  'tar': 'application/x-tar',
  'gz': 'application/gzip',
};

/// File extensions considered binary (non-text).
const binaryExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
  'ico',
  'tiff',
  'mp3',
  'wav',
  'ogg',
  'flac',
  'aac',
  'm4a',
  'mp4',
  'avi',
  'mov',
  'mkv',
  'webm',
  'pdf',
  'doc',
  'docx',
  'xls',
  'xlsx',
  'ppt',
  'pptx',
  'zip',
  'tar',
  'gz',
  'bz2',
  'xz',
  '7z',
  'rar',
  'exe',
  'dll',
  'so',
  'dylib',
  'o',
  'a',
  'class',
  'jar',
  'pyc',
  'pyo',
  'woff',
  'woff2',
  'ttf',
  'otf',
  'eot',
  'sqlite',
  'db',
};

/// Files/dirs to always ignore during searches.
const defaultIgnorePatterns = <String>[
  'node_modules',
  '.git',
  '.svn',
  '.hg',
  '__pycache__',
  '.pytest_cache',
  '.mypy_cache',
  '.tox',
  'venv',
  '.venv',
  'env',
  'dist',
  'build',
  'out',
  'target',
  '.next',
  '.nuxt',
  '.cache',
  '.parcel-cache',
  'coverage',
  '.nyc_output',
  '.dart_tool',
  '.flutter-plugins',
  '.flutter-plugins-dependencies',
  '.packages',
  '.pub-cache',
  'ios/Pods',
  'android/.gradle',
  '.idea',
  '.vscode',
  '*.min.js',
  '*.min.css',
  '*.map',
  '*.lock',
  'package-lock.json',
  'yarn.lock',
  'pnpm-lock.yaml',
  'pubspec.lock',
  'Cargo.lock',
  'Gemfile.lock',
  'poetry.lock',
];
