// BashTool Security — port of neom_claw/src/tools/BashTool/bashSecurity.ts.
// Shell command security validation: command substitution detection, redirection
// checks, IFS injection prevention, obfuscated flag detection, dangerous
// variable checks, quote extraction, heredoc validation, and more.

// ─── Constants ───────────────────────────────────────────────────────────────

/// Numeric identifiers for bash security checks (avoids logging strings).
class BashSecurityCheckId {
  static const int incompleteCommands = 1;
  static const int jqSystemFunction = 2;
  static const int jqFileArguments = 3;
  static const int obfuscatedFlags = 4;
  static const int shellMetacharacters = 5;
  static const int dangerousVariables = 6;
  static const int newlines = 7;
  static const int dangerousPatternsCommandSubstitution = 8;
  static const int dangerousPatternsInputRedirection = 9;
  static const int dangerousPatternsOutputRedirection = 10;
  static const int ifsInjection = 11;
  static const int gitCommitSubstitution = 12;
  static const int procEnvironAccess = 13;
  static const int malformedTokenInjection = 14;
  static const int backslashEscapedWhitespace = 15;
  static const int braceExpansion = 16;
  static const int controlCharacters = 17;
  static const int unicodeWhitespace = 18;
  static const int midWordHash = 19;
  static const int zshDangerousCommands = 20;
  static const int backslashEscapedOperators = 21;
  static const int commentQuoteDesync = 22;
  static const int quotedNewline = 23;
}

// ─── Permission Result ───────────────────────────────────────────────────────

/// Result of a security validation check.
class SecurityResult {
  /// The behavior: 'allow', 'ask', or 'passthrough'.
  final String behavior;

  /// Human-readable message explaining the decision.
  final String message;

  /// Updated input if the command was modified.
  final Map<String, dynamic>? updatedInput;

  /// Reason for the decision.
  final String? decisionReason;

  const SecurityResult.allow({
    required this.message,
    this.updatedInput,
    this.decisionReason,
  }) : behavior = 'allow';

  const SecurityResult.ask({required this.message})
    : behavior = 'ask',
      updatedInput = null,
      decisionReason = null;

  const SecurityResult.passthrough({required this.message})
    : behavior = 'passthrough',
      updatedInput = null,
      decisionReason = null;

  bool get isAllow => behavior == 'allow';
  bool get isAsk => behavior == 'ask';
  bool get isPassthrough => behavior == 'passthrough';
}

// ─── Command Substitution Patterns ───────────────────────────────────────────

/// Patterns that indicate command substitution in shell commands.
class _SubstitutionPattern {
  final RegExp pattern;
  final String message;

  const _SubstitutionPattern(this.pattern, this.message);
}

final List<_SubstitutionPattern> _commandSubstitutionPatterns = [
  _SubstitutionPattern(RegExp(r'<\('), 'process substitution <()'),
  _SubstitutionPattern(RegExp(r'>\('), 'process substitution >()'),
  _SubstitutionPattern(RegExp(r'=\('), 'Zsh process substitution =()'),
  _SubstitutionPattern(
    RegExp(r'(?:^|[\s;&|])=[a-zA-Z_]'),
    'Zsh equals expansion (=cmd)',
  ),
  _SubstitutionPattern(RegExp(r'\$\('), r'$() command substitution'),
  _SubstitutionPattern(RegExp(r'\$\{'), r'${} parameter substitution'),
  _SubstitutionPattern(RegExp(r'\$\['), r'$[] legacy arithmetic expansion'),
  _SubstitutionPattern(RegExp(r'~\['), 'Zsh-style parameter expansion'),
  _SubstitutionPattern(RegExp(r'\(e:'), 'Zsh-style glob qualifiers'),
  _SubstitutionPattern(
    RegExp(r'\(\+'),
    'Zsh glob qualifier with command execution',
  ),
  _SubstitutionPattern(
    RegExp(r'\}\s*always\s*\{'),
    'Zsh always block (try/always construct)',
  ),
  _SubstitutionPattern(RegExp(r'<#'), 'PowerShell comment syntax'),
];

/// Zsh-specific dangerous commands that can bypass security checks.
const Set<String> _zshDangerousCommands = {
  'zmodload',
  'emulate',
  'sysopen',
  'sysread',
  'syswrite',
  'sysseek',
  'zpty',
  'ztcp',
  'zsocket',
  'mapfile',
  'zf_rm',
  'zf_mv',
  'zf_ln',
  'zf_chmod',
  'zf_chown',
  'zf_mkdir',
  'zf_rmdir',
  'zf_chgrp',
};

// ─── Heredoc Detection ───────────────────────────────────────────────────────

final RegExp _heredocInSubstitution = RegExp(r'\$\(.*<<');

// ─── Quote Extraction ────────────────────────────────────────────────────────

/// Result of extracting quoted content from a command.
class QuoteExtraction {
  /// Content with single-quoted parts removed.
  final String withDoubleQuotes;

  /// Content with all quoted parts removed.
  final String fullyUnquoted;

  /// Like fullyUnquoted but preserves quote characters ('/"): strips quoted
  /// content while keeping the delimiters.
  final String unquotedKeepQuoteChars;

  const QuoteExtraction({
    required this.withDoubleQuotes,
    required this.fullyUnquoted,
    required this.unquotedKeepQuoteChars,
  });
}

/// Extract quoted content from a command string.
/// Returns strings with different levels of quote stripping.
QuoteExtraction extractQuotedContent(String command, {bool isJq = false}) {
  final withDoubleQuotes = StringBuffer();
  final fullyUnquoted = StringBuffer();
  final unquotedKeepQuoteChars = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var escaped = false;

  for (var i = 0; i < command.length; i++) {
    final char = command[i];

    if (escaped) {
      escaped = false;
      if (!inSingleQuote) withDoubleQuotes.write(char);
      if (!inSingleQuote && !inDoubleQuote) fullyUnquoted.write(char);
      if (!inSingleQuote && !inDoubleQuote) {
        unquotedKeepQuoteChars.write(char);
      }
      continue;
    }

    if (char == r'\' && !inSingleQuote) {
      escaped = true;
      if (!inSingleQuote) withDoubleQuotes.write(char);
      if (!inSingleQuote && !inDoubleQuote) fullyUnquoted.write(char);
      if (!inSingleQuote && !inDoubleQuote) {
        unquotedKeepQuoteChars.write(char);
      }
      continue;
    }

    if (char == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      unquotedKeepQuoteChars.write(char);
      continue;
    }

    if (char == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      unquotedKeepQuoteChars.write(char);
      if (!isJq) continue;
    }

    if (!inSingleQuote) withDoubleQuotes.write(char);
    if (!inSingleQuote && !inDoubleQuote) fullyUnquoted.write(char);
    if (!inSingleQuote && !inDoubleQuote) {
      unquotedKeepQuoteChars.write(char);
    }
  }

  return QuoteExtraction(
    withDoubleQuotes: withDoubleQuotes.toString(),
    fullyUnquoted: fullyUnquoted.toString(),
    unquotedKeepQuoteChars: unquotedKeepQuoteChars.toString(),
  );
}

/// Strip safe redirections from content (>/dev/null, 2>&1, </dev/null).
String stripSafeRedirections(String content) {
  // SECURITY: All three patterns MUST have a trailing boundary (?=\s|$).
  var result = content;
  result = result.replaceAll(RegExp(r'\s+2\s*>&\s*1(?=\s|$)'), '');
  result = result.replaceAll(RegExp(r'[012]?\s*>\s*/dev/null(?=\s|$)'), '');
  result = result.replaceAll(RegExp(r'\s*<\s*/dev/null(?=\s|$)'), '');
  return result;
}

// ─── Unescaped Character Check ───────────────────────────────────────────────

/// Check if content contains an unescaped occurrence of a single character.
/// Handles bash escape sequences correctly.
bool hasUnescapedChar(String content, String char) {
  assert(char.length == 1, 'hasUnescapedChar only works with single chars');
  var i = 0;
  while (i < content.length) {
    if (content[i] == r'\' && i + 1 < content.length) {
      i += 2; // Skip backslash and escaped character.
      continue;
    }
    if (content[i] == char) return true;
    i++;
  }
  return false;
}

// ─── Validation Context ──────────────────────────────────────────────────────

/// Context passed to each security validator.
class ValidationContext {
  final String originalCommand;
  final String baseCommand;
  final String unquotedContent;
  final String fullyUnquotedContent;
  final String fullyUnquotedPreStrip;
  final String unquotedKeepQuoteChars;

  const ValidationContext({
    required this.originalCommand,
    required this.baseCommand,
    required this.unquotedContent,
    required this.fullyUnquotedContent,
    required this.fullyUnquotedPreStrip,
    required this.unquotedKeepQuoteChars,
  });
}

// ─── Individual Validators ───────────────────────────────────────────────────

/// Check for empty commands.
SecurityResult _validateEmpty(ValidationContext ctx) {
  if (ctx.originalCommand.trim().isEmpty) {
    return SecurityResult.allow(
      message: 'Empty command is safe',
      updatedInput: {'command': ctx.originalCommand},
      decisionReason: 'Empty command is safe',
    );
  }
  return const SecurityResult.passthrough(message: 'Command is not empty');
}

/// Check for incomplete command fragments.
SecurityResult _validateIncompleteCommands(ValidationContext ctx) {
  final trimmed = ctx.originalCommand.trim();

  if (RegExp(r'^\s*\t').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message: 'Command appears to be an incomplete fragment (starts with tab)',
    );
  }

  if (trimmed.startsWith('-')) {
    return const SecurityResult.ask(
      message:
          'Command appears to be an incomplete fragment (starts with flags)',
    );
  }

  if (RegExp(r'^\s*(&&|\|\||;|>>?|<)').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command appears to be a continuation line (starts with operator)',
    );
  }

  return const SecurityResult.passthrough(message: 'Command appears complete');
}

/// Check for jq-specific dangerous patterns.
SecurityResult _validateJqCommand(ValidationContext ctx) {
  if (ctx.baseCommand != 'jq') {
    return const SecurityResult.passthrough(message: 'Not jq');
  }

  if (RegExp(r'\bsystem\s*\(').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'jq command contains system() function which executes arbitrary commands',
    );
  }

  final afterJq = ctx.originalCommand.substring(3).trim();
  if (RegExp(
    r'(?:^|\s)(?:-f\b|--from-file|--rawfile|--slurpfile|-L\b|--library-path)',
  ).hasMatch(afterJq)) {
    return const SecurityResult.ask(
      message:
          'jq command contains dangerous flags that could execute code or '
          'read arbitrary files',
    );
  }

  return const SecurityResult.passthrough(message: 'jq command is safe');
}

/// Check for shell metacharacters in arguments.
SecurityResult _validateShellMetacharacters(ValidationContext ctx) {
  const message =
      'Command contains shell metacharacters (;, |, or &) in arguments';

  if (RegExp(
    r'''(?:^|\s)["'][^"']*[;&][^"']*["'](?:\s|$)''',
  ).hasMatch(ctx.unquotedContent)) {
    return SecurityResult.ask(message: message);
  }

  final globPatterns = [
    RegExp(r'''-name\s+["'][^"']*[;|&][^"']*["']'''),
    RegExp(r'''-path\s+["'][^"']*[;|&][^"']*["']'''),
    RegExp(r'''-iname\s+["'][^"']*[;|&][^"']*["']'''),
  ];

  if (globPatterns.any((p) => p.hasMatch(ctx.unquotedContent))) {
    return SecurityResult.ask(message: message);
  }

  if (RegExp(
    r'''-regex\s+["'][^"']*[;&][^"']*["']''',
  ).hasMatch(ctx.unquotedContent)) {
    return SecurityResult.ask(message: message);
  }

  return const SecurityResult.passthrough(message: 'No metacharacters');
}

/// Check for dangerous variables in redirections/pipes.
SecurityResult _validateDangerousVariables(ValidationContext ctx) {
  if (RegExp(r'[<>|]\s*\$[A-Za-z_]').hasMatch(ctx.fullyUnquotedContent) ||
      RegExp(
        r'\$[A-Za-z_][A-Za-z0-9_]*\s*[|<>]',
      ).hasMatch(ctx.fullyUnquotedContent)) {
    return const SecurityResult.ask(
      message:
          'Command contains variables in dangerous contexts '
          '(redirections or pipes)',
    );
  }
  return const SecurityResult.passthrough(message: 'No dangerous variables');
}

/// Check for dangerous command substitution patterns.
SecurityResult _validateDangerousPatterns(ValidationContext ctx) {
  // Check for unescaped backticks.
  if (hasUnescapedChar(ctx.unquotedContent, '`')) {
    return const SecurityResult.ask(
      message: 'Command contains backticks (`) for command substitution',
    );
  }

  for (final sp in _commandSubstitutionPatterns) {
    if (sp.pattern.hasMatch(ctx.unquotedContent)) {
      return SecurityResult.ask(message: 'Command contains ${sp.message}');
    }
  }

  return const SecurityResult.passthrough(message: 'No dangerous patterns');
}

/// Check for input/output redirections.
SecurityResult _validateRedirections(ValidationContext ctx) {
  if (ctx.fullyUnquotedContent.contains('<')) {
    return const SecurityResult.ask(
      message:
          'Command contains input redirection (<) which could read sensitive files',
    );
  }
  if (ctx.fullyUnquotedContent.contains('>')) {
    return const SecurityResult.ask(
      message:
          'Command contains output redirection (>) which could write to '
          'arbitrary files',
    );
  }
  return const SecurityResult.passthrough(message: 'No redirections');
}

/// Check for newlines that could separate commands.
SecurityResult _validateNewlines(ValidationContext ctx) {
  if (!RegExp(r'[\n\r]').hasMatch(ctx.fullyUnquotedPreStrip)) {
    return const SecurityResult.passthrough(message: 'No newlines');
  }

  // Check for newline/CR followed by non-whitespace, except
  // backslash-newline continuations at word boundaries.
  if (RegExp(r'(?<![\s]\\)[\n\r]\s*\S').hasMatch(ctx.fullyUnquotedPreStrip)) {
    return const SecurityResult.ask(
      message:
          'Command contains newlines that could separate multiple commands',
    );
  }

  return const SecurityResult.passthrough(
    message: 'Newlines appear to be within data',
  );
}

/// Check for IFS variable injection.
SecurityResult _validateIFSInjection(ValidationContext ctx) {
  if (RegExp(r'\$IFS|\$\{[^}]*IFS').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command contains IFS variable usage which could bypass '
          'security validation',
    );
  }
  return const SecurityResult.passthrough(message: 'No IFS injection detected');
}

/// Check for /proc/*/environ access.
SecurityResult _validateProcEnvironAccess(ValidationContext ctx) {
  if (RegExp(r'/proc/.*/environ').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command accesses /proc/*/environ which could expose sensitive '
          'environment variables',
    );
  }
  return const SecurityResult.passthrough(
    message: 'No /proc/environ access detected',
  );
}

/// Check for Zsh-specific dangerous commands.
SecurityResult _validateZshDangerousCommands(ValidationContext ctx) {
  if (_zshDangerousCommands.contains(ctx.baseCommand)) {
    return SecurityResult.ask(
      message:
          'Command uses Zsh-specific dangerous builtin: ${ctx.baseCommand}',
    );
  }
  return const SecurityResult.passthrough(message: 'No Zsh dangerous commands');
}

/// Check for git commit with command substitution in message.
SecurityResult _validateGitCommit(ValidationContext ctx) {
  if (ctx.baseCommand != 'git' ||
      !RegExp(r'^git\s+commit\s+').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.passthrough(message: 'Not a git commit');
  }

  // Backslashes in commit commands are suspicious.
  if (ctx.originalCommand.contains(r'\')) {
    return const SecurityResult.passthrough(
      message: 'Git commit contains backslash, needs full validation',
    );
  }

  final messageMatch = RegExp(
    r'''^git[ \t]+commit[ \t]+[^;&|`$<>()\n\r]*?-m[ \t]+(["'])([\s\S]*?)\1(.*)$''',
  ).firstMatch(ctx.originalCommand);

  if (messageMatch != null) {
    final quote = messageMatch.group(1);
    final messageContent = messageMatch.group(2) ?? '';
    final remainder = messageMatch.group(3) ?? '';

    if (quote == '"' &&
        messageContent.isNotEmpty &&
        RegExp(r'\$\(|`|\$\{').hasMatch(messageContent)) {
      return const SecurityResult.ask(
        message: 'Git commit message contains command substitution patterns',
      );
    }

    if (remainder.isNotEmpty &&
        RegExp(r'''[;|&()`]|\$\(|\$\{''').hasMatch(remainder)) {
      return const SecurityResult.passthrough(
        message: 'Git commit remainder contains shell metacharacters',
      );
    }

    // Check remainder for unquoted redirect operators.
    if (remainder.isNotEmpty) {
      var unquoted = '';
      var inSQ = false;
      var inDQ = false;
      for (var i = 0; i < remainder.length; i++) {
        final c = remainder[i];
        if (c == "'" && !inDQ) {
          inSQ = !inSQ;
          continue;
        }
        if (c == '"' && !inSQ) {
          inDQ = !inDQ;
          continue;
        }
        if (!inSQ && !inDQ) unquoted += c;
      }
      if (RegExp(r'[<>]').hasMatch(unquoted)) {
        return const SecurityResult.passthrough(
          message: 'Git commit remainder contains unquoted redirect operator',
        );
      }
    }

    // Block messages starting with dash.
    if (messageContent.startsWith('-')) {
      return const SecurityResult.ask(
        message: 'Command contains quoted characters in flag names',
      );
    }

    return SecurityResult.allow(
      message: 'Git commit with simple quoted message is allowed',
      updatedInput: {'command': ctx.originalCommand},
      decisionReason: 'Git commit with simple quoted message is allowed',
    );
  }

  return const SecurityResult.passthrough(
    message: 'Git commit needs validation',
  );
}

/// Check for ANSI-C quoting and obfuscated flags.
SecurityResult _validateObfuscatedFlags(ValidationContext ctx) {
  final hasShellOperators = RegExp(r'[|&;]').hasMatch(ctx.originalCommand);
  if (ctx.baseCommand == 'echo' && !hasShellOperators) {
    return const SecurityResult.passthrough(
      message: 'echo command is safe and has no dangerous flags',
    );
  }

  // Block ANSI-C quoting ($'...').
  if (RegExp(r"\$'[^']*'").hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message: 'Command contains ANSI-C quoting which can hide characters',
    );
  }

  // Block locale quoting ($"...").
  if (RegExp(r'\$"[^"]*"').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message: 'Command contains locale quoting which can hide characters',
    );
  }

  // Block empty ANSI-C or locale quotes followed by dash.
  if (RegExp(r"""\$['"]{2}\s*-""").hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command contains empty special quotes before dash (potential bypass)',
    );
  }

  // Block empty quote pairs followed by dash.
  if (RegExp(r'''(?:^|\s)(?:''|""){1,}\s*-''').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message: 'Command contains empty quotes before dash (potential bypass)',
    );
  }

  // Block homogeneous empty quote pairs adjacent to quoted dash.
  if (RegExp(r'''(?:""|''){1,}['"]-''').hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command contains empty quote pair adjacent to quoted dash '
          '(potential flag obfuscation)',
    );
  }

  // Block 3+ consecutive quotes at word start.
  if (RegExp(r"""(?:^|\s)['"]{3,}""").hasMatch(ctx.originalCommand)) {
    return const SecurityResult.ask(
      message:
          'Command contains consecutive quote characters at word start '
          '(potential obfuscation)',
    );
  }

  return const SecurityResult.passthrough(
    message: 'No obfuscated flags detected',
  );
}

/// Check for carriage return characters causing tokenization differentials.
SecurityResult _validateCarriageReturn(ValidationContext ctx) {
  if (!ctx.originalCommand.contains('\r')) {
    return const SecurityResult.passthrough(message: 'No carriage return');
  }

  var inSingleQuote = false;
  var inDoubleQuote = false;
  var escaped = false;
  for (var i = 0; i < ctx.originalCommand.length; i++) {
    final c = ctx.originalCommand[i];
    if (escaped) {
      escaped = false;
      continue;
    }
    if (c == r'\' && !inSingleQuote) {
      escaped = true;
      continue;
    }
    if (c == "'" && !inDoubleQuote) {
      inSingleQuote = !inSingleQuote;
      continue;
    }
    if (c == '"' && !inSingleQuote) {
      inDoubleQuote = !inDoubleQuote;
      continue;
    }
    if (c == '\r' && !inDoubleQuote) {
      return const SecurityResult.ask(
        message:
            r'Command contains carriage return (\r) which shell-quote and '
            'bash tokenize differently',
      );
    }
  }

  return const SecurityResult.passthrough(
    message: 'CR only inside double quotes',
  );
}

// ─── Main Security Validator ─────────────────────────────────────────────────

/// Build a ValidationContext from a command string.
ValidationContext buildValidationContext(String command) {
  final trimmed = command.trim();
  final baseCommand = trimmed.split(RegExp(r'\s'))[0];

  final extracted = extractQuotedContent(command);
  final fullyUnquotedPreStrip = extracted.fullyUnquoted;
  final fullyUnquotedContent = stripSafeRedirections(extracted.fullyUnquoted);
  final unquotedContent = extracted.withDoubleQuotes;

  return ValidationContext(
    originalCommand: command,
    baseCommand: baseCommand,
    unquotedContent: unquotedContent,
    fullyUnquotedContent: fullyUnquotedContent,
    fullyUnquotedPreStrip: fullyUnquotedPreStrip,
    unquotedKeepQuoteChars: extracted.unquotedKeepQuoteChars,
  );
}

/// All security validators in evaluation order.
/// Early validators (allow/ask) short-circuit the chain.
/// Main validators run if early validators return passthrough.
final List<SecurityResult Function(ValidationContext)> _earlyValidators = [
  _validateEmpty,
  _validateIncompleteCommands,
  _validateGitCommit,
  _validateJqCommand,
];

final List<SecurityResult Function(ValidationContext)> _mainValidators = [
  _validateCarriageReturn,
  _validateObfuscatedFlags,
  _validateShellMetacharacters,
  _validateDangerousVariables,
  _validateDangerousPatterns,
  _validateRedirections,
  _validateNewlines,
  _validateIFSInjection,
  _validateProcEnvironAccess,
  _validateZshDangerousCommands,
];

/// Run all security checks on a command.
/// Returns the first non-passthrough result, or passthrough if all pass.
SecurityResult bashCommandIsSafe(String command) {
  final ctx = buildValidationContext(command);

  // Early validators — allow/ask short-circuits.
  for (final validator in _earlyValidators) {
    final result = validator(ctx);
    if (!result.isPassthrough) return result;
  }

  // Main validators — ask short-circuits.
  for (final validator in _mainValidators) {
    final result = validator(ctx);
    if (!result.isPassthrough) return result;
  }

  return const SecurityResult.passthrough(
    message: 'All security checks passed',
  );
}

/// Deprecated version of bashCommandIsSafe for heredoc recursive calls.
SecurityResult bashCommandIsSafe_DEPRECATED(String command) {
  return bashCommandIsSafe(command);
}

// ─── Safe Heredoc Substitution ───────────────────────────────────────────────

/// Check if a command contains a safe heredoc-in-substitution pattern.
bool hasSafeHeredocSubstitution(String command) {
  return stripSafeHeredocSubstitutions(command) != null;
}

/// Strip safe $(cat <<'DELIM'...DELIM) heredoc substitutions from a command.
/// Returns the command with heredocs stripped, or null if none found.
String? stripSafeHeredocSubstitutions(String command) {
  if (!_heredocInSubstitution.hasMatch(command)) return null;

  final heredocPattern = RegExp(
    r"""\$\(cat[ \t]*<<(-?)[ \t]*(?:'+([A-Za-z_]\w*)'+|\\([A-Za-z_]\w*))""",
  );
  var result = command;
  var found = false;
  final ranges = <({int start, int end})>[];

  for (final match in heredocPattern.allMatches(command)) {
    if (match.start > 0 && command[match.start - 1] == r'\') continue;
    final delimiter = match.group(2) ?? match.group(3);
    if (delimiter == null) continue;
    final isDash = match.group(1) == '-';
    final operatorEnd = match.start + match.group(0)!.length;

    final afterOperator = command.substring(operatorEnd);
    final openLineEnd = afterOperator.indexOf('\n');
    if (openLineEnd == -1) continue;
    if (!RegExp(
      r'^[ \t]*$',
    ).hasMatch(afterOperator.substring(0, openLineEnd))) {
      continue;
    }

    final bodyStart = operatorEnd + openLineEnd + 1;
    final bodyLines = command.substring(bodyStart).split('\n');
    for (var i = 0; i < bodyLines.length; i++) {
      final rawLine = bodyLines[i];
      final line = isDash ? rawLine.replaceFirst(RegExp(r'^\t*'), '') : rawLine;
      if (line.startsWith(delimiter)) {
        final after = line.substring(delimiter.length);
        var closePos = -1;
        if (RegExp(r'^[ \t]*\)').hasMatch(after)) {
          final lineStart =
              bodyStart +
              bodyLines.sublist(0, i).join('\n').length +
              (i > 0 ? 1 : 0);
          closePos = command.indexOf(')', lineStart);
        } else if (after.isEmpty) {
          final nextLine = i + 1 < bodyLines.length ? bodyLines[i + 1] : null;
          if (nextLine != null && RegExp(r'^[ \t]*\)').hasMatch(nextLine)) {
            final nextLineStart =
                bodyStart + bodyLines.sublist(0, i + 1).join('\n').length + 1;
            closePos = command.indexOf(')', nextLineStart);
          }
        }
        if (closePos != -1) {
          ranges.add((start: match.start, end: closePos + 1));
          found = true;
        }
        break;
      }
    }
  }

  if (!found) return null;
  for (var i = ranges.length - 1; i >= 0; i--) {
    final r = ranges[i];
    result = result.substring(0, r.start) + result.substring(r.end);
  }
  return result;
}

// ─── Utility: Extract Base Command ───────────────────────────────────────────

/// Extract the base command (first word) from a shell command string,
/// stripping variable assignments and common wrappers.
String extractBaseCommand(String command) {
  var trimmed = command.trim();

  // Strip leading variable assignments (FOO=bar cmd).
  while (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=\S*\s+').hasMatch(trimmed)) {
    trimmed = trimmed.replaceFirst(
      RegExp(r'^[A-Za-z_][A-Za-z0-9_]*=\S*\s+'),
      '',
    );
  }

  // Strip common wrappers: env, sudo, nohup, nice, time, etc.
  const wrappers = {
    'env',
    'sudo',
    'nohup',
    'nice',
    'time',
    'timeout',
    'strace',
    'ltrace',
    'unbuffer',
    'script',
  };

  var words = trimmed.split(RegExp(r'\s+'));
  while (words.isNotEmpty && wrappers.contains(words.first)) {
    words = words.sublist(1);
    // Skip flags after wrapper commands.
    while (words.isNotEmpty && words.first.startsWith('-')) {
      words = words.sublist(1);
    }
  }

  return words.isNotEmpty ? words.first : '';
}
