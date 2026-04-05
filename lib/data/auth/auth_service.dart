import 'package:hive_flutter/hive_flutter.dart';
import 'package:sint_sentinel/sint_sentinel.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_provider.dart';

/// Auth service — manages API keys and provider configuration.
/// Uses Hive for key storage (cross-platform, no entitlements needed).
class AuthService {
  static const _anthropicKeyKey = 'anthropic_api_key';
  static const _openaiKeyKey = 'openai_api_key';
  static const _geminiKeyKey = 'gemini_api_key';
  static const _qwenKeyKey = 'qwen_api_key';
  static const _deepseekKeyKey = 'deepseek_api_key';
  static const _providerTypeKey = 'provider_type';
  static const _modelKey = 'model';
  static const _baseUrlKey = 'custom_base_url';
  static const _onboardingCompleteKey = 'onboarding_complete';

  static const _boxName = 'neomage_auth';

  AuthService();

  Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_boxName)) return Hive.box(_boxName);
    return Hive.openBox(_boxName);
  }

  // ── API Key Management ──

  Future<String?> _readKey(String key) async {
    final box = await _openBox();
    return box.get(key) as String?;
  }

  Future<void> _writeKey(String key, String value) async {
    final box = await _openBox();
    await box.put(key, value);
  }

  Future<void> _deleteKey(String key) async {
    final box = await _openBox();
    await box.delete(key);
  }

  Future<String?> getAnthropicApiKey() => _readKey(_anthropicKeyKey);
  Future<void> setAnthropicApiKey(String key) => _writeKey(_anthropicKeyKey, key);

  Future<String?> getOpenAiApiKey() => _readKey(_openaiKeyKey);
  Future<void> setOpenAiApiKey(String key) => _writeKey(_openaiKeyKey, key);

  Future<String?> getGeminiApiKey() => _readKey(_geminiKeyKey);
  Future<void> setGeminiApiKey(String key) => _writeKey(_geminiKeyKey, key);

  Future<String?> getQwenApiKey() => _readKey(_qwenKeyKey);
  Future<void> setQwenApiKey(String key) => _writeKey(_qwenKeyKey, key);

  Future<String?> getDeepSeekApiKey() => _readKey(_deepseekKeyKey);
  Future<void> setDeepSeekApiKey(String key) => _writeKey(_deepseekKeyKey, key);

  Future<String?> getApiKeyForProvider(ApiProviderType type) => switch (type) {
    ApiProviderType.anthropic => getAnthropicApiKey(),
    ApiProviderType.openai => getOpenAiApiKey(),
    ApiProviderType.gemini => getGeminiApiKey(),
    ApiProviderType.qwen => getQwenApiKey(),
    ApiProviderType.deepseek => getDeepSeekApiKey(),
    _ => Future.value(null),
  };

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
    await _deleteKey(_anthropicKeyKey);
    await _deleteKey(_openaiKeyKey);
    await _deleteKey(_geminiKeyKey);
    await _deleteKey(_qwenKeyKey);
    await _deleteKey(_deepseekKeyKey);
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
    SintSentinel.logger.i('Saved provider config: ${type.name}, model: $model');
  }

  Future<ApiConfig?> loadApiConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_providerTypeKey);

    SintSentinel.logger.d('Loading API config for provider: $typeStr');

    if (typeStr == null) {
      final apiKey = await getGeminiApiKey();
      if (apiKey == null) {
        SintSentinel.logger.w('No API key found for gemini (default)');
        return null;
      }
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

  static String defaultModel(ApiProviderType type) => switch (type) {
    ApiProviderType.gemini => 'gemini-2.5-flash',
    ApiProviderType.qwen => 'qwen-plus',
    ApiProviderType.openai => 'gpt-4o',
    ApiProviderType.deepseek => 'deepseek-chat',
    ApiProviderType.anthropic => 'claude-sonnet-4-20250514',
    ApiProviderType.ollama => 'llama3.1',
    _ => 'gpt-4o',
  };

  static String defaultBaseUrl(ApiProviderType type) => switch (type) {
    ApiProviderType.gemini =>
      'https://generativelanguage.googleapis.com/v1beta',
    ApiProviderType.qwen => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    ApiProviderType.openai => 'https://api.openai.com/v1',
    ApiProviderType.deepseek => 'https://api.deepseek.com/v1',
    ApiProviderType.anthropic => 'https://api.anthropic.com',
    ApiProviderType.ollama => 'http://localhost:11434/v1',
    _ => 'https://api.openai.com/v1',
  };

  // ── Onboarding flag ──

  Future<bool> isOnboardingComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_onboardingCompleteKey) ?? false;
  }

  Future<void> setOnboardingComplete([bool complete = true]) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingCompleteKey, complete);
    SintSentinel.logger.i('Onboarding marked as ${complete ? "complete" : "incomplete"}');
  }

  static bool requiresApiKey(ApiProviderType type) => switch (type) {
    ApiProviderType.ollama => false,
    _ => true,
  };

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
