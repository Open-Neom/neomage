import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ---------------------------------------------------------------------------
// Theme
// ---------------------------------------------------------------------------

/// Colour and style configuration for markdown rendering.
class MarkdownTheme {
  const MarkdownTheme({
    this.headingColor = Colors.white,
    this.bodyColor = const Color(0xFFD4D4D4),
    this.codeBackground = const Color(0xFF1E1E1E),
    this.codeColor = const Color(0xFFCE9178),
    this.inlineCodeBackground = const Color(0xFF2D2D2D),
    this.inlineCodeColor = const Color(0xFFCE9178),
    this.linkColor = const Color(0xFF4FC3F7),
    this.blockquoteBorder = const Color(0xFF616161),
    this.blockquoteBackground = const Color(0xFF1A1A1A),
    this.tableBorder = const Color(0xFF424242),
    this.tableHeaderBackground = const Color(0xFF2D2D2D),
    this.hrColor = const Color(0xFF424242),
    this.noteColor = const Color(0xFF4FC3F7),
    this.warningColor = const Color(0xFFFFB74D),
    this.tipColor = const Color(0xFF81C784),
    this.cautionColor = const Color(0xFFE57373),
    this.importantColor = const Color(0xFFBA68C8),
  });

  final Color headingColor;
  final Color bodyColor;
  final Color codeBackground;
  final Color codeColor;
  final Color inlineCodeBackground;
  final Color inlineCodeColor;
  final Color linkColor;
  final Color blockquoteBorder;
  final Color blockquoteBackground;
  final Color tableBorder;
  final Color tableHeaderBackground;
  final Color hrColor;
  final Color noteColor;
  final Color warningColor;
  final Color tipColor;
  final Color cautionColor;
  final Color importantColor;
}

// ---------------------------------------------------------------------------
// AST node types (sealed class hierarchy)
// ---------------------------------------------------------------------------

sealed class _MarkdownNode {}

class _TextNode extends _MarkdownNode {
  _TextNode(this.text);
  final String text;
}

class _BoldNode extends _MarkdownNode {
  _BoldNode(this.children);
  final List<_MarkdownNode> children;
}

class _ItalicNode extends _MarkdownNode {
  _ItalicNode(this.children);
  final List<_MarkdownNode> children;
}

class _StrikethroughNode extends _MarkdownNode {
  _StrikethroughNode(this.children);
  final List<_MarkdownNode> children;
}

class _InlineCodeNode extends _MarkdownNode {
  _InlineCodeNode(this.code);
  final String code;
}

class _LinkNode extends _MarkdownNode {
  _LinkNode(this.text, this.url);
  final String text;
  final String url;
}

class _ImageNode extends _MarkdownNode {
  _ImageNode(this.alt, this.url);
  final String alt;
  final String url;
}

class _HeadingNode extends _MarkdownNode {
  _HeadingNode(this.level, this.children);
  final int level; // 1-6
  final List<_MarkdownNode> children;
}

class _ParagraphNode extends _MarkdownNode {
  _ParagraphNode(this.children);
  final List<_MarkdownNode> children;
}

class _CodeBlockNode extends _MarkdownNode {
  _CodeBlockNode(this.code, this.language);
  final String code;
  final String? language;
}

class _BlockquoteNode extends _MarkdownNode {
  _BlockquoteNode(this.children);
  final List<_MarkdownNode> children;
}

class _AdmonitionNode extends _MarkdownNode {
  _AdmonitionNode(this.kind, this.children);
  final String kind; // NOTE, WARNING, TIP, CAUTION, IMPORTANT
  final List<_MarkdownNode> children;
}

class _OrderedListNode extends _MarkdownNode {
  _OrderedListNode(this.items);
  final List<_ListItemNode> items;
}

class _UnorderedListNode extends _MarkdownNode {
  _UnorderedListNode(this.items);
  final List<_ListItemNode> items;
}

class _ListItemNode extends _MarkdownNode {
  _ListItemNode(this.children, {this.checked, this.sublist});
  final List<_MarkdownNode> children;
  final bool? checked; // null = not a task item
  final _MarkdownNode? sublist;
}

class _TableNode extends _MarkdownNode {
  _TableNode(this.headers, this.alignments, this.rows);
  final List<String> headers;
  final List<TextAlign?> alignments;
  final List<List<String>> rows;
}

class _HorizontalRuleNode extends _MarkdownNode {}

class _MathBlockNode extends _MarkdownNode {
  _MathBlockNode(this.tex);
  final String tex;
}

class _InlineMathNode extends _MarkdownNode {
  _InlineMathNode(this.tex);
  final String tex;
}

class _FootnoteRefNode extends _MarkdownNode {
  _FootnoteRefNode(this.label);
  final String label;
}

class _FootnoteDefNode extends _MarkdownNode {
  _FootnoteDefNode(this.label, this.children);
  final String label;
  final List<_MarkdownNode> children;
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

class _MarkdownParser {
  List<_MarkdownNode> parse(String input) {
    final lines = input.split('\n');
    return _parseBlocks(lines, 0, lines.length);
  }

  List<_MarkdownNode> _parseBlocks(List<String> lines, int start, int end) {
    final nodes = <_MarkdownNode>[];
    int i = start;

    while (i < end) {
      final line = lines[i];

      // Blank line
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // Horizontal rule
      if (RegExp(r'^(\*{3,}|-{3,}|_{3,})\s*$').hasMatch(line.trim())) {
        nodes.add(_HorizontalRuleNode());
        i++;
        continue;
      }

      // Heading
      final headingMatch = RegExp(r'^(#{1,6})\s+(.+)$').firstMatch(line);
      if (headingMatch != null) {
        final level = headingMatch.group(1)!.length;
        final content = headingMatch.group(2)!;
        nodes.add(_HeadingNode(level, _parseInline(content)));
        i++;
        continue;
      }

      // Fenced code block
      if (line.trimLeft().startsWith('```')) {
        final lang = line.trim().substring(3).trim();
        final codeLines = <String>[];
        i++;
        while (i < end && !lines[i].trimLeft().startsWith('```')) {
          codeLines.add(lines[i]);
          i++;
        }
        if (i < end) i++; // skip closing ```
        nodes.add(_CodeBlockNode(
          codeLines.join('\n'),
          lang.isEmpty ? null : lang,
        ));
        continue;
      }

      // Math block ($$...$$)
      if (line.trim().startsWith(r'$$')) {
        final mathLines = <String>[line.trim().substring(2)];
        i++;
        while (i < end && !lines[i].trim().endsWith(r'$$')) {
          mathLines.add(lines[i]);
          i++;
        }
        if (i < end) {
          final last = lines[i].trim();
          mathLines.add(last.substring(0, last.length - 2));
          i++;
        }
        nodes.add(_MathBlockNode(mathLines.join('\n').trim()));
        continue;
      }

      // Table (header | separator | rows)
      if (line.contains('|') && i + 1 < end && _isTableSeparator(lines[i + 1])) {
        final headers = _splitTableRow(line);
        final aligns = _parseAlignments(lines[i + 1]);
        final rows = <List<String>>[];
        i += 2;
        while (i < end && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
          rows.add(_splitTableRow(lines[i]));
          i++;
        }
        nodes.add(_TableNode(headers, aligns, rows));
        continue;
      }

      // Blockquote / admonition
      if (line.trimLeft().startsWith('>')) {
        final quoteLines = <String>[];
        while (i < end && lines[i].trimLeft().startsWith('>')) {
          quoteLines.add(lines[i].trimLeft().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        // Check for admonition
        final firstLine = quoteLines.isNotEmpty ? quoteLines.first.trim() : '';
        final admoMatch = RegExp(r'^\[!(NOTE|WARNING|TIP|CAUTION|IMPORTANT)\]')
            .firstMatch(firstLine);
        if (admoMatch != null) {
          final kind = admoMatch.group(1)!;
          quoteLines[0] = quoteLines[0].replaceFirst(admoMatch.group(0)!, '').trim();
          if (quoteLines[0].isEmpty) quoteLines.removeAt(0);
          nodes.add(_AdmonitionNode(
            kind,
            _parseBlocks(quoteLines, 0, quoteLines.length),
          ));
        } else {
          nodes.add(_BlockquoteNode(
            _parseBlocks(quoteLines, 0, quoteLines.length),
          ));
        }
        continue;
      }

      // Unordered list
      if (RegExp(r'^(\s*)([-*+])\s').hasMatch(line)) {
        final items = <_ListItemNode>[];
        final baseIndent = _leadingSpaces(line);
        while (i < end && RegExp(r'^(\s*)([-*+])\s').hasMatch(lines[i])) {
          final indent = _leadingSpaces(lines[i]);
          if (indent < baseIndent) break;
          final content = lines[i].replaceFirst(RegExp(r'^\s*[-*+]\s'), '');
          bool? checked;
          var text = content;
          if (text.startsWith('[ ] ')) {
            checked = false;
            text = text.substring(4);
          } else if (text.startsWith('[x] ') || text.startsWith('[X] ')) {
            checked = true;
            text = text.substring(4);
          }
          items.add(_ListItemNode(_parseInline(text), checked: checked));
          i++;
          // Gather nested sublist items – simplified approach
        }
        nodes.add(_UnorderedListNode(items));
        continue;
      }

      // Ordered list
      if (RegExp(r'^(\s*)\d+\.\s').hasMatch(line)) {
        final items = <_ListItemNode>[];
        while (i < end && RegExp(r'^(\s*)\d+\.\s').hasMatch(lines[i])) {
          final content = lines[i].replaceFirst(RegExp(r'^\s*\d+\.\s'), '');
          items.add(_ListItemNode(_parseInline(content)));
          i++;
        }
        nodes.add(_OrderedListNode(items));
        continue;
      }

      // Footnote definition
      final fnDefMatch = RegExp(r'^\[\^(\w+)\]:\s*(.+)').firstMatch(line);
      if (fnDefMatch != null) {
        nodes.add(_FootnoteDefNode(
          fnDefMatch.group(1)!,
          _parseInline(fnDefMatch.group(2)!),
        ));
        i++;
        continue;
      }

      // Paragraph (collect contiguous non-blank lines)
      final paraLines = <String>[];
      while (i < end &&
          lines[i].trim().isNotEmpty &&
          !lines[i].trimLeft().startsWith('#') &&
          !lines[i].trimLeft().startsWith('```') &&
          !lines[i].trimLeft().startsWith('>') &&
          !RegExp(r'^(\*{3,}|-{3,}|_{3,})\s*$').hasMatch(lines[i].trim())) {
        paraLines.add(lines[i]);
        i++;
      }
      if (paraLines.isNotEmpty) {
        nodes.add(_ParagraphNode(_parseInline(paraLines.join(' '))));
      }
    }
    return nodes;
  }

  // ---- inline parsing ----

  List<_MarkdownNode> _parseInline(String text) {
    final nodes = <_MarkdownNode>[];
    final buffer = StringBuffer();
    int i = 0;

    void flushBuffer() {
      if (buffer.isNotEmpty) {
        nodes.add(_TextNode(buffer.toString()));
        buffer.clear();
      }
    }

    while (i < text.length) {
      // Footnote ref [^label]
      if (text[i] == '[' && i + 1 < text.length && text[i + 1] == '^') {
        final close = text.indexOf(']', i + 2);
        if (close != -1) {
          flushBuffer();
          nodes.add(_FootnoteRefNode(text.substring(i + 2, close)));
          i = close + 1;
          continue;
        }
      }

      // Image ![alt](url)
      if (text[i] == '!' && i + 1 < text.length && text[i + 1] == '[') {
        final altClose = text.indexOf(']', i + 2);
        if (altClose != -1 && altClose + 1 < text.length && text[altClose + 1] == '(') {
          final urlClose = text.indexOf(')', altClose + 2);
          if (urlClose != -1) {
            flushBuffer();
            nodes.add(_ImageNode(
              text.substring(i + 2, altClose),
              text.substring(altClose + 2, urlClose),
            ));
            i = urlClose + 1;
            continue;
          }
        }
      }

      // Link [text](url)
      if (text[i] == '[') {
        final textClose = text.indexOf(']', i + 1);
        if (textClose != -1 && textClose + 1 < text.length && text[textClose + 1] == '(') {
          final urlClose = text.indexOf(')', textClose + 2);
          if (urlClose != -1) {
            flushBuffer();
            nodes.add(_LinkNode(
              text.substring(i + 1, textClose),
              text.substring(textClose + 2, urlClose),
            ));
            i = urlClose + 1;
            continue;
          }
        }
      }

      // Inline math $...$
      if (text[i] == r'$' && (i == 0 || text[i - 1] != r'\')) {
        final close = text.indexOf(r'$', i + 1);
        if (close != -1 && close > i + 1) {
          flushBuffer();
          nodes.add(_InlineMathNode(text.substring(i + 1, close)));
          i = close + 1;
          continue;
        }
      }

      // Inline code `...`
      if (text[i] == '`') {
        final close = text.indexOf('`', i + 1);
        if (close != -1) {
          flushBuffer();
          nodes.add(_InlineCodeNode(text.substring(i + 1, close)));
          i = close + 1;
          continue;
        }
      }

      // Bold **...**
      if (i + 1 < text.length && text[i] == '*' && text[i + 1] == '*') {
        final close = text.indexOf('**', i + 2);
        if (close != -1) {
          flushBuffer();
          nodes.add(_BoldNode(_parseInline(text.substring(i + 2, close))));
          i = close + 2;
          continue;
        }
      }

      // Strikethrough ~~...~~
      if (i + 1 < text.length && text[i] == '~' && text[i + 1] == '~') {
        final close = text.indexOf('~~', i + 2);
        if (close != -1) {
          flushBuffer();
          nodes.add(
              _StrikethroughNode(_parseInline(text.substring(i + 2, close))));
          i = close + 2;
          continue;
        }
      }

      // Italic *...*
      if (text[i] == '*' && (i + 1 >= text.length || text[i + 1] != '*')) {
        final close = text.indexOf('*', i + 1);
        if (close != -1) {
          flushBuffer();
          nodes.add(_ItalicNode(_parseInline(text.substring(i + 1, close))));
          i = close + 1;
          continue;
        }
      }

      buffer.write(text[i]);
      i++;
    }
    flushBuffer();
    return nodes;
  }

  // ---- table helpers ----

  bool _isTableSeparator(String line) {
    return RegExp(r'^[\s|:\-]+$').hasMatch(line) && line.contains('|');
  }

  List<String> _splitTableRow(String line) {
    var trimmed = line.trim();
    if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
    if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
    return trimmed.split('|').map((c) => c.trim()).toList();
  }

  List<TextAlign?> _parseAlignments(String line) {
    return _splitTableRow(line).map((cell) {
      final c = cell.trim();
      if (c.startsWith(':') && c.endsWith(':')) return TextAlign.center;
      if (c.endsWith(':')) return TextAlign.right;
      if (c.startsWith(':')) return TextAlign.left;
      return null;
    }).toList();
  }

  int _leadingSpaces(String s) {
    int c = 0;
    for (final ch in s.runes) {
      if (ch == 0x20) {
        c++;
      } else if (ch == 0x09) {
        c += 4;
      } else {
        break;
      }
    }
    return c;
  }
}

// ---------------------------------------------------------------------------
// MarkdownPreview widget
// ---------------------------------------------------------------------------

/// Renders a markdown string as a tree of Flutter widgets.
class MarkdownPreview extends StatelessWidget {
  const MarkdownPreview({
    super.key,
    required this.data,
    this.theme = const MarkdownTheme(),
    this.onLinkTap,
    this.selectable = true,
  });

  final String data;
  final MarkdownTheme theme;
  final ValueChanged<String>? onLinkTap;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final parser = _MarkdownParser();
    final nodes = parser.parse(data);
    final widgets = _buildWidgets(nodes);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  List<Widget> _buildWidgets(List<_MarkdownNode> nodes) {
    return nodes.map((n) => _buildNode(n)).toList();
  }

  Widget _buildNode(_MarkdownNode node) {
    return switch (node) {
      _HeadingNode() => _buildHeading(node),
      _ParagraphNode() => _buildParagraph(node),
      _CodeBlockNode() => _buildCodeBlock(node),
      _BlockquoteNode() => _buildBlockquote(node),
      _AdmonitionNode() => _buildAdmonition(node),
      _UnorderedListNode() => _buildUnorderedList(node),
      _OrderedListNode() => _buildOrderedList(node),
      _TableNode() => _buildTable(node),
      _HorizontalRuleNode() => _buildHr(),
      _MathBlockNode() => _buildMathBlock(node),
      _FootnoteDefNode() => _buildFootnoteDef(node),
      _ => _wrapInline(node),
    };
  }

  // ---- block builders ----

  Widget _buildHeading(_HeadingNode node) {
    final sizes = [28.0, 24.0, 20.0, 18.0, 16.0, 14.0];
    final size = sizes[math.min(node.level - 1, sizes.length - 1)];
    return Padding(
      padding: EdgeInsets.only(top: node.level <= 2 ? 20 : 14, bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInlineSpan(node.children, TextStyle(
            color: theme.headingColor,
            fontSize: size,
            fontWeight: FontWeight.bold,
            height: 1.3,
          )),
          if (node.level <= 2)
            Divider(color: theme.hrColor, height: 8, thickness: 0.5),
        ],
      ),
    );
  }

  Widget _buildParagraph(_ParagraphNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: _buildInlineSpan(node.children, TextStyle(
        color: theme.bodyColor,
        fontSize: 14,
        height: 1.6,
      )),
    );
  }

  Widget _buildCodeBlock(_CodeBlockNode node) {
    final lines = node.code.split('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.codeBackground,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.grey.shade700, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with language and copy button
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade800,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  if (node.language != null)
                    Text(
                      node.language!,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  const Spacer(),
                  _CopyButton(text: node.code),
                ],
              ),
            ),
            // Code with line numbers
            Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Line numbers
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: List.generate(lines.length, (i) {
                        return Text(
                          '${i + 1}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: Colors.white24,
                            height: 1.5,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(width: 16),
                    // Code content
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: lines.map((l) {
                        return Text(
                          l,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: theme.codeColor,
                            height: 1.5,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockquote(_BlockquoteNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.only(left: 14, top: 8, bottom: 8, right: 8),
        decoration: BoxDecoration(
          color: theme.blockquoteBackground,
          border: Border(
            left: BorderSide(color: theme.blockquoteBorder, width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildWidgets(node.children),
        ),
      ),
    );
  }

  Widget _buildAdmonition(_AdmonitionNode node) {
    Color accentColor;
    IconData icon;
    switch (node.kind) {
      case 'NOTE':
        accentColor = theme.noteColor;
        icon = Icons.info_outline;
      case 'WARNING':
        accentColor = theme.warningColor;
        icon = Icons.warning_amber;
      case 'TIP':
        accentColor = theme.tipColor;
        icon = Icons.lightbulb_outline;
      case 'CAUTION':
        accentColor = theme.cautionColor;
        icon = Icons.report_outlined;
      case 'IMPORTANT':
        accentColor = theme.importantColor;
        icon = Icons.priority_high;
      default:
        accentColor = theme.noteColor;
        icon = Icons.info_outline;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border(left: BorderSide(color: accentColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 6),
                Text(
                  node.kind,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ..._buildWidgets(node.children),
          ],
        ),
      ),
    );
  }

  Widget _buildUnorderedList(_UnorderedListNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: node.items.asMap().entries.map((e) {
          final item = e.value;
          return _buildListItem(item, bullet: true, index: e.key);
        }).toList(),
      ),
    );
  }

  Widget _buildOrderedList(_OrderedListNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: node.items.asMap().entries.map((e) {
          return _buildListItem(e.value, bullet: false, index: e.key);
        }).toList(),
      ),
    );
  }

  Widget _buildListItem(_ListItemNode item,
      {required bool bullet, required int index}) {
    Widget leading;
    if (item.checked != null) {
      // Task list
      leading = Icon(
        item.checked! ? Icons.check_box : Icons.check_box_outline_blank,
        size: 16,
        color: item.checked! ? Colors.green : Colors.white54,
      );
    } else if (bullet) {
      leading = Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: theme.bodyColor,
            shape: BoxShape.circle,
          ),
        ),
      );
    } else {
      leading = Text(
        '${index + 1}.',
        style: TextStyle(color: theme.bodyColor, fontSize: 14),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 24, child: leading),
          Expanded(
            child: _buildInlineSpan(
              item.children,
              TextStyle(color: theme.bodyColor, fontSize: 14, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(_TableNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          border: TableBorder.all(color: theme.tableBorder, width: 0.5),
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            // Header row
            TableRow(
              decoration: BoxDecoration(color: theme.tableHeaderBackground),
              children: node.headers.asMap().entries.map((e) {
                final align = e.key < node.alignments.length
                    ? node.alignments[e.key]
                    : null;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(
                    e.value,
                    textAlign: align,
                    style: TextStyle(
                      color: theme.headingColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
            ),
            // Data rows
            ...node.rows.map((row) {
              return TableRow(
                children: row.asMap().entries.map((e) {
                  final align = e.key < node.alignments.length
                      ? node.alignments[e.key]
                      : null;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    child: Text(
                      e.value,
                      textAlign: align,
                      style: TextStyle(
                        color: theme.bodyColor,
                        fontSize: 13,
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHr() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Divider(color: theme.hrColor, thickness: 1),
    );
  }

  Widget _buildMathBlock(_MathBlockNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.codeBackground,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            node.tex,
            style: const TextStyle(
              fontFamily: 'serif',
              fontStyle: FontStyle.italic,
              fontSize: 16,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFootnoteDef(_FootnoteDefNode node) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.grey.shade800,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              '[${node.label}]',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildInlineSpan(
              node.children,
              TextStyle(color: theme.bodyColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ---- inline span builder ----

  Widget _wrapInline(_MarkdownNode node) {
    return _buildInlineSpan([node], TextStyle(color: theme.bodyColor, fontSize: 14));
  }

  Widget _buildInlineSpan(List<_MarkdownNode> nodes, TextStyle baseStyle) {
    final spans = _inlineToSpans(nodes, baseStyle);
    final richText = Text.rich(
      TextSpan(children: spans),
      style: baseStyle,
    );
    return selectable ? SelectableText.rich(TextSpan(children: spans, style: baseStyle)) : richText;
  }

  List<InlineSpan> _inlineToSpans(
      List<_MarkdownNode> nodes, TextStyle baseStyle) {
    final spans = <InlineSpan>[];
    for (final node in nodes) {
      switch (node) {
        case _TextNode():
          spans.add(TextSpan(text: node.text));
        case _BoldNode():
          spans.addAll(_inlineToSpans(
              node.children,
              baseStyle.copyWith(fontWeight: FontWeight.bold)));
        case _ItalicNode():
          spans.addAll(_inlineToSpans(
              node.children,
              baseStyle.copyWith(fontStyle: FontStyle.italic)));
        case _StrikethroughNode():
          spans.addAll(_inlineToSpans(
              node.children,
              baseStyle.copyWith(
                  decoration: TextDecoration.lineThrough)));
        case _InlineCodeNode():
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: theme.inlineCodeBackground,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                node.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: baseStyle.fontSize != null
                      ? baseStyle.fontSize! - 1
                      : 13,
                  color: theme.inlineCodeColor,
                ),
              ),
            ),
          ));
        case _LinkNode():
          spans.add(TextSpan(
            text: node.text,
            style: TextStyle(
              color: theme.linkColor,
              decoration: TextDecoration.underline,
              decorationColor: theme.linkColor.withOpacity(0.4),
            ),
            // GestureRecognizer would need StatefulWidget; use onLinkTap callback
          ));
        case _ImageNode():
          spans.add(WidgetSpan(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: node.url.startsWith('http')
                    ? Image.network(
                        node.url,
                        errorBuilder: (_, __, ___) =>
                            _imagePlaceholder(node.alt),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return _imagePlaceholder('Loading...');
                        },
                      )
                    : _imagePlaceholder(node.alt),
              ),
            ),
          ));
        case _InlineMathNode():
          spans.add(TextSpan(
            text: node.tex,
            style: const TextStyle(
              fontFamily: 'serif',
              fontStyle: FontStyle.italic,
            ),
          ));
        case _FootnoteRefNode():
          spans.add(WidgetSpan(
            alignment: PlaceholderAlignment.top,
            child: Text(
              '[${node.label}]',
              style: TextStyle(
                color: theme.linkColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ));
        default:
          break;
      }
    }
    return spans;
  }

  Widget _imagePlaceholder(String alt) {
    return Container(
      width: 200,
      height: 120,
      color: Colors.grey.shade800,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.image, color: Colors.white38, size: 32),
            const SizedBox(height: 4),
            Text(alt,
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Copy button for code blocks
// ---------------------------------------------------------------------------

class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.text});
  final String text;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;

  void _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _copy,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _copied ? Icons.check : Icons.copy,
              size: 14,
              color: _copied ? Colors.green : Colors.white54,
            ),
            const SizedBox(width: 4),
            Text(
              _copied ? 'Copied!' : 'Copy',
              style: TextStyle(
                color: _copied ? Colors.green : Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
