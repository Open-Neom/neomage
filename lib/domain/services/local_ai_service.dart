/// Abstract open-source contract for on-device / in-process AI inference in Neomage.
///
/// Implementations can wrap `llamadart` (`llama.cpp`), LiteRT, MediaPipe,
/// Core ML, or any local inference engine without coupling `neomage` to
/// proprietary host packages.
abstract class LocalAiService {
  /// Whether a local model is loaded and ready for inference.
  bool get isReady;

  /// Loads the local model from [modelPath], returning `true` on success.
  Future<bool> initialize({String? modelPath});

  /// Generates a single-turn completion from [prompt].
  Future<String> generate(String prompt, {int maxTokens = 256});

  /// Generates a response given multi-turn [messages] (`role` / `content` maps).
  Future<String> chat(
    List<Map<String, String>> messages, {
    int maxTokens = 256,
  });

  /// Metadata describing the active local runtime and model state.
  Map<String, dynamic> get modelInfo;

  /// Releases native/local model resources.
  Future<void> dispose();
}
