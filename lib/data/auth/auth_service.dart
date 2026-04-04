import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_provider.dart';

/// Auth service — manages API keys and provider configuration.
/// Port of neom_claw/src/utils/auth.ts core functionality.
class AuthService {
  static const _anthropicKeyKey = 'anthropic_api_key';
  static const _openaiKeyKey = 'openai_api_key';
  static const _geminiKeyKey = 'gemini_api_key';
  static const _qwenKeyKey = 'qwen_api_key';
  static const _deepseekKeyKey = 'deepseek_api_key';
  static const _providerTypeKey = 'provider_type';
  static const _modelKey = 'model';
  static const _baseUrlKey = 'custom_base_url';

  final FlutterSecureStorage _secureStorage;

  AuthService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  // ── API Key Management ──

  Future<String?> getAnthropicApiKey() =>
      _secureStorage.read(key: _anthropicKeyKey);

  Future<void> setAnthropicApiKey(String key) =>
      _secureStorage.write(key: _anthropicKeyKey, value: key);

  Future<String?> getOpenAiApiKey() =>
      _secureStorage.read(key: _openaiKeyKey);

  Future<void> setOpenAiApiKey(String key) =>
      _secureStorage.write(key: _openaiKeyKey, value: key);

  Future<String?> getGeminiApiKey() =>
      _secureStorage.read(key: _geminiKeyKey);

  Future<void> setGeminiApiKey(String key) =>
      _secureStorage.write(key: _geminiKeyKey, value: key);

  Future<String?> getQwenApiKey() =>
      _secureStorage.read(key: _qwenKeyKey);

  Future<void> setQwenApiKey(String key) =>
      _secureStorage.write(key: _qwenKeyKey, value: key);

  Future<String?> getDeepSeekApiKey() =>
      _secureStorage.read(key: _deepseekKeyKey);

  Future<void> setDeepSeekApiKey(String key) =>
      _secureStorage.write(key: _deepseekKeyKey, value: key);

  /// Get API key for any provider type.
  Future<String?> getApiKeyForProvider(ApiProviderType type) => switch (type) {
        ApiProviderType.anthropic => getAnthropicApiKey(),
        ApiProviderType.openai => getOpenAiApiKey(),
        ApiProviderType.gemini => getGeminiApiKey(),
        ApiProviderType.qwen => getQwenApiKey(),
        ApiProviderType.deepseek => getDeepSeekApiKey(),
        _ => Future.value(null),
      };

  /// Set API key for any provider type.
  Future<void> setApiKeyForProvider(ApiProviderType type, String key) =>
      switch (type) {
        ApiProviderType.anthropic => setAnthropicApiKey(key),
        ApiProviderType.openai => setOpenAiApiKey(key),
        ApiProviderType.gemini => setGeminiApiKey(key),
        ApiProviderType.qwen => setQwenApiKey(key),
        ApiProviderType.deepseek => setDeepSeekApiKey(key),
        _ => Future.value(),
      };

  Future<void> clearAllKeys() async {
    await _secureStorage.delete(key: _anthropicKeyKey);
    await _secureStorage.delete(key: _openaiKeyKey);
    await _secureStorage.delete(key: _geminiKeyKey);
    await _secureStorage.delete(key: _qwenKeyKey);
    await _secureStorage.delete(key: _deepseekKeyKey);
  }

  // ── Provider Configuration ──

  Future<void> saveProviderConfig({
    required ApiProviderType type,
    required String model,
    String? baseUrl,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_providerTypeKey, type.name);
    await prefs.setString(_modelKey, model);
    if (baseUrl != null) {
      await prefs.setString(_baseUrlKey, baseUrl);
    }
  }

  Future<ApiConfig?> loadApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_providerTypeKey);

    if (typeStr == null) {
      // Try Gemini by default (NeomClaw default provider)
      final apiKey = await getGeminiApiKey();
      if (apiKey == null) return null;
      return ApiConfig.gemini(apiKey: apiKey);
    }

    final type = ApiProviderType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ApiProviderType.gemini,
    );

    final model = prefs.getString(_modelKey) ?? defaultModel(type);
    final baseUrl = prefs.getString(_baseUrlKey);

    switch (type) {
      case ApiProviderType.gemini:
        final apiKey = await getGeminiApiKey();
        if (apiKey == null) return null;
        return ApiConfig.gemini(apiKey: apiKey, model: model);

      case ApiProviderType.qwen:
        final apiKey = await getQwenApiKey();
        if (apiKey == null) return null;
        return ApiConfig.qwen(apiKey: apiKey, model: model);

      case ApiProviderType.anthropic:
        final apiKey = await getAnthropicApiKey();
        if (apiKey == null) return null;
        return ApiConfig.anthropic(apiKey: apiKey, model: model);

      case ApiProviderType.openai:
        final apiKey = await getOpenAiApiKey();
        return ApiConfig.openai(
          apiKey: apiKey,
          model: model,
          baseUrl: baseUrl ?? 'https://api.openai.com/v1',
        );

      case ApiProviderType.deepseek:
        final apiKey = await getDeepSeekApiKey();
        if (apiKey == null) return null;
        return ApiConfig.deepseek(apiKey: apiKey, model: model);

      case ApiProviderType.ollama:
        return ApiConfig.ollama(
          model: model,
          baseUrl: baseUrl ?? 'http://localhost:11434/v1',
        );

      case ApiProviderType.custom:
      case ApiProviderType.bedrock:
      case ApiProviderType.vertex:
        final apiKey = await getApiKeyForProvider(type);
        return ApiConfig(
          type: type,
          baseUrl: baseUrl ?? 'https://api.openai.com/v1',
          apiKey: apiKey,
          model: model,
        );
    }
  }

  Future<bool> hasValidConfig() async {
    final config = await loadApiConfig();
    return config != null;
  }

  /// Default model for each provider.
  static String defaultModel(ApiProviderType type) => switch (type) {
        ApiProviderType.gemini => 'gemini-2.5-flash',
        ApiProviderType.qwen => 'qwen-plus',
        ApiProviderType.openai => 'gpt-4o',
        ApiProviderType.deepseek => 'deepseek-chat',
        ApiProviderType.anthropic => 'claude-sonnet-4-20250514',
        ApiProviderType.ollama => 'llama3.1',
        _ => 'gpt-4o',
      };

  /// Default base URL for each provider.
  static String defaultBaseUrl(ApiProviderType type) => switch (type) {
        ApiProviderType.gemini =>
          'https://generativelanguage.googleapis.com/v1beta',
        ApiProviderType.qwen =>
          'https://dashscope.aliyuncs.com/compatible-mode/v1',
        ApiProviderType.openai => 'https://api.openai.com/v1',
        ApiProviderType.deepseek => 'https://api.deepseek.com/v1',
        ApiProviderType.anthropic => 'https://api.anthropic.com',
        ApiProviderType.ollama => 'http://localhost:11434/v1',
        _ => 'https://api.openai.com/v1',
      };

  /// Whether a provider requires an API key.
  static bool requiresApiKey(ApiProviderType type) => switch (type) {
        ApiProviderType.ollama => false,
        _ => true,
      };

  /// Provider display name.
  static String providerDisplayName(ApiProviderType type) => switch (type) {
        ApiProviderType.gemini => 'Gemini',
        ApiProviderType.qwen => 'Qwen',
        ApiProviderType.openai => 'OpenAI',
        ApiProviderType.deepseek => 'DeepSeek',
        ApiProviderType.anthropic => 'Anthropic',
        ApiProviderType.ollama => 'Ollama',
        ApiProviderType.custom => 'Custom',
        _ => type.name,
      };
}
