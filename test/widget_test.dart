import 'package:flutter_test/flutter_test.dart';

import 'package:neomage/neomage.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Domain Models: Message
  // ---------------------------------------------------------------------------
  group('Message', () {
    test('Message.user creates a user message with TextBlock', () {
      final msg = Message.user('Hello');
      expect(msg.role, MessageRole.user);
      expect(msg.content, hasLength(1));
      expect(msg.content.first, isA<TextBlock>());
      expect(msg.textContent, 'Hello');
    });

    test('Message.assistant creates an assistant message', () {
      final msg = Message.assistant('Hi there');
      expect(msg.role, MessageRole.assistant);
      expect(msg.textContent, 'Hi there');
    });

    test('Message auto-generates id and timestamp', () {
      final msg = Message.user('test');
      expect(msg.id, isNotEmpty);
      expect(msg.timestamp, isA<DateTime>());
    });

    test('Message.textContent joins multiple TextBlocks', () {
      final msg = Message(
        role: MessageRole.assistant,
        content: [
          const TextBlock('Hello'),
          const TextBlock('World'),
        ],
      );
      expect(msg.textContent, 'Hello\nWorld');
    });

    test('Message.toolUses extracts ToolUseBlocks', () {
      final msg = Message(
        role: MessageRole.assistant,
        content: [
          const TextBlock('Let me check that'),
          const ToolUseBlock(
            id: 'tu-1',
            name: 'bash',
            input: {'command': 'ls'},
          ),
          const ToolUseBlock(
            id: 'tu-2',
            name: 'read_file',
            input: {'path': 'main.dart'},
          ),
        ],
      );
      expect(msg.toolUses, hasLength(2));
      expect(msg.toolUses[0].name, 'bash');
      expect(msg.toolUses[1].name, 'read_file');
    });

    test('Message.toApiMap serializes correctly', () {
      final msg = Message.user('hello');
      final map = msg.toApiMap();
      expect(map['role'], 'user');
      expect(map['content'], isA<List>());
      expect((map['content'] as List).first['type'], 'text');
      expect((map['content'] as List).first['text'], 'hello');
    });

    test('toApiMap serializes ToolUseBlock', () {
      final msg = Message(
        role: MessageRole.assistant,
        content: [
          const ToolUseBlock(
            id: 'tu-abc',
            name: 'grep',
            input: {'pattern': 'TODO', 'path': '.'},
          ),
        ],
      );
      final map = msg.toApiMap();
      final block = (map['content'] as List).first as Map<String, dynamic>;
      expect(block['type'], 'tool_use');
      expect(block['id'], 'tu-abc');
      expect(block['name'], 'grep');
      expect(block['input']['pattern'], 'TODO');
    });

    test('toApiMap serializes ToolResultBlock with isError', () {
      final msg = Message(
        role: MessageRole.user,
        content: [
          const ToolResultBlock(
            toolUseId: 'tu-abc',
            content: 'file not found',
            isError: true,
          ),
        ],
      );
      final map = msg.toApiMap();
      final block = (map['content'] as List).first as Map<String, dynamic>;
      expect(block['type'], 'tool_result');
      expect(block['tool_use_id'], 'tu-abc');
      expect(block['is_error'], true);
    });

    test('toApiMap omits is_error when false', () {
      final msg = Message(
        role: MessageRole.user,
        content: [
          const ToolResultBlock(
            toolUseId: 'tu-1',
            content: 'success',
          ),
        ],
      );
      final block =
          (msg.toApiMap()['content'] as List).first as Map<String, dynamic>;
      expect(block.containsKey('is_error'), isFalse);
    });

    test('toApiMap serializes ImageBlock', () {
      final msg = Message(
        role: MessageRole.user,
        content: [
          const ImageBlock(
            mediaType: 'image/png',
            base64Data: 'iVBOR...==',
          ),
        ],
      );
      final block =
          (msg.toApiMap()['content'] as List).first as Map<String, dynamic>;
      expect(block['type'], 'image');
      expect(block['source']['type'], 'base64');
      expect(block['source']['media_type'], 'image/png');
    });
  });

  // ---------------------------------------------------------------------------
  // Domain Models: ContentBlock (sealed)
  // ---------------------------------------------------------------------------
  group('ContentBlock', () {
    test('TextBlock holds text', () {
      const block = TextBlock('code here');
      expect(block.text, 'code here');
    });

    test('ToolUseBlock holds id, name, input', () {
      const block = ToolUseBlock(
        id: 'tu-1',
        name: 'bash',
        input: {'command': 'echo hi'},
      );
      expect(block.id, 'tu-1');
      expect(block.name, 'bash');
      expect(block.input['command'], 'echo hi');
    });

    test('ToolResultBlock defaults isError to false', () {
      const block = ToolResultBlock(
        toolUseId: 'tu-1',
        content: 'output here',
      );
      expect(block.isError, isFalse);
    });

    test('ContentBlock sealed class exhaustive switch', () {
      const ContentBlock block = TextBlock('test');
      final result = switch (block) {
        TextBlock() => 'text',
        ToolUseBlock() => 'tool_use',
        ToolResultBlock() => 'tool_result',
        ImageBlock() => 'image',
      };
      expect(result, 'text');
    });
  });

  // ---------------------------------------------------------------------------
  // Domain Models: Branded IDs
  // ---------------------------------------------------------------------------
  group('Branded IDs', () {
    test('SessionId wraps a string', () {
      const id = SessionId('session-123');
      expect(id.value, 'session-123');
      // Extension types implement String
      expect(id, 'session-123');
    });

    test('AgentId.tryParse validates format', () {
      // Valid: a + 16 hex chars
      final valid = AgentId.tryParse('a1234567890abcdef');
      expect(valid, isNotNull);
      expect(valid!.value, 'a1234567890abcdef');

      // Valid: a + label + 16 hex chars
      final withLabel = AgentId.tryParse('amain-1234567890abcdef');
      expect(withLabel, isNotNull);

      // Invalid: missing 'a' prefix
      expect(AgentId.tryParse('1234567890abcdef'), isNull);

      // Invalid: too short
      expect(AgentId.tryParse('a123'), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Domain Models: ToolDefinition
  // ---------------------------------------------------------------------------
  group('ToolDefinition', () {
    test('toApiMap produces Anthropic format', () {
      const tool = ToolDefinition(
        name: 'read_file',
        description: 'Read a file from disk',
        inputSchema: {
          'type': 'object',
          'properties': {
            'path': {'type': 'string'},
          },
          'required': ['path'],
        },
      );
      final map = tool.toApiMap();
      expect(map['name'], 'read_file');
      expect(map['description'], 'Read a file from disk');
      expect(map['input_schema'], isA<Map>());
      expect(map['input_schema']['properties']['path']['type'], 'string');
    });

    test('toOpenAiMap produces OpenAI function format', () {
      const tool = ToolDefinition(
        name: 'bash',
        description: 'Execute a shell command',
        inputSchema: {
          'type': 'object',
          'properties': {
            'command': {'type': 'string'},
          },
        },
      );
      final map = tool.toOpenAiMap();
      expect(map['type'], 'function');
      expect(map['function']['name'], 'bash');
      expect(map['function']['description'], 'Execute a shell command');
      expect(map['function']['parameters'], isA<Map>());
    });
  });

  // ---------------------------------------------------------------------------
  // API: Error Classification
  // ---------------------------------------------------------------------------
  group('ApiError classification', () {
    test('classifyApiError maps 429 to rateLimited', () {
      final error = classifyApiError(statusCode: 429, body: '');
      expect(error.type, ApiErrorType.rateLimited);
      expect(error.isRetryable, isTrue);
    });

    test('classifyApiError maps 529 to overloaded', () {
      final error = classifyApiError(statusCode: 529, body: '');
      expect(error.type, ApiErrorType.overloaded);
      expect(error.isRetryable, isTrue);
    });

    test('classifyApiError maps 401 to authenticationError', () {
      final error = classifyApiError(statusCode: 401, body: '');
      expect(error.type, ApiErrorType.authenticationError);
      expect(error.isAuthError, isTrue);
      expect(error.isRetryable, isFalse);
    });

    test('classifyApiError maps 403 to permissionDenied', () {
      final error = classifyApiError(statusCode: 403, body: '');
      expect(error.type, ApiErrorType.permissionDenied);
      expect(error.isAuthError, isTrue);
    });

    test('classifyApiError detects promptTooLong from body', () {
      final error = classifyApiError(
        statusCode: 400,
        body: '{"error": "prompt is too long for this model"}',
      );
      expect(error.type, ApiErrorType.promptTooLong);
    });

    test('classifyApiError maps 500 to serverError', () {
      final error = classifyApiError(statusCode: 500, body: 'Internal error');
      expect(error.type, ApiErrorType.serverError);
      expect(error.isRetryable, isTrue);
    });

    test('ApiError.isRetryable is false for auth errors', () {
      const error = ApiError(
        type: ApiErrorType.authenticationError,
        message: 'bad key',
        statusCode: 401,
      );
      expect(error.isRetryable, isFalse);
    });

    test('ApiError.toString includes type and message', () {
      const error = ApiError(
        type: ApiErrorType.rateLimited,
        message: 'slow down',
      );
      expect(error.toString(), contains('rateLimited'));
      expect(error.toString(), contains('slow down'));
    });

    test('retryAfter header is preserved', () {
      final error = classifyApiError(
        statusCode: 429,
        body: '',
        retryAfterHeader: '30',
      );
      expect(error.retryAfter, '30');
    });
  });

  // ---------------------------------------------------------------------------
  // API: Retry Config
  // ---------------------------------------------------------------------------
  group('RetryConfig', () {
    test('defaultConfig has sensible defaults', () {
      const config = RetryConfig.defaultConfig;
      expect(config.maxRetries, 10);
      expect(config.baseDelayMs, 500);
      expect(config.maxDelayMs, 32000);
      expect(config.max529Retries, 3);
      expect(config.persistent, isFalse);
    });

    test('backgroundConfig is more conservative', () {
      const config = RetryConfig.backgroundConfig;
      expect(config.maxRetries, 3);
      expect(config.max529Retries, 1);
    });

    test('RetryContext starts at zero', () {
      final ctx = RetryContext();
      expect(ctx.attempt, 0);
      expect(ctx.consecutive529s, 0);
      expect(ctx.lastRetry, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Tools: ToolResult
  // ---------------------------------------------------------------------------
  group('ToolResult', () {
    test('ToolResult.success creates non-error result', () {
      final result = ToolResult.success('file contents here');
      expect(result.content, 'file contents here');
      expect(result.isError, isFalse);
    });

    test('ToolResult.error creates error result', () {
      final result = ToolResult.error('file not found');
      expect(result.content, 'file not found');
      expect(result.isError, isTrue);
    });

    test('ToolResult.success with metadata', () {
      final result = ToolResult.success(
        'ok',
        metadata: {'bytes': 1024},
      );
      expect(result.metadata?['bytes'], 1024);
    });
  });

  // ---------------------------------------------------------------------------
  // Tools: ValidationResult
  // ---------------------------------------------------------------------------
  group('ValidationResult', () {
    test('valid result', () {
      const v = ValidationResult.valid();
      expect(v.isValid, isTrue);
      expect(v.error, isNull);
    });

    test('invalid result with message', () {
      const v = ValidationResult.invalid('missing required field');
      expect(v.isValid, isFalse);
      expect(v.error, 'missing required field');
    });
  });

  // ---------------------------------------------------------------------------
  // Tools: Bash Security
  // ---------------------------------------------------------------------------
  group('Bash security', () {
    test('simple commands pass', () {
      final result = bashCommandIsSafe('ls -la');
      expect(result.isPassthrough, isTrue);
    });

    test('echo with safe content passes', () {
      final result = bashCommandIsSafe('echo "hello world"');
      expect(result.isPassthrough, isTrue);
    });

    test('git status passes', () {
      final result = bashCommandIsSafe('git status');
      expect(result.isPassthrough, isTrue);
    });

    test('flutter pub get passes', () {
      final result = bashCommandIsSafe('flutter pub get');
      expect(result.isPassthrough, isTrue);
    });

    test('dart analyze passes', () {
      final result = bashCommandIsSafe('dart analyze lib/');
      expect(result.isPassthrough, isTrue);
    });

    test('empty command is handled', () {
      final result = bashCommandIsSafe('');
      // Empty commands should be allowed (no-op)
      expect(result.isAllow, isTrue);
    });

    test('command with \$IFS injection is flagged', () {
      final result = bashCommandIsSafe(r'echo $IFS hello');
      // $IFS usage is detected and flagged
      expect(result.isAsk, isTrue);
    });

    test('extractBaseCommand strips variable assignments', () {
      expect(extractBaseCommand('FOO=bar baz'), 'baz');
    });

    test('extractBaseCommand strips sudo', () {
      expect(extractBaseCommand('sudo apt install vim'), 'apt');
    });

    test('extractBaseCommand strips env wrapper', () {
      // env is stripped, then NODE_ENV=prod is a var assignment
      expect(extractBaseCommand('env node app.js'), 'node');
    });

    test('extractBaseCommand handles simple command', () {
      expect(extractBaseCommand('cat file.txt'), 'cat');
    });

    test('stripSafeRedirections removes 2>/dev/null', () {
      final stripped = stripSafeRedirections('cmd 2>/dev/null');
      expect(stripped, isNot(contains('2>/dev/null')));
    });

    test('hasUnescapedChar detects unescaped semicolons', () {
      expect(hasUnescapedChar('ls; rm file', ';'), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming: SSE Parser
  // ---------------------------------------------------------------------------
  group('SSE Parser', () {
    test('parses a simple data event', () async {
      final parser = SseParser();
      final input = 'data: {"type":"ping"}\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events, hasLength(1));
      expect(events.first.data, '{"type":"ping"}');
    });

    test('parses event with type', () async {
      final parser = SseParser();
      final input = 'event: message_start\ndata: {"message":{}}\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events, hasLength(1));
      expect(events.first.eventType, 'message_start');
      expect(events.first.data, '{"message":{}}');
    });

    test('ignores comment lines', () async {
      final parser = SseParser();
      final input = ': this is a comment\ndata: hello\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events, hasLength(1));
      expect(events.first.data, 'hello');
    });

    test('parses multiple events', () async {
      final parser = SseParser();
      final input = 'data: event1\n\ndata: event2\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events, hasLength(2));
      expect(events[0].data, 'event1');
      expect(events[1].data, 'event2');
    });

    test('parses retry field', () async {
      final parser = SseParser();
      final input = 'retry: 5000\ndata: reconnect\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events.first.retry, 5000);
    });

    test('parses id field', () async {
      final parser = SseParser();
      final input = 'id: evt-123\ndata: tracked\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events.first.id, 'evt-123');
    });

    test('strips single leading space from value', () async {
      final parser = SseParser();
      // Note: "data: hello" — space after colon should be stripped
      final input = 'data: hello\n\n';
      final bytes = input.codeUnits;

      final events = await parser
          .parse(Stream.value(bytes))
          .toList();

      expect(events.first.data, 'hello');
    });

    test('reset clears parser state', () {
      final parser = SseParser();
      parser.reset(); // Should not throw
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming: Stream event type parsing
  // ---------------------------------------------------------------------------
  group('StreamEventType parsing', () {
    test('parses known event types', () {
      expect(parseStreamEventType('message_start'), StreamEventType.messageStart);
      expect(parseStreamEventType('content_block_start'), StreamEventType.contentBlockStart);
      expect(parseStreamEventType('content_block_delta'), StreamEventType.contentBlockDelta);
      expect(parseStreamEventType('content_block_stop'), StreamEventType.contentBlockStop);
      expect(parseStreamEventType('message_delta'), StreamEventType.messageDelta);
      expect(parseStreamEventType('message_stop'), StreamEventType.messageStop);
      expect(parseStreamEventType('ping'), StreamEventType.ping);
      expect(parseStreamEventType('error'), StreamEventType.error);
    });

    test('returns null for unknown event types', () {
      expect(parseStreamEventType('unknown_event'), isNull);
      expect(parseStreamEventType(''), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Streaming: StreamUpdate sealed class
  // ---------------------------------------------------------------------------
  group('StreamUpdate types', () {
    test('TextDelta holds text and blockIndex', () {
      const delta = TextDelta(text: 'hello', blockIndex: 0);
      expect(delta.text, 'hello');
      expect(delta.blockIndex, 0);
      expect(delta.toString(), contains('hello'));
    });

    test('TextDelta truncates long text in toString', () {
      const delta = TextDelta(
        text: 'This is a very long text that exceeds forty characters by quite a lot',
        blockIndex: 0,
      );
      expect(delta.toString(), contains('...'));
    });

    test('ThinkingDelta holds reasoning text', () {
      const delta = ThinkingDelta(text: 'Let me think...', blockIndex: 0);
      expect(delta.text, 'Let me think...');
    });

    test('ToolUseStart holds tool metadata', () {
      const start = ToolUseStart(
        toolName: 'bash',
        toolId: 'tu-123',
        blockIndex: 1,
      );
      expect(start.toolName, 'bash');
      expect(start.toolId, 'tu-123');
      expect(start.toString(), contains('bash'));
    });

    test('ToolUseInputDelta holds partial JSON', () {
      const delta = ToolUseInputDelta(
        partialJson: '{"command":',
        blockIndex: 1,
      );
      expect(delta.partialJson, '{"command":');
    });
  });

  // ---------------------------------------------------------------------------
  // Domain Models: Permissions
  // ---------------------------------------------------------------------------
  group('Permissions', () {
    test('ExternalPermissionMode has all expected values', () {
      expect(ExternalPermissionMode.values, hasLength(5));
      expect(
        ExternalPermissionMode.values.map((e) => e.name),
        containsAll([
          'acceptEdits',
          'bypassPermissions',
          'defaultMode',
          'dontAsk',
          'plan',
        ]),
      );
    });

    test('PermissionMode has auto and bubble for agents', () {
      expect(PermissionMode.values, contains(PermissionMode.auto));
      expect(PermissionMode.values, contains(PermissionMode.bubble));
    });

    test('PermissionBehavior has allow, deny, ask', () {
      expect(PermissionBehavior.values, hasLength(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Domain Models: Enums
  // ---------------------------------------------------------------------------
  group('MessageRole & StopReason', () {
    test('MessageRole has user, assistant, system', () {
      expect(MessageRole.values, hasLength(3));
    });

    test('StopReason has all expected values', () {
      expect(StopReason.values.map((e) => e.name), containsAll([
        'endTurn',
        'maxTokens',
        'toolUse',
        'stopSequence',
      ]));
    });
  });

  // ---------------------------------------------------------------------------
  // Token Usage
  // ---------------------------------------------------------------------------
  group('TokenUsage', () {
    test('Message can hold usage stats', () {
      final msg = Message(
        role: MessageRole.assistant,
        content: [const TextBlock('ok')],
        usage: const TokenUsage(inputTokens: 100, outputTokens: 50),
      );
      expect(msg.usage, isNotNull);
      expect(msg.usage!.inputTokens, 100);
      expect(msg.usage!.outputTokens, 50);
    });

    test('Message can hold stop reason', () {
      final msg = Message(
        role: MessageRole.assistant,
        content: [const TextBlock('done')],
        stopReason: StopReason.endTurn,
      );
      expect(msg.stopReason, StopReason.endTurn);
    });
  });

  // ---------------------------------------------------------------------------
  // Tools: InterruptBehavior
  // ---------------------------------------------------------------------------
  group('InterruptBehavior', () {
    test('has three modes', () {
      expect(InterruptBehavior.values, hasLength(3));
      expect(InterruptBehavior.values.map((e) => e.name), containsAll([
        'interruptible',
        'finishThenYield',
        'nonInterruptible',
      ]));
    });
  });

  // ---------------------------------------------------------------------------
  // Bash Security: SecurityResult
  // ---------------------------------------------------------------------------
  group('SecurityResult', () {
    test('allow factory', () {
      const r = SecurityResult.allow(message: 'safe');
      expect(r.isAllow, isTrue);
      expect(r.isAsk, isFalse);
      expect(r.isPassthrough, isFalse);
      expect(r.behavior, 'allow');
      expect(r.message, 'safe');
    });

    test('ask factory', () {
      const r = SecurityResult.ask(message: 'risky');
      expect(r.isAsk, isTrue);
      expect(r.isAllow, isFalse);
      expect(r.updatedInput, isNull);
    });

    test('passthrough factory', () {
      const r = SecurityResult.passthrough(message: 'ok');
      expect(r.isPassthrough, isTrue);
      expect(r.isAllow, isFalse);
      expect(r.isAsk, isFalse);
    });
  });
}
