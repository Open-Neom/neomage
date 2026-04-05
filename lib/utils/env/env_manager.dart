// Port of neomage env.ts + envDynamic.ts + envUtils.ts + envValidation.ts
// + managedEnv.ts + managedEnvConstants.ts
//
// Environment variable management, detection, and validation utilities for
// the neomage package.

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Platform type (env.ts)
// ---------------------------------------------------------------------------

/// Supported platform identifiers.
enum NeomagePlatform {
  win32,
  darwin,
  linux;

  /// Detect the current platform, mapping non-Darwin/Windows to linux.
  static NeomagePlatform detect() {
    if (Platform.isMacOS) return NeomagePlatform.darwin;
    if (Platform.isWindows) return NeomagePlatform.win32;
    return NeomagePlatform.linux;
  }
}

// ---------------------------------------------------------------------------
// envUtils.ts  --  low-level env helpers
// ---------------------------------------------------------------------------

/// Returns the Neomage config home directory (MAGE_CONFIG_DIR or ~/.neomage).
/// Memoized after first call.
String? _neomageConfigHomeDirCache;

String getNeomageConfigHomeDir() {
  if (_neomageConfigHomeDirCache != null) return _neomageConfigHomeDirCache!;
  final configDir = Platform.environment['MAGE_CONFIG_DIR'];
  if (configDir != null && configDir.isNotEmpty) {
    _neomageConfigHomeDirCache = configDir;
  } else {
    _neomageConfigHomeDirCache = p.join(_homedir(), '.neomage');
  }
  return _neomageConfigHomeDirCache!;
}

/// Returns the teams directory under the config home.
String getTeamsDir() {
  return p.join(getNeomageConfigHomeDir(), 'teams');
}

/// Check if NODE_OPTIONS contains a specific flag.
/// Splits on whitespace and checks for exact match.
bool hasNodeOption(String flag) {
  final nodeOptions = Platform.environment['NODE_OPTIONS'];
  if (nodeOptions == null) return false;
  return nodeOptions.split(RegExp(r'\s+')).contains(flag);
}

/// Check if an environment-variable-like value is truthy.
/// Accepts `'1'`, `'true'`, `'yes'`, `'on'` (case-insensitive).
bool isEnvTruthy(dynamic envVar) {
  if (envVar == null) return false;
  if (envVar is bool) return envVar;
  if (envVar is! String) return false;
  if (envVar.isEmpty) return false;
  final normalized = envVar.toLowerCase().trim();
  return const ['1', 'true', 'yes', 'on'].contains(normalized);
}

/// Check if an environment variable is explicitly set to a falsy value.
/// Accepts `'0'`, `'false'`, `'no'`, `'off'` (case-insensitive).
bool isEnvDefinedFalsy(dynamic envVar) {
  if (envVar == null) return false;
  if (envVar is bool) return !envVar;
  if (envVar is! String) return false;
  if (envVar.isEmpty) return false;
  final normalized = envVar.toLowerCase().trim();
  return const ['0', 'false', 'no', 'off'].contains(normalized);
}

/// --bare / MAGE_SIMPLE: skip hooks, LSP, plugin sync, skill walk,
/// attribution, background prefetches, and ALL keychain/credential reads.
bool isBareMode() {
  return isEnvTruthy(Platform.environment['MAGE_SIMPLE']);
}

/// Parse an array of `KEY=VALUE` strings into a map.
Map<String, String> parseEnvVars(List<String>? rawEnvArgs) {
  final parsedEnv = <String, String>{};
  if (rawEnvArgs == null) return parsedEnv;

  for (final envStr in rawEnvArgs) {
    final eqIndex = envStr.indexOf('=');
    if (eqIndex <= 0) {
      throw FormatException(
        'Invalid environment variable format: $envStr, '
        'environment variables should be added as: -e KEY1=value1 -e KEY2=value2',
      );
    }
    final key = envStr.substring(0, eqIndex);
    final value = envStr.substring(eqIndex + 1);
    parsedEnv[key] = value;
  }
  return parsedEnv;
}

/// Get the AWS region with fallback to default.
String getAWSRegion() {
  return Platform.environment['AWS_REGION'] ??
      Platform.environment['AWS_DEFAULT_REGION'] ??
      'us-east-1';
}

/// Get the default Vertex AI region.
String getDefaultVertexRegion() {
  return Platform.environment['CLOUD_ML_REGION'] ?? 'us-east5';
}

/// Check if bash commands should maintain project working directory.
bool shouldMaintainProjectWorkingDir() {
  return isEnvTruthy(
    Platform.environment['MAGE_BASH_MAINTAIN_PROJECT_WORKING_DIR'],
  );
}

/// Check if running on Homespace (ant-internal cloud environment).
bool isRunningOnHomespace() {
  return Platform.environment['USER_TYPE'] == 'ant' &&
      isEnvTruthy(Platform.environment['COO_RUNNING_ON_HOMESPACE']);
}

/// Conservative check for whether Neomage is running inside a protected
/// (privileged or ASL3+) COO namespace or cluster.
bool isInProtectedNamespace() {
  if (Platform.environment['USER_TYPE'] == 'ant') {
    // In the Dart port the protected-namespace module is not available.
    // Return false for external builds.
    return false;
  }
  return false;
}

/// Model-prefix to env-var for Vertex region overrides.
/// Order matters: more specific prefixes before less specific ones.
const _vertexRegionOverrides = <List<String>>[
  ['claude-haiku-4-5', 'VERTEX_REGION_CLAUDE_HAIKU_4_5'],
  ['claude-3-5-haiku', 'VERTEX_REGION_CLAUDE_3_5_HAIKU'],
  ['claude-3-5-sonnet', 'VERTEX_REGION_CLAUDE_3_5_SONNET'],
  ['claude-3-7-sonnet', 'VERTEX_REGION_CLAUDE_3_7_SONNET'],
  ['claude-opus-4-1', 'VERTEX_REGION_CLAUDE_4_1_OPUS'],
  ['claude-opus-4', 'VERTEX_REGION_CLAUDE_4_0_OPUS'],
  ['claude-sonnet-4-6', 'VERTEX_REGION_CLAUDE_4_6_SONNET'],
  ['claude-sonnet-4-5', 'VERTEX_REGION_CLAUDE_4_5_SONNET'],
  ['claude-sonnet-4', 'VERTEX_REGION_CLAUDE_4_0_SONNET'],
];

/// Get the Vertex AI region for a specific model.
/// Different models may be available in different regions.
String? getVertexRegionForModel(String? model) {
  if (model != null) {
    for (final entry in _vertexRegionOverrides) {
      if (model.startsWith(entry[0])) {
        return Platform.environment[entry[1]] ?? getDefaultVertexRegion();
      }
    }
  }
  return getDefaultVertexRegion();
}

// ---------------------------------------------------------------------------
// envValidation.ts
// ---------------------------------------------------------------------------

/// Validation status for a bounded integer env var.
enum EnvVarValidationStatus { valid, capped, invalid }

/// Result of validating a bounded integer env var.
class EnvVarValidationResult {
  const EnvVarValidationResult({
    required this.effective,
    required this.status,
    this.message,
  });

  final int effective;
  final EnvVarValidationStatus status;
  final String? message;
}

/// Validate and clamp an integer env var within [1 .. upperLimit].
/// Returns the default when the value is absent or non-positive.
EnvVarValidationResult validateBoundedIntEnvVar({
  required String name,
  required String? value,
  required int defaultValue,
  required int upperLimit,
}) {
  if (value == null || value.isEmpty) {
    return EnvVarValidationResult(
      effective: defaultValue,
      status: EnvVarValidationStatus.valid,
    );
  }
  final parsed = int.tryParse(value);
  if (parsed == null || parsed <= 0) {
    final msg = 'Invalid value "$value" (using default: $defaultValue)';
    return EnvVarValidationResult(
      effective: defaultValue,
      status: EnvVarValidationStatus.invalid,
      message: msg,
    );
  }
  if (parsed > upperLimit) {
    final msg = 'Capped from $parsed to $upperLimit';
    return EnvVarValidationResult(
      effective: upperLimit,
      status: EnvVarValidationStatus.capped,
      message: msg,
    );
  }
  return EnvVarValidationResult(
    effective: parsed,
    status: EnvVarValidationStatus.valid,
  );
}

// ---------------------------------------------------------------------------
// env.ts  --  immutable environment detection
// ---------------------------------------------------------------------------

/// Well-known JetBrains IDE identifiers.
const jetbrainsIdes = <String>[
  'pycharm',
  'intellij',
  'webstorm',
  'phpstorm',
  'rubymine',
  'clion',
  'goland',
  'rider',
  'datagrip',
  'appcode',
  'dataspell',
  'aqua',
  'gateway',
  'fleet',
  'jetbrains',
  'androidstudio',
];

/// Detect the terminal / editor hosting the CLI.
String? detectTerminal() {
  final env = Platform.environment;

  if (env['CURSOR_TRACE_ID'] != null) return 'cursor';
  final askpass = env['VSCODE_GIT_ASKPASS_MAIN'];
  if (askpass != null) {
    if (askpass.contains('cursor')) return 'cursor';
    if (askpass.contains('windsurf')) return 'windsurf';
    if (askpass.contains('antigravity')) return 'antigravity';
  }

  final bundleId = env['__CFBundleIdentifier']?.toLowerCase();
  if (bundleId != null) {
    if (bundleId.contains('vscodium')) return 'codium';
    if (bundleId.contains('windsurf')) return 'windsurf';
    if (bundleId.contains('com.google.android.studio')) return 'androidstudio';
    for (final ide in jetbrainsIdes) {
      if (bundleId.contains(ide)) return ide;
    }
  }

  if (env['VisualStudioVersion'] != null) return 'visualstudio';

  if (env['TERMINAL_EMULATOR'] == 'JetBrains-JediTerm') {
    return 'pycharm';
  }

  if (env['TERM'] == 'xterm-ghostty') return 'ghostty';
  if (env['TERM'] != null && env['TERM']!.contains('kitty')) return 'kitty';

  if (env['TERM_PROGRAM'] != null) return env['TERM_PROGRAM'];

  if (env['TMUX'] != null) return 'tmux';
  if (env['STY'] != null) return 'screen';

  if (env['KONSOLE_VERSION'] != null) return 'konsole';
  if (env['GNOME_TERMINAL_SERVICE'] != null) return 'gnome-terminal';
  if (env['XTERM_VERSION'] != null) return 'xterm';
  if (env['VTE_VERSION'] != null) return 'vte-based';
  if (env['TERMINATOR_UUID'] != null) return 'terminator';
  if (env['KITTY_WINDOW_ID'] != null) return 'kitty';
  if (env['ALACRITTY_LOG'] != null) return 'alacritty';
  if (env['TILIX_ID'] != null) return 'tilix';

  if (env['WT_SESSION'] != null) return 'windows-terminal';
  if (env['SESSIONNAME'] != null && env['TERM'] == 'cygwin') return 'cygwin';
  if (env['MSYSTEM'] != null) return env['MSYSTEM']!.toLowerCase();
  if (env['ConEmuANSI'] != null ||
      env['ConEmuPID'] != null ||
      env['ConEmuTask'] != null) {
    return 'conemu';
  }

  if (env['WSL_DISTRO_NAME'] != null) return 'wsl-${env["WSL_DISTRO_NAME"]}';

  if (_isSSHSession()) return 'ssh-session';

  if (env['TERM'] != null) {
    final term = env['TERM']!;
    if (term.contains('alacritty')) return 'alacritty';
    if (term.contains('rxvt')) return 'rxvt';
    if (term.contains('termite')) return 'termite';
    return term;
  }

  if (!stdout.hasTerminal) return 'non-interactive';

  return null;
}

bool _isSSHSession() {
  final env = Platform.environment;
  return env['SSH_CONNECTION'] != null ||
      env['SSH_CLIENT'] != null ||
      env['SSH_TTY'] != null;
}

/// Checks if we're running via Conductor.
bool isConductor() {
  return Platform.environment['__CFBundleIdentifier'] == 'com.conductor.app';
}

/// Detects the deployment environment/platform.
String? _deploymentEnvCache;

String detectDeploymentEnvironment() {
  if (_deploymentEnvCache != null) return _deploymentEnvCache!;
  _deploymentEnvCache = _detectDeploymentEnvironmentImpl();
  return _deploymentEnvCache!;
}

String _detectDeploymentEnvironmentImpl() {
  final env = Platform.environment;

  // Cloud development environments
  if (isEnvTruthy(env['CODESPACES'])) return 'codespaces';
  if (env['GITPOD_WORKSPACE_ID'] != null) return 'gitpod';
  if (env['REPL_ID'] != null || env['REPL_SLUG'] != null) return 'replit';
  if (env['PROJECT_DOMAIN'] != null) return 'glitch';

  // Cloud platforms
  if (isEnvTruthy(env['VERCEL'])) return 'vercel';
  if (env['RAILWAY_ENVIRONMENT_NAME'] != null ||
      env['RAILWAY_SERVICE_NAME'] != null) {
    return 'railway';
  }
  if (isEnvTruthy(env['RENDER'])) return 'render';
  if (isEnvTruthy(env['NETLIFY'])) return 'netlify';
  if (env['DYNO'] != null) return 'heroku';
  if (env['FLY_APP_NAME'] != null || env['FLY_MACHINE_ID'] != null) {
    return 'fly.io';
  }
  if (isEnvTruthy(env['CF_PAGES'])) return 'cloudflare-pages';
  if (env['DENO_DEPLOYMENT_ID'] != null) return 'deno-deploy';
  if (env['AWS_LAMBDA_FUNCTION_NAME'] != null) return 'aws-lambda';
  if (env['AWS_EXECUTION_ENV'] == 'AWS_ECS_FARGATE') return 'aws-fargate';
  if (env['AWS_EXECUTION_ENV'] == 'AWS_ECS_EC2') return 'aws-ecs';

  // EC2 via hypervisor UUID
  try {
    final uuid = File(
      '/sys/hypervisor/uuid',
    ).readAsStringSync().trim().toLowerCase();
    if (uuid.startsWith('ec2')) return 'aws-ec2';
  } catch (_) {}

  if (env['K_SERVICE'] != null) return 'gcp-cloud-run';
  if (env['GOOGLE_CLOUD_PROJECT'] != null) return 'gcp';
  if (env['WEBSITE_SITE_NAME'] != null || env['WEBSITE_SKU'] != null) {
    return 'azure-app-service';
  }
  if (env['AZURE_FUNCTIONS_ENVIRONMENT'] != null) return 'azure-functions';
  if (env['APP_URL'] != null &&
      env['APP_URL']!.contains('ondigitalocean.app')) {
    return 'digitalocean-app-platform';
  }
  if (env['SPACE_CREATOR_USER_ID'] != null) return 'huggingface-spaces';

  // CI/CD
  if (isEnvTruthy(env['GITHUB_ACTIONS'])) return 'github-actions';
  if (isEnvTruthy(env['GITLAB_CI'])) return 'gitlab-ci';
  if (env['CIRCLECI'] != null) return 'circleci';
  if (env['BUILDKITE'] != null) return 'buildkite';
  if (isEnvTruthy(env['CI'])) return 'ci';

  // Container orchestration
  if (env['KUBERNETES_SERVICE_HOST'] != null) return 'kubernetes';
  try {
    if (File('/.dockerenv').existsSync()) return 'docker';
  } catch (_) {}

  // Platform-specific fallback
  final platform = NeomagePlatform.detect();
  if (platform == NeomagePlatform.darwin) return 'unknown-darwin';
  if (platform == NeomagePlatform.linux) return 'unknown-linux';
  if (platform == NeomagePlatform.win32) return 'unknown-win32';

  return 'unknown';
}

/// Returns the host platform for analytics reporting.
NeomagePlatform getHostPlatformForAnalytics() {
  final override = Platform.environment['MAGE_HOST_PLATFORM'];
  switch (override) {
    case 'win32':
      return NeomagePlatform.win32;
    case 'darwin':
      return NeomagePlatform.darwin;
    case 'linux':
      return NeomagePlatform.linux;
    default:
      return NeomagePlatform.detect();
  }
}

// ---------------------------------------------------------------------------
// envDynamic.ts  --  dynamic env detection (Docker, WSL, musl, JetBrains)
// ---------------------------------------------------------------------------

/// Check if running inside a Docker container (Linux only).
Future<bool> getIsDocker() async {
  if (!Platform.isLinux) return false;
  return File('/.dockerenv').exists();
}

/// Check if running inside a Bubblewrap sandbox.
bool getIsBubblewrapSandbox() {
  return Platform.isLinux &&
      isEnvTruthy(Platform.environment['MAGE_BUBBLEWRAP']);
}

/// Checks if running in WSL.
bool? _wslCache;

bool isWslEnvironment() {
  if (_wslCache != null) return _wslCache!;
  try {
    _wslCache = File('/proc/sys/fs/binfmt_misc/WSLInterop').existsSync();
  } catch (_) {
    _wslCache = false;
  }
  return _wslCache!;
}

/// Checks if the npm executable is from the Windows filesystem in WSL.
bool isNpmFromWindowsPath() {
  if (!isWslEnvironment()) return false;
  try {
    final result = Process.runSync('which', ['npm']);
    final path = (result.stdout as String).trim();
    return path.startsWith('/mnt/c/');
  } catch (_) {
    return false;
  }
}

/// Checks whether the system uses musl libc instead of glibc.
bool isMuslEnvironment() {
  if (!Platform.isLinux) return false;
  final arch = _dartArch();
  final muslArch = arch == 'x64' ? 'x86_64' : 'aarch64';
  return File('/lib/libc.musl-$muslArch.so.1').existsSync();
}

String _dartArch() {
  // Dart does not expose process.arch; heuristic based on pointer size.
  // On 64-bit systems we assume x64 unless overridden.
  return Platform.environment['HOSTTYPE'] ?? 'x64';
}

/// Async JetBrains IDE detection from parent processes.
String? _jetBrainsIDECache;
bool _jetBrainsDetected = false;

Future<String?> detectJetBrainsIDEFromParentProcessAsync() async {
  if (_jetBrainsDetected) return _jetBrainsIDECache;
  if (Platform.isMacOS) {
    _jetBrainsDetected = true;
    return null;
  }

  try {
    final result = await Process.run('ps', ['-o', 'command=', '-p', '$pid']);
    final commands = (result.stdout as String).split('\n');
    for (final command in commands) {
      final lower = command.toLowerCase();
      for (final ide in jetbrainsIdes) {
        if (lower.contains(ide)) {
          _jetBrainsIDECache = ide;
          _jetBrainsDetected = true;
          return ide;
        }
      }
    }
  } catch (_) {}

  _jetBrainsDetected = true;
  return null;
}

/// Async terminal detection with JetBrains awareness.
Future<String?> getTerminalWithJetBrainsDetectionAsync() async {
  if (Platform.environment['TERMINAL_EMULATOR'] == 'JetBrains-JediTerm') {
    if (!Platform.isMacOS) {
      final specificIDE = await detectJetBrainsIDEFromParentProcessAsync();
      return specificIDE ?? 'pycharm';
    }
  }
  return detectTerminal();
}

/// Synchronous version using cache or falling back to detectTerminal().
String? getTerminalWithJetBrainsDetection() {
  if (Platform.environment['TERMINAL_EMULATOR'] == 'JetBrains-JediTerm') {
    if (!Platform.isMacOS) {
      if (_jetBrainsDetected) return _jetBrainsIDECache ?? 'pycharm';
      return 'pycharm';
    }
  }
  return detectTerminal();
}

/// Initialise JetBrains IDE detection early.
Future<void> initJetBrainsDetection() async {
  if (Platform.environment['TERMINAL_EMULATOR'] == 'JetBrains-JediTerm') {
    await detectJetBrainsIDEFromParentProcessAsync();
  }
}

/// Check internet access (best-effort, 1 s timeout).
Future<bool> hasInternetAccess() async {
  try {
    final result = await InternetAddress.lookup(
      '1.1.1.1',
    ).timeout(const Duration(seconds: 1));
    return result.isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Detect available package managers.
Future<List<String>> detectPackageManagers() async {
  final managers = <String>[];
  for (final name in ['npm', 'yarn', 'pnpm']) {
    if (await _isCommandAvailable(name)) managers.add(name);
  }
  return managers;
}

/// Detect available runtimes.
Future<List<String>> detectRuntimes() async {
  final runtimes = <String>[];
  for (final name in ['bun', 'deno', 'node']) {
    if (await _isCommandAvailable(name)) runtimes.add(name);
  }
  return runtimes;
}

Future<bool> _isCommandAvailable(String command) async {
  try {
    final result = await Process.run('which', [command]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// managedEnvConstants.ts
// ---------------------------------------------------------------------------

/// Environment variables that control inference routing.
const _providerManagedEnvVars = <String>{
  'MAGE_PROVIDER_MANAGED_BY_HOST',
  'MAGE_USE_BEDROCK',
  'MAGE_USE_VERTEX',
  'MAGE_USE_FOUNDRY',
  'ANTHROPIC_BASE_URL',
  'ANTHROPIC_BEDROCK_BASE_URL',
  'ANTHROPIC_VERTEX_BASE_URL',
  'ANTHROPIC_FOUNDRY_BASE_URL',
  'ANTHROPIC_FOUNDRY_RESOURCE',
  'ANTHROPIC_VERTEX_PROJECT_ID',
  'CLOUD_ML_REGION',
  'ANTHROPIC_API_KEY',
  'ANTHROPIC_AUTH_TOKEN',
  'MAGE_OAUTH_TOKEN',
  'AWS_BEARER_TOKEN_BEDROCK',
  'ANTHROPIC_FOUNDRY_API_KEY',
  'MAGE_SKIP_BEDROCK_AUTH',
  'MAGE_SKIP_VERTEX_AUTH',
  'MAGE_SKIP_FOUNDRY_AUTH',
  'ANTHROPIC_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_SMALL_FAST_MODEL',
  'ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION',
  'MAGE_SUBAGENT_MODEL',
};

const _providerManagedEnvPrefixes = <String>['VERTEX_REGION_CLAUDE_'];

/// Check if a key is a provider-managed env var.
bool isProviderManagedEnvVar(String key) {
  final upper = key.toUpperCase();
  if (_providerManagedEnvVars.contains(upper)) return true;
  for (final prefix in _providerManagedEnvPrefixes) {
    if (upper.startsWith(prefix)) return true;
  }
  return false;
}

/// Dangerous shell settings that can execute arbitrary shell code.
const dangerousShellSettings = <String>[
  'apiKeyHelper',
  'awsAuthRefresh',
  'awsCredentialExport',
  'gcpAuthRefresh',
  'otelHeadersHelper',
  'statusLine',
];

/// Safe environment variables that can be applied before the trust dialog.
const safeEnvVars = <String>{
  'ANTHROPIC_CUSTOM_HEADERS',
  'ANTHROPIC_CUSTOM_MODEL_OPTION',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION',
  'ANTHROPIC_CUSTOM_MODEL_OPTION_NAME',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
  'ANTHROPIC_DEFAULT_HAIKU_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_DEFAULT_OPUS_MODEL',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
  'ANTHROPIC_DEFAULT_OPUS_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_DEFAULT_SONNET_MODEL',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
  'ANTHROPIC_DEFAULT_SONNET_MODEL_SUPPORTED_CAPABILITIES',
  'ANTHROPIC_FOUNDRY_API_KEY',
  'ANTHROPIC_MODEL',
  'ANTHROPIC_SMALL_FAST_MODEL_AWS_REGION',
  'ANTHROPIC_SMALL_FAST_MODEL',
  'AWS_DEFAULT_REGION',
  'AWS_PROFILE',
  'AWS_REGION',
  'BASH_DEFAULT_TIMEOUT_MS',
  'BASH_MAX_OUTPUT_LENGTH',
  'BASH_MAX_TIMEOUT_MS',
  'MAGE_BASH_MAINTAIN_PROJECT_WORKING_DIR',
  'MAGE_API_KEY_HELPER_TTL_MS',
  'MAGE_DISABLE_EXPERIMENTAL_BETAS',
  'MAGE_DISABLE_NONESSENTIAL_TRAFFIC',
  'MAGE_DISABLE_TERMINAL_TITLE',
  'MAGE_ENABLE_TELEMETRY',
  'MAGE_EXPERIMENTAL_AGENT_TEAMS',
  'MAGE_IDE_SKIP_AUTO_INSTALL',
  'MAGE_MAX_OUTPUT_TOKENS',
  'MAGE_SKIP_BEDROCK_AUTH',
  'MAGE_SKIP_FOUNDRY_AUTH',
  'MAGE_SKIP_VERTEX_AUTH',
  'MAGE_SUBAGENT_MODEL',
  'MAGE_USE_BEDROCK',
  'MAGE_USE_FOUNDRY',
  'MAGE_USE_VERTEX',
  'DISABLE_AUTOUPDATER',
  'DISABLE_BUG_COMMAND',
  'DISABLE_COST_WARNINGS',
  'DISABLE_ERROR_REPORTING',
  'DISABLE_FEEDBACK_COMMAND',
  'DISABLE_TELEMETRY',
  'ENABLE_TOOL_SEARCH',
  'MAX_MCP_OUTPUT_TOKENS',
  'MAX_THINKING_TOKENS',
  'MCP_TIMEOUT',
  'MCP_TOOL_TIMEOUT',
  'OTEL_EXPORTER_OTLP_HEADERS',
  'OTEL_EXPORTER_OTLP_LOGS_HEADERS',
  'OTEL_EXPORTER_OTLP_LOGS_PROTOCOL',
  'OTEL_EXPORTER_OTLP_METRICS_CLIENT_CERTIFICATE',
  'OTEL_EXPORTER_OTLP_METRICS_CLIENT_KEY',
  'OTEL_EXPORTER_OTLP_METRICS_HEADERS',
  'OTEL_EXPORTER_OTLP_METRICS_PROTOCOL',
  'OTEL_EXPORTER_OTLP_PROTOCOL',
  'OTEL_EXPORTER_OTLP_TRACES_HEADERS',
  'OTEL_LOG_TOOL_DETAILS',
  'OTEL_LOG_USER_PROMPTS',
  'OTEL_LOGS_EXPORT_INTERVAL',
  'OTEL_LOGS_EXPORTER',
  'OTEL_METRIC_EXPORT_INTERVAL',
  'OTEL_METRICS_EXPORTER',
  'OTEL_METRICS_INCLUDE_ACCOUNT_UUID',
  'OTEL_METRICS_INCLUDE_SESSION_ID',
  'OTEL_METRICS_INCLUDE_VERSION',
  'OTEL_RESOURCE_ATTRIBUTES',
  'USE_BUILTIN_RIPGREP',
  'VERTEX_REGION_CLAUDE_3_5_HAIKU',
  'VERTEX_REGION_CLAUDE_3_5_SONNET',
  'VERTEX_REGION_CLAUDE_3_7_SONNET',
  'VERTEX_REGION_CLAUDE_4_0_OPUS',
  'VERTEX_REGION_CLAUDE_4_0_SONNET',
  'VERTEX_REGION_CLAUDE_4_1_OPUS',
  'VERTEX_REGION_CLAUDE_4_5_SONNET',
  'VERTEX_REGION_CLAUDE_4_6_SONNET',
  'VERTEX_REGION_CLAUDE_HAIKU_4_5',
};

// ---------------------------------------------------------------------------
// managedEnv.ts  --  apply settings env to the process
// ---------------------------------------------------------------------------

/// Strip SSH tunnel auth variables when ANTHROPIC_UNIX_SOCKET is set.
Map<String, String> _withoutSSHTunnelVars(Map<String, String>? env) {
  if (env == null || Platform.environment['ANTHROPIC_UNIX_SOCKET'] == null) {
    return env ?? {};
  }
  final copy = Map<String, String>.from(env);
  for (final key in [
    'ANTHROPIC_UNIX_SOCKET',
    'ANTHROPIC_BASE_URL',
    'ANTHROPIC_API_KEY',
    'ANTHROPIC_AUTH_TOKEN',
    'MAGE_OAUTH_TOKEN',
  ]) {
    copy.remove(key);
  }
  return copy;
}

/// Strip provider-managed vars when MAGE_PROVIDER_MANAGED_BY_HOST is set.
Map<String, String> _withoutHostManagedProviderVars(Map<String, String>? env) {
  if (env == null) return {};
  if (!isEnvTruthy(Platform.environment['MAGE_PROVIDER_MANAGED_BY_HOST'])) {
    return env;
  }
  final out = <String, String>{};
  for (final entry in env.entries) {
    if (!isProviderManagedEnvVar(entry.key)) {
      out[entry.key] = entry.value;
    }
  }
  return out;
}

/// Snapshot of env keys present before any settings.env is applied (for CCD).
Set<String>? _ccdSpawnEnvKeys;
bool _ccdSpawnEnvKeysInitialised = false;

Map<String, String> _withoutCcdSpawnEnvKeys(Map<String, String>? env) {
  if (env == null || _ccdSpawnEnvKeys == null) return env ?? {};
  final out = <String, String>{};
  for (final entry in env.entries) {
    if (!_ccdSpawnEnvKeys!.contains(entry.key)) {
      out[entry.key] = entry.value;
    }
  }
  return out;
}

/// Compose the strip filters applied to every settings-sourced env object.
Map<String, String> filterSettingsEnv(Map<String, String>? env) {
  return _withoutCcdSpawnEnvKeys(
    _withoutHostManagedProviderVars(_withoutSSHTunnelVars(env)),
  );
}

/// Trusted setting sources whose env vars can be applied before trust dialog.
const _trustedSettingSources = [
  'userSettings',
  'flagSettings',
  'policySettings',
];

/// Apply environment variables from trusted sources.
///
/// In the Dart port this is a simplified version that demonstrates the flow.
/// Callers should provide the settings retrieval callbacks.
void applySafeConfigEnvironmentVariables({
  required Map<String, String>? Function() getGlobalConfigEnv,
  required Map<String, String>? Function(String source) getSettingsForSourceEnv,
  required Map<String, String>? Function() getAllSettingsEnv,
  required bool Function(String source) isSettingSourceEnabled,
}) {
  // Capture CCD spawn-env keys before any settings.env is applied (once).
  if (!_ccdSpawnEnvKeysInitialised) {
    _ccdSpawnEnvKeysInitialised = true;
    if (Platform.environment['MAGE_ENTRYPOINT'] == 'claude-desktop') {
      _ccdSpawnEnvKeys = Platform.environment.keys.toSet();
    }
  }

  // Global config
  final globalEnv = filterSettingsEnv(getGlobalConfigEnv());
  globalEnv.forEach((key, value) {
    Platform.environment[key] = value;
  });

  // Trusted sources (except policy)
  for (final source in _trustedSettingSources) {
    if (source == 'policySettings') continue;
    if (!isSettingSourceEnabled(source)) continue;
    final env = filterSettingsEnv(getSettingsForSourceEnv(source));
    env.forEach((key, value) {
      Platform.environment[key] = value;
    });
  }

  // Policy settings last
  final policyEnv = filterSettingsEnv(
    getSettingsForSourceEnv('policySettings'),
  );
  policyEnv.forEach((key, value) {
    Platform.environment[key] = value;
  });

  // Safe vars from merged settings
  final settingsEnv = filterSettingsEnv(getAllSettingsEnv());
  for (final entry in settingsEnv.entries) {
    if (safeEnvVars.contains(entry.key.toUpperCase())) {
      Platform.environment[entry.key] = entry.value;
    }
  }
}

/// Apply ALL environment variables after trust is established.
void applyConfigEnvironmentVariables({
  required Map<String, String>? Function() getGlobalConfigEnv,
  required Map<String, String>? Function() getAllSettingsEnv,
  void Function()? clearCACertsCache,
  void Function()? clearMTLSCache,
  void Function()? clearProxyCache,
  void Function()? configureGlobalAgents,
}) {
  final globalEnv = filterSettingsEnv(getGlobalConfigEnv());
  globalEnv.forEach((key, value) {
    Platform.environment[key] = value;
  });

  final settingsEnv = filterSettingsEnv(getAllSettingsEnv());
  settingsEnv.forEach((key, value) {
    Platform.environment[key] = value;
  });

  // Clear caches so agents are rebuilt with the new env vars
  clearCACertsCache?.call();
  clearMTLSCache?.call();
  clearProxyCache?.call();

  // Reconfigure proxy/mTLS agents to pick up any proxy env vars from settings
  configureGlobalAgents?.call();
}

// ---------------------------------------------------------------------------
// Global config file path  (env.ts getGlobalNeomageFile)
// ---------------------------------------------------------------------------

String? _globalNeomageFileCache;

/// Returns the path to the global neomage config JSON file.
String getGlobalNeomageFile({String fileSuffix = ''}) {
  if (_globalNeomageFileCache != null) return _globalNeomageFileCache!;

  // Legacy fallback
  final legacyPath = p.join(getNeomageConfigHomeDir(), '.config.json');
  if (File(legacyPath).existsSync()) {
    _globalNeomageFileCache = legacyPath;
    return legacyPath;
  }

  final filename = '.neomage$fileSuffix.json';
  _globalNeomageFileCache = p.join(
    Platform.environment['MAGE_CONFIG_DIR'] ?? _homedir(),
    filename,
  );
  return _globalNeomageFileCache!;
}

// ---------------------------------------------------------------------------
// Consolidated environment singleton
// ---------------------------------------------------------------------------

/// Immutable snapshot of the environment at startup.
class EnvInfo {
  EnvInfo._();

  static final EnvInfo instance = EnvInfo._();

  final bool isCI = isEnvTruthy(Platform.environment['CI']);
  final NeomagePlatform platform = NeomagePlatform.detect();
  final String? terminal = detectTerminal();

  bool get isSSH => _isSSHSession();

  Future<bool> get internetAccess => hasInternetAccess();
  Future<List<String>> get packageManagers => detectPackageManagers();
  Future<List<String>> get runtimes => detectRuntimes();
}

// ---------------------------------------------------------------------------
// private helpers
// ---------------------------------------------------------------------------

String _homedir() {
  if (Platform.isWindows) {
    return Platform.environment['USERPROFILE'] ?? r'C:\Users\Default';
  }
  return Platform.environment['HOME'] ?? '/';
}
