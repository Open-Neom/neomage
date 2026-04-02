import 'package:flutter/material.dart';
import 'package:sint/sint.dart';

import '../../data/api/api_provider.dart';
import '../../data/auth/auth_service.dart';
import '../controllers/chat_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _apiKeyController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _modelController = TextEditingController();

  ApiProviderType _selectedProvider = ApiProviderType.anthropic;
  bool _loading = true;
  bool _obscureKey = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final config = await _authService.loadApiConfig();
    if (config != null) {
      _selectedProvider = config.type;
      _modelController.text = config.model;
      _baseUrlController.text = config.baseUrl;

      final key = config.type == ApiProviderType.anthropic
          ? await _authService.getAnthropicApiKey()
          : await _authService.getOpenAiApiKey();
      _apiKeyController.text = key ?? '';
    }
    setState(() => _loading = false);
  }

  Future<void> _save() async {
    // Save API key
    if (_apiKeyController.text.isNotEmpty) {
      if (_selectedProvider == ApiProviderType.anthropic) {
        await _authService.setAnthropicApiKey(_apiKeyController.text);
      } else {
        await _authService.setOpenAiApiKey(_apiKeyController.text);
      }
    }

    // Save provider config
    await _authService.saveProviderConfig(
      type: _selectedProvider,
      model: _modelController.text.isNotEmpty
          ? _modelController.text
          : _defaultModel,
      baseUrl: _baseUrlController.text.isNotEmpty
          ? _baseUrlController.text
          : null,
    );

    if (!mounted) return;
    final chat = Sint.find<ChatController>();
    await chat.reconfigure();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
    Sint.back();
  }

  String get _defaultModel => switch (_selectedProvider) {
        ApiProviderType.anthropic => 'claude-sonnet-4-20250514',
        ApiProviderType.openai => 'gpt-4o',
        ApiProviderType.ollama => 'llama3.1',
        _ => 'gpt-4o',
      };

  String get _defaultBaseUrl => switch (_selectedProvider) {
        ApiProviderType.anthropic => 'https://api.anthropic.com',
        ApiProviderType.openai => 'https://api.openai.com/v1',
        ApiProviderType.ollama => 'http://localhost:11434/v1',
        _ => 'https://api.openai.com/v1',
      };

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Provider selection
          Text('Provider', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ApiProviderType>(
            segments: const [
              ButtonSegment(
                value: ApiProviderType.anthropic,
                label: Text('Anthropic'),
                icon: Icon(Icons.auto_awesome),
              ),
              ButtonSegment(
                value: ApiProviderType.openai,
                label: Text('OpenAI'),
                icon: Icon(Icons.cloud),
              ),
              ButtonSegment(
                value: ApiProviderType.ollama,
                label: Text('Ollama'),
                icon: Icon(Icons.computer),
              ),
            ],
            selected: {_selectedProvider},
            onSelectionChanged: (selected) {
              setState(() {
                _selectedProvider = selected.first;
                _modelController.text = _defaultModel;
                _baseUrlController.text = _defaultBaseUrl;
              });
            },
          ),

          const SizedBox(height: 24),

          // API Key
          TextField(
            controller: _apiKeyController,
            obscureText: _obscureKey,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: _selectedProvider == ApiProviderType.ollama
                  ? 'Optional for local models'
                  : 'Enter your API key',
              suffixIcon: IconButton(
                icon: Icon(_obscureKey
                    ? Icons.visibility_off
                    : Icons.visibility),
                onPressed: () =>
                    setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Model
          TextField(
            controller: _modelController,
            decoration: InputDecoration(
              labelText: 'Model',
              hintText: _defaultModel,
            ),
          ),

          const SizedBox(height: 16),

          // Base URL
          TextField(
            controller: _baseUrlController,
            decoration: InputDecoration(
              labelText: 'Base URL',
              hintText: _defaultBaseUrl,
            ),
          ),

          const SizedBox(height: 32),

          // Supported models info
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supported Models',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Anthropic: Claude Opus, Sonnet, Haiku\n'
                    '• OpenAI: GPT-4o, GPT-4, o1, o3\n'
                    '• Ollama: Llama, Mistral, CodeGemma, DeepSeek\n'
                    '• Any OpenAI-compatible API endpoint',
                    style: TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
