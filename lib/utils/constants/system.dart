// System prompt constants — ported from NeomClaw src/constants/system.ts.
// Centralises app metadata, file-system paths, numeric limits,
// timeouts, network config, platform support, and file-pattern lists.

import 'package:flutter_claw/core/platform/claw_io.dart' show Platform;

// ---------------------------------------------------------------------------
// System prompt prefixes (preserved from original stub)
// ---------------------------------------------------------------------------

const String defaultSystemPrefix =
    "You are NeomClaw, Anthropic's official CLI for Claude.";

const String agentSdkNeomClawPresetPrefix =
    "You are NeomClaw, Anthropic's official CLI for Claude.";

const String agentSdkPrefix =
    "You are a NeomClaw agent, built on Anthropic's NeomClaw Agent SDK.";

const String productUrl = 'https://neomclaw.com/neom-claw';
const String neomClawAiBaseUrl = 'https://neomclaw.ai';

// ---------------------------------------------------------------------------
// SystemConstants
// ---------------------------------------------------------------------------

class SystemConstants {
  SystemConstants._();

  // ---- App info -----------------------------------------------------------
  static const String appName = 'Neom Claw';
  static const String appId = 'neom_claw';
  static const String appVersion = '0.1.0';
  static const String appBuildNumber = '1';
  static const String appDescription =
      'AI-powered coding assistant — Flutter port of NeomClaw';
  static const String productUrl = 'https://neomclaw.com/neom-claw';
  static const String apiBaseUrl = 'https://api.anthropic.com';
  static const String docsUrl = 'https://docs.anthropic.com';
  static const String feedbackUrl =
      'https://github.com/anthropics/neom-claw/issues';
  static const String privacyUrl = 'https://www.anthropic.com/privacy';
  static const String termsUrl = 'https://www.anthropic.com/terms';

  // ---- File paths (relative to user home) ---------------------------------
  static const String configDirName = '.neomclaw';
  static String get configDir =>
      '${Platform.environment['HOME'] ?? '/tmp'}/$configDirName';
  static String get memoryFile => '$configDir/NEOMCLAW.md';
  static String get projectMemoryFile => '.neomclaw/NEOMCLAW.md';
  static String get sessionDir => '$configDir/sessions';
  static String get logDir => '$configDir/logs';
  static String get cacheDir => '$configDir/cache';
  static String get tempDir => '$configDir/tmp';
  static String get credentialsFile => '$configDir/credentials.json';
  static String get settingsFile => '$configDir/settings.json';
  static String get mcpConfigFile => '$configDir/mcp.json';
  static String get todoFile => '$configDir/todos.json';

  // ---- Numeric limits -----------------------------------------------------
  static const int maxFileSize = 10 * 1024 * 1024; // 10 MB
  static const int maxOutputLength = 30000; // characters
  static const int maxSearchResults = 500;
  static const int maxHistoryEntries = 200;
  static const int maxConcurrentAgents = 5;
  static const int maxMcpServers = 20;
  static const int maxRetries = 3;
  static const int maxConversationTurns = 200;
  static const int maxToolOutputLength = 100000; // characters
  static const int maxContextTokens = 200000;
  static const int maxInputTokens = 150000;
  static const int maxFileReadLines = 2000;
  static const int maxDiffLines = 5000;
  static const int maxGlobResults = 1000;
  static const int maxGrepResults = 500;
  static const int compactionThreshold = 95; // percent of context window

  // ---- Process timeouts (milliseconds) ------------------------------------
  static const int defaultCommandTimeout = 120000; // 2 minutes
  static const int longCommandTimeout = 600000; // 10 minutes
  static const int shortCommandTimeout = 30000; // 30 seconds
  static const int toolExecutionTimeout = 120000; // 2 minutes
  static const int mcpConnectionTimeout = 30000; // 30 seconds
  static const int mcpRequestTimeout = 60000; // 60 seconds
  static const int apiRequestTimeout = 300000; // 5 minutes
  static const int healthCheckTimeout = 10000; // 10 seconds
  static const int compactionTimeout = 120000; // 2 minutes
  static const int hookTimeout = 60000; // 60 seconds

  // ---- Network configuration ----------------------------------------------
  static const int maxConcurrentRequests = 5;
  static const int retryBaseDelay = 1000; // ms
  static const int retryMaxDelay = 30000; // ms
  static const double retryBackoffMultiplier = 2.0;
  static const int connectionPoolSize = 10;
  static const int keepAliveInterval = 30000; // ms
  static const String defaultApiVersion = '2023-06-01';
  static const List<String> supportedApiVersions = [
    '2023-06-01',
    '2023-01-01',
  ];

  // ---- Platform support ---------------------------------------------------
  static const List<String> supportedPlatforms = [
    'macos',
    'linux',
    'windows',
    'android',
    'ios',
  ];

  static const List<String> cliPlatforms = [
    'macos',
    'linux',
    'windows',
  ];

  static const List<String> mobilePlatforms = [
    'android',
    'ios',
  ];

  // ---- File patterns: directories to ignore (search / glob) ---------------
  static const List<String> ignoredDirs = [
    '.git',
    '.svn',
    '.hg',
    'node_modules',
    '__pycache__',
    '.next',
    '.nuxt',
    'dist',
    'build',
    'out',
    '.gradle',
    '.idea',
    '.vscode',
    '.dart_tool',
    '.pub-cache',
    'coverage',
    '.cache',
    'vendor',
    '.terraform',
    'target',
    'Pods',
  ];

  // ---- File patterns: files to ignore -------------------------------------
  static const List<String> ignoredFiles = [
    '.DS_Store',
    'Thumbs.db',
    '*.pyc',
    '*.pyo',
    '*.class',
    '*.o',
    '*.obj',
    '*.dll',
    '*.exe',
    '*.so',
    '*.dylib',
    'package-lock.json',
    'yarn.lock',
    'pnpm-lock.yaml',
    'pubspec.lock',
    'Podfile.lock',
  ];

  // ---- File patterns: binary extensions -----------------------------------
  static const List<String> binaryExtensions = [
    '.png',
    '.jpg',
    '.jpeg',
    '.gif',
    '.bmp',
    '.ico',
    '.webp',
    '.svg',
    '.pdf',
    '.zip',
    '.tar',
    '.gz',
    '.bz2',
    '.7z',
    '.rar',
    '.mp3',
    '.mp4',
    '.avi',
    '.mov',
    '.wav',
    '.flac',
    '.ttf',
    '.otf',
    '.woff',
    '.woff2',
    '.eot',
    '.exe',
    '.dll',
    '.so',
    '.dylib',
    '.o',
    '.obj',
    '.class',
    '.pyc',
    '.db',
    '.sqlite',
  ];

  // ---- File patterns: text extensions -------------------------------------
  static const List<String> textExtensions = [
    '.dart',
    '.ts',
    '.tsx',
    '.js',
    '.jsx',
    '.py',
    '.rb',
    '.java',
    '.kt',
    '.swift',
    '.go',
    '.rs',
    '.c',
    '.cpp',
    '.h',
    '.hpp',
    '.cs',
    '.php',
    '.lua',
    '.sh',
    '.bash',
    '.zsh',
    '.fish',
    '.ps1',
    '.bat',
    '.cmd',
    '.sql',
    '.html',
    '.css',
    '.scss',
    '.less',
    '.json',
    '.yaml',
    '.yml',
    '.toml',
    '.xml',
    '.md',
    '.txt',
    '.csv',
    '.log',
    '.env',
    '.ini',
    '.cfg',
    '.conf',
    '.dockerfile',
    '.makefile',
    '.gradle',
    '.graphql',
    '.proto',
  ];

  // ---- Config file names --------------------------------------------------
  static const List<String> configFileNames = [
    'NEOMCLAW.md',
    '.neomclaw/settings.json',
    '.neomclaw/mcp.json',
    '.neomclawignore',
    'package.json',
    'pubspec.yaml',
    'pyproject.toml',
    'Cargo.toml',
    'go.mod',
    'Gemfile',
    'Makefile',
    'Dockerfile',
    'docker-compose.yml',
    '.gitignore',
    '.editorconfig',
    'tsconfig.json',
    'analysis_options.yaml',
  ];
}
