import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'gemini_realtime_event.dart';

/// Client for the Gemini Live (BidiGenerateContent) WebSocket API.
///
/// **Audio formats** (per Google docs):
///   * **Input**: PCM 16-bit, 16 kHz, mono, little-endian — base64-encoded
///     into JSON `realtime_input.media_chunks` messages.
///   * **Output**: PCM 16-bit, **24 kHz**, mono, little-endian — base64
///     blobs inside `serverContent.modelTurn.parts[].inlineData.data`.
///
/// **Lifecycle**:
///   1. `connect()` opens the WebSocket and sends the `setup` message.
///   2. The server responds with a setup-complete signal → emitted as
///      [GeminiSetupComplete] on [events].
///   3. Caller streams audio chunks in via [sendAudio], optional text via
///      [sendText], and signals end-of-turn with [sendTurnComplete] (or
///      lets the server's VAD do it).
///   4. The server replies on [events] with audio + text deltas plus
///      [GeminiTurnComplete] when done.
///   5. `close()` shuts the socket cleanly.
///
/// **Audio agnostic.** This client never touches a microphone or a speaker.
/// Callers wire in their own (`record` package on Itzli mobile, the Web
/// Audio API in browser, etc.) and feed PCM bytes through. That keeps
/// `neomage` pure-Dart with no platform shims.
///
/// **Network policy.** Uses `WebSocketChannel.connect`, which honours the
/// system proxy on Dart VM. The TLS / cert chain is whatever the platform's
/// default trust store accepts.
class GeminiRealtimeClient {
  /// Default Gemini Live endpoint. Override with [endpoint] when pointing
  /// at a regional or proxy URL.
  static const String defaultEndpoint =
      'wss://generativelanguage.googleapis.com/ws/'
      'google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent';

  /// Default model id for low-latency voice. Override per session.
  static const String defaultModel = 'models/gemini-2.0-flash-exp';

  final String apiKey;
  final String model;
  final String endpoint;

  /// Modalities the server should produce. Common values: `['AUDIO']` for
  /// pure voice, `['TEXT']` for speech-to-text mode, `['AUDIO', 'TEXT']`
  /// for both (the API limits combinations — check current docs).
  final List<String> responseModalities;

  /// Optional system instructions sent in the setup message.
  final String? systemInstruction;

  /// Override for the WebSocket connector — tests inject a fake.
  /// Production callers leave it null.
  final WebSocketChannel Function(Uri uri)? connector;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final StreamController<GeminiRealtimeEvent> _events =
      StreamController<GeminiRealtimeEvent>.broadcast();
  bool _setupComplete = false;
  bool _closed = false;

  GeminiRealtimeClient({
    required this.apiKey,
    this.model = defaultModel,
    this.endpoint = defaultEndpoint,
    this.responseModalities = const ['AUDIO'],
    this.systemInstruction,
    this.connector,
  });

  /// Hot stream of every event from the server. Subscribe before calling
  /// [connect] so you don't miss [GeminiSetupComplete].
  Stream<GeminiRealtimeEvent> get events => _events.stream;

  /// `true` once the initial setup handshake completed.
  bool get isReady => _setupComplete && !_closed;

  /// Whether [close] has run (or the server closed first).
  bool get isClosed => _closed;

  /// Opens the WebSocket and sends the setup envelope. Returns once
  /// the channel is open — [GeminiSetupComplete] arrives later on
  /// [events] after the server acks.
  Future<void> connect() async {
    if (_channel != null) return;
    final uri = Uri.parse('$endpoint?key=$apiKey');
    final channel = (connector ?? WebSocketChannel.connect)(uri);
    _channel = channel;
    _sub = channel.stream.listen(
      _onMessage,
      onError: (Object error, StackTrace st) {
        _events.add(
          GeminiRealtimeError(error.toString(), code: 'transport'),
        );
      },
      onDone: () {
        _closed = true;
      },
    );
    _send({
      'setup': {
        'model': model,
        'generation_config': {
          'response_modalities': responseModalities,
        },
        if (systemInstruction != null)
          'system_instruction': {
            'parts': [
              {'text': systemInstruction},
            ],
          },
      },
    });
  }

  /// Sends one chunk of microphone audio. [pcm16] must be 16-bit PCM, 16 kHz,
  /// mono, little-endian. Chunk size: 80–200 ms is the sweet spot
  /// (1280–3200 samples). Throws if called before [connect].
  Future<void> sendAudio(Uint8List pcm16) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError('GeminiRealtimeClient.sendAudio: not connected');
    }
    _send({
      'realtime_input': {
        'media_chunks': [
          {
            'mime_type': 'audio/pcm;rate=16000',
            'data': base64Encode(pcm16),
          },
        ],
      },
    });
  }

  /// Sends a text turn (e.g. when the user types instead of speaking).
  Future<void> sendText(String text) async {
    final ch = _channel;
    if (ch == null) {
      throw StateError('GeminiRealtimeClient.sendText: not connected');
    }
    _send({
      'client_content': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text},
            ],
          },
        ],
        'turn_complete': true,
      },
    });
  }

  /// Signals that the user has finished their current turn. Use when
  /// you've disabled server-side VAD and want explicit boundaries.
  Future<void> sendTurnComplete() async {
    final ch = _channel;
    if (ch == null) return;
    _send({
      'client_content': {'turn_complete': true},
    });
  }

  /// Closes the WebSocket. Safe to call more than once.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _sub?.cancel();
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    if (!_events.isClosed) await _events.close();
  }

  // ─── internals ────────────────────────────────────────────

  void _send(Map<String, Object?> message) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(message));
  }

  void _onMessage(dynamic raw) {
    Map<String, Object?>? json;
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          json = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      } else if (raw is List<int>) {
        final decoded = jsonDecode(utf8.decode(raw, allowMalformed: true));
        if (decoded is Map) {
          json = decoded.map((k, v) => MapEntry(k.toString(), v));
        }
      }
    } catch (e) {
      _events.add(
        GeminiRealtimeError('Bad JSON from server: $e', code: 'parse'),
      );
      return;
    }
    if (json == null) return;
    _dispatch(json);
  }

  /// Decodes one message envelope into one or more [GeminiRealtimeEvent]s.
  ///
  /// Exposed for tests so we can verify branch handling without standing
  /// up a fake WebSocket.
  void _dispatch(Map<String, Object?> json) {
    if (json.containsKey('setupComplete')) {
      _setupComplete = true;
      _events.add(const GeminiSetupComplete());
      return;
    }
    final serverContent = json['serverContent'];
    if (serverContent is Map) {
      _handleServerContent(
        serverContent.map((k, v) => MapEntry(k.toString(), v)),
      );
      return;
    }
    final error = json['error'];
    if (error is Map) {
      final msg = error['message']?.toString() ?? 'unknown error';
      final code = error['code']?.toString();
      _events.add(GeminiRealtimeError(msg, code: code));
      return;
    }
  }

  void _handleServerContent(Map<String, Object?> sc) {
    if (sc['interrupted'] == true) {
      _events.add(const GeminiInterrupted());
    }
    final modelTurn = sc['modelTurn'];
    if (modelTurn is Map) {
      final parts = modelTurn['parts'];
      if (parts is List) {
        for (final part in parts) {
          if (part is! Map) continue;
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            _events.add(GeminiTextDelta(text));
          }
          final inline = part['inlineData'];
          if (inline is Map) {
            final mimeType = inline['mimeType']?.toString() ?? '';
            final data = inline['data'];
            if (mimeType.startsWith('audio/pcm') && data is String) {
              try {
                _events.add(GeminiAudioOut(base64Decode(data)));
              } catch (e) {
                _events.add(GeminiRealtimeError(
                  'Bad audio base64: $e',
                  code: 'audio',
                ));
              }
            }
          }
        }
      }
    }
    if (sc['turnComplete'] == true) {
      _events.add(const GeminiTurnComplete());
    }
  }

  /// Test-only entry point. Forwards a server message into the event stream
  /// without going through a WebSocket. Mirror of what `_onMessage` would
  /// do on real input.
  void debugInjectServerMessage(Map<String, Object?> message) {
    _dispatch(message);
  }
}
