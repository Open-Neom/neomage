// PromptInput — port of neom_claw/src/components/PromptInput/.
// Main chat input widget with @-mentions, slash commands, file drop, autocomplete.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─── Autocomplete suggestion types ───

/// Type of autocomplete suggestion.
enum SuggestionType { file, directory, command, url, gitBranch, model, tool }

/// Single autocomplete suggestion.
class Suggestion {
  final String label;
  final String insertText;
  final SuggestionType type;
  final String? description;
  final IconData? icon;

  const Suggestion({
    required this.label,
    required this.insertText,
    required this.type,
    this.description,
    this.icon,
  });
}

/// Attached file/image chip data.
class Attachment {
  final String name;
  final String path;
  final AttachmentType type;
  final int? sizeBytes;

  const Attachment({
    required this.name,
    required this.path,
    required this.type,
    this.sizeBytes,
  });
}

enum AttachmentType { file, image, pdf, directory }

/// Callback typedefs.
typedef OnSubmit = void Function(String text, List<Attachment> attachments);
typedef OnSuggestionRequest =
    Future<List<Suggestion>> Function(String query, SuggestionType type);

// ─── PromptInput widget ───

/// Main chat input widget with rich editing features.
class PromptInput extends StatefulWidget {
  final OnSubmit onSubmit;
  final OnSuggestionRequest? onSuggestionRequest;
  final bool isLoading;
  final String? placeholder;
  final String? currentModel;
  final List<String>? availableModels;
  final ValueChanged<String>? onModelChanged;
  final int? tokenCount;
  final int? maxTokens;
  final bool vimMode;
  final FocusNode? focusNode;

  const PromptInput({
    super.key,
    required this.onSubmit,
    this.onSuggestionRequest,
    this.isLoading = false,
    this.placeholder,
    this.currentModel,
    this.availableModels,
    this.onModelChanged,
    this.tokenCount,
    this.maxTokens,
    this.vimMode = false,
    this.focusNode,
  });

  @override
  State<PromptInput> createState() => _PromptInputState();
}

class _PromptInputState extends State<PromptInput> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  final List<Attachment> _attachments = [];
  final List<String> _history = [];
  int _historyIndex = -1;
  String _savedInput = '';

  // Autocomplete state
  bool _showSuggestions = false;
  List<Suggestion> _suggestions = [];
  int _selectedSuggestion = 0;
  SuggestionType? _activeSuggestionType;
  // ignore: unused_field
  String _suggestionQuery = '';
  Timer? _debounce;

  // Metrics
  int _lineCount = 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    if (widget.focusNode == null) _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _controller.text;
    final lines = '\n'.allMatches(text).length + 1;
    if (lines != _lineCount) {
      setState(() => _lineCount = lines);
    }
    _checkForAutocomplete(text);
  }

  void _checkForAutocomplete(String text) {
    if (widget.onSuggestionRequest == null) return;
    final cursor = _controller.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;
    final before = text.substring(0, cursor);

    // Check for @-mention trigger
    final atMatch = RegExp(r'@([\w./~-]*)$').firstMatch(before);
    if (atMatch != null) {
      final query = atMatch.group(1) ?? '';
      _requestSuggestions(query, SuggestionType.file);
      return;
    }

    // Check for slash command trigger
    if (before.startsWith('/') && !before.contains(' ')) {
      final query = before.substring(1);
      _requestSuggestions(query, SuggestionType.command);
      return;
    }

    // No trigger — hide suggestions
    if (_showSuggestions) {
      setState(() => _showSuggestions = false);
    }
  }

  void _requestSuggestions(String query, SuggestionType type) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      if (!mounted) return;
      _suggestionQuery = query;
      _activeSuggestionType = type;
      final results = await widget.onSuggestionRequest!(query, type);
      if (!mounted) return;
      setState(() {
        _suggestions = results;
        _selectedSuggestion = 0;
        _showSuggestions = results.isNotEmpty;
      });
    });
  }

  void _acceptSuggestion(Suggestion suggestion) {
    final text = _controller.text;
    final cursor = _controller.selection.baseOffset;
    final before = text.substring(0, cursor);

    String newBefore;
    if (_activeSuggestionType == SuggestionType.command) {
      newBefore = '/${suggestion.insertText} ';
    } else {
      // Replace @query with @suggestion
      final atIndex = before.lastIndexOf('@');
      if (atIndex >= 0) {
        newBefore = '${before.substring(0, atIndex)}@${suggestion.insertText} ';
      } else {
        newBefore = '$before${suggestion.insertText} ';
      }
    }

    final after = cursor < text.length ? text.substring(cursor) : '';
    _controller.text = '$newBefore$after';
    _controller.selection = TextSelection.collapsed(offset: newBefore.length);
    setState(() => _showSuggestions = false);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.isLoading) return;

    // Add to history
    if (text.isNotEmpty) {
      _history.remove(text);
      _history.insert(0, text);
      if (_history.length > 500) _history.removeLast();
    }
    _historyIndex = -1;

    widget.onSubmit(text, List.from(_attachments));
    _controller.clear();
    _attachments.clear();
    setState(() {});
  }

  void _navigateHistory(bool up) {
    if (_history.isEmpty) return;
    if (up) {
      if (_historyIndex == -1) {
        _savedInput = _controller.text;
      }
      if (_historyIndex < _history.length - 1) {
        _historyIndex++;
        _controller.text = _history[_historyIndex];
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    } else {
      if (_historyIndex > 0) {
        _historyIndex--;
        _controller.text = _history[_historyIndex];
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      } else if (_historyIndex == 0) {
        _historyIndex = -1;
        _controller.text = _savedInput;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    }
  }

  void addAttachment(Attachment attachment) {
    setState(() => _attachments.add(attachment));
  }

  void removeAttachment(int index) {
    if (index >= 0 && index < _attachments.length) {
      setState(() => _attachments.removeAt(index));
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    // Autocomplete navigation
    if (_showSuggestions) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() {
          _selectedSuggestion = (_selectedSuggestion + 1) % _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _selectedSuggestion =
              (_selectedSuggestion - 1 + _suggestions.length) %
              _suggestions.length;
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
        _acceptSuggestion(_suggestions[_selectedSuggestion]);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.escape) {
        setState(() => _showSuggestions = false);
        return KeyEventResult.handled;
      }
    }

    // Submit: Ctrl+Enter or Enter (single line, no shift)
    if (key == LogicalKeyboardKey.enter) {
      if (ctrl ||
          (!shift && _lineCount == 1 && !_controller.text.contains('\n'))) {
        _submit();
        return KeyEventResult.handled;
      }
    }

    // History navigation: Up/Down when cursor is at start/end
    if (key == LogicalKeyboardKey.arrowUp && !_showSuggestions) {
      final offset = _controller.selection.baseOffset;
      final textBefore = _controller.text.substring(0, max(0, offset));
      if (!textBefore.contains('\n')) {
        _navigateHistory(true);
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown && !_showSuggestions) {
      final offset = _controller.selection.baseOffset;
      final textAfter = _controller.text.substring(offset);
      if (!textAfter.contains('\n')) {
        _navigateHistory(false);
        return KeyEventResult.handled;
      }
    }

    // Cancel: Escape
    if (key == LogicalKeyboardKey.escape) {
      if (_controller.text.isNotEmpty) {
        _controller.clear();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Attachment chips
        if (_attachments.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (var i = 0; i < _attachments.length; i++)
                  AttachmentChip(
                    attachment: _attachments[i],
                    onRemove: () => removeAttachment(i),
                  ),
              ],
            ),
          ),

        // Autocomplete overlay
        if (_showSuggestions)
          AutocompleteOverlay(
            suggestions: _suggestions,
            selectedIndex: _selectedSuggestion,
            onSelect: _acceptSuggestion,
          ),

        // Input area
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
            border: Border(
              top: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Text input
              Focus(
                onKeyEvent: _handleKeyEvent,
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  maxLines: null,
                  minLines: 1,
                  enabled: !widget.isLoading,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText:
                        widget.placeholder ??
                        'Type a message... (@ to mention files, / for commands)',
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),

              // Toolbar
              InputToolbar(
                isLoading: widget.isLoading,
                currentModel: widget.currentModel,
                availableModels: widget.availableModels,
                onModelChanged: widget.onModelChanged,
                tokenCount: widget.tokenCount,
                maxTokens: widget.maxTokens,
                lineCount: _lineCount,
                charCount: _controller.text.length,
                attachmentCount: _attachments.length,
                vimMode: widget.vimMode,
                onSubmit: _submit,
                onAttach: () {
                  // Trigger file picker — placeholder
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── AutocompleteOverlay ───

/// Floating autocomplete suggestion list.
class AutocompleteOverlay extends StatelessWidget {
  final List<Suggestion> suggestions;
  final int selectedIndex;
  final ValueChanged<Suggestion> onSelect;

  const AutocompleteOverlay({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelect,
  });

  IconData _iconForType(SuggestionType type) {
    switch (type) {
      case SuggestionType.file:
        return Icons.insert_drive_file_outlined;
      case SuggestionType.directory:
        return Icons.folder_outlined;
      case SuggestionType.command:
        return Icons.terminal;
      case SuggestionType.url:
        return Icons.link;
      case SuggestionType.gitBranch:
        return Icons.fork_right;
      case SuggestionType.model:
        return Icons.smart_toy_outlined;
      case SuggestionType.tool:
        return Icons.build_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      margin: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF252540) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: suggestions.length,
        itemBuilder: (context, index) {
          final s = suggestions[index];
          final isSelected = index == selectedIndex;
          return InkWell(
            onTap: () => onSelect(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: isSelected
                  ? (isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : Colors.blue.withValues(alpha: 0.1))
                  : null,
              child: Row(
                children: [
                  Icon(
                    s.icon ?? _iconForType(s.type),
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.label,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black87,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (s.description != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      s.description!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── AttachmentChip ───

/// Chip showing an attached file with remove button.
class AttachmentChip extends StatelessWidget {
  final Attachment attachment;
  final VoidCallback onRemove;

  const AttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
  });

  IconData get _icon {
    switch (attachment.type) {
      case AttachmentType.file:
        return Icons.insert_drive_file_outlined;
      case AttachmentType.image:
        return Icons.image_outlined;
      case AttachmentType.pdf:
        return Icons.picture_as_pdf_outlined;
      case AttachmentType.directory:
        return Icons.folder_outlined;
    }
  }

  String get _sizeLabel {
    final bytes = attachment.sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return ' ($bytes B)';
    if (bytes < 1024 * 1024) {
      return ' (${(bytes / 1024).toStringAsFixed(1)} KB)';
    }
    return ' (${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB)';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Chip(
      avatar: Icon(_icon, size: 16),
      label: Text(
        '${attachment.name}$_sizeLabel',
        style: TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
      deleteIcon: const Icon(Icons.close, size: 14),
      onDeleted: onRemove,
      backgroundColor: isDark
          ? const Color(0xFF2A2A40)
          : const Color(0xFFF0F0F5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

// ─── InputToolbar ───

/// Toolbar below input with model selector, counts, buttons.
class InputToolbar extends StatelessWidget {
  final bool isLoading;
  final String? currentModel;
  final List<String>? availableModels;
  final ValueChanged<String>? onModelChanged;
  final int? tokenCount;
  final int? maxTokens;
  final int lineCount;
  final int charCount;
  final int attachmentCount;
  final bool vimMode;
  final VoidCallback onSubmit;
  final VoidCallback onAttach;

  const InputToolbar({
    super.key,
    required this.isLoading,
    this.currentModel,
    this.availableModels,
    this.onModelChanged,
    this.tokenCount,
    this.maxTokens,
    required this.lineCount,
    required this.charCount,
    required this.attachmentCount,
    this.vimMode = false,
    required this.onSubmit,
    required this.onAttach,
  });

  String get _modelShort {
    final m = currentModel ?? 'gemini-2.5-flash';
    if (m.contains('gemini')) return 'Gemini';
    if (m.contains('qwen')) return 'Qwen';
    if (m.contains('deepseek')) return 'DeepSeek';
    if (m.contains('opus')) return 'Opus';
    if (m.contains('sonnet')) return 'Sonnet';
    if (m.contains('haiku')) return 'Haiku';
    if (m.contains('gpt-4o-mini')) return 'GPT-4o Mini';
    if (m.contains('gpt-4o')) return 'GPT-4o';
    if (m.contains('o1')) return 'o1';
    if (m.contains('o3')) return 'o3';
    if (m.contains('llama')) return 'Llama';
    if (m.contains('mistral')) return 'Mistral';
    if (m.length > 20) return '${m.substring(0, 17)}...';
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.white38 : Colors.black38;
    final textStyle = TextStyle(fontSize: 11, color: muted);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Model selector
          if (availableModels != null && availableModels!.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: onModelChanged,
              tooltip: 'Select model',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.smart_toy_outlined, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Text(_modelShort, style: textStyle),
                  Icon(Icons.arrow_drop_down, size: 14, color: muted),
                ],
              ),
              itemBuilder: (_) => availableModels!
                  .map((m) => PopupMenuItem(value: m, child: Text(m)))
                  .toList(),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 14, color: muted),
                const SizedBox(width: 4),
                Text(_modelShort, style: textStyle),
              ],
            ),

          const SizedBox(width: 12),

          // Token count
          if (tokenCount != null)
            Text(
              maxTokens != null
                  ? '${_formatNum(tokenCount!)}/${_formatNum(maxTokens!)} tokens'
                  : '${_formatNum(tokenCount!)} tokens',
              style: textStyle,
            ),

          const SizedBox(width: 12),

          // Line / char count
          Text('$lineCount ln · $charCount ch', style: textStyle),

          if (attachmentCount > 0) ...[
            const SizedBox(width: 12),
            Text('$attachmentCount files', style: textStyle),
          ],

          if (vimMode) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: isDark ? Colors.green.shade900 : Colors.green.shade100,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'VIM',
                style: textStyle.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                ),
              ),
            ),
          ],

          const Spacer(),

          // Attach button
          IconButton(
            onPressed: onAttach,
            icon: Icon(Icons.attach_file, size: 18, color: muted),
            tooltip: 'Attach file',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),

          const SizedBox(width: 4),

          // Send button
          SizedBox(
            height: 32,
            child: ElevatedButton.icon(
              onPressed: isLoading ? null : onSubmit,
              icon: isLoading
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    )
                  : const Icon(Icons.send, size: 14),
              label: Text(
                isLoading ? 'Generating...' : 'Send',
                style: const TextStyle(fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: isDark
                    ? const Color(0xFF4A3AFF)
                    : const Color(0xFF5B4CFF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}
