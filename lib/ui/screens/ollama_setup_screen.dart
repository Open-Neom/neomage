// Ollama Setup Screen — local model discovery, download, and configuration.
// Allows users to install and run local models without any cloud API key.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sint/sint.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:neomage/data/api/api_provider.dart';
import 'package:neomage/data/auth/auth_service.dart';
import 'package:neomage/data/services/ollama_service.dart';
import '../../utils/constants/neomage_translation_constants.dart';
import '../controllers/chat_controller.dart';

// ─── Controller ──

class OllamaSetupController extends SintController {
  final OllamaService _ollama = OllamaService();
  final AuthService _auth = AuthService();

  final status = OllamaStatus.unknown.obs;
  final models = <OllamaModel>[].obs;
  final selectedModel = Rxn<String>();
  final isRefreshing = false.obs;
  final isPulling = false.obs;
  final pullProgress = Rxn<OllamaPullProgress>();
  final pullModelName = ''.obs;
  final testResult = Rxn<String>();
  final testError = Rxn<String>();
  final isTesting = false.obs;

  @override
  void onInit() {
    super.onInit();
    refresh();
  }

  @override
  Future<void> refresh() async {
    isRefreshing.value = true;
    status.value = OllamaStatus.checking;

    final s = await _ollama.checkStatus();
    status.value = s;

    if (s == OllamaStatus.running) {
      final m = await _ollama.listModels();
      models.value = m;
      if (selectedModel.value == null && m.isNotEmpty) {
        selectedModel.value = m.first.name;
      }
    } else {
      models.clear();
    }

    isRefreshing.value = false;
  }

  Future<void> pullModel(String name) async {
    isPulling.value = true;
    pullModelName.value = name;
    pullProgress.value = null;

    await for (final p in _ollama.pullModel(name)) {
      pullProgress.value = p;
      if (p.isDone || p.isError) break;
    }

    isPulling.value = false;

    if (pullProgress.value?.isDone == true) {
      await refresh();
      selectedModel.value = name;
    }
  }

  Future<void> deleteModel(String name) async {
    await _ollama.deleteModel(name);
    await refresh();
    if (selectedModel.value == name) {
      selectedModel.value = models.isNotEmpty ? models.first.name : null;
    }
  }

  Future<void> testModel() async {
    final model = selectedModel.value;
    if (model == null) return;

    isTesting.value = true;
    testResult.value = null;
    testError.value = null;

    try {
      final result = await _ollama.testChat(
        model,
        'Introduce yourself in one sentence: what model are you and what can you do?',
      );
      testResult.value = result;
    } catch (e) {
      testError.value = e.toString().replaceFirst('Exception: ', '');
    }

    isTesting.value = false;
  }

  Future<void> activateModel() async {
    final model = selectedModel.value;
    if (model == null) return;

    await _auth.saveProviderConfig(
      type: ApiProviderType.ollama,
      model: model,
      baseUrl: _ollama.openAiBaseUrl,
    );

    try {
      final chat = Sint.find<ChatController>();
      await chat.reconfigure();
    } catch (_) {}
  }
}

// ─── Screen ──

class OllamaSetupScreen extends StatelessWidget {
  /// When true, renders without Scaffold/AppBar (for embedding as a tab).
  final bool embedded;

  const OllamaSetupScreen({super.key, this.embedded = false});

  @override
  Widget build(BuildContext context) {
    final ctrl = Sint.put(OllamaSetupController());
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (embedded) {
      return _OllamaBody(ctrl: ctrl, cs: cs, isDark: isDark);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(NeomageTranslationConstants.localModelsOllama.tr),
        actions: [
          Obx(
            () => IconButton(
              onPressed: ctrl.isRefreshing.value ? null : ctrl.refresh,
              icon: ctrl.isRefreshing.value
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              tooltip: NeomageTranslationConstants.refresh.tr,
            ),
          ),
        ],
      ),
      body: _OllamaBody(ctrl: ctrl, cs: cs, isDark: isDark),
    );
  }

  void _confirmDelete(
    BuildContext context,
    OllamaSetupController ctrl,
    OllamaModel model,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(NeomageTranslationConstants.deleteModel.tr),
        content: Text(
          NeomageTranslationConstants.deleteModelConfirm.tr
              .replaceAll('@model', model.displayName)
              .replaceAll('@size', model.sizeLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(NeomageTranslationConstants.cancel.tr),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.deleteModel(model.name);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(NeomageTranslationConstants.delete.tr),
          ),
        ],
      ),
    );
  }
}

// ─── Ollama body (reusable — used standalone and embedded in settings) ──

class _OllamaBody extends StatelessWidget {
  final OllamaSetupController ctrl;
  final ColorScheme cs;
  final bool isDark;

  const _OllamaBody({
    required this.ctrl,
    required this.cs,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Refresh bar (for embedded mode) ──
              Row(
                children: [
                  Text(
                    NeomageTranslationConstants.localModelsOllama.tr,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const Spacer(),
                  Obx(
                    () => IconButton(
                      onPressed: ctrl.isRefreshing.value ? null : ctrl.refresh,
                      icon: ctrl.isRefreshing.value
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh, size: 20),
                      tooltip: NeomageTranslationConstants.refresh.tr,
                      iconSize: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Status card ──
              Obx(
                () => _StatusCard(
                  status: ctrl.status.value,
                  onRetry: ctrl.refresh,
                ),
              ),

              const SizedBox(height: 24),

              // ── Installed models ──
              Obx(() {
                if (ctrl.status.value != OllamaStatus.running) {
                  return const SizedBox.shrink();
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NeomageTranslationConstants.installedModels.tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (ctrl.models.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.download_outlined, size: 40,
                                color: cs.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(
                              NeomageTranslationConstants.noModelsInstalled.tr,
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              NeomageTranslationConstants.downloadModelBelow.tr,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...ctrl.models.map(
                        (m) => _ModelTile(
                          model: m,
                          isSelected: ctrl.selectedModel.value == m.name,
                          onSelect: () => ctrl.selectedModel.value = m.name,
                          onDelete: () => _confirmDelete(context, ctrl, m),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Test & Activate buttons ──
                    if (ctrl.models.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Obx(
                            () => OutlinedButton.icon(
                              onPressed: ctrl.isTesting.value ||
                                      ctrl.selectedModel.value == null
                                  ? null
                                  : ctrl.testModel,
                              icon: ctrl.isTesting.value
                                  ? const SizedBox(
                                      width: 14, height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.wifi_tethering, size: 16),
                              label: Text(
                                ctrl.isTesting.value
                                    ? NeomageTranslationConstants.testing.tr
                                    : NeomageTranslationConstants.testModel.tr,
                              ),
                            ),
                          ),
                          Obx(
                            () => FilledButton.icon(
                              onPressed: ctrl.selectedModel.value == null
                                  ? null
                                  : () async {
                                      await ctrl.activateModel();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              '${ctrl.selectedModel.value} ${NeomageTranslationConstants.activatedAsDefault.tr}',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                              icon: const Icon(Icons.check_circle, size: 16),
                              label: Text(NeomageTranslationConstants.useThisModel.tr),
                            ),
                          ),
                        ],
                      ),

                    // ── Test result ──
                    Obx(() {
                      if (ctrl.testResult.value != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Colors.green.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.smart_toy, size: 16,
                                    color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    ctrl.testResult.value!,
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      if (ctrl.testError.value != null) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              ctrl.testError.value!,
                              style: TextStyle(fontSize: 13, color: cs.error),
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),

                    const SizedBox(height: 32),
                  ],
                );
              }),

              // ── Download recommended models ──
              Obx(() {
                if (ctrl.status.value != OllamaStatus.running) {
                  return const SizedBox.shrink();
                }

                final installed = ctrl.models.map((m) => m.name).toSet();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      NeomageTranslationConstants.downloadModels.tr,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      NeomageTranslationConstants.recommendedModels.tr,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...ollamaRecommendedModels.map((rec) {
                      final isInstalled = installed.any(
                        (n) => n.startsWith(rec.name.split(':').first),
                      );

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isInstalled
                              ? Icons.check_circle
                              : Icons.download_outlined,
                          color: isInstalled ? Colors.green : cs.primary,
                          size: 20,
                        ),
                        title: Text(
                          rec.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${rec.desc} · ${rec.size}',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        trailing: isInstalled
                            ? Text(
                                NeomageTranslationConstants.installed.tr,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.green.shade400,
                                ),
                              )
                            : Obx(
                                () => ctrl.isPulling.value &&
                                        ctrl.pullModelName.value == rec.name
                                    ? SizedBox(
                                        width: 80,
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            LinearProgressIndicator(
                                              value: ctrl.pullProgress.value
                                                  ?.progress,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              ctrl.pullProgress.value?.status ??
                                                  '',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: cs.onSurfaceVariant,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      )
                                    : TextButton(
                                        onPressed: ctrl.isPulling.value
                                            ? null
                                            : () => ctrl.pullModel(rec.name),
                                        child: Text(
                                          NeomageTranslationConstants
                                              .download.tr,
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                              ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Custom model pull
                    _CustomPullField(
                      onPull: (name) => ctrl.pullModel(name),
                      isPulling: ctrl.isPulling,
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    OllamaSetupController ctrl,
    OllamaModel model,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(NeomageTranslationConstants.deleteModel.tr),
        content: Text(
          NeomageTranslationConstants.deleteModelConfirm.tr
              .replaceAll('@model', model.displayName)
              .replaceAll('@size', model.sizeLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(NeomageTranslationConstants.cancel.tr),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ctrl.deleteModel(model.name);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(NeomageTranslationConstants.delete.tr),
          ),
        ],
      ),
    );
  }
}

// ─── Status card ──

class _StatusCard extends StatelessWidget {
  final OllamaStatus status;
  final VoidCallback onRetry;

  const _StatusCard({required this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (icon, color, title, subtitle, action) = switch (status) {
      OllamaStatus.checking => (
        Icons.hourglass_empty,
        Colors.amber,
        'Checking Ollama...',
        'Looking for local instance on localhost:11434',
        null,
      ),
      OllamaStatus.running => (
        Icons.check_circle,
        Colors.green,
        'Ollama is running',
        'Local models available on localhost:11434',
        null,
      ),
      OllamaStatus.notRunning => (
        Icons.warning_amber,
        Colors.orange,
        'Ollama not detected',
        'Install Ollama to run AI models locally — free, private, no API key needed',
        'Install Ollama',
      ),
      OllamaStatus.error => (
        Icons.error_outline,
        Colors.red,
        'Connection error',
        'Could not connect to Ollama. Make sure it\'s running.',
        'Retry',
      ),
      OllamaStatus.unknown => (
        Icons.help_outline,
        Colors.grey,
        'Checking...',
        '',
        null,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
          if (action != null)
            FilledButton(
              onPressed: status == OllamaStatus.notRunning
                  ? () => launchUrl(Uri.parse('https://ollama.com/download'))
                  : onRetry,
              child: Text(action),
            ),
        ],
      ),
    );
  }
}

// ─── Model tile ──

class _ModelTile extends StatelessWidget {
  final OllamaModel model;
  final bool isSelected;
  final VoidCallback onSelect;
  final VoidCallback onDelete;

  const _ModelTile({
    required this.model,
    required this.isSelected,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: isSelected ? cs.primaryContainer.withValues(alpha: 0.3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: isSelected
            ? BorderSide(color: cs.primary.withValues(alpha: 0.5))
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.displayName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                        color: cs.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        if (model.sizeLabel.isNotEmpty)
                          Text(
                            model.sizeLabel,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (model.family != null) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            model.family!,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (model.parameterSize != null) ...[
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            model.parameterSize!,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: cs.error.withValues(alpha: 0.7),
                ),
                onPressed: onDelete,
                tooltip: 'Delete model',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Custom pull field ──

class _CustomPullField extends StatefulWidget {
  final void Function(String name) onPull;
  final Rx<bool> isPulling;

  const _CustomPullField({required this.onPull, required this.isPulling});

  @override
  State<_CustomPullField> createState() => _CustomPullFieldState();
}

class _CustomPullFieldState extends State<_CustomPullField> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            decoration: InputDecoration(
              isDense: true,
              hintText: NeomageTranslationConstants.customModelHint.tr,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(width: 8),
        Obx(
          () => FilledButton(
            onPressed: widget.isPulling.value || _ctrl.text.trim().isEmpty
                ? null
                : () => widget.onPull(_ctrl.text.trim()),
            child: Text(NeomageTranslationConstants.pull.tr),
          ),
        ),
      ],
    );
  }
}
