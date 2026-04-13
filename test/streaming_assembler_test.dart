// Tests for streaming.dart — SSE parser edge cases, StreamAssembler state
// machine, partial chunks, broken tool-use JSON, error events, magic bytes.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/data/api/streaming.dart';

void main() {
  group('SseParser edge cases', () {
    Stream<List<int>> bytes(String s) async* {
      yield utf8.encode(s);
    }

    test('empty stream yields no events', () async {
      final events = await SseParser().parse(bytes('')).toList();
      expect(events, isEmpty);
    });

    test('data without trailing blank line is not emitted', () async {
      final events = await SseParser().parse(bytes('data: hello')).toList();
      expect(events, isEmpty);
    });

    test('single event with event + data', () async {
      final events = await SseParser()
          .parse(bytes('event: ping\ndata: pong\n\n'))
          .toList();
      expect(events, hasLength(1));
      expect(events.first.eventType, 'ping');
      expect(events.first.data, 'pong');
    });

    test('comment line ignored', () async {
      final events = await SseParser()
          .parse(bytes(': this is a comment\ndata: x\n\n'))
          .toList();
      expect(events.first.data, 'x');
    });

    test('field without colon treated as empty value', () async {
      // Line "data" with no colon: per spec value = ''. Still counts as data.
      final events =
          await SseParser().parse(bytes('data\ndata: real\n\n')).toList();
      expect(events.first.data, contains('real'));
    });

    test('multiple data lines concatenated with newlines', () async {
      final events = await SseParser()
          .parse(bytes('data: line1\ndata: line2\n\n'))
          .toList();
      expect(events.first.data, 'line1\nline2');
    });

    test('retry field is parsed as int', () async {
      final events =
          await SseParser().parse(bytes('retry: 5000\ndata: x\n\n')).toList();
      expect(events.first.retry, 5000);
    });

    test('invalid retry ignored', () async {
      final events = await SseParser()
          .parse(bytes('retry: not-a-number\ndata: x\n\n'))
          .toList();
      expect(events.first.retry, isNull);
    });

    test('id with NUL character rejected', () async {
      final events = await SseParser()
          .parse(bytes('id: bad\u0000id\ndata: x\n\n'))
          .toList();
      expect(events.first.id, isNull);
    });

    test('multiple events reset state between', () async {
      final events = await SseParser()
          .parse(bytes(
              'event: a\ndata: 1\n\nevent: b\ndata: 2\n\n'))
          .toList();
      expect(events, hasLength(2));
      expect(events[0].eventType, 'a');
      expect(events[0].data, '1');
      expect(events[1].eventType, 'b');
      expect(events[1].data, '2');
    });

    test('reset() clears buffered state', () {
      final p = SseParser();
      p.reset();
      // No throw.
      expect(true, isTrue);
    });
  });

  group('parseStreamEventType', () {
    test('known types', () {
      expect(
          parseStreamEventType('message_start'), StreamEventType.messageStart);
      expect(parseStreamEventType('content_block_delta'),
          StreamEventType.contentBlockDelta);
      expect(parseStreamEventType('error'), StreamEventType.error);
    });
    test('unknown returns null', () {
      expect(parseStreamEventType('frobnicate'), isNull);
    });
    test('empty string → null', () {
      expect(parseStreamEventType(''), isNull);
    });
  });

  group('ToolUseAccumulator parsing', () {
    test('empty json returns empty map', () {
      final acc = ToolUseAccumulator(0, toolId: 't1', toolName: 'bash');
      expect(acc.parsedInput, isEmpty);
    });

    test('malformed JSON returns empty map (graceful)', () {
      final acc = ToolUseAccumulator(0, toolId: 't1', toolName: 'bash');
      acc.append('{broken');
      expect(acc.parsedInput, isEmpty);
    });

    test('incrementally appended JSON parses when complete', () {
      final acc = ToolUseAccumulator(0, toolId: 't1', toolName: 'bash');
      acc.append('{"cmd":');
      acc.append('"ls -la"');
      acc.append('}');
      expect(acc.parsedInput, {'cmd': 'ls -la'});
    });

    test('nested JSON object', () {
      final acc = ToolUseAccumulator(0, toolId: 't1', toolName: 'x');
      acc.append('{"a":{"b":[1,2,3]}}');
      final p = acc.parsedInput;
      expect((p['a'] as Map)['b'], [1, 2, 3]);
    });
  });

  group('StreamAssembler state machine', () {
    test('message_start populates id + model', () {
      final a = StreamAssembler();
      a.processEvent('message_start', {
        'message': {
          'id': 'msg-1',
          'model': 'claude-sonnet-4-6',
          'usage': {'input_tokens': 10, 'output_tokens': 0}
        }
      });
      expect(a.state.messageId, 'msg-1');
      expect(a.state.model, 'claude-sonnet-4-6');
    });

    test('text deltas accumulate into TextAccumulator', () {
      final a = StreamAssembler();
      a.processEvent('content_block_start', {
        'index': 0,
        'content_block': {'type': 'text', 'text': ''}
      });
      a.processEvent('content_block_delta', {
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'Hel'}
      });
      a.processEvent('content_block_delta', {
        'index': 0,
        'delta': {'type': 'text_delta', 'text': 'lo'}
      });
      final acc = a.state.contentBlocks.first as TextAccumulator;
      expect(acc.currentText, 'Hello');
    });

    test('tool_use input deltas buffer and parse on complete', () {
      final a = StreamAssembler();
      a.processEvent('content_block_start', {
        'index': 0,
        'content_block': {'type': 'tool_use', 'id': 'tu1', 'name': 'bash'}
      });
      a.processEvent('content_block_delta', {
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '{"c":'}
      });
      a.processEvent('content_block_delta', {
        'index': 0,
        'delta': {'type': 'input_json_delta', 'partial_json': '"ls"}'}
      });
      a.processEvent('content_block_stop', {'index': 0});
      final acc = a.state.contentBlocks.first as ToolUseAccumulator;
      expect(acc.parsedInput, {'c': 'ls'});
    });

    test('unknown event type is a no-op', () {
      final a = StreamAssembler();
      a.processEvent('unknown_event', {});
      expect(a.state.contentBlocks, isEmpty);
    });

    test('unknown block type falls back to text accumulator', () {
      final a = StreamAssembler();
      a.processEvent('content_block_start', {
        'index': 0,
        'content_block': {'type': 'mystery'}
      });
      expect(a.state.contentBlocks.first, isA<TextAccumulator>());
    });

    test('error event emits StreamError', () async {
      final a = StreamAssembler();
      final updates = <StreamUpdate>[];
      final sub = a.state.updates.listen(updates.add);
      a.processEvent('error', {
        'error': {'message': 'oops', 'type': 'bad_thing'}
      });
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(updates.any((u) => u is StreamError), isTrue);
    });

    test('delta for non-existent block index is dropped', () {
      final a = StreamAssembler();
      a.processEvent('content_block_delta', {
        'index': 42,
        'delta': {'type': 'text_delta', 'text': 'hi'}
      });
      // No crash.
      expect(a.state.contentBlocks, isEmpty);
    });

    test('message_delta updates stopReason', () {
      final a = StreamAssembler();
      a.processEvent('message_delta', {
        'delta': {'stop_reason': 'end_turn'},
        'usage': {'output_tokens': 42}
      });
      expect(a.state.stopReason, 'end_turn');
    });

    test('ping is ignored', () {
      final a = StreamAssembler();
      a.processEvent('ping', {});
      expect(a.state.contentBlocks, isEmpty);
    });
  });

  group('mediaTypeFromBytes', () {
    test('detects JPEG magic', () {
      expect(mediaTypeFromBytes([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
    });
    test('detects PNG magic', () {
      expect(
          mediaTypeFromBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]), 'image/png');
    });
    test('detects GIF magic', () {
      expect(mediaTypeFromBytes([0x47, 0x49, 0x46, 0x38, 0x37]), 'image/gif');
    });
    test('short buffer → null', () {
      expect(mediaTypeFromBytes([0x89]), isNull);
    });
    test('unknown bytes → null', () {
      expect(
          mediaTypeFromBytes([0x00, 0x01, 0x02, 0x03, 0x04]),
          isNull);
    });
  });

  group('mediaTypeFromExtension', () {
    test('.jpg and .jpeg → image/jpeg', () {
      expect(mediaTypeFromExtension('jpg'), 'image/jpeg');
      expect(mediaTypeFromExtension('JPEG'), 'image/jpeg');
    });
    test('unknown ext → null', () {
      expect(mediaTypeFromExtension('xyz'), isNull);
    });
  });

  group('processStream with malformed SSE data', () {
    test('bad JSON in data field emits StreamError', () async {
      Stream<List<int>> bad() async* {
        yield utf8.encode('event: message_start\ndata: {not json\n\n');
      }

      final updates = <StreamUpdate>[];
      await for (final u in processStream(bad())) {
        updates.add(u);
      }
      expect(updates.any((u) => u is StreamError), isTrue);
    });

    test('chunked bytes reassemble correctly', () async {
      // Split event across multiple byte chunks.
      Stream<List<int>> chunks() async* {
        yield utf8.encode('event: messag');
        yield utf8.encode('e_start\ndata: {"mess');
        yield utf8.encode('age":{"id":"m1","model":"x"}}\n\n');
      }

      StreamAssembler? assembler;
      final updates = <StreamUpdate>[];
      final (stream, a) = processStreamWithAssembler(chunks());
      assembler = a;
      await for (final u in stream) {
        updates.add(u);
      }
      expect(assembler.state.messageId, 'm1');
    });
  });
}
