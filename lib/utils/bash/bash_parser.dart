// Bash parser utilities — port of neom_claw/src/utils/bash/.
// Command parsing, AST analysis, heredoc handling, security checks.

/// Bash token types.
enum BashTokenType {
  word, // plain word/argument
  operator_, // |, ||, &&, ;, &
  redirect, // >, >>, <, <<, 2>, 2>>
  pipe, // |
  and_, // &&
  or_, // ||
  semicolon, // ;
  background, // &
  newline, // \n
  lparen, // (
  rparen, // )
  lbrace, // {
  rbrace, // }
  heredocMarker, // << or <<-
  comment, // # ...
  variable, // $VAR or ${VAR}
  subshell, // $()
  backtick, // `...`
  singleQuote, // '...'
  doubleQuote, // "..."
  glob, // * or ? or [...]
  assignment, // VAR=value
}

/// A parsed bash token.
class BashToken {
  final BashTokenType type;
  final String value;
  final int offset;
  final int length;

  const BashToken(this.type, this.value, this.offset, this.length);

  @override
  String toString() => 'BashToken($type, "$value")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BashToken &&
          type == other.type &&
          value == other.value &&
          offset == other.offset &&
          length == other.length;

  @override
  int get hashCode => Object.hash(type, value, offset, length);
}

// ---------------------------------------------------------------------------
// Tokenizer
// ---------------------------------------------------------------------------

/// Tokenize a bash command string into a list of [BashToken]s.
///
/// Handles quoting (single, double, ANSI-C $''), escapes, operators,
/// heredoc markers, comments, variables, subshells, backticks, globs,
/// and assignments.
List<BashToken> tokenizeBash(String input) {
  final tokens = <BashToken>[];
  final len = input.length;
  var i = 0;

  bool isOperatorChar(String ch) =>
      ch == '|' ||
      ch == '&' ||
      ch == ';' ||
      ch == '(' ||
      ch == ')' ||
      ch == '{' ||
      ch == '}';

  bool isWhitespace(String ch) => ch == ' ' || ch == '\t';

  // Check if we are at the start of the input or after an operator / newline.
  bool isAtCommandStart() {
    if (tokens.isEmpty) return true;
    final last = tokens.last.type;
    return last == BashTokenType.newline ||
        last == BashTokenType.semicolon ||
        last == BashTokenType.pipe ||
        last == BashTokenType.and_ ||
        last == BashTokenType.or_ ||
        last == BashTokenType.lparen ||
        last == BashTokenType.lbrace;
  }

  while (i < len) {
    final ch = input[i];

    // Skip whitespace.
    if (isWhitespace(ch)) {
      i++;
      continue;
    }

    // Newline.
    if (ch == '\n') {
      tokens.add(BashToken(BashTokenType.newline, '\n', i, 1));
      i++;
      continue;
    }

    // Comment — # at start of a logical command position or after whitespace.
    // In bash, # is only a comment when at the start of a word in command
    // position. For simplicity, we treat any # at word-start as a comment.
    if (ch == '#' && isAtCommandStart()) {
      final start = i;
      while (i < len && input[i] != '\n') {
        i++;
      }
      tokens.add(
        BashToken(
          BashTokenType.comment,
          input.substring(start, i),
          start,
          i - start,
        ),
      );
      continue;
    }

    // Operators: ||, &&, |, &, ;, (, ), {, }
    if (ch == '|') {
      final start = i;
      if (i + 1 < len && input[i + 1] == '|') {
        tokens.add(BashToken(BashTokenType.or_, '||', start, 2));
        i += 2;
      } else {
        tokens.add(BashToken(BashTokenType.pipe, '|', start, 1));
        i++;
      }
      continue;
    }

    if (ch == '&') {
      final start = i;
      if (i + 1 < len && input[i + 1] == '&') {
        tokens.add(BashToken(BashTokenType.and_, '&&', start, 2));
        i += 2;
      } else if (i + 1 < len && input[i + 1] == '>') {
        // &> redirect both
        if (i + 2 < len && input[i + 2] == '>') {
          tokens.add(BashToken(BashTokenType.redirect, '&>>', start, 3));
          i += 3;
        } else {
          tokens.add(BashToken(BashTokenType.redirect, '&>', start, 2));
          i += 2;
        }
      } else {
        tokens.add(BashToken(BashTokenType.background, '&', start, 1));
        i++;
      }
      continue;
    }

    if (ch == ';') {
      tokens.add(BashToken(BashTokenType.semicolon, ';', i, 1));
      i++;
      continue;
    }

    if (ch == '(') {
      tokens.add(BashToken(BashTokenType.lparen, '(', i, 1));
      i++;
      continue;
    }
    if (ch == ')') {
      tokens.add(BashToken(BashTokenType.rparen, ')', i, 1));
      i++;
      continue;
    }
    if (ch == '{') {
      tokens.add(BashToken(BashTokenType.lbrace, '{', i, 1));
      i++;
      continue;
    }
    if (ch == '}') {
      tokens.add(BashToken(BashTokenType.rbrace, '}', i, 1));
      i++;
      continue;
    }

    // Redirections: >, >>, <, <<, <<-, 2>, 2>>, >&
    if (ch == '>' ||
        ch == '<' ||
        (ch == '2' && i + 1 < len && input[i + 1] == '>')) {
      final start = i;
      if (ch == '2' && i + 1 < len && input[i + 1] == '>') {
        if (i + 2 < len && input[i + 2] == '>') {
          tokens.add(BashToken(BashTokenType.redirect, '2>>', start, 3));
          i += 3;
        } else {
          tokens.add(BashToken(BashTokenType.redirect, '2>', start, 2));
          i += 2;
        }
        continue;
      }
      if (ch == '>') {
        if (i + 1 < len && input[i + 1] == '>') {
          tokens.add(BashToken(BashTokenType.redirect, '>>', start, 2));
          i += 2;
        } else if (i + 1 < len && input[i + 1] == '&') {
          tokens.add(BashToken(BashTokenType.redirect, '>&', start, 2));
          i += 2;
        } else {
          tokens.add(BashToken(BashTokenType.redirect, '>', start, 1));
          i++;
        }
        continue;
      }
      if (ch == '<') {
        if (i + 1 < len && input[i + 1] == '<') {
          if (i + 2 < len && input[i + 2] == '-') {
            tokens.add(BashToken(BashTokenType.heredocMarker, '<<-', start, 3));
            i += 3;
          } else if (i + 2 < len && input[i + 2] == '<') {
            // <<< here-string
            tokens.add(BashToken(BashTokenType.redirect, '<<<', start, 3));
            i += 3;
          } else {
            tokens.add(BashToken(BashTokenType.heredocMarker, '<<', start, 2));
            i += 2;
          }
        } else if (i + 1 < len && input[i + 1] == '>') {
          tokens.add(BashToken(BashTokenType.redirect, '<>', start, 2));
          i += 2;
        } else {
          tokens.add(BashToken(BashTokenType.redirect, '<', start, 1));
          i++;
        }
        continue;
      }
    }

    // Single-quoted string.
    if (ch == "'") {
      final start = i;
      i++; // skip opening quote
      final buf = StringBuffer();
      while (i < len && input[i] != "'") {
        buf.write(input[i]);
        i++;
      }
      if (i < len) i++; // skip closing quote
      tokens.add(
        BashToken(BashTokenType.singleQuote, buf.toString(), start, i - start),
      );
      continue;
    }

    // Double-quoted string.
    if (ch == '"') {
      final start = i;
      i++; // skip opening quote
      final buf = StringBuffer();
      while (i < len && input[i] != '"') {
        if (input[i] == '\\' && i + 1 < len) {
          final next = input[i + 1];
          if (next == '"' ||
              next == '\\' ||
              next == '\$' ||
              next == '`' ||
              next == '\n') {
            buf.write(next);
            i += 2;
            continue;
          }
        }
        buf.write(input[i]);
        i++;
      }
      if (i < len) i++; // skip closing quote
      tokens.add(
        BashToken(BashTokenType.doubleQuote, buf.toString(), start, i - start),
      );
      continue;
    }

    // Backtick command substitution.
    if (ch == '`') {
      final start = i;
      i++; // skip opening backtick
      final buf = StringBuffer();
      while (i < len && input[i] != '`') {
        if (input[i] == '\\' && i + 1 < len) {
          buf.write(input[i + 1]);
          i += 2;
          continue;
        }
        buf.write(input[i]);
        i++;
      }
      if (i < len) i++; // skip closing backtick
      tokens.add(
        BashToken(BashTokenType.backtick, buf.toString(), start, i - start),
      );
      continue;
    }

    // Dollar-prefixed constructs: $(), ${}, $VAR, $'...'
    if (ch == '\$') {
      final start = i;
      if (i + 1 < len && input[i + 1] == '(') {
        // $() — subshell / command substitution
        i += 2;
        var depth = 1;
        final buf = StringBuffer();
        while (i < len && depth > 0) {
          if (input[i] == '(') depth++;
          if (input[i] == ')') depth--;
          if (depth > 0) buf.write(input[i]);
          i++;
        }
        tokens.add(
          BashToken(BashTokenType.subshell, buf.toString(), start, i - start),
        );
        continue;
      }
      if (i + 1 < len && input[i + 1] == '{') {
        // ${VAR}
        i += 2;
        final buf = StringBuffer();
        while (i < len && input[i] != '}') {
          buf.write(input[i]);
          i++;
        }
        if (i < len) i++; // skip }
        tokens.add(
          BashToken(
            BashTokenType.variable,
            '\${${buf.toString()}}',
            start,
            i - start,
          ),
        );
        continue;
      }
      if (i + 1 < len && input[i + 1] == "'") {
        // $'...' ANSI-C quoting
        i += 2;
        final buf = StringBuffer();
        while (i < len && input[i] != "'") {
          if (input[i] == '\\' && i + 1 < len) {
            final esc = input[i + 1];
            switch (esc) {
              case 'n':
                buf.write('\n');
                break;
              case 't':
                buf.write('\t');
                break;
              case 'r':
                buf.write('\r');
                break;
              case '\\':
                buf.write('\\');
                break;
              case "'":
                buf.write("'");
                break;
              case 'a':
                buf.write('\x07');
                break;
              case 'b':
                buf.write('\b');
                break;
              case 'e':
                buf.write('\x1B');
                break;
              case 'f':
                buf.write('\x0C');
                break;
              case 'v':
                buf.write('\x0B');
                break;
              default:
                buf.write('\\');
                buf.write(esc);
            }
            i += 2;
            continue;
          }
          buf.write(input[i]);
          i++;
        }
        if (i < len) i++; // skip closing '
        tokens.add(
          BashToken(
            BashTokenType.singleQuote,
            buf.toString(),
            start,
            i - start,
          ),
        );
        continue;
      }
      if (i + 1 < len && _isVarStartChar(input[i + 1])) {
        // $VAR
        i++; // skip $
        final buf = StringBuffer();
        while (i < len && _isVarChar(input[i])) {
          buf.write(input[i]);
          i++;
        }
        tokens.add(
          BashToken(
            BashTokenType.variable,
            '\$${buf.toString()}',
            start,
            i - start,
          ),
        );
        continue;
      }
      if (i + 1 < len &&
          (input[i + 1] == '?' ||
              input[i + 1] == '!' ||
              input[i + 1] == '#' ||
              input[i + 1] == '@' ||
              input[i + 1] == '*' ||
              input[i + 1] == '-' ||
              input[i + 1] == '\$')) {
        // Special variables: $?, $!, $#, $@, $*, $-, $$
        tokens.add(
          BashToken(BashTokenType.variable, '\$${input[i + 1]}', start, 2),
        );
        i += 2;
        continue;
      }
      if (i + 1 < len &&
          input[i + 1].codeUnitAt(0) >= 0x30 &&
          input[i + 1].codeUnitAt(0) <= 0x39) {
        // Positional: $0..$9
        tokens.add(
          BashToken(BashTokenType.variable, '\$${input[i + 1]}', start, 2),
        );
        i += 2;
        continue;
      }
      // Bare $ — treat as word
      i++;
      tokens.add(BashToken(BashTokenType.word, '\$', start, 1));
      continue;
    }

    // Glob characters standalone.
    if (ch == '*' || ch == '?') {
      tokens.add(BashToken(BashTokenType.glob, ch, i, 1));
      i++;
      continue;
    }
    if (ch == '[') {
      final start = i;
      i++;
      while (i < len && input[i] != ']') {
        i++;
      }
      if (i < len) i++; // skip ]
      tokens.add(
        BashToken(
          BashTokenType.glob,
          input.substring(start, i),
          start,
          i - start,
        ),
      );
      continue;
    }

    // Word / assignment — collect until whitespace or operator.
    {
      final start = i;
      final buf = StringBuffer();
      var sawEquals = false;
      var equalsPos = -1;
      while (i < len) {
        final c = input[i];
        if (isWhitespace(c) ||
            c == '\n' ||
            isOperatorChar(c) ||
            c == '>' ||
            c == '<') {
          break;
        }
        if (c == '#' && buf.isNotEmpty) break; // inline comment start
        if (c == '\\' && i + 1 < len) {
          buf.write(input[i + 1]);
          i += 2;
          continue;
        }
        if (c == "'" || c == '"' || c == '`' || c == '\$') break;
        if (c == '*' || c == '?' || c == '[') break;
        if (c == '=' && !sawEquals) {
          sawEquals = true;
          equalsPos = buf.length;
        }
        buf.write(c);
        i++;
      }
      final word = buf.toString();
      if (word.isEmpty) {
        // Safety: advance past an unrecognised character to avoid infinite loop.
        i++;
        continue;
      }

      // Check for assignment (VAR=value).
      if (sawEquals && equalsPos > 0) {
        final name = word.substring(0, equalsPos);
        if (_isValidVarName(name)) {
          tokens.add(
            BashToken(BashTokenType.assignment, word, start, i - start),
          );
          continue;
        }
      }

      tokens.add(BashToken(BashTokenType.word, word, start, i - start));
    }
  }

  return tokens;
}

bool _isVarStartChar(String ch) {
  final c = ch.codeUnitAt(0);
  return (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F; // _
}

bool _isVarChar(String ch) {
  final c = ch.codeUnitAt(0);
  return _isVarStartChar(ch) || (c >= 0x30 && c <= 0x39); // 0-9
}

bool _isValidVarName(String name) {
  if (name.isEmpty) return false;
  if (!_isVarStartChar(name[0])) return false;
  for (var i = 1; i < name.length; i++) {
    if (!_isVarChar(name[i])) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------
// AST types
// ---------------------------------------------------------------------------

/// Redirect representation.
class Redirect {
  final RedirectType type;
  final int? fd;
  final String target;

  const Redirect({required this.type, this.fd, required this.target});

  @override
  String toString() => 'Redirect($type, fd=$fd, target="$target")';
}

enum RedirectType {
  output, // >
  append, // >>
  input, // <
  heredoc, // <<
  heredocStrip, // <<-
  errorOutput, // 2>
  errorAppend, // 2>>
  both, // &> or >&
  inputOutput, // <>
  hereString, // <<<
}

/// Simple command representation.
class SimpleCommand {
  final String executable;
  final List<String> arguments;
  final Map<String, String> assignments;
  final List<Redirect> redirects;

  const SimpleCommand({
    required this.executable,
    this.arguments = const [],
    this.assignments = const {},
    this.redirects = const [],
  });

  /// All words: executable + arguments.
  List<String> get words => [executable, ...arguments];

  @override
  String toString() =>
      'SimpleCommand($executable, args=$arguments, env=$assignments, redirects=$redirects)';
}

/// Pipeline (connected by |).
class Pipeline {
  final List<SimpleCommand> commands;
  final bool negated;

  const Pipeline({required this.commands, this.negated = false});

  @override
  String toString() => 'Pipeline(negated=$negated, commands=$commands)';
}

/// List operator between pipelines.
enum ListOperator { and_, or_, sequential, background }

/// An entry in a command list: a pipeline plus the operator that follows it.
class CommandListEntry {
  final Pipeline pipeline;
  final ListOperator operator_;

  const CommandListEntry({required this.pipeline, required this.operator_});
}

/// Command list (connected by &&, ||, ;, &).
class CommandList {
  final List<CommandListEntry> entries;

  const CommandList({required this.entries});

  /// All pipelines in this command list.
  List<Pipeline> get pipelines => entries.map((e) => e.pipeline).toList();

  /// All simple commands across all pipelines.
  List<SimpleCommand> get allCommands =>
      entries.expand((e) => e.pipeline.commands).toList();

  @override
  String toString() => 'CommandList(${entries.length} entries)';
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

/// Parse a command string into a [CommandList].
CommandList parseCommand(String input) {
  final tokens = tokenizeBash(input);
  final entries = <CommandListEntry>[];

  // Filter out comments and newlines for simpler parsing.
  final filtered = tokens
      .where(
        (t) =>
            t.type != BashTokenType.comment && t.type != BashTokenType.newline,
      )
      .toList();

  if (filtered.isEmpty) {
    return const CommandList(entries: []);
  }

  var i = 0;

  /// Consume one simple command from the token stream.
  SimpleCommand? parseSimpleCmd() {
    final assignments = <String, String>{};
    final redirects = <Redirect>[];
    final words = <String>[];

    // Leading assignments.
    while (i < filtered.length &&
        filtered[i].type == BashTokenType.assignment) {
      final parsed = parseAssignment(filtered[i].value);
      if (parsed != null) {
        assignments[parsed.name] = parsed.value;
      }
      i++;
    }

    // Words, redirects, variables, quoted strings, etc.
    while (i < filtered.length) {
      final t = filtered[i];

      // Stop at list/pipe operators.
      if (t.type == BashTokenType.pipe ||
          t.type == BashTokenType.and_ ||
          t.type == BashTokenType.or_ ||
          t.type == BashTokenType.semicolon ||
          t.type == BashTokenType.background ||
          t.type == BashTokenType.rparen ||
          t.type == BashTokenType.rbrace) {
        break;
      }

      // Redirections.
      if (t.type == BashTokenType.redirect ||
          t.type == BashTokenType.heredocMarker) {
        final rType = _redirectTypeFromToken(t.value);
        i++;
        String target = '';
        if (i < filtered.length) {
          target = _tokenTextValue(filtered[i]);
          i++;
        }
        redirects.add(
          Redirect(type: rType, fd: _fdFromRedirect(t.value), target: target),
        );
        continue;
      }

      // Everything else is a word.
      words.add(_tokenTextValue(t));
      i++;
    }

    if (words.isEmpty && assignments.isEmpty) return null;

    final executable = words.isNotEmpty ? words.first : '';
    final args = words.length > 1 ? words.sublist(1) : <String>[];

    return SimpleCommand(
      executable: executable,
      arguments: args,
      assignments: assignments,
      redirects: redirects,
    );
  }

  /// Parse one pipeline.
  Pipeline parsePipe() {
    var negated = false;
    if (i < filtered.length &&
        filtered[i].type == BashTokenType.word &&
        filtered[i].value == '!') {
      negated = true;
      i++;
    }

    final commands = <SimpleCommand>[];
    final first = parseSimpleCmd();
    if (first != null) commands.add(first);

    while (i < filtered.length && filtered[i].type == BashTokenType.pipe) {
      i++; // skip |
      final next = parseSimpleCmd();
      if (next != null) commands.add(next);
    }

    return Pipeline(commands: commands, negated: negated);
  }

  // Parse the full command list.
  while (i < filtered.length) {
    final pipeline = parsePipe();

    var op = ListOperator.sequential;
    if (i < filtered.length) {
      final t = filtered[i];
      if (t.type == BashTokenType.and_) {
        op = ListOperator.and_;
        i++;
      } else if (t.type == BashTokenType.or_) {
        op = ListOperator.or_;
        i++;
      } else if (t.type == BashTokenType.background) {
        op = ListOperator.background;
        i++;
      } else if (t.type == BashTokenType.semicolon) {
        op = ListOperator.sequential;
        i++;
      } else {
        // Unknown — skip to avoid infinite loop.
        i++;
      }
    }

    entries.add(CommandListEntry(pipeline: pipeline, operator_: op));
  }

  return CommandList(entries: entries);
}

RedirectType _redirectTypeFromToken(String tok) {
  switch (tok) {
    case '>':
      return RedirectType.output;
    case '>>':
      return RedirectType.append;
    case '<':
      return RedirectType.input;
    case '<<':
      return RedirectType.heredoc;
    case '<<-':
      return RedirectType.heredocStrip;
    case '2>':
      return RedirectType.errorOutput;
    case '2>>':
      return RedirectType.errorAppend;
    case '&>':
    case '>&':
      return RedirectType.both;
    case '<>':
      return RedirectType.inputOutput;
    case '<<<':
      return RedirectType.hereString;
    default:
      return RedirectType.output;
  }
}

int? _fdFromRedirect(String tok) {
  if (tok.startsWith('2')) return 2;
  if (tok == '>' || tok == '>>' || tok == '>&') return 1;
  if (tok == '<' ||
      tok == '<<' ||
      tok == '<<-' ||
      tok == '<<<' ||
      tok == '<>') {
    return 0;
  }
  return null;
}

String _tokenTextValue(BashToken t) {
  switch (t.type) {
    case BashTokenType.singleQuote:
    case BashTokenType.doubleQuote:
      return t.value;
    case BashTokenType.variable:
      return t.value;
    case BashTokenType.subshell:
      return '\$(${t.value})';
    case BashTokenType.backtick:
      return '`${t.value}`';
    default:
      return t.value;
  }
}

/// Extract all simple commands from a command string.
List<SimpleCommand> extractCommands(String input) {
  final cmdList = parseCommand(input);
  return cmdList.allCommands;
}

// ---------------------------------------------------------------------------
// Heredoc handling
// ---------------------------------------------------------------------------

/// Heredoc information.
class HeredocInfo {
  final String delimiter;
  final String content;
  final bool stripTabs;
  final bool quoted;

  const HeredocInfo({
    required this.delimiter,
    required this.content,
    this.stripTabs = false,
    this.quoted = false,
  });

  @override
  String toString() =>
      'HeredocInfo(delimiter="$delimiter", stripTabs=$stripTabs, quoted=$quoted, '
      'content=${content.length} chars)';
}

/// Extract heredoc information from a command string.
///
/// Parses `<< DELIM ... DELIM` and `<<- DELIM ... DELIM` patterns.
/// The delimiter may optionally be quoted with single or double quotes,
/// which suppresses variable expansion inside the heredoc.
List<HeredocInfo> extractHeredocs(String input) {
  final results = <HeredocInfo>[];
  final lines = input.split('\n');

  var i = 0;
  while (i < lines.length) {
    final line = lines[i];
    final markers = _findHeredocMarkers(line);

    for (final marker in markers) {
      final stripTabs = marker.strip;
      var delimiter = marker.delimiter;
      var quoted = false;

      // Check for quoting on the delimiter.
      if ((delimiter.startsWith("'") && delimiter.endsWith("'")) ||
          (delimiter.startsWith('"') && delimiter.endsWith('"'))) {
        quoted = true;
        delimiter = delimiter.substring(1, delimiter.length - 1);
      }

      // Collect content until we find the delimiter on its own line.
      final content = StringBuffer();
      var j = i + 1;
      while (j < lines.length) {
        final contentLine = lines[j];
        final trimmed = stripTabs
            ? contentLine.replaceAll(RegExp(r'^\t+'), '')
            : contentLine;
        if (trimmed == delimiter) break;
        if (content.isNotEmpty) content.write('\n');
        content.write(stripTabs ? trimmed : contentLine);
        j++;
      }

      results.add(
        HeredocInfo(
          delimiter: delimiter,
          content: content.toString(),
          stripTabs: stripTabs,
          quoted: quoted,
        ),
      );

      // Advance past the closing delimiter.
      if (j < lines.length) i = j;
    }

    i++;
  }

  return results;
}

class _HeredocMarker {
  final String delimiter;
  final bool strip;
  const _HeredocMarker(this.delimiter, this.strip);
}

List<_HeredocMarker> _findHeredocMarkers(String line) {
  final results = <_HeredocMarker>[];
  // Match <<[-] with optional quoted or unquoted delimiter.
  final pattern = RegExp(r'<<(-?)\s*(?:(["\x27])(\w+)\2|(\w+))');
  for (final match in pattern.allMatches(line)) {
    final strip = match.group(1) == '-';
    final quotedDelim = match.group(3);
    final unquotedDelim = match.group(4);
    final delim = quotedDelim ?? unquotedDelim ?? '';
    results.add(_HeredocMarker(delim, strip));
  }
  return results;
}

/// Check if a heredoc is safe (no command substitution or dangerous variable
/// expansion).
bool isHeredocSafe(HeredocInfo heredoc) {
  // Quoted heredocs prevent expansion — always safe.
  if (heredoc.quoted) return true;

  final content = heredoc.content;

  // Check for command substitution: $() or backticks.
  if (content.contains(r'$(') || content.contains('`')) {
    return false;
  }

  // Check for dangerous variable patterns.
  // Simple $VAR is generally okay; ${VAR:-cmd} or ${VAR:+cmd} can be
  // dangerous if they contain command substitution.
  final dangerousVarPattern = RegExp(r'\$\{[^}]*[`$].*\}', dotAll: true);
  if (dangerousVarPattern.hasMatch(content)) {
    return false;
  }

  return true;
}

// ---------------------------------------------------------------------------
// Command classification
// ---------------------------------------------------------------------------

/// Command category for security / display.
enum CommandCategory {
  fileSystem, // ls, cat, find, rm, mv, cp, mkdir, etc.
  git, // git *
  packageManager, // npm, yarn, pip, cargo, etc.
  compiler, // gcc, rustc, javac, dart, etc.
  editor, // vim, nano, code, etc.
  network, // curl, wget, ssh, etc.
  process, // ps, kill, top, etc.
  search, // grep, rg, ag, find, etc.
  shell, // bash, sh, zsh, source, etc.
  docker, // docker, docker-compose
  database, // psql, mysql, redis-cli, etc.
  testing, // pytest, jest, cargo test, etc.
  linting, // eslint, prettier, dart analyze, etc.
  other,
}

const _categoryMap = <String, CommandCategory>{
  // File system
  'ls': CommandCategory.fileSystem,
  'cat': CommandCategory.fileSystem,
  'head': CommandCategory.fileSystem,
  'tail': CommandCategory.fileSystem,
  'less': CommandCategory.fileSystem,
  'more': CommandCategory.fileSystem,
  'find': CommandCategory.fileSystem,
  'rm': CommandCategory.fileSystem,
  'mv': CommandCategory.fileSystem,
  'cp': CommandCategory.fileSystem,
  'mkdir': CommandCategory.fileSystem,
  'rmdir': CommandCategory.fileSystem,
  'touch': CommandCategory.fileSystem,
  'chmod': CommandCategory.fileSystem,
  'chown': CommandCategory.fileSystem,
  'chgrp': CommandCategory.fileSystem,
  'ln': CommandCategory.fileSystem,
  'stat': CommandCategory.fileSystem,
  'file': CommandCategory.fileSystem,
  'du': CommandCategory.fileSystem,
  'df': CommandCategory.fileSystem,
  'tar': CommandCategory.fileSystem,
  'zip': CommandCategory.fileSystem,
  'unzip': CommandCategory.fileSystem,
  'gzip': CommandCategory.fileSystem,
  'gunzip': CommandCategory.fileSystem,
  'bzip2': CommandCategory.fileSystem,
  'xz': CommandCategory.fileSystem,
  'rsync': CommandCategory.fileSystem,
  'dd': CommandCategory.fileSystem,
  'tee': CommandCategory.fileSystem,
  'wc': CommandCategory.fileSystem,
  'sort': CommandCategory.fileSystem,
  'uniq': CommandCategory.fileSystem,
  'cut': CommandCategory.fileSystem,
  'paste': CommandCategory.fileSystem,
  'tr': CommandCategory.fileSystem,
  'diff': CommandCategory.fileSystem,
  'patch': CommandCategory.fileSystem,
  'realpath': CommandCategory.fileSystem,
  'dirname': CommandCategory.fileSystem,
  'basename': CommandCategory.fileSystem,
  'readlink': CommandCategory.fileSystem,
  'mktemp': CommandCategory.fileSystem,

  // Git
  'git': CommandCategory.git,
  'gh': CommandCategory.git,

  // Package managers
  'npm': CommandCategory.packageManager,
  'npx': CommandCategory.packageManager,
  'yarn': CommandCategory.packageManager,
  'pnpm': CommandCategory.packageManager,
  'bun': CommandCategory.packageManager,
  'pip': CommandCategory.packageManager,
  'pip3': CommandCategory.packageManager,
  'pipx': CommandCategory.packageManager,
  'poetry': CommandCategory.packageManager,
  'conda': CommandCategory.packageManager,
  'cargo': CommandCategory.packageManager,
  'gem': CommandCategory.packageManager,
  'bundle': CommandCategory.packageManager,
  'composer': CommandCategory.packageManager,
  'apt': CommandCategory.packageManager,
  'apt-get': CommandCategory.packageManager,
  'brew': CommandCategory.packageManager,
  'yum': CommandCategory.packageManager,
  'dnf': CommandCategory.packageManager,
  'pacman': CommandCategory.packageManager,
  'snap': CommandCategory.packageManager,
  'flatpak': CommandCategory.packageManager,
  'pub': CommandCategory.packageManager,
  'flutter': CommandCategory.packageManager,
  'dart': CommandCategory.packageManager,
  'go': CommandCategory.packageManager,
  'maven': CommandCategory.packageManager,
  'gradle': CommandCategory.packageManager,
  'nuget': CommandCategory.packageManager,
  'dotnet': CommandCategory.packageManager,

  // Compilers / interpreters
  'gcc': CommandCategory.compiler,
  'g++': CommandCategory.compiler,
  'clang': CommandCategory.compiler,
  'clang++': CommandCategory.compiler,
  'rustc': CommandCategory.compiler,
  'javac': CommandCategory.compiler,
  'java': CommandCategory.compiler,
  'python': CommandCategory.compiler,
  'python3': CommandCategory.compiler,
  'node': CommandCategory.compiler,
  'deno': CommandCategory.compiler,
  'ruby': CommandCategory.compiler,
  'perl': CommandCategory.compiler,
  'php': CommandCategory.compiler,
  'swift': CommandCategory.compiler,
  'swiftc': CommandCategory.compiler,
  'kotlinc': CommandCategory.compiler,
  'scalac': CommandCategory.compiler,
  'make': CommandCategory.compiler,
  'cmake': CommandCategory.compiler,
  'ninja': CommandCategory.compiler,
  'meson': CommandCategory.compiler,
  'cc': CommandCategory.compiler,
  'ld': CommandCategory.compiler,
  'as': CommandCategory.compiler,
  'nasm': CommandCategory.compiler,
  'tsc': CommandCategory.compiler,

  // Editors
  'vim': CommandCategory.editor,
  'nvim': CommandCategory.editor,
  'vi': CommandCategory.editor,
  'nano': CommandCategory.editor,
  'emacs': CommandCategory.editor,
  'code': CommandCategory.editor,
  'subl': CommandCategory.editor,
  'atom': CommandCategory.editor,
  'ed': CommandCategory.editor,
  'sed': CommandCategory.editor,
  'awk': CommandCategory.editor,
  'gawk': CommandCategory.editor,

  // Network
  'curl': CommandCategory.network,
  'wget': CommandCategory.network,
  'ssh': CommandCategory.network,
  'scp': CommandCategory.network,
  'sftp': CommandCategory.network,
  'ftp': CommandCategory.network,
  'nc': CommandCategory.network,
  'netcat': CommandCategory.network,
  'ncat': CommandCategory.network,
  'ping': CommandCategory.network,
  'traceroute': CommandCategory.network,
  'dig': CommandCategory.network,
  'nslookup': CommandCategory.network,
  'host': CommandCategory.network,
  'ifconfig': CommandCategory.network,
  'ip': CommandCategory.network,
  'netstat': CommandCategory.network,
  'ss': CommandCategory.network,
  'tcpdump': CommandCategory.network,
  'nmap': CommandCategory.network,
  'telnet': CommandCategory.network,
  'openssl': CommandCategory.network,
  'socat': CommandCategory.network,
  'httpie': CommandCategory.network,

  // Process management
  'ps': CommandCategory.process,
  'kill': CommandCategory.process,
  'killall': CommandCategory.process,
  'pkill': CommandCategory.process,
  'top': CommandCategory.process,
  'htop': CommandCategory.process,
  'nice': CommandCategory.process,
  'renice': CommandCategory.process,
  'nohup': CommandCategory.process,
  'bg': CommandCategory.process,
  'fg': CommandCategory.process,
  'jobs': CommandCategory.process,
  'wait': CommandCategory.process,
  'time': CommandCategory.process,
  'timeout': CommandCategory.process,
  'watch': CommandCategory.process,
  'xargs': CommandCategory.process,
  'parallel': CommandCategory.process,
  'lsof': CommandCategory.process,
  'strace': CommandCategory.process,
  'ltrace': CommandCategory.process,
  'pgrep': CommandCategory.process,

  // Search
  'grep': CommandCategory.search,
  'egrep': CommandCategory.search,
  'fgrep': CommandCategory.search,
  'rg': CommandCategory.search,
  'ag': CommandCategory.search,
  'ack': CommandCategory.search,
  'locate': CommandCategory.search,
  'which': CommandCategory.search,
  'whereis': CommandCategory.search,
  'type': CommandCategory.search,
  'fd': CommandCategory.search,

  // Shell
  'bash': CommandCategory.shell,
  'sh': CommandCategory.shell,
  'zsh': CommandCategory.shell,
  'fish': CommandCategory.shell,
  'dash': CommandCategory.shell,
  'ksh': CommandCategory.shell,
  'csh': CommandCategory.shell,
  'tcsh': CommandCategory.shell,
  'source': CommandCategory.shell,
  'exec': CommandCategory.shell,
  'eval': CommandCategory.shell,
  'export': CommandCategory.shell,
  'set': CommandCategory.shell,
  'unset': CommandCategory.shell,
  'alias': CommandCategory.shell,
  'unalias': CommandCategory.shell,
  'history': CommandCategory.shell,
  'env': CommandCategory.shell,
  'printenv': CommandCategory.shell,
  'true': CommandCategory.shell,
  'false': CommandCategory.shell,
  'echo': CommandCategory.shell,
  'printf': CommandCategory.shell,
  'read': CommandCategory.shell,
  'test': CommandCategory.shell,
  'cd': CommandCategory.shell,
  'pushd': CommandCategory.shell,
  'popd': CommandCategory.shell,
  'pwd': CommandCategory.shell,
  'dirs': CommandCategory.shell,
  'umask': CommandCategory.shell,

  // Docker
  'docker': CommandCategory.docker,
  'docker-compose': CommandCategory.docker,
  'podman': CommandCategory.docker,
  'kubectl': CommandCategory.docker,
  'helm': CommandCategory.docker,
  'minikube': CommandCategory.docker,

  // Database
  'psql': CommandCategory.database,
  'mysql': CommandCategory.database,
  'sqlite3': CommandCategory.database,
  'mongo': CommandCategory.database,
  'mongosh': CommandCategory.database,
  'redis-cli': CommandCategory.database,
  'redis-server': CommandCategory.database,
  'pg_dump': CommandCategory.database,
  'pg_restore': CommandCategory.database,
  'mysqldump': CommandCategory.database,

  // Testing
  'pytest': CommandCategory.testing,
  'jest': CommandCategory.testing,
  'mocha': CommandCategory.testing,
  'vitest': CommandCategory.testing,
  'phpunit': CommandCategory.testing,
  'rspec': CommandCategory.testing,
  'minitest': CommandCategory.testing,

  // Linting / formatting
  'eslint': CommandCategory.linting,
  'prettier': CommandCategory.linting,
  'black': CommandCategory.linting,
  'flake8': CommandCategory.linting,
  'pylint': CommandCategory.linting,
  'mypy': CommandCategory.linting,
  'rubocop': CommandCategory.linting,
  'shellcheck': CommandCategory.linting,
  'clippy': CommandCategory.linting,
  'rustfmt': CommandCategory.linting,
  'gofmt': CommandCategory.linting,
  'golint': CommandCategory.linting,
  'clang-format': CommandCategory.linting,
  'clang-tidy': CommandCategory.linting,
  'dartfmt': CommandCategory.linting,
  'dartanalyzer': CommandCategory.linting,
};

/// Classify a command into a [CommandCategory].
CommandCategory classifyCommand(String command) {
  final exe = extractExecutable(command);
  if (exe == null || exe.isEmpty) return CommandCategory.other;

  final baseName = exe.split('/').last;

  // Direct lookup.
  final cat = _categoryMap[baseName];
  if (cat != null) return cat;

  // Special sub-command patterns.
  if (baseName == 'cargo') {
    if (command.contains('test')) return CommandCategory.testing;
    if (command.contains('fmt') || command.contains('clippy')) {
      return CommandCategory.linting;
    }
    return CommandCategory.packageManager;
  }
  if (baseName == 'dart') {
    if (command.contains('analyze') || command.contains('format')) {
      return CommandCategory.linting;
    }
    if (command.contains('test')) return CommandCategory.testing;
    if (command.contains('pub')) return CommandCategory.packageManager;
    return CommandCategory.compiler;
  }
  if (baseName == 'flutter') {
    if (command.contains('test')) return CommandCategory.testing;
    if (command.contains('analyze')) return CommandCategory.linting;
    return CommandCategory.packageManager;
  }
  if (baseName == 'go') {
    if (command.contains('test')) return CommandCategory.testing;
    if (command.contains('vet') || command.contains('lint')) {
      return CommandCategory.linting;
    }
    return CommandCategory.packageManager;
  }
  if (baseName == 'npm' || baseName == 'yarn' || baseName == 'pnpm') {
    if (command.contains('test')) return CommandCategory.testing;
    if (command.contains('lint') || command.contains('format')) {
      return CommandCategory.linting;
    }
    return CommandCategory.packageManager;
  }

  return CommandCategory.other;
}

/// Extract the primary executable from a command string.
///
/// Handles `env` prefixes, `sudo`, `nice`, `time`, etc.
String? extractExecutable(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final commands = extractCommands(trimmed);
  if (commands.isEmpty) return null;

  final cmd = commands.first;
  var exe = cmd.executable;

  // Skip through env-prefix commands.
  const prefixCommands = {
    'env',
    'sudo',
    'nice',
    'nohup',
    'time',
    'timeout',
    'strace',
    'ltrace',
    'ionice',
    'chrt',
    'taskset',
    'numactl',
    'command',
    'builtin',
  };

  if (prefixCommands.contains(exe)) {
    // Skip any flags (starting with -).
    for (final arg in cmd.arguments) {
      if (!arg.startsWith('-')) {
        return arg.split('/').last;
      }
    }
  }

  // Skip env-var assignments that appear as the executable (shouldn't happen
  // after proper parsing, but be defensive).
  if (exe.contains('=') && !exe.startsWith('-')) {
    for (final arg in cmd.arguments) {
      if (!arg.contains('=') || arg.startsWith('-')) {
        return arg.split('/').last;
      }
    }
    return null;
  }

  return exe.split('/').last;
}

// ---------------------------------------------------------------------------
// Security analysis
// ---------------------------------------------------------------------------

/// Security analysis of a command.
class CommandSecurityAnalysis {
  final bool hasCommandSubstitution;
  final bool hasVariableExpansion;
  final bool hasGlobbing;
  final bool hasRedirection;
  final bool hasPiping;
  final bool hasBackgroundExec;
  final bool hasSubshell;
  final bool hasEval;
  final bool hasExec;
  final bool hasSudo;
  final bool hasChown;
  final bool hasRemove;
  final bool hasNetworkAccess;
  final bool hasDiskWrite;
  final List<String> writtenPaths;
  final List<String> readPaths;
  final List<String> executables;

  const CommandSecurityAnalysis({
    this.hasCommandSubstitution = false,
    this.hasVariableExpansion = false,
    this.hasGlobbing = false,
    this.hasRedirection = false,
    this.hasPiping = false,
    this.hasBackgroundExec = false,
    this.hasSubshell = false,
    this.hasEval = false,
    this.hasExec = false,
    this.hasSudo = false,
    this.hasChown = false,
    this.hasRemove = false,
    this.hasNetworkAccess = false,
    this.hasDiskWrite = false,
    this.writtenPaths = const [],
    this.readPaths = const [],
    this.executables = const [],
  });

  /// Compute the overall risk level.
  SecurityRiskLevel get riskLevel => computeRiskLevel(this);

  @override
  String toString() => 'CommandSecurityAnalysis(risk=${riskLevel.name})';
}

/// Risk level.
enum SecurityRiskLevel {
  safe,
  low,
  medium,
  high,
  critical;

  bool operator >(SecurityRiskLevel other) => index > other.index;
  bool operator >=(SecurityRiskLevel other) => index >= other.index;
  bool operator <(SecurityRiskLevel other) => index < other.index;
  bool operator <=(SecurityRiskLevel other) => index <= other.index;
}

const _networkExecutables = {
  'curl',
  'wget',
  'ssh',
  'scp',
  'sftp',
  'ftp',
  'nc',
  'netcat',
  'ncat',
  'ping',
  'telnet',
  'nmap',
  'socat',
  'openssl',
  'rsync',
};

const _writeCommands = {
  'tee',
  'dd',
  'install',
  'cp',
  'mv',
  'mkdir',
  'touch',
  'ln',
  'tar',
  'unzip',
  'gunzip',
  'patch',
};

const _readCommands = {
  'cat',
  'head',
  'tail',
  'less',
  'more',
  'file',
  'stat',
  'wc',
  'md5sum',
  'sha256sum',
  'xxd',
  'hexdump',
  'strings',
};

/// Analyze a command for security risks.
CommandSecurityAnalysis analyzeCommandSecurity(String input) {
  final tokens = tokenizeBash(input);
  final cmdList = parseCommand(input);
  final allCmds = cmdList.allCommands;

  var hasCommandSubstitution = false;
  var hasVariableExpansion = false;
  var hasGlobbing = false;
  var hasRedirection = false;
  var hasPiping = false;
  var hasBackgroundExec = false;
  var hasSubshell = false;
  var hasEval = false;
  var hasExec = false;
  var hasSudo = false;
  var hasChown = false;
  var hasRemove = false;
  var hasNetworkAccess = false;
  var hasDiskWrite = false;
  final writtenPaths = <String>[];
  final readPaths = <String>[];
  final executables = <String>[];

  // Token-level analysis.
  for (final t in tokens) {
    switch (t.type) {
      case BashTokenType.subshell:
        hasCommandSubstitution = true;
        hasSubshell = true;
        break;
      case BashTokenType.backtick:
        hasCommandSubstitution = true;
        break;
      case BashTokenType.variable:
        hasVariableExpansion = true;
        break;
      case BashTokenType.glob:
        hasGlobbing = true;
        break;
      case BashTokenType.redirect:
      case BashTokenType.heredocMarker:
        hasRedirection = true;
        break;
      case BashTokenType.pipe:
        hasPiping = true;
        break;
      case BashTokenType.background:
        hasBackgroundExec = true;
        break;
      case BashTokenType.lparen:
        hasSubshell = true;
        break;
      default:
        break;
    }
  }

  // Check for background in list operators.
  for (final entry in cmdList.entries) {
    if (entry.operator_ == ListOperator.background) {
      hasBackgroundExec = true;
    }
  }

  // Command-level analysis.
  for (final cmd in allCmds) {
    final exe = cmd.executable.split('/').last;
    if (exe.isNotEmpty) executables.add(exe);

    if (exe == 'eval') hasEval = true;
    if (exe == 'exec') hasExec = true;
    if (exe == 'sudo') hasSudo = true;
    if (exe == 'chown' || exe == 'chmod' || exe == 'chgrp') hasChown = true;
    if (exe == 'rm' || exe == 'rmdir' || exe == 'shred') hasRemove = true;
    if (_networkExecutables.contains(exe)) hasNetworkAccess = true;

    // Detect disk writes.
    if (_writeCommands.contains(exe) || exe == 'rm' || exe == 'rmdir') {
      hasDiskWrite = true;
      // Collect written paths from arguments.
      for (final arg in cmd.arguments) {
        if (!arg.startsWith('-') && !arg.startsWith('\$')) {
          writtenPaths.add(arg);
        }
      }
    }

    // Detect reads.
    if (_readCommands.contains(exe)) {
      for (final arg in cmd.arguments) {
        if (!arg.startsWith('-') && !arg.startsWith('\$')) {
          readPaths.add(arg);
        }
      }
    }

    // Redirections in the command.
    for (final redir in cmd.redirects) {
      hasRedirection = true;
      if (redir.type == RedirectType.output ||
          redir.type == RedirectType.append ||
          redir.type == RedirectType.both ||
          redir.type == RedirectType.errorOutput ||
          redir.type == RedirectType.errorAppend) {
        hasDiskWrite = true;
        if (redir.target.isNotEmpty && !redir.target.startsWith('\$')) {
          writtenPaths.add(redir.target);
        }
      }
      if (redir.type == RedirectType.input ||
          redir.type == RedirectType.inputOutput) {
        if (redir.target.isNotEmpty && !redir.target.startsWith('\$')) {
          readPaths.add(redir.target);
        }
      }
    }

    // Sudo elevates everything that follows.
    if (exe == 'sudo') {
      hasSudo = true;
      for (final arg in cmd.arguments) {
        if (!arg.startsWith('-')) {
          final sudoExe = arg.split('/').last;
          if (sudoExe == 'rm' || sudoExe == 'rmdir') hasRemove = true;
          if (sudoExe == 'chown' || sudoExe == 'chmod') hasChown = true;
          if (_networkExecutables.contains(sudoExe)) hasNetworkAccess = true;
          break;
        }
      }
    }
  }

  return CommandSecurityAnalysis(
    hasCommandSubstitution: hasCommandSubstitution,
    hasVariableExpansion: hasVariableExpansion,
    hasGlobbing: hasGlobbing,
    hasRedirection: hasRedirection,
    hasPiping: hasPiping,
    hasBackgroundExec: hasBackgroundExec,
    hasSubshell: hasSubshell,
    hasEval: hasEval,
    hasExec: hasExec,
    hasSudo: hasSudo,
    hasChown: hasChown,
    hasRemove: hasRemove,
    hasNetworkAccess: hasNetworkAccess,
    hasDiskWrite: hasDiskWrite,
    writtenPaths: writtenPaths,
    readPaths: readPaths,
    executables: executables,
  );
}

/// Compute risk level from analysis.
SecurityRiskLevel computeRiskLevel(CommandSecurityAnalysis a) {
  // Critical: sudo + remove, eval with substitution, fork bombs.
  if (a.hasSudo && a.hasRemove) return SecurityRiskLevel.critical;
  if (a.hasEval && a.hasCommandSubstitution) return SecurityRiskLevel.critical;
  if (a.hasSudo && a.hasChown) return SecurityRiskLevel.critical;

  // High: sudo, eval, exec, remove with glob.
  if (a.hasSudo) return SecurityRiskLevel.high;
  if (a.hasEval) return SecurityRiskLevel.high;
  if (a.hasExec) return SecurityRiskLevel.high;
  if (a.hasRemove && a.hasGlobbing) return SecurityRiskLevel.high;
  if (a.hasRemove &&
      a.writtenPaths.any((p) => p == '/' || p == '~' || p.startsWith('/'))) {
    return SecurityRiskLevel.high;
  }

  // Medium: network access, disk writes with variable expansion, command
  // substitution, remove.
  if (a.hasNetworkAccess) return SecurityRiskLevel.medium;
  if (a.hasDiskWrite && a.hasVariableExpansion) return SecurityRiskLevel.medium;
  if (a.hasCommandSubstitution) return SecurityRiskLevel.medium;
  if (a.hasRemove) return SecurityRiskLevel.medium;
  if (a.hasChown) return SecurityRiskLevel.medium;

  // Low: disk writes, redirections, backgrounding, piping.
  if (a.hasDiskWrite) return SecurityRiskLevel.low;
  if (a.hasRedirection) return SecurityRiskLevel.low;
  if (a.hasBackgroundExec) return SecurityRiskLevel.low;
  if (a.hasSubshell) return SecurityRiskLevel.low;

  // Safe: read-only commands, piping between safe commands.
  if (a.hasPiping) return SecurityRiskLevel.low;
  if (a.hasGlobbing) return SecurityRiskLevel.low;

  return SecurityRiskLevel.safe;
}

// ---------------------------------------------------------------------------
// Assignment handling
// ---------------------------------------------------------------------------

/// Parsed variable assignment (name=value).
class AssignmentParts {
  final String name;
  final String value;
  const AssignmentParts(this.name, this.value);

  @override
  String toString() => 'AssignmentParts($name=$value)';
}

/// Validate environment variable assignments.
bool isValidAssignment(String assignment) {
  return parseAssignment(assignment) != null;
}

/// Parse environment variable name and value from an assignment string.
AssignmentParts? parseAssignment(String assignment) {
  final eqIdx = assignment.indexOf('=');
  if (eqIdx <= 0) return null;

  final name = assignment.substring(0, eqIdx);
  if (!_isValidVarName(name)) return null;

  final value = assignment.substring(eqIdx + 1);
  return AssignmentParts(name, value);
}

// ---------------------------------------------------------------------------
// Shell quoting
// ---------------------------------------------------------------------------

/// Quote a string for safe shell usage.
///
/// Uses single quotes by default. If the string contains single quotes,
/// uses the `$'...'` ANSI-C quoting form. If the string is a simple
/// alphanumeric/dash/underscore string, returns it unquoted.
String shellQuote(String input) {
  if (input.isEmpty) return "''";

  // Check if quoting is needed at all.
  if (RegExp(r'^[a-zA-Z0-9._/=:@%^,+-]+$').hasMatch(input)) {
    return input;
  }

  // If no single quotes, wrap in single quotes.
  if (!input.contains("'")) {
    return "'$input'";
  }

  // Use $'...' form for strings with single quotes.
  final escaped = input
      .replaceAll('\\', '\\\\')
      .replaceAll("'", "\\'")
      .replaceAll('\n', '\\n')
      .replaceAll('\t', '\\t')
      .replaceAll('\r', '\\r')
      .replaceAll('\x07', '\\a')
      .replaceAll('\b', '\\b')
      .replaceAll('\x1B', '\\e');
  return "\$'$escaped'";
}

/// Quote a list of arguments and join them with spaces.
String shellQuoteArgs(List<String> args) {
  return args.map(shellQuote).join(' ');
}

// ---------------------------------------------------------------------------
// Pattern detection
// ---------------------------------------------------------------------------

/// Detect if a command uses process substitution `<()` or `>()`.
bool hasProcessSubstitution(String command) {
  return RegExp(r'[<>]\(').hasMatch(command);
}

/// Detect dangerous patterns in a command and return descriptions of each.
List<String> detectDangerousPatterns(String command) {
  final patterns = <String>[];

  // Fork bomb: :(){ :|:& };:
  if (RegExp(r':\(\)\s*\{.*:\|:.*\}').hasMatch(command) ||
      command.contains(':(){ :|:& };:')) {
    patterns.add('Fork bomb detected');
  }

  // Infinite loops writing to disk.
  if (RegExp(r'while\s+(true|1|:)').hasMatch(command) &&
      command.contains('>')) {
    patterns.add('Potential infinite loop with disk write');
  }

  // /dev/sda or raw disk access.
  if (RegExp(r'/dev/[sh]d[a-z]').hasMatch(command)) {
    patterns.add('Raw disk device access');
  }

  // dd with of=/dev.
  if (command.contains('dd ') && RegExp(r'of=/dev/').hasMatch(command)) {
    patterns.add('Direct device write with dd');
  }

  // rm -rf / or rm -rf ~.
  if (RegExp(
    r'rm\s+(-[a-zA-Z]*r[a-zA-Z]*f|(-[a-zA-Z]*f[a-zA-Z]*r))\s+[/~]',
  ).hasMatch(command)) {
    patterns.add('Recursive force removal of root or home');
  }

  // chmod 777 on sensitive paths.
  if (RegExp(r'chmod\s+777\s+/').hasMatch(command)) {
    patterns.add('World-writable permissions on system path');
  }

  // curl | bash or wget | bash.
  if (RegExp(r'(curl|wget)\s.*\|\s*(ba)?sh').hasMatch(command)) {
    patterns.add('Piping remote script to shell');
  }

  // eval with user input or variable expansion.
  if (RegExp(r'eval\s+.*\$').hasMatch(command)) {
    patterns.add('eval with variable expansion');
  }

  // mkfs — formatting a filesystem.
  if (command.contains('mkfs')) {
    patterns.add('Filesystem format command');
  }

  // Overwriting /etc/passwd, /etc/shadow.
  if (RegExp(r'>\s*/etc/(passwd|shadow|sudoers)').hasMatch(command)) {
    patterns.add('Overwriting critical system file');
  }

  // Disabling firewall.
  if (RegExp(
    r'(ufw\s+disable|iptables\s+-F|firewall-cmd\s+--panic-off)',
  ).hasMatch(command)) {
    patterns.add('Firewall disable command');
  }

  // history -c or removing bash_history.
  if (command.contains('history -c') ||
      command.contains('.bash_history') ||
      command.contains('.zsh_history')) {
    patterns.add('Shell history manipulation');
  }

  // Reverse shell patterns.
  if (RegExp(r'bash\s+-i\s+>&?\s*/dev/tcp/').hasMatch(command) ||
      RegExp(r'nc\s.*-[el].*\d+').hasMatch(command) ||
      command.contains('/dev/tcp/')) {
    patterns.add('Potential reverse shell');
  }

  // Base64 decode and execute.
  if (RegExp(r'base64\s+-d.*\|\s*(ba)?sh').hasMatch(command) ||
      RegExp(r'echo\s.*\|\s*base64\s+-d\s*\|\s*(ba)?sh').hasMatch(command)) {
    patterns.add('Base64 decode piped to shell');
  }

  // Crontab manipulation.
  if (RegExp(r'crontab\s+-r').hasMatch(command)) {
    patterns.add('Crontab removal');
  }

  // Disk fill: yes > file, /dev/zero > file.
  if (RegExp(r'(yes|/dev/zero)\s*>\s*').hasMatch(command)) {
    patterns.add('Potential disk fill');
  }

  return patterns;
}

// ---------------------------------------------------------------------------
// ANSI stripping and output truncation
// ---------------------------------------------------------------------------

/// Strip ANSI escape codes from output.
String stripAnsiCodes(String input) {
  // Matches: ESC[ ... m (SGR), ESC[ ... H/J/K (cursor/erase),
  // ESC] ... ST (OSC), and other common escape sequences.
  return input
      .replaceAll(RegExp(r'\x1B\[[0-9;]*[A-Za-z]'), '') // CSI sequences
      .replaceAll(
        RegExp(r'\x1B\][^\x07\x1B]*(\x07|\x1B\\)'),
        '',
      ) // OSC sequences
      .replaceAll(RegExp(r'\x1B[()][AB012]'), '') // Character set selection
      .replaceAll(RegExp(r'\x1B[>=<]'), '') // Keypad mode
      .replaceAll(RegExp(r'\x1B\[[\?]?[0-9;]*[hlsr]'), '') // Mode set/reset
      .replaceAll(RegExp(r'\x1B[78DMEHc]'), '') // Single-char escapes
      .replaceAll(RegExp(r'\x1B\[\d*[ABCDEFGH]'), ''); // Remaining cursor moves
}

/// Truncate command output to a maximum number of lines and/or characters.
///
/// Inserts a `[truncated]` marker if truncation occurs.
String truncateOutput(
  String output, {
  int maxLines = 1000,
  int maxChars = 100000,
}) {
  var result = output;
  var truncated = false;

  // Truncate by character count first.
  if (result.length > maxChars) {
    result = result.substring(0, maxChars);
    truncated = true;
  }

  // Truncate by line count.
  final lines = result.split('\n');
  if (lines.length > maxLines) {
    final kept = maxLines ~/ 2;
    final headLines = lines.sublist(0, kept);
    final tailLines = lines.sublist(lines.length - kept);
    final omitted = lines.length - (kept * 2);
    result = [
      ...headLines,
      '\n... [$omitted lines truncated] ...\n',
      ...tailLines,
    ].join('\n');
    truncated = true;
  } else if (truncated) {
    result += '\n[truncated at $maxChars characters]';
  }

  return result;
}

// ---------------------------------------------------------------------------
// Exit code interpretation
// ---------------------------------------------------------------------------

/// Provide a semantic interpretation of an exit code for a given command.
String interpretExitCode(int exitCode, String command) {
  if (exitCode == 0) return 'Success';

  final exe = extractExecutable(command) ?? '';

  // General signals.
  if (exitCode >= 128) {
    final signal = exitCode - 128;
    final signalNames = <int, String>{
      1: 'SIGHUP (hangup)',
      2: 'SIGINT (interrupt / Ctrl+C)',
      3: 'SIGQUIT (quit)',
      6: 'SIGABRT (abort)',
      9: 'SIGKILL (killed)',
      11: 'SIGSEGV (segmentation fault)',
      13: 'SIGPIPE (broken pipe)',
      14: 'SIGALRM (alarm)',
      15: 'SIGTERM (terminated)',
    };
    final name = signalNames[signal] ?? 'signal $signal';
    return 'Killed by $name (exit code $exitCode)';
  }

  // Command-specific codes.
  switch (exe) {
    case 'grep':
    case 'egrep':
    case 'fgrep':
    case 'rg':
    case 'ag':
      if (exitCode == 1) return 'No matches found';
      if (exitCode == 2) return 'Syntax error or inaccessible file';
      break;
    case 'diff':
      if (exitCode == 1) return 'Files differ';
      if (exitCode == 2) {
        return 'Trouble (missing file, permission denied, etc.)';
      }
      break;
    case 'test':
    case '[':
      if (exitCode == 1) return 'Condition evaluated to false';
      break;
    case 'curl':
      if (exitCode == 6) return 'Could not resolve host';
      if (exitCode == 7) return 'Failed to connect';
      if (exitCode == 22) return 'HTTP error (4xx or 5xx)';
      if (exitCode == 28) return 'Operation timed out';
      if (exitCode == 35) return 'SSL/TLS connection error';
      if (exitCode == 56) return 'Failure in receiving network data';
      break;
    case 'wget':
      if (exitCode == 1) return 'Generic error';
      if (exitCode == 4) return 'Network failure';
      if (exitCode == 8) return 'Server issued an error response';
      break;
    case 'ssh':
    case 'scp':
      if (exitCode == 255) return 'SSH connection failure';
      break;
    case 'git':
      if (exitCode == 1) {
        return 'Git operation failed (check output for details)';
      }
      if (exitCode == 128) return 'Fatal git error';
      break;
    case 'make':
      if (exitCode == 2) return 'Make encountered errors';
      break;
    case 'gcc':
    case 'g++':
    case 'clang':
    case 'clang++':
    case 'rustc':
    case 'javac':
    case 'tsc':
      if (exitCode == 1) return 'Compilation error';
      break;
    case 'python':
    case 'python3':
    case 'node':
    case 'ruby':
    case 'perl':
      if (exitCode == 1) return 'Runtime error or unhandled exception';
      if (exitCode == 2) return 'Misuse of command (invalid arguments)';
      break;
    case 'npm':
    case 'yarn':
    case 'pnpm':
      if (exitCode == 1) return 'Operation failed (check output)';
      break;
    case 'docker':
      if (exitCode == 1) return 'Docker command failed';
      if (exitCode == 125) return 'Docker daemon error';
      if (exitCode == 126) {
        return 'Command cannot be invoked (permission issue)';
      }
      if (exitCode == 127) return 'Command not found in container';
      break;
  }

  // Generic interpretations.
  switch (exitCode) {
    case 1:
      return 'General error';
    case 2:
      return 'Misuse of shell command (invalid arguments or syntax)';
    case 126:
      return 'Command found but not executable (permission denied)';
    case 127:
      return 'Command not found';
    default:
      return 'Non-zero exit code: $exitCode';
  }
}

// ---------------------------------------------------------------------------
// Directory-changing command detection
// ---------------------------------------------------------------------------

/// Check if a command modifies the working directory.
bool isDirectoryChangingCommand(String command) {
  final exe = extractExecutable(command);
  if (exe == null) return false;
  return exe == 'cd' || exe == 'pushd' || exe == 'popd';
}

/// Extract the target directory from a `cd` command.
///
/// Returns `null` if the command is not a cd, or if no target is given
/// (bare `cd` goes to `$HOME`).
String? extractCdTarget(String command) {
  final cmds = extractCommands(command);
  if (cmds.isEmpty) return null;

  final cmd = cmds.first;
  final exe = cmd.executable.split('/').last;

  if (exe != 'cd' && exe != 'pushd') return null;

  // Collect first non-flag argument.
  for (final arg in cmd.arguments) {
    if (!arg.startsWith('-')) {
      return arg;
    }
  }

  // Bare cd with no args means $HOME.
  if (exe == 'cd') return '~';

  return null;
}
