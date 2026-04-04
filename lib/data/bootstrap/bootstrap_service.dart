// bootstrap_service.dart — Application initialization for flutter_claw
// Port of neom_claw/src/bootstrap/ (~1.8K TS LOC) to pure Dart + dart:io.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';

// ---------------------------------------------------------------------------
// Enums & constants
// ---------------------------------------------------------------------------

enum BootstrapStepStatus {
  pending,
  running,
  completed,
  skipped,
  failed;

  String get label => switch (this) {
        pending => 'Pending',
        running => 'Running',
        completed => 'Done',
        skipped => 'Skipped',
        failed => 'Failed',
      };
}

enum BootstrapResultStatus {
  success,
  partialSuccess,
  failure;
}

// ---------------------------------------------------------------------------
// BootstrapStep — individual step with name, duration, status
// ---------------------------------------------------------------------------

class BootstrapStep {
  final String id;
  final String name;
  BootstrapStepStatus status;
  Duration duration;
  String? error;
  String? warning;

  BootstrapStep({
    required this.id,
    required this.name,
    this.status = BootstrapStepStatus.pending,
    this.duration = Duration.zero,
    this.error,
    this.warning,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.label,
        'durationMs': duration.inMilliseconds,
        'error': error,
        'warning': warning,
      };
}

// ---------------------------------------------------------------------------
// BootstrapProgress — progress tracking for startup
// ---------------------------------------------------------------------------

class BootstrapProgress {
  final List<BootstrapStep> steps;
  int _currentIndex;
  final Stopwatch _totalTimer;

  BootstrapProgress({required List<BootstrapStep> steps})
      : steps = steps,
        _currentIndex = 0,
        _totalTimer = Stopwatch();

  int get currentIndex => _currentIndex;
  int get totalSteps => steps.length;
  double get fraction => totalSteps == 0 ? 0 : _currentIndex / totalSteps;
  BootstrapStep? get currentStep =>
      _currentIndex < steps.length ? steps[_currentIndex] : null;
  Duration get elapsed => _totalTimer.elapsed;
  bool get isComplete => _currentIndex >= steps.length;

  void start() => _totalTimer.start();
  void stop() => _totalTimer.stop();

  void advanceStep() {
    if (_currentIndex < steps.length) _currentIndex++;
  }

  int get completedCount =>
      steps.where((s) => s.status == BootstrapStepStatus.completed).length;
  int get failedCount =>
      steps.where((s) => s.status == BootstrapStepStatus.failed).length;
  int get skippedCount =>
      steps.where((s) => s.status == BootstrapStepStatus.skipped).length;

  String format() {
    final pct = (fraction * 100).toStringAsFixed(0);
    final current = currentStep;
    final stepName = current?.name ?? 'Done';
    return '[$pct%] $stepName (${elapsed.inMilliseconds}ms)';
  }
}

// ---------------------------------------------------------------------------
// BootstrapConfig — configuration for bootstrap
// ---------------------------------------------------------------------------

class BootstrapConfig {
  final bool debugMode;
  final Set<String> skipSteps;
  final bool skipUpdateCheck;
  final bool skipTelemetry;
  final bool skipPlugins;
  final bool skipMcpServers;
  final bool skipDoctor;
  final Duration stepTimeout;
  final String? configDir;
  final String? projectDir;

  const BootstrapConfig({
    this.debugMode = false,
    this.skipSteps = const {},
    this.skipUpdateCheck = false,
    this.skipTelemetry = false,
    this.skipPlugins = false,
    this.skipMcpServers = false,
    this.skipDoctor = false,
    this.stepTimeout = const Duration(seconds: 30),
    this.configDir,
    this.projectDir,
  });

  bool shouldSkip(String stepId) {
    if (skipSteps.contains(stepId)) return true;
    if (stepId == 'update_check' && skipUpdateCheck) return true;
    if (stepId == 'telemetry' && skipTelemetry) return true;
    if (stepId == 'plugins' && skipPlugins) return true;
    if (stepId == 'mcp_servers' && skipMcpServers) return true;
    if (stepId == 'doctor' && skipDoctor) return true;
    return false;
  }
}

// ---------------------------------------------------------------------------
// ProjectInfo — detected project information
// ---------------------------------------------------------------------------

class ProjectInfo {
  final String? gitRoot;
  final String? gitBranch;
  final String? gitRemoteUrl;
  final String projectDir;
  final List<String> languages;
  final String? framework;
  final String? packageManager;
  final bool isGitRepo;
  final bool hasPackageJson;
  final bool hasPubspecYaml;
  final bool hasCargoToml;
  final bool hasGoMod;
  final bool hasPyprojectToml;
  final bool hasRequirementsTxt;
  final Map<String, dynamic> extraInfo;

  const ProjectInfo({
    this.gitRoot,
    this.gitBranch,
    this.gitRemoteUrl,
    required this.projectDir,
    this.languages = const [],
    this.framework,
    this.packageManager,
    this.isGitRepo = false,
    this.hasPackageJson = false,
    this.hasPubspecYaml = false,
    this.hasCargoToml = false,
    this.hasGoMod = false,
    this.hasPyprojectToml = false,
    this.hasRequirementsTxt = false,
    this.extraInfo = const {},
  });

  Map<String, dynamic> toJson() => {
        'gitRoot': gitRoot,
        'gitBranch': gitBranch,
        'gitRemoteUrl': gitRemoteUrl,
        'projectDir': projectDir,
        'languages': languages,
        'framework': framework,
        'packageManager': packageManager,
        'isGitRepo': isGitRepo,
      };
}

// ---------------------------------------------------------------------------
// MemoryFile — loaded NEOMCLAW.md content
// ---------------------------------------------------------------------------

class MemoryFile {
  final String path;
  final String content;
  final MemoryFileSource source;

  const MemoryFile({
    required this.path,
    required this.content,
    required this.source,
  });
}

enum MemoryFileSource {
  projectRoot,
  parentDir,
  userHome,
  configDir;

  String get label => switch (this) {
        projectRoot => 'Project root',
        parentDir => 'Parent directory',
        userHome => 'User home',
        configDir => 'Config directory',
      };
}

// ---------------------------------------------------------------------------
// BootstrapResult
// ---------------------------------------------------------------------------

class BootstrapResult {
  final BootstrapResultStatus status;
  final List<BootstrapStep> steps;
  final List<String> warnings;
  final List<String> errors;
  final ProjectInfo? projectInfo;
  final List<MemoryFile> memoryFiles;
  final Duration totalDuration;
  final String? shell;
  final Map<String, dynamic> settings;

  const BootstrapResult({
    required this.status,
    required this.steps,
    this.warnings = const [],
    this.errors = const [],
    this.projectInfo,
    this.memoryFiles = const [],
    this.totalDuration = Duration.zero,
    this.shell,
    this.settings = const {},
  });

  bool get isSuccess => status == BootstrapResultStatus.success;

  String formatReport() {
    final buf = StringBuffer();
    buf.writeln('Bootstrap ${status.name} in ${totalDuration.inMilliseconds}ms');
    buf.writeln('Steps:');
    for (final step in steps) {
      final icon = switch (step.status) {
        BootstrapStepStatus.completed => '+',
        BootstrapStepStatus.skipped => '-',
        BootstrapStepStatus.failed => 'x',
        _ => '?',
      };
      buf.writeln('  [$icon] ${step.name} (${step.duration.inMilliseconds}ms)');
      if (step.error != null) buf.writeln('      Error: ${step.error}');
      if (step.warning != null) buf.writeln('      Warn: ${step.warning}');
    }
    if (warnings.isNotEmpty) {
      buf.writeln('Warnings:');
      for (final w in warnings) {
        buf.writeln('  - $w');
      }
    }
    if (errors.isNotEmpty) {
      buf.writeln('Errors:');
      for (final e in errors) {
        buf.writeln('  - $e');
      }
    }
    return buf.toString();
  }
}

// ---------------------------------------------------------------------------
// Environment validation
// ---------------------------------------------------------------------------

class EnvironmentCheck {
  final String name;
  final bool passed;
  final String? message;
  final String? version;

  const EnvironmentCheck({
    required this.name,
    required this.passed,
    this.message,
    this.version,
  });
}

Future<List<EnvironmentCheck>> validateEnvironment() async {
  final checks = <EnvironmentCheck>[];

  // Check Dart
  checks.add(await _checkTool('dart', ['--version']));

  // Check git
  checks.add(await _checkTool('git', ['--version']));

  // Check flutter (optional)
  checks.add(await _checkTool('flutter', ['--version'], required: false));

  // Check node (optional — for MCP servers)
  checks.add(await _checkTool('node', ['--version'], required: false));

  // Check disk space
  checks.add(await _checkDiskSpace());

  // Check write permissions to home config
  checks.add(await _checkWritePermissions());

  return checks;
}

Future<EnvironmentCheck> _checkTool(String tool, List<String> args,
    {bool required = true}) async {
  try {
    final result = await Process.run(tool, args);
    if (result.exitCode == 0) {
      final version = result.stdout.toString().trim().split('\n').first;
      return EnvironmentCheck(name: tool, passed: true, version: version);
    }
    return EnvironmentCheck(
      name: tool,
      passed: !required,
      message: required ? '$tool returned exit code ${result.exitCode}' : '$tool not available (optional)',
    );
  } catch (_) {
    return EnvironmentCheck(
      name: tool,
      passed: !required,
      message: required ? '$tool not found in PATH' : '$tool not found (optional)',
    );
  }
}

Future<EnvironmentCheck> _checkDiskSpace() async {
  try {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final stat = await FileStat.stat(home);
    // We can't easily get free disk space from Dart, so just verify the dir exists
    if (stat.type != FileSystemEntityType.notFound) {
      return const EnvironmentCheck(
          name: 'disk_space', passed: true, message: 'Home directory accessible');
    }
    return const EnvironmentCheck(
        name: 'disk_space', passed: false, message: 'Home directory not found');
  } catch (e) {
    return EnvironmentCheck(
        name: 'disk_space', passed: false, message: 'Error checking disk: $e');
  }
}

Future<EnvironmentCheck> _checkWritePermissions() async {
  try {
    final home = Platform.environment['HOME'] ?? '/tmp';
    final configDir = Directory('/.neomclaw');
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }
    // Test write
    final testFile = File('${configDir.path}/.write_test');
    testFile.writeAsStringSync('test');
    testFile.deleteSync();
    return const EnvironmentCheck(
        name: 'write_permissions', passed: true, message: 'Config dir writable');
  } catch (e) {
    return EnvironmentCheck(
        name: 'write_permissions',
        passed: false,
        message: 'Cannot write to config dir: $e');
  }
}

// ---------------------------------------------------------------------------
// Project detection
// ---------------------------------------------------------------------------

Future<ProjectInfo> detectProjectInfo(String projectDir) async {
  final dir = Directory(projectDir);
  if (!dir.existsSync()) {
    return ProjectInfo(projectDir: projectDir);
  }

  // Git detection
  String? gitRoot;
  String? gitBranch;
  String? gitRemoteUrl;
  bool isGitRepo = false;

  try {
    final revParse = await Process.run('git', ['rev-parse', '--show-toplevel'],
        workingDirectory: projectDir);
    if (revParse.exitCode == 0) {
      gitRoot = revParse.stdout.toString().trim();
      isGitRepo = true;
    }
  } catch (_) {}

  if (isGitRepo) {
    try {
      final branch = await Process.run('git', ['branch', '--show-current'],
          workingDirectory: projectDir);
      if (branch.exitCode == 0) {
        gitBranch = branch.stdout.toString().trim();
      }
    } catch (_) {}

    try {
      final remote = await Process.run(
          'git', ['config', '--get', 'remote.origin.url'],
          workingDirectory: projectDir);
      if (remote.exitCode == 0) {
        gitRemoteUrl = remote.stdout.toString().trim();
      }
    } catch (_) {}
  }

  // File detection
  final hasPackageJson = File('$projectDir/package.json').existsSync();
  final hasPubspecYaml = File('$projectDir/pubspec.yaml').existsSync();
  final hasCargoToml = File('$projectDir/Cargo.toml').existsSync();
  final hasGoMod = File('$projectDir/go.mod').existsSync();
  final hasPyprojectToml = File('$projectDir/pyproject.toml').existsSync();
  final hasRequirementsTxt = File('$projectDir/requirements.txt').existsSync();

  // Language detection
  final languages = <String>[];
  if (hasPubspecYaml) languages.add('dart');
  if (hasPackageJson) languages.add('javascript');
  if (hasCargoToml) languages.add('rust');
  if (hasGoMod) languages.add('go');
  if (hasPyprojectToml || hasRequirementsTxt) languages.add('python');

  // Check for TypeScript
  if (hasPackageJson) {
    if (File('$projectDir/tsconfig.json').existsSync()) {
      languages.add('typescript');
    }
  }

  // Framework detection
  String? framework;
  if (hasPubspecYaml) {
    try {
      final pubspec = File('$projectDir/pubspec.yaml').readAsStringSync();
      if (pubspec.contains('flutter:')) {
        framework = 'flutter';
      }
    } catch (_) {}
  }
  if (hasPackageJson) {
    try {
      final pkg =
          jsonDecode(File('$projectDir/package.json').readAsStringSync())
              as Map<String, dynamic>;
      final deps = <String>[
        ...((pkg['dependencies'] as Map<String, dynamic>?) ?? {}).keys,
        ...((pkg['devDependencies'] as Map<String, dynamic>?) ?? {}).keys,
      ];
      if (deps.contains('next')) {
        framework = 'next.js';
      } else if (deps.contains('react')) {
        framework = 'react';
      } else if (deps.contains('vue')) {
        framework = 'vue';
      } else if (deps.contains('@angular/core')) {
        framework = 'angular';
      } else if (deps.contains('svelte')) {
        framework = 'svelte';
      } else if (deps.contains('express')) {
        framework = 'express';
      }
    } catch (_) {}
  }

  // Package manager detection
  String? packageManager;
  if (File('$projectDir/pnpm-lock.yaml').existsSync()) {
    packageManager = 'pnpm';
  } else if (File('$projectDir/yarn.lock').existsSync()) {
    packageManager = 'yarn';
  } else if (File('$projectDir/bun.lockb').existsSync()) {
    packageManager = 'bun';
  } else if (File('$projectDir/package-lock.json').existsSync()) {
    packageManager = 'npm';
  } else if (hasPubspecYaml) {
    packageManager = 'pub';
  } else if (hasCargoToml) {
    packageManager = 'cargo';
  } else if (hasGoMod) {
    packageManager = 'go';
  } else if (File('$projectDir/Pipfile').existsSync()) {
    packageManager = 'pipenv';
  } else if (File('$projectDir/poetry.lock').existsSync()) {
    packageManager = 'poetry';
  } else if (hasRequirementsTxt) {
    packageManager = 'pip';
  }

  return ProjectInfo(
    gitRoot: gitRoot,
    gitBranch: gitBranch,
    gitRemoteUrl: gitRemoteUrl,
    projectDir: projectDir,
    languages: languages,
    framework: framework,
    packageManager: packageManager,
    isGitRepo: isGitRepo,
    hasPackageJson: hasPackageJson,
    hasPubspecYaml: hasPubspecYaml,
    hasCargoToml: hasCargoToml,
    hasGoMod: hasGoMod,
    hasPyprojectToml: hasPyprojectToml,
    hasRequirementsTxt: hasRequirementsTxt,
  );
}

// ---------------------------------------------------------------------------
// Memory file loading — find and load all NEOMCLAW.md files
// ---------------------------------------------------------------------------

Future<List<MemoryFile>> loadMemoryFiles(String projectDir) async {
  final files = <MemoryFile>[];
  final home = Platform.environment['HOME'] ?? '';

  // 1. Project root NEOMCLAW.md
  final projectMemory = File('$projectDir/NEOMCLAW.md');
  if (projectMemory.existsSync()) {
    try {
      files.add(MemoryFile(
        path: projectMemory.path,
        content: projectMemory.readAsStringSync(),
        source: MemoryFileSource.projectRoot,
      ));
    } catch (_) {}
  }

  // 2. .neomclaw/NEOMCLAW.md in project
  final projectNeomClawDir = File('$projectDir/.neomclaw/NEOMCLAW.md');
  if (projectNeomClawDir.existsSync()) {
    try {
      files.add(MemoryFile(
        path: projectNeomClawDir.path,
        content: projectNeomClawDir.readAsStringSync(),
        source: MemoryFileSource.projectRoot,
      ));
    } catch (_) {}
  }

  // 3. Walk parent directories (up to 5 levels or home)
  var current = Directory(projectDir).parent;
  int depth = 0;
  while (depth < 5 && current.path != '/' && current.path != home) {
    final parentMemory = File('${current.path}/NEOMCLAW.md');
    if (parentMemory.existsSync()) {
      try {
        files.add(MemoryFile(
          path: parentMemory.path,
          content: parentMemory.readAsStringSync(),
          source: MemoryFileSource.parentDir,
        ));
      } catch (_) {}
    }
    current = current.parent;
    depth++;
  }

  // 4. User home NEOMCLAW.md
  if (home.isNotEmpty) {
    final homeMemory = File('$home/NEOMCLAW.md');
    if (homeMemory.existsSync()) {
      try {
        files.add(MemoryFile(
          path: homeMemory.path,
          content: homeMemory.readAsStringSync(),
          source: MemoryFileSource.userHome,
        ));
      } catch (_) {}
    }

    // 5. Config dir
    final configMemory = File('$home/.neomclaw/NEOMCLAW.md');
    if (configMemory.existsSync() &&
        !files.any((f) => f.path == configMemory.path)) {
      try {
        files.add(MemoryFile(
          path: configMemory.path,
          content: configMemory.readAsStringSync(),
          source: MemoryFileSource.configDir,
        ));
      } catch (_) {}
    }
  }

  return files;
}

// ---------------------------------------------------------------------------
// Shell detection
// ---------------------------------------------------------------------------

String detectShell() {
  final shell = Platform.environment['SHELL'] ?? '';
  if (shell.contains('zsh')) return 'zsh';
  if (shell.contains('bash')) return 'bash';
  if (shell.contains('fish')) return 'fish';
  if (shell.contains('nu')) return 'nushell';
  if (shell.contains('pwsh') || shell.contains('powershell')) return 'powershell';
  if (shell.isNotEmpty) return shell.split('/').last;
  // Fallback
  if (Platform.isWindows) return 'cmd';
  return 'sh';
}

// ---------------------------------------------------------------------------
// Settings loading
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _loadSettingsFile(String path) async {
  final file = File(path);
  if (!file.existsSync()) return {};
  try {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  return {};
}

Future<Map<String, dynamic>> loadAllSettings({
  required String projectDir,
  String? configDir,
}) async {
  final home = Platform.environment['HOME'] ?? '';
  final cfgDir = configDir ?? '/.neomclaw';

  // Layer settings: user -> project -> local -> policy
  final userSettings = await _loadSettingsFile('$cfgDir/settings.json');
  final projectSettings =
      await _loadSettingsFile('$projectDir/.neomclaw/settings.json');
  final localSettings =
      await _loadSettingsFile('$projectDir/.neomclaw/settings.local.json');

  // Policy settings (from org)
  final policySettings =
      await _loadSettingsFile('$cfgDir/policy.json');

  // Merge: policy overrides everything, then local, then project, then user
  final merged = <String, dynamic>{};
  merged.addAll(userSettings);
  merged.addAll(projectSettings);
  merged.addAll(localSettings);
  merged.addAll(policySettings);

  return merged;
}

// ---------------------------------------------------------------------------
// BootstrapService — the main initialization sequence
// ---------------------------------------------------------------------------

class BootstrapService {
  final BootstrapConfig config;
  final void Function(String message)? onLog;
  final void Function(BootstrapProgress progress)? onProgress;

  BootstrapService({
    BootstrapConfig? config,
    this.onLog,
    this.onProgress,
  }) : config = config ?? const BootstrapConfig();

  Future<BootstrapResult> run() async {
    final steps = _buildSteps();
    final progress = BootstrapProgress(steps: steps);
    progress.start();

    final warnings = <String>[];
    final errors = <String>[];
    ProjectInfo? projectInfo;
    List<MemoryFile> memoryFiles = [];
    String? shell;
    Map<String, dynamic> settings = {};

    for (int i = 0; i < steps.length; i++) {
      final step = steps[i];
      onProgress?.call(progress);

      if (config.shouldSkip(step.id)) {
        step.status = BootstrapStepStatus.skipped;
        _log('Skipping: ${step.name}');
        progress.advanceStep();
        continue;
      }

      step.status = BootstrapStepStatus.running;
      final sw = Stopwatch()..start();

      try {
        final result = await _executeStep(step.id).timeout(config.stepTimeout);
        sw.stop();
        step.duration = sw.elapsed;

        if (result is ProjectInfo) projectInfo = result;
        if (result is List<MemoryFile>) memoryFiles = result;
        if (result is String && step.id == 'detect_shell') shell = result;
        if (result is Map<String, dynamic> && step.id == 'load_settings') {
          settings = result;
        }
        if (result is String && result.startsWith('WARN:')) {
          step.warning = result.substring(5);
          warnings.add(step.warning!);
        }

        step.status = BootstrapStepStatus.completed;
        _log('Done: ${step.name} (${step.duration.inMilliseconds}ms)');
      } on TimeoutException {
        sw.stop();
        step.duration = sw.elapsed;
        step.status = BootstrapStepStatus.failed;
        step.error = 'Timed out after ${config.stepTimeout.inSeconds}s';
        errors.add('${step.name}: ${step.error}');
        _log('Timeout: ${step.name}');
      } catch (e) {
        sw.stop();
        step.duration = sw.elapsed;
        step.status = BootstrapStepStatus.failed;
        step.error = e.toString();
        errors.add('${step.name}: $e');
        _log('Failed: ${step.name}: $e');
      }

      progress.advanceStep();
    }

    progress.stop();

    final resultStatus = errors.isEmpty
        ? BootstrapResultStatus.success
        : warnings.isNotEmpty || progress.completedCount > progress.failedCount
            ? BootstrapResultStatus.partialSuccess
            : BootstrapResultStatus.failure;

    final result = BootstrapResult(
      status: resultStatus,
      steps: steps,
      warnings: warnings,
      errors: errors,
      projectInfo: projectInfo,
      memoryFiles: memoryFiles,
      totalDuration: progress.elapsed,
      shell: shell,
      settings: settings,
    );

    _log(result.formatReport());
    return result;
  }

  List<BootstrapStep> _buildSteps() => [
        BootstrapStep(id: 'load_settings', name: 'Load settings'),
        BootstrapStep(id: 'detect_shell', name: 'Detect shell'),
        BootstrapStep(id: 'detect_project', name: 'Detect project'),
        BootstrapStep(id: 'detect_git', name: 'Detect git repository'),
        BootstrapStep(id: 'load_memory', name: 'Load memory files'),
        BootstrapStep(id: 'validate_env', name: 'Validate environment'),
        BootstrapStep(id: 'init_api', name: 'Initialize API client'),
        BootstrapStep(id: 'register_tools', name: 'Register tools'),
        BootstrapStep(id: 'register_commands', name: 'Register commands'),
        BootstrapStep(id: 'mcp_servers', name: 'Start MCP servers'),
        BootstrapStep(id: 'plugins', name: 'Load plugins'),
        BootstrapStep(id: 'keybindings', name: 'Load keybindings'),
        BootstrapStep(id: 'telemetry', name: 'Initialize telemetry'),
        BootstrapStep(id: 'update_check', name: 'Check for updates'),
        BootstrapStep(id: 'doctor', name: 'Run doctor checks'),
      ];

  Future<Object?> _executeStep(String stepId) async {
    final projectDir = config.projectDir ?? Directory.current.path;
    switch (stepId) {
      case 'load_settings':
        return loadAllSettings(
          projectDir: projectDir,
          configDir: config.configDir,
        );

      case 'detect_shell':
        return detectShell();

      case 'detect_project':
        return detectProjectInfo(projectDir);

      case 'detect_git':
        return _detectGit(projectDir);

      case 'load_memory':
        return loadMemoryFiles(projectDir);

      case 'validate_env':
        final checks = await validateEnvironment();
        final failed = checks.where((c) => !c.passed).toList();
        if (failed.isNotEmpty) {
          final names = failed.map((c) => c.name).join(', ');
          return 'WARN:Missing tools: $names';
        }
        return null;

      case 'init_api':
        return _initializeApiClient();

      case 'register_tools':
        return _registerTools();

      case 'register_commands':
        return _registerCommands();

      case 'mcp_servers':
        return _startMcpServers(projectDir);

      case 'plugins':
        return _loadPlugins(projectDir);

      case 'keybindings':
        return _loadKeybindings();

      case 'telemetry':
        return _initializeTelemetry();

      case 'update_check':
        return _checkForUpdates();

      case 'doctor':
        return _runDoctorChecks(projectDir);

      default:
        return null;
    }
  }

  Future<Object?> _detectGit(String projectDir) async {
    try {
      final result = await Process.run('git', ['rev-parse', '--is-inside-work-tree'],
          workingDirectory: projectDir);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Object?> _initializeApiClient() async {
    // Check for API key in environment
    final apiKey = Platform.environment['ANTHROPIC_API_KEY'] ??
        Platform.environment['NEOMCLAW_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      return 'WARN:No API key found in environment';
    }
    // Validate key format
    if (!apiKey.startsWith('sk-ant-')) {
      return 'WARN:API key format may be invalid';
    }
    return null;
  }

  Future<Object?> _registerTools() async {
    // Register built-in tools
    final tools = [
      'read_file',
      'write_file',
      'edit_file',
      'list_directory',
      'search_files',
      'run_command',
      'glob',
      'grep',
      'web_search',
      'web_fetch',
    ];
    _log('Registered ${tools.length} built-in tools');
    return tools;
  }

  Future<Object?> _registerCommands() async {
    // Register slash commands
    final commands = [
      '/help',
      '/clear',
      '/compact',
      '/config',
      '/cost',
      '/doctor',
      '/init',
      '/login',
      '/logout',
      '/memory',
      '/model',
      '/permissions',
      '/review',
      '/status',
      '/vim',
    ];
    _log('Registered ${commands.length} commands');
    return commands;
  }

  Future<Object?> _startMcpServers(String projectDir) async {
    // Load MCP server configurations
    final configPaths = [
      '$projectDir/.neomclaw/mcp.json',
      '$projectDir/.mcp.json',
    ];
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      configPaths.add('$home/.neomclaw/mcp.json');
    }

    int serverCount = 0;
    for (final path in configPaths) {
      final file = File(path);
      if (!file.existsSync()) continue;
      try {
        final content = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final servers = content['mcpServers'] as Map<String, dynamic>? ?? {};
        serverCount += servers.length;
        _log('Found ${servers.length} MCP servers in $path');
      } catch (e) {
        _log('Error reading MCP config $path: $e');
      }
    }

    if (serverCount == 0) {
      return 'WARN:No MCP servers configured';
    }
    return null;
  }

  Future<Object?> _loadPlugins(String projectDir) async {
    final pluginDir = Directory('$projectDir/.neomclaw/plugins');
    if (!pluginDir.existsSync()) return null;

    final plugins = pluginDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') || f.path.endsWith('.json'))
        .toList();

    _log('Found ${plugins.length} plugins');
    return plugins.length;
  }

  Future<Object?> _loadKeybindings() async {
    final home = Platform.environment['HOME'] ?? '';
    final keybindingsFile = File('$home/.neomclaw/keybindings.json');
    if (!keybindingsFile.existsSync()) {
      _log('No custom keybindings file found, using defaults');
      return null;
    }
    try {
      final content = jsonDecode(keybindingsFile.readAsStringSync());
      if (content is List) {
        _log('Loaded ${content.length} custom keybindings');
        return content.length;
      }
    } catch (e) {
      return 'WARN:Error loading keybindings: $e';
    }
    return null;
  }

  Future<Object?> _initializeTelemetry() async {
    final home = Platform.environment['HOME'] ?? '';
    final telemetryFile = File('$home/.neomclaw/telemetry.json');
    if (telemetryFile.existsSync()) {
      try {
        final config =
            jsonDecode(telemetryFile.readAsStringSync()) as Map<String, dynamic>;
        final enabled = config['enabled'] as bool? ?? false;
        _log('Telemetry ${enabled ? "enabled" : "disabled"}');
        return enabled;
      } catch (_) {}
    }
    return false;
  }

  Future<Object?> _checkForUpdates() async {
    // Check current version against latest
    try {
      final result = await Process.run('dart', ['pub', 'global', 'list']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        if (output.contains('flutter_claw')) {
          _log('Current installation found');
        }
      }
    } catch (_) {
      // Update check is best-effort
    }
    return null;
  }

  Future<Object?> _runDoctorChecks(String projectDir) async {
    final issues = <String>[];

    // Check git config
    try {
      final name = await Process.run('git', ['config', 'user.name']);
      if (name.exitCode != 0 || name.stdout.toString().trim().isEmpty) {
        issues.add('Git user.name not configured');
      }
      final email = await Process.run('git', ['config', 'user.email']);
      if (email.exitCode != 0 || email.stdout.toString().trim().isEmpty) {
        issues.add('Git user.email not configured');
      }
    } catch (_) {}

    // Check for common misconfigurations
    final gitignore = File('$projectDir/.gitignore');
    if (gitignore.existsSync()) {
      final content = gitignore.readAsStringSync();
      if (!content.contains('.neomclaw')) {
        issues.add('.neomclaw directory not in .gitignore');
      }
    }

    if (issues.isNotEmpty) {
      return 'WARN:${issues.join('; ')}';
    }
    return null;
  }

  void _log(String message) {
    if (config.debugMode) {
      onLog?.call('[Bootstrap] $message');
    }
  }
}
