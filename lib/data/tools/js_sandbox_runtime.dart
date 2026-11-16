// Conditional export for QuickJS FFI sandbox evaluation.
// Uses flutter_js (QuickJS FFI) on native platforms and a Trusted-Types-safe
// no-DOM-eval stub on Web/Wasm.
export 'js_sandbox_runtime_stub.dart'
    if (dart.library.ffi) 'js_sandbox_runtime_io.dart';
