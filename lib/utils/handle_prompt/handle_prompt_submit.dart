/// Prompt submission pipeline: validation, exit commands, slash-command dispatch,
/// queuing under concurrency guard, reference expansion, external editor
/// integration, embedded shell command execution, and prompt category
/// classification for analytics.
///
/// Port of:
///   neomage/src/utils/handlePromptSubmit.ts (610 LOC)
///   neomage/src/utils/promptEditor.ts (188 LOC)
///   neomage/src/utils/promptShellExecution.ts (183 LOC)
///   neomage/src/utils/promptCategory.ts (49 LOC)
library;

import 'dart:async';
import 'package:neomage/core/platform/neomage_io.dart';

import 'package:path/path.dart' as p;
import 'package:sint/sint.dart';

import '../config/config_full.dart';

// ===================================================================
// Prompt Input Types
// ===================================================================

/// Modes in which prompt text can be submitted.
enum PromptInputMode { prompt, bash, taskNotification }

/// Item queued for deferred execution when the model is busy.
class QueuedCommand {
  final String value;
  final String? preExpansionValue;
  final PromptInputMode mode;
  final Map<int, PastedContent>? pastedContents;
  final bool? skipSlashCommands;
  final String? uuid;
  final String? workload;
  final MessageOrigin? origin;
  final String? bridgeOrigin;
  final bool? isMeta;

  const QueuedCommand({
    required this.value,
    this.preExpansionValue,
    this.mode = PromptInputMode.prompt,
    this.pastedContents,
    this.skipSlashCommands,
    this.uuid,
    this.workload,
    this.origin,
    this.bridgeOrigin,
    this.isMeta,
  });
}

/// Origin of a message for attribution.
sealed class MessageOrigin {
  const MessageOrigin();
}

class TaskNotificationOrigin extends MessageOrigin {
  const TaskNotificationOrigin();
}

class BridgeMessageOrigin extends MessageOrigin {
  final String bridgeId;
  const BridgeMessageOrigin({required this.bridgeId});
}

/// Spinner display mode.
enum SpinnerMode { streaming, thinking, toolUse }

/// Query source for analytics.
typedef QuerySource = String;

/// Reference found in pasted text.
class ParsedReference {
  final int id;
  final String raw;

  const ParsedReference({required this.id, required this.raw});
}

/// Effort value for controlling response depth.
typedef EffortValue = String;

// ===================================================================
// Prompt Input Helpers
// ===================================================================

/// Helpers passed to the submit handler for managing the input buffer.
class PromptInputHelpers {
  final void Function(int offset) setCursorOffset;
  final void Function() clearBuffer;
  final void Function() resetHistory;

  const PromptInputHelpers({
    required this.setCursorOffset,
    required this.clearBuffer,
    required this.resetHistory,
  });
}

// ===================================================================
// Query Guard — concurrency serializer
// ===================================================================

/// Concurrency guard that serializes query execution.
///
/// Mirrors the TS `QueryGuard` used by handlePromptSubmit to
/// determine whether the model is currently processing. When active,
/// new submissions are queued instead of executed immediately.
class QueryGuard {
  bool _isActive = false;
  bool _isReserved = false;

  /// True when the guard is either active (query running) or reserved
  /// (about to start).
  bool get isActive => _isActive || _isReserved;

  /// Reserve the guard before processUserInput. This ensures concurrent
  /// handlePromptSubmit calls queue (via the isActive check) instead of
  /// starting a second executeUserInput.
  void reserve() {
    _isReserved = true;
  }

  /// Cancel reservation without starting.  Only acts on dispatching state.
  void cancelReservation() {
    _isReserved = false;
  }

  /// Transition to running state.
  void start() {
    _isActive = true;
    _isReserved = false;
  }

  /// Transition to idle state.
  void end() {
    _isActive = false;
    _isReserved = false;
  }
}

// ===================================================================
// Command descriptor (simplified from TS Command type)
// ===================================================================

/// Simplified command descriptor for slash-command matching.
class CommandDescriptor {
  final String name;
  final List<String> aliases;
  final bool immediate;
  final bool enabled;
  final String type; // 'local-jsx', 'network', etc.
  final Future<dynamic> Function(String args)? load;

  const CommandDescriptor({
    required this.name,
    this.aliases = const [],
    this.immediate = false,
    this.enabled = true,
    this.type = 'network',
    this.load,
  });
}

// ===================================================================
// Notification
// ===================================================================

class AppNotification {
  final String key;
  final String text;
  final String priority; // 'low', 'medium', 'high', 'immediate'

  const AppNotification({
    required this.key,
    required this.text,
    this.priority = 'low',
  });
}

// ===================================================================
// Process User Input result
// ===================================================================

/// Result of processUserInput.
class ProcessUserInputResult {
  final List<Map<String, dynamic>> messages;
  final bool shouldQuery;
  final List<String>? allowedTools;
  final String? model;
  final EffortValue? effort;
  final String? nextInput;
  final bool? submitNextInput;

  const ProcessUserInputResult({
    this.messages = const [],
    this.shouldQuery = false,
    this.allowedTools,
    this.model,
    this.effort,
    this.nextInput,
    this.submitNextInput,
  });
}

// ===================================================================
// Callback typedefs
// ===================================================================

typedef GracefulShutdownFn = void Function(int code);

typedef ProcessUserInputFn =
    Future<ProcessUserInputResult> Function({
      required String input,
      String? preExpansionInput,
      required PromptInputMode mode,
      Map<int, PastedContent>? pastedContents,
      required List<Map<String, dynamic>> messages,
      required QuerySource querySource,
      Map<String, dynamic>? ideSelection,
      bool? skipSlashCommands,
      String? uuid,
      bool? skipAttachments,
      bool? isAlreadyProcessing,
      void Function(String? prompt)? setUserInputOnProcessing,
      bool Function(String toolName)? canUseTool,
      String? bridgeOrigin,
      bool? isMeta,
    });

typedef EnqueueFn = void Function(QueuedCommand command);

typedef OnQueryFn =
    Future<void> Function(
      List<Map<String, dynamic>> newMessages,
      Object abortController,
      bool shouldQuery,
      List<String> additionalAllowedTools,
      String mainLoopModel,
      Future<bool> Function(
        String input,
        List<Map<String, dynamic>> newMessages,
      )?
      onBeforeQuery,
      String? input,
      EffortValue? effort,
    );

typedef SetToolJSXFn =
    void Function({
      dynamic jsx,
      bool shouldHidePromptInput,
      bool? clearLocalJSX,
      bool? isLocalJSXCommand,
      bool? isImmediate,
    });

typedef GetToolUseContextFn =
    Map<String, dynamic> Function(
      List<Map<String, dynamic>> messages,
      List<Map<String, dynamic>> newMessages,
      Object abortController,
      String mainLoopModel,
    );

typedef SetAppStateFn =
    void Function(
      Map<String, dynamic> Function(Map<String, dynamic> prev) updater,
    );

// ===================================================================
// Base Execution Parameters
// ===================================================================

class BaseExecutionParams {
  final List<QueuedCommand>? queuedCommands;
  final List<Map<String, dynamic>> messages;
  final String mainLoopModel;
  final Map<String, dynamic>? ideSelection;
  final QuerySource querySource;
  final List<CommandDescriptor> commands;
  final QueryGuard queryGuard;
  final bool isExternalLoading;
  final SetToolJSXFn setToolJSX;
  final GetToolUseContextFn getToolUseContext;
  final void Function(String? prompt) setUserInputOnProcessing;
  final void Function(Object? abortController) setAbortController;
  final OnQueryFn onQuery;
  final SetAppStateFn setAppState;
  final Future<bool> Function(
    String input,
    List<Map<String, dynamic>> newMessages,
  )?
  onBeforeQuery;
  final bool Function(String toolName)? canUseTool;

  const BaseExecutionParams({
    this.queuedCommands,
    required this.messages,
    required this.mainLoopModel,
    this.ideSelection,
    required this.querySource,
    required this.commands,
    required this.queryGuard,
    this.isExternalLoading = false,
    required this.setToolJSX,
    required this.getToolUseContext,
    required this.setUserInputOnProcessing,
    required this.setAbortController,
    required this.onQuery,
    required this.setAppState,
    this.onBeforeQuery,
    this.canUseTool,
  });
}

// ===================================================================
// Execute User Input Parameters
// ===================================================================

class ExecuteUserInputParams extends BaseExecutionParams {
  final void Function() resetHistory;
  final void Function(String value) onInputChange;

  const ExecuteUserInputParams({
    super.queuedCommands,
    required super.messages,
    required super.mainLoopModel,
    super.ideSelection,
    required super.querySource,
    required super.commands,
    required super.queryGuard,
    super.isExternalLoading = false,
    required super.setToolJSX,
    required super.getToolUseContext,
    required super.setUserInputOnProcessing,
    required super.setAbortController,
    required super.onQuery,
    required super.setAppState,
    super.onBeforeQuery,
    super.canUseTool,
    required this.resetHistory,
    required this.onInputChange,
  });
}

// ===================================================================
// Handle Prompt Submit Parameters
// ===================================================================

class HandlePromptSubmitParams extends BaseExecutionParams {
  final String? input;
  final PromptInputMode? mode;
  final Map<int, PastedContent>? pastedContents;
  final PromptInputHelpers helpers;
  final void Function(String value) onInputChange;
  final void Function(Map<int, PastedContent>) setPastedContents;
  final Object? abortController;
  final void Function(AppNotification notification)? addNotification;
  final void Function(
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>> prev)
    updater,
  )?
  setMessages;
  final SpinnerMode? streamMode;
  final bool? hasInterruptibleToolInProgress;
  final String? uuid;
  final bool? skipSlashCommands;

  const HandlePromptSubmitParams({
    super.queuedCommands,
    required super.messages,
    required super.mainLoopModel,
    super.ideSelection,
    required super.querySource,
    required super.commands,
    required super.queryGuard,
    super.isExternalLoading = false,
    required super.setToolJSX,
    required super.getToolUseContext,
    required super.setUserInputOnProcessing,
    required super.setAbortController,
    required super.onQuery,
    required super.setAppState,
    super.onBeforeQuery,
    super.canUseTool,
    this.input,
    this.mode,
    this.pastedContents,
    required this.helpers,
    required this.onInputChange,
    required this.setPastedContents,
    this.abortController,
    this.addNotification,
    this.setMessages,
    this.streamMode,
    this.hasInterruptibleToolInProgress,
    this.uuid,
    this.skipSlashCommands,
  });
}

// ===================================================================
// Exit Commands
// ===================================================================

const _exitInputs = ['exit', 'quit', ':q', ':q!', ':wq', ':wq!'];

// ===================================================================
// Reference Parsing
// ===================================================================

/// Inline image reference pattern: [Image #N].
final _imageRefPattern = RegExp(r'\[Image #(\d+)\]');

/// Pasted text reference pattern: [Pasted Text #N (M lines)].
final _pastedTextRefPattern = RegExp(r'\[Pasted Text #(\d+) \((\d+) lines\)\]');

/// Parse inline references from prompt text.
List<ParsedReference> parseReferences(String input) {
  final refs = <ParsedReference>[];
  for (final match in _imageRefPattern.allMatches(input)) {
    final id = int.tryParse(match.group(1) ?? '');
    if (id != null) {
      refs.add(ParsedReference(id: id, raw: match.group(0)!));
    }
  }
  for (final match in _pastedTextRefPattern.allMatches(input)) {
    final id = int.tryParse(match.group(1) ?? '');
    if (id != null) {
      refs.add(ParsedReference(id: id, raw: match.group(0)!));
    }
  }
  return refs;
}

/// Check if a pasted content entry is a valid image.
bool isValidImagePaste(PastedContent content) {
  return content.type == 'image' &&
      content.content.isNotEmpty &&
      content.mediaType != null;
}

/// Format a pasted text reference placeholder.
String formatPastedTextRef(int id, int numLines) {
  return '[Pasted Text #$id ($numLines lines)]';
}

/// Count lines in pasted text content.
int getPastedTextRefNumLines(String content) {
  return content.split('\n').length;
}

/// Expand pasted text references with actual content.
String expandPastedTextRefs(
  String input,
  Map<int, PastedContent> pastedContents,
) {
  var result = input;
  for (final entry in pastedContents.entries) {
    if (entry.value.type == 'text') {
      final numLines = getPastedTextRefNumLines(entry.value.content);
      final ref = formatPastedTextRef(entry.key, numLines);
      result = result.replaceAll(ref, entry.value.content);
    }
  }
  return result;
}

// ===================================================================
// Handle Prompt Submit — main entry point
// ===================================================================

/// Main entry point for prompt submission.
///
/// Handles exit commands, slash-command dispatch, queuing when the
/// model is busy, reference expansion, and initiating query execution.
Future<void> handlePromptSubmit({
  required HandlePromptSubmitParams params,
  required GracefulShutdownFn gracefulShutdownSync,
  required ProcessUserInputFn processUserInput,
  required EnqueueFn enqueue,
}) async {
  final helpers = params.helpers;
  final queryGuard = params.queryGuard;
  final isExternalLoading = params.isExternalLoading;
  final commands = params.commands;
  final onInputChange = params.onInputChange;
  final setPastedContents = params.setPastedContents;

  // Queue processor path: commands are pre-validated and ready to execute.
  // Skip all input validation, reference parsing, and queuing logic.
  if (params.queuedCommands != null && params.queuedCommands!.isNotEmpty) {
    await _executeUserInput(
      params: ExecuteUserInputParams(
        queuedCommands: params.queuedCommands,
        messages: params.messages,
        mainLoopModel: params.mainLoopModel,
        ideSelection: params.ideSelection,
        querySource: params.querySource,
        commands: commands,
        queryGuard: queryGuard,
        setToolJSX: params.setToolJSX,
        getToolUseContext: params.getToolUseContext,
        setUserInputOnProcessing: params.setUserInputOnProcessing,
        setAbortController: params.setAbortController,
        onQuery: params.onQuery,
        setAppState: params.setAppState,
        onBeforeQuery: params.onBeforeQuery,
        canUseTool: params.canUseTool,
        resetHistory: helpers.resetHistory,
        onInputChange: onInputChange,
      ),
      processUserInput: processUserInput,
      enqueue: enqueue,
    );
    return;
  }

  final input = params.input ?? '';
  final mode = params.mode ?? PromptInputMode.prompt;
  final rawPastedContents = params.pastedContents ?? {};

  // Images are only sent if their [Image #N] placeholder is still in the text.
  // Deleting the inline pill drops the image; orphaned entries are filtered here.
  final referencedIds = parseReferences(input).map((r) => r.id).toSet();
  final pastedContents = Map<int, PastedContent>.fromEntries(
    rawPastedContents.entries.where(
      (e) => e.value.type != 'image' || referencedIds.contains(e.value.id),
    ),
  );

  final hasImages = pastedContents.values.any(isValidImagePaste);
  if (input.trim().isEmpty) return;

  // Handle exit commands — skip for remote bridge messages.
  final skipSlashCommands = params.skipSlashCommands ?? false;
  if (!skipSlashCommands && _exitInputs.contains(input.trim())) {
    final exitCommand = commands.where((cmd) => cmd.name == 'exit').firstOrNull;
    if (exitCommand != null) {
      await handlePromptSubmit(
        params: HandlePromptSubmitParams(
          messages: params.messages,
          mainLoopModel: params.mainLoopModel,
          querySource: params.querySource,
          commands: commands,
          queryGuard: queryGuard,
          setToolJSX: params.setToolJSX,
          getToolUseContext: params.getToolUseContext,
          setUserInputOnProcessing: params.setUserInputOnProcessing,
          setAbortController: params.setAbortController,
          onQuery: params.onQuery,
          setAppState: params.setAppState,
          helpers: helpers,
          onInputChange: onInputChange,
          setPastedContents: setPastedContents,
          input: '/exit',
        ),
        gracefulShutdownSync: gracefulShutdownSync,
        processUserInput: processUserInput,
        enqueue: enqueue,
      );
    } else {
      gracefulShutdownSync(0);
    }
    return;
  }

  // Parse references and replace with actual content early, before queueing
  // or immediate-command dispatch.
  final finalInput = expandPastedTextRefs(input, pastedContents);
  final pastedTextRefs = parseReferences(
    input,
  ).where((r) => pastedContents[r.id]?.type == 'text').toList();
  final pastedTextCount = pastedTextRefs.length;
  final pastedTextBytes = pastedTextRefs.fold<int>(
    0,
    (sum, r) => sum + (pastedContents[r.id]?.content.length ?? 0),
  );
  // Analytics: logEvent('tengu_paste_text', {pastedTextCount, pastedTextBytes})

  // Handle local-jsx immediate commands (e.g., /config, /doctor).
  // Skip for remote bridge messages.
  if (!skipSlashCommands && finalInput.trim().startsWith('/')) {
    final trimmedInput = finalInput.trim();
    final spaceIndex = trimmedInput.indexOf(' ');
    final commandName = spaceIndex == -1
        ? trimmedInput.substring(1)
        : trimmedInput.substring(1, spaceIndex);
    final commandArgs = spaceIndex == -1
        ? ''
        : trimmedInput.substring(spaceIndex + 1).trim();

    final immediateCommand = commands.where((cmd) {
      return cmd.immediate &&
          cmd.enabled &&
          (cmd.name == commandName || cmd.aliases.contains(commandName));
    }).firstOrNull;

    if (immediateCommand != null &&
        immediateCommand.type == 'local-jsx' &&
        (queryGuard.isActive || isExternalLoading)) {
      // Clear input.
      onInputChange('');
      helpers.setCursorOffset(0);
      setPastedContents({});
      helpers.clearBuffer();

      final context = params.getToolUseContext(
        params.messages,
        [],
        Object(), // placeholder abort controller
        params.mainLoopModel,
      );

      // Execute immediate command. In Flutter, this would dispatch
      // through the command registry. The TS version calls
      // immediateCommand.load() and then impl.call(onDone, context, args).
      // Simplified here since Flutter uses a different UI layer.

      if (immediateCommand.load != null) {
        await immediateCommand.load!(commandArgs);
      }

      return;
    }
  }

  // Queue the command if model is busy.
  if (queryGuard.isActive || isExternalLoading) {
    // Only allow prompt and bash mode commands to be queued.
    if (mode != PromptInputMode.prompt && mode != PromptInputMode.bash) {
      return;
    }

    // Interrupt current turn when executing tools have interruptBehavior 'cancel'.
    if (params.hasInterruptibleToolInProgress == true &&
        params.abortController != null) {
      // In Dart/Flutter this would call an AbortController-style cancel.
      // params.abortController?.abort('interrupt');
    }

    // Enqueue with string value + raw pastedContents. Images will be resized
    // at execution time when processUserInput runs.
    enqueue(
      QueuedCommand(
        value: finalInput.trim(),
        preExpansionValue: input.trim(),
        mode: mode,
        pastedContents: hasImages ? pastedContents : null,
        skipSlashCommands: skipSlashCommands ? true : null,
        uuid: params.uuid,
      ),
    );

    onInputChange('');
    helpers.setCursorOffset(0);
    setPastedContents({});
    helpers.resetHistory();
    helpers.clearBuffer();
    return;
  }

  // Construct a QueuedCommand from the direct user input so both paths
  // go through the same executeUserInput loop.
  final cmd = QueuedCommand(
    value: finalInput,
    preExpansionValue: input,
    mode: mode,
    pastedContents: hasImages ? pastedContents : null,
    skipSlashCommands: skipSlashCommands ? true : null,
    uuid: params.uuid,
  );

  await _executeUserInput(
    params: ExecuteUserInputParams(
      queuedCommands: [cmd],
      messages: params.messages,
      mainLoopModel: params.mainLoopModel,
      ideSelection: params.ideSelection,
      querySource: params.querySource,
      commands: commands,
      queryGuard: queryGuard,
      setToolJSX: params.setToolJSX,
      getToolUseContext: params.getToolUseContext,
      setUserInputOnProcessing: params.setUserInputOnProcessing,
      setAbortController: params.setAbortController,
      onQuery: params.onQuery,
      setAppState: params.setAppState,
      onBeforeQuery: params.onBeforeQuery,
      canUseTool: params.canUseTool,
      resetHistory: helpers.resetHistory,
      onInputChange: onInputChange,
    ),
    processUserInput: processUserInput,
    enqueue: enqueue,
  );
}

// ===================================================================
// Execute User Input — core execution logic
// ===================================================================

/// Core logic for executing user input without UI side effects.
///
/// All commands arrive as [queuedCommands]. First command gets full treatment
/// (attachments, ideSelection, pastedContents with image resizing). Commands
/// 2-N get skipAttachments to avoid duplicating turn-level context.
Future<void> _executeUserInput({
  required ExecuteUserInputParams params,
  required ProcessUserInputFn processUserInput,
  required EnqueueFn enqueue,
}) async {
  final queryGuard = params.queryGuard;
  // Always create a fresh abort controller.
  final abortController = Object();
  params.setAbortController(abortController);

  try {
    // Reserve the guard BEFORE processUserInput.
    queryGuard.reserve();

    final newMessages = <Map<String, dynamic>>[];
    var shouldQuery = false;
    List<String>? allowedTools;
    String? model;
    EffortValue? effort;
    String? nextInput;
    bool? submitNextInput;

    final commands = params.queuedCommands ?? [];

    // Compute workload tag. Only tag when EVERY command agrees on the same
    // non-null workload.
    final firstWorkload = commands.isNotEmpty ? commands[0].workload : null;
    final turnWorkload =
        firstWorkload != null &&
            commands.every((c) => c.workload == firstWorkload)
        ? firstWorkload
        : null;

    for (var i = 0; i < commands.length; i++) {
      final cmd = commands[i];
      final isFirst = i == 0;

      final result = await processUserInput(
        input: cmd.value,
        preExpansionInput: cmd.preExpansionValue,
        mode: cmd.mode,
        pastedContents: isFirst ? cmd.pastedContents : null,
        messages: params.messages,
        querySource: params.querySource,
        ideSelection: isFirst ? params.ideSelection : null,
        skipSlashCommands: cmd.skipSlashCommands,
        uuid: cmd.uuid,
        skipAttachments: !isFirst,
        isAlreadyProcessing: !isFirst,
        setUserInputOnProcessing: isFirst
            ? params.setUserInputOnProcessing
            : null,
        canUseTool: params.canUseTool,
        bridgeOrigin: cmd.bridgeOrigin,
        isMeta: cmd.isMeta,
      );

      // Stamp origin for task-notification messages.
      final origin =
          cmd.origin ??
          (cmd.mode == PromptInputMode.taskNotification
              ? const TaskNotificationOrigin()
              : null);
      if (origin != null) {
        for (final m in result.messages) {
          if (m['type'] == 'user') {
            m['origin'] = origin;
          }
        }
      }

      newMessages.addAll(result.messages);

      if (isFirst) {
        shouldQuery = result.shouldQuery;
        allowedTools = result.allowedTools;
        model = result.model;
        effort = result.effort;
        nextInput = result.nextInput;
        submitNextInput = result.submitNextInput;
      }
    }

    // File history snapshot (if enabled) would go here.

    if (newMessages.isNotEmpty) {
      params.resetHistory();
      params.setToolJSX(
        jsx: null,
        shouldHidePromptInput: false,
        clearLocalJSX: true,
      );

      final primaryCmd = commands.isNotEmpty ? commands[0] : null;
      final primaryMode = primaryCmd?.mode ?? PromptInputMode.prompt;
      final primaryInput = primaryCmd?.value;
      final shouldCallBeforeQuery = primaryMode == PromptInputMode.prompt;

      await params.onQuery(
        newMessages,
        abortController,
        shouldQuery,
        allowedTools ?? [],
        model ?? params.mainLoopModel,
        shouldCallBeforeQuery ? params.onBeforeQuery : null,
        primaryInput,
        effort,
      );
    } else {
      // Local slash commands that skip messages.
      queryGuard.cancelReservation();
      params.setToolJSX(
        jsx: null,
        shouldHidePromptInput: false,
        clearLocalJSX: true,
      );
      params.resetHistory();
      params.setAbortController(null);
    }

    // Handle nextInput from commands that want to chain.
    if (nextInput != null) {
      if (submitNextInput == true) {
        enqueue(QueuedCommand(value: nextInput));
      } else {
        params.onInputChange(nextInput);
      }
    }
  } finally {
    // Safety net: release guard reservation and clear placeholder.
    queryGuard.cancelReservation();
    params.setUserInputOnProcessing(null);
  }
}

// ===================================================================
// Prompt Editor (from promptEditor.ts)
// ===================================================================

/// Editor result from external editor.
class EditorResult {
  final String? content;
  final String? error;

  const EditorResult({this.content, this.error});
}

/// Map of editor command overrides (e.g. to add wait flags).
const _editorOverrides = <String, String>{
  'code': 'code -w', // VS Code: wait for file to be closed
  'subl': 'subl --wait', // Sublime Text: wait for file to be closed
};

/// Edit a file in an external editor (synchronous).
///
/// Terminal editors (vi, nano) take over the terminal.
/// GUI editors (code, subl) open in a separate window.
EditorResult editFileInEditor({
  required String filePath,
  required String? editor,
}) {
  if (editor == null || editor.isEmpty) {
    return const EditorResult(content: null);
  }

  final file = File(filePath);
  if (!file.existsSync()) {
    return const EditorResult(content: null);
  }

  final editorCommand = _editorOverrides[editor] ?? editor;

  try {
    final result = Process.runSync('sh', [
      '-c',
      '$editorCommand "$filePath"',
    ], runInShell: false);

    if (result.exitCode != 0) {
      return EditorResult(
        content: null,
        error: '$editor exited with code ${result.exitCode}',
      );
    }

    final editedContent = file.readAsStringSync();
    return EditorResult(content: editedContent);
  } catch (e) {
    return const EditorResult(content: null);
  }
}

/// Re-collapse expanded pasted text by finding content that matches
/// pastedContents and replacing it with references.
String recollapsePastedContent({
  required String editedPrompt,
  required String originalPrompt,
  required Map<int, PastedContent> pastedContents,
}) {
  var collapsed = editedPrompt;

  for (final entry in pastedContents.entries) {
    if (entry.value.type == 'text') {
      final pasteId = entry.key;
      final contentStr = entry.value.content;
      final contentIndex = collapsed.indexOf(contentStr);

      if (contentIndex != -1) {
        final numLines = getPastedTextRefNumLines(contentStr);
        final ref = formatPastedTextRef(pasteId, numLines);
        collapsed =
            collapsed.substring(0, contentIndex) +
            ref +
            collapsed.substring(contentIndex + contentStr.length);
      }
    }
  }

  return collapsed;
}

/// Edit a prompt in an external editor.
EditorResult editPromptInEditor({
  required String currentPrompt,
  required String? editor,
  Map<int, PastedContent>? pastedContents,
}) {
  final tempDir = Directory.systemTemp;
  final tempFile = File(
    p.join(
      tempDir.path,
      'neomage_prompt_${DateTime.now().millisecondsSinceEpoch}.txt',
    ),
  );

  try {
    // Expand pasted text references before editing.
    final expandedPrompt = pastedContents != null
        ? expandPastedTextRefs(currentPrompt, pastedContents)
        : currentPrompt;

    tempFile.writeAsStringSync(expandedPrompt);

    final result = editFileInEditor(filePath: tempFile.path, editor: editor);

    if (result.content == null) return result;

    // Trim a single trailing newline (common editor behavior).
    var finalContent = result.content!;
    if (finalContent.endsWith('\n') && !finalContent.endsWith('\n\n')) {
      finalContent = finalContent.substring(0, finalContent.length - 1);
    }

    // Re-collapse pasted content if it was not edited.
    if (pastedContents != null) {
      finalContent = recollapsePastedContent(
        editedPrompt: finalContent,
        originalPrompt: currentPrompt,
        pastedContents: pastedContents,
      );
    }

    return EditorResult(content: finalContent);
  } finally {
    try {
      if (tempFile.existsSync()) tempFile.deleteSync();
    } catch (_) {}
  }
}

// ===================================================================
// Prompt Shell Execution (from promptShellExecution.ts)
// ===================================================================

/// Pattern for code blocks: ```! command ```.
final _blockPattern = RegExp(r'```!\s*\n?([\s\S]*?)\n?```');

/// Pattern for inline: !`command`.
/// Uses a lookbehind to require whitespace or start-of-line before !
final _inlinePattern = RegExp(r'(?<=^|\s)!`([^`]+)`', multiLine: true);

/// Error for malformed shell commands in prompts.
class MalformedCommandError implements Exception {
  final String message;
  const MalformedCommandError(this.message);

  @override
  String toString() => 'MalformedCommandError: $message';
}

/// Error from shell command execution.
class ShellError implements Exception {
  final String stdout;
  final String stderr;
  final bool interrupted;

  const ShellError({
    required this.stdout,
    required this.stderr,
    this.interrupted = false,
  });
}

/// Shell type from frontmatter.
enum FrontmatterShell { bash, powershell }

/// Result from a shell command execution.
class ShellCommandResult {
  final String stdout;
  final String stderr;
  final bool interrupted;

  const ShellCommandResult({
    required this.stdout,
    required this.stderr,
    this.interrupted = false,
  });
}

/// Callback for executing a shell command.
typedef ShellCommandExecutor =
    Future<ShellCommandResult> Function(String command);

/// Callback for checking shell permissions.
typedef ShellPermissionChecker = Future<bool> Function(String command);

/// Parse prompt text and execute any embedded shell commands.
///
/// Supports two syntaxes:
/// - Code blocks: ```! command ```
/// - Inline: !`command`
///
/// [shell] - Shell to route commands through. Defaults to bash.
/// This comes from .md frontmatter (author's choice) or is null for
/// built-in commands.
Future<String> executeShellCommandsInPrompt({
  required String text,
  required ShellCommandExecutor executeCommand,
  required ShellPermissionChecker hasPermission,
  required String slashCommandName,
  FrontmatterShell? shell,
}) async {
  var result = text;

  // INLINE_PATTERN's lookbehind is expensive. 93% of skills have no !`
  // at all, so gate the scan on a cheap substring check.
  final blockMatches = _blockPattern.allMatches(text).toList();
  final inlineMatches = text.contains('!`')
      ? _inlinePattern.allMatches(text).toList()
      : <RegExpMatch>[];

  final allMatches = [...blockMatches, ...inlineMatches];

  await Future.wait(
    allMatches.map((match) async {
      final command = match.group(1)?.trim();
      if (command == null || command.isEmpty) return;

      try {
        final permitted = await hasPermission(command);
        if (!permitted) {
          throw MalformedCommandError(
            'Shell command permission check failed for pattern '
            '"${match.group(0)}": Permission denied',
          );
        }

        final shellResult = await executeCommand(command);
        final output = formatBashOutput(
          stdout: shellResult.stdout,
          stderr: shellResult.stderr,
        );
        // Use function-based replacement to avoid $ interpolation issues.
        result = result.replaceFirst(match.group(0)!, output);
      } on MalformedCommandError {
        rethrow;
      } on ShellError catch (e) {
        formatBashError(e: e, pattern: match.group(0)!);
      } catch (e) {
        final message = e.toString();
        throw MalformedCommandError('[Error]\n$message');
      }
    }),
  );

  return result;
}

/// Format bash output combining stdout and stderr.
String formatBashOutput({
  required String stdout,
  required String stderr,
  bool inline = false,
}) {
  final parts = <String>[];

  if (stdout.trim().isNotEmpty) {
    parts.add(stdout.trim());
  }

  if (stderr.trim().isNotEmpty) {
    if (inline) {
      parts.add('[stderr: ${stderr.trim()}]');
    } else {
      parts.add('[stderr]\n${stderr.trim()}');
    }
  }

  return parts.join(inline ? ' ' : '\n');
}

/// Format and throw a bash error.
Never formatBashError({
  required ShellError e,
  required String pattern,
  bool inline = false,
}) {
  if (e.interrupted) {
    throw MalformedCommandError(
      'Shell command interrupted for pattern "$pattern": [Command interrupted]',
    );
  }
  final output = formatBashOutput(
    stdout: e.stdout,
    stderr: e.stderr,
    inline: inline,
  );
  throw MalformedCommandError(
    'Shell command failed for pattern "$pattern": $output',
  );
}

// ===================================================================
// Prompt Category (from promptCategory.ts)
// ===================================================================

/// Default output style name.
const defaultOutputStyleName = 'default';

/// Built-in output style config keys (from TS OUTPUT_STYLE_CONFIG).
const builtInOutputStyles = <String>{
  'default',
  'concise',
  'verbose',
  'code-only',
  'markdown',
};

/// Determines the query source for agent usage (analytics).
///
/// Used for analytics to track different agent patterns.
QuerySource getQuerySourceForAgent({
  required String? agentType,
  required bool isBuiltInAgent,
}) {
  if (isBuiltInAgent) {
    return agentType != null ? 'agent:builtin:$agentType' : 'agent:default';
  } else {
    return 'agent:custom';
  }
}

/// Determines the query source based on output style settings (analytics).
///
/// Used for analytics to track different output style usage.
QuerySource getQuerySourceForREPL({String? outputStyle}) {
  final style = outputStyle ?? defaultOutputStyleName;

  if (style == defaultOutputStyleName) {
    return 'repl_main_thread';
  }

  final isBuiltIn = builtInOutputStyles.contains(style);
  return isBuiltIn
      ? 'repl_main_thread:outputStyle:$style'
      : 'repl_main_thread:outputStyle:custom';
}
