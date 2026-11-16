import 'package:flutter_js/flutter_js.dart';

/// Evaluates [code] inside an isolated native QuickJS runtime (`dart:ffi`)
/// with zero access to the host filesystem, network, or shell.
({String output, bool isError}) evaluateIsolatedJavaScript(String code) {
  JavascriptRuntime? jsRuntime;
  try {
    jsRuntime = getJavascriptRuntime();
    final result = jsRuntime.evaluate(code);
    return (output: result.stringResult, isError: result.isError);
  } finally {
    jsRuntime?.dispose();
  }
}
