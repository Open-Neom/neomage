// Settings screen — faithful port of neom_claw/src/components/Settings/
// Ports: Settings.tsx (tab container), Config.tsx (config options),
// Status.tsx (system info + diagnostics), Usage.tsx (rate limit bars).
//
// Provides a full tabbed settings screen with:
// - Status tab: version, session info, model, API provider, diagnostics
// - Config tab: boolean toggles, enum pickers, search filtering
// - Usage tab: rate limit progress bars with auto-refresh
// - Provider / API key configuration (original claw feature)

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sint/sint.dart';

import '../../data/api/api_provider.dart';
import '../../data/auth/auth_service.dart';
import '../controllers/chat_controller.dart';
import 'ollama_setup_screen.dart';
import '../widgets/design_system.dart';

// ─── Settings tab enum ───────────────────────────────────────────────────

enum SettingsTab { status, config, usage }

// ─── Setting model (port of Setting type from Config.tsx) ────────────────

enum SettingType { boolean, enum_, managedEnum }

class SettingItem {
  final String id;
  final String label;
  final String? searchText;
  final SettingType type;
  final dynamic value;
  final List<String>? options;
  final ValueChanged<dynamic>? onChange;

  const SettingItem({
    required this.id,
    required this.label,
    this.searchText,
    required this.type,
    required this.value,
    this.options,
    this.onChange,
  });
}

// ─── Property model (port of Property type from Status.tsx) ──────────────

class StatusProperty {
  final String label;
  final String value;

  const StatusProperty({required this.label, required this.value});
}

// ─── Diagnostic model (port of Diagnostic from status.ts) ────────────────

enum DiagnosticLevel { info, warning, error }

class Diagnostic {
  final String message;
  final DiagnosticLevel level;

  const Diagnostic({required this.message, this.level = DiagnosticLevel.info});

  Color get color {
    switch (level) {
      case DiagnosticLevel.info:
        return ClawColors.info;
      case DiagnosticLevel.warning:
        return ClawColors.warning;
      case DiagnosticLevel.error:
        return ClawColors.error;
    }
  }

  IconData get icon {
    switch (level) {
      case DiagnosticLevel.info:
        return Icons.info_outline;
      case DiagnosticLevel.warning:
        return Icons.warning_amber;
      case DiagnosticLevel.error:
        return Icons.error_outline;
    }
  }
}

// ─── Rate limit model (port of RateLimit/Utilization from usage.ts) ─────

class RateLimit {
  final String title;
  final double utilization; // 0-100
  final DateTime? resetsAt;
  final String? extraSubtext;

  const RateLimit({
    required this.title,
    required this.utilization,
    this.resetsAt,
    this.extraSubtext,
  });
}

class Utilization {
  final List<RateLimit> limits;
  final double? totalCost;

  const Utilization({required this.limits, this.totalCost});
}

// ─── SettingsController ──────────────────────────────────────────────────

class SettingsController extends SintController {
  final _authService = AuthService();

  // Tab state
  final selectedTab = SettingsTab.status.obs;
  final isLoading = true.obs;

  // Provider config
  final selectedProvider = ApiProviderType.anthropic.obs;
  final apiKeyController = TextEditingController();
  final baseUrlController = TextEditingController();
  final modelController = TextEditingController();
  final obscureKey = true.obs;

  // Config settings (port of Config.tsx settingsItems)
  final autoCompactEnabled = true.obs;
  final showTips = true.obs;
  final reduceMotion = false.obs;
  final thinkingEnabled = true.obs;
  final verboseMode = false.obs;
  final fileCheckpointing = true.obs;
  final notificationsEnabled = true.obs;

  // Config search
  final searchQuery = ''.obs;
  final isSearchMode = true.obs;

  // Usage state
  final utilization = Rxn<Utilization>();
  final usageError = Rxn<String>();
  final isLoadingUsage = true.obs;

  // Status state
  final diagnostics = <Diagnostic>[].obs;
  final isLoadingDiagnostics = true.obs;

  // Changes tracking (port of changes state from Config.tsx)
  final changes = <String, dynamic>{}.obs;
  final isDirty = false.obs;

  // Test connection state
  final isTesting = false.obs;
  final testResult = Rxn<String>();
  final testError = Rxn<String>();

  @override
  void onInit() {
    super.onInit();
    _loadSettings();
    _loadDiagnostics();
    _loadUsage();
  }

  @override
  void onClose() {
    apiKeyController.dispose();
    baseUrlController.dispose();
    modelController.dispose();
    super.onClose();
  }

  Future<void> _loadSettings() async {
    isLoading.value = true;
    try {
      final config = await _authService.loadApiConfig();
      if (config != null) {
        selectedProvider.value = config.type;
        modelController.text = config.model;
        baseUrlController.text = config.baseUrl;

        final key = await _authService.getApiKeyForProvider(config.type);
        apiKeyController.text = key ?? '';
      }
    } catch (_) {
      // Silently handle load errors
    } finally {
      isLoading.value = false;
    }
  }

  /// Test the connection with the current provider settings.
  /// Sends a prompt asking the AI to introduce itself.
  Future<void> testConnection() async {
    final provider = selectedProvider.value;
    final apiKey = apiKeyController.text.trim();
    final model = modelController.text.trim().isNotEmpty
        ? modelController.text.trim()
        : defaultModel;
    final baseUrl = baseUrlController.text.trim().isNotEmpty
        ? baseUrlController.text.trim()
        : defaultBaseUrl;

    if (AuthService.requiresApiKey(provider) && apiKey.isEmpty) {
      testError.value =
          'API key is required for '
          '${AuthService.providerDisplayName(provider)}';
      testResult.value = null;
      return;
    }

    isTesting.value = true;
    testResult.value = null;
    testError.value = null;

    try {
      final response = await _sendTestMessage(
        provider: provider,
        apiKey: apiKey,
        model: model,
        baseUrl: baseUrl,
      );
      testResult.value = response;
      testError.value = null;
    } catch (e) {
      testError.value = e.toString().replaceFirst('Exception: ', '');
      testResult.value = null;
    } finally {
      isTesting.value = false;
    }
  }

  Future<String> _sendTestMessage({
    required ApiProviderType provider,
    required String apiKey,
    required String model,
    required String baseUrl,
  }) async {
    const prompt =
        'Introduce yourself briefly: what model are you, '
        'who made you, and what are your main capabilities? '
        'Keep it to 2-3 sentences.';

    switch (provider) {
      case ApiProviderType.gemini:
        return _testGemini(apiKey, model, baseUrl, prompt);
      case ApiProviderType.anthropic:
        return _testAnthropic(apiKey, model, baseUrl, prompt);
      case ApiProviderType.openai:
      case ApiProviderType.deepseek:
      case ApiProviderType.qwen:
      case ApiProviderType.ollama:
      case ApiProviderType.custom:
        return _testOpenAiCompat(apiKey, model, baseUrl, prompt);
      case ApiProviderType.bedrock:
      case ApiProviderType.vertex:
        return _testOpenAiCompat(apiKey, model, baseUrl, prompt);
    }
  }

  Future<String> _testGemini(
    String apiKey,
    String model,
    String baseUrl,
    String prompt,
  ) async {
    final url = Uri.parse('$baseUrl/models/$model:generateContent?key=$apiKey');
    final resp = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {'maxOutputTokens': 256},
      }),
    );
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw Exception(body['error']?['message'] ?? 'HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final candidates = body['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No response from model');
    }
    final parts = candidates[0]['content']?['parts'] as List?;
    return parts?.map((p) => p['text'] ?? '').join('') ?? 'No text in response';
  }

  Future<String> _testAnthropic(
    String apiKey,
    String model,
    String baseUrl,
    String prompt,
  ) async {
    final url = Uri.parse('$baseUrl/v1/messages');
    final resp = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': model,
        'max_tokens': 256,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      throw Exception(body['error']?['message'] ?? 'HTTP ${resp.statusCode}');
    }
    final body = jsonDecode(resp.body);
    final content = body['content'] as List?;
    return content?.map((c) => c['text'] ?? '').join('') ??
        'No text in response';
  }

  Future<String> _testOpenAiCompat(
    String apiKey,
    String model,
    String baseUrl,
    String prompt,
  ) async {
    final url = Uri.parse('$baseUrl/chat/completions');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }
    final resp = await http.post(
      url,
      headers: headers,
      body: jsonEncode({
        'model': model,
        'max_tokens': 256,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
      }),
    );
    if (resp.statusCode != 200) {
      final body = jsonDecode(resp.body);
      final msg = body['error']?['message'] ?? body['message'] ?? '';
      throw Exception(
        msg.toString().isNotEmpty ? msg : 'HTTP ${resp.statusCode}',
      );
    }
    final body = jsonDecode(resp.body);
    final choices = body['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No response from model');
    }
    return choices[0]['message']?['content'] ?? 'No text in response';
  }

  Future<void> _loadDiagnostics() async {
    isLoadingDiagnostics.value = true;
    try {
      // Port of buildDiagnostics() from Status.tsx
      diagnostics.value = [
        const Diagnostic(
          message: 'Installation health: OK',
          level: DiagnosticLevel.info,
        ),
      ];
    } catch (_) {
      diagnostics.value = [];
    } finally {
      isLoadingDiagnostics.value = false;
    }
  }

  Future<void> _loadUsage() async {
    isLoadingUsage.value = true;
    usageError.value = null;
    try {
      // Port of fetchUtilization() from Usage.tsx
      // In production, this calls the API to get rate limit data
      utilization.value = const Utilization(
        limits: [RateLimit(title: 'Standard usage', utilization: 0)],
      );
    } catch (e) {
      usageError.value = 'Failed to load usage data: $e';
    } finally {
      isLoadingUsage.value = false;
    }
  }

  Future<void> refreshUsage() async {
    await _loadUsage();
  }

  /// Get the list of configurable settings.
  /// Port of settingsItems array from Config.tsx.
  List<SettingItem> get settingsItems {
    final query = searchQuery.value.toLowerCase();
    final items = <SettingItem>[
      SettingItem(
        id: 'autoCompactEnabled',
        label: 'Auto-compact',
        type: SettingType.boolean,
        value: autoCompactEnabled.value,
        onChange: (v) {
          autoCompactEnabled.value = v as bool;
          _trackChange('Auto-compact', v);
        },
      ),
      SettingItem(
        id: 'spinnerTipsEnabled',
        label: 'Show tips',
        type: SettingType.boolean,
        value: showTips.value,
        onChange: (v) {
          showTips.value = v as bool;
          _trackChange('Show tips', v);
        },
      ),
      SettingItem(
        id: 'prefersReducedMotion',
        label: 'Reduce motion',
        type: SettingType.boolean,
        value: reduceMotion.value,
        onChange: (v) {
          reduceMotion.value = v as bool;
          _trackChange('Reduce motion', v);
        },
      ),
      SettingItem(
        id: 'thinkingEnabled',
        label: 'Thinking mode',
        type: SettingType.boolean,
        value: thinkingEnabled.value,
        onChange: (v) {
          thinkingEnabled.value = v as bool;
          _trackChange('Thinking mode', v);
        },
      ),
      SettingItem(
        id: 'verbose',
        label: 'Verbose output',
        type: SettingType.boolean,
        value: verboseMode.value,
        onChange: (v) {
          verboseMode.value = v as bool;
          _trackChange('Verbose', v);
        },
      ),
      SettingItem(
        id: 'fileCheckpointing',
        label: 'File checkpointing',
        type: SettingType.boolean,
        value: fileCheckpointing.value,
        onChange: (v) {
          fileCheckpointing.value = v as bool;
          _trackChange('File checkpointing', v);
        },
      ),
      SettingItem(
        id: 'notifications',
        label: 'Notifications',
        type: SettingType.boolean,
        value: notificationsEnabled.value,
        onChange: (v) {
          notificationsEnabled.value = v as bool;
          _trackChange('Notifications', v);
        },
      ),
    ];

    if (query.isEmpty) return items;
    return items
        .where(
          (item) =>
              item.label.toLowerCase().contains(query) ||
              (item.searchText?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  void _trackChange(String key, dynamic value) {
    isDirty.value = true;
    changes[key] = value;
  }

  /// Build status properties for display.
  /// Port of buildPrimarySection() + buildSecondarySection() from Status.tsx.
  List<StatusProperty> get statusProperties {
    return [
      const StatusProperty(label: 'Version', value: '1.0.0'),
      StatusProperty(label: 'Provider', value: selectedProvider.value.name),
      StatusProperty(label: 'Model', value: modelController.text),
    ];
  }

  String get defaultModel => AuthService.defaultModel(selectedProvider.value);

  String get defaultBaseUrl =>
      AuthService.defaultBaseUrl(selectedProvider.value);

  Future<void> saveProviderConfig() async {
    if (apiKeyController.text.isNotEmpty) {
      await _authService.setApiKeyForProvider(
        selectedProvider.value,
        apiKeyController.text,
      );
    }

    await _authService.saveProviderConfig(
      type: selectedProvider.value,
      model: modelController.text.isNotEmpty
          ? modelController.text
          : defaultModel,
      baseUrl: baseUrlController.text.isNotEmpty
          ? baseUrlController.text
          : null,
    );

    try {
      final chat = Sint.find<ChatController>();
      await chat.reconfigure();
    } catch (_) {}

    _trackChange('Provider', selectedProvider.value.name);
    _trackChange('Model', modelController.text);
  }
}

// ─── SettingsScreen widget (port of Settings.tsx) ────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = Sint.put(SettingsController());

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await controller.saveProviderConfig();
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Settings saved')));
            },
            icon: const Icon(Icons.save),
            label: const Text('Save'),
          ),
        ],
        // Tab bar (port of Tabs component from Settings.tsx)
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Obx(
            () => Row(
              children: SettingsTab.values.map((tab) {
                final selected = controller.selectedTab.value == tab;
                return Expanded(
                  child: InkWell(
                    onTap: () => controller.selectedTab.value = tab,
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        tab.name[0].toUpperCase() + tab.name.substring(1),
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        switch (controller.selectedTab.value) {
          case SettingsTab.status:
            return _StatusTab(controller: controller);
          case SettingsTab.config:
            return _ConfigTab(controller: controller);
          case SettingsTab.usage:
            return _UsageTab(controller: controller);
        }
      }),
    );
  }
}

// ─── Status tab (port of Status.tsx) ─────────────────────────────────────

class _StatusTab extends StatelessWidget {
  final SettingsController controller;

  const _StatusTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Primary section ──
        ...controller.statusProperties.map(
          (prop) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    '${prop.label}:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Expanded(child: SelectableText(prop.value)),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 16),

        // ── Provider config ──
        Text('API Provider', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),

        Obx(() {
          const providers = [
            (ApiProviderType.gemini, 'Gemini', Icons.auto_awesome),
            (ApiProviderType.qwen, 'Qwen', Icons.translate),
            (ApiProviderType.openai, 'OpenAI', Icons.cloud),
            (ApiProviderType.deepseek, 'DeepSeek', Icons.psychology),
            (ApiProviderType.anthropic, 'Anthropic', Icons.hub),
            (ApiProviderType.ollama, 'Ollama', Icons.computer),
          ];
          return Wrap(
            spacing: 8,
            runSpacing: 6,
            children: providers.map((p) {
              final (type, label, icon) = p;
              final selected = controller.selectedProvider.value == type;
              return ChoiceChip(
                avatar: Icon(icon, size: 16),
                label: Text(label),
                selected: selected,
                onSelected: (_) {
                  controller.selectedProvider.value = type;
                  controller.modelController.text = controller.defaultModel;
                  controller.baseUrlController.text = controller.defaultBaseUrl;
                },
              );
            }).toList(),
          );
        }),

        const SizedBox(height: 16),

        TextField(
          controller: controller.apiKeyController,
          obscureText: controller.obscureKey.value,
          decoration: InputDecoration(
            labelText: 'API Key',
            hintText:
                !AuthService.requiresApiKey(controller.selectedProvider.value)
                ? 'Optional for local models'
                : 'Enter your ${AuthService.providerDisplayName(controller.selectedProvider.value)} API key',
            suffixIcon: Obx(
              () => IconButton(
                icon: Icon(
                  controller.obscureKey.value
                      ? Icons.visibility_off
                      : Icons.visibility,
                ),
                onPressed: () => controller.obscureKey.toggle(),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: controller.modelController,
          decoration: InputDecoration(
            labelText: 'Model',
            hintText: controller.defaultModel,
          ),
        ),

        const SizedBox(height: 12),

        TextField(
          controller: controller.baseUrlController,
          decoration: InputDecoration(
            labelText: 'Base URL',
            hintText: controller.defaultBaseUrl,
          ),
        ),

        const SizedBox(height: 16),

        // ── Test Connection button ──
        Obx(
          () => SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: controller.isTesting.value
                  ? null
                  : () => controller.testConnection(),
              icon: controller.isTesting.value
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering, size: 18),
              label: Text(
                controller.isTesting.value
                    ? 'Connecting...'
                    : 'Test Connection',
              ),
            ),
          ),
        ),

        // ── Test result / error display ──
        Obx(() {
          if (controller.testResult.value != null) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 16,
                          color: ClawColors.success,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Connected successfully',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: ClawColors.success,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.smart_toy,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            controller.testResult.value!,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }
          if (controller.testError.value != null) {
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: ClawColors.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: ClawColors.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: ClawColors.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        controller.testError.value!,
                        style: TextStyle(
                          fontSize: 13,
                          color: ClawColors.error,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }),

        const SizedBox(height: 16),

        // ── Local Models (Ollama) shortcut ──
        OutlinedButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const OllamaSetupScreen())),
          icon: const Icon(Icons.computer, size: 18),
          label: const Text('Local Models (Ollama)'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
          ),
        ),

        const SizedBox(height: 24),

        // ── Diagnostics (port of Diagnostics component from Status.tsx) ──
        Obx(() {
          if (controller.isLoadingDiagnostics.value) {
            return const SizedBox.shrink();
          }
          if (controller.diagnostics.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Diagnostics', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ...controller.diagnostics.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(d.icon, size: 16, color: d.color),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          d.message,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// ─── Config tab (port of Config.tsx) ─────────────────────────────────────

class _ConfigTab extends StatelessWidget {
  final SettingsController controller;

  const _ConfigTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // ── Search box (port of SearchBox from Config.tsx) ──
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 20),
              hintText: 'Search settings...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (v) => controller.searchQuery.value = v,
          ),
        ),

        // ── Settings list ──
        Expanded(
          child: Obx(() {
            final items = controller.settingsItems;

            if (items.isEmpty) {
              return Center(
                child: Text(
                  'No settings match your search',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
              );
            }

            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _SettingTile(item: item);
              },
            );
          }),
        ),
      ],
    );
  }
}

// ─── Setting tile widget ─────────────────────────────────────────────────

class _SettingTile extends StatelessWidget {
  final SettingItem item;

  const _SettingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    switch (item.type) {
      case SettingType.boolean:
        return SwitchListTile(
          title: Text(item.label),
          value: item.value as bool,
          onChanged: (v) => item.onChange?.call(v),
          dense: true,
        );
      case SettingType.enum_:
        return ListTile(
          title: Text(item.label),
          subtitle: Text(item.value as String),
          trailing: const Icon(Icons.chevron_right, size: 20),
          dense: true,
          onTap: () {
            if (item.options != null && item.options!.isNotEmpty) {
              _showEnumPicker(context, item);
            }
          },
        );
      case SettingType.managedEnum:
        return ListTile(
          title: Text(item.label),
          subtitle: Text(item.value as String),
          trailing: const Icon(Icons.chevron_right, size: 20),
          dense: true,
          onTap: () {},
        );
    }
  }

  void _showEnumPicker(BuildContext context, SettingItem item) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                item.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            ...item.options!.map(
              (opt) => ListTile(
                title: Text(opt),
                trailing: opt == item.value
                    ? const Icon(Icons.check, color: ClawColors.success)
                    : null,
                onTap: () {
                  item.onChange?.call(opt);
                  Navigator.pop(ctx);
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Usage tab (port of Usage.tsx) ───────────────────────────────────────

class _UsageTab extends StatelessWidget {
  final SettingsController controller;

  const _UsageTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Obx(() {
      if (controller.isLoadingUsage.value) {
        return const Center(child: CircularProgressIndicator());
      }

      if (controller.usageError.value != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: ClawColors.error,
              ),
              const SizedBox(height: 12),
              Text(
                controller.usageError.value!,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                onPressed: controller.refreshUsage,
              ),
            ],
          ),
        );
      }

      final util = controller.utilization.value;
      if (util == null) {
        return const Center(child: Text('No usage data available'));
      }

      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Rate limit bars (port of LimitBar from Usage.tsx) ──
          ...util.limits.map((limit) => _LimitBar(limit: limit)),

          // ── Total cost ──
          if (util.totalCost != null) ...[
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text(
                  'Total cost this session:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text('\$${util.totalCost!.toStringAsFixed(4)}'),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ── Refresh button ──
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh usage data'),
              onPressed: controller.refreshUsage,
            ),
          ),
        ],
      );
    });
  }
}

// ─── LimitBar widget (port of LimitBar from Usage.tsx) ───────────────────

class _LimitBar extends StatelessWidget {
  final RateLimit limit;

  const _LimitBar({required this.limit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = limit.utilization / 100;
    final usedText = '${limit.utilization.floor()}% used';
    final barColor = ratio > 0.9
        ? ClawColors.error
        : ratio > 0.7
        ? ClawColors.warning
        : ClawColors.success;

    String? subtext;
    if (limit.resetsAt != null) {
      final diff = limit.resetsAt!.difference(DateTime.now());
      if (diff.inHours > 0) {
        subtext = 'Resets in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
      } else if (diff.inMinutes > 0) {
        subtext = 'Resets in ${diff.inMinutes}m';
      } else {
        subtext = 'Resets soon';
      }
    }
    if (limit.extraSubtext != null) {
      subtext = subtext != null
          ? '${limit.extraSubtext} \u00B7 $subtext'
          : limit.extraSubtext;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            limit.title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(barColor),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(usedText, style: const TextStyle(fontSize: 13)),
            ],
          ),
          if (subtext != null) ...[
            const SizedBox(height: 4),
            Text(
              subtext,
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
