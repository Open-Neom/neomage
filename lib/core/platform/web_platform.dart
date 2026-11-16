import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:neomage/utils/security/neomage_network_guard.dart';

import 'platform_interface.dart';
import 'web_socket_adapter_stub.dart'
    if (dart.library.js_interop) 'web_socket_adapter_web.dart'
    as ws_adapter;

/// Web implementation of [PlatformService].
///
/// Every call is proxied to a local REST API server at [_baseUrl] (defaults to
/// `http://localhost:3219`).  The server is expected to be running alongside
/// the web frontend — see `bin/server.dart`.
///
/// This file must never import `dart:io`.
class WebPlatformService implements PlatformService {
  static const int maxJsonResponseBytes = 16 * 1024 * 1024; // 16 MiB
  static const int maxBinaryResponseBytes = 64 * 1024 * 1024; // 64 MiB
  static const Duration _defaultRequestTimeout = Duration(seconds: 30);

  final String _baseUrl;
  final String _wsBaseUrl;
  final http.Client _client;

  WebPlatformService({
    String baseUrl = 'http://localhost:3219',
    http.Client? client,
  }) : _baseUrl = _normalizeValidBaseUrl(baseUrl),
       _wsBaseUrl = _deriveWsBaseUrl(_normalizeValidBaseUrl(baseUrl)),
       _client = client ?? http.Client();

  /// Validates and normalizes the backend REST server base URL, allowing
  /// `https://` or loopback/RFC1918 LAN `http://` while rejecting cloud IMDS,
  /// userinfo, query/fragment, `/..`, and `%5c`.
  static Uri? validateBackendBaseUri(String rawBaseUrl) {
    var trimmed = rawBaseUrl.trim();
    if (trimmed.isEmpty ||
        trimmed.contains(r'\') ||
        trimmed.toLowerCase().contains('%5c') ||
        trimmed.contains('/..') ||
        trimmed.toLowerCase().contains('%2e%2e')) {
      return null;
    }
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.hasQuery || uri.hasFragment) return null;
    if (uri.pathSegments.contains('..')) return null;
    final ok = NeomageNetworkGuard.isSafeEndpointUri(
      uri,
      allowLoopbackInsecure: true,
      allowPrivateLanHttp: true,
      allowPublicInsecure: false,
      secureSchemes: const <String>{'https'},
      insecureSchemes: const <String>{'http'},
    );
    return ok ? uri : null;
  }

  static String _normalizeValidBaseUrl(String rawBaseUrl) {
    final uri = validateBackendBaseUri(rawBaseUrl);
    if (uri == null) {
      throw ArgumentError.value(
        rawBaseUrl,
        'baseUrl',
        'Rejected unsafe WebPlatformService backend baseUrl',
      );
    }
    var normalized = uri.toString();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  static String _deriveWsBaseUrl(String normalizedBaseUrl) {
    final uri = Uri.parse(normalizedBaseUrl);
    final wsScheme = uri.scheme.toLowerCase() == 'https' ? 'wss' : 'ws';
    var wsUrl = uri.replace(scheme: wsScheme).toString();
    while (wsUrl.endsWith('/')) {
      wsUrl = wsUrl.substring(0, wsUrl.length - 1);
    }
    return wsUrl;
  }

  static void _assertSafePath(String path) {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      throw ArgumentError('Rejected unsafe filesystem path');
    }
    if (NeomageNetworkGuard.isProtectedSystemOrCredentialPath(path)) {
      throw PlatformException(
        'Access to protected system or credential path is denied',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Uri _uri(String path, [Map<String, String>? queryParams]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: queryParams);

  Future<(int statusCode, Uint8List bytes)> _sendBounded(
    String method,
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    int maxBytes = maxJsonResponseBytes,
    Duration timeout = _defaultRequestTimeout,
  }) async {
    final request = http.Request(method, uri)..followRedirects = false;
    headers?.forEach((k, v) {
      if (NeomageNetworkGuard.isValidHeaderName(k)) {
        request.headers[k] = NeomageNetworkGuard.sanitizeHeaderValue(v);
      }
    });
    if (body != null) {
      if (body is String) {
        request.body = body;
      } else if (body is List<int>) {
        request.bodyBytes = body;
      }
    }
    final streamed = await _client.send(request).timeout(timeout);
    final code = streamed.statusCode;
    if (code >= 300 && code < 400) {
      await streamed.stream.drain<void>().catchError((_) {});
      throw PlatformException('HTTP redirect ($code) rejected on backend call');
    }
    final contentLength = streamed.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      await streamed.stream.drain<void>().catchError((_) {});
      throw PlatformException('Backend response exceeded $maxBytes bytes');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream.timeout(timeout)) {
      if (builder.length + chunk.length > maxBytes) {
        throw PlatformException('Backend response exceeded $maxBytes bytes');
      }
      builder.add(chunk);
    }
    return (code, builder.takeBytes());
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final (statusCode, bytes) = await _sendBounded('GET', _uri(path, query));
    final bodyText = utf8.decode(bytes, allowMalformed: true);
    if (statusCode != 200) {
      throw PlatformException(
        'GET $path failed: $statusCode '
        '${NeomageNetworkGuard.sanitizeApiErrorBody(bodyText)}',
      );
    }
    return jsonDecode(bodyText) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final (statusCode, bytes) = await _sendBounded(
      'POST',
      _uri(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final bodyText = utf8.decode(bytes, allowMalformed: true);
    if (statusCode != 200) {
      throw PlatformException(
        'POST $path failed: $statusCode '
        '${NeomageNetworkGuard.sanitizeApiErrorBody(bodyText)}',
      );
    }
    return jsonDecode(bodyText) as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — basic read / write
  // ---------------------------------------------------------------------------

  @override
  Future<String> readFile(String path) async {
    _assertSafePath(path);
    final json = await _getJson('/api/fs/read', {'path': path});
    return json['content'] as String;
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    _assertSafePath(path);
    final (statusCode, bytes) = await _sendBounded(
      'GET',
      _uri('/api/fs/read-bytes', {'path': path}),
      maxBytes: maxBinaryResponseBytes,
    );
    if (statusCode != 200) {
      throw PlatformException(
        'GET /api/fs/read-bytes failed: $statusCode',
      );
    }
    return bytes;
  }

  @override
  Future<void> writeFile(String path, String content) async {
    _assertSafePath(path);
    await _postJson('/api/fs/write', {'path': path, 'content': content});
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    _assertSafePath(path);
    final (statusCode, _) = await _sendBounded(
      'POST',
      _uri('/api/fs/write-bytes', {'path': path}),
      headers: const {'Content-Type': 'application/octet-stream'},
      body: bytes,
    );
    if (statusCode != 200) {
      throw PlatformException(
        'POST /api/fs/write-bytes failed: $statusCode',
      );
    }
  }

  @override
  Future<void> appendFile(String path, String content) async {
    _assertSafePath(path);
    await _postJson('/api/fs/append', {'path': path, 'content': content});
  }

  // ---------------------------------------------------------------------------
  // Filesystem — queries
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) async {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      return false;
    }
    final json = await _getJson('/api/fs/exists', {
      'path': path,
      'type': 'file',
    });
    return json['exists'] as bool;
  }

  @override
  Future<bool> directoryExists(String path) async {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      return false;
    }
    final json = await _getJson('/api/fs/exists', {
      'path': path,
      'type': 'directory',
    });
    return json['exists'] as bool;
  }

  @override
  Future<PlatformFileStat> statFile(String path) async {
    _assertSafePath(path);
    final json = await _getJson('/api/fs/stat', {'path': path});
    return PlatformFileStat.fromJson(json);
  }

  @override
  Future<List<String>> listDirectory(
    String path, {
    bool recursive = false,
  }) async {
    _assertSafePath(path);
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
    _assertSafePath(path);
    await _postJson('/api/fs/mkdir', {'path': path, 'recursive': recursive});
  }

  @override
  Future<void> deleteFile(String path) async {
    _assertSafePath(path);
    await _postJson('/api/fs/delete', {'path': path, 'type': 'file'});
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    _assertSafePath(path);
    await _postJson('/api/fs/delete', {
      'path': path,
      'type': 'directory',
      'recursive': recursive,
    });
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    _assertSafePath(source);
    _assertSafePath(destination);
    await _postJson('/api/fs/copy', {
      'source': source,
      'destination': destination,
    });
  }

  @override
  Future<void> moveFile(String source, String destination) async {
    _assertSafePath(source);
    _assertSafePath(destination);
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
      'prefix': ?prefix,
      'suffix': ?suffix,
    });
    return json['path'] as String;
  }

  @override
  Future<String> createTempDirectory({String? prefix}) async {
    final json = await _postJson('/api/fs/temp-dir', {'prefix': ?prefix});
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
  Stream<FileChangeEvent> watchDirectory(String path, {bool recursive = true}) {
    _assertSafePath(path);
    // File watching on web is done via a WebSocket on the server.
    final controller = StreamController<FileChangeEvent>();
    final uri = Uri.parse(
      '$_wsBaseUrl/api/fs/watch?path=${Uri.encodeComponent(path)}'
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
      final ws = await _WebSocketImpl.connect(uri);
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

  static void _validateProcessArgs(
    String executable,
    List<String> arguments,
    String? workingDirectory,
  ) {
    if (executable.isEmpty ||
        executable.contains('\x00') ||
        arguments.any((a) => a.contains('\x00'))) {
      throw ArgumentError('Process executable/arguments contain NUL bytes');
    }
    if (workingDirectory != null &&
        (workingDirectory.contains('\x00') ||
            workingDirectory.startsWith('//') ||
            workingDirectory.startsWith(r'\\'))) {
      throw ArgumentError('Rejected unsafe workingDirectory');
    }
  }

  @override
  Future<ProcessOutput> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool runInShell = false,
  }) async {
    _validateProcessArgs(executable, arguments, workingDirectory);
    final cleanEnv = environment != null
        ? NeomageNetworkGuard.sanitizeSubprocessEnv(const <String, String>{}, environment)
        : null;
    final json = await _postJson('/api/process/run', {
      'executable': executable,
      'arguments': arguments,
      'workingDirectory': ?workingDirectory,
      'environment': ?cleanEnv,
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
    _validateProcessArgs(executable, arguments, workingDirectory);
    final cleanEnv = environment != null
        ? NeomageNetworkGuard.sanitizeSubprocessEnv(const <String, String>{}, environment)
        : null;
    // Start the process on the server and get a process ID back.
    final json = await _postJson('/api/process/start', {
      'executable': executable,
      'arguments': arguments,
      'workingDirectory': ?workingDirectory,
      'environment': ?cleanEnv,
      'runInShell': runInShell,
    });

    final pid = json['pid'] as int;

    return _WebRunningProcess(
      pid: pid,
      baseUrl: _baseUrl,
      wsUrl: _wsBaseUrl,
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
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      url,
      allowLoopbackHttp: true,
      allowPrivateLanHttp: true,
    )) {
      throw ArgumentError('Rejected unsafe HTTP endpoint URI: $url');
    }
    Map<String, String>? safeHeaders;
    if (headers != null) {
      safeHeaders = <String, String>{};
      headers.forEach((k, v) {
        if (NeomageNetworkGuard.isValidHeaderName(k)) {
          safeHeaders![k] = NeomageNetworkGuard.sanitizeHeaderValue(v);
        }
      });
    }
    // Proxy through the server to avoid CORS issues.
    final json = await _postJson('/api/http/request', {
      'method': method,
      'url': url.toString(),
      'headers': ?safeHeaders,
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
    if (!NeomageNetworkGuard.isSafeWebSocketEndpointUri(
      url,
      allowLoopbackWs: true,
      allowPrivateLanWs: true,
    )) {
      throw ArgumentError('Rejected unsafe WebSocket URI: $url');
    }
    final proxyUri = Uri.parse(
      '$_wsBaseUrl/api/ws/proxy?url=${Uri.encodeComponent(url.toString())}',
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
  }) : _baseUrl = baseUrl,
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
/// Browser-compatible [PlatformWebSocket] backed by `package:web` `WebSocket`
/// on Web/Wasm and `web_socket_channel` when imported in VM tests.
class _WebSocketImpl implements PlatformWebSocket {
  final ws_adapter.BrowserWebSocketAdapter _delegate;

  _WebSocketImpl._(this._delegate);

  /// Connect to [url] using a real browser `WebSocket` adapter.
  static Future<_WebSocketImpl> connect(Uri url) async {
    final delegate = await ws_adapter.BrowserWebSocketAdapter.connect(url);
    return _WebSocketImpl._(delegate);
  }

  @override
  Stream<dynamic> get stream => _delegate.stream;

  @override
  void add(dynamic data) {
    _delegate.add(data);
  }

  @override
  Future<void> close([int? code, String? reason]) async {
    await _delegate.close(code, reason);
  }

  @override
  int? get closeCode => _delegate.closeCode;
}
