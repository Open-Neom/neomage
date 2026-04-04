// MCP config — port of neom_claw/src/services/mcp/config.ts.
// Configuration loading and validation for MCP servers.

import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'mcp_types.dart';

/// Load MCP server configs from a JSON file (.mcp.json format).
Future<List<McpServerConfig>> loadMcpConfigFile(String path) async {
  final file = File(path);
  if (!await file.exists()) return const [];

  try {
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return _parseConfigs(json);
  } catch (_) {
    return const [];
  }
}

/// Load all MCP configs from standard locations.
Future<List<McpServerConfig>> loadAllMcpConfigs({String? projectRoot}) async {
  final configs = <McpServerConfig>[];

  // 1. Project-local: .mcp.json
  if (projectRoot != null) {
    configs.addAll(await loadMcpConfigFile('$projectRoot/.mcp.json'));
  }

  // 2. User: ~/.neomclaw/settings.json (mcpServers key)
  final homeDir =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/tmp';
  final userSettings = File('$homeDir/.neomclaw/settings.json');
  if (await userSettings.exists()) {
    try {
      final json = jsonDecode(await userSettings.readAsString());
      final servers = (json as Map<String, dynamic>)['mcpServers'];
      if (servers is Map<String, dynamic>) {
        configs.addAll(_parseConfigs(servers));
      }
    } catch (_) {}
  }

  // 3. Managed: ~/.neomclaw/managed/managed-mcp.json
  final managedFile = File('$homeDir/.neomclaw/managed/managed-mcp.json');
  if (await managedFile.exists()) {
    configs.addAll(await loadMcpConfigFile(managedFile.path));
  }

  return configs;
}

/// Write MCP config to a .mcp.json file.
Future<void> writeMcpConfigFile(
  String path,
  List<McpServerConfig> configs,
) async {
  final json = <String, dynamic>{};
  for (final config in configs) {
    json[config.name] = _configToJson(config);
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
}

// ── Parsing ──

List<McpServerConfig> _parseConfigs(Map<String, dynamic> json) {
  final configs = <McpServerConfig>[];

  for (final entry in json.entries) {
    final name = entry.key;
    final value = entry.value;
    if (value is! Map<String, dynamic>) continue;

    final config = _parseOneConfig(name, value);
    if (config != null) configs.add(config);
  }

  return configs;
}

McpServerConfig? _parseOneConfig(String name, Map<String, dynamic> json) {
  final env = _parseEnv(json['env']);

  // Detect transport type
  if (json.containsKey('command')) {
    return McpStdioConfig(
      name: name,
      command: json['command'] as String,
      args:
          (json['args'] as List<dynamic>?)?.map((a) => a.toString()).toList() ??
          const [],
      env: env,
    );
  }

  if (json.containsKey('url')) {
    final url = json['url'] as String;
    final headers = _parseHeaders(json['headers']);
    final transport = json['transport'] as String?;

    if (transport == 'sse' || url.contains('/sse')) {
      return McpSseConfig(name: name, url: url, headers: headers, env: env);
    }

    if (transport == 'ws' ||
        url.startsWith('ws://') ||
        url.startsWith('wss://')) {
      return McpWebSocketConfig(
        name: name,
        url: url,
        headers: headers,
        env: env,
      );
    }

    return McpHttpConfig(name: name, url: url, headers: headers, env: env);
  }

  return null;
}

Map<String, String> _parseEnv(dynamic env) {
  if (env is! Map) return const {};
  return env.map((k, v) => MapEntry(k.toString(), v.toString()));
}

Map<String, String> _parseHeaders(dynamic headers) {
  if (headers is! Map) return const {};
  return headers.map((k, v) => MapEntry(k.toString(), v.toString()));
}

Map<String, dynamic> _configToJson(McpServerConfig config) => switch (config) {
  McpStdioConfig(command: final cmd, args: final args) => {
    'command': cmd,
    if (args.isNotEmpty) 'args': args,
    if (config.env.isNotEmpty) 'env': config.env,
  },
  McpSseConfig(url: final url, headers: final h) => {
    'url': url,
    'transport': 'sse',
    if (h.isNotEmpty) 'headers': h,
    if (config.env.isNotEmpty) 'env': config.env,
  },
  McpHttpConfig(url: final url, headers: final h) => {
    'url': url,
    if (h.isNotEmpty) 'headers': h,
    if (config.env.isNotEmpty) 'env': config.env,
  },
  McpWebSocketConfig(url: final url, headers: final h) => {
    'url': url,
    'transport': 'ws',
    if (h.isNotEmpty) 'headers': h,
    if (config.env.isNotEmpty) 'env': config.env,
  },
  McpSdkConfig() => {
    'transport': 'sdk',
    if (config.env.isNotEmpty) 'env': config.env,
  },
};
