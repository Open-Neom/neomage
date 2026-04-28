import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/realtime/gemini_realtime_client.dart';
import 'package:neomage/realtime/gemini_realtime_event.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal WebSocketChannel double — captures everything sent and lets the
/// test feed messages back via [emit]. We intentionally only implement what
/// `GeminiRealtimeClient` touches; throwing on the rest keeps the surface
/// honest.
class _FakeChannel implements WebSocketChannel {
  final StreamController<dynamic> _incoming =
      StreamController<dynamic>.broadcast();
  final List<dynamic> sentMessages = [];
  bool _closed = false;

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _Sink(this);

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready async {}

  void emit(dynamic message) {
    if (_closed) return;
    _incoming.add(message);
  }

  Future<void> dispose() async {
    if (!_closed) {
      _closed = true;
      await _incoming.close();
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeChannel does not implement ${invocation.memberName}',
    );
  }
}

class _Sink implements WebSocketSink {
  final _FakeChannel parent;
  _Sink(this.parent);

  @override
  void add(dynamic data) => parent.sentMessages.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final m in stream) {
      add(m);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await parent.dispose();
  }

  @override
  Future<void> get done async {}
}

Map<String, Object?> _decodeSent(_FakeChannel channel, int index) {
  final raw = channel.sentMessages[index];
  expect(raw, isA<String>());
  return (jsonDecode(raw as String) as Map).cast<String, Object?>();
}

void main() {
  late _FakeChannel channel;
  late GeminiRealtimeClient client;

  setUp(() {
    channel = _FakeChannel();
    client = GeminiRealtimeClient(
      apiKey: 'test-key',
      model: 'models/test',
      connector: (_) => channel,
    );
  });

  tearDown(() async {
    await client.close();
    await channel.dispose();
  });

  group('connect', () {
    test('sends a setup envelope with model + modalities', () async {
      await client.connect();
      expect(channel.sentMessages, hasLength(1));
      final setup = _decodeSent(channel, 0)['setup'] as Map<String, Object?>?;
      expect(setup, isNotNull);
      expect(setup!['model'], equals('models/test'));
      expect(
        (setup['generation_config'] as Map)['response_modalities'],
        equals(['AUDIO']),
      );
    });

    test('includes systemInstruction when configured', () async {
      final c = GeminiRealtimeClient(
        apiKey: 'k',
        model: 'm',
        systemInstruction: 'You are Itzli.',
        connector: (_) => channel,
      );
      await c.connect();
      final setup = _decodeSent(channel, 0)['setup'] as Map<String, Object?>;
      final si = setup['system_instruction'] as Map<String, Object?>?;
      expect(si, isNotNull);
      final parts = si!['parts'] as List;
      expect(parts.first, equals({'text': 'You are Itzli.'}));
      await c.close();
    });

    test('isReady is false until setupComplete arrives', () async {
      await client.connect();
      expect(client.isReady, isFalse);
      client.debugInjectServerMessage({'setupComplete': {}});
      await Future<void>.delayed(Duration.zero);
      expect(client.isReady, isTrue);
    });
  });

  group('sendAudio', () {
    test('throws before connect', () async {
      await expectLater(
        () => client.sendAudio(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<StateError>()),
      );
    });

    test('encodes PCM as base64 inside realtime_input', () async {
      await client.connect();
      await client.sendAudio(Uint8List.fromList([0x10, 0x20, 0x30, 0x40]));
      final body =
          _decodeSent(channel, 1)['realtime_input'] as Map<String, Object?>;
      final chunks = body['media_chunks'] as List;
      expect(chunks, hasLength(1));
      final chunk = chunks.first as Map<String, Object?>;
      expect(chunk['mime_type'], equals('audio/pcm;rate=16000'));
      expect(
        chunk['data'],
        equals(base64Encode(Uint8List.fromList([0x10, 0x20, 0x30, 0x40]))),
      );
    });
  });

  group('sendText / sendTurnComplete', () {
    test('sendText puts a turn with role=user', () async {
      await client.connect();
      await client.sendText('hola');
      final body =
          _decodeSent(channel, 1)['client_content'] as Map<String, Object?>;
      expect(body['turn_complete'], isTrue);
      final turns = body['turns'] as List;
      expect(turns, hasLength(1));
      final turn = turns.first as Map<String, Object?>;
      expect(turn['role'], equals('user'));
      expect((turn['parts'] as List).first, equals({'text': 'hola'}));
    });

    test('sendTurnComplete sends a bare turn_complete envelope', () async {
      await client.connect();
      await client.sendTurnComplete();
      final body =
          _decodeSent(channel, 1)['client_content'] as Map<String, Object?>;
      expect(body['turn_complete'], isTrue);
      expect(body['turns'], isNull);
    });
  });

  group('inbound dispatch', () {
    test('emits GeminiSetupComplete', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({'setupComplete': {}});
      await Future<void>.delayed(Duration.zero);
      expect(events.last, isA<GeminiSetupComplete>());
    });

    test('emits GeminiTextDelta from modelTurn parts', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {'text': 'Hola, '},
              {'text': 'soy Itzli.'},
            ],
          },
        },
      });
      await Future<void>.delayed(Duration.zero);
      final deltas = events.whereType<GeminiTextDelta>().toList();
      expect(deltas.map((e) => e.text).toList(),
          equals(['Hola, ', 'soy Itzli.']));
    });

    test('emits GeminiAudioOut for inline audio/pcm parts', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      final pcm = Uint8List.fromList([1, 2, 3, 4, 5]);
      client.debugInjectServerMessage({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode(pcm),
                },
              },
            ],
          },
        },
      });
      await Future<void>.delayed(Duration.zero);
      final audio = events.whereType<GeminiAudioOut>().toList();
      expect(audio, hasLength(1));
      expect(audio.first.pcm, equals(pcm));
    });

    test('emits GeminiInterrupted', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({
        'serverContent': {'interrupted': true},
      });
      await Future<void>.delayed(Duration.zero);
      expect(events.any((e) => e is GeminiInterrupted), isTrue);
    });

    test('emits GeminiTurnComplete', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({
        'serverContent': {'turnComplete': true},
      });
      await Future<void>.delayed(Duration.zero);
      expect(events.last, isA<GeminiTurnComplete>());
    });

    test('emits GeminiRealtimeError on error envelope', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({
        'error': {'code': 'auth', 'message': 'API key invalid'},
      });
      await Future<void>.delayed(Duration.zero);
      final err = events.last as GeminiRealtimeError;
      expect(err.code, equals('auth'));
      expect(err.message, equals('API key invalid'));
    });

    test('decodes audio + text in a single combined turn', () async {
      await client.connect();
      final events = <GeminiRealtimeEvent>[];
      client.events.listen(events.add);
      client.debugInjectServerMessage({
        'serverContent': {
          'modelTurn': {
            'parts': [
              {'text': 'Hola.'},
              {
                'inlineData': {
                  'mimeType': 'audio/pcm;rate=24000',
                  'data': base64Encode(Uint8List.fromList([9, 9, 9])),
                },
              },
            ],
          },
          'turnComplete': true,
        },
      });
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<GeminiTextDelta>(), hasLength(1));
      expect(events.whereType<GeminiAudioOut>(), hasLength(1));
      expect(events.last, isA<GeminiTurnComplete>());
    });
  });
}
