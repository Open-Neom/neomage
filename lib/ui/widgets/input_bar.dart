import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Attachment data ready to send with a message.
class InputAttachment {
  final String name;
  final String mimeType;
  final Uint8List bytes;
  final AttachmentKind kind;

  const InputAttachment({
    required this.name,
    required this.mimeType,
    required this.bytes,
    required this.kind,
  });

  /// Base64-encoded content for API payloads.
  String get base64Data => base64Encode(bytes);

  bool get isImage =>
      mimeType.startsWith('image/') || kind == AttachmentKind.image;
}

enum AttachmentKind { image, file, pdf }

class InputBar extends StatefulWidget {
  final void Function(String text, {List<InputAttachment> attachments})
      onSubmit;
  final bool isLoading;

  const InputBar({
    super.key,
    required this.onSubmit,
    required this.isLoading,
  });

  @override
  State<InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<InputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();
  final List<InputAttachment> _attachments = [];
  bool _isRecording = false;

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    if (widget.isLoading) return;
    widget.onSubmit(text, attachments: List.from(_attachments));
    _controller.clear();
    setState(() => _attachments.clear());
    _focusNode.requestFocus();
  }

  // ── File picker ──

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: true,
      );
      if (result == null) return;

      for (final file in result.files) {
        if (file.bytes == null) continue;
        final mime = _guessMime(file.name);
        final kind = mime.startsWith('image/')
            ? AttachmentKind.image
            : mime == 'application/pdf'
                ? AttachmentKind.pdf
                : AttachmentKind.file;
        setState(() {
          _attachments.add(InputAttachment(
            name: file.name,
            mimeType: mime,
            bytes: file.bytes!,
            kind: kind,
          ));
        });
      }
    } catch (e) {
      _showError('Failed to pick file: $e');
    }
  }

  // ── Image picker (camera / gallery) ──

  Future<void> _pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final xFile = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 85,
      );
      if (xFile == null) return;

      final bytes = await xFile.readAsBytes();
      final mime = _guessMime(xFile.name);
      setState(() {
        _attachments.add(InputAttachment(
          name: xFile.name,
          mimeType: mime,
          bytes: bytes,
          kind: AttachmentKind.image,
        ));
      });
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  // ── Voice (placeholder — shows recording state) ──

  void _toggleVoice() {
    setState(() => _isRecording = !_isRecording);
    if (_isRecording) {
      // TODO: Integrate VoiceService for real STT
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isRecording) {
          setState(() => _isRecording = false);
          _showError('Voice input coming soon — type your message for now');
        }
      });
    }
  }

  // ── Attachment actions menu ──

  void _showAttachMenu() {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _AttachOption(
              icon: Icons.insert_drive_file_outlined,
              label: 'File',
              subtitle: 'Pick any file',
              onTap: () {
                Navigator.pop(ctx);
                _pickFiles();
              },
            ),
            _AttachOption(
              icon: Icons.image_outlined,
              label: 'Image',
              subtitle: 'From gallery',
              onTap: () {
                Navigator.pop(ctx);
                _pickImage();
              },
            ),
            if (!kIsWeb)
              _AttachOption(
                icon: Icons.camera_alt_outlined,
                label: 'Camera',
                subtitle: 'Take a photo',
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(source: ImageSource.camera);
                },
              ),
            _AttachOption(
              icon: Icons.picture_as_pdf_outlined,
              label: 'PDF',
              subtitle: 'Pick a PDF document',
              onTap: () async {
                Navigator.pop(ctx);
                try {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['pdf'],
                    withData: true,
                  );
                  if (result != null && result.files.first.bytes != null) {
                    setState(() {
                      _attachments.add(InputAttachment(
                        name: result.files.first.name,
                        mimeType: 'application/pdf',
                        bytes: result.files.first.bytes!,
                        kind: AttachmentKind.pdf,
                      ));
                    });
                  }
                } catch (e) {
                  _showError('Failed to pick PDF: $e');
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 3)),
    );
  }

  String _guessMime(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'pdf' => 'application/pdf',
      'json' => 'application/json',
      'txt' => 'text/plain',
      'md' => 'text/markdown',
      'dart' => 'text/x-dart',
      'ts' || 'tsx' => 'text/typescript',
      'js' || 'jsx' => 'text/javascript',
      'py' => 'text/x-python',
      'rs' => 'text/x-rust',
      'go' => 'text/x-go',
      'yaml' || 'yml' => 'text/yaml',
      'csv' => 'text/csv',
      'html' => 'text/html',
      'css' => 'text/css',
      _ => 'application/octet-stream',
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Attachment previews ──
            if (_attachments.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: SizedBox(
                  height: 72,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _attachments.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) =>
                        _AttachmentChip(
                          attachment: _attachments[i],
                          onRemove: () => _removeAttachment(i),
                        ),
                  ),
                ),
              ),

            // ── Input row ──
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attach button
                  IconButton(
                    onPressed: widget.isLoading ? null : _showAttachMenu,
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: 'Attach file, image, or PDF',
                    color: cs.onSurfaceVariant,
                    iconSize: 24,
                  ),

                  // Text field
                  Expanded(
                    child: KeyboardListener(
                      focusNode: FocusNode(),
                      onKeyEvent: (event) {
                        if (event is KeyDownEvent &&
                            event.logicalKey == LogicalKeyboardKey.enter &&
                            !HardwareKeyboard.instance.isShiftPressed) {
                          _submit();
                        }
                      },
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLines: 8,
                        minLines: 1,
                        enabled: !widget.isLoading,
                        decoration: InputDecoration(
                          hintText: _attachments.isNotEmpty
                              ? 'Add a message or just send...'
                              : 'Ask anything...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        style: const TextStyle(fontSize: 14),
                        textInputAction: TextInputAction.newline,
                      ),
                    ),
                  ),

                  // Voice button
                  IconButton(
                    onPressed: widget.isLoading ? null : _toggleVoice,
                    icon: Icon(
                      _isRecording ? Icons.stop_circle : Icons.mic_outlined,
                      color: _isRecording ? cs.error : cs.onSurfaceVariant,
                    ),
                    tooltip: _isRecording ? 'Stop recording' : 'Voice input',
                    iconSize: 24,
                  ),

                  // Send button
                  IconButton.filled(
                    onPressed: widget.isLoading ? null : _submit,
                    icon: widget.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      minimumSize: const Size(44, 44),
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

// ─── Attachment chip (preview thumbnail) ───

class _AttachmentChip extends StatelessWidget {
  final InputAttachment attachment;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.attachment,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Stack(
        children: [
          // Content
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Thumbnail / icon
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: attachment.isImage
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            attachment.bytes,
                            fit: BoxFit.cover,
                            width: 40,
                            height: 40,
                          ),
                        )
                      : Icon(
                          attachment.kind == AttachmentKind.pdf
                              ? Icons.picture_as_pdf
                              : Icons.insert_drive_file,
                          size: 20,
                          color: cs.primary,
                        ),
                ),
                const SizedBox(width: 8),
                // Name + size
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        attachment.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatSize(attachment.bytes.length),
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Remove button
          Positioned(
            top: 2,
            right: 2,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.error.withValues(alpha: 0.8),
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

// ─── Attach option tile (for bottom sheet) ───

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cs.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: cs.primary, size: 22),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}
