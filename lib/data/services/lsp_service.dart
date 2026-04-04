// LSP service — port of neom_claw/src/services/lsp/.
// Language Server Protocol client for code intelligence.
// Manages LSP server lifecycles, file synchronization, and diagnostics.

import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart';

/// LSP server states.
enum LspServerState { stopped, starting, running, stopping, error }

/// LSP server configuration.
class LspServerConfig {
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> extensionToLanguage;
  final Map<String, String> env;
  final String? workspaceFolder;
  final Map<String, dynamic>? initializationOptions;
  final int maxRestarts;

  const LspServerConfig({
    required this.name,
    required this.command,
    this.args = const [],
    required this.extensionToLanguage,
    this.env = const {},
    this.workspaceFolder,
    this.initializationOptions,
    this.maxRestarts = 3,
  });
}

/// LSP diagnostic severity.
enum DiagnosticSeverity { error, warning, information, hint }

/// An LSP diagnostic.
class LspDiagnostic {
  final String filePath;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;
  final String message;
  final DiagnosticSeverity severity;
  final String? code;
  final String? source;

  const LspDiagnostic({
    required this.filePath,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
    required this.message,
    required this.severity,
    this.code,
    this.source,
  });
}

/// A connected LSP server instance.
class LspServerInstance {
  final LspServerConfig config;
  final Process _process;
  final StreamSubscription<String> _stdoutSub;
  final Map<int, Completer<Map<String, dynamic>>> _pendingRequests = {};
  final Map<String, void Function(Map<String, dynamic>)> _notificationHandlers =
      {};
  int _nextId = 1;

  LspServerState state;
  int restartCount;
  String? lastError;
  Map<String, dynamic>? serverCapabilities;

  LspServerInstance._({
    required this.config,
    required Process process,
    required StreamSubscription<String> stdoutSub,
    this.state = LspServerState.running,
  }) : _process = process,
       _stdoutSub = stdoutSub,
       restartCount = 0;

  /// Send a JSON-RPC request and await response.
  Future<Map<String, dynamic>> sendRequest(
    String method,
    Map<String, dynamic> params,
  ) async {
    final id = _nextId++;
    final request = {
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    };

    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    _send(request);

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw TimeoutException('LSP request timed out: $method');
      },
    );
  }

  /// Send a notification (no response expected).
  void sendNotification(String method, Map<String, dynamic> params) {
    _send({'jsonrpc': '2.0', 'method': method, 'params': params});
  }

  /// Register a notification handler.
  void onNotification(
    String method,
    void Function(Map<String, dynamic>) handler,
  ) {
    _notificationHandlers[method] = handler;
  }

  /// Stop the server.
  Future<void> stop() async {
    state = LspServerState.stopping;
    try {
      // Send shutdown request
      await sendRequest('shutdown', {}).timeout(
        const Duration(seconds: 5),
        onTimeout: () => <String, dynamic>{},
      );
      // Send exit notification
      sendNotification('exit', {});
      await Future.delayed(const Duration(milliseconds: 200));
    } catch (_) {}

    _process.kill(ProcessSignal.sigterm);
    await _stdoutSub.cancel();
    state = LspServerState.stopped;
  }

  void _send(Map<String, dynamic> message) {
    final body = jsonEncode(message);
    final header = 'Content-Length: ${utf8.encode(body).length}\r\n\r\n';
    _process.stdin.write(header);
    _process.stdin.write(body);
    _process.stdin.flush();
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (message.containsKey('id') && message.containsKey('result')) {
      // Response
      final id = message['id'] as int;
      _pendingRequests
          .remove(id)
          ?.complete(message['result'] as Map<String, dynamic>? ?? {});
    } else if (message.containsKey('id') && message.containsKey('error')) {
      // Error response
      final id = message['id'] as int;
      final error = message['error'] as Map<String, dynamic>;
      _pendingRequests
          .remove(id)
          ?.completeError(Exception('LSP error: ${error['message']}'));
    } else if (message.containsKey('method') && !message.containsKey('id')) {
      // Notification
      final method = message['method'] as String;
      final params = message['params'] as Map<String, dynamic>? ?? {};
      _notificationHandlers[method]?.call(params);
    }
  }
}

/// LSP server manager — manages multiple LSP servers and routes requests.
class LspServerManager {
  final Map<String, LspServerInstance> _servers = {};
  final Map<String, String> _openFiles = {}; // filePath → serverName
  final Map<String, int> _fileVersions = {}; // filePath → version
  final List<LspServerConfig> _configs;
  final void Function(List<LspDiagnostic>)? onDiagnostics;

  LspServerManager({required List<LspServerConfig> configs, this.onDiagnostics})
    : _configs = configs;

  /// All server instances.
  Map<String, LspServerInstance> get servers => Map.unmodifiable(_servers);

  /// Find the config for a file based on extension.
  LspServerConfig? configForFile(String filePath) {
    final ext = filePath.contains('.') ? '.${filePath.split('.').last}' : '';

    for (final config in _configs) {
      if (config.extensionToLanguage.containsKey(ext)) {
        return config;
      }
    }
    return null;
  }

  /// Ensure a server is started for the given file.
  Future<LspServerInstance?> ensureServerForFile(String filePath) async {
    final config = configForFile(filePath);
    if (config == null) return null;

    final existing = _servers[config.name];
    if (existing != null && existing.state == LspServerState.running) {
      return existing;
    }

    return _startServer(config);
  }

  /// Open a file (sends textDocument/didOpen).
  Future<void> openFile(String filePath, String content) async {
    final server = await ensureServerForFile(filePath);
    if (server == null) return;

    final config = configForFile(filePath)!;
    final ext = filePath.contains('.') ? '.${filePath.split('.').last}' : '';
    final languageId = config.extensionToLanguage[ext] ?? 'plaintext';

    _openFiles[filePath] = config.name;
    _fileVersions[filePath] = 1;

    server.sendNotification('textDocument/didOpen', {
      'textDocument': {
        'uri': _fileUri(filePath),
        'languageId': languageId,
        'version': 1,
        'text': content,
      },
    });
  }

  /// Notify content change (sends textDocument/didChange).
  Future<void> changeFile(String filePath, String content) async {
    final serverName = _openFiles[filePath];
    if (serverName == null) return;

    final server = _servers[serverName];
    if (server == null) return;

    final version = (_fileVersions[filePath] ?? 0) + 1;
    _fileVersions[filePath] = version;

    server.sendNotification('textDocument/didChange', {
      'textDocument': {'uri': _fileUri(filePath), 'version': version},
      'contentChanges': [
        {'text': content},
      ],
    });
  }

  /// Notify file save (sends textDocument/didSave).
  void saveFile(String filePath) {
    final serverName = _openFiles[filePath];
    if (serverName == null) return;

    _servers[serverName]?.sendNotification('textDocument/didSave', {
      'textDocument': {'uri': _fileUri(filePath)},
    });
  }

  /// Close a file (sends textDocument/didClose).
  void closeFile(String filePath) {
    final serverName = _openFiles.remove(filePath);
    if (serverName == null) return;

    _fileVersions.remove(filePath);
    _servers[serverName]?.sendNotification('textDocument/didClose', {
      'textDocument': {'uri': _fileUri(filePath)},
    });
  }

  /// Send a request to the server handling a file.
  Future<Map<String, dynamic>?> sendRequest(
    String filePath,
    String method,
    Map<String, dynamic> params,
  ) async {
    final server = await ensureServerForFile(filePath);
    if (server == null) return null;

    try {
      return await server.sendRequest(method, params);
    } catch (e) {
      // Transient error retry for "content modified"
      if (e.toString().contains('-32801')) {
        await Future.delayed(const Duration(milliseconds: 100));
        return server.sendRequest(method, params);
      }
      rethrow;
    }
  }

  /// Shutdown all servers.
  Future<void> shutdown() async {
    for (final server in _servers.values) {
      await server.stop();
    }
    _servers.clear();
    _openFiles.clear();
    _fileVersions.clear();
  }

  /// Check if a file is currently open.
  bool isFileOpen(String filePath) => _openFiles.containsKey(filePath);

  // ── Private ──

  Future<LspServerInstance> _startServer(LspServerConfig config) async {
    final process = await Process.start(
      config.command,
      config.args,
      environment: config.env.isNotEmpty ? config.env : null,
      workingDirectory: config.workspaceFolder,
    );

    // Parse LSP Content-Length framed messages from stdout
    final controller = StreamController<String>();
    final buffer = StringBuffer();
    int? expectedLength;

    process.stdout.transform(utf8.decoder).listen((chunk) {
      buffer.write(chunk);
      final str = buffer.toString();

      while (true) {
        if (expectedLength == null) {
          final headerEnd = str.indexOf('\r\n\r\n');
          if (headerEnd == -1) break;

          final header = str.substring(0, headerEnd);
          final match = RegExp(r'Content-Length:\s*(\d+)').firstMatch(header);
          if (match == null) break;

          expectedLength = int.parse(match.group(1)!);
          final bodyStart = headerEnd + 4;
          buffer.clear();
          buffer.write(str.substring(bodyStart));
        } else {
          final current = buffer.toString();
          if (current.length >= expectedLength!) {
            controller.add(current.substring(0, expectedLength!));
            buffer.clear();
            buffer.write(current.substring(expectedLength!));
            expectedLength = null;
          } else {
            break;
          }
        }
      }
    });

    late final LspServerInstance server;
    final stdoutSub = controller.stream.listen((message) {
      try {
        final json = jsonDecode(message) as Map<String, dynamic>;
        server._handleMessage(json);
      } catch (_) {}
    });

    server = LspServerInstance._(
      config: config,
      process: process,
      stdoutSub: stdoutSub,
      state: LspServerState.starting,
    );

    _servers[config.name] = server;

    // Register diagnostic handler
    server.onNotification('textDocument/publishDiagnostics', (params) {
      _handleDiagnostics(params);
    });

    // Initialize
    try {
      final result = await server.sendRequest('initialize', {
        'processId': pid,
        'capabilities': {
          'textDocument': {
            'synchronization': {
              'dynamicRegistration': false,
              'willSave': false,
              'willSaveWaitUntil': false,
              'didSave': true,
            },
            'completion': {
              'completionItem': {'snippetSupport': false},
            },
            'hover': {'dynamicRegistration': false},
            'definition': {'dynamicRegistration': false},
            'references': {'dynamicRegistration': false},
            'publishDiagnostics': {'relatedInformation': true},
          },
          'workspace': {'workspaceFolders': true, 'configuration': false},
        },
        if (config.workspaceFolder != null) ...{
          'rootUri': _fileUri(config.workspaceFolder!),
          'rootPath': config.workspaceFolder,
          'workspaceFolders': [
            {
              'uri': _fileUri(config.workspaceFolder!),
              'name': config.workspaceFolder!.split('/').last,
            },
          ],
        },
        if (config.initializationOptions != null)
          'initializationOptions': config.initializationOptions,
      });

      server.serverCapabilities =
          result['capabilities'] as Map<String, dynamic>?;
      server.sendNotification('initialized', {});
      server.state = LspServerState.running;
    } catch (e) {
      server.state = LspServerState.error;
      server.lastError = e.toString();
    }

    // Handle process exit for crash recovery
    process.exitCode.then((code) {
      if (server.state == LspServerState.running) {
        server.state = LspServerState.error;
        server.lastError = 'Process exited with code $code';

        if (server.restartCount < config.maxRestarts) {
          server.restartCount++;
          // Auto-restart after brief delay
          Future.delayed(
            Duration(seconds: server.restartCount * 2),
            () => _startServer(config),
          );
        }
      }
    });

    return server;
  }

  void _handleDiagnostics(Map<String, dynamic> params) {
    final uri = params['uri'] as String? ?? '';
    final filePath = Uri.parse(uri).toFilePath();
    final diagnosticsList = params['diagnostics'] as List? ?? [];

    final diagnostics = diagnosticsList.map((d) {
      final diag = d as Map<String, dynamic>;
      final range = diag['range'] as Map<String, dynamic>;
      final start = range['start'] as Map<String, dynamic>;
      final end = range['end'] as Map<String, dynamic>;
      final severity = diag['severity'] as int? ?? 1;

      return LspDiagnostic(
        filePath: filePath,
        startLine: start['line'] as int,
        startColumn: start['character'] as int,
        endLine: end['line'] as int,
        endColumn: end['character'] as int,
        message: diag['message'] as String? ?? '',
        severity: switch (severity) {
          1 => DiagnosticSeverity.error,
          2 => DiagnosticSeverity.warning,
          3 => DiagnosticSeverity.information,
          _ => DiagnosticSeverity.hint,
        },
        code: diag['code']?.toString(),
        source: diag['source'] as String?,
      );
    }).toList();

    onDiagnostics?.call(diagnostics);
  }

  String _fileUri(String path) {
    if (path.startsWith('file://')) return path;
    return Uri.file(path).toString();
  }
}

/// Standard LSP server configs for common languages.
List<LspServerConfig> defaultLspConfigs({String? workspaceFolder}) => [
  LspServerConfig(
    name: 'typescript',
    command: 'typescript-language-server',
    args: ['--stdio'],
    extensionToLanguage: {
      '.ts': 'typescript',
      '.tsx': 'typescriptreact',
      '.js': 'javascript',
      '.jsx': 'javascriptreact',
    },
    workspaceFolder: workspaceFolder,
  ),
  LspServerConfig(
    name: 'dart',
    command: 'dart',
    args: ['language-server', '--protocol=lsp'],
    extensionToLanguage: {'.dart': 'dart'},
    workspaceFolder: workspaceFolder,
  ),
  LspServerConfig(
    name: 'python',
    command: 'pylsp',
    extensionToLanguage: {'.py': 'python'},
    workspaceFolder: workspaceFolder,
  ),
  LspServerConfig(
    name: 'rust',
    command: 'rust-analyzer',
    extensionToLanguage: {'.rs': 'rust'},
    workspaceFolder: workspaceFolder,
  ),
  LspServerConfig(
    name: 'go',
    command: 'gopls',
    extensionToLanguage: {'.go': 'go'},
    workspaceFolder: workspaceFolder,
  ),
];
