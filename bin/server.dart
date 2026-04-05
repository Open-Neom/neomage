// Local API server for neomage web mode.
//
// Run with:
//   dart run bin/server.dart
//
// Exposes filesystem, process, environment, and network operations on
// localhost:3219 so that the web frontend can call them via REST / WebSocket.

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

const int _port = 3219;

void _log(String message) => developer.log(message, name: 'neomage');

// ---------------------------------------------------------------------------
// Active processes — keyed by PID
// ---------------------------------------------------------------------------
final Map<int, Process> _activeProcesses = {};

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main() async {
  final server = await HttpServer.bind('127.0.0.1', _port);
  _log('neomage local server running on http://localhost:$_port');
  _log('Press Ctrl+C to stop.');

  await for (final request in server) {
    try {
      await _handleRequest(request);
    } catch (e, st) {
      stderr.writeln('Error handling ${request.uri}: $e\n$st');
      _sendError(request.response, 500, e.toString());
    }
  }
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

Future<void> _handleRequest(HttpRequest request) async {
  _addCorsHeaders(request.response);

  // Handle CORS preflight.
  if (request.method == 'OPTIONS') {
    request.response.statusCode = 204;
    await request.response.close();
    return;
  }

  final path = request.uri.path;

  // --- Filesystem ---
  if (path == '/api/fs/read') return _fsRead(request);
  if (path == '/api/fs/read-bytes') return _fsReadBytes(request);
  if (path == '/api/fs/write') return _fsWrite(request);
  if (path == '/api/fs/write-bytes') return _fsWriteBytes(request);
  if (path == '/api/fs/append') return _fsAppend(request);
  if (path == '/api/fs/exists') return _fsExists(request);
  if (path == '/api/fs/stat') return _fsStat(request);
  if (path == '/api/fs/list') return _fsList(request);
  if (path == '/api/fs/mkdir') return _fsMkdir(request);
  if (path == '/api/fs/delete') return _fsDelete(request);
  if (path == '/api/fs/copy') return _fsCopy(request);
  if (path == '/api/fs/move') return _fsMove(request);
  if (path == '/api/fs/temp-file') return _fsTempFile(request);
  if (path == '/api/fs/temp-dir') return _fsTempDir(request);
  if (path == '/api/fs/watch') return _fsWatch(request);

  // --- Process ---
  if (path == '/api/process/run') return _processRun(request);
  if (path == '/api/process/start') return _processStart(request);
  if (path == '/api/process/kill') return _processKill(request);
  if (path == '/api/process/stdin') return _processStdin(request);
  if (path == '/api/process/stream') return _processStream(request);

  // --- Environment ---
  if (path == '/api/env') return _env(request);
  if (path == '/api/env/paths') return _envPaths(request);

  // --- HTTP proxy ---
  if (path == '/api/http/request') return _httpProxy(request);

  // --- WebSocket proxy ---
  if (path == '/api/ws/proxy') return _wsProxy(request);

  // --- Health ---
  if (path == '/api/health') {
    return _sendJson(request.response, {'status': 'ok'});
  }

  _sendError(request.response, 404, 'Not found: $path');
}

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------

void _addCorsHeaders(HttpResponse response) {
  response.headers.set('Access-Control-Allow-Origin', '*');
  response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  response.headers.set(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization',
  );
}

// ---------------------------------------------------------------------------
// JSON helpers
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
  final body = await utf8.decoder.bind(request).join();
  if (body.isEmpty) return {};
  return jsonDecode(body) as Map<String, dynamic>;
}

void _sendJson(HttpResponse response, Object data, [int statusCode = 200]) {
  response
    ..statusCode = statusCode
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(data));
  response.close();
}

void _sendError(HttpResponse response, int code, String message) {
  _sendJson(response, {'error': message}, code);
}

String _queryParam(HttpRequest request, String name) {
  final value = request.uri.queryParameters[name];
  if (value == null || value.isEmpty) {
    throw ArgumentError('Missing query parameter: $name');
  }
  return value;
}

// ===========================================================================
// Filesystem handlers
// ===========================================================================

Future<void> _fsRead(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final content = await File(path).readAsString();
  _sendJson(request.response, {'content': content});
}

Future<void> _fsReadBytes(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final bytes = await File(path).readAsBytes();
  request.response
    ..statusCode = 200
    ..headers.contentType = ContentType.binary
    ..add(bytes);
  await request.response.close();
}

Future<void> _fsWrite(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final path = body['path'] as String;
  final content = body['content'] as String;
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsWriteBytes(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final bytes = await request.fold<List<int>>(
    <int>[],
    (prev, chunk) => prev..addAll(chunk),
  );
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsAppend(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final path = body['path'] as String;
  final content = body['content'] as String;
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(content, mode: FileMode.append);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsExists(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final type = request.uri.queryParameters['type'] ?? 'file';
  bool exists;
  if (type == 'directory') {
    exists = await Directory(path).exists();
  } else {
    exists = await File(path).exists();
  }
  _sendJson(request.response, {'exists': exists});
}

Future<void> _fsStat(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final stat = await FileStat.stat(path);
  _sendJson(request.response, {
    'size': stat.size,
    'modified': stat.modified.toIso8601String(),
    'accessed': stat.accessed.toIso8601String(),
    'type': _entityTypeName(stat.type),
  });
}

String _entityTypeName(FileSystemEntityType type) {
  if (type == FileSystemEntityType.file) return 'file';
  if (type == FileSystemEntityType.directory) return 'directory';
  if (type == FileSystemEntityType.link) return 'link';
  return 'notFound';
}

Future<void> _fsList(HttpRequest request) async {
  final path = _queryParam(request, 'path');
  final recursive = request.uri.queryParameters['recursive'] == 'true';
  final dir = Directory(path);
  final entries = await dir
      .list(recursive: recursive)
      .map((e) => e.path)
      .toList();
  _sendJson(request.response, {'entries': entries});
}

Future<void> _fsMkdir(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final path = body['path'] as String;
  final recursive = body['recursive'] as bool? ?? true;
  await Directory(path).create(recursive: recursive);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsDelete(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final path = body['path'] as String;
  final type = body['type'] as String? ?? 'file';
  if (type == 'directory') {
    final recursive = body['recursive'] as bool? ?? false;
    await Directory(path).delete(recursive: recursive);
  } else {
    await File(path).delete();
  }
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsCopy(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final source = body['source'] as String;
  final destination = body['destination'] as String;
  final destFile = File(destination);
  await destFile.parent.create(recursive: true);
  await File(source).copy(destination);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsMove(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final source = body['source'] as String;
  final destination = body['destination'] as String;
  final destFile = File(destination);
  await destFile.parent.create(recursive: true);
  await File(source).rename(destination);
  _sendJson(request.response, {'ok': true});
}

Future<void> _fsTempFile(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final prefix = body['prefix'] as String? ?? 'tmp_';
  final suffix = body['suffix'] as String? ?? '';
  final tempFile = await File(
    '${Directory.systemTemp.path}/$prefix${DateTime.now().millisecondsSinceEpoch}$suffix',
  ).create();
  _sendJson(request.response, {'path': tempFile.path});
}

Future<void> _fsTempDir(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final prefix = body['prefix'] as String? ?? 'tmp_';
  final dir = await Directory.systemTemp.createTemp(prefix);
  _sendJson(request.response, {'path': dir.path});
}

Future<void> _fsWatch(HttpRequest request) async {
  // Upgrade to WebSocket for real-time file watching.
  final path = _queryParam(request, 'path');
  final recursive = request.uri.queryParameters['recursive'] != 'false';

  final ws = await WebSocketTransformer.upgrade(request);
  _log('[watch] Watching $path (recursive=$recursive)');

  final subscription = Directory(path).watch(recursive: recursive).listen((
    event,
  ) {
    final changeType = _fileChangeTypeName(event.type);
    ws.add(jsonEncode({'path': event.path, 'type': changeType}));
  });

  ws.listen(
    (_) {},
    onDone: () {
      subscription.cancel();
      _log('[watch] Stopped watching $path');
    },
  );
}

String _fileChangeTypeName(int type) {
  switch (type) {
    case FileSystemEvent.create:
      return 'create';
    case FileSystemEvent.modify:
      return 'modify';
    case FileSystemEvent.delete:
      return 'delete';
    case FileSystemEvent.move:
      return 'move';
    default:
      return 'modify';
  }
}

// ===========================================================================
// Process handlers
// ===========================================================================

Future<void> _processRun(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final executable = body['executable'] as String;
  final arguments = List<String>.from(body['arguments'] as List? ?? []);
  final workingDirectory = body['workingDirectory'] as String?;
  final environment = body['environment'] != null
      ? Map<String, String>.from(body['environment'] as Map)
      : null;
  final timeoutMs = body['timeoutMs'] as int?;
  final runInShell = body['runInShell'] as bool? ?? false;

  _log('[process] run: $executable ${arguments.join(' ')}');

  final result =
      await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: runInShell,
      ).timeout(
        Duration(milliseconds: timeoutMs ?? 300000), // Default 5 min timeout
        onTimeout: () => ProcessResult(-1, 124, '', 'Process timed out'),
      );

  _sendJson(request.response, {
    'exitCode': result.exitCode,
    'stdout': result.stdout as String,
    'stderr': result.stderr as String,
  });
}

Future<void> _processStart(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final executable = body['executable'] as String;
  final arguments = List<String>.from(body['arguments'] as List? ?? []);
  final workingDirectory = body['workingDirectory'] as String?;
  final environment = body['environment'] != null
      ? Map<String, String>.from(body['environment'] as Map)
      : null;
  final runInShell = body['runInShell'] as bool? ?? false;

  _log('[process] start: $executable ${arguments.join(' ')}');

  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: runInShell,
  );

  _activeProcesses[process.pid] = process;

  // Auto-cleanup when process exits.
  process.exitCode.then((_) {
    _activeProcesses.remove(process.pid);
    _log('[process] pid=${process.pid} exited');
  });

  _sendJson(request.response, {'pid': process.pid});
}

Future<void> _processKill(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final pid = body['pid'] as int;
  final process = _activeProcesses[pid];
  if (process != null) {
    process.kill();
    _sendJson(request.response, {'ok': true});
  } else {
    _sendError(request.response, 404, 'No active process with pid=$pid');
  }
}

Future<void> _processStdin(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final pid = body['pid'] as int;
  final data = body['data'] as String;
  final process = _activeProcesses[pid];
  if (process != null) {
    process.stdin.write(data);
    _sendJson(request.response, {'ok': true});
  } else {
    _sendError(request.response, 404, 'No active process with pid=$pid');
  }
}

Future<void> _processStream(HttpRequest request) async {
  final pid = int.parse(_queryParam(request, 'pid'));
  final process = _activeProcesses[pid];

  if (process == null) {
    _sendError(request.response, 404, 'No active process with pid=$pid');
    return;
  }

  final ws = await WebSocketTransformer.upgrade(request);
  _log('[process] streaming pid=$pid');

  final stdoutSub = process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        ws.add(jsonEncode({'type': 'stdout', 'data': line}));
      });

  final stderrSub = process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((line) {
        ws.add(jsonEncode({'type': 'stderr', 'data': line}));
      });

  process.exitCode.then((code) {
    ws.add(jsonEncode({'type': 'exit', 'exitCode': code}));
    ws.close();
  });

  ws.listen(
    (data) {
      // Client can send stdin data via the WebSocket too.
      if (data is String) {
        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          if (json['type'] == 'stdin') {
            process.stdin.write(json['data'] as String);
          }
        } catch (_) {}
      }
    },
    onDone: () {
      stdoutSub.cancel();
      stderrSub.cancel();
    },
  );
}

// ===========================================================================
// Environment handlers
// ===========================================================================

Future<void> _env(HttpRequest request) async {
  _sendJson(request.response, {
    'variables': Platform.environment,
    'operatingSystem': Platform.operatingSystem,
    'numberOfProcessors': Platform.numberOfProcessors,
    'localHostname': Platform.localHostname,
  });
}

Future<void> _envPaths(HttpRequest request) async {
  _sendJson(request.response, {
    'currentDirectory': Directory.current.path,
    'homeDirectory':
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '',
    'tempDirectory': Directory.systemTemp.path,
  });
}

// ===========================================================================
// HTTP proxy handler
// ===========================================================================

Future<void> _httpProxy(HttpRequest request) async {
  final body = await _readJsonBody(request);
  final method = body['method'] as String;
  final url = Uri.parse(body['url'] as String);
  final reqHeaders = body['headers'] != null
      ? Map<String, String>.from(body['headers'] as Map)
      : <String, String>{};
  final reqBody = body['body'] as String?;
  final timeoutMs = body['timeoutMs'] as int?;

  _log('[http] $method $url');

  final client = HttpClient();
  if (timeoutMs != null) {
    client.connectionTimeout = Duration(milliseconds: timeoutMs);
  }

  try {
    final outRequest = await client.openUrl(method, url);
    reqHeaders.forEach((k, v) => outRequest.headers.set(k, v));

    if (reqBody != null && reqBody.isNotEmpty) {
      outRequest.write(reqBody);
    }

    final outResponse = await outRequest.close();
    final responseBytes = await outResponse.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );

    final responseHeaders = <String, String>{};
    outResponse.headers.forEach((name, values) {
      responseHeaders[name] = values.join(', ');
    });

    _sendJson(request.response, {
      'statusCode': outResponse.statusCode,
      'headers': responseHeaders,
      'body': utf8.decode(responseBytes, allowMalformed: true),
    });
  } finally {
    client.close();
  }
}

// ===========================================================================
// WebSocket proxy handler
// ===========================================================================

Future<void> _wsProxy(HttpRequest request) async {
  final targetUrl = _queryParam(request, 'url');
  _log('[ws] proxy to $targetUrl');

  final clientWs = await WebSocketTransformer.upgrade(request);
  final targetWs = await WebSocket.connect(targetUrl);

  // Bidirectional pipe.
  targetWs.listen(
    (data) => clientWs.add(data),
    onDone: () => clientWs.close(),
    onError: (Object e) => clientWs.close(),
  );

  clientWs.listen(
    (data) => targetWs.add(data),
    onDone: () => targetWs.close(),
    onError: (Object e) => targetWs.close(),
  );
}
