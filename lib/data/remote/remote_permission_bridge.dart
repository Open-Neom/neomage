// Remote permission bridge — ported from neomagent
// src/remote/remotePermissionBridge.ts.
//
// Creates synthetic assistant messages and tool stubs for remote permission
// requests. In remote mode the tool execution happens on the CCR container,
// but the local UI still needs an AssistantMessage and Tool instance to
// render the permission confirmation dialog.

import 'dart:convert';

import 'package:neomage/data/tools/tool.dart';
import 'package:neomage/domain/models/message.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Create a synthetic [Message] for remote permission requests.
///
/// The tool-use confirmation UI requires an assistant [Message], but in remote
/// mode we don't have a real one -- the tool use runs on the CCR container.
/// This builds a minimal stand-in with the correct tool-use content block.
Message createSyntheticAssistantMessage({
  required Map<String, dynamic> request,
  required String requestId,
}) {
  final toolUseId = request['tool_use_id'] as String? ?? '';
  final toolName = request['tool_name'] as String? ?? '';
  final input = request['input'] as Map<String, dynamic>? ?? {};

  return Message(
    id: 'remote-$requestId',
    role: MessageRole.assistant,
    content: [
      ToolUseBlock(
        id: toolUseId,
        name: toolName,
        input: input,
      ),
    ],
  );
}

/// Create a minimal [Tool] stub for tools that are not loaded locally.
///
/// This happens when the remote CCR has tools (e.g. MCP tools) that the
/// local client does not know about. The stub provides enough information
/// for the permission dialog to render without crashing.
Tool createToolStub(String toolName) => _RemoteToolStub(toolName);

/// Internal stub implementation.
class _RemoteToolStub extends Tool {
  final String _name;
  _RemoteToolStub(this._name);

  @override
  String get name => _name;

  @override
  String get description => '';

  @override
  Map<String, dynamic> get inputSchema => const {};

  @override
  bool get isReadOnly => false;

  @override
  bool get isEnabled => true;

  @override
  Future<ToolResult> execute(Map<String, dynamic> input) async =>
      ToolResult.success('');

  @override
  String get userFacingName => _name;

  /// Render a short summary of the tool-use input.
  ///
  /// Shows up to three key-value pairs from the input map.
  String renderToolUseMessage(Map<String, dynamic> input) {
    if (input.isEmpty) return '';
    return input.entries
        .take(3)
        .map((e) {
          final valueStr =
              e.value is String ? e.value as String : jsonEncode(e.value);
          return '${e.key}: $valueStr';
        })
        .join(', ');
  }
}
