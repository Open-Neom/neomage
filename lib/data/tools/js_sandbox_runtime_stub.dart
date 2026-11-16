/// Web/Wasm stub for QuickJS FFI sandbox evaluation.
///
/// Intentionally refuses to invoke browser `eval()` / `Function()` so untrusted
/// LLM code can never execute in the host document origin or violate CSP /
/// Trusted Types policies.
({String output, bool isError}) evaluateIsolatedJavaScript(String code) {
  return (
    output: 'QuickJS FFI runtime is unavailable on Web/Wasm.',
    isError: true,
  );
}
