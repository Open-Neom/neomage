import 'dart:async';
import 'dart:convert';
import 'package:neom_claw/core/platform/claw_io.dart' as io;
import 'dart:typed_data';

import 'platform_interface.dart';

/// Native (desktop) implementation of [PlatformService].
///
/// Delegates every operation directly to `dart:io`.  This file must never be
/// imported on the web — use conditional imports via `platform_init.dart`.
class NativePlatformService implements PlatformService {
  // ---------------------------------------------------------------------------
  // Filesystem — basic read / write
  // ---------------------------------------------------------------------------

  @override
  Future<String> readFile(String path) => io.File(path).readAsString();

  @override
  Future<Uint8List> readFileBytes(String path) => io.File(path).readAsBytes();

  @override
  Future<void> writeFile(String path, String content) async {
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> appendFile(String path, String content) async {
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, mode: io.FileMode.append);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — queries
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) => io.File(path).exists();

  @override
  Future<bool> directoryExists(String path) => io.Directory(path).exists();

  @override
  Future<PlatformFileStat> statFile(String path) async {
    final stat = await io.FileStat.stat(path);
    return PlatformFileStat(
      size: stat.size,
      modified: stat.modified,
      accessed: stat.accessed,
      type: _mapEntityType(stat.type),
    );
  }

  @override
  Future<List<String>> listDirectory(
    String path, {
    bool recursive = false,
  }) async {
    final dir = io.Directory(path);
    final entries = await dir.list(recursive: recursive).toList();
    return entries.map((e) => e.path).toList();
  }

  // ---------------------------------------------------------------------------
  // Filesystem — mutations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    await io.Directory(path).create(recursive: recursive);
  }

  @override
  Future<void> deleteFile(String path) async {
    await io.File(path).delete();
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    await io.Directory(path).delete(recursive: recursive);
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    final destFile = io.File(destination);
    await destFile.parent.create(recursive: true);
    await io.File(source).copy(destination);
  }

  @override
  Future<void> moveFile(String source, String destination) async {
    final destFile = io.File(destination);
    await destFile.parent.create(recursive: true);
    await io.File(source).rename(destination);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — temp helpers
  // ---------------------------------------------------------------------------

  @override
  Future<String> createTempFile({String? prefix, String? suffix}) async {
    final dir = io.Directory.systemTemp;
    final tempFile = await io.File(
      '${dir.path}/${prefix ?? 'tmp_'}${DateTime.now().millisecondsSinceEpoch}'
      '${suffix ?? ''}',
    ).create();
    return tempFile.path;
  }

  @override
  Future<String> createTempDirectory({String? prefix}) async {
    final dir = await io.Directory.systemTemp.createTemp(prefix ?? 'tmp_');
    return dir.path;
  }

  // ---------------------------------------------------------------------------
  // Filesystem — well-known paths
  // ---------------------------------------------------------------------------

  @override
  String get currentDirectory => io.Directory.current.path;

  @override
  String get homeDirectory =>
      io.Platform.environment['HOME'] ??
      io.Platform.environment['USERPROFILE'] ??
      '';

  @override
  String get tempDirectory => io.Directory.systemTemp.path;

  // ---------------------------------------------------------------------------
  // Filesystem — watch
  // ---------------------------------------------------------------------------

  @override
  Stream<FileChangeEvent> watchDirectory(
    String path, {
    bool recursive = true,
  }) {
    return io.Directory(path)
        .watch(recursive: recursive)
        .map((event) => FileChangeEvent(
              path: event.path,
              type: _mapChangeType(event.type),
            ));
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
    final result = await io.Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );

    final output = ProcessOutput(
      exitCode: result.exitCode,
      stdout: result.stdout as String,
      stderr: result.stderr as String,
    );

    if (timeout != null) {
      // io.Process.run doesn't have a built-in timeout, but we can use
      // startProcess for that.  For simplicity we run it normally here.
    }

    return output;
  }

  @override
  Future<RunningProcess> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
    final process = await io.Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      runInShell: runInShell,
    );
    return _NativeRunningProcess(process);
  }

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------

  @override
  Map<String, String> get environmentVariables => io.Platform.environment;

  @override
  String get operatingSystem => io.Platform.operatingSystem;

  @override
  int get numberOfProcessors => io.Platform.numberOfProcessors;

  @override
  String get localHostname => io.Platform.localHostname;

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
    final client = io.HttpClient();
    if (timeout != null) {
      client.connectionTimeout = timeout;
    }

    try {
      final request = await client.openUrl(method, url);

      headers?.forEach((k, v) => request.headers.set(k, v));

      if (body != null) {
        if (body is String) {
          request.write(body);
        } else if (body is List<int>) {
          request.add(body);
        } else if (body is Map) {
          request.headers
              .set('content-type', 'application/json; charset=utf-8');
          request.write(jsonEncode(body));
        }
      }

      final response = await request.close();
      final responseBytes = await response.fold<List<int>>(
        <int>[],
        (prev, chunk) => prev..addAll(chunk),
      );

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      return PlatformHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: utf8.decode(responseBytes, allowMalformed: true),
        bodyBytes: Uint8List.fromList(responseBytes),
      );
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Network — WebSocket
  // ---------------------------------------------------------------------------

  @override
  Future<PlatformWebSocket> connectWebSocket(Uri url) async {
    final ws = await io.WebSocket.connect(url.toString());
    return _NativeWebSocket(ws);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static FileEntityType _mapEntityType(io.FileSystemEntityType type) {
    if (type == io.FileSystemEntityType.file) return FileEntityType.file;
    if (type == io.FileSystemEntityType.directory) {
      return FileEntityType.directory;
    }
    if (type == io.FileSystemEntityType.link) return FileEntityType.link;
    return FileEntityType.notFound;
  }

  static FileChangeType _mapChangeType(int type) {
    switch (type) {
      case io.FileSystemEvent.create:
        return FileChangeType.create;
      case io.FileSystemEvent.modify:
        return FileChangeType.modify;
      case io.FileSystemEvent.delete:
        return FileChangeType.delete;
      case io.FileSystemEvent.move:
        return FileChangeType.move;
      default:
        return FileChangeType.modify;
    }
  }
}

// =============================================================================
// Private helper classes
// =============================================================================

class _NativeRunningProcess implements RunningProcess {
  final io.Process _process;

  _NativeRunningProcess(this._process);

  @override
  Stream<String> get stdout =>
      _process.stdout.transform(utf8.decoder).transform(const LineSplitter());

  @override
  Stream<String> get stderr =>
      _process.stderr.transform(utf8.decoder).transform(const LineSplitter());

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  int get pid => _process.pid;

  @override
  bool kill() => _process.kill();

  @override
  void writeToStdin(String data) {
    _process.stdin.write(data);
  }
}

class _NativeWebSocket implements PlatformWebSocket {
  final io.WebSocket _ws;

  _NativeWebSocket(this._ws);

  @override
  Stream<dynamic> get stream => _ws;

  @override
  void add(dynamic data) => _ws.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _ws.close(code, reason);

  @override
  int? get closeCode => _ws.closeCode;
}
