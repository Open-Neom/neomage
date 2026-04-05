// ShellExecutor — cross-platform adapter for neom_cli's CliExecutor.
// Desktop: delegates to CliExecutor.run() from neom_cli.
// Web: returns graceful error (shell not available).
export 'shell_executor_stub.dart'
    if (dart.library.io) 'shell_executor_io.dart';
