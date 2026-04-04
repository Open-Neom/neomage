import 'dart:async';
import 'dart:typed_data';

/// Platform abstraction layer that hides `dart:io` from the web frontend.
///
/// On native platforms (macOS, Linux, Windows) the implementation delegates
/// directly to `dart:io`.  On the web the implementation proxies every call
/// to a local REST server running on `localhost:3219`.
///
/// Usage:
/// ```dart
/// import 'package:neom_claw/core/platform/platform_init.dart';
///
/// void main() {
///   initializePlatform();
///   final ps = PlatformService.instance;
///   final content = await ps.readFile('/tmp/hello.txt');
/// }
/// ```
abstract class PlatformService {
  // ---------------------------------------------------------------------------
  // Singleton
  // ---------------------------------------------------------------------------

  static PlatformService get instance => _instance;
  static late PlatformService _instance;

  /// Must be called once at application startup.
  static void initialize(PlatformService impl) => _instance = impl;

  // ---------------------------------------------------------------------------
  // Filesystem — basic read / write
  // ---------------------------------------------------------------------------

  /// Read file at [path] as a UTF-8 string.
  Future<String> readFile(String path);

  /// Read file at [path] as raw bytes.
  Future<Uint8List> readFileBytes(String path);

  /// Write [content] (UTF-8) to file at [path], creating parent dirs as needed.
  Future<void> writeFile(String path, String content);

  /// Write raw [bytes] to file at [path], creating parent dirs as needed.
  Future<void> writeFileBytes(String path, Uint8List bytes);

  /// Append [content] to the end of the file at [path].
  Future<void> appendFile(String path, String content);

  // ---------------------------------------------------------------------------
  // Filesystem — queries
  // ---------------------------------------------------------------------------

  /// Whether a file exists at [path].
  Future<bool> fileExists(String path);

  /// Whether a directory exists at [path].
  Future<bool> directoryExists(String path);

  /// Return metadata for the entity at [path].
  Future<PlatformFileStat> statFile(String path);

  /// List entries inside [path].  When [recursive] is true, descend into
  /// sub-directories.
  Future<List<String>> listDirectory(String path, {bool recursive = false});

  // ---------------------------------------------------------------------------
  // Filesystem — mutations
  // ---------------------------------------------------------------------------

  /// Create a directory at [path].
  Future<void> createDirectory(String path, {bool recursive = true});

  /// Delete the file at [path].
  Future<void> deleteFile(String path);

  /// Delete the directory at [path].  If [recursive] is true, delete contents.
  Future<void> deleteDirectory(String path, {bool recursive = false});

  /// Copy a file from [source] to [destination].
  Future<void> copyFile(String source, String destination);

  /// Move / rename a file from [source] to [destination].
  Future<void> moveFile(String source, String destination);

  // ---------------------------------------------------------------------------
  // Filesystem — temp helpers
  // ---------------------------------------------------------------------------

  /// Create a temporary file and return its path.
  Future<String> createTempFile({String? prefix, String? suffix});

  /// Create a temporary directory and return its path.
  Future<String> createTempDirectory({String? prefix});

  // ---------------------------------------------------------------------------
  // Filesystem — well-known paths
  // ---------------------------------------------------------------------------

  /// Current working directory.
  String get currentDirectory;

  /// User home directory (e.g. `/Users/me`).
  String get homeDirectory;

  /// System temp directory.
  String get tempDirectory;

  // ---------------------------------------------------------------------------
  // Filesystem — watch
  // ---------------------------------------------------------------------------

  /// Watch [path] for filesystem changes.
  Stream<FileChangeEvent> watchDirectory(String path, {bool recursive = true});

  // ---------------------------------------------------------------------------
  // Process execution
  // ---------------------------------------------------------------------------

  /// Run a process to completion and capture its output.
  Future<ProcessOutput> runProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    Duration? timeout,
    bool runInShell = false,
  });

  /// Start a long-running process and return a handle that exposes output
  /// streams and a kill method.
  Future<RunningProcess> startProcess(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool runInShell = false,
  });

  // ---------------------------------------------------------------------------
  // Environment
  // ---------------------------------------------------------------------------

  /// All environment variables.
  Map<String, String> get environmentVariables;

  /// Operating system identifier (e.g. `macos`, `linux`, `windows`, `web`).
  String get operatingSystem;

  /// Number of processors available.
  int get numberOfProcessors;

  /// Local hostname.
  String get localHostname;

  // ---------------------------------------------------------------------------
  // Network — HTTP
  // ---------------------------------------------------------------------------

  /// Perform an HTTP request.
  Future<PlatformHttpResponse> httpRequest(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  });

  // ---------------------------------------------------------------------------
  // Network — WebSocket
  // ---------------------------------------------------------------------------

  /// Open a WebSocket connection to [url].
  Future<PlatformWebSocket> connectWebSocket(Uri url);
}

// =============================================================================
// Supporting value types
// =============================================================================

/// Metadata about a filesystem entity.
class PlatformFileStat {
  final int size;
  final DateTime modified;
  final DateTime accessed;
  final FileEntityType type;

  const PlatformFileStat({
    required this.size,
    required this.modified,
    required this.accessed,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'size': size,
    'modified': modified.toIso8601String(),
    'accessed': accessed.toIso8601String(),
    'type': type.name,
  };

  factory PlatformFileStat.fromJson(Map<String, dynamic> json) {
    return PlatformFileStat(
      size: json['size'] as int,
      modified: DateTime.parse(json['modified'] as String),
      accessed: DateTime.parse(json['accessed'] as String),
      type: FileEntityType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FileEntityType.notFound,
      ),
    );
  }

  @override
  String toString() =>
      'PlatformFileStat(type=$type, size=$size, modified=$modified)';
}

enum FileEntityType { file, directory, link, notFound }

/// A filesystem change notification.
class FileChangeEvent {
  final String path;
  final FileChangeType type;

  const FileChangeEvent({required this.path, required this.type});

  factory FileChangeEvent.fromJson(Map<String, dynamic> json) {
    return FileChangeEvent(
      path: json['path'] as String,
      type: FileChangeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => FileChangeType.modify,
      ),
    );
  }

  @override
  String toString() => 'FileChangeEvent($type, $path)';
}

enum FileChangeType { create, modify, delete, move }

/// Result of running a process to completion.
class ProcessOutput {
  final int exitCode;
  final String stdout;
  final String stderr;

  const ProcessOutput({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  factory ProcessOutput.fromJson(Map<String, dynamic> json) {
    return ProcessOutput(
      exitCode: json['exitCode'] as int,
      stdout: json['stdout'] as String? ?? '',
      stderr: json['stderr'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'exitCode': exitCode,
    'stdout': stdout,
    'stderr': stderr,
  };

  @override
  String toString() =>
      'ProcessOutput(exitCode=$exitCode, stdout=${stdout.length} chars, '
      'stderr=${stderr.length} chars)';
}

/// Handle for a long-running process.
abstract class RunningProcess {
  /// Standard output stream (line-based).
  Stream<String> get stdout;

  /// Standard error stream (line-based).
  Stream<String> get stderr;

  /// Completes with the exit code when the process terminates.
  Future<int> get exitCode;

  /// Process identifier.
  int get pid;

  /// Send a signal to the process.  Returns true if the signal was delivered.
  bool kill();

  /// Write to the process stdin.
  void writeToStdin(String data);
}

/// An HTTP response.
class PlatformHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final String body;
  final Uint8List bodyBytes;

  const PlatformHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.bodyBytes,
  });

  factory PlatformHttpResponse.fromJson(Map<String, dynamic> json) {
    return PlatformHttpResponse(
      statusCode: json['statusCode'] as int,
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      body: json['body'] as String? ?? '',
      bodyBytes: Uint8List(0),
    );
  }

  @override
  String toString() =>
      'PlatformHttpResponse($statusCode, ${body.length} chars)';
}

/// A bidirectional WebSocket channel.
abstract class PlatformWebSocket {
  /// Incoming messages.
  Stream<dynamic> get stream;

  /// Send a message.
  void add(dynamic data);

  /// Close the connection.
  Future<void> close([int? code, String? reason]);

  /// The close code once the connection has closed.
  int? get closeCode;
}
