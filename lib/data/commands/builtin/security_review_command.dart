// /security-review command — security-focused code review of pending changes.
// Faithful port of neom_claw/src/commands/security-review.ts (243 TS LOC).
//
// This is a prompt command that performs a comprehensive security review of the
// changes on the current branch. It executes git commands to gather diff
// context, then applies a structured security analysis methodology:
//
//   Phase 1: Repository context research
//   Phase 2: Comparative analysis against existing patterns
//   Phase 3: Vulnerability assessment with data flow tracing
//
// The command uses sub-tasks for parallel false-positive filtering and
// confidence scoring. Only HIGH and MEDIUM severity findings with confidence
// >= 0.8 are reported.
//
// Covers: input validation, auth/authz, crypto, injection/code execution,
// data exposure, with extensive false-positive filtering rules and precedents.

import '../../../domain/models/message.dart';
import '../../tools/tool.dart';
import '../command.dart';

// ============================================================================
// Security review categories
// ============================================================================

/// Security vulnerability categories examined during review.
enum SecurityCategory {
  /// SQL, command, XXE, template, NoSQL, path traversal injection.
  inputValidation,

  /// Auth bypass, privilege escalation, session flaws, JWT, authz bypass.
  authenticationAuthorization,

  /// Hardcoded secrets, weak crypto, improper key management.
  cryptoSecretsManagement,

  /// RCE, deserialization, eval injection, XSS.
  injectionCodeExecution,

  /// Sensitive data logging, PII handling, API data leakage.
  dataExposure,
}

/// Get a human-readable label for a security category.
String securityCategoryLabel(SecurityCategory category) {
  switch (category) {
    case SecurityCategory.inputValidation:
      return 'Input Validation Vulnerabilities';
    case SecurityCategory.authenticationAuthorization:
      return 'Authentication & Authorization Issues';
    case SecurityCategory.cryptoSecretsManagement:
      return 'Crypto & Secrets Management';
    case SecurityCategory.injectionCodeExecution:
      return 'Injection & Code Execution';
    case SecurityCategory.dataExposure:
      return 'Data Exposure';
  }
}

// ============================================================================
// Severity levels and confidence scoring
// ============================================================================

/// Vulnerability severity levels.
enum Severity {
  /// Directly exploitable — RCE, data breach, auth bypass.
  high,

  /// Requires specific conditions but significant impact.
  medium,

  /// Defense-in-depth or lower-impact.
  low,
}

/// Get the severity label string.
String severityLabel(Severity severity) {
  switch (severity) {
    case Severity.high:
      return 'HIGH';
    case Severity.medium:
      return 'MEDIUM';
    case Severity.low:
      return 'LOW';
  }
}

/// Confidence score thresholds.
class ConfidenceThresholds {
  /// 0.9-1.0: Certain exploit path identified.
  static const double certain = 0.9;

  /// 0.8-0.9: Clear vulnerability pattern with known exploitation methods.
  static const double clear = 0.8;

  /// 0.7-0.8: Suspicious pattern requiring specific conditions.
  static const double suspicious = 0.7;

  /// Below 0.7: Too speculative — don't report.
  static const double minimumReport = 0.7;

  /// Minimum confidence for inclusion in final report after false-positive
  /// filtering.
  static const double minimumFinal = 0.8;
}

// ============================================================================
// False-positive exclusion rules
// ============================================================================

/// Hard exclusion patterns — automatically exclude findings matching these.
const List<String> hardExclusions = [
  'Denial of Service (DOS) vulnerabilities or resource exhaustion attacks',
  'Secrets or credentials stored on disk if they are otherwise secured',
  'Rate limiting concerns or service overload scenarios',
  'Memory consumption or CPU exhaustion issues',
  'Lack of input validation on non-security-critical fields without proven '
      'security impact',
  'Input sanitization concerns for GitHub Action workflows unless clearly '
      'triggerable via untrusted input',
  'A lack of hardening measures — only flag concrete vulnerabilities',
  'Race conditions or timing attacks that are theoretical rather than practical',
  'Vulnerabilities related to outdated third-party libraries',
  'Memory safety issues in Rust or other memory-safe languages',
  'Files that are only unit tests or only used as part of running tests',
  'Log spoofing concerns — outputting unsanitized user input to logs is not '
      'a vulnerability',
  'SSRF vulnerabilities that only control the path (must control host or protocol)',
  'Including user-controlled content in AI system prompts',
  'Regex injection — injecting untrusted content into a regex',
  'Regex DOS concerns',
  'Insecure documentation — no findings in markdown files',
  'A lack of audit logs',
];

/// Precedent rules for common patterns.
const List<String> precedents = [
  'Logging high-value secrets in plaintext is a vulnerability; logging URLs '
      'is assumed safe',
  'UUIDs can be assumed unguessable and do not need validation',
  'Environment variables and CLI flags are trusted values — attacks requiring '
      'control of an env var are invalid',
  'Resource management issues (memory or file descriptor leaks) are not valid',
  'Subtle or low-impact web vulnerabilities (tabnabbing, XS-Leaks, prototype '
      'pollution, open redirects) should not be reported unless extremely high '
      'confidence',
  'React and Angular are generally secure against XSS — do not report XSS '
      'unless using dangerouslySetInnerHTML, bypassSecurityTrustHtml, or similar',
  'Most GitHub Action workflow vulnerabilities are not exploitable in practice',
  'Lack of permission checking in client-side JS/TS is not a vulnerability — '
      'validation is the server\'s responsibility',
  'Most iPython notebook (.ipynb) vulnerabilities are not exploitable in practice',
  'Logging non-PII data is not a vulnerability, even if potentially sensitive',
  'Only include MEDIUM findings if they are obvious and concrete issues',
  'Command injection in shell scripts is generally not exploitable since they '
      'don\'t run with untrusted user input',
];

/// Signal quality criteria for remaining findings.
const List<String> signalQualityCriteria = [
  'Is there a concrete, exploitable vulnerability with a clear attack path?',
  'Does this represent a real security risk vs theoretical best practice?',
  'Are there specific code locations and reproduction steps?',
  'Would this finding be actionable for a security team?',
];

// ============================================================================
// Git context helpers
// ============================================================================

/// Shell command to get git status.
const String gitStatusCmd = 'git status';

/// Shell command to get files modified on the branch.
const String gitDiffNamesCmd = 'git diff --name-only origin/HEAD...';

/// Shell command to get commit log for the branch.
const String gitLogCmd = 'git log --no-decorate origin/HEAD...';

/// Shell command to get the full diff for the branch.
const String gitDiffCmd = 'git diff origin/HEAD...';

// ============================================================================
// Frontmatter parsing for allowed-tools
// ============================================================================

/// The allowed tools for the security-review command (from frontmatter).
const Set<String> securityReviewAllowedTools = {
  'Bash',
  'Read',
  'Glob',
  'Grep',
  'Task',
};

// ============================================================================
// SecurityReviewCommand
// ============================================================================

/// The /security-review command — performs a comprehensive security review of
/// pending changes on the current branch.
///
/// Executes a structured multi-phase analysis:
///   1. Repository context research using file search tools
///   2. Comparative analysis against existing security patterns
///   3. Vulnerability assessment with data flow tracing
///
/// Uses sub-tasks for parallel false-positive filtering and confidence scoring.
/// Only reports HIGH and MEDIUM severity findings with confidence >= 8/10.
///
/// Categories examined:
///   - Input validation (SQL/command/XXE/template/NoSQL/path injection)
///   - Authentication & authorization (bypass, escalation, session, JWT)
///   - Crypto & secrets management (hardcoded keys, weak algorithms)
///   - Injection & code execution (RCE, deserialization, eval, XSS)
///   - Data exposure (sensitive logging, PII handling, API leakage)
class SecurityReviewCommand extends PromptCommand {
  @override
  String get name => 'security-review';

  @override
  String get description =>
      'Complete a security review of the pending changes on the current branch';

  @override
  String get progressMessage => 'analyzing code changes for security risks';

  @override
  Set<String> get allowedTools => securityReviewAllowedTools;

  @override
  Future<List<ContentBlock>> getPrompt(
    String args,
    ToolUseContext context,
  ) async {
    // Build the security review prompt with embedded git commands.
    // In the TS version, shell commands prefixed with `!` are executed
    // inline. Here we instruct the LLM to run them as its first step.
    return [
      const TextBlock(
        'You are a senior security engineer conducting a focused security review '
        'of the changes on this branch.\n'
        '\n'
        'First, gather context by running these commands:\n'
        '1. `git status`\n'
        '2. `git diff --name-only origin/HEAD...`\n'
        '3. `git log --no-decorate origin/HEAD...`\n'
        '4. `git diff origin/HEAD...`\n'
        '\n'
        'Review the complete diff. This contains all code changes in the PR.\n'
        '\n'
        '\n'
        'OBJECTIVE:\n'
        'Perform a security-focused code review to identify HIGH-CONFIDENCE security '
        'vulnerabilities that could have real exploitation potential. This is not a '
        'general code review -- focus ONLY on security implications newly added by this '
        'PR. Do not comment on existing security concerns.\n'
        '\n'
        'CRITICAL INSTRUCTIONS:\n'
        '1. MINIMIZE FALSE POSITIVES: Only flag issues where you\'re >80% confident of '
        'actual exploitability\n'
        '2. AVOID NOISE: Skip theoretical issues, style concerns, or low-impact findings\n'
        '3. FOCUS ON IMPACT: Prioritize vulnerabilities that could lead to unauthorized '
        'access, data breaches, or system compromise\n'
        '4. EXCLUSIONS: Do NOT report the following issue types:\n'
        '   - Denial of Service (DOS) vulnerabilities\n'
        '   - Secrets or sensitive data stored on disk\n'
        '   - Rate limiting or resource exhaustion issues\n'
        '\n'
        'SECURITY CATEGORIES TO EXAMINE:\n'
        '\n'
        '**Input Validation Vulnerabilities:**\n'
        '- SQL injection via unsanitized user input\n'
        '- Command injection in system calls or subprocesses\n'
        '- XXE injection in XML parsing\n'
        '- Template injection in templating engines\n'
        '- NoSQL injection in database queries\n'
        '- Path traversal in file operations\n'
        '\n'
        '**Authentication & Authorization Issues:**\n'
        '- Authentication bypass logic\n'
        '- Privilege escalation paths\n'
        '- Session management flaws\n'
        '- JWT token vulnerabilities\n'
        '- Authorization logic bypasses\n'
        '\n'
        '**Crypto & Secrets Management:**\n'
        '- Hardcoded API keys, passwords, or tokens\n'
        '- Weak cryptographic algorithms or implementations\n'
        '- Improper key storage or management\n'
        '- Cryptographic randomness issues\n'
        '- Certificate validation bypasses\n'
        '\n'
        '**Injection & Code Execution:**\n'
        '- Remote code execution via deserialization\n'
        '- Pickle injection in Python\n'
        '- YAML deserialization vulnerabilities\n'
        '- Eval injection in dynamic code execution\n'
        '- XSS vulnerabilities in web applications (reflected, stored, DOM-based)\n'
        '\n'
        '**Data Exposure:**\n'
        '- Sensitive data logging or storage\n'
        '- PII handling violations\n'
        '- API endpoint data leakage\n'
        '- Debug information exposure\n'
        '\n'
        'Additional notes:\n'
        '- Even if something is only exploitable from the local network, it can still '
        'be a HIGH severity issue\n'
        '\n'
        'ANALYSIS METHODOLOGY:\n'
        '\n'
        'Phase 1 - Repository Context Research (Use file search tools):\n'
        '- Identify existing security frameworks and libraries in use\n'
        '- Look for established secure coding patterns in the codebase\n'
        '- Examine existing sanitization and validation patterns\n'
        '- Understand the project\'s security model and threat model\n'
        '\n'
        'Phase 2 - Comparative Analysis:\n'
        '- Compare new code changes against existing security patterns\n'
        '- Identify deviations from established secure practices\n'
        '- Look for inconsistent security implementations\n'
        '- Flag code that introduces new attack surfaces\n'
        '\n'
        'Phase 3 - Vulnerability Assessment:\n'
        '- Examine each modified file for security implications\n'
        '- Trace data flow from user inputs to sensitive operations\n'
        '- Look for privilege boundaries being crossed unsafely\n'
        '- Identify injection points and unsafe deserialization\n'
        '\n'
        'REQUIRED OUTPUT FORMAT:\n'
        '\n'
        'You MUST output your findings in markdown. The markdown output should contain '
        'the file, line number, severity, category (e.g. `sql_injection` or `xss`), '
        'description, exploit scenario, and fix recommendation.\n'
        '\n'
        'For example:\n'
        '\n'
        '# Vuln 1: XSS: `foo.py:42`\n'
        '\n'
        '* Severity: High\n'
        '* Description: User input from `username` parameter is directly interpolated '
        'into HTML without escaping, allowing reflected XSS attacks\n'
        '* Exploit Scenario: Attacker crafts URL like /bar?q=<script>alert('
        'document.cookie)</script> to execute JavaScript in victim\'s browser, enabling '
        'session hijacking or data theft\n'
        '* Recommendation: Use escape() function or templates with auto-escaping '
        'enabled for all user inputs rendered in HTML\n'
        '\n'
        'SEVERITY GUIDELINES:\n'
        '- **HIGH**: Directly exploitable vulnerabilities leading to RCE, data breach, '
        'or authentication bypass\n'
        '- **MEDIUM**: Vulnerabilities requiring specific conditions but with significant '
        'impact\n'
        '- **LOW**: Defense-in-depth issues or lower-impact vulnerabilities\n'
        '\n'
        'CONFIDENCE SCORING:\n'
        '- 0.9-1.0: Certain exploit path identified, tested if possible\n'
        '- 0.8-0.9: Clear vulnerability pattern with known exploitation methods\n'
        '- 0.7-0.8: Suspicious pattern requiring specific conditions to exploit\n'
        '- Below 0.7: Don\'t report (too speculative)\n'
        '\n'
        'FINAL REMINDER:\n'
        'Focus on HIGH and MEDIUM findings only. Better to miss some theoretical issues '
        'than flood the report with false positives. Each finding should be something a '
        'security engineer would confidently raise in a PR review.\n'
        '\n'
        'FALSE POSITIVE FILTERING:\n'
        '\n'
        'You do not need to run commands to reproduce the vulnerability, just read the '
        'code to determine if it is a real vulnerability. Do not use the bash tool or '
        'write to any files.\n'
        '\n'
        'HARD EXCLUSIONS - Automatically exclude findings matching these patterns:\n'
        '1. Denial of Service (DOS) vulnerabilities or resource exhaustion attacks.\n'
        '2. Secrets or credentials stored on disk if they are otherwise secured.\n'
        '3. Rate limiting concerns or service overload scenarios.\n'
        '4. Memory consumption or CPU exhaustion issues.\n'
        '5. Lack of input validation on non-security-critical fields without proven '
        'security impact.\n'
        '6. Input sanitization concerns for GitHub Action workflows unless clearly '
        'triggerable via untrusted input.\n'
        '7. A lack of hardening measures. Code is not expected to implement all security '
        'best practices, only flag concrete vulnerabilities.\n'
        '8. Race conditions or timing attacks that are theoretical rather than practical.\n'
        '9. Vulnerabilities related to outdated third-party libraries.\n'
        '10. Memory safety issues in Rust or any other memory-safe languages.\n'
        '11. Files that are only unit tests or only used as part of running tests.\n'
        '12. Log spoofing concerns. Outputting unsanitized user input to logs is not a '
        'vulnerability.\n'
        '13. SSRF vulnerabilities that only control the path. SSRF is only a concern if '
        'it can control the host or protocol.\n'
        '14. Including user-controlled content in AI system prompts is not a vulnerability.\n'
        '15. Regex injection. Injecting untrusted content into a regex is not a vulnerability.\n'
        '16. Regex DOS concerns.\n'
        '17. Insecure documentation. Do not report any findings in documentation files '
        'such as markdown files.\n'
        '18. A lack of audit logs is not a vulnerability.\n'
        '\n'
        'PRECEDENTS:\n'
        '1. Logging high-value secrets in plaintext is a vulnerability. Logging URLs is '
        'assumed to be safe.\n'
        '2. UUIDs can be assumed to be unguessable and do not need to be validated.\n'
        '3. Environment variables and CLI flags are trusted values. Attackers are generally '
        'not able to modify them in a secure environment.\n'
        '4. Resource management issues such as memory or file descriptor leaks are not valid.\n'
        '5. Subtle or low-impact web vulnerabilities such as tabnabbing, XS-Leaks, prototype '
        'pollution, and open redirects should not be reported unless extremely high confidence.\n'
        '6. React and Angular are generally secure against XSS. Do not report XSS in React or '
        'Angular components unless using dangerouslySetInnerHTML, bypassSecurityTrustHtml, or '
        'similar unsafe methods.\n'
        '7. Most GitHub Action workflow vulnerabilities are not exploitable in practice.\n'
        '8. A lack of permission checking in client-side JS/TS code is not a vulnerability. '
        'Client-side code is not trusted; validation is the server\'s responsibility.\n'
        '9. Only include MEDIUM findings if they are obvious and concrete issues.\n'
        '10. Most iPython notebook (.ipynb) vulnerabilities are not exploitable in practice.\n'
        '11. Logging non-PII data is not a vulnerability even if potentially sensitive.\n'
        '12. Command injection in shell scripts is generally not exploitable since they '
        'don\'t run with untrusted user input.\n'
        '\n'
        'SIGNAL QUALITY CRITERIA - For remaining findings, assess:\n'
        '1. Is there a concrete, exploitable vulnerability with a clear attack path?\n'
        '2. Does this represent a real security risk vs theoretical best practice?\n'
        '3. Are there specific code locations and reproduction steps?\n'
        '4. Would this finding be actionable for a security team?\n'
        '\n'
        'For each finding, assign a confidence score from 1-10:\n'
        '- 1-3: Low confidence, likely false positive or noise\n'
        '- 4-6: Medium confidence, needs investigation\n'
        '- 7-10: High confidence, likely true vulnerability\n'
        '\n'
        'START ANALYSIS:\n'
        '\n'
        'Begin your analysis now. Do this in 3 steps:\n'
        '\n'
        '1. Use a sub-task to identify vulnerabilities. Use the repository exploration '
        'tools to understand the codebase context, then analyze the PR changes for '
        'security implications. In the prompt for this sub-task, include all of the above.\n'
        '2. Then for each vulnerability identified by the above sub-task, create a new '
        'sub-task to filter out false-positives. Launch these sub-tasks as parallel '
        'sub-tasks. In the prompt for these sub-tasks, include everything in the '
        '"FALSE POSITIVE FILTERING" instructions.\n'
        '3. Filter out any vulnerabilities where the sub-task reported a confidence '
        'less than 8.\n'
        '\n'
        'Your final reply must contain the markdown report and nothing else.',
      ),
    ];
  }
}
