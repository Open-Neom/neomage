// Syntax highlighting — port of neomage native-ts/color-diff + utils/cliHighlight.
// Provides token-based syntax highlighting for code blocks.
// Uses a lightweight rule-based highlighter (no native module dependency).

import 'package:flutter/material.dart';

/// A highlighted text span.
class HighlightSpan {
  final String text;
  final HighlightTokenType type;

  const HighlightSpan(this.text, this.type);
}

/// Token types for syntax coloring.
enum HighlightTokenType {
  plain,
  keyword,
  string,
  comment,
  number,
  operator,
  punctuation,
  type,
  function_,
  variable,
  constant,
  annotation,
  tag,
  attribute,
}

/// Language detection from file extension or code fence.
String detectLanguage(String hint) {
  final lower = hint.toLowerCase().trim();

  return switch (lower) {
    'js' || 'jsx' || 'javascript' => 'javascript',
    'ts' || 'tsx' || 'typescript' => 'typescript',
    'dart' => 'dart',
    'py' || 'python' => 'python',
    'rb' || 'ruby' => 'ruby',
    'rs' || 'rust' => 'rust',
    'go' || 'golang' => 'go',
    'java' => 'java',
    'kt' || 'kotlin' => 'kotlin',
    'swift' => 'swift',
    'c' || 'h' => 'c',
    'cpp' || 'cc' || 'cxx' || 'hpp' => 'cpp',
    'cs' || 'csharp' => 'csharp',
    'php' => 'php',
    'sh' || 'bash' || 'zsh' || 'shell' => 'shell',
    'sql' => 'sql',
    'html' || 'htm' => 'html',
    'css' || 'scss' || 'sass' => 'css',
    'json' => 'json',
    'yaml' || 'yml' => 'yaml',
    'xml' => 'xml',
    'md' || 'markdown' => 'markdown',
    'toml' => 'toml',
    'dockerfile' => 'dockerfile',
    _ => 'plaintext',
  };
}

/// Detect language from file path.
String detectLanguageFromPath(String path) {
  final ext = path.contains('.') ? path.split('.').last : '';
  return detectLanguage(ext);
}

/// Tokenize source code into highlighted spans.
/// Uses a rule-based approach — not a full parser, but good enough
/// for display purposes.
List<HighlightSpan> tokenize(String code, String language) {
  if (language == 'plaintext') {
    return [HighlightSpan(code, HighlightTokenType.plain)];
  }

  final rules = _getRules(language);
  if (rules.isEmpty) {
    return [HighlightSpan(code, HighlightTokenType.plain)];
  }

  final spans = <HighlightSpan>[];
  var lastIndex = 0;
  var i = 0;

  while (i < code.length) {
    HighlightTokenType? matchType;
    String? matchText;

    for (final rule in rules) {
      final match = rule.pattern.matchAsPrefix(code, i);
      if (match != null && match.end > i) {
        matchType = rule.type;
        matchText = match[0]!;
        break;
      }
    }

    if (matchType != null && matchText != null) {
      // Emit plain text before this match
      if (i > lastIndex) {
        spans.add(
          HighlightSpan(code.substring(lastIndex, i), HighlightTokenType.plain),
        );
      }
      spans.add(HighlightSpan(matchText, matchType));
      i += matchText.length;
      lastIndex = i;
    } else {
      i++;
    }
  }

  // Remaining plain text
  if (lastIndex < code.length) {
    spans.add(
      HighlightSpan(code.substring(lastIndex), HighlightTokenType.plain),
    );
  }

  return spans;
}

/// Syntax highlight color theme.
class SyntaxColors {
  final Color plain;
  final Color keyword;
  final Color string;
  final Color comment;
  final Color number;
  final Color operator_;
  final Color punctuation;
  final Color type;
  final Color function_;
  final Color variable;
  final Color constant;
  final Color annotation;
  final Color tag;
  final Color attribute;

  const SyntaxColors({
    this.plain = const Color(0xFFD4D4D4),
    this.keyword = const Color(0xFFC586C0),
    this.string = const Color(0xFFCE9178),
    this.comment = const Color(0xFF6A9955),
    this.number = const Color(0xFFB5CEA8),
    this.operator_ = const Color(0xFFD4D4D4),
    this.punctuation = const Color(0xFF808080),
    this.type = const Color(0xFF4EC9B0),
    this.function_ = const Color(0xFFDCDCAA),
    this.variable = const Color(0xFF9CDCFE),
    this.constant = const Color(0xFF4FC1FF),
    this.annotation = const Color(0xFFD7BA7D),
    this.tag = const Color(0xFF569CD6),
    this.attribute = const Color(0xFF9CDCFE),
  });

  factory SyntaxColors.light() => const SyntaxColors(
    plain: Color(0xFF333333),
    keyword: Color(0xFFAF00DB),
    string: Color(0xFFA31515),
    comment: Color(0xFF008000),
    number: Color(0xFF098658),
    operator_: Color(0xFF333333),
    punctuation: Color(0xFF666666),
    type: Color(0xFF267F99),
    function_: Color(0xFF795E26),
    variable: Color(0xFF001080),
    constant: Color(0xFF0070C1),
    annotation: Color(0xFF808000),
    tag: Color(0xFF800000),
    attribute: Color(0xFFFF0000),
  );

  Color colorFor(HighlightTokenType type) => switch (type) {
    HighlightTokenType.plain => plain,
    HighlightTokenType.keyword => keyword,
    HighlightTokenType.string => string,
    HighlightTokenType.comment => comment,
    HighlightTokenType.number => number,
    HighlightTokenType.operator => operator_,
    HighlightTokenType.punctuation => punctuation,
    HighlightTokenType.type => this.type,
    HighlightTokenType.function_ => function_,
    HighlightTokenType.variable => variable,
    HighlightTokenType.constant => constant,
    HighlightTokenType.annotation => annotation,
    HighlightTokenType.tag => tag,
    HighlightTokenType.attribute => attribute,
  };
}

/// Widget that renders syntax-highlighted code.
class SyntaxHighlightView extends StatelessWidget {
  final String code;
  final String language;
  final SyntaxColors? colors;
  final TextStyle? baseStyle;
  final bool showLineNumbers;
  final int startLine;

  const SyntaxHighlightView({
    super.key,
    required this.code,
    this.language = 'plaintext',
    this.colors,
    this.baseStyle,
    this.showLineNumbers = true,
    this.startLine = 1,
  });

  @override
  Widget build(BuildContext context) {
    final theme =
        colors ??
        (Theme.of(context).brightness == Brightness.dark
            ? const SyntaxColors()
            : SyntaxColors.light());

    final style =
        baseStyle ??
        TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          height: 1.5,
          color: theme.plain,
        );

    final lines = code.split('\n');
    final gutterWidth = (startLine + lines.length - 1).toString().length;

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            _buildLine(lines[i], i + startLine, gutterWidth, theme, style),
        ],
      ),
    );
  }

  Widget _buildLine(
    String line,
    int lineNumber,
    int gutterWidth,
    SyntaxColors theme,
    TextStyle style,
  ) {
    final spans = tokenize(line, language);
    final textSpans = spans.map((s) {
      return TextSpan(
        text: s.text,
        style: style.copyWith(color: theme.colorFor(s.type)),
      );
    }).toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showLineNumbers)
          Container(
            width: gutterWidth * 8.0 + 16,
            padding: const EdgeInsets.only(right: 8),
            alignment: Alignment.centerRight,
            child: Text(
              lineNumber.toString(),
              style: style.copyWith(
                color: theme.plain.withAlpha(102),
                fontSize: 12,
              ),
            ),
          ),
        Expanded(
          child: RichText(text: TextSpan(children: textSpans), softWrap: true),
        ),
      ],
    );
  }
}

// ── Tokenization Rules ──

class _Rule {
  final Pattern pattern;
  final HighlightTokenType type;
  const _Rule(this.pattern, this.type);
}

List<_Rule> _getRules(String language) {
  // Shared rules for C-family languages
  final cFamilyRules = [
    _Rule(RegExp(r'//[^\n]*'), HighlightTokenType.comment),
    _Rule(RegExp(r'/\*[\s\S]*?\*/'), HighlightTokenType.comment),
    _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
    _Rule(RegExp(r"'(?:[^'\\]|\\.)'"), HighlightTokenType.string),
    _Rule(RegExp(r'\b\d+\.?\d*([eE][+-]?\d+)?\b'), HighlightTokenType.number),
    _Rule(RegExp(r'[{}()\[\];,.]'), HighlightTokenType.punctuation),
    _Rule(RegExp(r'[+\-*/%=<>!&|^~?:]'), HighlightTokenType.operator),
  ];

  return switch (language) {
    'dart' => [
      ...cFamilyRules,
      _Rule(
        RegExp(
          r'\b(abstract|as|assert|async|await|break|case|catch|class|const|'
          r'continue|covariant|default|deferred|do|dynamic|else|enum|export|'
          r'extends|extension|external|factory|false|final|finally|for|'
          r'Function|get|hide|if|implements|import|in|interface|is|late|'
          r'library|mixin|new|null|on|operator|part|required|rethrow|return|'
          r'sealed|set|show|static|super|switch|sync|this|throw|true|try|'
          r'typedef|var|void|when|while|with|yield)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(RegExp(r"r'(?:[^'\\]|\\.)*'"), HighlightTokenType.string),
      _Rule(RegExp(r'r"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'''[\s\S]*?'''"), HighlightTokenType.string),
      _Rule(RegExp(r'"""[\s\S]*?"""'), HighlightTokenType.string),
      _Rule(RegExp(r'@\w+'), HighlightTokenType.annotation),
      _Rule(RegExp(r'\b[A-Z][a-zA-Z0-9]*\b'), HighlightTokenType.type),
    ],
    'javascript' || 'typescript' => [
      ...cFamilyRules,
      _Rule(
        RegExp(
          r'\b(abstract|any|as|async|await|boolean|break|case|catch|class|'
          r'const|constructor|continue|debugger|declare|default|delete|do|'
          r'else|enum|export|extends|false|finally|for|from|function|get|'
          r'if|implements|import|in|infer|instanceof|interface|keyof|let|'
          r'module|namespace|never|new|null|number|object|of|package|'
          r'private|protected|public|readonly|return|set|static|string|'
          r'super|switch|symbol|this|throw|true|try|type|typeof|undefined|'
          r'unique|unknown|var|void|while|with|yield)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(RegExp(r'`(?:[^`\\]|\\.)*`'), HighlightTokenType.string),
      _Rule(RegExp(r'\b[A-Z][a-zA-Z0-9]*\b'), HighlightTokenType.type),
    ],
    'python' => [
      _Rule(RegExp(r'#[^\n]*'), HighlightTokenType.comment),
      _Rule(RegExp(r'"""[\s\S]*?"""'), HighlightTokenType.string),
      _Rule(RegExp(r"'''[\s\S]*?'''"), HighlightTokenType.string),
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'(?:[^'\\]|\\.)*'"), HighlightTokenType.string),
      _Rule(RegExp(r'[fb]?"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(
        RegExp(
          r'\b(and|as|assert|async|await|break|class|continue|def|del|'
          r'elif|else|except|False|finally|for|from|global|if|import|in|'
          r'is|lambda|None|nonlocal|not|or|pass|raise|return|True|try|'
          r'while|with|yield)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(RegExp(r'\b\d+\.?\d*([eE][+-]?\d+)?\b'), HighlightTokenType.number),
      _Rule(RegExp(r'@\w+'), HighlightTokenType.annotation),
      _Rule(RegExp(r'\b[A-Z][a-zA-Z0-9]*\b'), HighlightTokenType.type),
      _Rule(RegExp(r'[{}()\[\];,.]'), HighlightTokenType.punctuation),
      _Rule(RegExp(r'[+\-*/%=<>!&|^~?:]'), HighlightTokenType.operator),
    ],
    'go' => [
      ...cFamilyRules,
      _Rule(RegExp(r'`[^`]*`'), HighlightTokenType.string),
      _Rule(
        RegExp(
          r'\b(break|case|chan|const|continue|default|defer|else|'
          r'fallthrough|for|func|go|goto|if|import|interface|map|'
          r'package|range|return|select|struct|switch|type|var)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(
        RegExp(
          r'\b(bool|byte|complex64|complex128|error|float32|float64|'
          r'int|int8|int16|int32|int64|rune|string|uint|uint8|uint16|'
          r'uint32|uint64|uintptr|any)\b',
        ),
        HighlightTokenType.type,
      ),
      _Rule(RegExp(r'\b(true|false|nil|iota)\b'), HighlightTokenType.constant),
    ],
    'rust' => [
      ...cFamilyRules,
      _Rule(
        RegExp(
          r'\b(as|async|await|break|const|continue|crate|dyn|else|enum|'
          r'extern|false|fn|for|if|impl|in|let|loop|match|mod|move|mut|'
          r'pub|ref|return|self|Self|static|struct|super|trait|true|type|'
          r'unsafe|use|where|while|yield)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(
        RegExp(
          r'\b(i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize|'
          r'f32|f64|bool|char|str|String|Vec|Option|Result|Box|Rc|Arc)\b',
        ),
        HighlightTokenType.type,
      ),
      _Rule(RegExp(r'#\[[\s\S]*?\]'), HighlightTokenType.annotation),
    ],
    'shell' || 'bash' => [
      _Rule(RegExp(r'#[^\n]*'), HighlightTokenType.comment),
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'[^']*'"), HighlightTokenType.string),
      _Rule(
        RegExp(
          r'\b(if|then|else|elif|fi|for|while|do|done|case|esac|in|'
          r'function|return|exit|local|export|source|alias|unset|'
          r'readonly|declare|typeset|eval|exec|set|shift|trap)\b',
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(RegExp(r'\$\{?\w+\}?'), HighlightTokenType.variable),
      _Rule(RegExp(r'\b\d+\b'), HighlightTokenType.number),
      _Rule(RegExp(r'[|&;><()]'), HighlightTokenType.operator),
    ],
    'json' => [
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"\s*(?=:)'), HighlightTokenType.variable),
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r'\b\d+\.?\d*([eE][+-]?\d+)?\b'), HighlightTokenType.number),
      _Rule(RegExp(r'\b(true|false|null)\b'), HighlightTokenType.constant),
      _Rule(RegExp(r'[{}()\[\],:]'), HighlightTokenType.punctuation),
    ],
    'yaml' => [
      _Rule(RegExp(r'#[^\n]*'), HighlightTokenType.comment),
      _Rule(
        RegExp(r'^[\w.-]+(?=\s*:)', multiLine: true),
        HighlightTokenType.variable,
      ),
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'[^']*'"), HighlightTokenType.string),
      _Rule(
        RegExp(r'\b(true|false|null|yes|no|on|off)\b', caseSensitive: false),
        HighlightTokenType.constant,
      ),
      _Rule(RegExp(r'\b\d+\.?\d*\b'), HighlightTokenType.number),
      _Rule(RegExp(r'[:\-|>]'), HighlightTokenType.operator),
    ],
    'sql' => [
      _Rule(RegExp(r'--[^\n]*'), HighlightTokenType.comment),
      _Rule(RegExp(r'/\*[\s\S]*?\*/'), HighlightTokenType.comment),
      _Rule(RegExp(r"'(?:[^'\\]|\\.)*'"), HighlightTokenType.string),
      _Rule(
        RegExp(
          r'\b(SELECT|FROM|WHERE|AND|OR|NOT|IN|INSERT|INTO|VALUES|UPDATE|'
          r'SET|DELETE|CREATE|DROP|ALTER|TABLE|INDEX|VIEW|JOIN|LEFT|RIGHT|'
          r'INNER|OUTER|ON|AS|IS|NULL|LIKE|ORDER|BY|GROUP|HAVING|LIMIT|'
          r'OFFSET|UNION|ALL|DISTINCT|EXISTS|BETWEEN|CASE|WHEN|THEN|'
          r'ELSE|END|BEGIN|COMMIT|ROLLBACK|GRANT|REVOKE|PRIMARY|KEY|'
          r'FOREIGN|REFERENCES|CONSTRAINT|DEFAULT|CHECK|UNIQUE|NOT|'
          r'AUTO_INCREMENT|CASCADE)\b',
          caseSensitive: false,
        ),
        HighlightTokenType.keyword,
      ),
      _Rule(RegExp(r'\b\d+\.?\d*\b'), HighlightTokenType.number),
      _Rule(RegExp(r'[();,.*=<>!]'), HighlightTokenType.punctuation),
    ],
    'html' || 'xml' => [
      _Rule(RegExp(r'<!--[\s\S]*?-->'), HighlightTokenType.comment),
      _Rule(RegExp(r'</?[\w:-]+'), HighlightTokenType.tag),
      _Rule(RegExp(r'/?>'), HighlightTokenType.tag),
      _Rule(RegExp(r'\b[\w:-]+(?==)'), HighlightTokenType.attribute),
      _Rule(RegExp(r'"[^"]*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'[^']*'"), HighlightTokenType.string),
    ],
    'css' || 'scss' => [
      _Rule(RegExp(r'/\*[\s\S]*?\*/'), HighlightTokenType.comment),
      _Rule(RegExp(r'//[^\n]*'), HighlightTokenType.comment),
      _Rule(RegExp(r'"(?:[^"\\]|\\.)*"'), HighlightTokenType.string),
      _Rule(RegExp(r"'(?:[^'\\]|\\.)*'"), HighlightTokenType.string),
      _Rule(RegExp(r'#[0-9a-fA-F]{3,8}\b'), HighlightTokenType.number),
      _Rule(
        RegExp(r'\b\d+\.?\d*(px|em|rem|%|vh|vw|s|ms)?\b'),
        HighlightTokenType.number,
      ),
      _Rule(RegExp(r'[{}();:,]'), HighlightTokenType.punctuation),
      _Rule(RegExp(r'\$[\w-]+'), HighlightTokenType.variable),
      _Rule(RegExp(r'@[\w-]+'), HighlightTokenType.annotation),
    ],
    _ => [],
  };
}
