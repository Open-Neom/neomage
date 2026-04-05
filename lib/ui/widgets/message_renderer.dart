// Message renderer — port of neomage Message + Markdown + AssistantTextMessage.
// Renders conversation messages with markdown, code blocks, and tool outputs.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard

import 'package:neomage/domain/models/message.dart';
import 'diff_view.dart';
import 'syntax_highlight.dart';
import 'tool_output_widget.dart';

/// Markdown token types for rendering.
sealed class MarkdownToken {
  const MarkdownToken();
}

class TextToken extends MarkdownToken {
  final String text;
  const TextToken(this.text);
}

class BoldToken extends MarkdownToken {
  final String text;
  const BoldToken(this.text);
}

class ItalicToken extends MarkdownToken {
  final String text;
  const ItalicToken(this.text);
}

class CodeSpanToken extends MarkdownToken {
  final String code;
  const CodeSpanToken(this.code);
}

class CodeBlockToken extends MarkdownToken {
  final String code;
  final String? language;
  const CodeBlockToken(this.code, this.language);
}

class HeadingToken extends MarkdownToken {
  final String text;
  final int level;
  const HeadingToken(this.text, this.level);
}

class ListItemToken extends MarkdownToken {
  final String text;
  final bool ordered;
  final int index;
  const ListItemToken(this.text, {this.ordered = false, this.index = 0});
}

class BlockquoteToken extends MarkdownToken {
  final String text;
  const BlockquoteToken(this.text);
}

class LinkToken extends MarkdownToken {
  final String text;
  final String url;
  const LinkToken(this.text, this.url);
}

class HorizontalRuleToken extends MarkdownToken {
  const HorizontalRuleToken();
}

/// Fast check for markdown syntax (optimization — skip parsing for plain text).
bool hasMarkdownSyntax(String text) {
  if (text.length > 500) {
    return RegExp(
      r'[*_`#\[>\-|~]|^\d+\.',
      multiLine: true,
    ).hasMatch(text.substring(0, 500));
  }
  return RegExp(r'[*_`#\[>\-|~]|^\d+\.', multiLine: true).hasMatch(text);
}

/// Parse markdown text into tokens.
List<MarkdownToken> parseMarkdown(String text) {
  if (!hasMarkdownSyntax(text)) {
    return [TextToken(text)];
  }

  final tokens = <MarkdownToken>[];
  final lines = text.split('\n');
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    // Code block (fenced)
    if (line.startsWith('```')) {
      final lang = line.substring(3).trim().isEmpty
          ? null
          : line.substring(3).trim();
      final codeLines = <String>[];
      i++;
      while (i < lines.length && !lines[i].startsWith('```')) {
        codeLines.add(lines[i]);
        i++;
      }
      tokens.add(CodeBlockToken(codeLines.join('\n'), lang));
      i++; // Skip closing ```
      continue;
    }

    // Heading
    final headingMatch = RegExp(r'^(#{1,6})\s+(.*)').firstMatch(line);
    if (headingMatch != null) {
      tokens.add(
        HeadingToken(headingMatch.group(2)!, headingMatch.group(1)!.length),
      );
      i++;
      continue;
    }

    // Horizontal rule
    if (RegExp(r'^(\*{3,}|-{3,}|_{3,})\s*$').hasMatch(line)) {
      tokens.add(const HorizontalRuleToken());
      i++;
      continue;
    }

    // Blockquote
    if (line.startsWith('> ')) {
      final quoteLines = <String>[];
      while (i < lines.length && lines[i].startsWith('> ')) {
        quoteLines.add(lines[i].substring(2));
        i++;
      }
      tokens.add(BlockquoteToken(quoteLines.join('\n')));
      continue;
    }

    // Ordered list
    final olMatch = RegExp(r'^(\d+)\.\s+(.*)').firstMatch(line);
    if (olMatch != null) {
      tokens.add(
        ListItemToken(
          olMatch.group(2)!,
          ordered: true,
          index: int.tryParse(olMatch.group(1)!) ?? 1,
        ),
      );
      i++;
      continue;
    }

    // Unordered list
    if (RegExp(r'^[\-*+]\s+').hasMatch(line)) {
      tokens.add(ListItemToken(line.replaceFirst(RegExp(r'^[\-*+]\s+'), '')));
      i++;
      continue;
    }

    // Regular text — parse inline elements
    if (line.trim().isNotEmpty) {
      _parseInlineTokens(line, tokens);
      tokens.add(const TextToken('\n'));
    } else {
      tokens.add(const TextToken('\n'));
    }
    i++;
  }

  return tokens;
}

void _parseInlineTokens(String text, List<MarkdownToken> tokens) {
  final pattern = RegExp(
    r'(`[^`]+`)' // inline code
    r'|(\*\*[^*]+\*\*)' // bold
    r'|(\*[^*]+\*)' // italic
    r'|(\[[^\]]+\]\([^)]+\))', // link
  );

  var lastEnd = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > lastEnd) {
      tokens.add(TextToken(text.substring(lastEnd, match.start)));
    }

    final full = match[0]!;
    if (full.startsWith('`')) {
      tokens.add(CodeSpanToken(full.substring(1, full.length - 1)));
    } else if (full.startsWith('**')) {
      tokens.add(BoldToken(full.substring(2, full.length - 2)));
    } else if (full.startsWith('*')) {
      tokens.add(ItalicToken(full.substring(1, full.length - 1)));
    } else if (full.startsWith('[')) {
      final linkMatch = RegExp(r'\[([^\]]+)\]\(([^)]+)\)').firstMatch(full);
      if (linkMatch != null) {
        tokens.add(LinkToken(linkMatch.group(1)!, linkMatch.group(2)!));
      }
    }

    lastEnd = match.end;
  }

  if (lastEnd < text.length) {
    tokens.add(TextToken(text.substring(lastEnd)));
  }
}

// ── Flutter Widgets ──

/// Renders a single conversation message.
class MessageRenderer extends StatelessWidget {
  final ContentBlock block;
  final bool isUser;
  final SyntaxColors? syntaxColors;

  const MessageRenderer({
    super.key,
    required this.block,
    this.isUser = false,
    this.syntaxColors,
  });

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      TextBlock(text: final text) => _MarkdownView(
        text: text,
        isUser: isUser,
        syntaxColors: syntaxColors,
      ),
      ToolUseBlock() => ToolOutputWidget(
        toolName: (block as ToolUseBlock).name,
        input: (block as ToolUseBlock).input,
        output: '',
      ),
      ToolResultBlock(content: final content) => _ToolResultView(
        content: content,
        isError: (block as ToolResultBlock).isError,
      ),
      ImageBlock() => const Icon(Icons.image, size: 48),
    };
  }
}

/// Renders markdown text with syntax highlighting for code blocks.
class _MarkdownView extends StatelessWidget {
  final String text;
  final bool isUser;
  final SyntaxColors? syntaxColors;

  const _MarkdownView({
    required this.text,
    this.isUser = false,
    this.syntaxColors,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = parseMarkdown(text);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildTokenWidgets(tokens, context, isDark),
      ),
    );
  }

  List<Widget> _buildTokenWidgets(
    List<MarkdownToken> tokens,
    BuildContext context,
    bool isDark,
  ) {
    final widgets = <Widget>[];
    final inlineSpans = <InlineSpan>[];

    void flushInline() {
      if (inlineSpans.isNotEmpty) {
        widgets.add(
          RichText(
            text: TextSpan(children: List.of(inlineSpans)),
            softWrap: true,
          ),
        );
        inlineSpans.clear();
      }
    }

    final textColor = isDark ? Colors.white70 : Colors.black87;
    final baseStyle = TextStyle(
      fontFamily: '.SF Pro Text',
      fontSize: 14,
      height: 1.6,
      color: textColor,
    );

    for (final token in tokens) {
      switch (token) {
        case TextToken(text: final t):
          if (t == '\n') {
            flushInline();
            widgets.add(const SizedBox(height: 4));
          } else {
            inlineSpans.add(TextSpan(text: t, style: baseStyle));
          }

        case BoldToken(text: final t):
          inlineSpans.add(
            TextSpan(
              text: t,
              style: baseStyle.copyWith(fontWeight: FontWeight.bold),
            ),
          );

        case ItalicToken(text: final t):
          inlineSpans.add(
            TextSpan(
              text: t,
              style: baseStyle.copyWith(fontStyle: FontStyle.italic),
            ),
          );

        case CodeSpanToken(code: final code):
          inlineSpans.add(
            TextSpan(
              text: code,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                color: isDark
                    ? const Color(0xFFE06C75)
                    : const Color(0xFFE45649),
                backgroundColor: isDark
                    ? const Color(0xFF2C313A)
                    : const Color(0xFFF0F0F0),
              ),
            ),
          );

        case CodeBlockToken(code: final code, language: final lang):
          flushInline();
          widgets.add(
            _CodeBlockWidget(
              code: code,
              language: lang,
              isDark: isDark,
              syntaxColors: syntaxColors,
            ),
          );

        case HeadingToken(text: final t, level: final level):
          flushInline();
          widgets.add(
            Padding(
              padding: EdgeInsets.only(top: level <= 2 ? 16 : 8, bottom: 4),
              child: Text(
                t,
                style: baseStyle.copyWith(
                  fontSize: switch (level) {
                    1 => 24.0,
                    2 => 20.0,
                    3 => 18.0,
                    _ => 16.0,
                  },
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );

        case ListItemToken(
          text: final t,
          ordered: final ordered,
          index: final idx,
        ):
          flushInline();
          widgets.add(
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(ordered ? '$idx.' : '\u2022', style: baseStyle),
                  ),
                  Expanded(child: Text(t, style: baseStyle)),
                ],
              ),
            ),
          );

        case BlockquoteToken(text: final t):
          flushInline();
          widgets.add(
            Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: isDark ? Colors.white24 : Colors.black26,
                    width: 3,
                  ),
                ),
              ),
              child: Text(
                t,
                style: baseStyle.copyWith(
                  color: textColor.withAlpha(178),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );

        case LinkToken(text: final t, url: _):
          inlineSpans.add(
            TextSpan(
              text: t,
              style: baseStyle.copyWith(
                color: isDark
                    ? const Color(0xFF61AFEF)
                    : const Color(0xFF4078F2),
                decoration: TextDecoration.underline,
              ),
            ),
          );

        case HorizontalRuleToken():
          flushInline();
          widgets.add(
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(color: textColor.withAlpha(51)),
            ),
          );
      }
    }

    flushInline();
    return widgets;
  }
}

/// Code block with syntax highlighting, language label, and copy button.
class _CodeBlockWidget extends StatefulWidget {
  final String code;
  final String? language;
  final bool isDark;
  final SyntaxColors? syntaxColors;

  const _CodeBlockWidget({
    required this.code,
    this.language,
    required this.isDark,
    this.syntaxColors,
  });

  @override
  State<_CodeBlockWidget> createState() => _CodeBlockWidgetState();
}

class _CodeBlockWidgetState extends State<_CodeBlockWidget> {
  bool _copied = false;

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.language != null
        ? detectLanguage(widget.language!)
        : 'plaintext';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: widget.isDark
            ? const Color(0xFF1E1E2E)
            : const Color(0xFFF6F8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.isDark
              ? const Color(0xFF333344)
              : const Color(0xFFE1E4E8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: language label + copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? const Color(0xFF282840)
                  : const Color(0xFFEAECF0),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.language ?? 'code',
                  style: TextStyle(
                    fontSize: 12,
                    color: widget.isDark ? Colors.white38 : Colors.black38,
                    fontFamily: 'monospace',
                  ),
                ),
                InkWell(
                  onTap: _copyCode,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _copied ? Icons.check : Icons.copy,
                          size: 14,
                          color: _copied
                              ? Colors.greenAccent
                              : (widget.isDark
                                  ? Colors.white38
                                  : Colors.black38),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _copied ? 'Copied' : 'Copy',
                          style: TextStyle(
                            fontSize: 11,
                            color: _copied
                                ? Colors.greenAccent
                                : (widget.isDark
                                    ? Colors.white38
                                    : Colors.black38),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Code body
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SyntaxHighlightView(
              code: widget.code,
              language: lang,
              colors: widget.syntaxColors,
              showLineNumbers: widget.code.split('\n').length > 3,
            ),
          ),
        ],
      ),
    );
  }
}

/// Thinking block view (collapsed by default).
class _ThinkingView extends StatefulWidget {
  final String text;

  const _ThinkingView({required this.text});

  @override
  State<_ThinkingView> createState() => _ThinkingViewState();
}

class _ThinkingViewState extends State<_ThinkingView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xFF333355) : const Color(0xFFD0D0E0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                widget.text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black54,
                  height: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tool result view.
class _ToolResultView extends StatelessWidget {
  final String content;
  final bool isError;

  const _ToolResultView({required this.content, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Detect diff content
    if (content.contains('@@') && content.contains('---')) {
      final hunks = parseUnifiedDiff(content);
      if (hunks.isNotEmpty) {
        return ScrollableDiffView(hunks: hunks, maxHeight: 300);
      }
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isError
            ? (isDark ? const Color(0xFF2A1515) : const Color(0xFFFFF0F0))
            : (isDark ? const Color(0xFF1E2E1E) : const Color(0xFFF0FFF0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        content,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: isError
              ? (isDark ? const Color(0xFFFF6666) : const Color(0xFFCC0000))
              : (isDark ? Colors.white70 : Colors.black87),
        ),
      ),
    );
  }
}

/// Renders a full conversation message with bubble-style layout.
///
/// User messages appear as compact bubbles aligned to the right.
/// Assistant messages appear on the left with action buttons (copy, like/dislike).
class ConversationMessage extends StatefulWidget {
  final Message message;
  final VoidCallback? onRegenerate;

  const ConversationMessage({
    super.key,
    required this.message,
    this.onRegenerate,
  });

  @override
  State<ConversationMessage> createState() => _ConversationMessageState();
}

class _ConversationMessageState extends State<ConversationMessage> {
  bool _copied = false;
  bool _liked = false;
  bool _disliked = false;

  String _timeAgo(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _copyFullText() {
    final text = widget.message.textContent;
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      setState(() => _copied = true);
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUser = widget.message.role == MessageRole.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxBubbleWidth = screenWidth < 600
        ? screenWidth * 0.82
        : screenWidth * 0.65;

    if (isUser) {
      return _buildUserBubble(isDark, maxBubbleWidth);
    } else {
      return _buildAssistantMessage(isDark, maxBubbleWidth);
    }
  }

  Widget _buildUserBubble(bool isDark, double maxWidth) {
    final accentColor = isDark
        ? const Color(0xFF2A3A4A) // dark teal-blue
        : const Color(0xFFE8F0FE); // light blue

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(top: 8, bottom: 4, left: 48, right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Bubble
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(18),
                  topRight: Radius.circular(18),
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in widget.message.content)
                    MessageRenderer(block: block, isUser: true),
                ],
              ),
            ),
            // Timestamp
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(
                _timeAgo(widget.message.timestamp),
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistantMessage(bool isDark, double maxWidth) {
    final actionColor = isDark ? Colors.white30 : Colors.black26;

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        margin: const EdgeInsets.only(top: 8, bottom: 4, right: 48, left: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Content — no bubble background, clean left-aligned like SAIA
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in widget.message.content)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: MessageRenderer(block: block, isUser: false),
                    ),
                ],
              ),
            ),
            // Action bar + timestamp
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Copy
                  _ActionIconButton(
                    icon: _copied ? Icons.check : Icons.copy_outlined,
                    tooltip: _copied ? 'Copied' : 'Copy',
                    color: _copied
                        ? (isDark ? Colors.greenAccent : Colors.green)
                        : actionColor,
                    onPressed: _copyFullText,
                  ),
                  // View source / code
                  _ActionIconButton(
                    icon: Icons.code,
                    tooltip: 'View source',
                    color: actionColor,
                    onPressed: () {
                      // Could show raw markdown in a dialog
                    },
                  ),
                  // Regenerate
                  if (widget.onRegenerate != null)
                    _ActionIconButton(
                      icon: Icons.refresh,
                      tooltip: 'Regenerate',
                      color: actionColor,
                      onPressed: widget.onRegenerate!,
                    ),
                  // Like
                  _ActionIconButton(
                    icon: _liked
                        ? Icons.thumb_up
                        : Icons.thumb_up_outlined,
                    tooltip: 'Good response',
                    color: _liked
                        ? (isDark ? Colors.greenAccent : Colors.green)
                        : actionColor,
                    onPressed: () => setState(() {
                      _liked = !_liked;
                      if (_liked) _disliked = false;
                    }),
                  ),
                  // Dislike
                  _ActionIconButton(
                    icon: _disliked
                        ? Icons.thumb_down
                        : Icons.thumb_down_outlined,
                    tooltip: 'Bad response',
                    color: _disliked
                        ? (isDark ? Colors.redAccent : Colors.red)
                        : actionColor,
                    onPressed: () => setState(() {
                      _disliked = !_disliked;
                      if (_disliked) _liked = false;
                    }),
                  ),
                  const SizedBox(width: 8),
                  // Timestamp
                  Text(
                    _timeAgo(widget.message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small icon button for message actions (copy, like, dislike, etc.)
class _ActionIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  const _ActionIconButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}
