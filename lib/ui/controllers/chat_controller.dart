import 'dart:convert';

import 'package:neomage/core/platform/neomage_io.dart';
import 'package:sint_sentinel/sint_sentinel.dart';

import 'package:flutter/foundation.dart';
import 'package:sint/sint.dart';
import 'package:uuid/uuid.dart';

import 'package:neomage/data/api/anthropic_client.dart';
import 'package:neomage/data/api/api_provider.dart';
import 'package:neomage/data/api/gemini_client.dart';
import 'package:neomage/data/api/openai_shim.dart';
import 'package:neomage/data/auth/auth_service.dart';
import 'package:neomage/data/hooks/hook_executor.dart';
import 'package:neomage/data/hooks/hook_types.dart';
import 'package:neomage/utils/config/settings.dart';
import 'package:neomage/data/engine/query_engine.dart';
import 'package:neomage/domain/models/message.dart';
import 'package:neomage/data/tools/bash_tool.dart';
import 'package:neomage/data/tools/file_edit_tool.dart';
import 'package:neomage/data/tools/file_read_tool.dart';
import 'package:neomage/data/tools/file_write_tool.dart';
import 'package:neomage/data/tools/glob_tool.dart';
import 'package:neomage/data/tools/grep_tool.dart';
import 'package:neomage/data/tools/tool.dart';
import 'package:neomage/data/tools/tool_registry.dart';
import 'package:neomage/data/compact/compaction_service.dart';
import 'package:neomage/data/session/session_history.dart';
import 'package:neomage/data/session/session_memory.dart';
import 'package:neomage/data/memdir/memdir_service.dart';
import 'package:neomage/data/commands/command.dart';
import 'package:neomage/data/commands/command_registry.dart';
import 'package:neomage/data/commands/builtin/clear_command.dart';
import 'package:neomage/data/commands/builtin/compact_command.dart';
import 'package:neomage/data/commands/builtin/cost_command.dart';
import 'package:neomage/data/commands/builtin/help_command.dart';
import 'package:neomage/data/commands/builtin/memory_command.dart';
import 'package:neomage/data/commands/builtin/model_command.dart';
import 'package:neomage/data/commands/builtin/session_command.dart';
import 'package:neomage/utils/constants/system.dart';
import 'package:neomage/utils/telemetry/telemetry_service.dart';
import 'package:neomage/data/analytics/analytics_service.dart';
import 'package:neomage/data/services/rate_limit_service.dart';
import 'package:neomage/core/agent/neomage_system_prompt.dart';
import '../widgets/input_bar.dart';

const _uuid = Uuid();

/// Main chat state controller — Sint pattern.
///
/// Wires together: QueryEngine, CompactionService, SessionMemoryService,
/// SessionHistoryManager, MemdirService, and JSONL transcript persistence.
class ChatController extends SintController {
  final AuthService _authService = AuthService();

  // Telemetry, analytics & rate limiting
  late final TelemetryService _telemetry;
  final AnalyticsService _analytics = AnalyticsService();
  RateLimitService? _rateLimitService;

  // Reactive state
  final messages = <Message>[].obs;
  final isLoading = false.obs;
  final isStreaming = false.obs;
  final streamingText = ''.obs;
  final error = Rxn<String>();
  final currentToolName = Rxn<String>();
  final lastUsage = Rxn<TokenUsage>();
  final sessionId = ''.obs;
  final totalInputTokens = 0.obs;
  final totalOutputTokens = 0.obs;
  final compactionCount = 0.obs;

  // Hook executor for lifecycle hooks
  late final HookExecutor _hookExecutor;

  // Non-reactive internals
  ApiProvider? _provider;
  QueryEngine? _engine;
  ToolRegistry? _toolRegistry;
  CompactionService? _compactionService;
  SessionHistoryManager? _sessionHistoryManager;
  SessionMemoryService? _sessionMemoryService;
  MemdirService? _memdirService;
  String? _transcriptPath;
  late final CommandRegistry _commandRegistry;

  bool get isInitialized => _engine != null;

  /// Exposes the hook executor so callers can register custom hooks.
  HookExecutor get hookExecutor => _hookExecutor;

  @override
  void onInit() {
    super.onInit();
    _hookExecutor = HookExecutor();
    _telemetry = TelemetryService(config: TelemetryConfig.development());
    _analytics.attachSink(InMemoryAnalyticsSink());
    _commandRegistry = CommandRegistry();
    _initializeIfConfigured();
  }

  @override
  void onClose() {
    // Auto-save session on close
    _autoSaveSession();
    _telemetry.endSession(metadata: {
      'totalInputTokens': totalInputTokens.value,
      'totalOutputTokens': totalOutputTokens.value,
    });
    _hookExecutor.executeAsync(
      HookType.onSessionEnd,
      HookContext.now(
        hookType: HookType.onSessionEnd,
        sessionId: sessionId.value,
      ),
    ).ignore();
    _hookExecutor.dispose();
    _analytics.dispose();
    _telemetry.dispose();
    _commandRegistry.dispose();
    super.onClose();
  }

  Future<void> _initializeIfConfigured() async {
    final hasConfig = await _authService.hasValidConfig();
    if (hasConfig) {
      await initialize();
    }
  }

  // ── Initialization ──

  Future<bool> initialize() async {
    SintSentinel.logger.i('ChatController.initialize() starting...');
    final config = await _authService.loadApiConfig();
    if (config == null) return false;

    _provider = _createProvider(config);
    _toolRegistry = _createToolRegistry();

    final settings = await AppSettings.load();

    // Generate session ID
    sessionId.value = _uuid.v4();

    // Initialize session history manager (saves/loads full sessions)
    if (!kIsWeb) {
      _sessionHistoryManager = SessionHistoryManager(
        baseDir: SystemConstants.sessionDir,
      );
    }

    // Initialize compaction service (auto-compact + microcompact)
    _compactionService = CompactionService(provider: _provider!);

    // Initialize session memory (periodic extraction)
    if (!kIsWeb) {
      final projectDir = Directory.current.path;
      _sessionMemoryService = SessionMemoryService(
        sessionId: sessionId.value,
        projectDir: '${SystemConstants.configDir}/projects/${_sanitizePath(projectDir)}',
      );
    }

    // Initialize memdir (persistent memory across sessions)
    if (!kIsWeb) {
      _memdirService = MemdirService(projectRoot: Directory.current.path);
    }

    // Load personality modules (IDENTITY, COGNITION, CAPABILITIES, TOOLS, etc.)
    await NeomageSystemPrompt.load();

    // Build memdir context
    String? memoryContext;
    if (_memdirService != null) {
      try {
        final memoryResult = await _memdirService!.loadMemoryPrompt();
        memoryContext = memoryResult.prompt;
        SintSentinel.logger.i(
          'Loaded ${memoryResult.memoryFileCount} memory files into context',
        );
      } catch (e) {
        SintSentinel.logger.w('Failed to load memory prompt: $e');
      }
    }

    // Load NEOMAGE.md / project instructions
    final neomageInstructions = await _loadNeomageInstructions();

    // Load existing session memory if resuming
    String? sessionMemoryContext;
    if (_sessionMemoryService != null) {
      try {
        sessionMemoryContext = await _sessionMemoryService!.load();
      } catch (_) {}
    }

    // Detect working directory, git branch, and platform info
    String workingDir = '.';
    String? gitBranch;
    bool isGitRepo = false;
    String? platformInfo;
    if (!kIsWeb) {
      workingDir = Directory.current.path;
      try {
        final branchResult = await Process.run('git', ['branch', '--show-current'],
            workingDirectory: workingDir);
        if (branchResult.exitCode == 0) {
          gitBranch = (branchResult.stdout as String).trim();
          isGitRepo = true;
        }
      } catch (_) {}
      try {
        final unameResult = await Process.run('uname', ['-sr']);
        if (unameResult.exitCode == 0) {
          platformInfo = (unameResult.stdout as String).trim();
        }
      } catch (_) {
        platformInfo = Platform.operatingSystem;
      }
    } else {
      platformInfo = 'Web';
    }

    // Build the full system prompt from personality modules + dynamic context.
    // If user has a custom system prompt override, use that instead of modules.
    String systemPrompt;
    if (settings.customSystemPrompt != null) {
      systemPrompt = settings.customSystemPrompt!;
    } else {
      // Combine memdir + session memory into single memory block
      final combinedMemory = [
        if (memoryContext != null && memoryContext.isNotEmpty) memoryContext,
        if (sessionMemoryContext != null && sessionMemoryContext.isNotEmpty)
          '<session_memory>\n$sessionMemoryContext\n</session_memory>',
      ].join('\n\n');

      systemPrompt = NeomageSystemPrompt.build(
        model: config.model,
        workingDirectory: workingDir,
        gitBranch: gitBranch,
        isGitRepo: isGitRepo,
        platform: platformInfo,
        projectFramework: 'Flutter/Dart',
        userInstructions: neomageInstructions,
        memoryContext: combinedMemory.isEmpty ? null : combinedMemory,
      );
    }

    // Create query engine with ALL services connected
    _engine = QueryEngine(
      provider: _provider!,
      toolRegistry: _toolRegistry!,
      systemPrompt: systemPrompt,
      compactionService: _compactionService,
      sessionMemory: _sessionMemoryService,
    );

    // Initialize rate limit service
    _rateLimitService = RateLimitService(
      apiKey: config.apiKey,
      baseUrl: config.baseUrl,
      cacheDir: SystemConstants.configDir,
    );
    // Load policies in background — fail-open if unavailable
    _rateLimitService!.loadPolicies().ignore();

    // Start telemetry session
    _telemetry.startSession(metadata: {
      'sessionId': sessionId.value,
      'provider': config.type.name,
      'model': config.model,
    });

    // Register slash commands
    _registerBuiltinCommands();

    // Initialize transcript file for JSONL persistence
    if (!kIsWeb) {
      _transcriptPath = '${SystemConstants.sessionDir}/${sessionId.value}.jsonl';
      await _ensureTranscriptDir();
    }

    // Try to restore last session if no messages
    if (messages.isEmpty && !kIsWeb) {
      await _tryRestoreLastSession();
    }

    // Fire session_start lifecycle hook
    await _hookExecutor.executeAsync(
      HookType.onSessionStart,
      HookContext.now(
        hookType: HookType.onSessionStart,
        sessionId: sessionId.value,
        metadata: {
          'provider': config.type.name,
          'model': config.model,
        },
      ),
    );

    update();
    SintSentinel.logger.i(
      'ChatController.initialize() completed — '
      'session=${sessionId.value}, '
      'compaction=${_compactionService != null}, '
      'sessionMemory=${_sessionMemoryService != null}, '
      'memdir=${_memdirService != null}, '
      'transcript=${_transcriptPath != null}',
    );
    return true;
  }

  ApiProvider _createProvider(ApiConfig config) {
    SintSentinel.logger.d('Creating provider for type: ${config.type.name}');
    return switch (config.type) {
      ApiProviderType.anthropic => AnthropicClient(config),
      ApiProviderType.gemini => GeminiClient(config),
      _ => OpenAiShim(config),
    };
  }

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

  Future<void> sendMessage(
    String text, {
    List<InputAttachment> attachments = const [],
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;
    if (_engine == null) return;

    SintSentinel.logger.d(
      'sendMessage: ${text.length} chars, ${attachments.length} attachments',
    );

    // Rate-limit check before calling the API
    if (_rateLimitService != null &&
        !_rateLimitService!.isPolicyAllowed('api_call')) {
      error.value = 'Rate limited — please wait before sending another message.';
      _telemetry.trackError(
        message: 'Rate limited',
        context: 'sendMessage',
        errorCode: 'RATE_LIMITED',
      );
      _analytics.logEvent(AnalyticsEvents.apiError, {
        'reason': 'rate_limited',
      });
      return;
    }

    error.value = null;
    isLoading.value = true;
    isStreaming.value = true;
    streamingText.value = '';
    currentToolName.value = null;

    // Build content blocks: images first, then text
    final content = <ContentBlock>[];
    for (final att in attachments) {
      if (att.isImage) {
        content.add(
          ImageBlock(mediaType: att.mimeType, base64Data: att.base64Data),
        );
      } else {
        // Non-image files: include as text with filename context
        final decoded = _tryDecodeText(att.bytes);
        if (decoded != null) {
          content.add(TextBlock('[File: ${att.name}]\n$decoded'));
        } else {
          content.add(
            TextBlock(
              '[Attached binary file: ${att.name} '
              '(${att.bytes.length} bytes)]',
            ),
          );
        }
      }
    }
    if (text.trim().isNotEmpty) {
      content.add(TextBlock(text));
    }

    final userMessage = Message(role: MessageRole.user, content: content);
    messages.add(userMessage);

    // Persist user message to JSONL transcript
    _appendToTranscript(userMessage);

    // Track message_sent
    _telemetry.track(TelemetryEvent(
      name: 'message_sent',
      type: TelemetryEventType.apiCall,
      properties: {
        'charCount': text.length,
        'attachmentCount': attachments.length,
      },
    ));
    _analytics.logEvent('message_sent', {
      'charCount': text.length,
      'attachmentCount': attachments.length,
    });

    _telemetry.performance.start('api_call');

    // Fire preMessage lifecycle hook
    final preMessageResult = await _hookExecutor.executeAsync(
      HookType.preMessage,
      MessageHookContext(
        hookType: HookType.preMessage,
        timestamp: DateTime.now(),
        sessionId: sessionId.value,
        role: 'user',
        content: text,
        messageTurnIndex: messages.length,
      ),
    );
    if (preMessageResult is HookAbort) {
      error.value = 'Message blocked by hook: ${preMessageResult.reason}';
      isLoading.value = false;
      isStreaming.value = false;
      return;
    }

    try {
      final response = await _engine!.query(
        messages: messages.toList(),
        onTextDelta: (delta) {
          streamingText.value += delta;
        },
        onToolUse: (name, input) {
          SintSentinel.logger.d('Tool use: $name');
          currentToolName.value = name;
          _hookExecutor.executeAsync(
            HookType.preToolExecution,
            ToolHookContext(
              hookType: HookType.preToolExecution,
              timestamp: DateTime.now(),
              sessionId: sessionId.value,
              toolName: name,
              toolInput: input,
            ),
          ).ignore();
          _telemetry.performance.start('tool_$name');
          _analytics.logEvent(AnalyticsEvents.toolUseGranted, {'tool': name});
        },
        onToolResult: (name, result) {
          SintSentinel.logger.d('Tool result: $name');
          _hookExecutor.executeAsync(
            HookType.postToolExecution,
            ToolHookContext(
              hookType: HookType.postToolExecution,
              timestamp: DateTime.now(),
              sessionId: sessionId.value,
              toolName: name,
              toolInput: const {},
              toolOutput: result.content,
              toolIsError: result.isError,
            ),
          ).ignore();
          final toolDuration = _telemetry.performance.stop('tool_$name');
          _telemetry.trackToolUse(
            toolName: name,
            duration: toolDuration ?? Duration.zero,
          );
          _telemetry.track(TelemetryEvent(
            name: 'tool_executed',
            type: TelemetryEventType.toolUse,
            properties: {'tool': name},
          ));
          _analytics.logEvent(AnalyticsEvents.toolUseSuccess, {'tool': name});
          currentToolName.value = null;
        },
        onCompaction: (result) {
          compactionCount.value++;
          SintSentinel.logger.i(
            'Auto-compacted: ${result.preCompactTokenCount} → '
            '${result.postCompactTokenCount} tokens '
            '(strategy: ${result.strategy.name})',
          );
          // Update messages list with compacted version
          messages.assignAll(result.compactedMessages);
          _telemetry.track(TelemetryEvent(
            name: 'compaction_triggered',
            type: TelemetryEventType.compaction,
            properties: {
              'strategy': result.strategy.name,
              'preTokens': result.preCompactTokenCount,
              'postTokens': result.postCompactTokenCount,
            },
          ));
          _analytics.logEvent(AnalyticsEvents.compactionTriggered, {
            'strategy': result.strategy.name,
          });
        },
      );

      // Stop API call perf timer and track the call
      final apiDuration = _telemetry.performance.stop('api_call');
      _telemetry.trackApiCall(
        model: _provider?.config.model ?? 'unknown',
        latency: apiDuration ?? Duration.zero,
        inputTokens: response.usage?.inputTokens,
        outputTokens: response.usage?.outputTokens,
      );

      // Track message_received
      _telemetry.track(TelemetryEvent(
        name: 'message_received',
        type: TelemetryEventType.apiCall,
        properties: {
          'inputTokens': response.usage?.inputTokens,
          'outputTokens': response.usage?.outputTokens,
        },
      ));
      _analytics.logEvent(AnalyticsEvents.apiSuccess, {
        'inputTokens': response.usage?.inputTokens,
        'outputTokens': response.usage?.outputTokens,
      });

      messages.add(response);
      lastUsage.value = response.usage;
      streamingText.value = '';
      isStreaming.value = false;

      // Track token usage
      if (response.usage != null) {
        totalInputTokens.value += response.usage!.inputTokens;
        totalOutputTokens.value += response.usage!.outputTokens;
      }

      // Persist assistant response to JSONL transcript
      _appendToTranscript(response);

      // Auto-save session snapshot after each exchange
      _autoSaveSession();

      // Track session_saved
      _telemetry.track(TelemetryEvent(
        name: 'session_saved',
        type: TelemetryEventType.sessionStart,
        properties: {'messageCount': messages.length},
      ));

      // Trigger session memory extraction if thresholds met
      _tryExtractSessionMemory();

      // Fire postMessage lifecycle hook
      _hookExecutor.executeAsync(
        HookType.postMessage,
        MessageHookContext(
          hookType: HookType.postMessage,
          timestamp: DateTime.now(),
          sessionId: sessionId.value,
          role: 'assistant',
          content: response.textContent,
          messageTurnIndex: messages.length,
        ),
      ).ignore();
    } catch (e) {
      SintSentinel.logger.e('sendMessage error', error: e);
      error.value = e.toString();
      isStreaming.value = false;
      // Stop perf timer on error path
      _telemetry.performance.stop('api_call');
      // Track error_occurred
      _telemetry.trackError(
        message: e.toString(),
        context: 'sendMessage',
      );
      _analytics.logEvent(AnalyticsEvents.apiError, {
        'error': e.toString(),
      });
    }

    isLoading.value = false;
  }

  void clearConversation() {
    // Save current session before clearing
    _autoSaveSession();

    messages.clear();
    error.value = null;
    streamingText.value = '';
    lastUsage.value = null;
    totalInputTokens.value = 0;
    totalOutputTokens.value = 0;
    compactionCount.value = 0;

    // Start a new session
    sessionId.value = _uuid.v4();
    if (!kIsWeb) {
      _transcriptPath =
          '${SystemConstants.sessionDir}/${sessionId.value}.jsonl';
      _sessionMemoryService = SessionMemoryService(
        sessionId: sessionId.value,
        projectDir: _sessionMemoryService?.projectDir ?? SystemConstants.configDir,
        config: _sessionMemoryService?.config ?? const SessionMemoryConfig(),
      );
      _engine?.sessionMemory = _sessionMemoryService;
    }
  }

  Future<void> reconfigure() async {
    _provider = null;
    _engine = null;
    _compactionService = null;
    _sessionMemoryService = null;
    await initialize();
  }

  /// Send a context signal (silent skill/personality injection).
  Future<void> sendContextSignal(String contextPrompt) async {
    if (_engine == null) return;

    SintSentinel.logger.d('sendContextSignal: ${contextPrompt.length} chars');

    final contextMessage = Message(
      role: MessageRole.user,
      content: [TextBlock(contextPrompt)],
    );
    messages.add(contextMessage);
    _appendToTranscript(contextMessage);

    try {
      isLoading.value = true;
      final response = await _engine!.query(
        messages: messages.toList(),
        onTextDelta: (delta) {},
      );

      messages.add(Message(
        role: MessageRole.assistant,
        content: response.content,
      ));
      _appendToTranscript(response);
    } catch (e) {
      SintSentinel.logger.e('sendContextSignal error', error: e);
    }

    isLoading.value = false;
  }

  // ── Session Management ──

  /// List all saved sessions, newest first.
  Future<List<String>> listSessions() async {
    if (_sessionHistoryManager == null) return const [];
    return _sessionHistoryManager!.listSessions();
  }

  /// Load a specific session by ID.
  Future<bool> loadSession(String id) async {
    if (_sessionHistoryManager == null) return false;

    final snapshot = await _sessionHistoryManager!.loadSession(id);
    if (snapshot == null) return false;

    messages.assignAll(snapshot.messages);
    sessionId.value = snapshot.sessionId;

    if (!kIsWeb) {
      _transcriptPath = '${SystemConstants.sessionDir}/$id.jsonl';
    }

    SintSentinel.logger.i(
      'Loaded session $id with ${snapshot.messages.length} messages',
    );
    return true;
  }

  /// Delete a saved session.
  Future<bool> deleteSession(String id) async {
    if (_sessionHistoryManager == null) return false;

    // Also delete transcript
    try {
      final transcriptFile =
          File('${SystemConstants.sessionDir}/$id.jsonl');
      if (await transcriptFile.exists()) {
        await transcriptFile.delete();
      }
    } catch (_) {}

    return _sessionHistoryManager!.deleteSession(id);
  }

  /// Manually trigger compaction.
  Future<bool> compactConversation() async {
    if (_compactionService == null || messages.length < 4) return false;

    try {
      final result = await _compactionService!.compactConversation(
        messages: messages.toList(),
        systemPrompt: _engine?.systemPrompt ?? '',
      );
      messages.assignAll(result.compactedMessages);
      compactionCount.value++;
      SintSentinel.logger.i(
        'Manual compaction: ${result.preCompactTokenCount} → '
        '${result.postCompactTokenCount} tokens',
      );
      return true;
    } catch (e) {
      SintSentinel.logger.e('Compaction failed', error: e);
      return false;
    }
  }

  /// Get session history manager for direct snapshot access.
  SessionHistoryManager? get sessionHistoryManager => _sessionHistoryManager;

  /// Get memdir service for memory panel access.
  MemdirService? get memdirService => _memdirService;

  // ── Slash Commands ──

  /// Handle user input — dispatches slash commands or sends as a message.
  Future<void> handleInput(
    String text, {
    List<InputAttachment> attachments = const [],
  }) async {
    if (text.trim().isEmpty && attachments.isEmpty) return;

    final trimmed = text.trim();
    if (trimmed.startsWith('/')) {
      await _dispatchCommand(trimmed);
    } else {
      await sendMessage(text, attachments: attachments);
    }
  }

  Future<void> _dispatchCommand(String input) async {
    // Parse "/name args..." from the input
    final withoutSlash = input.substring(1);
    final spaceIndex = withoutSlash.indexOf(' ');
    final name = spaceIndex == -1
        ? withoutSlash
        : withoutSlash.substring(0, spaceIndex);
    final args = spaceIndex == -1
        ? ''
        : withoutSlash.substring(spaceIndex + 1).trim();

    if (!_commandRegistry.isValid(name)) {
      _addCommandResultMessage('Unknown command: /$name\n'
          'Type /help for available commands.');
      return;
    }

    final context = ToolUseContext(cwd: Directory.current.path);

    // Handle /clear specially — it needs to call clearConversation()
    final reg = _commandRegistry.get(name);
    if (reg != null && reg.name == 'clear') {
      clearConversation();
      _addCommandResultMessage('Conversation cleared.');
      return;
    }

    // Track command_dispatched
    _telemetry.track(TelemetryEvent(
      name: 'command_dispatched',
      type: TelemetryEventType.commandRun,
      properties: {'command': name},
    ));
    _analytics.logEvent(AnalyticsEvents.commandExecuted, {'command': name});

    final result = await _commandRegistry.execute(name, args, context);
    if (result == null) {
      _addCommandResultMessage('Command /$name did not produce a result.');
      return;
    }

    switch (result) {
      case TextCommandResult(value: final text):
        _addCommandResultMessage(text);
      case CompactCommandResult(
        compactedMessages: final compacted,
        displayText: final display,
      ):
        messages.assignAll(compacted);
        compactionCount.value++;
        if (display != null) {
          _addCommandResultMessage(display);
        }
      case SkipCommandResult():
        break;
    }
  }

  /// Add a command result as an assistant message in the conversation.
  void _addCommandResultMessage(String text) {
    final msg = Message(
      role: MessageRole.assistant,
      content: [TextBlock(text)],
    );
    messages.add(msg);
    _appendToTranscript(msg);
  }

  /// Register built-in slash commands into the command registry.
  void _registerBuiltinCommands() {
    _commandRegistry.clear();

    // Session commands
    _commandRegistry.registerBuiltinCommands(
      sessionCommands: [
        ClearCommand(),
        if (_compactionService != null)
          CompactCommand(
            compactionService: _compactionService!,
            getMessages: () => messages.toList(),
            getSystemPrompt: () => _engine?.systemPrompt ?? '',
          ),
      ],
      debugCommands: [
        CostCommand(getMessages: () => messages.toList()),
      ],
      configCommands: [
        ModelCommand(
          getCurrentModel: () => _provider?.config.model ?? 'unknown',
          onModelChange: (model) {
            // Reconfigure with new model
            if (_provider != null) {
              final newConfig = ApiConfig(
                type: _provider!.config.type,
                apiKey: _provider!.config.apiKey,
                model: model,
                baseUrl: _provider!.config.baseUrl,
              );
              _provider = _createProvider(newConfig);
              if (_engine != null) {
                _engine = QueryEngine(
                  provider: _provider!,
                  toolRegistry: _toolRegistry!,
                  systemPrompt: _engine!.systemPrompt,
                  compactionService: _compactionService,
                  sessionMemory: _sessionMemoryService,
                );
              }
            }
          },
        ),
      ],
      helpCommands: [
        HelpCommand(registry: _commandRegistry),
      ],
    );

    // Commands that require non-web services
    if (!kIsWeb) {
      if (_memdirService != null) {
        _commandRegistry.register(
          MemoryCommand(memdir: _memdirService!),
          category: CommandCategory.session,
        );
      }
      if (_sessionHistoryManager != null) {
        _commandRegistry.register(
          SessionCommand(
            historyManager: _sessionHistoryManager!,
            getCurrentSessionId: () => sessionId.value,
          ),
          category: CommandCategory.session,
        );
      }
    }
  }

  // ── Private: Transcript Persistence (JSONL) ──

  Future<void> _ensureTranscriptDir() async {
    if (_transcriptPath == null) return;
    final dir = Directory(SystemConstants.sessionDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Append a single message to the JSONL transcript file.
  void _appendToTranscript(Message message) {
    if (_transcriptPath == null || kIsWeb) return;

    try {
      final file = File(_transcriptPath!);
      final json = jsonEncode(_messageToJsonl(message));
      file.writeAsStringSync('$json\n', mode: FileMode.append, flush: true);
    } catch (e) {
      SintSentinel.logger.w('Failed to write transcript: $e');
    }
  }

  Map<String, dynamic> _messageToJsonl(Message m) => {
    'id': m.id,
    'role': m.role.name,
    'timestamp': m.timestamp.toIso8601String(),
    'content': m.content.map(_blockToJsonl).toList(),
    if (m.stopReason != null) 'stopReason': m.stopReason!.name,
    if (m.usage != null)
      'usage': {
        'input_tokens': m.usage!.inputTokens,
        'output_tokens': m.usage!.outputTokens,
      },
  };

  Map<String, dynamic> _blockToJsonl(ContentBlock block) => switch (block) {
    TextBlock(text: final t) => {'type': 'text', 'text': t},
    ToolUseBlock(id: final id, name: final n, input: final i) => {
      'type': 'tool_use',
      'id': id,
      'name': n,
      'input': i,
    },
    ToolResultBlock(
      toolUseId: final tid,
      content: final c,
      isError: final e,
    ) =>
      {
        'type': 'tool_result',
        'tool_use_id': tid,
        'content': c,
        if (e) 'is_error': true,
      },
    ImageBlock(mediaType: final mt, base64Data: final d) => {
      'type': 'image',
      'media_type': mt,
      'data': d,
    },
  };

  // ── Private: Session Save/Load ──

  Future<void> _autoSaveSession() async {
    if (_sessionHistoryManager == null || messages.isEmpty) return;

    try {
      final snapshot = SessionSnapshot(
        sessionId: sessionId.value,
        createdAt: messages.first.timestamp,
        updatedAt: DateTime.now(),
        messages: messages.toList(),
        metadata: {
          'totalInputTokens': totalInputTokens.value,
          'totalOutputTokens': totalOutputTokens.value,
          'compactionCount': compactionCount.value,
          'messageCount': messages.length,
        },
      );
      await _sessionHistoryManager!.saveSession(snapshot);
    } catch (e) {
      SintSentinel.logger.w('Failed to auto-save session: $e');
    }
  }

  Future<void> _tryRestoreLastSession() async {
    if (_sessionHistoryManager == null) return;

    try {
      final lastId = await _sessionHistoryManager!.getMostRecentSession();
      if (lastId == null) return;

      // Only restore if the session is recent (last 24h)
      final snapshot = await _sessionHistoryManager!.loadSession(lastId);
      if (snapshot == null) return;

      final age = DateTime.now().difference(snapshot.updatedAt);
      if (age.inHours > 24) return;

      // Don't auto-restore, but set session ID so we can resume if wanted
      SintSentinel.logger.i(
        'Found recent session $lastId (${snapshot.messages.length} msgs, '
        '${age.inMinutes}min ago) — available for restore',
      );
    } catch (e) {
      SintSentinel.logger.w('Failed to check for restorable session: $e');
    }
  }

  // ── Private: Session Memory Extraction ──

  Future<void> _tryExtractSessionMemory() async {
    if (_sessionMemoryService == null) return;
    if (!_sessionMemoryService!.shouldExtract()) return;

    try {
      SintSentinel.logger.d('Extracting session memory...');
      await _sessionMemoryService!.extract(messages.toList());
      SintSentinel.logger.i(
        'Session memory extracted '
        '(extraction #${_sessionMemoryService!.state.extractionCount})',
      );
    } catch (e) {
      SintSentinel.logger.w('Session memory extraction failed: $e');
    }
  }

  // ── Private: NEOMAGE.md Instructions ──

  /// Load NEOMAGE.md instructions from multiple locations (priority order):
  /// 1. Project-local: .neomage/NEOMAGE.md (or NEOMAGE.md in cwd)
  /// 2. User global: ~/.neomage/NEOMAGE.md
  /// 3. Rules dir: .neomage/rules/*.md
  Future<String?> _loadNeomageInstructions() async {
    if (kIsWeb) return null;

    final sections = <String>[];

    // 1. User-global NEOMAGE.md
    try {
      final globalFile = File(SystemConstants.memoryFile);
      if (await globalFile.exists()) {
        final content = await globalFile.readAsString();
        if (content.trim().isNotEmpty) {
          sections.add('# User Instructions (global)\n\n$content');
        }
      }
    } catch (_) {}

    // 2. Project-local NEOMAGE.md (search upward from cwd)
    try {
      final projectInstructions = await _findProjectNeomageFile();
      if (projectInstructions != null) {
        sections.add('# Project Instructions\n\n$projectInstructions');
      }
    } catch (_) {}

    // 3. Rules directory: .neomage/rules/*.md
    try {
      final rulesDir = Directory('.neomage/rules');
      if (await rulesDir.exists()) {
        await for (final entity in rulesDir.list()) {
          if (entity is File && entity.path.endsWith('.md')) {
            final content = await entity.readAsString();
            if (content.trim().isNotEmpty) {
              final name = entity.path.split('/').last;
              sections.add('# Rule: $name\n\n$content');
            }
          }
        }
      }
    } catch (_) {}

    if (sections.isEmpty) return null;

    return '<neomage_instructions>\n${sections.join('\n\n---\n\n')}\n</neomage_instructions>';
  }

  /// Search upward from cwd for NEOMAGE.md or .neomage/NEOMAGE.md.
  Future<String?> _findProjectNeomageFile() async {
    var dir = Directory.current;
    for (var depth = 0; depth < 10; depth++) {
      // Check .neomage/NEOMAGE.md
      final dotFile = File('${dir.path}/.neomage/NEOMAGE.md');
      if (await dotFile.exists()) {
        return dotFile.readAsString();
      }

      // Check NEOMAGE.md in root
      final rootFile = File('${dir.path}/NEOMAGE.md');
      if (await rootFile.exists()) {
        return rootFile.readAsString();
      }

      // Go up
      final parent = dir.parent;
      if (parent.path == dir.path) break; // reached filesystem root
      dir = parent;
    }
    return null;
  }

  // ── Private: Utils ──

  /// Try to decode bytes as UTF-8 text, return null if binary.
  String? _tryDecodeText(Uint8List bytes) {
    try {
      final text = utf8.decode(bytes);
      // Heuristic: if too many control chars, it's binary
      final controlCount = text.codeUnits
          .where((c) => c < 32 && c != 10 && c != 13 && c != 9)
          .length;
      if (controlCount > text.length * 0.1) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  String _sanitizePath(String path) {
    return path
        .replaceAll(RegExp(r'^[/\\]+'), '')
        .replaceAll(RegExp(r'[/\\]'), '-');
  }
}
