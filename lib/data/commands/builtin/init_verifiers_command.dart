// /init-verifiers command — creates verifier skills for automated verification.
// Faithful port of neom_claw/src/commands/init-verifiers.ts (262 TS LOC).
//
// This is a prompt command that guides the LLM through a multi-phase process:
//   Phase 1: Auto-detection of project type, stack, and existing tools
//   Phase 2: Verification tool setup (Playwright, Tmux, HTTP)
//   Phase 3: Interactive Q&A for verifier configuration
//   Phase 4: Generate verifier skill files
//   Phase 5: Confirm creation and explain discovery
//
// Supports three verifier types:
//   - Playwright (web UI testing)
//   - CLI (terminal/Tmux testing)
//   - API (HTTP endpoint testing)
//
// Verifier skills are written to .neomclaw/skills/<verifier-name>/SKILL.md and
// are automatically discovered by the Verify agent via "verifier" in the
// folder name.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Constants — allowed tools by verifier type
// ============================================================================

/// Allowed tools for Playwright-based web UI verifiers.
const List<String> playwrightAllowedTools = [
  'Bash(npm:*)',
  'Bash(yarn:*)',
  'Bash(pnpm:*)',
  'Bash(bun:*)',
  'mcp__playwright__*',
  'Read',
  'Glob',
  'Grep',
];

/// Allowed tools for CLI/terminal verifiers using Tmux.
const List<String> cliAllowedTools = [
  'Tmux',
  'Bash(asciinema:*)',
  'Read',
  'Glob',
  'Grep',
];

/// Allowed tools for HTTP API verifiers.
const List<String> apiAllowedTools = [
  'Bash(curl:*)',
  'Bash(http:*)',
  'Bash(npm:*)',
  'Bash(yarn:*)',
  'Read',
  'Glob',
  'Grep',
];

// ============================================================================
// Verifier type detection helpers
// ============================================================================

/// Supported verifier types.
enum VerifierType {
  /// Web app verified with Playwright or browser automation.
  playwright,

  /// CLI tool verified with Tmux terminal sessions.
  cli,

  /// API service verified with HTTP requests.
  api,
}

/// Get a human-readable label for a verifier type.
String verifierTypeLabel(VerifierType type) {
  switch (type) {
    case VerifierType.playwright:
      return 'Playwright (Web UI)';
    case VerifierType.cli:
      return 'CLI (Terminal)';
    case VerifierType.api:
      return 'API (HTTP)';
  }
}

/// Get the default verifier name for a type (single-project format).
String defaultVerifierName(VerifierType type) {
  switch (type) {
    case VerifierType.playwright:
      return 'verifier-playwright';
    case VerifierType.cli:
      return 'verifier-cli';
    case VerifierType.api:
      return 'verifier-api';
  }
}

/// Get the default verifier name for a type in a multi-project repo.
String multiProjectVerifierName(String projectName, VerifierType type) {
  switch (type) {
    case VerifierType.playwright:
      return 'verifier-$projectName-playwright';
    case VerifierType.cli:
      return 'verifier-$projectName-cli';
    case VerifierType.api:
      return 'verifier-$projectName-api';
  }
}

/// Get allowed tools YAML block for a verifier type.
String allowedToolsYaml(VerifierType type) {
  final tools = switch (type) {
    VerifierType.playwright => playwrightAllowedTools,
    VerifierType.cli => cliAllowedTools,
    VerifierType.api => apiAllowedTools,
  };
  return tools.map((t) => '  - $t').join('\n');
}

// ============================================================================
// Skill template generation
// ============================================================================

/// Generate a SKILL.md template for a verifier.
String generateVerifierSkillTemplate({
  required String verifierName,
  required String description,
  required VerifierType type,
  required String projectContext,
  required String setupInstructions,
  String? authenticationSection,
}) {
  final buf = StringBuffer();

  // Frontmatter
  buf.writeln('---');
  buf.writeln('name: $verifierName');
  buf.writeln('description: $description');
  buf.writeln('allowed-tools:');
  buf.writeln(allowedToolsYaml(type));
  buf.writeln('---');
  buf.writeln();

  // Title
  buf.writeln('# ${_titleCase(verifierName.replaceAll('-', ' '))}');
  buf.writeln();
  buf.writeln(
    'You are a verification executor. You receive a verification plan '
    'and execute it EXACTLY as written.',
  );
  buf.writeln();

  // Project Context
  buf.writeln('## Project Context');
  buf.writeln(projectContext);
  buf.writeln();

  // Setup Instructions
  buf.writeln('## Setup Instructions');
  buf.writeln(setupInstructions);
  buf.writeln();

  // Authentication (optional)
  if (authenticationSection != null && authenticationSection.isNotEmpty) {
    buf.writeln('## Authentication');
    buf.writeln(authenticationSection);
    buf.writeln();
  }

  // Reporting
  buf.writeln('## Reporting');
  buf.writeln();
  buf.writeln(
    'Report PASS or FAIL for each step using the format specified in '
    'the verification plan.',
  );
  buf.writeln();

  // Cleanup
  buf.writeln('## Cleanup');
  buf.writeln();
  buf.writeln('After verification:');
  buf.writeln('1. Stop any dev servers started');
  buf.writeln('2. Close any browser sessions');
  buf.writeln('3. Report final summary');
  buf.writeln();

  // Self-Update
  buf.writeln('## Self-Update');
  buf.writeln();
  buf.writeln(
    'If verification fails because this skill\'s instructions are outdated '
    '(dev server command/port/ready-signal changed, etc.) -- not because the '
    'feature under test is broken -- or if the user corrects you mid-run, use '
    'AskUserQuestion to confirm and then Edit this SKILL.md with a minimal '
    'targeted fix.',
  );

  return buf.toString();
}

/// Title-case a string (capitalize first letter of each word).
String _titleCase(String input) {
  return input
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ============================================================================
// Browser automation tool detection
// ============================================================================

/// Known browser automation MCP server identifiers.
const List<String> knownBrowserAutomationServers = [
  'playwright',
  'chrome-devtools',
  'neom-claw-chrome',
  'browser-use',
  'puppeteer',
];

/// Playwright installation commands by package manager.
const Map<String, String> playwrightInstallCommands = {
  'npm': 'npm install -D @playwright/test && npx playwright install',
  'yarn': 'yarn add -D @playwright/test && yarn playwright install',
  'pnpm': 'pnpm add -D @playwright/test && pnpm exec playwright install',
  'bun': 'bun add -D @playwright/test && bun playwright install',
};

// ============================================================================
// Project type detection patterns
// ============================================================================

/// Manifest file names and associated project types.
const Map<String, String> manifestFiles = {
  'package.json': 'Node.js',
  'Cargo.toml': 'Rust',
  'pyproject.toml': 'Python',
  'go.mod': 'Go',
  'pom.xml': 'Java (Maven)',
  'build.gradle': 'Java (Gradle)',
  'Gemfile': 'Ruby',
  'pubspec.yaml': 'Dart/Flutter',
  'mix.exs': 'Elixir',
  'composer.json': 'PHP',
};

/// Web framework indicators (dependency names -> framework name).
const Map<String, String> webFrameworkIndicators = {
  'react': 'React',
  'next': 'Next.js',
  'vue': 'Vue',
  'nuxt': 'Nuxt',
  'svelte': 'Svelte',
  'angular': 'Angular',
  'gatsby': 'Gatsby',
  'remix': 'Remix',
  'astro': 'Astro',
};

/// API framework indicators (dependency names -> framework name).
const Map<String, String> apiFrameworkIndicators = {
  'express': 'Express',
  'fastify': 'Fastify',
  'koa': 'Koa',
  'hapi': 'Hapi',
  'flask': 'Flask',
  'fastapi': 'FastAPI',
  'django': 'Django',
  'actix-web': 'Actix Web',
  'axum': 'Axum',
  'gin': 'Gin',
  'fiber': 'Fiber',
};

// ============================================================================
// InitVerifiersCommand
// ============================================================================

/// The /init-verifiers command — creates verifier skills for automated
/// verification of code changes.
///
/// This prompt command guides the LLM through a structured multi-phase process
/// to detect project type, set up verification tools, gather configuration
/// through interactive Q&A, and generate SKILL.md files for each verifier.
///
/// Verifier types:
///   - Playwright: web app UI testing with browser automation
///   - CLI: terminal-based testing with Tmux sessions
///   - API: HTTP endpoint testing with curl/httpie
///
/// Skills are created at `.neomclaw/skills/<verifier-name>/SKILL.md` and are
/// automatically discovered by the Verify agent when the folder name contains
/// "verifier" (case-insensitive).
class InitVerifiersCommand extends PromptCommand {
  @override
  String get name => 'init-verifiers';

  @override
  String get description =>
      'Create verifier skill(s) for automated verification of code changes';

  @override
  String get progressMessage =>
      'analyzing your project and creating verifier skills';

  @override
  Set<String> get allowedTools => const {
    'Bash',
    'Read',
    'Glob',
    'Grep',
    'Write',
    'Edit',
    'TodoWrite',
    'AskUserQuestion',
    'Task',
  };

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    return [
      const TextBlock(
        'Use the TodoWrite tool to track your progress through this multi-step task.\n'
        '\n'
        '## Goal\n'
        '\n'
        'Create one or more verifier skills that can be used by the Verify agent to '
        'automatically verify code changes in this project or folder. You may create '
        'multiple verifiers if the project has different verification needs (e.g., both '
        'web UI and API endpoints).\n'
        '\n'
        '**Do NOT create verifiers for unit tests or typechecking.** Those are already '
        'handled by the standard build/test workflow and don\'t need dedicated verifier '
        'skills. Focus on functional verification: web UI (Playwright), CLI (Tmux), and '
        'API (HTTP) verifiers.\n'
        '\n'
        '## Phase 1: Auto-Detection\n'
        '\n'
        'Analyze the project to detect what\'s in different subdirectories. The project '
        'may contain multiple sub-projects or areas that need different verification '
        'approaches (e.g., a web frontend, an API backend, and shared libraries all in '
        'one repo).\n'
        '\n'
        '1. **Scan top-level directories** to identify distinct project areas:\n'
        '   - Look for separate package.json, Cargo.toml, pyproject.toml, go.mod in '
        'subdirectories\n'
        '   - Identify distinct application types in different folders\n'
        '\n'
        '2. **For each area, detect:**\n'
        '\n'
        '   a. **Project type and stack**\n'
        '      - Primary language(s) and frameworks\n'
        '      - Package managers (npm, yarn, pnpm, pip, cargo, etc.)\n'
        '\n'
        '   b. **Application type**\n'
        '      - Web app (React, Next.js, Vue, etc.) -> suggest Playwright-based verifier\n'
        '      - CLI tool -> suggest Tmux-based verifier\n'
        '      - API service (Express, FastAPI, etc.) -> suggest HTTP-based verifier\n'
        '\n'
        '   c. **Existing verification tools**\n'
        '      - Test frameworks (Jest, Vitest, pytest, etc.)\n'
        '      - E2E tools (Playwright, Cypress, etc.)\n'
        '      - Dev server scripts in package.json\n'
        '\n'
        '   d. **Dev server configuration**\n'
        '      - How to start the dev server\n'
        '      - What URL it runs on\n'
        '      - What text indicates it\'s ready\n'
        '\n'
        '3. **Installed verification packages** (for web apps)\n'
        '   - Check if Playwright is installed (look in package.json '
        'dependencies/devDependencies)\n'
        '   - Check MCP configuration (.mcp.json) for browser automation tools:\n'
        '     - Playwright MCP server\n'
        '     - Chrome DevTools MCP server\n'
        '     - NeomClaw Chrome Extension MCP (browser-use via Claude\'s Chrome extension)\n'
        '   - For Python projects, check for playwright, pytest-playwright\n'
        '\n'
        '## Phase 2: Verification Tool Setup\n'
        '\n'
        'Based on what was detected in Phase 1, help the user set up appropriate '
        'verification tools.\n'
        '\n'
        '### For Web Applications\n'
        '\n'
        '1. **If browser automation tools are already installed/configured**, ask the '
        'user which one they want to use:\n'
        '   - Use AskUserQuestion to present the detected options\n'
        '   - Example: "I found Playwright and Chrome DevTools MCP configured. Which '
        'would you like to use for verification?"\n'
        '\n'
        '2. **If NO browser automation tools are detected**, ask if they want to '
        'install/configure one:\n'
        '   - Use AskUserQuestion: "No browser automation tools detected. Would you '
        'like to set one up for UI verification?"\n'
        '   - Options to offer:\n'
        '     - **Playwright** (Recommended) - Full browser automation library, works '
        'headless, great for CI\n'
        '     - **Chrome DevTools MCP** - Uses Chrome DevTools Protocol via MCP\n'
        '     - **NeomClaw Chrome Extension** - Uses the Claude Chrome extension for '
        'browser interaction (requires the extension installed in Chrome)\n'
        '     - **None** - Skip browser automation (will use basic HTTP checks only)\n'
        '\n'
        '3. **If user chooses to install Playwright**, run the appropriate command '
        'based on package manager:\n'
        '   - For npm: `npm install -D @playwright/test && npx playwright install`\n'
        '   - For yarn: `yarn add -D @playwright/test && yarn playwright install`\n'
        '   - For pnpm: `pnpm add -D @playwright/test && pnpm exec playwright install`\n'
        '   - For bun: `bun add -D @playwright/test && bun playwright install`\n'
        '\n'
        '4. **If user chooses Chrome DevTools MCP or NeomClaw Chrome Extension**:\n'
        '   - These require MCP server configuration rather than package installation\n'
        '   - Ask if they want you to add the MCP server configuration to .mcp.json\n'
        '   - For NeomClaw Chrome Extension, inform them they need the extension installed '
        'from the Chrome Web Store\n'
        '\n'
        '5. **MCP Server Setup** (if applicable):\n'
        '   - If user selected an MCP-based option, configure the appropriate entry in '
        '.mcp.json\n'
        '   - Update the verifier skill\'s allowed-tools to use the appropriate mcp__* tools\n'
        '\n'
        '### For CLI Tools\n'
        '\n'
        '1. Check if asciinema is available (run `which asciinema`)\n'
        '2. If not available, inform the user that asciinema can help record verification '
        'sessions but is optional\n'
        '3. Tmux is typically system-installed, just verify it\'s available\n'
        '\n'
        '### For API Services\n'
        '\n'
        '1. Check if HTTP testing tools are available:\n'
        '   - curl (usually system-installed)\n'
        '   - httpie (`http` command)\n'
        '2. No installation typically needed\n'
        '\n'
        '## Phase 3: Interactive Q&A\n'
        '\n'
        'Based on the areas detected in Phase 1, you may need to create multiple '
        'verifiers. For each distinct area, use the AskUserQuestion tool to confirm:\n'
        '\n'
        '1. **Verifier name** - Based on detection, suggest a name but let user choose:\n'
        '\n'
        '   If there is only ONE project area, use the simple format:\n'
        '   - "verifier-playwright" for web UI testing\n'
        '   - "verifier-cli" for CLI/terminal testing\n'
        '   - "verifier-api" for HTTP API testing\n'
        '\n'
        '   If there are MULTIPLE project areas, use the format '
        '`verifier-<project>-<type>`:\n'
        '   - "verifier-frontend-playwright" for the frontend web UI\n'
        '   - "verifier-backend-api" for the backend API\n'
        '   - "verifier-admin-playwright" for an admin dashboard\n'
        '\n'
        '   Custom names are allowed but MUST include "verifier" in the name -- the '
        'Verify agent discovers skills by looking for "verifier" in the folder name.\n'
        '\n'
        '2. **Project-specific questions** based on type:\n'
        '\n'
        '   For web apps (playwright):\n'
        '   - Dev server command (e.g., "npm run dev")\n'
        '   - Dev server URL (e.g., "http://localhost:3000")\n'
        '   - Ready signal (text that appears when server is ready)\n'
        '\n'
        '   For CLI tools:\n'
        '   - Entry point command (e.g., "node ./cli.js" or "./target/debug/myapp")\n'
        '   - Whether to record with asciinema\n'
        '\n'
        '   For APIs:\n'
        '   - API server command\n'
        '   - Base URL\n'
        '\n'
        '3. **Authentication & Login** (for web apps and APIs):\n'
        '\n'
        '   Use AskUserQuestion to ask: "Does your app require authentication/login '
        'to access the pages or endpoints being verified?"\n'
        '   - **No authentication needed** - App is publicly accessible\n'
        '   - **Yes, login required** - App requires authentication\n'
        '   - **Some pages require auth** - Mix of public and authenticated routes\n'
        '\n'
        '   If login is required, ask follow-up questions:\n'
        '   - **Login method**: Form-based, API token, OAuth/SSO, or Other\n'
        '   - **Test credentials**: Suggest using environment variables '
        '(e.g., `TEST_USER`, `TEST_PASSWORD`)\n'
        '   - **Post-login indicator**: URL redirect, element appears, or '
        'cookie/token set\n'
        '\n'
        '## Phase 4: Generate Verifier Skill\n'
        '\n'
        '**All verifier skills are created in the project root\'s `.neomclaw/skills/` '
        'directory.** This ensures they are automatically loaded when NeomClaw runs in '
        'the project.\n'
        '\n'
        'Write the skill file to `.neomclaw/skills/<verifier-name>/SKILL.md`.\n'
        '\n'
        '### Skill Template Structure\n'
        '\n'
        '```markdown\n'
        '---\n'
        'name: <verifier-name>\n'
        'description: <description based on type>\n'
        'allowed-tools:\n'
        '  # Tools appropriate for the verifier type\n'
        '---\n'
        '\n'
        '# <Verifier Title>\n'
        '\n'
        'You are a verification executor. You receive a verification plan and '
        'execute it EXACTLY as written.\n'
        '\n'
        '## Project Context\n'
        '<Project-specific details from detection>\n'
        '\n'
        '## Setup Instructions\n'
        '<How to start any required services>\n'
        '\n'
        '## Authentication\n'
        '<If auth is required, include step-by-step login instructions here>\n'
        '\n'
        '## Reporting\n'
        '\n'
        'Report PASS or FAIL for each step using the format specified in the '
        'verification plan.\n'
        '\n'
        '## Cleanup\n'
        '\n'
        'After verification:\n'
        '1. Stop any dev servers started\n'
        '2. Close any browser sessions\n'
        '3. Report final summary\n'
        '\n'
        '## Self-Update\n'
        '\n'
        'If verification fails because this skill\'s instructions are outdated '
        '(dev server command/port/ready-signal changed, etc.) -- not because the '
        'feature under test is broken -- or if the user corrects you mid-run, use '
        'AskUserQuestion to confirm and then Edit this SKILL.md with a minimal '
        'targeted fix.\n'
        '```\n'
        '\n'
        '### Allowed Tools by Type\n'
        '\n'
        '**verifier-playwright**:\n'
        '```yaml\n'
        'allowed-tools:\n'
        '  - Bash(npm:*)\n'
        '  - Bash(yarn:*)\n'
        '  - Bash(pnpm:*)\n'
        '  - Bash(bun:*)\n'
        '  - mcp__playwright__*\n'
        '  - Read\n'
        '  - Glob\n'
        '  - Grep\n'
        '```\n'
        '\n'
        '**verifier-cli**:\n'
        '```yaml\n'
        'allowed-tools:\n'
        '  - Tmux\n'
        '  - Bash(asciinema:*)\n'
        '  - Read\n'
        '  - Glob\n'
        '  - Grep\n'
        '```\n'
        '\n'
        '**verifier-api**:\n'
        '```yaml\n'
        'allowed-tools:\n'
        '  - Bash(curl:*)\n'
        '  - Bash(http:*)\n'
        '  - Bash(npm:*)\n'
        '  - Bash(yarn:*)\n'
        '  - Read\n'
        '  - Glob\n'
        '  - Grep\n'
        '```\n'
        '\n'
        '## Phase 5: Confirm Creation\n'
        '\n'
        'After writing the skill file(s), inform the user:\n'
        '1. Where each skill was created (always in `.neomclaw/skills/`)\n'
        '2. How the Verify agent will discover them -- the folder name must contain '
        '"verifier" (case-insensitive) for automatic discovery\n'
        '3. That they can edit the skills to customize them\n'
        '4. That they can run /init-verifiers again to add more verifiers for other areas\n'
        '5. That the verifier will offer to self-update if it detects its own '
        'instructions are outdated (wrong dev server command, changed ready signal, etc.)',
      ),
    ];
  }
}
