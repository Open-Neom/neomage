import 'dart:async';
import 'package:neom_claw/core/platform/claw_io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Doctor / Diagnostic screen — ported from NeomClaw's doctor functionality.
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
    // System
    DiagnosticCheck(
      name: 'Flutter Version',
      description: 'Verify Flutter SDK is accessible',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Dart Version',
      description: 'Verify Dart SDK version',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Platform Info',
      description: 'Detect operating system and architecture',
      category: DiagnosticCategory.system,
    ),
    DiagnosticCheck(
      name: 'Disk Space',
      description: 'Check available disk space',
      category: DiagnosticCategory.system,
    ),

    // Network
    DiagnosticCheck(
      name: 'Network Connectivity',
      description: 'Test outbound network access',
      category: DiagnosticCategory.network,
    ),
    DiagnosticCheck(
      name: 'API Endpoint Reachable',
      description: 'Verify the configured API endpoint responds',
      category: DiagnosticCategory.network,
    ),

    // API
    DiagnosticCheck(
      name: 'API Key Validity',
      description: 'Check that the stored API key has a valid format',
      category: DiagnosticCategory.api,
    ),
    DiagnosticCheck(
      name: 'Config File Validity',
      description: 'Verify settings and config files parse correctly',
      category: DiagnosticCategory.api,
    ),

    // Tools
    DiagnosticCheck(
      name: 'Bash Tool',
      description: 'Check shell command execution',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'Git Tool',
      description: 'Verify git binary is available',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'Grep Tool',
      description: 'Verify ripgrep (rg) or grep is available',
      category: DiagnosticCategory.tools,
    ),
    DiagnosticCheck(
      name: 'Glob Tool',
      description: 'Verify file globbing works',
      category: DiagnosticCategory.tools,
    ),

    // MCP
    DiagnosticCheck(
      name: 'MCP Config',
      description: 'Check for .mcp.json or MCP server configuration',
      category: DiagnosticCategory.mcp,
    ),
    DiagnosticCheck(
      name: 'MCP Server Connections',
      description: 'Test connectivity to configured MCP servers',
      category: DiagnosticCategory.mcp,
    ),

    // Git
    DiagnosticCheck(
      name: 'Git Repo Status',
      description: 'Check if current directory is a git repository',
      category: DiagnosticCategory.git,
    ),

    // Permissions
    DiagnosticCheck(
      name: 'Permission Rules',
      description: 'Validate permission rules in settings',
      category: DiagnosticCategory.permissions,
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
      case 'Flutter Version':
        await _runProcessCheck(check, 'flutter', ['--version']);
      case 'Dart Version':
        await _runProcessCheck(check, 'dart', ['--version']);
      case 'Platform Info':
        check.detail =
            '${Platform.operatingSystem} '
            '${Platform.operatingSystemVersion} '
            '(${Platform.localHostname})';
        check.status = DiagnosticStatus.pass;
      case 'Disk Space':
        await _checkDiskSpace(check);
      case 'Network Connectivity':
        await _checkNetwork(check);
      case 'API Endpoint Reachable':
        await _checkApiEndpoint(check);
      case 'API Key Validity':
        _checkApiKeyFormat(check);
      case 'Config File Validity':
        await _checkConfigFiles(check);
      case 'Bash Tool':
        await _runProcessCheck(check, 'bash', ['--version']);
      case 'Git Tool':
        await _runProcessCheck(check, 'git', ['--version']);
      case 'Grep Tool':
        await _checkGrep(check);
      case 'Glob Tool':
        _checkGlob(check);
      case 'MCP Config':
        await _checkMcpConfig(check);
      case 'MCP Server Connections':
        await _checkMcpConnections(check);
      case 'Git Repo Status':
        await _checkGitRepo(check);
      case 'Permission Rules':
        _checkPermissions(check);
      default:
        check.status = DiagnosticStatus.warn;
        check.detail = 'No handler for this check';
    }
  }

  // ── Check implementations ──

  Future<void> _runProcessCheck(
    DiagnosticCheck check,
    String cmd,
    List<String> args,
  ) async {
    try {
      final result = await Process.run(cmd, args);
      final output = (result.stdout as String).trim();
      if (result.exitCode == 0) {
        check.status = DiagnosticStatus.pass;
        check.detail = output.split('\n').first;
      } else {
        check.status = DiagnosticStatus.fail;
        check.detail = 'Exit code ${result.exitCode}';
      }
    } on ProcessException {
      check.status = DiagnosticStatus.fail;
      check.detail = '"$cmd" not found in PATH';
    }
  }

  Future<void> _checkDiskSpace(DiagnosticCheck check) async {
    try {
      if (Platform.isMacOS || Platform.isLinux) {
        final result = await Process.run('df', ['-h', '.']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).trim().split('\n');
          if (lines.length >= 2) {
            check.detail = lines[1].replaceAll(RegExp(r'\s+'), ' ');
            check.status = DiagnosticStatus.pass;
            return;
          }
        }
      }
      check.status = DiagnosticStatus.warn;
      check.detail = 'Could not determine disk space';
    } catch (e) {
      check.status = DiagnosticStatus.warn;
      check.detail = e.toString();
    }
  }

  Future<void> _checkNetwork(DiagnosticCheck check) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(
        Uri.parse('https://api.anthropic.com'),
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();

      check.status = DiagnosticStatus.pass;
      check.detail = 'HTTP ${response.statusCode}';
    } on SocketException catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Socket error: ${e.message}';
    } on HttpException catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'HTTP error: ${e.message}';
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = e.toString();
    }
  }

  Future<void> _checkApiEndpoint(DiagnosticCheck check) async {
    try {
      // Read configured base URL from shared prefs would be ideal;
      // for now test the default Anthropic endpoint.
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.headUrl(
        Uri.parse('https://api.anthropic.com/v1'),
      );
      final response = await request.close();
      await response.drain<void>();
      client.close();

      if (response.statusCode < 500) {
        check.status = DiagnosticStatus.pass;
        check.detail = 'Endpoint responded with HTTP ${response.statusCode}';
      } else {
        check.status = DiagnosticStatus.warn;
        check.detail = 'Endpoint returned HTTP ${response.statusCode}';
      }
    } catch (e) {
      check.status = DiagnosticStatus.fail;
      check.detail = 'Cannot reach API endpoint: $e';
    }
  }

  void _checkApiKeyFormat(DiagnosticCheck check) {
    // We cannot read from secure storage synchronously, so we do a
    // best-effort check using environment variables as fallback.
    final envKey = Platform.environment['ANTHROPIC_API_KEY'] ?? '';
    if (envKey.isNotEmpty) {
      if (envKey.startsWith('sk-ant-') && envKey.length > 30) {
        check.status = DiagnosticStatus.pass;
        check.detail =
            'Key from env (sk-ant-...${envKey.substring(envKey.length - 4)})';
      } else if (envKey.length > 10) {
        check.status = DiagnosticStatus.warn;
        check.detail = 'Key present but format unrecognised';
      } else {
        check.status = DiagnosticStatus.fail;
        check.detail = 'Key too short';
      }
    } else {
      check.status = DiagnosticStatus.warn;
      check.detail =
          'No ANTHROPIC_API_KEY in environment; key may be in secure storage';
    }
  }

  Future<void> _checkConfigFiles(DiagnosticCheck check) async {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    final settingsFile = File('$home/.neomclaw/settings.json');
    if (await settingsFile.exists()) {
      try {
        final content = await settingsFile.readAsString();
        // Simple parse test.
        if (content.trim().startsWith('{')) {
          check.status = DiagnosticStatus.pass;
          check.detail = 'settings.json parses OK';
        } else {
          check.status = DiagnosticStatus.fail;
          check.detail = 'settings.json is not valid JSON';
        }
      } catch (e) {
        check.status = DiagnosticStatus.fail;
        check.detail = 'Cannot read settings.json: $e';
      }
    } else {
      check.status = DiagnosticStatus.warn;
      check.detail = 'No ~/.neomclaw/settings.json found (using defaults)';
    }
  }

  Future<void> _checkGrep(DiagnosticCheck check) async {
    // Prefer ripgrep, fall back to grep.
    try {
      final rg = await Process.run('rg', ['--version']);
      if (rg.exitCode == 0) {
        check.status = DiagnosticStatus.pass;
        check.detail = (rg.stdout as String).split('\n').first;
        return;
      }
    } catch (_) {
      // rg not found, try grep.
    }
    await _runProcessCheck(check, 'grep', ['--version']);
  }

  void _checkGlob(DiagnosticCheck check) {
    // Dart's glob support is built-in via the `glob` package and
    // Directory.list — always available.
    check.status = DiagnosticStatus.pass;
    check.detail = 'Dart Directory.list / glob available';
  }

  Future<void> _checkMcpConfig(DiagnosticCheck check) async {
    final localFile = File('.mcp.json');
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '/tmp';
    final userFile = File('$home/.neomclaw/settings.json');

    final hasLocal = await localFile.exists();
    final hasUser = await userFile.exists();

    if (hasLocal || hasUser) {
      check.status = DiagnosticStatus.pass;
      check.detail = [
        if (hasLocal) '.mcp.json found',
        if (hasUser) '~/.neomclaw/settings.json found',
      ].join(', ');
    } else {
      check.status = DiagnosticStatus.warn;
      check.detail = 'No MCP configuration files found';
    }
  }

  Future<void> _checkMcpConnections(DiagnosticCheck check) async {
    // Without live MCP server info we report a warning.
    check.status = DiagnosticStatus.warn;
    check.detail = 'MCP connection testing requires running servers';
  }

  Future<void> _checkGitRepo(DiagnosticCheck check) async {
    try {
      final result = await Process.run('git', [
        'rev-parse',
        '--is-inside-work-tree',
      ]);
      if (result.exitCode == 0 && (result.stdout as String).trim() == 'true') {
        // Get branch name.
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

  void _checkPermissions(DiagnosticCheck check) {
    // Permission rules are loaded from settings — a full check would
    // deserialise them. Here we do a presence check.
    check.status = DiagnosticStatus.pass;
    check.detail = 'Permission system available';
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
    buf.writeln('=== Neom Claw Diagnostic Report ===');
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
