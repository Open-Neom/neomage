import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_provider.dart';

/// Auth service — manages API keys and provider configuration.
/// Port of openclaude/src/utils/auth.ts core functionality.
class AuthService {
  static const _anthropicKeyKey = 'anthropic_api_key';
  static const _openaiKeyKey = 'openai_api_key';
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

  Future<void> clearAllKeys() async {
    await _secureStorage.delete(key: _anthropicKeyKey);
    await _secureStorage.delete(key: _openaiKeyKey);
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
      // Try Anthropic by default
      final apiKey = await getAnthropicApiKey();
      if (apiKey == null) return null;
      return ApiConfig.anthropic(apiKey: apiKey);
    }

    final type = ApiProviderType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => ApiProviderType.anthropic,
    );

    final model = prefs.getString(_modelKey) ?? _defaultModel(type);
    final baseUrl = prefs.getString(_baseUrlKey);

    switch (type) {
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

      case ApiProviderType.ollama:
        return ApiConfig.ollama(
          model: model,
          baseUrl: baseUrl ?? 'http://localhost:11434/v1',
        );

      default:
        final apiKey = await getOpenAiApiKey();
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

  String _defaultModel(ApiProviderType type) => switch (type) {
        ApiProviderType.anthropic => 'claude-sonnet-4-20250514',
        ApiProviderType.openai => 'gpt-4o',
        ApiProviderType.ollama => 'llama3.1',
        _ => 'gpt-4o',
      };
}
