import 'package:shared_preferences/shared_preferences.dart';

/// App-wide settings — port of openclaude's configuration system.
class AppSettings {
  static const _themeKey = 'theme_mode';
  static const _maxTokensKey = 'max_tokens';
  static const _streamingKey = 'streaming_enabled';
  static const _systemPromptKey = 'custom_system_prompt';

  final SharedPreferences _prefs;

  AppSettings(this._prefs);

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(prefs);
  }

  // ── Theme ──

  String get themeMode => _prefs.getString(_themeKey) ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString(_themeKey, mode);

  // ── API Settings ──

  int get maxTokens => _prefs.getInt(_maxTokensKey) ?? 16384;
  Future<void> setMaxTokens(int tokens) =>
      _prefs.setInt(_maxTokensKey, tokens);

  bool get streamingEnabled => _prefs.getBool(_streamingKey) ?? true;
  Future<void> setStreamingEnabled(bool enabled) =>
      _prefs.setBool(_streamingKey, enabled);

  // ── System Prompt ──

  String? get customSystemPrompt => _prefs.getString(_systemPromptKey);
  Future<void> setCustomSystemPrompt(String? prompt) async {
    if (prompt == null) {
      await _prefs.remove(_systemPromptKey);
    } else {
      await _prefs.setString(_systemPromptKey, prompt);
    }
  }

  /// Default system prompt — matches openclaude's system.ts.
  static const defaultSystemPrompt =
      'You are OpenClaude, an AI coding assistant powered by Flutter. '
      'You help users with software engineering tasks including writing code, '
      'debugging, refactoring, and explaining code. '
      'You have access to tools for reading files, writing files, '
      'editing files, searching code, and executing shell commands.';
}
