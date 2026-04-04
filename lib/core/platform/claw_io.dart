// Conditional export for dart:io types needed by neom_claw.
// Extends neom_core's core_io pattern with Process, stdin/stdout, HttpServer, etc.
// On IO platforms (desktop), re-exports dart:io.
// On web, exports stub classes that compile but delegate to the local backend.
export 'claw_io_stub.dart' if (dart.library.io) 'claw_io_io.dart';
