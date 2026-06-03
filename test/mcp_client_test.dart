import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/mcp/mcp_client.dart';
import 'package:neomage/mcp/mcp_models.dart';

/// Mock MCP transport to simulate server communication.
class MockMcpTransport implements McpTransport {
  final _incomingController = StreamController<String>.broadcast();
  final List<String> sentMessages = [];
  bool isClosed = false;

  @override
  Stream<String> get messageStream => _incomingController.stream;

  @override
  Future<void> send(String message) async {
    sentMessages.add(message);
  }

  @override
  Future<void> close() async {
    isClosed = true;
    await _incomingController.close();
  }

  void simulateServerMessage(String message) {
    _incomingController.add(message);
  }
}

void main() {
  group('MCP Models Tests', () {
    test('McpTool JSON serialization and deserialization', () {
      final tool = McpTool(
        name: 'test_tool',
        description: 'A tool for testing',
        inputSchema: {
          'type': 'object',
          'properties': {
            'arg1': {'type': 'string'}
          }
        },
      );

      final json = tool.toJson();
      expect(json['name'], 'test_tool');
      expect(json['description'], 'A tool for testing');

      final parsed = McpTool.fromJson(json);
      expect(parsed.name, 'test_tool');
      expect(parsed.description, 'A tool for testing');
      expect(parsed.inputSchema['type'], 'object');
    });

    test('McpResponse standard JSON-RPC parsing', () {
      final successJson = {
        'jsonrpc': '2.0',
        'id': 1,
        'result': {'status': 'success'}
      };

      final response = McpResponse.fromJson(successJson);
      expect(response.id, 1);
      expect(response.isError, false);
      expect(response.result['status'], 'success');

      final errorJson = {
        'jsonrpc': '2.0',
        'id': 2,
        'error': {'code': -32603, 'message': 'Execution failed'}
      };

      final errResponse = McpResponse.fromJson(errorJson);
      expect(errResponse.id, 2);
      expect(errResponse.isError, true);
      expect(errResponse.error?.code, -32603);
      expect(errResponse.error?.message, 'Execution failed');
    });
  });

  group('McpClient Protocol Tests', () {
    late MockMcpTransport transport;
    late McpClient client;

    setUp(() {
      transport = MockMcpTransport();
      client = McpClient(transport: transport);
    });

    tearDown(() async {
      await client.disconnect();
    });

    test('Successful handshake upon connect', () async {
      final connectFuture = client.connect();

      // Simulate initialize handshake response from server
      await Future.delayed(const Duration(milliseconds: 10));
      transport.simulateServerMessage('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}');

      await connectFuture;

      expect(transport.sentMessages.length, 1);
      expect(transport.sentMessages[0], contains('initialize'));
    });

    test('List tools successfully', () async {
      final connectFuture = client.connect();
      await Future.delayed(const Duration(milliseconds: 5));
      transport.simulateServerMessage('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}');
      await connectFuture;

      final toolsFuture = client.listTools();

      await Future.delayed(const Duration(milliseconds: 5));
      transport.simulateServerMessage(
          '{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"brave_search","description":"Search Brave","inputSchema":{}}]}}');

      final tools = await toolsFuture;
      expect(tools.length, 1);
      expect(tools[0].name, 'brave_search');
      expect(tools[0].description, 'Search Brave');
    });

    test('Execute tool successfully', () async {
      final connectFuture = client.connect();
      await Future.delayed(const Duration(milliseconds: 5));
      transport.simulateServerMessage('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}');
      await connectFuture;

      final callFuture = client.callTool('run_cmd', {'command': 'ls'});

      await Future.delayed(const Duration(milliseconds: 5));
      transport.simulateServerMessage('{"jsonrpc":"2.0","id":2,"result":{"content":[{"type":"text","text":"file1\\nfile2"}],"isError":false}}');

      final response = await callFuture;
      expect(response.isError, false);
      expect(response.result['content'][0]['text'], 'file1\nfile2');
    });

    test('Disconnected client completes outstanding requests with errors', () async {
      final connectFuture = client.connect();
      await Future.delayed(const Duration(milliseconds: 5));
      transport.simulateServerMessage('{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05"}}');
      await connectFuture;

      final callFuture = client.callTool('run_cmd', {'command': 'ls'});

      // Disconnect immediately before server responds
      await client.disconnect();

      expect(callFuture, throwsA(isA<TimeoutException>()));
    });
  });
}
