// Web stub for dart:io types used by neom_claw.
// Complete self-contained stubs — does NOT re-export from neom_core.
// These stubs let the code COMPILE on web — runtime I/O goes through the
// local backend server via HTTP/WebSocket from WebPlatformService.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

// Re-export dart:convert Encoding types (code that imported dart:io
// sometimes got Encoding from there)
export 'dart:convert' show Encoding, utf8, ascii, latin1;

// ═══════════════════════════════════════════════════════════════════════════
// Platform
// ═══════════════════════════════════════════════════════════════════════════

class Platform {
  static Map<String, String> get environment => const <String, String>{};
  static String get resolvedExecutable => '';
  static String get executable => '';
  static String get operatingSystem => 'web';
  static String get operatingSystemVersion => '';
  static String get pathSeparator => '/';
  static String get localHostname => 'localhost';
  static int get numberOfProcessors => 1;
  static Uri get script => Uri.parse('');
  static Uri? get packageConfig => null;
  static String get version => '';
  static List<String> get executableArguments => const <String>[];

  static bool get isAndroid => false;
  static bool get isIOS => false;
  static bool get isMacOS => false;
  static bool get isWindows => false;
  static bool get isLinux => false;
  static bool get isFuchsia => false;
}

/// No-op exit function for web.
void exit(int code) {}

// ═══════════════════════════════════════════════════════════════════════════
// File
// ═══════════════════════════════════════════════════════════════════════════

class File implements FileSystemEntity {
  @override
  final String path;

  File(this.path);

  factory File.fromUri(Uri uri) => File(uri.path);

  // --- sync methods ---
  @override
  bool existsSync() => false;
  int lengthSync() => 0;
  Uint8List readAsBytesSync() => Uint8List(0);
  String readAsStringSync({Encoding encoding = utf8}) => '';
  List<String> readAsLinesSync({Encoding encoding = utf8}) => const <String>[];
  void writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {}
  void writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) {}
  void createSync({bool recursive = false, bool exclusive = false}) {}
  File copySync(String newPath) => File(newPath);
  File renameSync(String newPath) => File(newPath);
  void deleteSync({bool recursive = false}) {}
  @override
  FileStat statSync() => FileStat._stub();
  DateTime lastModifiedSync() => DateTime.fromMillisecondsSinceEpoch(0);
  @override
  String resolveSymbolicLinksSync() => path;

  // --- async methods ---
  @override
  Future<bool> exists() async => false;
  Future<int> length() async => 0;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<String> readAsString({Encoding encoding = utf8}) async => '';
  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      const <String>[];
  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async => this;
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async => this;
  Future<File> create({bool recursive = false, bool exclusive = false}) async =>
      this;
  Future<File> copy(String newPath) async => File(newPath);
  @override
  Future<File> rename(String newPath) async => File(newPath);
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;
  @override
  Future<FileStat> stat() async => FileStat._stub();
  Future<DateTime> lastModified() async =>
      DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Future<String> resolveSymbolicLinks() async => path;

  // --- stream / random access ---
  Stream<List<int>> openRead([int? start, int? end]) =>
      Stream.value(Uint8List(0));
  IOSink openWrite({
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
  }) => _StubIOSink();
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _StubRandomAccessFile(path);
  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      _StubRandomAccessFile(path);

  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => const Stream.empty();

  @override
  Uri get uri => Uri.file(path);
  @override
  Directory get parent => Directory(
    path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '.',
  );

  @override
  String toString() => "File: '$path'";
}

// ═══════════════════════════════════════════════════════════════════════════
// Directory
// ═══════════════════════════════════════════════════════════════════════════

class Directory implements FileSystemEntity {
  @override
  final String path;

  Directory(this.path);

  factory Directory.fromUri(Uri uri) => Directory(uri.path);

  // --- static accessors ---
  static Directory get current => Directory('.');
  static set current(dynamic value) {}
  static Directory get systemTemp => Directory('/tmp');

  // --- sync methods ---
  @override
  bool existsSync() => false;
  void createSync({bool recursive = false}) {}
  Directory createTempSync([String? prefix]) =>
      Directory('$path/${prefix ?? ''}temp');
  void deleteSync({bool recursive = false}) {}
  Directory renameSync(String newPath) => Directory(newPath);
  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) => const <FileSystemEntity>[];
  @override
  String resolveSymbolicLinksSync() => path;
  @override
  FileStat statSync() => FileStat._stub();

  // --- async methods ---
  @override
  Future<bool> exists() async => false;
  Future<Directory> create({bool recursive = false}) async => this;
  Future<Directory> createTemp([String? prefix]) async =>
      Directory('$path/${prefix ?? ''}temp');
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;
  @override
  Future<Directory> rename(String newPath) async => Directory(newPath);
  Stream<FileSystemEntity> list({
    bool recursive = false,
    bool followLinks = true,
  }) => const Stream.empty();
  @override
  Future<String> resolveSymbolicLinks() async => path;
  @override
  Future<FileStat> stat() async => FileStat._stub();
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => const Stream.empty();

  @override
  Uri get uri => Uri.directory(path);
  @override
  Directory get parent => Directory(
    path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '.',
  );

  @override
  String toString() => "Directory: '$path'";
}

// ═══════════════════════════════════════════════════════════════════════════
// Process
// ═══════════════════════════════════════════════════════════════════════════

class Process {
  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) async {
    return ProcessResult(0, -1, '', 'dart:io unavailable on web');
  }

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessStartMode mode = ProcessStartMode.normal,
  }) async {
    throw UnsupportedError('Process.start unavailable on web');
  }

  static ProcessResult runSync(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    Encoding? stdoutEncoding,
    Encoding? stderrEncoding,
  }) {
    return ProcessResult(0, -1, '', 'dart:io unavailable on web');
  }

  static bool killPid(int pid, [ProcessSignal signal = ProcessSignal.sigterm]) {
    return false;
  }

  int get pid => 0;
  Stream<List<int>> get stdout => const Stream.empty();
  Stream<List<int>> get stderr => const Stream.empty();
  IOSink get stdin => _StubIOSink();
  Future<int> get exitCode => Future.value(-1);

  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => false;
}

class ProcessResult {
  final int pid;
  final int exitCode;
  final dynamic stdout;
  final dynamic stderr;

  ProcessResult(this.pid, this.exitCode, this.stdout, this.stderr);
}

class ProcessSignal {
  final int _signalNumber;
  const ProcessSignal._(this._signalNumber);

  static const sigint = ProcessSignal._(2);
  static const sigterm = ProcessSignal._(15);
  static const sigkill = ProcessSignal._(9);
  static const sighup = ProcessSignal._(1);
  static const sigusr1 = ProcessSignal._(10);
  static const sigusr2 = ProcessSignal._(12);
  static const sigwinch = ProcessSignal._(28);
  static const sigcont = ProcessSignal._(18);

  Stream<ProcessSignal> watch() => const Stream.empty();

  @override
  String toString() => 'ProcessSignal($_signalNumber)';
}

enum ProcessStartMode { normal, inheritStdio, detached, detachedWithStdio }

class ProcessException implements Exception {
  final String executable;
  final List<String> arguments;
  final String message;
  final int errorCode;

  const ProcessException(
    this.executable,
    this.arguments, [
    this.message = '',
    this.errorCode = 0,
  ]);

  @override
  String toString() => 'ProcessException: $message ($executable)';
}

// ═══════════════════════════════════════════════════════════════════════════
// stdin / stdout / stderr
// ═══════════════════════════════════════════════════════════════════════════

final Stdin stdin = Stdin._();
final Stdout stdout = Stdout._();
final Stdout stderr = Stdout._();

class Stdin extends Stream<List<int>> {
  Stdin._();

  bool get echoMode => false;
  set echoMode(bool value) {}
  bool get lineMode => true;
  set lineMode(bool value) {}
  bool get echoNewlineMode => false;
  set echoNewlineMode(bool value) {}
  bool get hasTerminal => false;
  int? readByteSync() => null;
  String? readLineSync({
    Encoding encoding = utf8,
    bool retainNewlines = false,
  }) => null;
  bool get supportsAnsiEscapes => false;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class Stdout implements IOSink {
  Stdout._();

  bool get hasTerminal => false;
  int get terminalColumns => 120;
  int get terminalLines => 40;
  bool get supportsAnsiEscapes => false;
  IOSink get nonBlocking => this;

  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => Future.value();
  @override
  Future close() => Future.value();
  @override
  Future get done => Future.value();
  @override
  Future flush() => Future.value();
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding value) {}
}

// ═══════════════════════════════════════════════════════════════════════════
// IOSink
// ═══════════════════════════════════════════════════════════════════════════

abstract class IOSink implements StringSink {
  Encoding get encoding;
  set encoding(Encoding value);
  void add(List<int> data);
  void addError(Object error, [StackTrace? stackTrace]);
  Future addStream(Stream<List<int>> stream);
  Future flush();
  Future close();
  Future get done;
}

class _StubIOSink implements IOSink {
  @override
  Encoding get encoding => utf8;
  @override
  set encoding(Encoding value) {}
  @override
  void add(List<int> data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream<List<int>> stream) => Future.value();
  @override
  Future close() => Future.value();
  @override
  Future get done => Future.value();
  @override
  Future flush() => Future.value();
  @override
  void write(Object? object) {}
  @override
  void writeAll(Iterable objects, [String separator = '']) {}
  @override
  void writeCharCode(int charCode) {}
  @override
  void writeln([Object? object = '']) {}
}

// ═══════════════════════════════════════════════════════════════════════════
// FileSystem types
// ═══════════════════════════════════════════════════════════════════════════

class FileStat {
  final FileSystemEntityType type;
  final int mode;
  final int size;
  final DateTime modified;
  final DateTime accessed;
  final DateTime changed;

  const FileStat._({
    required this.modified,
    required this.accessed,
    required this.changed,
    this.type = FileSystemEntityType.notFound,
    this.mode = 0,
    this.size = 0,
  });

  factory FileStat._stub() => FileStat._(
    modified: DateTime.fromMillisecondsSinceEpoch(0),
    accessed: DateTime.fromMillisecondsSinceEpoch(0),
    changed: DateTime.fromMillisecondsSinceEpoch(0),
  );

  static FileStat statSync(String path) => FileStat._stub();

  static Future<FileStat> stat(String path) async => statSync(path);

  String modeString() => '---------';

  @override
  String toString() => 'FileStat(type=$type, size=$size)';
}

enum FileSystemEntityType {
  file,
  directory,
  link,
  notFound,
  pipe,
  unixDomainSock,
}

class FileSystemEntity {
  static Future<FileSystemEntityType> type(String path) async =>
      FileSystemEntityType.notFound;
  static FileSystemEntityType typeSync(String path) =>
      FileSystemEntityType.notFound;
  static Future<bool> isFile(String path) async => false;
  static Future<bool> isDirectory(String path) async => false;
  static Future<bool> isLink(String path) async => false;
  static bool isFileSync(String path) => false;
  static bool isDirectorySync(String path) => false;
  static bool isLinkSync(String path) => false;
  static String parentOf(String path) =>
      path.contains('/') ? path.substring(0, path.lastIndexOf('/')) : '.';

  String get path => '';
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;
  Future<FileSystemEntity> rename(String newPath) async => this;
  Uri get uri => Uri.parse(path);
  Directory get parent => Directory('');
  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<FileStat> stat() async => FileStat._stub();
  FileStat statSync() => FileStat._stub();
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => const Stream.empty();
  Future<String> resolveSymbolicLinks() async => path;
  String resolveSymbolicLinksSync() => path;
}

enum FileMode { read, write, append, writeOnly, writeOnlyAppend }

class FileSystemException implements Exception {
  final String message;
  final String? path;
  final OSError? osError;

  const FileSystemException([this.message = '', this.path, this.osError]);

  @override
  String toString() => 'FileSystemException: $message (path=$path)';
}

class PathNotFoundException extends FileSystemException {
  const PathNotFoundException([super.message, super.path, super.osError]);

  @override
  String toString() => 'PathNotFoundException: $message (path=$path)';
}

class OSError {
  final String message;
  final int errorCode;

  const OSError([this.message = '', this.errorCode = 0]);

  static const int noErrorCode = -1;

  @override
  String toString() => 'OSError: $message ($errorCode)';
}

class FileSystemEvent {
  static const int create = 1;
  static const int modify = 2;
  static const int delete = 4;
  static const int move = 8;
  static const int all = create | modify | delete | move;

  final int type;
  final String path;
  final bool isDirectory;

  const FileSystemEvent._(this.type, this.path, this.isDirectory);
}

class FileSystemCreateEvent extends FileSystemEvent {
  const FileSystemCreateEvent._(String path, bool isDirectory)
    : super._(FileSystemEvent.create, path, isDirectory);
}

class FileSystemModifyEvent extends FileSystemEvent {
  final bool contentChanged;
  const FileSystemModifyEvent._(
    String path,
    bool isDirectory,
    this.contentChanged,
  ) : super._(FileSystemEvent.modify, path, isDirectory);
}

class FileSystemDeleteEvent extends FileSystemEvent {
  const FileSystemDeleteEvent._(String path, bool isDirectory)
    : super._(FileSystemEvent.delete, path, isDirectory);
}

class FileSystemMoveEvent extends FileSystemEvent {
  final String? destination;
  const FileSystemMoveEvent._(String path, bool isDirectory, this.destination)
    : super._(FileSystemEvent.move, path, isDirectory);
}

class Link implements FileSystemEntity {
  @override
  final String path;
  Link(this.path);

  static Link fromUri(Uri uri) => Link(uri.path);
  @override
  Future<bool> exists() async => false;
  @override
  bool existsSync() => false;
  Future<Link> create(String target, {bool recursive = false}) async => this;
  void createSync(String target, {bool recursive = false}) {}
  void deleteSync({bool recursive = false}) {}
  Future<String> target() async => '';
  String targetSync() => '';
  Future<Link> update(String target) async => this;
  void updateSync(String target) {}
  @override
  Future<String> resolveSymbolicLinks() async => path;
  @override
  String resolveSymbolicLinksSync() => path;
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) async => this;
  @override
  Future<Link> rename(String newPath) async => Link(newPath);
  @override
  Future<FileStat> stat() async => FileStat._stub();
  @override
  FileStat statSync() => FileStat._stub();
  @override
  Stream<FileSystemEvent> watch({
    int events = FileSystemEvent.all,
    bool recursive = false,
  }) => const Stream.empty();
  @override
  Uri get uri => Uri.parse(path);
  @override
  Directory get parent => Directory('');
}

// ═══════════════════════════════════════════════════════════════════════════
// RandomAccessFile
// ═══════════════════════════════════════════════════════════════════════════

abstract class RandomAccessFile {
  String get path;
  int lengthSync();
  Future<int> length();
  int readByteSync();
  Future<int> readByte();
  Uint8List readSync(int count);
  Future<Uint8List> read(int count);
  int readIntoSync(List<int> buffer, [int start = 0, int? end]);
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]);
  void writeByteSync(int value);
  Future<RandomAccessFile> writeByte(int value);
  void writeFromSync(List<int> buffer, [int start = 0, int? end]);
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]);
  void writeStringSync(String string, {Encoding encoding = utf8});
  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  });
  int positionSync();
  Future<int> position();
  void setPositionSync(int position);
  Future<RandomAccessFile> setPosition(int position);
  void truncateSync(int length);
  Future<RandomAccessFile> truncate(int length);
  void flushSync();
  Future<RandomAccessFile> flush();
  void lockSync([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]);
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]);
  void unlockSync([int start = 0, int end = -1]);
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]);
  void closeSync();
  Future<void> close();
}

enum FileLock { shared, exclusive, blockingShared, blockingExclusive }

class _StubRandomAccessFile implements RandomAccessFile {
  @override
  final String path;
  _StubRandomAccessFile(this.path);

  @override
  int lengthSync() => 0;
  @override
  Future<int> length() async => 0;
  @override
  int readByteSync() => -1;
  @override
  Future<int> readByte() async => -1;
  @override
  Uint8List readSync(int count) => Uint8List(0);
  @override
  Future<Uint8List> read(int count) async => Uint8List(0);
  @override
  int readIntoSync(List<int> buffer, [int start = 0, int? end]) => 0;
  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) async => 0;
  @override
  void writeByteSync(int value) {}
  @override
  Future<RandomAccessFile> writeByte(int value) async => this;
  @override
  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {}
  @override
  Future<RandomAccessFile> writeFrom(
    List<int> buffer, [
    int start = 0,
    int? end,
  ]) async => this;
  @override
  void writeStringSync(String string, {Encoding encoding = utf8}) {}
  @override
  Future<RandomAccessFile> writeString(
    String string, {
    Encoding encoding = utf8,
  }) async => this;
  @override
  int positionSync() => 0;
  @override
  Future<int> position() async => 0;
  @override
  void setPositionSync(int position) {}
  @override
  Future<RandomAccessFile> setPosition(int position) async => this;
  @override
  void truncateSync(int length) {}
  @override
  Future<RandomAccessFile> truncate(int length) async => this;
  @override
  void flushSync() {}
  @override
  Future<RandomAccessFile> flush() async => this;
  @override
  void lockSync([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) {}
  @override
  Future<RandomAccessFile> lock([
    FileLock mode = FileLock.exclusive,
    int start = 0,
    int end = -1,
  ]) async => this;
  @override
  void unlockSync([int start = 0, int end = -1]) {}
  @override
  Future<RandomAccessFile> unlock([int start = 0, int end = -1]) async => this;
  @override
  void closeSync() {}
  @override
  Future<void> close() async {}
}

// ═══════════════════════════════════════════════════════════════════════════
// SystemEncoding & BytesBuilder
// ═══════════════════════════════════════════════════════════════════════════

class SystemEncoding extends Encoding {
  const SystemEncoding();

  @override
  String get name => 'system';

  @override
  Converter<List<int>, String> get decoder => utf8.decoder;

  @override
  Converter<String, List<int>> get encoder => utf8.encoder;
}

const systemEncoding = SystemEncoding();

class BytesBuilder {
  final List<int> _buffer = [];

  BytesBuilder({bool copy = true});

  void add(List<int> bytes) => _buffer.addAll(bytes);
  void addByte(int byte) => _buffer.add(byte);
  Uint8List takeBytes() {
    final result = Uint8List.fromList(_buffer);
    _buffer.clear();
    return result;
  }

  Uint8List toBytes() => Uint8List.fromList(_buffer);
  int get length => _buffer.length;
  bool get isEmpty => _buffer.isEmpty;
  bool get isNotEmpty => _buffer.isNotEmpty;
  void clear() => _buffer.clear();
}

// ═══════════════════════════════════════════════════════════════════════════
// Network stubs
// ═══════════════════════════════════════════════════════════════════════════

class HttpStatus {
  static const int continue_ = 100;
  static const int switchingProtocols = 101;
  static const int ok = 200;
  static const int created = 201;
  static const int accepted = 202;
  static const int nonAuthoritativeInformation = 203;
  static const int noContent = 204;
  static const int resetContent = 205;
  static const int partialContent = 206;
  static const int multipleChoices = 300;
  static const int movedPermanently = 301;
  static const int found = 302;
  static const int movedTemporarily = 302;
  static const int seeOther = 303;
  static const int notModified = 304;
  static const int useProxy = 305;
  static const int temporaryRedirect = 307;
  static const int permanentRedirect = 308;
  static const int badRequest = 400;
  static const int unauthorized = 401;
  static const int paymentRequired = 402;
  static const int forbidden = 403;
  static const int notFound = 404;
  static const int methodNotAllowed = 405;
  static const int notAcceptable = 406;
  static const int requestTimeout = 408;
  static const int conflict = 409;
  static const int gone = 410;
  static const int lengthRequired = 411;
  static const int preconditionFailed = 412;
  static const int requestEntityTooLarge = 413;
  static const int requestUriTooLong = 414;
  static const int unsupportedMediaType = 415;
  static const int requestedRangeNotSatisfiable = 416;
  static const int expectationFailed = 417;
  static const int upgradeRequired = 426;
  static const int tooManyRequests = 429;
  static const int internalServerError = 500;
  static const int notImplemented = 501;
  static const int badGateway = 502;
  static const int serviceUnavailable = 503;
  static const int gatewayTimeout = 504;
  static const int httpVersionNotSupported = 505;
  static const int networkConnectTimeoutError = 599;
}

class HttpClient {
  bool autoUncompress = true;
  Duration? connectionTimeout;
  Duration idleTimeout = const Duration(seconds: 15);
  int? maxConnectionsPerHost;
  String? userAgent;

  HttpClient({SecurityContext? context});

  Future<HttpClientRequest> getUrl(Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');
  Future<HttpClientRequest> postUrl(Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');
  Future<HttpClientRequest> putUrl(Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');
  Future<HttpClientRequest> deleteUrl(Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');
  Future<HttpClientRequest> headUrl(Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      throw UnsupportedError('HttpClient unavailable on web');

  set badCertificateCallback(bool Function(dynamic, String, int)? callback) {}
  set findProxy(String Function(Uri)? f) {}
  set authenticate(Future<bool> Function(Uri, String, String?)? f) {}

  void close({bool force = false}) {}
}

abstract class HttpClientRequest {
  HttpHeaders get headers;
  void add(List<int> data);
  void write(Object? obj);
  Future<HttpClientResponse> close();
}

abstract class HttpClientResponse extends Stream<List<int>> {
  int get statusCode;
  String get reasonPhrase;
  int get contentLength;
  bool get isRedirect;
  HttpHeaders get headers;
  HttpClientResponseCompressionState get compressionState;
}

enum HttpClientResponseCompressionState {
  notCompressed,
  decompressed,
  compressed,
}

abstract class HttpHeaders {
  static const acceptHeader = 'accept';
  static const contentTypeHeader = 'content-type';
  static const authorizationHeader = 'authorization';

  List<String>? operator [](String name);
  void add(String name, Object value, {bool preserveHeaderCase = false});
  void set(String name, Object value, {bool preserveHeaderCase = false});
  void remove(String name, Object value);
  void removeAll(String name);
  void forEach(void Function(String name, List<String> values) action);
  String? value(String name);
  ContentType? get contentType;
  set contentType(ContentType? contentType);
  int get contentLength;
  set contentLength(int contentLength);
}

class ContentType {
  final String primaryType;
  final String subType;
  final Map<String, String?> parameters;

  ContentType(
    this.primaryType,
    this.subType, {
    String? charset,
    Map<String, String?>? parameters,
  }) : parameters = parameters ?? {};

  static final json = ContentType('application', 'json', charset: 'utf-8');
  static final text = ContentType('text', 'plain', charset: 'utf-8');
  static final html = ContentType('text', 'html', charset: 'utf-8');
  static final binary = ContentType('application', 'octet-stream');

  String? get charset => parameters['charset'];
  String get mimeType => '$primaryType/$subType';

  @override
  String toString() => mimeType;
}

class HttpServer extends Stream<HttpRequest> {
  static Future<HttpServer> bind(
    dynamic address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) async {
    throw UnsupportedError('HttpServer unavailable on web');
  }

  static Future<HttpServer> bindSecure(
    dynamic address,
    int port,
    SecurityContext context, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) async {
    throw UnsupportedError('HttpServer unavailable on web');
  }

  InternetAddress get address => InternetAddress.loopbackIPv4;
  int get port => 0;
  Duration get idleTimeout => const Duration(seconds: 120);
  set idleTimeout(Duration value) {}
  Future close({bool force = false}) => Future.value();

  @override
  StreamSubscription<HttpRequest> listen(
    void Function(HttpRequest)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return const Stream<Never>.empty().listen(null);
  }
}

abstract class HttpRequest extends Stream<Uint8List> {
  Uri get uri;
  String get method;
  HttpHeaders get headers;
  HttpResponse get response;
  HttpConnectionInfo? get connectionInfo;
}

class HttpConnectionInfo {
  final InternetAddress remoteAddress;
  final int remotePort;
  final int localPort;

  HttpConnectionInfo._(this.remoteAddress, this.remotePort, this.localPort);
}

abstract class HttpResponse implements IOSink {
  int statusCode = 200;
  String? reasonPhrase;
  HttpHeaders get headers;
  @override
  Future close();
}

class HttpException implements Exception {
  final String message;
  final Uri? uri;

  const HttpException(this.message, {this.uri});

  @override
  String toString() => 'HttpException: $message';
}

class InternetAddress {
  final String address;
  final String host;
  final InternetAddressType type;

  InternetAddress._(this.address, this.host, this.type);

  factory InternetAddress(String address) =>
      InternetAddress._(address, address, InternetAddressType.IPv4);

  static final loopbackIPv4 = InternetAddress._(
    '127.0.0.1',
    'localhost',
    InternetAddressType.IPv4,
  );
  static final loopbackIPv6 = InternetAddress._(
    '::1',
    'localhost',
    InternetAddressType.IPv6,
  );
  static final anyIPv4 = InternetAddress._(
    '0.0.0.0',
    '0.0.0.0',
    InternetAddressType.IPv4,
  );
  static final anyIPv6 = InternetAddress._(
    '::',
    '::',
    InternetAddressType.IPv6,
  );

  static Future<List<InternetAddress>> lookup(
    String host, {
    InternetAddressType type = InternetAddressType.any,
  }) async => [];
}

// ignore: constant_identifier_names
enum InternetAddressType { IPv4, IPv6, unix, any }

class Socket {
  static Future<Socket> connect(
    dynamic host,
    int port, {
    dynamic sourceAddress,
    int sourcePort = 0,
    Duration? timeout,
  }) async {
    throw UnsupportedError('Socket unavailable on web');
  }

  Stream<Uint8List> get stream => const Stream.empty();
  void add(List<int> data) {}
  void write(Object? object) {}
  Future close() => Future.value();
  void destroy() {}
  int get port => 0;
  InternetAddress get address => InternetAddress.loopbackIPv4;
  InternetAddress get remoteAddress => InternetAddress.loopbackIPv4;
  int get remotePort => 0;
}

class ServerSocket {
  static Future<ServerSocket> bind(
    dynamic address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) async {
    throw UnsupportedError('ServerSocket unavailable on web');
  }

  int get port => 0;
  InternetAddress get address => InternetAddress.loopbackIPv4;
  Future close() => Future.value();
}

class WebSocket extends Stream<dynamic> {
  static const int normalClosure = 1000;
  final Stream<dynamic> _stream = const Stream.empty();

  static Future<WebSocket> connect(
    String url, {
    Iterable<String>? protocols,
    Map<String, dynamic>? headers,
  }) async {
    throw UnsupportedError(
      'WebSocket unavailable on web — use web_socket_channel',
    );
  }

  int? get closeCode => null;
  String? get closeReason => null;
  String? get protocol => null;
  int get readyState => 0;

  void add(dynamic data) {}
  Future addStream(Stream stream) => Future.value();
  Future close([int? code, String? reason]) => Future.value();

  @override
  StreamSubscription listen(
    void Function(dynamic)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

class WebSocketTransformer {
  static Future<WebSocket> upgrade(
    HttpRequest request, {
    dynamic protocolSelector,
    CompressionOptions compression = CompressionOptions.compressionDefault,
  }) async {
    throw UnsupportedError('WebSocketTransformer unavailable on web');
  }

  static bool isUpgradeRequest(HttpRequest request) => false;
}

class WebSocketStatus {
  static const int normalClosure = 1000;
  static const int goingAway = 1001;
  static const int protocolError = 1002;
  static const int unsupportedData = 1003;
  static const int reserved1004 = 1004;
  static const int noStatusReceived = 1005;
  static const int abnormalClosure = 1006;
  static const int invalidFramePayloadData = 1007;
  static const int policyViolation = 1008;
  static const int messageTooBig = 1009;
  static const int missingMandatoryExtension = 1010;
  static const int internalServerError = 1011;
  static const int reserved1015 = 1015;
}

class CompressionOptions {
  static const CompressionOptions compressionDefault = CompressionOptions();
  static const CompressionOptions compressionOff = CompressionOptions(
    enabled: false,
  );

  final bool enabled;
  const CompressionOptions({this.enabled = true});
}

class SocketException implements Exception {
  final String message;
  final OSError? osError;
  final InternetAddress? address;
  final int? port;

  const SocketException(this.message, {this.osError, this.address, this.port});

  @override
  String toString() => 'SocketException: $message';
}

class HandshakeException implements Exception {
  final String message;
  const HandshakeException([this.message = '']);

  @override
  String toString() => 'HandshakeException: $message';
}

class SecurityContext {
  SecurityContext({bool withTrustedRoots = false});

  static SecurityContext get defaultContext => SecurityContext();

  void setTrustedCertificates(String file) {}
  void setTrustedCertificatesBytes(List<int> certBytes) {}
  void useCertificateChain(String file) {}
  void useCertificateChainBytes(List<int> chainBytes) {}
  void usePrivateKey(String file, {String? password}) {}
  void usePrivateKeyBytes(List<int> keyBytes, {String? password}) {}
  void setClientAuthorities(String file) {}
  void setClientAuthoritiesBytes(List<int> authCertBytes) {}
  void setAlpnProtocols(List<String> protocols, bool isServer) {}
}

// ═══════════════════════════════════════════════════════════════════════════
// Global functions & getters
// ═══════════════════════════════════════════════════════════════════════════

int get pid => 0;
int exitCode = 0;

void sleep(Duration duration) {
  // No-op on web — can't block the event loop
}
