// Full entrypoint definitions — ported from Neomage src/entrypoints/.
// Covers all entry modes: CLI, SDK, MCP server, headless, embedded, piped, remote.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:neomage/domain/models/message.dart';
import 'package:neomage/domain/models/permissions.dart';
import 'package:neomage/domain/models/tool_definition.dart';

// ---------------------------------------------------------------------------
// Entry mode enumeration
// ---------------------------------------------------------------------------

/// All supported entry modes for the application.
enum EntryMode {
  /// Interactive terminal UI (default).
  interactive,

  /// Non-interactive CLI invocation with a single prompt.
  cli,

  /// Programmatic SDK usage from another Dart application.
  sdk,

  /// Run as an MCP (Model Context Protocol) server.
  mcpServer,

  /// Headless mode — no UI, reads from stdin/file, writes to stdout/file.
  headless,

  /// Embedded inside another application (e.g., IDE panel).
  embedded,

  /// Remote session accessible over network.
  remote,

  /// Piped mode — stdin to stdout pipeline processing.
  piped;

  /// Parse an entry mode from a string identifier.
  static EntryMode fromString(String s) => switch (s.toLowerCase()) {
    'interactive' => interactive,
    'cli' => cli,
    'sdk' => sdk,
    'mcp' || 'mcp-server' || 'mcpserver' => mcpServer,
    'headless' => headless,
    'embedded' => embedded,
    'remote' => remote,
    'piped' || 'pipe' => piped,
    _ => throw ArgumentError('Unknown entry mode: $s'),
  };
}

// ---------------------------------------------------------------------------
// CLI Entrypoint
// ---------------------------------------------------------------------------

/// Parsed CLI flag definition.
class CliFlagDef {
  final String long;
  final String? short;
  final String description;
  final bool takesValue;
  final String? defaultValue;
  final bool isHidden;

  const CliFlagDef({
    required this.long,
    this.short,
    required this.description,
    this.takesValue = false,
    this.defaultValue,
    this.isHidden = false,
  });
}

/// Complete CLI configuration produced by parsing command-line arguments.
class CliConfig {
  /// The subcommand, if any (e.g., "mcp", "listen").
  final String? command;

  /// Positional arguments (the prompt text, file paths, etc.).
  final List<String> positionalArgs;

  /// Raw flag values keyed by long name.
  final Map<String, String> flags;

  /// Named options keyed by long name.
  final Map<String, String> options;

  /// Enable verbose logging output.
  final bool verbose;

  /// Suppress non-essential output.
  final bool quiet;

  /// Emit output as JSON instead of human-readable text.
  final bool jsonOutput;

  /// Model identifier override.
  final String? model;

  /// API key override (prefer env var ANTHROPIC_API_KEY).
  final String? apiKey;

  /// Maximum response tokens.
  final int? maxTokens;

  /// System prompt override or path to file.
  final String? systemPrompt;

  /// Comma-separated list of allowed tool names.
  final List<String> allowedTools;

  /// Permission mode override.
  final PermissionMode? permissionMode;

  /// Working directory override.
  final String? workDir;

  /// Session identifier for resume.
  final String? sessionId;

  /// Whether to continue the most recent session.
  final bool continueSession;

  /// Print the system prompt and exit (debug).
  final bool printOnly;

  /// Skip all permission checks (dangerous).
  final bool dangerouslySkipPermissions;

  /// MCP server configurations to connect to.
  final List<String> mcpServers;

  /// Run in listen mode (accept connections).
  final bool listen;

  /// Port for listen mode.
  final int? listenPort;

  /// Output format.
  final String? outputFormat;

  const CliConfig({
    this.command,
    this.positionalArgs = const [],
    this.flags = const {},
    this.options = const {},
    this.verbose = false,
    this.quiet = false,
    this.jsonOutput = false,
    this.model,
    this.apiKey,
    this.maxTokens,
    this.systemPrompt,
    this.allowedTools = const [],
    this.permissionMode,
    this.workDir,
    this.sessionId,
    this.continueSession = false,
    this.printOnly = false,
    this.dangerouslySkipPermissions = false,
    this.mcpServers = const [],
    this.listen = false,
    this.listenPort,
    this.outputFormat,
  });

  /// Merge with another config, preferring non-null values from [other].
  CliConfig merge(CliConfig other) => CliConfig(
    command: other.command ?? command,
    positionalArgs: other.positionalArgs.isNotEmpty
        ? other.positionalArgs
        : positionalArgs,
    flags: {...flags, ...other.flags},
    options: {...options, ...other.options},
    verbose: other.verbose || verbose,
    quiet: other.quiet || quiet,
    jsonOutput: other.jsonOutput || jsonOutput,
    model: other.model ?? model,
    apiKey: other.apiKey ?? apiKey,
    maxTokens: other.maxTokens ?? maxTokens,
    systemPrompt: other.systemPrompt ?? systemPrompt,
    allowedTools: other.allowedTools.isNotEmpty
        ? other.allowedTools
        : allowedTools,
    permissionMode: other.permissionMode ?? permissionMode,
    workDir: other.workDir ?? workDir,
    sessionId: other.sessionId ?? sessionId,
    continueSession: other.continueSession || continueSession,
    printOnly: other.printOnly || printOnly,
    dangerouslySkipPermissions:
        other.dangerouslySkipPermissions || dangerouslySkipPermissions,
    mcpServers: other.mcpServers.isNotEmpty ? other.mcpServers : mcpServers,
    listen: other.listen || listen,
    listenPort: other.listenPort ?? listenPort,
    outputFormat: other.outputFormat ?? outputFormat,
  );
}

/// All supported CLI flag definitions.
class CliFlags {
  static const List<CliFlagDef> all = [
    CliFlagDef(
      long: 'model',
      short: 'm',
      description: 'Model to use (e.g., claude-sonnet-4-20250514)',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'api-key',
      description: 'Anthropic API key (overrides ANTHROPIC_API_KEY env var)',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'max-tokens',
      description: 'Maximum tokens in response',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'system-prompt',
      short: 's',
      description: 'System prompt text or path to file containing it',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'permission-mode',
      short: 'p',
      description:
          'Permission mode: default, accept-edits, bypass-permissions, plan',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'allowed-tools',
      description: 'Comma-separated list of allowed tool names',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'work-dir',
      short: 'w',
      description: 'Working directory (defaults to cwd)',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'session',
      description: 'Resume a specific session by ID',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'continue',
      short: 'c',
      description: 'Continue the most recent session',
    ),
    CliFlagDef(long: 'json', description: 'Output in JSON format'),
    CliFlagDef(
      long: 'verbose',
      short: 'v',
      description: 'Enable verbose logging',
    ),
    CliFlagDef(
      long: 'quiet',
      short: 'q',
      description: 'Suppress non-essential output',
    ),
    CliFlagDef(long: 'print', description: 'Print the system prompt and exit'),
    CliFlagDef(
      long: 'dangerous-skip-permissions',
      description: 'Skip all permission checks (use with caution)',
      isHidden: true,
    ),
    CliFlagDef(
      long: 'version',
      short: 'V',
      description: 'Print version information and exit',
    ),
    CliFlagDef(long: 'help', short: 'h', description: 'Show this help message'),
    CliFlagDef(
      long: 'mcp',
      description: 'MCP server config (name:command format), repeatable',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'listen',
      description: 'Start in listen mode, accepting connections on a port',
    ),
    CliFlagDef(
      long: 'listen-port',
      description: 'Port for listen mode (default: 0 for auto)',
      takesValue: true,
    ),
    CliFlagDef(
      long: 'output-format',
      description: 'Output format: text, json, markdown (default: text)',
      takesValue: true,
    ),
  ];

  /// Lookup a flag by long or short name.
  static CliFlagDef? lookup(String name) {
    final normalized = name.replaceFirst(RegExp(r'^-{1,2}'), '');
    for (final flag in all) {
      if (flag.long == normalized || flag.short == normalized) {
        return flag;
      }
    }
    return null;
  }
}

/// CLI entrypoint — parses arguments and produces a [CliConfig].
class CliEntrypoint {
  const CliEntrypoint();

  /// Parse command-line arguments into a [CliConfig].
  CliConfig parse(List<String> args) {
    String? command;
    final positional = <String>[];
    final flags = <String, String>{};
    final options = <String, String>{};
    bool verbose = false;
    bool quiet = false;
    bool jsonOutput = false;
    String? model;
    String? apiKey;
    int? maxTokens;
    String? systemPrompt;
    List<String> allowedTools = [];
    PermissionMode? permissionMode;
    String? workDir;
    String? sessionId;
    bool continueSession = false;
    bool printOnly = false;
    bool dangerouslySkipPermissions = false;
    final mcpServers = <String>[];
    bool listen = false;
    int? listenPort;
    String? outputFormat;

    int i = 0;
    while (i < args.length) {
      final arg = args[i];

      if (arg == '--') {
        // Everything after -- is positional.
        positional.addAll(args.sublist(i + 1));
        break;
      }

      if (arg.startsWith('-')) {
        final flagDef = CliFlags.lookup(arg);
        if (flagDef == null) {
          flags[arg.replaceFirst(RegExp(r'^-{1,2}'), '')] = 'true';
          i++;
          continue;
        }

        String? value;
        if (flagDef.takesValue) {
          if (i + 1 >= args.length) {
            throw ArgumentError('Flag $arg requires a value');
          }
          value = args[++i];
        }

        switch (flagDef.long) {
          case 'model':
            model = value;
          case 'api-key':
            apiKey = value;
          case 'max-tokens':
            maxTokens = int.tryParse(value ?? '');
          case 'system-prompt':
            systemPrompt = value;
          case 'permission-mode':
            permissionMode = _parsePermissionMode(value!);
          case 'allowed-tools':
            allowedTools = value!.split(',').map((s) => s.trim()).toList();
          case 'work-dir':
            workDir = value;
          case 'session':
            sessionId = value;
          case 'continue':
            continueSession = true;
          case 'json':
            jsonOutput = true;
          case 'verbose':
            verbose = true;
          case 'quiet':
            quiet = true;
          case 'print':
            printOnly = true;
          case 'dangerous-skip-permissions':
            dangerouslySkipPermissions = true;
          case 'mcp':
            mcpServers.add(value!);
          case 'listen':
            listen = true;
          case 'listen-port':
            listenPort = int.tryParse(value ?? '');
          case 'output-format':
            outputFormat = value;
          case 'version':
            flags['version'] = 'true';
          case 'help':
            flags['help'] = 'true';
          default:
            if (value != null) {
              options[flagDef.long] = value;
            } else {
              flags[flagDef.long] = 'true';
            }
        }
      } else {
        // First non-flag is treated as a subcommand if no command yet.
        if (command == null && _isSubcommand(arg)) {
          command = arg;
        } else {
          positional.add(arg);
        }
      }
      i++;
    }

    return CliConfig(
      command: command,
      positionalArgs: positional,
      flags: flags,
      options: options,
      verbose: verbose,
      quiet: quiet,
      jsonOutput: jsonOutput,
      model: model,
      apiKey: apiKey,
      maxTokens: maxTokens,
      systemPrompt: systemPrompt,
      allowedTools: allowedTools,
      permissionMode: permissionMode,
      workDir: workDir,
      sessionId: sessionId,
      continueSession: continueSession,
      printOnly: printOnly,
      dangerouslySkipPermissions: dangerouslySkipPermissions,
      mcpServers: mcpServers,
      listen: listen,
      listenPort: listenPort,
      outputFormat: outputFormat,
    );
  }

  /// Validate a parsed config and return a list of errors (empty if valid).
  List<String> validateConfig(CliConfig config) {
    final errors = <String>[];

    if (config.maxTokens != null && config.maxTokens! <= 0) {
      errors.add('--max-tokens must be a positive integer');
    }

    if (config.verbose && config.quiet) {
      errors.add('Cannot use both --verbose and --quiet');
    }

    if (config.sessionId != null && config.continueSession) {
      errors.add('Cannot use both --session and --continue');
    }

    if (config.listenPort != null &&
        (config.listenPort! < 0 || config.listenPort! > 65535)) {
      errors.add('--listen-port must be between 0 and 65535');
    }

    if (config.outputFormat != null &&
        !const ['text', 'json', 'markdown'].contains(config.outputFormat)) {
      errors.add('--output-format must be one of: text, json, markdown');
    }

    if (config.permissionMode == PermissionMode.bypassPermissions &&
        !config.dangerouslySkipPermissions) {
      errors.add(
        'bypass-permissions mode requires --dangerous-skip-permissions flag',
      );
    }

    return errors;
  }

  /// Generate formatted help text for all CLI flags.
  String helpText() {
    final buffer = StringBuffer();
    buffer.writeln('Usage: neomage [options] [prompt]');
    buffer.writeln();
    buffer.writeln('Options:');

    final visibleFlags = CliFlags.all.where((f) => !f.isHidden).toList();

    // Calculate max flag width for alignment.
    int maxWidth = 0;
    for (final flag in visibleFlags) {
      int width = flag.long.length + 4; // --flag
      if (flag.short != null) width += 4; // -f,
      if (flag.takesValue) width += 8; // <value>
      if (width > maxWidth) maxWidth = width;
    }

    for (final flag in visibleFlags) {
      final shortPart = flag.short != null ? '-${flag.short}, ' : '    ';
      final longPart = '--${flag.long}';
      final valuePart = flag.takesValue ? ' <value>' : '';
      final flagStr = '$shortPart$longPart$valuePart';
      final padding = ' ' * (maxWidth - flagStr.length + 4);
      buffer.writeln('  $flagStr$padding${flag.description}');
    }

    buffer.writeln();
    buffer.writeln('Subcommands:');
    buffer.writeln('  mcp         Start as an MCP server');
    buffer.writeln('  listen      Start in listen mode');

    return buffer.toString();
  }

  /// Generate version text.
  String versionText() {
    return 'neomage 0.1.0';
  }

  static PermissionMode _parsePermissionMode(String value) =>
      switch (value.toLowerCase()) {
        'default' => PermissionMode.defaultMode,
        'accept-edits' || 'acceptedits' => PermissionMode.acceptEdits,
        'bypass-permissions' ||
        'bypasspermissions' => PermissionMode.bypassPermissions,
        'plan' => PermissionMode.plan,
        'dont-ask' || 'dontask' => PermissionMode.dontAsk,
        _ => throw ArgumentError('Unknown permission mode: $value'),
      };

  static bool _isSubcommand(String arg) =>
      const {'mcp', 'listen'}.contains(arg.toLowerCase());
}

// ---------------------------------------------------------------------------
// SDK Entrypoint
// ---------------------------------------------------------------------------

/// Callback type for handling assistant messages.
typedef OnMessageCallback = void Function(Message message);

/// Callback type for handling tool use events.
typedef OnToolUseCallback =
    void Function(String toolName, Map<String, dynamic> input);

/// Callback type for handling errors.
typedef OnErrorCallback = void Function(Object error, StackTrace? stackTrace);

/// Callback type for permission handling in SDK mode.
typedef PermissionHandler =
    Future<bool> Function(
      String toolName,
      Map<String, dynamic> input,
      String description,
    );

/// Configuration for SDK entrypoint.
class SdkConfig {
  /// Anthropic API key.
  final String apiKey;

  /// Model identifier.
  final String model;

  /// System prompt.
  final String? systemPrompt;

  /// Tool definitions to register.
  final List<ToolDefinition> tools;

  /// Maximum conversation turns before stopping.
  final int? maxTurns;

  /// Custom permission handler.
  final PermissionHandler? permissionHandler;

  /// Callback for assistant messages.
  final OnMessageCallback? onMessage;

  /// Callback for tool use events.
  final OnToolUseCallback? onToolUse;

  /// Callback for errors.
  final OnErrorCallback? onError;

  /// Working directory for file operations.
  final String? workDir;

  /// Additional MCP server configs.
  final List<String> mcpServers;

  /// Whether to include system tools (bash, file ops, etc.).
  final bool includeSystemTools;

  const SdkConfig({
    required this.apiKey,
    required this.model,
    this.systemPrompt,
    this.tools = const [],
    this.maxTurns,
    this.permissionHandler,
    this.onMessage,
    this.onToolUse,
    this.onError,
    this.workDir,
    this.mcpServers = const [],
    this.includeSystemTools = true,
  });
}

/// An active SDK session — wraps an ongoing conversation.
class SdkSession {
  final SdkConfig _config;
  final List<Message> _history = [];
  final _messageController = StreamController<Message>.broadcast();
  bool _isAborted = false;
  bool _isDisposed = false;

  SdkSession._(this._config);

  /// Stream of messages as the conversation progresses.
  Stream<Message> get messages => _messageController.stream;

  /// Whether the session has been aborted.
  bool get isAborted => _isAborted;

  /// Whether the session has been disposed.
  bool get isDisposed => _isDisposed;

  /// Send a user message and receive assistant response(s).
  ///
  /// Returns the final assistant message. Tool use and intermediate
  /// messages are delivered via the [messages] stream.
  Future<Message> sendMessage(String text) async {
    _ensureActive();
    final userMsg = Message.user(text);
    _history.add(userMsg);
    _messageController.add(userMsg);

    // In a real implementation this would call the API in a loop,
    // processing tool use until the assistant produces a final response.
    // Placeholder: return an empty assistant message.
    final assistantMsg = Message.assistant('');
    _history.add(assistantMsg);
    _messageController.add(assistantMsg);
    _config.onMessage?.call(assistantMsg);
    return assistantMsg;
  }

  /// Get the full conversation history.
  List<Message> getHistory() => List.unmodifiable(_history);

  /// Abort the current request.
  void abort() {
    _isAborted = true;
  }

  /// Dispose the session, releasing all resources.
  void dispose() {
    _isDisposed = true;
    _isAborted = true;
    _messageController.close();
  }

  void _ensureActive() {
    if (_isDisposed) {
      throw StateError('SdkSession has been disposed');
    }
    if (_isAborted) {
      throw StateError('SdkSession has been aborted');
    }
  }
}

/// SDK entrypoint — programmatic access from Dart applications.
class SdkEntrypoint {
  const SdkEntrypoint();

  /// Create a new SDK session with the given configuration.
  SdkSession create(SdkConfig config) {
    // Validate required fields.
    if (config.apiKey.isEmpty) {
      throw ArgumentError('apiKey must not be empty');
    }
    if (config.model.isEmpty) {
      throw ArgumentError('model must not be empty');
    }
    return SdkSession._(config);
  }
}

// ---------------------------------------------------------------------------
// MCP Server Entrypoint
// ---------------------------------------------------------------------------

/// MCP server capability declarations.
class McpCapabilities {
  final bool supportsTools;
  final bool supportsResources;
  final bool supportsPrompts;
  final bool supportsLogging;
  final bool supportsSampling;

  const McpCapabilities({
    this.supportsTools = true,
    this.supportsResources = false,
    this.supportsPrompts = false,
    this.supportsLogging = false,
    this.supportsSampling = false,
  });

  Map<String, dynamic> toJson() => {
    if (supportsTools) 'tools': {'listChanged': true},
    if (supportsResources) 'resources': {'subscribe': true},
    if (supportsPrompts) 'prompts': {'listChanged': true},
    if (supportsLogging) 'logging': {},
    if (supportsSampling) 'sampling': {},
  };
}

/// MCP server-side tool definition (includes handler).
class McpServerTool {
  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic> input)
  handler;

  const McpServerTool({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
  });
}

/// MCP resource definition.
class McpServerResource {
  final String uri;
  final String name;
  final String? description;
  final String? mimeType;
  final Future<String> Function() reader;

  const McpServerResource({
    required this.uri,
    required this.name,
    this.description,
    this.mimeType,
    required this.reader,
  });
}

/// MCP prompt definition.
class McpServerPrompt {
  final String name;
  final String? description;
  final List<McpPromptArgument> arguments;
  final Future<String> Function(Map<String, String> args) generator;

  const McpServerPrompt({
    required this.name,
    this.description,
    this.arguments = const [],
    required this.generator,
  });
}

/// MCP prompt argument.
class McpPromptArgument {
  final String name;
  final String? description;
  final bool required;

  const McpPromptArgument({
    required this.name,
    this.description,
    this.required = false,
  });
}

/// MCP transport types for server mode.
enum McpServerTransport { stdio, sse, streamableHttp }

/// Configuration for the MCP server entrypoint.
class McpEntrypointConfig {
  final String name;
  final String version;
  final McpCapabilities capabilities;
  final List<McpServerTool> tools;
  final List<McpServerResource> resources;
  final List<McpServerPrompt> prompts;

  const McpEntrypointConfig({
    required this.name,
    required this.version,
    this.capabilities = const McpCapabilities(),
    this.tools = const [],
    this.resources = const [],
    this.prompts = const [],
  });
}

/// MCP server entrypoint — runs Neomage as an MCP-compatible server.
class McpServerEntrypoint {
  bool _running = false;

  /// Whether the server is currently running.
  bool get isRunning => _running;

  /// Start serving MCP requests using the given transport.
  Future<void> serve(
    McpEntrypointConfig config,
    McpServerTransport transport,
  ) async {
    _running = true;
    // In a real implementation this sets up the transport (stdio pipes,
    // HTTP server, etc.) and enters the request loop.
  }

  /// Handle a single MCP JSON-RPC request and produce a response.
  Future<Map<String, dynamic>> handleRequest(
    Map<String, dynamic> request,
    McpEntrypointConfig config,
  ) async {
    final method = request['method'] as String?;
    final id = request['id'];
    final params = request['params'] as Map<String, dynamic>? ?? {};

    return switch (method) {
      'initialize' => _handleInitialize(id, params, config),
      'tools/list' => _handleToolsList(id, config),
      'tools/call' => await _handleToolsCall(id, params, config),
      'resources/list' => _handleResourcesList(id, config),
      'resources/read' => await _handleResourcesRead(id, params, config),
      'prompts/list' => _handlePromptsList(id, config),
      'prompts/get' => await _handlePromptsGet(id, params, config),
      'ping' => {'jsonrpc': '2.0', 'id': id, 'result': {}},
      _ => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32601, 'message': 'Method not found: $method'},
      },
    };
  }

  /// Stop the server.
  void shutdown() {
    _running = false;
  }

  Map<String, dynamic> _handleInitialize(
    dynamic id,
    Map<String, dynamic> params,
    McpEntrypointConfig config,
  ) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': {
      'protocolVersion': '2024-11-05',
      'capabilities': config.capabilities.toJson(),
      'serverInfo': {'name': config.name, 'version': config.version},
    },
  };

  Map<String, dynamic> _handleToolsList(
    dynamic id,
    McpEntrypointConfig config,
  ) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': {
      'tools': config.tools
          .map(
            (t) => {
              'name': t.name,
              'description': t.description,
              'inputSchema': t.inputSchema,
            },
          )
          .toList(),
    },
  };

  Future<Map<String, dynamic>> _handleToolsCall(
    dynamic id,
    Map<String, dynamic> params,
    McpEntrypointConfig config,
  ) async {
    final toolName = params['name'] as String?;
    final input = params['arguments'] as Map<String, dynamic>? ?? {};
    final tool = config.tools.where((t) => t.name == toolName).firstOrNull;

    if (tool == null) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32602, 'message': 'Unknown tool: $toolName'},
      };
    }

    try {
      final result = await tool.handler(input);
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': result.toString()},
          ],
        },
      };
    } catch (e) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [
            {'type': 'text', 'text': 'Error: $e'},
          ],
          'isError': true,
        },
      };
    }
  }

  Map<String, dynamic> _handleResourcesList(
    dynamic id,
    McpEntrypointConfig config,
  ) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': {
      'resources': config.resources
          .map(
            (r) => {
              'uri': r.uri,
              'name': r.name,
              if (r.description != null) 'description': r.description,
              if (r.mimeType != null) 'mimeType': r.mimeType,
            },
          )
          .toList(),
    },
  };

  Future<Map<String, dynamic>> _handleResourcesRead(
    dynamic id,
    Map<String, dynamic> params,
    McpEntrypointConfig config,
  ) async {
    final uri = params['uri'] as String?;
    final resource = config.resources.where((r) => r.uri == uri).firstOrNull;

    if (resource == null) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32602, 'message': 'Unknown resource: $uri'},
      };
    }

    final content = await resource.reader();
    return {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'contents': [
          {
            'uri': uri,
            'text': content,
            if (resource.mimeType != null) 'mimeType': resource.mimeType,
          },
        ],
      },
    };
  }

  Map<String, dynamic> _handlePromptsList(
    dynamic id,
    McpEntrypointConfig config,
  ) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': {
      'prompts': config.prompts
          .map(
            (p) => {
              'name': p.name,
              if (p.description != null) 'description': p.description,
              'arguments': p.arguments
                  .map(
                    (a) => {
                      'name': a.name,
                      if (a.description != null) 'description': a.description,
                      'required': a.required,
                    },
                  )
                  .toList(),
            },
          )
          .toList(),
    },
  };

  Future<Map<String, dynamic>> _handlePromptsGet(
    dynamic id,
    Map<String, dynamic> params,
    McpEntrypointConfig config,
  ) async {
    final promptName = params['name'] as String?;
    final promptArgs =
        (params['arguments'] as Map<String, dynamic>?)
            ?.cast<String, String>() ??
        {};
    final prompt = config.prompts
        .where((p) => p.name == promptName)
        .firstOrNull;

    if (prompt == null) {
      return {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': -32602, 'message': 'Unknown prompt: $promptName'},
      };
    }

    final text = await prompt.generator(promptArgs);
    return {
      'jsonrpc': '2.0',
      'id': id,
      'result': {
        'messages': [
          {
            'role': 'user',
            'content': {'type': 'text', 'text': text},
          },
        ],
      },
    };
  }
}

// ---------------------------------------------------------------------------
// Headless Entrypoint
// ---------------------------------------------------------------------------

/// Input source for headless mode.
sealed class HeadlessInput {
  const HeadlessInput();
}

/// Read input from stdin.
class StdinInput extends HeadlessInput {
  const StdinInput();
}

/// Read input from a file.
class FileInput extends HeadlessInput {
  final String path;
  const FileInput(this.path);
}

/// Use a literal string as input.
class StringInput extends HeadlessInput {
  final String text;
  const StringInput(this.text);
}

/// Output destination for headless mode.
sealed class HeadlessOutput {
  const HeadlessOutput();
}

/// Write output to stdout.
class StdoutOutput extends HeadlessOutput {
  const StdoutOutput();
}

/// Write output to a file.
class FileOutput extends HeadlessOutput {
  final String path;
  const FileOutput(this.path);
}

/// Output format for headless mode.
enum HeadlessFormat { text, json, markdown }

/// Configuration for headless mode.
class HeadlessConfig {
  final HeadlessInput input;
  final HeadlessOutput output;
  final HeadlessFormat format;
  final String? model;
  final String? systemPrompt;
  final List<String> allowedTools;
  final int? maxTokens;

  const HeadlessConfig({
    required this.input,
    this.output = const StdoutOutput(),
    this.format = HeadlessFormat.text,
    this.model,
    this.systemPrompt,
    this.allowedTools = const [],
    this.maxTokens,
  });
}

/// Result of a headless run.
class HeadlessResult {
  final String output;
  final int inputTokens;
  final int outputTokens;
  final Duration duration;
  final bool success;
  final String? error;

  const HeadlessResult({
    required this.output,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.duration = Duration.zero,
    this.success = true,
    this.error,
  });
}

/// Headless entrypoint — run without interactive UI.
class HeadlessEntrypoint {
  const HeadlessEntrypoint();

  /// Run in headless mode with the given configuration.
  Future<HeadlessResult> run(HeadlessConfig config) async {
    final stopwatch = Stopwatch()..start();

    // Read input.
    final inputText = switch (config.input) {
      StdinInput() => await _readStdin(),
      FileInput(path: final p) => await File(p).readAsString(),
      StringInput(text: final t) => t,
    };

    if (inputText.isEmpty) {
      return const HeadlessResult(
        output: '',
        success: false,
        error: 'Empty input',
      );
    }

    // In a real implementation, this sends the input to the API
    // and collects the response.
    stopwatch.stop();

    return HeadlessResult(output: '', duration: stopwatch.elapsed);
  }

  Future<String> _readStdin() async {
    final buffer = StringBuffer();
    await for (final line in stdin.transform(const SystemEncoding().decoder)) {
      buffer.writeln(line);
    }
    return buffer.toString().trimRight();
  }
}

// ---------------------------------------------------------------------------
// Embedded Entrypoint
// ---------------------------------------------------------------------------

/// Communication channel between host app and embedded Neomage.
enum CommunicationChannel { methodChannel, messagePort, directCall }

/// Restrictions applied in embedded mode.
class EmbeddedRestrictions {
  /// Whether file system access is allowed.
  final bool allowFileSystem;

  /// Whether process spawning is allowed.
  final bool allowProcessSpawn;

  /// Whether network access is allowed.
  final bool allowNetwork;

  /// Maximum tokens per request.
  final int? maxTokensPerRequest;

  /// Allowed tool names (empty = all).
  final List<String> allowedTools;

  const EmbeddedRestrictions({
    this.allowFileSystem = false,
    this.allowProcessSpawn = false,
    this.allowNetwork = true,
    this.maxTokensPerRequest,
    this.allowedTools = const [],
  });
}

/// Configuration for embedded mode.
class EmbeddedConfig {
  /// Name of the parent application.
  final String parentApp;

  /// Communication channel to use.
  final CommunicationChannel communicationChannel;

  /// Restrictions for the embedded session.
  final EmbeddedRestrictions restrictions;

  /// API key (usually provided by parent app).
  final String? apiKey;

  /// Model override.
  final String? model;

  /// System prompt additions from the parent app.
  final String? systemPromptAddition;

  const EmbeddedConfig({
    required this.parentApp,
    this.communicationChannel = CommunicationChannel.directCall,
    this.restrictions = const EmbeddedRestrictions(),
    this.apiKey,
    this.model,
    this.systemPromptAddition,
  });
}

/// An active embedded session.
class EmbeddedSession {
  final EmbeddedConfig config;
  final _messageController = StreamController<Message>.broadcast();
  bool _isActive = true;

  EmbeddedSession._(this.config);

  /// Stream of messages from the session.
  Stream<Message> get messages => _messageController.stream;

  /// Whether the session is active.
  bool get isActive => _isActive;

  /// Send a message to the embedded session.
  Future<Message> sendMessage(String text) async {
    if (!_isActive) {
      throw StateError('Embedded session is not active');
    }
    final msg = Message.user(text);
    _messageController.add(msg);
    // Placeholder for actual API interaction.
    final response = Message.assistant('');
    _messageController.add(response);
    return response;
  }

  /// Detach and dispose the embedded session.
  void detach() {
    _isActive = false;
    _messageController.close();
  }
}

/// Embedded entrypoint — run inside another application.
class EmbeddedEntrypoint {
  const EmbeddedEntrypoint();

  /// Attach to a host application and create an embedded session.
  EmbeddedSession attach(EmbeddedConfig config) {
    return EmbeddedSession._(config);
  }
}

// ---------------------------------------------------------------------------
// Piped Entrypoint
// ---------------------------------------------------------------------------

/// Configuration for piped mode (stdin -> stdout pipeline).
class PipedConfig {
  /// Input stream (defaults to stdin).
  final Stream<List<int>>? inputStream;

  /// Output sink (defaults to stdout).
  final IOSink? outputSink;

  /// Output format.
  final HeadlessFormat format;

  /// Model override.
  final String? model;

  /// System prompt.
  final String? systemPrompt;

  /// Whether to process input line-by-line or as a single batch.
  final bool lineByLine;

  /// Delimiter for separating input chunks (if not line-by-line).
  final String? delimiter;

  const PipedConfig({
    this.inputStream,
    this.outputSink,
    this.format = HeadlessFormat.text,
    this.model,
    this.systemPrompt,
    this.lineByLine = false,
    this.delimiter,
  });
}

/// Piped entrypoint — process stdin to stdout as a pipeline.
class PipedEntrypoint {
  const PipedEntrypoint();

  /// Run the piped pipeline.
  Future<void> run(PipedConfig config) async {
    final input = config.inputStream ?? stdin;
    final output = config.outputSink ?? stdout;
    final encoding = const SystemEncoding();

    if (config.lineByLine) {
      await for (final chunk in input.transform(encoding.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          final result = await _processChunk(line, config);
          output.writeln(result);
        }
      }
    } else {
      final buffer = StringBuffer();
      await for (final chunk in input.transform(encoding.decoder)) {
        buffer.write(chunk);
      }
      final result = await _processChunk(buffer.toString(), config);
      output.writeln(result);
    }

    await output.flush();
  }

  Future<String> _processChunk(String input, PipedConfig config) async {
    // In a real implementation, send to API and return response.
    return '';
  }
}

// ---------------------------------------------------------------------------
// Entry Router
// ---------------------------------------------------------------------------

/// Routes to the correct entrypoint based on arguments and environment.
class EntryRouter {
  /// Detect the entry mode from command-line args and environment variables.
  static EntryMode detect(List<String> args, Map<String, String> env) {
    // Explicit mode flags take precedence.
    if (args.contains('--mode')) {
      final idx = args.indexOf('--mode');
      if (idx + 1 < args.length) {
        return EntryMode.fromString(args[idx + 1]);
      }
    }

    // Check for MCP server subcommand.
    if (args.isNotEmpty && args.first == 'mcp') {
      return EntryMode.mcpServer;
    }

    // Check for listen subcommand.
    if (args.contains('--listen') ||
        (args.isNotEmpty && args.first == 'listen')) {
      return EntryMode.remote;
    }

    // Check environment variables.
    if (env.containsKey('MAGE_SDK_MODE')) {
      return EntryMode.sdk;
    }
    if (env.containsKey('MAGE_EMBEDDED')) {
      return EntryMode.embedded;
    }

    // Check if stdin is a pipe (not a terminal).
    if (_stdinIsPiped()) {
      return EntryMode.piped;
    }

    // Check for non-interactive indicators.
    if (args.any((a) => a == '--json' || a == '--print')) {
      return EntryMode.headless;
    }

    // Positional prompt with --quiet or non-tty stdout => headless.
    if (args.isNotEmpty &&
        !args.first.startsWith('-') &&
        (args.contains('--quiet') || !_stdoutIsTty())) {
      return EntryMode.headless;
    }

    return EntryMode.interactive;
  }

  /// Route to the appropriate entrypoint and run.
  static Future<void> route(List<String> args, Map<String, String> env) async {
    final mode = detect(args, env);

    switch (mode) {
      case EntryMode.interactive:
        // Launch the Flutter/TUI interactive mode.
        break;
      case EntryMode.cli:
        final config = const CliEntrypoint().parse(args);
        final errors = const CliEntrypoint().validateConfig(config);
        if (errors.isNotEmpty) {
          for (final err in errors) {
            stderr.writeln('Error: $err');
          }
          exit(1);
        }
        // Execute CLI mode with the parsed config.
        break;
      case EntryMode.sdk:
        // SDK mode is invoked programmatically, not from the CLI.
        break;
      case EntryMode.mcpServer:
        // Start MCP server.
        break;
      case EntryMode.headless:
        // Run in headless mode.
        break;
      case EntryMode.embedded:
        // Embedded mode is invoked by the host app.
        break;
      case EntryMode.remote:
        // Start in listen/remote mode.
        break;
      case EntryMode.piped:
        await const PipedEntrypoint().run(const PipedConfig());
    }
  }

  static bool _stdinIsPiped() {
    try {
      return !stdin.hasTerminal;
    } catch (_) {
      return false;
    }
  }

  static bool _stdoutIsTty() {
    try {
      return stdout.hasTerminal;
    } catch (_) {
      return false;
    }
  }
}
