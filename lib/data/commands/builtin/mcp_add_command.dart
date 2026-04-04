// /mcp add command — adds MCP servers to the configuration.
// Faithful port of neom_claw/src/commands/mcp/addCommand.ts (280 TS LOC).
//
// Supports three transport types (stdio, sse, http), environment variables,
// custom headers, OAuth configuration (client-id, client-secret, callback-port),
// XAA (SEP-990) authentication, and scope-based configuration (local, user,
// project). Validates inputs, detects URL-like commands for stdio transport
// warnings, and writes the server configuration to the appropriate config file.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:path/path.dart' as p;

import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Configuration scope
// ============================================================================

/// Where MCP configuration is stored.
enum McpConfigScope {
  /// Local to the current directory (.neomclaw/mcp.json).
  local,

  /// User-level (~/.neomclaw/mcp.json).
  user,

  /// Project-level (.mcp.json in project root).
  project,
}

/// Parse a scope string into [McpConfigScope], defaulting to [local].
McpConfigScope ensureConfigScope(String? scope) {
  switch (scope?.toLowerCase()) {
    case 'user':
      return McpConfigScope.user;
    case 'project':
      return McpConfigScope.project;
    case 'local':
    default:
      return McpConfigScope.local;
  }
}

/// Human-readable description of the config file path for a scope.
String describeMcpConfigFilePath(McpConfigScope scope) {
  switch (scope) {
    case McpConfigScope.local:
      return '.neomclaw/mcp.json (local)';
    case McpConfigScope.user:
      return '~/.neomclaw/mcp.json (user)';
    case McpConfigScope.project:
      return '.mcp.json (project)';
  }
}

// ============================================================================
// Transport type
// ============================================================================

/// MCP transport protocol.
enum McpTransport { stdio, sse, http }

/// Parse a transport string, defaulting to [stdio].
McpTransport ensureTransport(String? transport) {
  switch (transport?.toLowerCase()) {
    case 'sse':
      return McpTransport.sse;
    case 'http':
      return McpTransport.http;
    case 'stdio':
    default:
      return McpTransport.stdio;
  }
}

// ============================================================================
// MCP server configuration models
// ============================================================================

/// Base configuration for an MCP server.
abstract class McpServerConfig {
  String get type;
  Map<String, dynamic> toJson();
}

/// Stdio-based MCP server configuration.
class StdioMcpServerConfig implements McpServerConfig {
  @override
  final String type = 'stdio';
  final String command;
  final List<String> args;
  final Map<String, String>? env;

  const StdioMcpServerConfig({
    required this.command,
    this.args = const [],
    this.env,
  });

  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{
      'type': type,
      'command': command,
      'args': args,
    };
    if (env != null && env!.isNotEmpty) result['env'] = env;
    return result;
  }
}

/// SSE-based MCP server configuration.
class SseMcpServerConfig implements McpServerConfig {
  @override
  final String type = 'sse';
  final String url;
  final Map<String, String>? headers;
  final Map<String, dynamic>? oauth;

  const SseMcpServerConfig({required this.url, this.headers, this.oauth});

  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'type': type, 'url': url};
    if (headers != null && headers!.isNotEmpty) result['headers'] = headers;
    if (oauth != null && oauth!.isNotEmpty) result['oauth'] = oauth;
    return result;
  }
}

/// HTTP-based MCP server configuration.
class HttpMcpServerConfig implements McpServerConfig {
  @override
  final String type = 'http';
  final String url;
  final Map<String, String>? headers;
  final Map<String, dynamic>? oauth;

  const HttpMcpServerConfig({required this.url, this.headers, this.oauth});

  @override
  Map<String, dynamic> toJson() {
    final result = <String, dynamic>{'type': type, 'url': url};
    if (headers != null && headers!.isNotEmpty) result['headers'] = headers;
    if (oauth != null && oauth!.isNotEmpty) result['oauth'] = oauth;
    return result;
  }
}

// ============================================================================
// Header parsing
// ============================================================================

/// Parse header strings of the form "Key: Value" into a map.
Map<String, String> parseHeaders(List<String> headerStrings) {
  final headers = <String, String>{};
  for (final h in headerStrings) {
    final colonIdx = h.indexOf(':');
    if (colonIdx == -1) continue;
    final key = h.substring(0, colonIdx).trim();
    final value = h.substring(colonIdx + 1).trim();
    if (key.isNotEmpty) {
      headers[key] = value;
    }
  }
  return headers;
}

// ============================================================================
// Environment variable parsing
// ============================================================================

/// Parse environment variable strings of the form "KEY=value" into a map.
Map<String, String> parseEnvVars(List<String>? envStrings) {
  if (envStrings == null || envStrings.isEmpty) return {};
  final env = <String, String>{};
  for (final e in envStrings) {
    final eqIdx = e.indexOf('=');
    if (eqIdx == -1) continue;
    final key = e.substring(0, eqIdx).trim();
    final value = e.substring(eqIdx + 1).trim();
    if (key.isNotEmpty) {
      env[key] = value;
    }
  }
  return env;
}

// ============================================================================
// OAuth configuration builder
// ============================================================================

/// Build an OAuth configuration map from the provided options.
Map<String, dynamic>? buildOAuthConfig({
  String? clientId,
  int? callbackPort,
  bool xaa = false,
}) {
  if (clientId == null && callbackPort == null && !xaa) return null;
  final oauth = <String, dynamic>{};
  if (clientId != null) oauth['clientId'] = clientId;
  if (callbackPort != null) oauth['callbackPort'] = callbackPort;
  if (xaa) oauth['xaa'] = true;
  return oauth;
}

// ============================================================================
// MCP config file I/O
// ============================================================================

/// Resolve the config file path for a given scope.
String _resolveConfigPath(McpConfigScope scope, String cwd) {
  switch (scope) {
    case McpConfigScope.local:
      return p.join(cwd, '.neomclaw', 'mcp.json');
    case McpConfigScope.user:
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          '';
      return p.join(home, '.neomclaw', 'mcp.json');
    case McpConfigScope.project:
      return p.join(cwd, '.mcp.json');
  }
}

/// Read existing MCP config from file, or return empty structure.
Future<Map<String, dynamic>> _readMcpConfig(String path) async {
  final file = File(path);
  if (await file.exists()) {
    try {
      final content = await file.readAsString();
      final parsed = jsonDecode(content);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {
      // Malformed — start fresh
    }
  }
  return <String, dynamic>{'mcpServers': <String, dynamic>{}};
}

/// Write MCP config to file, creating parent directories if needed.
Future<void> _writeMcpConfig(String path, Map<String, dynamic> config) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(config),
    flush: true,
  );
}

/// Add an MCP server configuration to the config file for the given scope.
Future<void> addMcpConfig(
  String name,
  McpServerConfig serverConfig,
  McpConfigScope scope,
  String cwd,
) async {
  final configPath = _resolveConfigPath(scope, cwd);
  final config = await _readMcpConfig(configPath);

  // Ensure mcpServers map exists.
  if (config['mcpServers'] is! Map) {
    config['mcpServers'] = <String, dynamic>{};
  }
  (config['mcpServers'] as Map<String, dynamic>)[name] = serverConfig.toJson();

  await _writeMcpConfig(configPath, config);
}

// ============================================================================
// XAA (SEP-990) support stubs
// ============================================================================

/// Check whether XAA is enabled via environment variable.
bool isXaaEnabled() {
  final env = Platform.environment['NEOMCLAW_ENABLE_XAA'];
  return env == '1' || env?.toLowerCase() == 'true';
}

/// Check whether XAA IdP settings are configured.
/// Returns true if settings.xaaIdp is present in user settings.
bool hasXaaIdpSettings() {
  // In a full implementation this would read from the settings store.
  // Stubbed to return false; the XAA setup command must be run first.
  return false;
}

// ============================================================================
// McpAddCommand — options model
// ============================================================================

/// Parsed options for the /mcp add command.
class McpAddOptions {
  final String name;
  final String commandOrUrl;
  final List<String> args;
  final String scope;
  final String? transport;
  final List<String>? envVars;
  final List<String>? headers;
  final String? clientId;
  final bool clientSecret;
  final int? callbackPort;
  final bool xaa;

  const McpAddOptions({
    required this.name,
    required this.commandOrUrl,
    this.args = const [],
    this.scope = 'local',
    this.transport,
    this.envVars,
    this.headers,
    this.clientId,
    this.clientSecret = false,
    this.callbackPort,
    this.xaa = false,
  });

  /// Parse from a raw argument string.
  /// Expected format mirrors the CLI:
  ///   `/mcp add [--scope <scope>] [--transport <t>] [-e KEY=val]`
  ///            `[-H "Header: val"] [--client-id <id>] [--client-secret]`
  ///            `[--callback-port <port>] [--xaa] <name> <command> [args...]`
  factory McpAddOptions.parse(String rawArgs) {
    final tokens = _tokenize(rawArgs);
    String? scope;
    String? transport;
    final envVars = <String>[];
    final headers = <String>[];
    String? clientId;
    bool clientSecret = false;
    int? callbackPort;
    bool xaa = false;
    final positional = <String>[];

    var i = 0;
    while (i < tokens.length) {
      final tok = tokens[i];
      switch (tok) {
        case '-s':
        case '--scope':
          scope = (++i < tokens.length) ? tokens[i] : null;
          break;
        case '-t':
        case '--transport':
          transport = (++i < tokens.length) ? tokens[i] : null;
          break;
        case '-e':
        case '--env':
          if (++i < tokens.length) envVars.add(tokens[i]);
          break;
        case '-H':
        case '--header':
          if (++i < tokens.length) headers.add(tokens[i]);
          break;
        case '--client-id':
          clientId = (++i < tokens.length) ? tokens[i] : null;
          break;
        case '--client-secret':
          clientSecret = true;
          break;
        case '--callback-port':
          final raw = (++i < tokens.length) ? tokens[i] : null;
          callbackPort = raw != null ? int.tryParse(raw) : null;
          break;
        case '--xaa':
          xaa = true;
          break;
        case '--':
          // Everything after -- is positional
          i++;
          while (i < tokens.length) {
            positional.add(tokens[i++]);
          }
          continue;
        default:
          positional.add(tok);
      }
      i++;
    }

    if (positional.isEmpty) {
      throw ArgumentError(
        'Error: Server name is required.\n'
        'Usage: /mcp add <name> <command> [args...]',
      );
    }
    if (positional.length < 2) {
      throw ArgumentError(
        'Error: Command is required when server name is provided.\n'
        'Usage: /mcp add <name> <command> [args...]',
      );
    }

    return McpAddOptions(
      name: positional[0],
      commandOrUrl: positional[1],
      args: positional.length > 2 ? positional.sublist(2) : const [],
      scope: scope ?? 'local',
      transport: transport,
      envVars: envVars.isEmpty ? null : envVars,
      headers: headers.isEmpty ? null : headers,
      clientId: clientId,
      clientSecret: clientSecret,
      callbackPort: callbackPort,
      xaa: xaa,
    );
  }

  /// Simple shell-like tokenizer respecting double-quoted strings.
  static List<String> _tokenize(String input) {
    final tokens = <String>[];
    final buf = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == ' ' && !inQuotes) {
        if (buf.isNotEmpty) {
          tokens.add(buf.toString());
          buf.clear();
        }
      } else {
        buf.write(ch);
      }
    }
    if (buf.isNotEmpty) tokens.add(buf.toString());
    return tokens;
  }
}

// ============================================================================
// McpAddCommand
// ============================================================================

/// The /mcp add command — registers MCP servers in NeomClaw configuration.
///
/// Supports three transport types:
///   - stdio: subprocess-based MCP servers (default)
///   - sse:   Server-Sent Events over HTTP
///   - http:  Standard HTTP transport
///
/// Options:
///   `-s, --scope <scope>`         Configuration scope (local, user, project)
///   `-t, --transport <transport>` Transport type (stdio, sse, http)
///   `-e, --env <KEY=val>`         Environment variables for stdio servers
///   `-H, --header <Header: val>`  Headers for HTTP/SSE servers
///   `--client-id <id>`            OAuth client ID for HTTP/SSE servers
///   --client-secret             Prompt for OAuth client secret
///   `--callback-port <port>`      Fixed OAuth callback port
///   --xaa                       Enable XAA (SEP-990) authentication
class McpAddCommand extends LocalCommand {
  /// Callback to get the current working directory.
  final String Function() getCwd;

  McpAddCommand({required this.getCwd});

  @override
  String get name => 'mcp-add';

  @override
  String get description => 'Add an MCP server to NeomClaw';

  @override
  String? get argumentHint =>
      '[-s scope] [-t transport] [-e KEY=val] [-H "Header: val"] '
      '[--client-id id] [--client-secret] [--callback-port port] [--xaa] '
      '<name> <commandOrUrl> [args...]';

  @override
  bool get supportsNonInteractive => true;

  @override
  Future<CommandResult> execute(String args, ToolUseContext context) async {
    // Parse options.
    final McpAddOptions options;
    try {
      options = McpAddOptions.parse(args);
    } on ArgumentError catch (e) {
      return TextCommandResult(e.message);
    }

    try {
      final scope = ensureConfigScope(options.scope);
      final transport = ensureTransport(options.transport);
      final cwd = getCwd();

      // XAA fail-fast: validate at add-time, not auth-time.
      if (options.xaa && !isXaaEnabled()) {
        return const TextCommandResult(
          'Error: --xaa requires NEOMCLAW_ENABLE_XAA=1 in your environment',
        );
      }

      if (options.xaa) {
        final missing = <String>[];
        if (options.clientId == null) missing.add('--client-id');
        if (!options.clientSecret) missing.add('--client-secret');
        if (!hasXaaIdpSettings()) {
          missing.add(
            "'neomclaw mcp xaa setup' (settings.xaaIdp not configured)",
          );
        }
        if (missing.isNotEmpty) {
          return TextCommandResult(
            'Error: --xaa requires: ${missing.join(', ')}',
          );
        }
      }

      // Check if transport was explicitly provided.
      final transportExplicit = options.transport != null;

      // Check if the command looks like a URL (likely incorrect usage).
      final cmd = options.commandOrUrl;
      final looksLikeUrl =
          cmd.startsWith('http://') ||
          cmd.startsWith('https://') ||
          cmd.startsWith('localhost') ||
          cmd.endsWith('/sse') ||
          cmd.endsWith('/mcp');

      final output = StringBuffer();

      if (transport == McpTransport.sse) {
        final headers = options.headers != null
            ? parseHeaders(options.headers!)
            : null;
        final oauth = buildOAuthConfig(
          clientId: options.clientId,
          callbackPort: options.callbackPort,
          xaa: options.xaa,
        );

        final serverConfig = SseMcpServerConfig(
          url: cmd,
          headers: headers,
          oauth: oauth,
        );
        await addMcpConfig(options.name, serverConfig, scope, cwd);

        output.writeln(
          'Added SSE MCP server ${options.name} with URL: $cmd '
          'to ${scope.name} config',
        );
        if (headers != null && headers.isNotEmpty) {
          output.writeln(
            'Headers: ${const JsonEncoder.withIndent('  ').convert(headers)}',
          );
        }
      } else if (transport == McpTransport.http) {
        final headers = options.headers != null
            ? parseHeaders(options.headers!)
            : null;
        final oauth = buildOAuthConfig(
          clientId: options.clientId,
          callbackPort: options.callbackPort,
          xaa: options.xaa,
        );

        final serverConfig = HttpMcpServerConfig(
          url: cmd,
          headers: headers,
          oauth: oauth,
        );
        await addMcpConfig(options.name, serverConfig, scope, cwd);

        output.writeln(
          'Added HTTP MCP server ${options.name} with URL: $cmd '
          'to ${scope.name} config',
        );
        if (headers != null && headers.isNotEmpty) {
          output.writeln(
            'Headers: ${const JsonEncoder.withIndent('  ').convert(headers)}',
          );
        }
      } else {
        // stdio transport
        if (options.clientId != null ||
            options.clientSecret ||
            options.callbackPort != null ||
            options.xaa) {
          output.writeln(
            'Warning: --client-id, --client-secret, --callback-port, and '
            '--xaa are only supported for HTTP/SSE transports and will be '
            'ignored for stdio.',
          );
        }

        // Warn if this looks like a URL but transport wasn't explicitly
        // specified.
        if (!transportExplicit && looksLikeUrl) {
          output.writeln();
          output.writeln(
            'Warning: The command "$cmd" looks like a URL, but is being '
            'interpreted as a stdio server as --transport was not specified.',
          );
          output.writeln(
            'If this is an HTTP server, use: /mcp-add --transport http '
            '${options.name} $cmd',
          );
          output.writeln(
            'If this is an SSE server, use: /mcp-add --transport sse '
            '${options.name} $cmd',
          );
        }

        final env = parseEnvVars(options.envVars);
        final serverConfig = StdioMcpServerConfig(
          command: cmd,
          args: options.args,
          env: env.isNotEmpty ? env : null,
        );
        await addMcpConfig(options.name, serverConfig, scope, cwd);

        output.writeln(
          'Added stdio MCP server ${options.name} with command: '
          '$cmd ${options.args.join(' ')} to ${scope.name} config',
        );
      }

      output.writeln('File modified: ${describeMcpConfigFilePath(scope)}');
      return TextCommandResult(output.toString().trimRight());
    } catch (e) {
      return TextCommandResult('Error: $e');
    }
  }
}
