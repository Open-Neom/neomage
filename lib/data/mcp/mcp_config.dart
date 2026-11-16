// MCP config — port of neomage/src/services/mcp/config.ts.
// Configuration loading and validation for MCP servers.

import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';

import '../../utils/security/neomage_network_guard.dart';
import 'mcp_types.dart';

const int _maxMcpConfigBytes = 1024 * 1024;
const int _maxMcpArgsCount = 64;

Future<Map<String, dynamic>?> _readSafeJsonMap(String path) async {
  if (path.isEmpty || path.contains('\x00')) return null;
  if (await FileSystemEntity.isLink(path)) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  if (await file.length() > _maxMcpConfigBytes) return null;
  try {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return null;
}

/// Load MCP server configs from a JSON file (.mcp.json format).
Future<List<McpServerConfig>> loadMcpConfigFile(String path) async {
  final json = await _readSafeJsonMap(path);
  if (json == null) return const [];
  return _parseConfigs(json);
}

/// Load all MCP configs from standard locations.
Future<List<McpServerConfig>> loadAllMcpConfigs({String? projectRoot}) async {
  final configs = <McpServerConfig>[];

  // 1. Project-local: .mcp.json
  if (projectRoot != null && !projectRoot.contains('\x00')) {
    configs.addAll(await loadMcpConfigFile('$projectRoot/.mcp.json'));
  }

  // 2. User: ~/.neomage/settings.json (mcpServers key)
  final homeDir =
      Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '/tmp';
  final settingsJson = await _readSafeJsonMap('$homeDir/.neomage/settings.json');
  if (settingsJson != null) {
    final servers = settingsJson['mcpServers'];
    if (servers is Map<String, dynamic>) {
      configs.addAll(_parseConfigs(servers));
    }
  }

  // 3. Managed: ~/.neomage/managed/managed-mcp.json
  final managedPath = '$homeDir/.neomage/managed/managed-mcp.json';
  configs.addAll(await loadMcpConfigFile(managedPath));

  return configs;
}

/// Write MCP config to a .mcp.json file.
Future<void> writeMcpConfigFile(
  String path,
  List<McpServerConfig> configs,
) async {
  final blockReason = NeomageNetworkGuard.checkProtectedFilesystemPath(path);
  if (blockReason != null) {
    throw ArgumentError(blockReason);
  }
  if (await FileSystemEntity.isLink(path)) {
    throw ArgumentError('Refusing to write MCP config through symbolic link');
  }
  final json = <String, dynamic>{};
  for (final config in configs) {
    if (!NeomageNetworkGuard.isSafeIdentifier(config.name)) continue;
    json[config.name] = _configToJson(config);
  }
  final file = File(path);
  await file.parent.create(recursive: true);
  final tmpFile = File('$path.tmp.${DateTime.now().microsecondsSinceEpoch}');
  await tmpFile.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  await tmpFile.rename(path);
}

// ── Parsing ──

List<McpServerConfig> _parseConfigs(Map<String, dynamic> json) {
  final configs = <McpServerConfig>[];

  for (final entry in json.entries) {
    final name = entry.key;
    if (!NeomageNetworkGuard.isSafeIdentifier(name)) continue;
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
    final rawCmd = json['command'];
    if (rawCmd is! String || !NeomageNetworkGuard.isSafeMcpCommand(rawCmd)) {
      return null;
    }
    final rawArgs =
        (json['args'] as List<dynamic>?)?.map((a) => a.toString()).toList() ??
        const <String>[];
    if (rawArgs.length > _maxMcpArgsCount ||
        rawArgs.any((a) => a.contains('\x00') || a.length > 8192)) {
      return null;
    }
    return McpStdioConfig(
      name: name,
      command: rawCmd.trim(),
      args: rawArgs,
      env: env,
    );
  }

  if (json.containsKey('url')) {
    final rawUrl = json['url'];
    if (rawUrl is! String) return null;
    final url = rawUrl.trim();
    final uri = Uri.tryParse(url);
    final headers = _parseHeaders(json['headers']);
    final transport = json['transport'] as String?;

    if (transport == 'ws' ||
        url.startsWith('ws://') ||
        url.startsWith('wss://')) {
      if (!NeomageNetworkGuard.isSafeWebSocketEndpointUri(
        uri,
        allowLoopbackInsecure: true,
      )) {
        return null;
      }
      return McpWebSocketConfig(
        name: name,
        url: url,
        headers: headers,
        env: env,
      );
    }

    if (!NeomageNetworkGuard.isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: true,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{'http'},
    )) {
      return null;
    }

    if (transport == 'sse' || url.contains('/sse')) {
      return McpSseConfig(name: name, url: url, headers: headers, env: env);
    }

    return McpHttpConfig(name: name, url: url, headers: headers, env: env);
  }

  return null;
}

Map<String, String> _parseEnv(dynamic env) {
  if (env is! Map) return const {};
  final raw = env.map((k, v) => MapEntry(k.toString(), v.toString()));
  return NeomageNetworkGuard.sanitizeSubprocessEnv(raw);
}

Map<String, String> _parseHeaders(dynamic headers) {
  if (headers is! Map) return const {};
  final out = <String, String>{};
  for (final entry in headers.entries) {
    final k = entry.key.toString().trim();
    if (!NeomageNetworkGuard.isValidHeaderName(k)) continue;
    out[k] = NeomageNetworkGuard.sanitizeHeaderValue(entry.value.toString());
  }
  return out;
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
