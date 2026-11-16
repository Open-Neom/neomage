import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:neomage/core/platform/neomage_io.dart' as io;
import 'package:neomage/utils/security/neomage_network_guard.dart';
import 'dart:typed_data';

import 'platform_interface.dart';

/// Native (desktop) implementation of [PlatformService].
///
/// Delegates every operation directly to `dart:io`.  This file must never be
/// imported on the web — use conditional imports via `platform_init.dart`.
class NativePlatformService implements PlatformService {
  static const int _maxProcessOutputBytes = 16 * 1024 * 1024; // 16 MiB
  static const int _maxHttpResponseBytes = 16 * 1024 * 1024; // 16 MiB

  static Random _createCsprng() {
    try {
      return Random.secure();
    } catch (_) {
      return Random();
    }
  }

  static void _assertSafePath(String path, {bool mutating = false}) {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      throw ArgumentError('Rejected unsafe filesystem path');
    }
    if (NeomageNetworkGuard.isProtectedSystemOrCredentialPath(path)) {
      throw io.FileSystemException(
        'Access to protected system or credential path is denied',
        path,
      );
    }
    if (mutating && io.FileSystemEntity.isLinkSync(path)) {
      throw io.FileSystemException(
        'Refusing to mutate symbolic link target',
        path,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Filesystem — basic read / write
  // ---------------------------------------------------------------------------

  @override
  Future<String> readFile(String path) async {
    _assertSafePath(path);
    return io.File(path).readAsString();
  }

  @override
  Future<Uint8List> readFileBytes(String path) async {
    _assertSafePath(path);
    return io.File(path).readAsBytes();
  }

  @override
  Future<void> writeFile(String path, String content) async {
    _assertSafePath(path, mutating: true);
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> writeFileBytes(String path, Uint8List bytes) async {
    _assertSafePath(path, mutating: true);
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
  }

  @override
  Future<void> appendFile(String path, String content) async {
    _assertSafePath(path, mutating: true);
    final file = io.File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(content, mode: io.FileMode.append);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — queries
  // ---------------------------------------------------------------------------

  @override
  Future<bool> fileExists(String path) {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      return Future.value(false);
    }
    return io.File(path).exists();
  }

  @override
  Future<bool> directoryExists(String path) {
    if (path.isEmpty ||
        path.contains('\x00') ||
        path.startsWith('//') ||
        path.startsWith(r'\\')) {
      return Future.value(false);
    }
    return io.Directory(path).exists();
  }

  @override
  Future<PlatformFileStat> statFile(String path) async {
    _assertSafePath(path);
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
    _assertSafePath(path);
    final dir = io.Directory(path);
    final entries = await dir
        .list(recursive: recursive, followLinks: false)
        .toList();
    return entries.map((e) => e.path).toList();
  }

  // ---------------------------------------------------------------------------
  // Filesystem — mutations
  // ---------------------------------------------------------------------------

  @override
  Future<void> createDirectory(String path, {bool recursive = true}) async {
    _assertSafePath(path, mutating: true);
    await io.Directory(path).create(recursive: recursive);
  }

  @override
  Future<void> deleteFile(String path) async {
    _assertSafePath(path, mutating: true);
    await io.File(path).delete();
  }

  @override
  Future<void> deleteDirectory(String path, {bool recursive = false}) async {
    _assertSafePath(path, mutating: true);
    await io.Directory(path).delete(recursive: recursive);
  }

  @override
  Future<void> copyFile(String source, String destination) async {
    _assertSafePath(source);
    _assertSafePath(destination, mutating: true);
    final destFile = io.File(destination);
    await destFile.parent.create(recursive: true);
    await io.File(source).copy(destination);
  }

  @override
  Future<void> moveFile(String source, String destination) async {
    _assertSafePath(source, mutating: true);
    _assertSafePath(destination, mutating: true);
    final destFile = io.File(destination);
    await destFile.parent.create(recursive: true);
    await io.File(source).rename(destination);
  }

  // ---------------------------------------------------------------------------
  // Filesystem — temp helpers
  // ---------------------------------------------------------------------------

  @override
  Future<String> createTempFile({String? prefix, String? suffix}) async {
    final safePrefix = (prefix ?? 'tmp_').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final safeSuffix = (suffix ?? '').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final rng = _createCsprng();
    final dir = io.Directory.systemTemp;
    for (var attempt = 0; attempt < 8; attempt++) {
      final nonce = List<int>.generate(12, (_) => rng.nextInt(256))
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final candidate = io.File('${dir.path}/$safePrefix$nonce$safeSuffix');
      try {
        await candidate.create(exclusive: true);
        return candidate.path;
      } on io.FileSystemException {
        continue;
      }
    }
    throw const io.FileSystemException('Failed to create unique temp file');
  }

  @override
  Future<String> createTempDirectory({String? prefix}) async {
    final safePrefix = (prefix ?? 'tmp_').replaceAll(
      RegExp(r'[^A-Za-z0-9._-]'),
      '_',
    );
    final dir = await io.Directory.systemTemp.createTemp(safePrefix);
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
  Stream<FileChangeEvent> watchDirectory(String path, {bool recursive = true}) {
    _assertSafePath(path);
    return io.Directory(path)
        .watch(recursive: recursive)
        .map(
          (event) => FileChangeEvent(
            path: event.path,
            type: _mapChangeType(event.type),
          ),
        );
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

    final sanitizedEnv = NeomageNetworkGuard.sanitizeSubprocessEnv(
      io.Platform.environment,
      environment,
    );
    final process = await io.Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: sanitizedEnv,
      includeParentEnvironment: false,
      runInShell: runInShell,
    );

    final outBuf = BytesBuilder(copy: false);
    final errBuf = BytesBuilder(copy: false);
    final outSub = process.stdout.listen((chunk) {
      final rem = _maxProcessOutputBytes - outBuf.length;
      if (rem > 0) {
        outBuf.add(chunk.length <= rem ? chunk : chunk.sublist(0, rem));
      }
    });
    final errSub = process.stderr.listen((chunk) {
      final rem = _maxProcessOutputBytes - errBuf.length;
      if (rem > 0) {
        errBuf.add(chunk.length <= rem ? chunk : chunk.sublist(0, rem));
      }
    });

    final effectiveTimeout = timeout ?? const Duration(minutes: 5);
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(effectiveTimeout);
      await Future.wait([outSub.asFuture<void>(), errSub.asFuture<void>()])
          .timeout(const Duration(seconds: 1), onTimeout: () => const []);
    } on TimeoutException {
      process.kill();
      if (!io.Platform.isWindows) {
        try {
          await process.exitCode.timeout(const Duration(milliseconds: 200));
        } catch (_) {
          process.kill(io.ProcessSignal.sigkill);
        }
      }
      await outSub.cancel();
      await errSub.cancel();
      rethrow;
    } finally {
      await outSub.cancel();
      await errSub.cancel();
    }

    return ProcessOutput(
      exitCode: exitCode,
      stdout: utf8.decode(outBuf.takeBytes(), allowMalformed: true),
      stderr: utf8.decode(errBuf.takeBytes(), allowMalformed: true),
    );
  }

  @override
  Future<RunningProcess> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  }) async {
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

    final sanitizedEnv = NeomageNetworkGuard.sanitizeSubprocessEnv(
      io.Platform.environment,
      environment,
    );
    final process = await io.Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: sanitizedEnv,
      includeParentEnvironment: false,
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
    if (!NeomageNetworkGuard.isSafeEndpointUri(
      url,
      allowLoopbackHttp: true,
      allowPrivateLanHttp: true,
    )) {
      throw ArgumentError('Rejected unsafe HTTP endpoint URI: $url');
    }

    final effectiveTimeout = timeout ?? const Duration(seconds: 30);
    final client = io.HttpClient()..connectionTimeout = effectiveTimeout;

    try {
      final request = await client.openUrl(method, url);
      request.followRedirects = false;
      request.maxRedirects = 0;

      headers?.forEach((k, v) {
        if (NeomageNetworkGuard.isValidHeaderName(k)) {
          request.headers.set(k, NeomageNetworkGuard.sanitizeHeaderValue(v));
        }
      });

      if (body != null) {
        if (body is String) {
          request.write(body);
        } else if (body is List<int>) {
          request.add(body);
        } else if (body is Map) {
          request.headers.set(
            'content-type',
            'application/json; charset=utf-8',
          );
          request.write(jsonEncode(body));
        }
      }

      final response = await request.close().timeout(effectiveTimeout);
      final responseBytes = BytesBuilder(copy: false);
      await for (final chunk in response) {
        if (responseBytes.length + chunk.length > _maxHttpResponseBytes) {
          throw StateError('HTTP response exceeded 16 MiB limit');
        }
        responseBytes.add(chunk);
      }

      final responseHeaders = <String, String>{};
      response.headers.forEach((name, values) {
        responseHeaders[name] = values.join(', ');
      });

      final bytes = responseBytes.takeBytes();
      return PlatformHttpResponse(
        statusCode: response.statusCode,
        headers: responseHeaders,
        body: utf8.decode(bytes, allowMalformed: true),
        bodyBytes: bytes,
      );
    } finally {
      client.close(force: true);
    }
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
    final ws = await io.WebSocket.connect(
      url.toString(),
    ).timeout(const Duration(seconds: 15));
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
