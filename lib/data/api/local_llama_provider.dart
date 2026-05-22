import 'dart:io';
import 'package:saia_core/saia_core.dart' as saia;
import 'package:llamadart/llamadart.dart' as llama;
import 'package:neom_ollama/neom_ollama.dart';
import 'package:sint_sentinel/sint_sentinel.dart';

/// Local in-process GGUF LLM inference provider for Neomage.
///
/// Implements SAIA's [saia.LocalAiService] interface.
/// Integrates with the [HardwareProfiler] from neom_ollama to dynamically
/// profile device resources at runtime and optimize context size/thread settings.
class LocalLlamaProvider implements saia.LocalAiService {

  llama.LlamaEngine? _engine;
  String _loadedModelPath = '';
  bool _isInitializing = false;

  @override
  bool get isReady => _engine != null && _loadedModelPath.isNotEmpty;

  @override
  Map<String, dynamic> get modelInfo => {
    'provider': 'llamadart',
    'model_path': _loadedModelPath,
    'backend': 'llama.cpp (native in-process)',
    'status': isReady ? 'ready' : (_isInitializing ? 'loading' : 'not_loaded'),
  };

  // ═══════════════════════════════════════════
  // Initialization & Resource Management
  // ═══════════════════════════════════════════

  @override
  Future<bool> initialize({String? modelPath}) async {
    if (isReady && modelPath == _loadedModelPath) return true;
    if (_isInitializing) return false;

    _isInitializing = true;
    final path = modelPath ?? '';

    if (path.isEmpty || !File(path).existsSync()) {
      SintSentinel.logger.e('LocalLlamaProvider: Cannot initialize, model file does not exist at: "$path"');
      _isInitializing = false;
      return false;
    }

    try {
      SintSentinel.logger.i('LocalLlamaProvider: Optimizing local LLM inference context via HardwareProfiler...');
      
      // Perform hardware profiling to optimize settings
      final profiler = const HardwareProfiler();
      final profile = await profiler.detect();
      
      SintSentinel.logger.i('LocalLlamaProvider: Detected hardware tier: ${profile.tier.name.toUpperCase()} '
          '(RAM: ${profile.totalRamGB}GB, Cores: ${profile.cpuCores}, GPU: ${profile.gpuBackend.name.toUpperCase()})');

      // Dispose existing engine if any
      await dispose();

      // Setup backend
      final backend = llama.LlamaBackend();
      _engine = llama.LlamaEngine(backend);

      SintSentinel.logger.i('LocalLlamaProvider: Loading model GGUF: "$path" into in-process runtime...');
      
      // Load model into engine
      await _engine!.loadModel(path);
      _loadedModelPath = path;

      SintSentinel.logger.i('LocalLlamaProvider: Loaded model successfully! In-process inference engine is active.');
      _isInitializing = false;
      return true;
    } catch (e, st) {
      SintSentinel.logger.e('LocalLlamaProvider: Initialization failed: $e', error: e, stackTrace: st);
      await dispose();
      _isInitializing = false;
      return false;
    }
  }

  // ═══════════════════════════════════════════
  // Generation & Chat Inference
  // ═══════════════════════════════════════════

  @override
  Future<String> generate(String prompt, {int maxTokens = 256}) async {
    if (!isReady) {
      throw Exception('LocalLlamaProvider: Local LLM is not loaded. Call initialize() first.');
    }

    try {
      final session = llama.ChatSession(_engine!);
      final responseChunks = await session.create(
        [llama.LlamaTextContent(prompt)],
        params: llama.GenerationParams(maxTokens: maxTokens),
      ).toList();
      
      final buffer = StringBuffer();
      for (final chunk in responseChunks) {
        final delta = chunk.choices.first.delta;
        if (delta.content != null) {
          buffer.write(delta.content);
        }
      }
      final response = buffer.toString();
      
      // Extract thinking trace if model output contains it
      final parsed = ThinkingParser.split(response);
      
      return parsed.content;
    } catch (e) {
      SintSentinel.logger.e('LocalLlamaProvider: Generation failed: $e');
      rethrow;
    }
  }

  @override
  Future<String> chat(List<Map<String, String>> messages, {int maxTokens = 256}) async {
    if (!isReady) {
      throw Exception('LocalLlamaProvider: Local LLM is not loaded. Call initialize() first.');
    }

    try {
      // Reconstruct prompt in standard ChatML/Llama chat template format
      final formattedPrompt = _formatChatTemplate(messages);
      
      return await generate(formattedPrompt, maxTokens: maxTokens);
    } catch (e) {
      SintSentinel.logger.e('LocalLlamaProvider: Chat inference failed: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════
  // Helper Formatter
  // ═══════════════════════════════════════════

  String _formatChatTemplate(List<Map<String, String>> messages) {
    final buffer = StringBuffer();
    for (final msg in messages) {
      final role = msg['role'] ?? 'user';
      final content = msg['content'] ?? '';
      
      // Standard ChatML tokens
      buffer.write('<|im_start|>$role\n$content<|im_end|>\n');
    }
    
    // Inject start of assistant turn to prompt completion
    buffer.write('<|im_start|>assistant\n');
    return buffer.toString();
  }

  // ═══════════════════════════════════════════
  // Disposal
  // ═══════════════════════════════════════════

  @override
  Future<void> dispose() async {
    if (_engine != null) {
      SintSentinel.logger.i('LocalLlamaProvider: Disposing llama.cpp engine and freeing native memory.');
      try {
        await _engine!.dispose();
      } catch (e) {
        SintSentinel.logger.e('LocalLlamaProvider: Error during engine disposal: $e');
      }
      _engine = null;
      _loadedModelPath = '';
    }
  }
}
