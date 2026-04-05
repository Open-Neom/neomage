// Re-export from neom_ollama — shared Ollama module.
export 'package:neom_ollama/neom_ollama.dart';

/// Recommended models for local coding tasks.
const ollamaRecommendedModels = [
  (name: 'qwen2.5-coder:7b', desc: 'Best small coding model', size: '4.7 GB'),
  (name: 'codellama:7b', desc: 'Meta Code Llama', size: '3.8 GB'),
  (name: 'deepseek-coder-v2:16b', desc: 'DeepSeek Coder v2', size: '8.9 GB'),
  (name: 'llama3.1:8b', desc: 'Meta Llama 3.1 general', size: '4.7 GB'),
  (name: 'mistral:7b', desc: 'Mistral 7B general', size: '4.1 GB'),
  (name: 'qwen2.5-coder:32b', desc: 'Best large coding model', size: '18 GB'),
];
