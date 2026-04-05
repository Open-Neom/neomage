// ChooseYourAgentPage — hardware-aware local AI model recommender.
// Detects system specs automatically, recommends the best local model,
// shows KPIs, and provides step-by-step installation commands.

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ═══════════════════════════════════════════
// Data Models
// ═══════════════════════════════════════════

enum HwPlatform { mac, pc }
enum MacGen { m1, m2, m3, m4 }
enum MacTier { base, pro, max }
enum UseCase { dev, lawyer, accountant, sales, marketing }
enum ContextSize { short, medium, long }

class _HwCapability {
  final String level; // ultra, high, medium-high, low-medium, low
  final double speedFactor;
  const _HwCapability(this.level, this.speedFactor);
}

class _ModelRec {
  final String name;
  final String size;
  final String params;
  final String desc;
  final String toolReliability;
  final bool isGemma;
  final String nextModel;

  const _ModelRec({
    required this.name,
    this.size = '',
    this.params = '',
    this.desc = '',
    this.toolReliability = 'Medium',
    this.isGemma = false,
    this.nextModel = '',
  });
}

class _KPIs {
  final String speed;
  final String ttft;
  final String pracContext;
  const _KPIs({required this.speed, required this.ttft, required this.pracContext});
}

// ═══════════════════════════════════════════
// Hardware Detection
// ═══════════════════════════════════════════

class _SystemSpecs {
  final int ramGB;
  final String chipName;
  final MacGen? macGen;
  final MacTier? macTier;
  final bool isMac;

  const _SystemSpecs({
    required this.ramGB,
    required this.chipName,
    this.macGen,
    this.macTier,
    required this.isMac,
  });

  static Future<_SystemSpecs> detect() async {
    if (kIsWeb) {
      return const _SystemSpecs(ramGB: 16, chipName: 'Unknown (Web)', isMac: false);
    }

    int ramGB = 16;
    String chipName = 'Unknown';
    MacGen? macGen;
    MacTier? macTier;
    bool isMac = Platform.isMacOS;

    try {
      if (Platform.isMacOS) {
        final memResult = await Process.run('sysctl', ['-n', 'hw.memsize']);
        if (memResult.exitCode == 0) {
          final bytes = int.tryParse(memResult.stdout.toString().trim()) ?? 0;
          ramGB = (bytes / (1024 * 1024 * 1024)).round();
        }

        final cpuResult = await Process.run('sysctl', ['-n', 'machdep.cpu.brand_string']);
        if (cpuResult.exitCode == 0) {
          chipName = cpuResult.stdout.toString().trim();

          final lower = chipName.toLowerCase();
          if (lower.contains('m4')) macGen = MacGen.m4;
          else if (lower.contains('m3')) macGen = MacGen.m3;
          else if (lower.contains('m2')) macGen = MacGen.m2;
          else if (lower.contains('m1')) macGen = MacGen.m1;

          if (lower.contains('ultra') || lower.contains('max')) macTier = MacTier.max;
          else if (lower.contains('pro')) macTier = MacTier.pro;
          else macTier = MacTier.base;
        }
      } else if (Platform.isLinux || Platform.isWindows) {
        isMac = false;
        if (Platform.isLinux) {
          final memResult = await Process.run('grep', ['MemTotal', '/proc/meminfo']);
          if (memResult.exitCode == 0) {
            final match = RegExp(r'(\d+)').firstMatch(memResult.stdout.toString());
            if (match != null) {
              ramGB = (int.parse(match.group(1)!) / (1024 * 1024)).round();
            }
          }
        }
      }
    } catch (_) {}

    return _SystemSpecs(
      ramGB: ramGB,
      chipName: chipName,
      macGen: macGen,
      macTier: macTier,
      isMac: isMac,
    );
  }
}

// ═══════════════════════════════════════════
// Recommendation Engine
// ═══════════════════════════════════════════

_HwCapability _getCapability(_SystemSpecs specs, {bool hasGpu = false, int vramGB = 0}) {
  if (specs.isMac) {
    final gen = specs.macGen;
    final isNew = gen == MacGen.m3 || gen == MacGen.m4;
    if (specs.ramGB >= 32) return _HwCapability('ultra', isNew ? 1.4 : 1.1);
    if (specs.ramGB >= 24) return _HwCapability('high', isNew ? 1.3 : 1.0);
    if (specs.ramGB >= 16) return _HwCapability('medium-high', 1.0);
    return const _HwCapability('low', 0.7);
  } else {
    if (hasGpu) {
      if (vramGB >= 16 && specs.ramGB >= 32) return const _HwCapability('ultra', 1.5);
      if (vramGB >= 8 && specs.ramGB >= 16) return const _HwCapability('high', 1.2);
      if (vramGB >= 6) return const _HwCapability('medium-high', 0.9);
      return const _HwCapability('low', 0.5);
    }
    if (specs.ramGB >= 16) return const _HwCapability('low-medium', 0.4);
    return const _HwCapability('low', 0.2);
  }
}

_ModelRec _recommend(_HwCapability hw, UseCase useCase, ContextSize ctx, bool needsTools) {
  final cap = hw.level;

  if (useCase == UseCase.dev) {
    if (cap == 'ultra') {
      return const _ModelRec(name: 'deepseek-coder-v2', size: '~16 GB', params: '16B',
        desc: 'Top hardware. MoE architecture for massive projects.',
        toolReliability: 'Very High', nextModel: 'Llama 3 70B');
    } else if (cap == 'high' || cap == 'medium-high') {
      return const _ModelRec(name: 'qwen2.5-coder:7b', size: '~4.7 GB', params: '7B',
        desc: 'The local coding king. Excellent for JSON and APIs.',
        toolReliability: 'High', nextModel: 'DeepSeek Coder V2');
    }
    return const _ModelRec(name: 'qwen2.5-coder:1.5b', size: '~1 GB', params: '1.5B',
      desc: 'Micro-model for autocomplete without choking RAM.',
      toolReliability: 'Medium', nextModel: 'Qwen 2.5 Coder 7B');
  }

  if (useCase == UseCase.marketing) {
    if (needsTools || ctx == ContextSize.long) {
      if (cap == 'ultra' || cap == 'high' || cap == 'medium-high') {
        return const _ModelRec(name: 'llama3.1:8b', size: '~4.7 GB', params: '8B',
          desc: 'Stable JSON/long context for structured marketing outputs.',
          toolReliability: 'High', nextModel: 'Llama 3.1 70B');
      }
      return const _ModelRec(name: 'llama3.2', size: '~2.0 GB', params: '3B',
        desc: 'Fast and follows structured formats efficiently.',
        toolReliability: 'Medium-High', nextModel: 'Llama 3.1 8B');
    }
    if (cap == 'ultra' || cap == 'high' || cap == 'medium-high') {
      return const _ModelRec(name: 'gemma2:9b', size: '~5.5 GB', params: '9B',
        desc: 'Incredible prose for copy — ideal when you don\'t need strict JSON.',
        isGemma: true, toolReliability: 'Low-Medium', nextModel: 'Command R');
    }
    return const _ModelRec(name: 'qwen2.5:3b', size: '~1.9 GB', params: '3B',
      desc: 'Creative and balanced for limited hardware.',
      toolReliability: 'Medium', nextModel: 'Gemma 2 9B');
  }

  // General (lawyer, accountant, sales)
  if (cap == 'ultra' || cap == 'high') {
    if (useCase == UseCase.sales) {
      return const _ModelRec(name: 'llama3.1:8b', size: '~4.7 GB', params: '8B',
        desc: 'Fast and effective for support bots.',
        toolReliability: 'High', nextModel: 'Llama 3.1 70B');
    }
    return const _ModelRec(name: 'qwen2.5:14b', size: '~9 GB', params: '14B',
      desc: 'Massive context and impeccable instruction following.',
      toolReliability: 'Very High', nextModel: 'Qwen 2.5 32B');
  }
  if (cap == 'medium-high') {
    return const _ModelRec(name: 'llama3.1:8b', size: '~4.7 GB', params: '8B',
      desc: 'The gold standard for reasoning and APIs on consumer hardware.',
      toolReliability: 'High', nextModel: 'Qwen 2.5 14B');
  }
  if (needsTools) {
    return const _ModelRec(name: 'llama3.2', size: '~2.0 GB', params: '3B',
      desc: 'Best effort at structured APIs despite limited hardware.',
      toolReliability: 'Medium-High', nextModel: 'Llama 3.1 8B');
  }
  return const _ModelRec(name: 'phi3.5', size: '~2.3 GB', params: '3.8B',
    desc: 'Strong short-text reasoning for basic machines.',
    toolReliability: 'Medium', nextModel: 'Llama 3.1 8B');
}

_KPIs _calculateKPIs(String params, _HwCapability hw, ContextSize ctx, {bool isGemma = false}) {
  final p = double.tryParse(params.replaceAll('B', '')) ?? 3;
  int baseSpeed;
  if (p <= 2) baseSpeed = 45;
  else if (p <= 4) baseSpeed = 35;
  else if (p <= 9) baseSpeed = 22;
  else baseSpeed = 12;

  var speed = (baseSpeed * hw.speedFactor).round();
  if (ctx == ContextSize.long) speed = (speed * 0.7).round();
  speed = max(1, speed);

  String ttft = '< 0.5s';
  if (p > 9 || ctx == ContextSize.long) ttft = '~1.5s - 3s';
  if (hw.level.contains('low')) ttft = '> 4s';

  String pracCtx = '32k Tokens';
  if (isGemma) pracCtx = '8k Tokens (Limit)';
  if (hw.level.contains('low') || hw.level == 'medium-high') {
    if (!isGemma) pracCtx = '16k Tokens (RAM)';
  }

  return _KPIs(speed: '$speed tok/s', ttft: ttft, pracContext: pracCtx);
}

// ═══════════════════════════════════════════
// Widget
// ═══════════════════════════════════════════

class ChooseAgentPage extends StatefulWidget {
  /// If true, shows a "Continue" button at the bottom (onboarding flow).
  final bool isOnboarding;
  final VoidCallback? onContinue;

  const ChooseAgentPage({super.key, this.isOnboarding = false, this.onContinue});

  @override
  State<ChooseAgentPage> createState() => _ChooseAgentPageState();
}

class _ChooseAgentPageState extends State<ChooseAgentPage> {
  _SystemSpecs? _specs;
  UseCase _useCase = UseCase.dev;
  ContextSize _contextSize = ContextSize.medium;
  bool _needsTools = false;
  bool _loading = true;

  // PC-specific overrides
  bool _hasGpu = false;
  int _vramGB = 8;
  int _ramOverride = 0;

  @override
  void initState() {
    super.initState();
    _detectHardware();
  }

  Future<void> _detectHardware() async {
    final specs = await _SystemSpecs.detect();
    if (mounted) setState(() { _specs = specs; _loading = false; });
  }

  int get _effectiveRam => _ramOverride > 0 ? _ramOverride : (_specs?.ramGB ?? 16);

  _HwCapability get _capability {
    final specs = _specs ?? const _SystemSpecs(ramGB: 16, chipName: 'Unknown', isMac: true);
    final overridden = _SystemSpecs(
      ramGB: _effectiveRam, chipName: specs.chipName,
      macGen: specs.macGen, macTier: specs.macTier, isMac: specs.isMac,
    );
    return _getCapability(overridden, hasGpu: _hasGpu, vramGB: _vramGB);
  }

  _ModelRec get _rec => _recommend(_capability, _useCase, _contextSize, _needsTools);
  _KPIs get _kpis => _calculateKPIs(_rec.params, _capability, _contextSize, isGemma: _rec.isGemma);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF58A6FF) : const Color(0xFF0366D6);
    final bg = isDark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final border = isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final textMain = isDark ? const Color(0xFFC9D1D9) : const Color(0xFF1F2328);
    final textMuted = isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final success = const Color(0xFF2EA043);

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: accent)),
      );
    }

    final rec = _rec;
    final kpis = _kpis;
    final isMac = _specs?.isMac ?? true;

    return Scaffold(
      backgroundColor: bg,
      appBar: widget.isOnboarding ? null : AppBar(
        title: const Text('Choose Your Agent'),
        backgroundColor: bg,
        foregroundColor: textMain,
        elevation: 0,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Title
              Text('Choose Your Local Agent',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textMain),
                textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text('Hardware analysis and deployment guide for local AI.',
                style: TextStyle(fontSize: 14, color: textMuted), textAlign: TextAlign.center),
              const SizedBox(height: 24),

              // Detected hardware banner
              if (_specs != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: accent.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.memory, size: 20, color: accent),
                      const SizedBox(width: 10),
                      Expanded(child: Text(
                        '${_specs!.chipName}  •  ${_specs!.ramGB} GB RAM',
                        style: TextStyle(color: accent, fontWeight: FontWeight.w600, fontSize: 13),
                      )),
                      Text('Auto-detected', style: TextStyle(color: textMuted, fontSize: 11)),
                    ],
                  ),
                ),

              // Two-column layout on wide screens
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 700;
                final controls = _buildControls(cardBg, border, textMain, textMuted, accent, isMac);
                final results = _buildResults(rec, kpis, cardBg, border, textMain, textMuted, accent, success, isMac);

                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 340, child: controls),
                      const SizedBox(width: 20),
                      Expanded(child: results),
                    ],
                  );
                }
                return Column(children: [controls, const SizedBox(height: 20), results]);
              }),

              // Continue button for onboarding
              if (widget.isOnboarding) ...[
                const SizedBox(height: 24),
                Center(
                  child: SizedBox(
                    width: 280,
                    height: 48,
                    child: FilledButton.icon(
                      onPressed: widget.onContinue,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Continue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Controls Panel ──

  Widget _buildControls(Color cardBg, Color border, Color textMain, Color textMuted, Color accent, bool isMac) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionLabel('Use Case', accent),
          const SizedBox(height: 8),
          _dropdown<UseCase>(
            value: _useCase,
            items: const {
              UseCase.dev: 'Software Development',
              UseCase.lawyer: 'Legal / Documents',
              UseCase.accountant: 'Finance / Data',
              UseCase.sales: 'Sales / Support Bots',
              UseCase.marketing: 'Marketing / Copywriting',
            },
            onChanged: (v) => setState(() => _useCase = v),
            textMain: textMain, border: border,
          ),
          const SizedBox(height: 16),

          _sectionLabel('Context Window', accent),
          const SizedBox(height: 8),
          _dropdown<ContextSize>(
            value: _contextSize,
            items: const {
              ContextSize.short: 'Short (< 4k) — chats, queries',
              ContextSize.medium: 'Medium (~8-16k) — 1 PDF or file',
              ContextSize.long: 'Long (32k+) — repos, contracts',
            },
            onChanged: (v) => setState(() => _contextSize = v),
            textMain: textMain, border: border,
          ),
          const SizedBox(height: 16),

          _sectionLabel('Tool Calling', accent),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: _needsTools,
            onChanged: (v) => setState(() => _needsTools = v),
            title: Text('Needs strict JSON output', style: TextStyle(color: textMain, fontSize: 13)),
            subtitle: Text('APIs, webhooks, structured data', style: TextStyle(color: textMuted, fontSize: 11)),
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: accent,
          ),

          if (!isMac) ...[
            const SizedBox(height: 16),
            _sectionLabel('GPU', accent),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              value: _hasGpu,
              onChanged: (v) => setState(() => _hasGpu = v),
              title: Text('Dedicated GPU (NVIDIA/AMD)', style: TextStyle(color: textMain, fontSize: 13)),
              contentPadding: EdgeInsets.zero, dense: true, activeColor: accent,
            ),
            if (_hasGpu) ...[
              const SizedBox(height: 8),
              _dropdown<int>(
                value: _vramGB,
                items: const {4: '4 GB VRAM', 6: '6 GB', 8: '8 GB', 12: '12 GB', 16: '16 GB', 24: '24 GB+'},
                onChanged: (v) => setState(() => _vramGB = v),
                textMain: textMain, border: border,
              ),
            ],
          ],

          const SizedBox(height: 16),
          _sectionLabel('RAM Override', accent),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _effectiveRam.toDouble(),
                  min: 8, max: 64, divisions: 28,
                  activeColor: accent,
                  onChanged: (v) => setState(() => _ramOverride = v.round()),
                ),
              ),
              SizedBox(
                width: 50,
                child: Text('${_effectiveRam} GB',
                  style: TextStyle(color: accent, fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Results Panel ──

  Widget _buildResults(_ModelRec rec, _KPIs kpis, Color cardBg, Color border,
      Color textMain, Color textMuted, Color accent, Color success, bool isMac) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('RECOMMENDED AGENT', style: TextStyle(color: textMuted, fontSize: 11, letterSpacing: 1)),
          const SizedBox(height: 4),
          Text(rec.name, style: TextStyle(color: accent, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          // Meta tags
          Wrap(spacing: 8, runSpacing: 8, children: [
            _metaTag('Disk: ${rec.size}', accent),
            _metaTag('${rec.params} Params', accent),
          ]),
          const SizedBox(height: 12),
          Text(rec.desc, style: TextStyle(color: textMain, fontSize: 14, height: 1.5)),
          const SizedBox(height: 16),

          // KPIs
          Row(children: [
            Expanded(child: _kpiBox('Inference Speed', kpis.speed, success, textMuted)),
            const SizedBox(width: 10),
            Expanded(child: _kpiBox('Tool Calling', rec.toolReliability,
              rec.toolReliability.contains('High') ? success : accent, textMuted)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _kpiBox('Context Limit', kpis.pracContext, const Color(0xFFD29922), textMuted)),
            const SizedBox(width: 10),
            Expanded(child: _kpiBox('Time to First Token', kpis.ttft, success, textMuted)),
          ]),
          const SizedBox(height: 16),

          // Speed demo — live typing simulation
          _SpeedDemo(
            key: ValueKey('${rec.name}_${kpis.speed}'),
            tokensPerSecond: int.tryParse(kpis.speed.replaceAll(RegExp(r'[^0-9]'), '')) ?? 20,
            accent: accent,
            textMain: textMain,
            textMuted: textMuted,
          ),
          const SizedBox(height: 20),

          // Install steps
          Text('QUICKSTART', style: TextStyle(color: accent, fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _step(1, 'Install Ollama',
            isMac ? 'brew install ollama' : 'curl -fsSL https://ollama.com/install.sh | sh',
            'Or download from ollama.com', accent, textMain, textMuted, success),
          _step(2, 'Download the model',
            'ollama pull ${rec.name}', 'Saves to Ollama cache.', accent, textMain, textMuted, success),
          _step(3, 'Run it',
            'ollama run ${rec.name}', 'Or connect via Neomage / OpenClaw.', accent, textMain, textMuted, success),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _sectionLabel(String text, Color accent) {
    return Text(text.toUpperCase(),
      style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1));
  }

  Widget _dropdown<T>({
    required T value, required Map<T, String> items,
    required ValueChanged<T> onChanged, required Color textMain, required Color border,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items.entries.map((e) =>
        DropdownMenuItem(value: e.key, child: Text(e.value, style: TextStyle(fontSize: 13, color: textMain)))).toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
      decoration: InputDecoration(
        isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: border)),
      ),
      dropdownColor: Theme.of(context).scaffoldBackgroundColor,
    );
  }

  Widget _metaTag(String text, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Text(text, style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  Widget _kpiBox(String label, String value, Color valueColor, Color labelColor) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF010409),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: TextStyle(color: labelColor, fontSize: 10, letterSpacing: 0.5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: valueColor, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _step(int n, String title, String cmd, String sub, Color accent, Color textMain, Color textMuted, Color success) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24, height: 24, margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
            child: Center(child: Text('$n', style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textMain, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: cmd));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Copied: $cmd'), duration: const Duration(seconds: 2)));
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF010409),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF30363D)),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: Text(cmd, style: TextStyle(fontFamily: 'monospace', color: success, fontSize: 13))),
                      Icon(Icons.copy, size: 14, color: textMuted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(sub, style: TextStyle(color: textMuted, fontSize: 11)),
            ],
          )),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════
// Speed Demo — live typing at estimated tok/s
// ═══════════════════════════════════════════

class _SpeedDemo extends StatefulWidget {
  final int tokensPerSecond;
  final Color accent;
  final Color textMain;
  final Color textMuted;

  const _SpeedDemo({
    super.key,
    required this.tokensPerSecond,
    required this.accent,
    required this.textMain,
    required this.textMuted,
  });

  @override
  State<_SpeedDemo> createState() => _SpeedDemoState();
}

class _SpeedDemoState extends State<_SpeedDemo> {
  static const _sampleText =
    'Here is a quick sorting algorithm in Dart:\n\n'
    'List<int> quickSort(List<int> list) {\n'
    '  if (list.length <= 1) return list;\n'
    '  final pivot = list[list.length ~/ 2];\n'
    '  final less = list.where((e) => e < pivot).toList();\n'
    '  final equal = list.where((e) => e == pivot).toList();\n'
    '  final greater = list.where((e) => e > pivot).toList();\n'
    '  return [...quickSort(less), ...equal, ...quickSort(greater)];\n'
    '}';

  // Average ~1.3 tokens per word, ~4 chars per token
  static const _charsPerToken = 4;

  int _visibleChars = 0;
  bool _running = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant _SpeedDemo old) {
    super.didUpdateWidget(old);
    if (old.tokensPerSecond != widget.tokensPerSecond) {
      _visibleChars = 0;
      _done = false;
      _start();
    }
  }

  Future<void> _start() async {
    if (_running) return;
    _running = true;
    _visibleChars = 0;
    _done = false;

    // chars per tick — emit ~_charsPerToken chars per token
    final charsPerSecond = widget.tokensPerSecond * _charsPerToken;
    // Tick every 50ms for smooth animation
    const tickMs = 50;
    final charsPerTick = max(1, (charsPerSecond * tickMs / 1000).round());

    while (_visibleChars < _sampleText.length && mounted) {
      await Future.delayed(const Duration(milliseconds: tickMs));
      if (!mounted) return;
      setState(() {
        _visibleChars = min(_visibleChars + charsPerTick, _sampleText.length);
        if (_visibleChars >= _sampleText.length) _done = true;
      });
    }
    _running = false;
  }

  void _replay() {
    _running = false;
    setState(() { _visibleChars = 0; _done = false; });
    _start();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _sampleText.substring(0, _visibleChars);
    final cursor = _done ? '' : '\u258C';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF010409),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF161B22),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(9), topRight: Radius.circular(9)),
            ),
            child: Row(
              children: [
                Icon(Icons.speed, size: 14, color: widget.accent),
                const SizedBox(width: 6),
                Text('SPEED PREVIEW', style: TextStyle(
                  color: widget.accent, fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 1)),
                const Spacer(),
                Text('${widget.tokensPerSecond} tok/s', style: TextStyle(
                  color: widget.textMuted, fontSize: 11, fontFamily: 'monospace')),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _replay,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.replay, size: 14, color: widget.textMuted),
                  ),
                ),
              ],
            ),
          ),
          // Typing area
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText.rich(
              TextSpan(children: [
                TextSpan(
                  text: visible,
                  style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12, height: 1.5,
                    color: const Color(0xFF7EE787),
                  ),
                ),
                TextSpan(
                  text: cursor,
                  style: TextStyle(
                    fontFamily: 'monospace', fontSize: 12,
                    color: widget.accent,
                  ),
                ),
              ]),
            ),
          ),
          // Progress bar
          if (!_done)
            LinearProgressIndicator(
              value: _sampleText.isEmpty ? 0 : _visibleChars / _sampleText.length,
              backgroundColor: Colors.transparent,
              color: widget.accent.withValues(alpha: 0.3),
              minHeight: 2,
            ),
        ],
      ),
    );
  }
}
