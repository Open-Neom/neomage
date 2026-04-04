import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_claw/core/platform/claw_io.dart';

import 'package:flutter/foundation.dart';
import 'package:sint/sint.dart';

import '../../data/api/anthropic_client.dart';
import '../../data/api/api_provider.dart';
import '../../data/api/openai_shim.dart';
import '../../data/auth/auth_service.dart';
import '../../utils/config/settings.dart';
import '../../data/engine/query_engine.dart';
import '../../domain/models/message.dart';
import '../../data/tools/bash_tool.dart';
import '../../data/tools/file_edit_tool.dart';
import '../../data/tools/file_read_tool.dart';
import '../../data/tools/file_write_tool.dart';
import '../../data/tools/glob_tool.dart';
import '../../data/tools/grep_tool.dart';
import '../../data/tools/tool_registry.dart';
import '../widgets/input_bar.dart';

/// Main chat state controller — Sint pattern.
class ChatController extends SintController {
  final AuthService _authService = AuthService();

  // Reactive state
  final messages = <Message>[].obs;
  final isLoading = false.obs;
  final isStreaming = false.obs;
  final streamingText = ''.obs;
  final error = Rxn<String>();
  final currentToolName = Rxn<String>();
  final lastUsage = Rxn<TokenUsage>();

  // Non-reactive internals
  ApiProvider? _provider;
  QueryEngine? _engine;
  ToolRegistry? _toolRegistry;

  bool get isInitialized => _engine != null;

  @override
  void onInit() {
    super.onInit();
    _initializeIfConfigured();
  }

  Future<void> _initializeIfConfigured() async {
    final hasConfig = await _authService.hasValidConfig();
    if (hasConfig) {
      await initialize();
    }
  }

  // ── Initialization ──

  Future<bool> initialize() async {
    final config = await _authService.loadApiConfig();
    if (config == null) return false;

    _provider = _createProvider(config);
    _toolRegistry = _createToolRegistry();

    final settings = await AppSettings.load();

    _engine = QueryEngine(
      provider: _provider!,
      toolRegistry: _toolRegistry!,
      systemPrompt:
          settings.customSystemPrompt ?? AppSettings.defaultSystemPrompt,
    );

    update();
    return true;
  }

  ApiProvider _createProvider(ApiConfig config) => switch (config.type) {
        ApiProviderType.anthropic => AnthropicClient(config),
        _ => OpenAiShim(config),
      };

  ToolRegistry _createToolRegistry() {
    final registry = ToolRegistry();

    if (!kIsWeb) {
      if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
        registry.register(BashTool());
      }
      registry.register(FileReadTool());
      registry.register(FileWriteTool());
      registry.register(FileEditTool());
      registry.register(GrepTool());
      registry.register(GlobTool());
    }

    return registry;
  }

  // ── Chat ──

  Future<void> sendMessage(String text,
      {List<InputAttachment> attachments = const []}) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;
    if (_engine == null) return;

    error.value = null;
    isLoading.value = true;
    isStreaming.value = true;
    streamingText.value = '';
    currentToolName.value = null;

    // Build content blocks: images first, then text
    final content = <ContentBlock>[];
    for (final att in attachments) {
      if (att.isImage) {
        content.add(ImageBlock(
          mediaType: att.mimeType,
          base64Data: att.base64Data,
        ));
      } else {
        // Non-image files: include as text with filename context
        final decoded = _tryDecodeText(att.bytes);
        if (decoded != null) {
          content
              .add(TextBlock('[File: ${att.name}]\n$decoded'));
        } else {
          content.add(TextBlock(
              '[Attached binary file: ${att.name} '
              '(${att.bytes.length} bytes)]'));
        }
      }
    }
    if (text.trim().isNotEmpty) {
      content.add(TextBlock(text));
    }

    final userMessage = Message(
      role: MessageRole.user,
      content: content,
    );
    messages.add(userMessage);

    try {
      final response = await _engine!.query(
        messages: messages.toList(),
        onTextDelta: (delta) {
          streamingText.value += delta;
        },
        onToolUse: (name, input) {
          currentToolName.value = name;
        },
        onToolResult: (name, result) {
          currentToolName.value = null;
        },
      );

      messages.add(response);
      lastUsage.value = response.usage;
      streamingText.value = '';
      isStreaming.value = false;
    } catch (e) {
      error.value = e.toString();
      isStreaming.value = false;
    }

    isLoading.value = false;
  }

  void clearConversation() {
    messages.clear();
    error.value = null;
    streamingText.value = '';
    lastUsage.value = null;
  }

  Future<void> reconfigure() async {
    _provider = null;
    _engine = null;
    await initialize();
  }

  /// Try to decode bytes as UTF-8 text, return null if binary.
  String? _tryDecodeText(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      // Heuristic: if too many control chars, it's binary
      final controlCount =
          text.codeUnits.where((c) => c < 32 && c != 10 && c != 13 && c != 9).length;
      if (controlCount > text.length * 0.1) return null;
      return text;
    } catch (_) {
      return null;
    }
  }
}
