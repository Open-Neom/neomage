import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'platform_interface.dart';

/// Web implementation of [PlatformService].
///
/// Every call is proxied to a local REST API server at [_baseUrl] (defaults to
/// `http://localhost:3219`).  The server is expected to be running alongside
/// the web frontend — see `bin/server.dart`.
///
/// This file must never import `dart:io`.
class WebPlatformService implements PlatformService {
  final String _baseUrl;
  final http.Client _client;

  WebPlatformService({
    String baseUrl = 'http://localhost:3219',
    http.Client? client,
  })  : _baseUrl = baseUrl,
        _client = client ?? http.Client();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? queryParams]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _client.get(_uri(path, query));
    if (response.statusCode != 200) {
      throw PlatformException(
        'GET $path failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _client.post(
      _uri(path),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode != 200) {
      throw PlatformException(
        'POST $path failed: ${response.statusCode} ${response.body}',
      );
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — basic read / write
  // ---------------------------------------------------------------------------

  @override
  Future<String> readFile(String path) async {
    final json = await _getJson('/api/fs/read', {'path': path});
    return json['content'] as String;
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    final response = await _client.get(
      _uri('/api/fs/read-bytes', {'path': path}),
    );
    if (response.statusCode != 200) {
      throw PlatformException(
        'GET /api/fs/read-bytes failed: ${response.statusCode}',
      );
    }
    return response.bodyBytes;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    await _postJson('/api/fs/write', {'path': path, 'content': content});
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    final response = await _client.post(
      _uri('/api/fs/write-bytes', {'path': path}),
      headers: {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (response.statusCode != 200) {
      throw PlatformException(
        'POST /api/fs/write-bytes failed: ${response.statusCode}',
      );
    }
  }

  @override
  Future<void> appendFile(String path, String content) async {
    await _postJson('/api/fs/append', {'path': path, 'content': content});
  }

  // ---------------------------------------------------------------------------
  // Filesystem — queries
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) async {
    final json = await _getJson('/api/fs/exists', {'path': path, 'type': 'file'});
    return json['exists'] as bool;
  }

  @override
  Future<bool> directoryExists(String path) async {
    final json = await _getJson('/api/fs/exists', {'path': path, 'type': 'directory'});
    return json['exists'] as bool;
  }

  @override
  Future<PlatformFileStat> statFile(String path) async {
    final json = await _getJson('/api/fs/stat', {'path': path});
    return PlatformFileStat.fromJson(json);
  }

  @override
  Future<List<String>> listDirectory(
    String path, {
    bool recursive = false,
  }) async {
    final json = await _getJson('/api/fs/list', {
      'path': path,
      'recursive': recursive.toString(),
    });
    return List<String>.from(json['entries'] as List);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — mutations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    await _postJson('/api/fs/mkdir', {
      'path': path,
      'recursive': recursive,
    });
  }

  @override
  Future<void> deleteFile(String path) async {
    await _postJson('/api/fs/delete', {'path': path, 'type': 'file'});
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    await _postJson('/api/fs/delete', {
      'path': path,
      'type': 'directory',
      'recursive': recursive,
    });
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    await _postJson('/api/fs/copy', {
      'source': source,
      'destination': destination,
    });
  }

  @override
  Future<void> moveFile(String source, String destination) async {
    await _postJson('/api/fs/move', {
      'source': source,
      'destination': destination,
    });
  }

  // ---------------------------------------------------------------------------
  // Filesystem — temp helpers
  // ---------------------------------------------------------------------------

  @override
  Future<String> createTempFile({String? prefix, String? suffix}) async {
    final json = await _postJson('/api/fs/temp-file', {
      if (prefix != null) 'prefix': prefix,
      if (suffix != null) 'suffix': suffix,
    });
    return json['path'] as String;
  }

  @override
  Future<String> createTempDirectory({String? prefix}) async {
    final json = await _postJson('/api/fs/temp-dir', {
      if (prefix != null) 'prefix': prefix,
    });
    return json['path'] as String;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — well-known paths (cached from server)
  // ---------------------------------------------------------------------------

  String? _currentDirectory;
  String? _homeDirectory;
  String? _tempDirectory;

  Future<void> _ensurePathsCached() async {
    if (_currentDirectory != null) return;
    final json = await _getJson('/api/env/paths');
    _currentDirectory = json['currentDirectory'] as String;
    _homeDirectory = json['homeDirectory'] as String;
    _tempDirectory = json['tempDirectory'] as String;
  }

  @override
  String get currentDirectory {
    if (_currentDirectory == null) {
      // Kick off async fetch; return sensible default until it completes.
      _ensurePathsCached();
      return '/';
    }
    return _currentDirectory!;
  }

  @override
  String get homeDirectory {
    if (_homeDirectory == null) {
      _ensurePathsCached();
      return '/';
    }
    return _homeDirectory!;
  }

  @override
  String get tempDirectory {
    if (_tempDirectory == null) {
      _ensurePathsCached();
      return '/tmp';
    }
    return _tempDirectory!;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — watch
  // ---------------------------------------------------------------------------

  @override
  Stream<FileChangeEvent> watchDirectory(
    String path, {
    bool recursive = true,
  }) {
    // File watching on web is done via a WebSocket on the server.
    final controller = StreamController<FileChangeEvent>();
    final wsUrl = _baseUrl.replaceFirst('http', 'ws');
    final uri = Uri.parse(
      '$wsUrl/api/fs/watch?path=${Uri.encodeComponent(path)}'
      '&recursive=$recursive',
    );

    _connectWatch(uri, controller);
    return controller.stream;
  }

  Future<void> _connectWatch(
    Uri uri,
    StreamController<FileChangeEvent> controller,
  ) async {
    try {
      final ws = await connectWebSocket(uri);
      ws.stream.listen(
        (data) {
          if (data is String) {
            final json = jsonDecode(data) as Map<String, dynamic>;
            controller.add(FileChangeEvent.fromJson(json));
          }
        },
        onDone: () => controller.close(),
        onError: (Object e) => controller.addError(e),
      );
    } catch (e) {
      controller.addError(e);
      controller.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Process execution
  // ---------------------------------------------------------------------------

  @override
  Future<ProcessOutput> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool runInShell = false,
  }) async {
    final json = await _postJson('/api/process/run', {
      'executable': executable,
      'arguments': arguments,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (environment != null) 'environment': environment,
      if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
      'runInShell': runInShell,
    });
    return ProcessOutput.fromJson(json);
  }

  @override
  Future<RunningProcess> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    // Start the process on the server and get a process ID back.
    final json = await _postJson('/api/process/start', {
      'executable': executable,
      'arguments': arguments,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      if (environment != null) 'environment': environment,
      'runInShell': runInShell,
    });

    final pid = json['pid'] as int;
    final wsUrl = _baseUrl.replaceFirst('http', 'ws');

    return _WebRunningProcess(
      pid: pid,
      baseUrl: _baseUrl,
      wsUrl: wsUrl,
      client: _client,
    );
  }

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------

  Map<String, String>? _envCache;

  @override
  Map<String, String> get environmentVariables {
    if (_envCache == null) {
      // Fire-and-forget fetch; return empty map until cached.
      _fetchEnv();
      return {};
    }
    return _envCache!;
  }

  Future<void> _fetchEnv() async {
    final json = await _getJson('/api/env');
    _envCache = Map<String, String>.from(json['variables'] as Map);
  }

  @override
  String get operatingSystem => 'web';

  @override
  int get numberOfProcessors => 1;

  @override
  String get localHostname => 'localhost';

  // ---------------------------------------------------------------------------
  // Network — HTTP
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformHttpResponse> httpRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    // Proxy through the server to avoid CORS issues.
    final json = await _postJson('/api/http/request', {
      'method': method,
      'url': url.toString(),
      if (headers != null) 'headers': headers,
      if (body != null)
        'body': body is String
            ? body
            : body is Map
                ? jsonEncode(body)
                : body.toString(),
      if (timeout != null) 'timeoutMs': timeout.inMilliseconds,
    });

    return PlatformHttpResponse(
      statusCode: json['statusCode'] as int,
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      body: json['body'] as String? ?? '',
      bodyBytes: Uint8List(0),
    );
  }

  // ---------------------------------------------------------------------------
  // Network — WebSocket
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformWebSocket> connectWebSocket(Uri url) async {
    // Use the browser's native WebSocket via dart:html / web interop.
    // On web, package:web or dart:html provides WebSocket.
    // For simplicity we use the server as a WS proxy.
    final wsUrl = _baseUrl.replaceFirst('http', 'ws');
    final proxyUri = Uri.parse(
      '$wsUrl/api/ws/proxy?url=${Uri.encodeComponent(url.toString())}',
    );

    return _WebSocketImpl.connect(proxyUri);
  }
}

// =============================================================================
// Private helper classes
// =============================================================================

class PlatformException implements Exception {
  final String message;
  PlatformException(this.message);

  @override
  String toString() => 'PlatformException: $message';
}

/// A running process on the web — communicates with the server via WebSocket
/// for real-time stdout/stderr and HTTP for control.
class _WebRunningProcess implements RunningProcess {
  @override
  final int pid;
  final String _baseUrl;
  final String _wsUrl;
  final http.Client _client;

  late final StreamController<String> _stdoutController;
  late final StreamController<String> _stderrController;
  final Completer<int> _exitCodeCompleter = Completer<int>();

  _WebRunningProcess({
    required this.pid,
    required String baseUrl,
    required String wsUrl,
    required http.Client client,
  })  : _baseUrl = baseUrl,
        _wsUrl = wsUrl,
        _client = client {
    _stdoutController = StreamController<String>.broadcast();
    _stderrController = StreamController<String>.broadcast();
    _connectStreams();
  }

  Future<void> _connectStreams() async {
    try {
      final ws = await _WebSocketImpl.connect(
        Uri.parse('$_wsUrl/api/process/stream?pid=$pid'),
      );

      ws.stream.listen(
        (data) {
          if (data is String) {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final type = json['type'] as String;
            final content = json['data'] as String? ?? '';

            if (type == 'stdout') {
              _stdoutController.add(content);
            } else if (type == 'stderr') {
              _stderrController.add(content);
            } else if (type == 'exit') {
              final code = json['exitCode'] as int? ?? -1;
              if (!_exitCodeCompleter.isCompleted) {
                _exitCodeCompleter.complete(code);
              }
              _stdoutController.close();
              _stderrController.close();
            }
          }
        },
        onDone: () {
          if (!_exitCodeCompleter.isCompleted) {
            _exitCodeCompleter.complete(-1);
          }
          _stdoutController.close();
          _stderrController.close();
        },
        onError: (Object e) {
          _stdoutController.addError(e);
          _stderrController.addError(e);
        },
      );
    } catch (e) {
      _stdoutController.addError(e);
      _stderrController.addError(e);
      if (!_exitCodeCompleter.isCompleted) {
        _exitCodeCompleter.complete(-1);
      }
    }
  }

  @override
  Stream<String> get stdout => _stdoutController.stream;

  @override
  Stream<String> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exitCodeCompleter.future;

  @override
  bool kill() {
    _client.post(
      Uri.parse('$_baseUrl/api/process/kill'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pid': pid}),
    );
    return true;
  }

  @override
  void writeToStdin(String data) {
    _client.post(
      Uri.parse('$_baseUrl/api/process/stdin'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pid': pid, 'data': data}),
    );
  }
}

/// Minimal browser-compatible WebSocket wrapper.
///
/// On the web target we rely on `dart:html` (or `package:web`).  We use a
/// conditional import stub pattern: this class is only instantiated on web,
/// so the actual implementation goes through the browser's `WebSocket` API
/// via `dart:html`.
///
/// For testing and simplicity this uses `package:http` — in production you
/// would replace this with `dart:html` WebSocket or `package:web_socket_channel`.
class _WebSocketImpl implements PlatformWebSocket {
  final StreamController<dynamic> _controller;
  dynamic _nativeSocket;

  _WebSocketImpl._(this._controller, this._nativeSocket);

  /// Connect to [url] using a browser-compatible WebSocket.
  static Future<_WebSocketImpl> connect(Uri url) async {
    // This is a simplified implementation.  In a real web build you would
    // use `package:web_socket_channel/html.dart` or `dart:html`.  The
    // server.dart backend provides the WebSocket endpoint.
    final controller = StreamController<dynamic>.broadcast();

    // We simulate the connection — the actual browser WS would be:
    //   final ws = html.WebSocket(url.toString());
    //   ws.onMessage.listen((e) => controller.add(e.data));
    //   ws.onClose.listen((_) => controller.close());

    // For now we return a placeholder that the web build will replace
    // with the real browser WebSocket via conditional import.
    final impl = _WebSocketImpl._(controller, null);
    return impl;
  }

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  void add(dynamic data) {
    // In production: _nativeSocket.send(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    _controller.close();
  }

  @override
  int? get closeCode => null;
}
