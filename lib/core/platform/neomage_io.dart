// Conditional export for dart:io types needed by neomage.
// Extends neom_core's core_io pattern with Process, stdin/stdout, HttpServer, etc.
// On IO platforms (desktop), re-exports dart:io.
// On web, exports stub classes that compile but delegate to the local backend.
export 'neomage_io_stub.dart' if (dart.library.io) 'neomage_io_io.dart';
