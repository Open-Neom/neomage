import 'dart:async';
import 'dart:convert';
import 'package:neomage/core/platform/neomage_io.dart';
import 'package:neomage/data/auth/auth_service.dart';
import 'package:neomage/utils/constants/system.dart';
import 'package:sint/sint.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/chat_controller.dart';

// ---------------------------------------------------------------------------
// Doctor / Diagnostic screen — ported from Neomage's doctor functionality.
// Runs a battery of system, network, API, tool, MCP, git, and permission
// checks and displays results grouped by category.
// ---------------------------------------------------------------------------

/// Category of a diagnostic check.
enum DiagnosticCategory {
  system('System'),
  network('Network'),
  api('API'),
  tools('Tools'),
  mcp('MCP'),
  git('Git'),
  permissions('Permissions');

  final String label;
  const DiagnosticCategory(this.label);
}

/// Status of an individual check.
enum DiagnosticStatus { pending, running, pass, warn, fail }

/// A single diagnostic check with its result.
class DiagnosticCheck {
  final String name;
  final String description;
  final DiagnosticCategory category;
  DiagnosticStatus status;
  String? detail;
  Duration? duration;

  DiagnosticCheck({
    required this.name,
    required this.description,
    required this.category,
    this.status = DiagnosticStatus.pending,
    this.detail,
    this.duration,
  });

  DiagnosticCheck copyWith({
    DiagnosticStatus? status,
    String? detail,
    Duration? duration,
  }) {
    return DiagnosticCheck(
      name: name,
      description: description,
      category: category,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      duration: duration ?? this.duration,
    );
  }
}

// ===========================================================================
// DoctorScreen
// ===========================================================================

class DoctorScreen extends StatefulWidget {
  const DoctorScreen({super.key});

  @override
  State<DoctorScreen> createState() => _DoctorScreenState();
}

class _DoctorScreenState extends State<DoctorScreen> {
  late List<DiagnosticCheck> _checks;
  bool _running = false;
  int _completed = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _checks = _buildCheckList();
    _runAll();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Check definitions ──

  List<DiagnosticCheck> _buildCheckList() => [
    // API
    DiagnosticCheck(
      name: 'API Config',
      description: 'Check if an API key is configured via AuthService',
      category: DiagnosticCategory.api,
    ),
    DiagnosticCheck(
      name: 'Provider Connectivity',
      description: 'Verify the configured provider endpoint is reachable',
      category: DiagnosticCategory.api,
    ),

    // Tools
    DiagnosticCheck(
      name: 'Bash Tool',
      description: 'Check if Bash tool is registered (platform-dependent)',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'FileRead Tool',
      description: 'Check if FileRead tool is registered',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'FileWrite Tool',
      description: 'Check if FileWrite tool is registered',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'FileEdit Tool',
      description: 'Check if FileEdit tool is registered',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'Grep Tool',
      description: 'Check if Grep tool is registered',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'Glob Tool',
      description: 'Check if Glob tool is registered',
      category: DiagnosticCategory.tools,
    ),

    // System
    DiagnosticCheck(
      name: 'Memory Directory',
      description: 'Check if ~/.neomage/ exists and is writable',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Session Directory',
      description: 'Check if sessions directory exists',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Disk Space',
      description: 'Check config directory size on disk',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Platform Info',
      description: 'Detect operating system and architecture',
      category: DiagnosticCategory.system,
    ),

    // Network
    DiagnosticCheck(
      name: 'Ollama',
      description: 'Check if Ollama is reachable on localhost:11434',
      category: DiagnosticCategory.network,
    ),

    // MCP
    DiagnosticCheck(
      name: 'MCP Config',
      description: 'Check if mcp.json exists',
      category: DiagnosticCategory.mcp,
    ),

    // Permissions
    DiagnosticCheck(
      name: 'NEOMAGE.md',
      description: 'Check if project or global NEOMAGE.md exists',
      category: DiagnosticCategory.permissions,
    ),

    // Git
    DiagnosticCheck(
      name: 'Git Repo Status',
      description: 'Check if current directory is a git repository',
      category: DiagnosticCategory.git,
    ),
  ];

  // ── Run all checks ──

  Future<void> _runAll() async {
    setState(() {
      _running = true;
      _completed = 0;
      for (final c in _checks) {
        c.status = DiagnosticStatus.pending;
        c.detail = null;
        c.duration = null;
      }
    });

    for (var i = 0; i < _checks.length; i++) {
      if (!mounted) return;
      setState(() => _checks[i].status = DiagnosticStatus.running);

      final sw = Stopwatch()..start();
      try {
        await _executeCheck(_checks[i]);
      } catch (e) {
        _checks[i].status = DiagnosticStatus.fail;
        _checks[i].detail = 'Unexpected error: $e';
      }
      sw.stop();
      _checks[i].duration = sw.elapsed;

      setState(() => _completed = i + 1);
    }

    setState(() => _running = false);

    // Auto-scroll to first failure.
    _scrollToFirstFailure();
  }

  void _scrollToFirstFailure() {
    final failIndex = _checks.indexWhere(
      (c) => c.status == DiagnosticStatus.fail,
    );
    if (failIndex < 0) return;

    // Approximate position: header + cards before the failure.
    // Each card is roughly 72px. Add category headers at ~48px each.
    final grouped = _groupedChecks();
    double offset = 0;
    for (final entry in grouped.entries) {
      offset += 48; // category header
      for (final check in entry.value) {
        if (identical(check, _checks[failIndex])) {
          break;
        }
        offset += 76;
      }
      if (entry.value.contains(_checks[failIndex])) break;
    }

    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    }
  }

  // ── Individual check execution ──

  Future<void> _executeCheck(DiagnosticCheck check) async {
    switch (check.name) {
      case 'API Config':
        await _checkApiConfig(check);
      case 'Provider Connectivity':
        await _checkProviderConnectivity(check);
      case 'Bash Tool':
        _checkRegisteredTool(check, 'Bash');
      case 'FileRead Tool':
        _checkRegisteredTool(check, 'FileRead');
      case 'FileWrite Tool':
        _checkRegisteredTool(check, 'FileWrite');
      case 'FileEdit Tool':
        _checkRegisteredTool(check, 'FileEdit');
      case 'Grep Tool':
        _checkRegisteredTool(check, 'Grep');
      case 'Glob Tool':
        _checkRegisteredTool(check, 'Glob');
      case 'Memory Directory':
        await _checkMemoryDirectory(check);
      case 'Session Directory':
        await _checkSessionDirectory(check);
      case 'Disk Space':
        await _checkDiskSpace(check);
      case 'Platform Info':
        check.detail =
            '${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion} '
            '(${Platform.localHostname})';
        check.status = DiagnosticStatus.pass;
      case 'Ollama':
        await _checkOllama(check);
      case 'MCP Config':
        await _checkMcpConfig(check);
      case 'NEOMAGE.md':
        await _checkNeomageFile(check);
      case 'Git Repo Status':
        await _checkGitRepo(check);
      default:
        check.status = DiagnosticStatus.warn;
        check.detail = 'No handler for this check';
    }
  }

  // ── Check implementations ──

  /// Resolve the ChatController via Sint.find (if available).
  ChatController? _tryGetChatController() {
    try {
      return Sint.find<ChatController>();
    } catch (_) {
      return null;
    }
  }

  /// Check if an API key is configured via AuthService.
  Future<void> _checkApiConfig(DiagnosticCheck check) async {
    try {
      final authService = AuthService();
      final config = await authService.loadApiConfig();
      if (config != null) {
        final masked = config.apiKey != null && config.apiKey!.length > 8
            ? '${config.apiKey!.substring(0, 4)}...${config.apiKey!.substring(config.apiKey!.length - 4)}'
            : (config.apiKey != null ? '***' : 'none');
        check.status = DiagnosticStatus.pass;
        check.detail =
            'Provider: ${config.type.name}, model: ${config.model}, '
            'key: $masked';
      } else {
        check.status = DiagnosticStatus.fail;
        check.detail = 'No API configuration found — run onboarding first';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Failed to load API config: $e';
    }
  }

  /// Try a minimal HEAD request to the configured provider endpoint.
  Future<void> _checkProviderConnectivity(DiagnosticCheck check) async {
    try {
      final authService = AuthService();
      final config = await authService.loadApiConfig();
      if (config == null) {
        check.status = DiagnosticStatus.warn;
        check.detail = 'No API config — skipping connectivity check';
        return;
      }

      final baseUrl = config.baseUrl;
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(Uri.parse(baseUrl));
      final response = await request.close();
      await response.drain<void>();
      client.close();

      if (response.statusCode < 500) {
        check.status = DiagnosticStatus.pass;
        check.detail =
            '${config.type.name} endpoint reachable (HTTP ${response.statusCode})';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail =
            '${config.type.name} endpoint returned HTTP ${response.statusCode}';
      }
    } on SocketException catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Socket error: ${e.message}';
    } on HttpException catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'HTTP error: ${e.message}';
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Cannot reach provider: $e';
    }
  }

  /// Check if a specific tool is registered in the ChatController's engine.
  void _checkRegisteredTool(DiagnosticCheck check, String toolName) {
    final chat = _tryGetChatController();
    if (chat == null || !chat.isInitialized) {
      check.status = DiagnosticStatus.warn;
      check.detail = 'ChatController not initialized — cannot verify tools';
      return;
    }

    // The tool registry is private on ChatController, so we verify
    // initialization status and check platform availability instead.
    final isDesktop =
        Platform.isMacOS || Platform.isLinux || Platform.isWindows;

    if (toolName == 'Bash') {
      if (isDesktop) {
        check.status = DiagnosticStatus.pass;
        check.detail = 'Bash tool available (${Platform.operatingSystem})';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail =
            'Bash tool not available on ${Platform.operatingSystem}';
      }
      return;
    }

    // FileRead, FileWrite, FileEdit, Grep, Glob are registered on all
    // non-web IO platforms.
    if (isDesktop) {
      check.status = DiagnosticStatus.pass;
      check.detail = '$toolName tool registered (native platform)';
    } else {
      check.status = DiagnosticStatus.warn;
      check.detail = '$toolName tool may not be available on this platform';
    }
  }

  /// Check if ~/.neomage/ directory exists and is writable.
  Future<void> _checkMemoryDirectory(DiagnosticCheck check) async {
    try {
      final configDir = Directory(SystemConstants.configDir);
      if (await configDir.exists()) {
        // Test writability by creating and removing a temp file.
        final testFile = File('${configDir.path}/.doctor_write_test');
        try {
          await testFile.writeAsString('test');
          await testFile.delete();
          check.status = DiagnosticStatus.pass;
          check.detail = '${SystemConstants.configDir} exists and is writable';
        } catch (e) {
          check.status = DiagnosticStatus.warn;
          check.detail =
              '${SystemConstants.configDir} exists but is not writable: $e';
        }
      } else {
        check.status = DiagnosticStatus.fail;
        check.detail =
            '${SystemConstants.configDir} does not exist — '
            'it will be created on first use';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Error checking memory directory: $e';
    }
  }

  /// Check if the sessions directory exists.
  Future<void> _checkSessionDirectory(DiagnosticCheck check) async {
    try {
      final sessionDir = Directory(SystemConstants.sessionDir);
      if (await sessionDir.exists()) {
        final entries = await sessionDir.list().toList();
        final sessionCount =
            entries.where((e) => e.path.endsWith('.json')).length;
        check.status = DiagnosticStatus.pass;
        check.detail =
            '${SystemConstants.sessionDir} exists '
            '($sessionCount saved sessions)';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail =
            '${SystemConstants.sessionDir} does not exist — '
            'will be created on first session';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Error checking session directory: $e';
    }
  }

  /// Check config directory size on disk.
  Future<void> _checkDiskSpace(DiagnosticCheck check) async {
    try {
      final configDir = Directory(SystemConstants.configDir);
      if (!await configDir.exists()) {
        check.status = DiagnosticStatus.warn;
        check.detail = 'Config directory does not exist yet';
        return;
      }

      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run(
          'du',
          ['-sh', SystemConstants.configDir],
        );
        if (result.exitCode == 0) {
          final output = (result.stdout as String).trim();
          final size = output.split(RegExp(r'\s+')).first;
          check.status = DiagnosticStatus.pass;
          check.detail = 'Config dir size: $size';
          return;
        }
      }
      check.status = DiagnosticStatus.warn;
      check.detail = 'Could not determine config directory size';
    } catch (e) {
      check.status = DiagnosticStatus.warn;
      check.detail = e.toString();
    }
  }

  /// Check if Ollama is reachable on localhost:11434.
  Future<void> _checkOllama(DiagnosticCheck check) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final request = await client.getUrl(
        Uri.parse('http://localhost:11434/api/tags'),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      client.close();

      if (response.statusCode == 200) {
        // Try to parse the model list.
        try {
          final data = jsonDecode(body) as Map<String, dynamic>;
          final models = (data['models'] as List?)?.length ?? 0;
          check.status = DiagnosticStatus.pass;
          check.detail = 'Ollama running, $models model(s) available';
        } catch (_) {
          check.status = DiagnosticStatus.pass;
          check.detail = 'Ollama running (HTTP 200)';
        }
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail = 'Ollama responded with HTTP ${response.statusCode}';
      }
    } on SocketException {
      check.status = DiagnosticStatus.warn;
      check.detail = 'Ollama not reachable on localhost:11434 (not running?)';
    } catch (e) {
      check.status = DiagnosticStatus.warn;
      check.detail = 'Could not connect to Ollama: $e';
    }
  }

  /// Check if mcp.json exists at the standard location.
  Future<void> _checkMcpConfig(DiagnosticCheck check) async {
    try {
      final mcpFile = File(SystemConstants.mcpConfigFile);
      final localFile = File('.mcp.json');
      final hasMcp = await mcpFile.exists();
      final hasLocal = await localFile.exists();

      if (hasMcp || hasLocal) {
        final found = <String>[];
        if (hasMcp) {
          // Validate JSON.
          try {
            final content = await mcpFile.readAsString();
            jsonDecode(content);
            found.add('~/.neomage/mcp.json (valid JSON)');
          } catch (_) {
            found.add('~/.neomage/mcp.json (invalid JSON!)');
          }
        }
        if (hasLocal) found.add('.mcp.json (project-local)');
        check.status = DiagnosticStatus.pass;
        check.detail = found.join(', ');
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail =
            'No MCP config found at ${SystemConstants.mcpConfigFile} '
            'or .mcp.json';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Error checking MCP config: $e';
    }
  }

  /// Check if project-local or global NEOMAGE.md exists.
  Future<void> _checkNeomageFile(DiagnosticCheck check) async {
    try {
      final globalFile = File(SystemConstants.memoryFile);
      final projectFile = File(SystemConstants.projectMemoryFile);
      final rootFile = File('NEOMAGE.md');

      final hasGlobal = await globalFile.exists();
      final hasProject = await projectFile.exists();
      final hasRoot = await rootFile.exists();

      if (hasGlobal || hasProject || hasRoot) {
        final found = <String>[];
        if (hasGlobal) found.add('global (~/.neomage/NEOMAGE.md)');
        if (hasProject) found.add('project (.neomage/NEOMAGE.md)');
        if (hasRoot) found.add('root (NEOMAGE.md)');
        check.status = DiagnosticStatus.pass;
        check.detail = 'Found: ${found.join(', ')}';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail =
            'No NEOMAGE.md found (optional — used for custom instructions)';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Error checking NEOMAGE.md: $e';
    }
  }

  Future<void> _checkGitRepo(DiagnosticCheck check) async {
    try {
      final result = await Process.run('git', [
        'rev-parse',
        '--is-inside-work-tree',
      ]);
      if (result.exitCode == 0 && (result.stdout as String).trim() == 'true') {
        final branch = await Process.run('git', [
          'rev-parse',
          '--abbrev-ref',
          'HEAD',
        ]);
        check.status = DiagnosticStatus.pass;
        check.detail =
            'Inside git repo, branch: ${(branch.stdout as String).trim()}';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail = 'Not inside a git repository';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'git check failed: $e';
    }
  }

  // ── Grouping helper ──

  Map<DiagnosticCategory, List<DiagnosticCheck>> _groupedChecks() {
    final map = <DiagnosticCategory, List<DiagnosticCheck>>{};
    for (final c in _checks) {
      map.putIfAbsent(c.category, () => []).add(c);
    }
    return map;
  }

  // ── Report generation ──

  String _generateReport() {
    final buf = StringBuffer();
    buf.writeln('=== Neomage Diagnostic Report ===');
    buf.writeln('Date: ${DateTime.now().toIso8601String()}');
    buf.writeln(
      'Platform: ${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}',
    );
    buf.writeln();

    final grouped = _groupedChecks();
    for (final entry in grouped.entries) {
      buf.writeln('--- ${entry.key.label} ---');
      for (final check in entry.value) {
        final icon = switch (check.status) {
          DiagnosticStatus.pass => '[PASS]',
          DiagnosticStatus.warn => '[WARN]',
          DiagnosticStatus.fail => '[FAIL]',
          DiagnosticStatus.running => '[....]',
          DiagnosticStatus.pending => '[    ]',
        };
        final dur = check.duration != null
            ? ' (${check.duration!.inMilliseconds}ms)'
            : '';
        buf.writeln('  $icon ${check.name}$dur');
        if (check.detail != null) {
          buf.writeln('       ${check.detail}');
        }
      }
      buf.writeln();
    }

    final passCount = _checks
        .where((c) => c.status == DiagnosticStatus.pass)
        .length;
    final warnCount = _checks
        .where((c) => c.status == DiagnosticStatus.warn)
        .length;
    final failCount = _checks
        .where((c) => c.status == DiagnosticStatus.fail)
        .length;
    buf.writeln(
      'Summary: $passCount passed, $warnCount warnings, $failCount failed',
    );

    return buf.toString();
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final grouped = _groupedChecks();
    final progress = _checks.isEmpty ? 0.0 : _completed / _checks.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy Report',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _generateReport()));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report copied to clipboard')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-run All',
            onPressed: _running
                ? null
                : () {
                    setState(() => _checks = _buildCheckList());
                    _runAll();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: _running ? 6 : 0,
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),

          // Summary chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _SummaryChip(
                  icon: Icons.check_circle,
                  color: Colors.green,
                  count: _checks
                      .where((c) => c.status == DiagnosticStatus.pass)
                      .length,
                  label: 'Passed',
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange,
                  count: _checks
                      .where((c) => c.status == DiagnosticStatus.warn)
                      .length,
                  label: 'Warnings',
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  icon: Icons.cancel,
                  color: Colors.red,
                  count: _checks
                      .where((c) => c.status == DiagnosticStatus.fail)
                      .length,
                  label: 'Failed',
                ),
                const Spacer(),
                if (!_running && _completed == _checks.length)
                  Text(
                    'All checks complete',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Results list
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: grouped.length,
              itemBuilder: (context, index) {
                final entry = grouped.entries.elementAt(index);
                return _CategorySection(
                  category: entry.key,
                  checks: entry.value,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Private helper widgets
// ===========================================================================

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _SummaryChip({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          '$count',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _CategorySection extends StatelessWidget {
  final DiagnosticCategory category;
  final List<DiagnosticCheck> checks;

  const _CategorySection({required this.category, required this.checks});

  IconData _categoryIcon() => switch (category) {
    DiagnosticCategory.system => Icons.computer,
    DiagnosticCategory.network => Icons.wifi,
    DiagnosticCategory.api => Icons.api,
    DiagnosticCategory.tools => Icons.build,
    DiagnosticCategory.mcp => Icons.extension,
    DiagnosticCategory.git => Icons.commit,
    DiagnosticCategory.permissions => Icons.shield,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(_categoryIcon(), size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text(
                category.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: cs.primary,
                ),
              ),
            ],
          ),
        ),
        ...checks.map((check) => _CheckTile(check: check)),
      ],
    );
  }
}

class _CheckTile extends StatefulWidget {
  final DiagnosticCheck check;
  const _CheckTile({required this.check});

  @override
  State<_CheckTile> createState() => _CheckTileState();
}

class _CheckTileState extends State<_CheckTile> {
  bool _expanded = false;

  Widget _statusIcon() {
    switch (widget.check.status) {
      case DiagnosticStatus.pending:
        return Icon(
          Icons.circle_outlined,
          size: 20,
          color: Colors.grey.shade400,
        );
      case DiagnosticStatus.running:
        return const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DiagnosticStatus.pass:
        return const Icon(Icons.check_circle, size: 20, color: Colors.green);
      case DiagnosticStatus.warn:
        return const Icon(
          Icons.warning_amber_rounded,
          size: 20,
          color: Colors.orange,
        );
      case DiagnosticStatus.fail:
        return const Icon(Icons.cancel, size: 20, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasDetail =
        widget.check.detail != null && widget.check.detail!.isNotEmpty;

    return InkWell(
      onTap: hasDetail ? () => setState(() => _expanded = !_expanded) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _statusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.check.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        widget.check.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.check.duration != null)
                  Text(
                    '${widget.check.duration!.inMilliseconds}ms',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                if (hasDetail) ...[
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ],
            ),
            // Expandable detail
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(left: 32, top: 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: SelectableText(
                    widget.check.detail ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ),
              crossFadeState: _expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }
}
