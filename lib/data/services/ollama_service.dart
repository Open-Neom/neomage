// Ollama local model service — auto-discovery, model management, health checks.
// Enables NeomClaw to detect and use local Ollama instances without configuration.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Status of the local Ollama instance.
enum OllamaStatus { unknown, checking, running, notRunning, error }

/// A locally available Ollama model.
class OllamaModel {
  final String name;
  final String? digest;
  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? family;
  final String? parameterSize;
  final String? quantizationLevel;

  const OllamaModel({
    required this.name,
    this.digest,
    this.sizeBytes,
    this.modifiedAt,
    this.family,
    this.parameterSize,
    this.quantizationLevel,
  });

  factory OllamaModel.fromJson(Map<String, dynamic> json) {
    final details = json['details'] as Map<String, dynamic>? ?? {};
    return OllamaModel(
      name: json['name'] as String? ?? json['model'] as String? ?? '',
      digest: json['digest'] as String?,
      sizeBytes: json['size'] as int?,
      modifiedAt: json['modified_at'] != null
          ? DateTime.tryParse(json['modified_at'] as String)
          : null,
      family: details['family'] as String?,
      parameterSize: details['parameter_size'] as String?,
      quantizationLevel: details['quantization_level'] as String?,
    );
  }

  /// Human-readable size.
  String get sizeLabel {
    if (sizeBytes == null) return '';
    final gb = sizeBytes! / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    final mb = sizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  /// Short display name (without tag if it's :latest).
  String get displayName {
    if (name.endsWith(':latest')) return name.replaceAll(':latest', '');
    return name;
  }
}

/// Service for discovering and managing local Ollama models.
class OllamaService {
  final String host;
  final Duration timeout;

  OllamaService({
    this.host = 'http://localhost:11434',
    this.timeout = const Duration(seconds: 5),
  });

  /// Check if Ollama is running.
  Future<OllamaStatus> checkStatus() async {
    try {
      final resp = await http
          .get(Uri.parse(host))
          .timeout(timeout);
      if (resp.statusCode == 200 && resp.body.contains('Ollama')) {
        return OllamaStatus.running;
      }
      return OllamaStatus.notRunning;
    } on TimeoutException {
      return OllamaStatus.notRunning;
    } catch (_) {
      return OllamaStatus.notRunning;
    }
  }

  /// List all locally available models.
  Future<List<OllamaModel>> listModels() async {
    try {
      final resp = await http
          .get(Uri.parse('$host/api/tags'))
          .timeout(timeout);
      if (resp.statusCode != 200) return [];

      final body = jsonDecode(resp.body);
      final models = body['models'] as List? ?? [];
      return models
          .map((m) => OllamaModel.fromJson(m as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
    } catch (_) {
      return [];
    }
  }

  /// Get info about a specific model.
  Future<OllamaModel?> showModel(String name) async {
    try {
      final resp = await http
          .post(
            Uri.parse('$host/api/show'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'name': name}),
          )
          .timeout(timeout);
      if (resp.statusCode != 200) return null;

      final body = jsonDecode(resp.body);
      return OllamaModel.fromJson({
        'name': name,
        ...body as Map<String, dynamic>,
      });
    } catch (_) {
      return null;
    }
  }

  /// Pull (download) a model. Returns a stream of progress updates.
  Stream<OllamaPullProgress> pullModel(String name) async* {
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$host/api/pull'),
      );
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'name': name, 'stream': true});

      final client = http.Client();
      final response = await client.send(request);

      await for (final chunk in response.stream.transform(utf8.decoder)) {
        for (final line in chunk.split('\n')) {
          if (line.trim().isEmpty) continue;
          try {
            final json = jsonDecode(line) as Map<String, dynamic>;
            yield OllamaPullProgress(
              status: json['status'] as String? ?? '',
              total: json['total'] as int?,
              completed: json['completed'] as int?,
              digest: json['digest'] as String?,
            );
          } catch (_) {}
        }
      }

      client.close();
    } catch (e) {
      yield OllamaPullProgress(status: 'error: $e');
    }
  }

  /// Delete a local model.
  Future<bool> deleteModel(String name) async {
    try {
      final resp = await http.delete(
        Uri.parse('$host/api/delete'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name}),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Quick chat test with a model.
  Future<String> testChat(String model, String prompt) async {
    final resp = await http
        .post(
          Uri.parse('$host/api/chat'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'model': model,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
            'stream': false,
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw Exception('Ollama error: ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body);
    return body['message']?['content'] as String? ?? 'No response';
  }

  /// The OpenAI-compatible base URL for use with NeomClaw's API provider.
  String get openAiBaseUrl => '$host/v1';
}

/// Progress update during model pull.
class OllamaPullProgress {
  final String status;
  final int? total;
  final int? completed;
  final String? digest;

  const OllamaPullProgress({
    required this.status,
    this.total,
    this.completed,
    this.digest,
  });

  /// Progress as 0.0–1.0, or null if unknown.
  double? get progress {
    if (total == null || total == 0 || completed == null) return null;
    return completed! / total!;
  }

  bool get isDone => status == 'success';
  bool get isError => status.startsWith('error');
}

/// Recommended models for coding tasks, smallest first.
const ollamaRecommendedModels = [
  (name: 'qwen2.5-coder:7b', desc: 'Best small coding model', size: '4.7 GB'),
  (name: 'codellama:7b', desc: 'Meta Code Llama', size: '3.8 GB'),
  (name: 'deepseek-coder-v2:16b', desc: 'DeepSeek Coder v2', size: '8.9 GB'),
  (name: 'llama3.1:8b', desc: 'Meta Llama 3.1 general', size: '4.7 GB'),
  (name: 'mistral:7b', desc: 'Mistral 7B general', size: '4.1 GB'),
  (name: 'qwen2.5-coder:32b', desc: 'Best large coding model', size: '18 GB'),
  (name: 'codestral:22b', desc: 'Mistral Codestral', size: '12 GB'),
  (name: 'llama3.1:70b', desc: 'Llama 3.1 70B (needs 40GB+ RAM)', size: '40 GB'),
];
