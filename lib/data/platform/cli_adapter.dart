// CLI adapter — port of openclaude CLI entrypoint.
// Argument parsing, headless mode, and CLI compatibility layer.

import 'dart:io';

/// Parsed CLI arguments.
class CliArgs {
  final String? prompt;
  final String? model;
  final String? apiKey;
  final String? apiEndpoint;
  final bool headless;
  final bool verbose;
  final bool version;
  final bool help;
  final bool noColor;
  final String? sessionId;
  final String? resumeSession;
  final String? workingDir;
  final List<String> files;
  final Map<String, String> env;
  final bool stdinPipe;
  final String? outputFormat;
  final int? maxTokens;
  final bool dangerouslySkipPermissions;

  const CliArgs({
    this.prompt,
    this.model,
    this.apiKey,
    this.apiEndpoint,
    this.headless = false,
    this.verbose = false,
    this.version = false,
    this.help = false,
    this.noColor = false,
    this.sessionId,
    this.resumeSession,
    this.workingDir,
    this.files = const [],
    this.env = const {},
    this.stdinPipe = false,
    this.outputFormat,
    this.maxTokens,
    this.dangerouslySkipPermissions = false,
  });
}

/// Parse CLI arguments.
CliArgs parseCliArgs(List<String> args) {
  String? prompt;
  String? model;
  String? apiKey;
  String? apiEndpoint;
  bool headless = false;
  bool verbose = false;
  bool version = false;
  bool help = false;
  bool noColor = false;
  String? sessionId;
  String? resumeSession;
  String? workingDir;
  final files = <String>[];
  final env = <String, String>{};
  String? outputFormat;
  int? maxTokens;
  bool dangerouslySkipPermissions = false;

  var i = 0;
  final positional = <String>[];

  while (i < args.length) {
    final arg = args[i];

    switch (arg) {
      case '-p' || '--prompt':
        prompt = _nextArg(args, i, 'prompt');
        i += 2;
      case '-m' || '--model':
        model = _nextArg(args, i, 'model');
        i += 2;
      case '-k' || '--api-key':
        apiKey = _nextArg(args, i, 'api-key');
        i += 2;
      case '--api-endpoint':
        apiEndpoint = _nextArg(args, i, 'api-endpoint');
        i += 2;
      case '--headless':
        headless = true;
        i++;
      case '-v' || '--verbose':
        verbose = true;
        i++;
      case '--version':
        version = true;
        i++;
      case '-h' || '--help':
        help = true;
        i++;
      case '--no-color':
        noColor = true;
        i++;
      case '-s' || '--session':
        sessionId = _nextArg(args, i, 'session');
        i += 2;
      case '-r' || '--resume':
        resumeSession = _nextArg(args, i, 'resume');
        i += 2;
      case '-C' || '--directory':
        workingDir = _nextArg(args, i, 'directory');
        i += 2;
      case '-f' || '--file':
        files.add(_nextArg(args, i, 'file'));
        i += 2;
      case '-e' || '--env':
        final kv = _nextArg(args, i, 'env');
        final eq = kv.indexOf('=');
        if (eq > 0) {
          env[kv.substring(0, eq)] = kv.substring(eq + 1);
        }
        i += 2;
      case '-o' || '--output-format':
        outputFormat = _nextArg(args, i, 'output-format');
        i += 2;
      case '--max-tokens':
        maxTokens = int.tryParse(_nextArg(args, i, 'max-tokens'));
        i += 2;
      case '--dangerously-skip-permissions':
        dangerouslySkipPermissions = true;
        i++;
      default:
        if (arg.startsWith('-')) {
          stderr.writeln('Unknown option: $arg');
          i++;
        } else {
          positional.add(arg);
          i++;
        }
    }
  }

  // First positional is the prompt
  if (positional.isNotEmpty && prompt == null) {
    prompt = positional.join(' ');
  }

  // Detect piped stdin
  final stdinPipe = !stdin.hasTerminal;

  return CliArgs(
    prompt: prompt,
    model: model,
    apiKey: apiKey,
    apiEndpoint: apiEndpoint,
    headless: headless,
    verbose: verbose,
    version: version,
    help: help,
    noColor: noColor,
    sessionId: sessionId,
    resumeSession: resumeSession,
    workingDir: workingDir,
    files: files,
    env: env,
    stdinPipe: stdinPipe,
    outputFormat: outputFormat,
    maxTokens: maxTokens,
    dangerouslySkipPermissions: dangerouslySkipPermissions,
  );
}

String _nextArg(List<String> args, int i, String name) {
  if (i + 1 >= args.length) {
    throw ArgumentError('--$name requires a value');
  }
  return args[i + 1];
}

/// Print help text.
void printHelp() {
  stdout.writeln('''
Flutter Claw — AI coding assistant

Usage: claw [options] [prompt]

Options:
  -p, --prompt <text>         Initial prompt to send
  -m, --model <name>          Model to use (default: auto-detect)
  -k, --api-key <key>         API key (or set ANTHROPIC_API_KEY)
  --api-endpoint <url>        API endpoint URL
  --headless                  Run without UI (CI/CD mode)
  -v, --verbose               Verbose output
  --version                   Show version
  -h, --help                  Show this help
  --no-color                  Disable colored output
  -s, --session <id>          Session ID
  -r, --resume <id>           Resume a previous session
  -C, --directory <path>      Working directory
  -f, --file <path>           Include file (can be repeated)
  -e, --env <KEY=VALUE>       Set environment variable
  -o, --output-format <fmt>   Output format: text, json, stream
  --max-tokens <n>            Maximum response tokens

Environment Variables:
  ANTHROPIC_API_KEY            API key for Anthropic
  OPENAI_API_KEY               API key for OpenAI-compatible
  CLAW_MODEL                   Default model name
  CLAW_API_ENDPOINT            Default API endpoint
  CLAW_CLI_MODE                Force CLI mode
  CLAW_NO_COLOR                Disable colors

Examples:
  claw "fix the bug in main.dart"
  claw -m sonnet -p "refactor this function"
  echo "explain this code" | claw
  claw --headless -p "run tests and fix failures"
''');
}

/// Output format for headless/pipe mode.
enum CliOutputFormat { text, json, stream }

CliOutputFormat parseOutputFormat(String? format) => switch (format) {
      'json' => CliOutputFormat.json,
      'stream' => CliOutputFormat.stream,
      _ => CliOutputFormat.text,
    };
