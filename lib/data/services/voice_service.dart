// VoiceService — port of neom_claw/src/services/voice/.
// Speech-to-text and text-to-speech for multi-platform voice input.

import 'dart:async';
import 'dart:convert';
import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math';
import 'dart:typed_data';

// ─── Types ───

/// Voice input state.
enum VoiceState {
  idle,
  listening,
  processing,
  speaking,
  error,
}

/// Audio format for recording.
enum AudioFormat {
  wav,
  mp3,
  ogg,
  flac,
  webm,
  pcm16,
}

/// STT provider.
enum SttProvider {
  whisper, // OpenAI Whisper API
  whisperLocal, // Local whisper.cpp
  deepgram,
  assemblyAi,
  googleSpeech,
  azureSpeech,
  system, // System STT (macOS Dictation, Android, etc.)
}

/// TTS provider.
enum TtsProvider {
  openAi, // OpenAI TTS
  elevenlabs,
  googleTts,
  azureTts,
  system, // System TTS (macOS say, espeak, etc.)
}

/// Language for speech recognition.
class SpeechLanguage {
  final String code; // e.g. 'en-US', 'es-ES'
  final String name;
  final String nativeName;

  const SpeechLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  static const english = SpeechLanguage(code: 'en-US', name: 'English (US)', nativeName: 'English');
  static const spanish = SpeechLanguage(code: 'es-ES', name: 'Spanish', nativeName: 'Espanol');
  static const french = SpeechLanguage(code: 'fr-FR', name: 'French', nativeName: 'Francais');
  static const german = SpeechLanguage(code: 'de-DE', name: 'German', nativeName: 'Deutsch');
  static const japanese = SpeechLanguage(code: 'ja-JP', name: 'Japanese', nativeName: '日本語');
  static const chinese = SpeechLanguage(code: 'zh-CN', name: 'Chinese (Simplified)', nativeName: '简体中文');
  static const portuguese = SpeechLanguage(code: 'pt-BR', name: 'Portuguese (Brazil)', nativeName: 'Portugues');
  static const korean = SpeechLanguage(code: 'ko-KR', name: 'Korean', nativeName: '한국어');

  static const all = [english, spanish, french, german, japanese, chinese, portuguese, korean];
}

/// Voice configuration.
class VoiceConfig {
  final SttProvider sttProvider;
  final TtsProvider ttsProvider;
  final SpeechLanguage language;
  final String? apiKey; // For cloud providers
  final String? baseUrl; // Custom endpoint
  final String? model; // e.g. 'whisper-1'
  final String? voice; // TTS voice ID
  final double speed; // TTS speed multiplier
  final double silenceThreshold; // Seconds of silence before auto-stop
  final bool autoSend; // Auto-send transcription as message
  final bool continuousMode; // Keep listening after each utterance
  final int sampleRate; // Audio sample rate
  final AudioFormat format;

  const VoiceConfig({
    this.sttProvider = SttProvider.whisper,
    this.ttsProvider = TtsProvider.system,
    this.language = SpeechLanguage.english,
    this.apiKey,
    this.baseUrl,
    this.model = 'whisper-1',
    this.voice = 'alloy',
    this.speed = 1.0,
    this.silenceThreshold = 2.0,
    this.autoSend = false,
    this.continuousMode = false,
    this.sampleRate = 16000,
    this.format = AudioFormat.wav,
  });

  VoiceConfig copyWith({
    SttProvider? sttProvider,
    TtsProvider? ttsProvider,
    SpeechLanguage? language,
    String? apiKey,
    String? baseUrl,
    String? model,
    String? voice,
    double? speed,
    double? silenceThreshold,
    bool? autoSend,
    bool? continuousMode,
    int? sampleRate,
    AudioFormat? format,
  }) =>
      VoiceConfig(
        sttProvider: sttProvider ?? this.sttProvider,
        ttsProvider: ttsProvider ?? this.ttsProvider,
        language: language ?? this.language,
        apiKey: apiKey ?? this.apiKey,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        voice: voice ?? this.voice,
        speed: speed ?? this.speed,
        silenceThreshold: silenceThreshold ?? this.silenceThreshold,
        autoSend: autoSend ?? this.autoSend,
        continuousMode: continuousMode ?? this.continuousMode,
        sampleRate: sampleRate ?? this.sampleRate,
        format: format ?? this.format,
      );
}

/// Transcription result from STT.
class TranscriptionResult {
  final String text;
  final double confidence;
  final SpeechLanguage? detectedLanguage;
  final Duration duration;
  final List<TranscriptionSegment> segments;
  final String? rawResponse;

  const TranscriptionResult({
    required this.text,
    this.confidence = 1.0,
    this.detectedLanguage,
    required this.duration,
    this.segments = const [],
    this.rawResponse,
  });
}

/// A segment of transcription with timing.
class TranscriptionSegment {
  final String text;
  final Duration start;
  final Duration end;
  final double confidence;

  const TranscriptionSegment({
    required this.text,
    required this.start,
    required this.end,
    this.confidence = 1.0,
  });
}

/// Audio level data for visualization.
class AudioLevel {
  final double rms; // Root mean square (0.0 - 1.0)
  final double peak; // Peak level (0.0 - 1.0)
  final DateTime timestamp;

  const AudioLevel({
    required this.rms,
    required this.peak,
    required this.timestamp,
  });
}

/// Voice event for state changes.
sealed class VoiceEvent {
  const VoiceEvent();
}

class VoiceStateChanged extends VoiceEvent {
  final VoiceState state;
  const VoiceStateChanged(this.state);
}

class VoiceTranscriptionPartial extends VoiceEvent {
  final String text;
  const VoiceTranscriptionPartial(this.text);
}

class VoiceTranscriptionComplete extends VoiceEvent {
  final TranscriptionResult result;
  const VoiceTranscriptionComplete(this.result);
}

class VoiceAudioLevel extends VoiceEvent {
  final AudioLevel level;
  const VoiceAudioLevel(this.level);
}

class VoiceSpeakingComplete extends VoiceEvent {
  const VoiceSpeakingComplete();
}

class VoiceError extends VoiceEvent {
  final String message;
  final Object? error;
  const VoiceError(this.message, [this.error]);
}

// ─── Audio Recorder ───

/// Records audio from the microphone.
class AudioRecorder {
  final int sampleRate;
  final AudioFormat format;
  Process? _process;
  final List<int> _buffer = [];
  final StreamController<AudioLevel> _levelController =
      StreamController<AudioLevel>.broadcast();
  bool _isRecording = false;
  DateTime? _startTime;

  AudioRecorder({this.sampleRate = 16000, this.format = AudioFormat.wav});

  bool get isRecording => _isRecording;
  Stream<AudioLevel> get levelStream => _levelController.stream;
  Duration get recordingDuration => _startTime != null
      ? DateTime.now().difference(_startTime!)
      : Duration.zero;

  /// Start recording audio.
  Future<void> start() async {
    if (_isRecording) return;

    _buffer.clear();
    _startTime = DateTime.now();
    _isRecording = true;

    // Use platform-appropriate recording command.
    if (Platform.isMacOS) {
      _process = await Process.start('rec', [
        '-q', // Quiet
        '-r', '$sampleRate', // Sample rate
        '-c', '1', // Mono
        '-b', '16', // 16-bit
        '-t', _formatExtension(), // Output format
        '-', // Stdout
      ]);
    } else if (Platform.isLinux) {
      _process = await Process.start('arecord', [
        '-q',
        '-r', '$sampleRate',
        '-c', '1',
        '-f', 'S16_LE',
        '-t', _formatExtension(),
        '-',
      ]);
    } else {
      throw UnsupportedError(
          'Audio recording not supported on ${Platform.operatingSystem}');
    }

    // Collect audio data and compute levels.
    _process!.stdout.listen((data) {
      _buffer.addAll(data);

      // Compute audio level from PCM data.
      if (data.length >= 2) {
        final level = _computeLevel(data);
        _levelController.add(level);
      }
    });

    _process!.stderr.listen((_) {}); // Ignore stderr.
  }

  /// Stop recording and return audio data.
  Future<Uint8List> stop() async {
    if (!_isRecording) return Uint8List(0);

    _isRecording = false;
    _process?.kill(ProcessSignal.sigterm);
    await _process?.exitCode;
    _process = null;

    return Uint8List.fromList(_buffer);
  }

  /// Cancel recording without saving.
  Future<void> cancel() async {
    _isRecording = false;
    _process?.kill(ProcessSignal.sigkill);
    _process = null;
    _buffer.clear();
  }

  String _formatExtension() {
    return switch (format) {
      AudioFormat.wav => 'wav',
      AudioFormat.mp3 => 'mp3',
      AudioFormat.ogg => 'ogg',
      AudioFormat.flac => 'flac',
      AudioFormat.webm => 'webm',
      AudioFormat.pcm16 => 'raw',
    };
  }

  AudioLevel _computeLevel(List<int> data) {
    // Parse as 16-bit signed PCM.
    double sumSquares = 0;
    double peak = 0;
    final sampleCount = data.length ~/ 2;

    for (int i = 0; i < data.length - 1; i += 2) {
      final sample = (data[i] | (data[i + 1] << 8));
      final signed = sample > 32767 ? sample - 65536 : sample;
      final normalized = signed / 32768.0;
      sumSquares += normalized * normalized;
      peak = max(peak, normalized.abs());
    }

    final rms = sampleCount > 0 ? sqrt(sumSquares / sampleCount) : 0.0;

    return AudioLevel(
      rms: rms.clamp(0.0, 1.0),
      peak: peak.clamp(0.0, 1.0),
      timestamp: DateTime.now(),
    );
  }

  void dispose() {
    cancel();
    _levelController.close();
  }
}

// ─── STT Providers ───

/// Abstract speech-to-text provider.
abstract class SttEngine {
  Future<TranscriptionResult> transcribe(
    Uint8List audio,
    VoiceConfig config,
  );

  Future<Stream<String>> transcribeStream(
    Stream<Uint8List> audioStream,
    VoiceConfig config,
  );
}

/// OpenAI Whisper STT.
class WhisperSttEngine implements SttEngine {
  @override
  Future<TranscriptionResult> transcribe(
    Uint8List audio,
    VoiceConfig config,
  ) async {
    final apiKey = config.apiKey;
    if (apiKey == null) throw StateError('API key required for Whisper STT');

    final baseUrl = config.baseUrl ?? 'https://api.openai.com/v1';

    // Create multipart request.
    final boundary = 'dart-voice-${DateTime.now().millisecondsSinceEpoch}';
    final body = _buildMultipartBody(audio, config, boundary);

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/audio/transcriptions'));
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'multipart/form-data; boundary=$boundary');
      request.add(body);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode != 200) {
        throw Exception('Whisper API error: $responseBody');
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final text = json['text'] as String? ?? '';
      final segments = (json['segments'] as List<dynamic>?)
              ?.map((s) => TranscriptionSegment(
                    text: s['text'] as String,
                    start: Duration(
                        milliseconds: ((s['start'] as num) * 1000).round()),
                    end: Duration(
                        milliseconds: ((s['end'] as num) * 1000).round()),
                    confidence:
                        (s['avg_logprob'] as num?)?.toDouble() ?? 1.0,
                  ))
              .toList() ??
          [];

      return TranscriptionResult(
        text: text,
        duration: Duration(
            milliseconds:
                ((json['duration'] as num?)?.toDouble() ?? 0) * 1000 ~/ 1),
        segments: segments,
        detectedLanguage: _detectLanguage(json['language'] as String?),
        rawResponse: responseBody,
      );
    } finally {
      client.close();
    }
  }

  @override
  Future<Stream<String>> transcribeStream(
    Stream<Uint8List> audioStream,
    VoiceConfig config,
  ) async {
    // Whisper doesn't support streaming — buffer and transcribe.
    final controller = StreamController<String>();
    final buffer = <int>[];

    audioStream.listen(
      (chunk) => buffer.addAll(chunk),
      onDone: () async {
        try {
          final result = await transcribe(
              Uint8List.fromList(buffer), config);
          controller.add(result.text);
          controller.close();
        } catch (e) {
          controller.addError(e);
          controller.close();
        }
      },
      onError: (e) {
        controller.addError(e);
        controller.close();
      },
    );

    return controller.stream;
  }

  Uint8List _buildMultipartBody(
      Uint8List audio, VoiceConfig config, String boundary) {
    final buffer = BytesBuilder();
    final encoder = utf8.encoder;

    void addField(String name, String value) {
      buffer.add(encoder.convert('--$boundary\r\n'));
      buffer.add(encoder.convert(
          'Content-Disposition: form-data; name="$name"\r\n\r\n'));
      buffer.add(encoder.convert('$value\r\n'));
    }

    void addFile(String name, String filename, Uint8List data) {
      buffer.add(encoder.convert('--$boundary\r\n'));
      buffer.add(encoder.convert(
          'Content-Disposition: form-data; name="$name"; filename="$filename"\r\n'));
      buffer.add(encoder.convert('Content-Type: audio/wav\r\n\r\n'));
      buffer.add(data);
      buffer.add(encoder.convert('\r\n'));
    }

    addFile('file', 'recording.wav', audio);
    addField('model', config.model ?? 'whisper-1');
    addField('language', config.language.code.split('-').first);
    addField('response_format', 'verbose_json');

    buffer.add(encoder.convert('--$boundary--\r\n'));

    return buffer.toBytes();
  }

  SpeechLanguage? _detectLanguage(String? code) {
    if (code == null) return null;
    return SpeechLanguage.all.cast<SpeechLanguage?>().firstWhere(
          (l) => l!.code.startsWith(code),
          orElse: () => null,
        );
  }
}

/// System STT using platform commands.
class SystemSttEngine implements SttEngine {
  @override
  Future<TranscriptionResult> transcribe(
    Uint8List audio,
    VoiceConfig config,
  ) async {
    // On macOS, use the system speech recognition (limited).
    // In practice, this delegates to a more capable provider.
    if (Platform.isMacOS) {
      // Save audio to temp file and use macOS Dictation API via osascript.
      final tempFile = File(
          '${Directory.systemTemp.path}/claw_audio_${DateTime.now().millisecondsSinceEpoch}.wav');
      await tempFile.writeAsBytes(audio);

      try {
        // Fallback: use a local whisper binary if available.
        final whisperResult = await Process.run('which', ['whisper']);
        if (whisperResult.exitCode == 0) {
          final result = await Process.run('whisper', [
            tempFile.path,
            '--model', 'base',
            '--language', config.language.code.split('-').first,
            '--output_format', 'json',
            '--output_dir', Directory.systemTemp.path,
          ]);

          if (result.exitCode == 0) {
            final jsonFile = File(tempFile.path.replaceAll('.wav', '.json'));
            if (await jsonFile.exists()) {
              final json = jsonDecode(await jsonFile.readAsString())
                  as Map<String, dynamic>;
              await jsonFile.delete();
              return TranscriptionResult(
                text: json['text'] as String? ?? '',
                duration: Duration.zero,
              );
            }
          }
        }

        return const TranscriptionResult(
          text: '',
          duration: Duration.zero,
        );
      } finally {
        if (await tempFile.exists()) await tempFile.delete();
      }
    }

    throw UnsupportedError(
        'System STT not supported on ${Platform.operatingSystem}');
  }

  @override
  Future<Stream<String>> transcribeStream(
    Stream<Uint8List> audioStream,
    VoiceConfig config,
  ) async {
    throw UnsupportedError('System STT does not support streaming');
  }
}

// ─── TTS Providers ───

/// Abstract text-to-speech provider.
abstract class TtsEngine {
  Future<Uint8List> synthesize(String text, VoiceConfig config);
  Future<void> speak(String text, VoiceConfig config);
  Future<void> stop();
}

/// System TTS using platform commands.
class SystemTtsEngine implements TtsEngine {
  Process? _speakProcess;

  @override
  Future<Uint8List> synthesize(String text, VoiceConfig config) async {
    if (Platform.isMacOS) {
      final tempFile = File(
          '${Directory.systemTemp.path}/claw_tts_${DateTime.now().millisecondsSinceEpoch}.aiff');

      await Process.run('say', [
        '-o', tempFile.path,
        '-r', '${(175 * config.speed).round()}', // Words per minute
        text,
      ]);

      if (await tempFile.exists()) {
        final data = await tempFile.readAsBytes();
        await tempFile.delete();
        return data;
      }
    }

    return Uint8List(0);
  }

  @override
  Future<void> speak(String text, VoiceConfig config) async {
    await stop(); // Stop any current speech.

    if (Platform.isMacOS) {
      _speakProcess = await Process.start('say', [
        '-r', '${(175 * config.speed).round()}',
        text,
      ]);
      await _speakProcess!.exitCode;
      _speakProcess = null;
    } else if (Platform.isLinux) {
      _speakProcess = await Process.start('espeak', [
        '-s', '${(175 * config.speed).round()}',
        text,
      ]);
      await _speakProcess!.exitCode;
      _speakProcess = null;
    }
  }

  @override
  Future<void> stop() async {
    _speakProcess?.kill();
    _speakProcess = null;
  }
}

/// OpenAI TTS engine.
class OpenAiTtsEngine implements TtsEngine {
  Process? _playProcess;

  @override
  Future<Uint8List> synthesize(String text, VoiceConfig config) async {
    final apiKey = config.apiKey;
    if (apiKey == null) throw StateError('API key required for OpenAI TTS');

    final baseUrl = config.baseUrl ?? 'https://api.openai.com/v1';

    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse('$baseUrl/audio/speech'));
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.headers.set('Content-Type', 'application/json');
      request.add(utf8.encode(jsonEncode({
        'model': 'tts-1',
        'input': text,
        'voice': config.voice ?? 'alloy',
        'speed': config.speed,
        'response_format': 'mp3',
      })));

      final response = await request.close();
      if (response.statusCode != 200) {
        final body = await response.transform(utf8.decoder).join();
        throw Exception('OpenAI TTS error: $body');
      }

      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return Uint8List.fromList(bytes);
    } finally {
      client.close();
    }
  }

  @override
  Future<void> speak(String text, VoiceConfig config) async {
    final audio = await synthesize(text, config);

    // Save to temp file and play.
    final tempFile = File(
        '${Directory.systemTemp.path}/claw_speech_${DateTime.now().millisecondsSinceEpoch}.mp3');
    await tempFile.writeAsBytes(audio);

    try {
      if (Platform.isMacOS) {
        _playProcess = await Process.start('afplay', [tempFile.path]);
      } else if (Platform.isLinux) {
        _playProcess = await Process.start('mpv', ['--no-video', tempFile.path]);
      }
      await _playProcess?.exitCode;
    } finally {
      if (await tempFile.exists()) await tempFile.delete();
      _playProcess = null;
    }
  }

  @override
  Future<void> stop() async {
    _playProcess?.kill();
    _playProcess = null;
  }
}

// ─── Voice Service ───

/// Main voice service coordinating recording, STT, and TTS.
class VoiceService {
  VoiceConfig _config;
  VoiceState _state = VoiceState.idle;
  final AudioRecorder _recorder;
  late SttEngine _stt;
  late TtsEngine _tts;
  final StreamController<VoiceEvent> _eventController =
      StreamController<VoiceEvent>.broadcast();
  Timer? _silenceTimer;
  DateTime? _lastAudioAboveThreshold;
  StreamSubscription<AudioLevel>? _levelSub;

  VoiceService({VoiceConfig? config})
      : _config = config ?? const VoiceConfig(),
        _recorder = AudioRecorder(
          sampleRate: config?.sampleRate ?? 16000,
          format: config?.format ?? AudioFormat.wav,
        ) {
    _initEngines();
  }

  void _initEngines() {
    _stt = switch (_config.sttProvider) {
      SttProvider.whisper => WhisperSttEngine(),
      SttProvider.system => SystemSttEngine(),
      _ => WhisperSttEngine(), // Default to Whisper
    };

    _tts = switch (_config.ttsProvider) {
      TtsProvider.openAi => OpenAiTtsEngine(),
      TtsProvider.system => SystemTtsEngine(),
      _ => SystemTtsEngine(), // Default to system
    };
  }

  /// Current voice state.
  VoiceState get state => _state;

  /// Voice event stream.
  Stream<VoiceEvent> get events => _eventController.stream;

  /// Audio level stream (while recording).
  Stream<AudioLevel> get audioLevels => _recorder.levelStream;

  /// Current configuration.
  VoiceConfig get config => _config;

  /// Update configuration.
  void updateConfig(VoiceConfig newConfig) {
    _config = newConfig;
    _initEngines();
  }

  /// Start listening for voice input.
  Future<void> startListening() async {
    if (_state != VoiceState.idle) return;

    _setState(VoiceState.listening);

    try {
      await _recorder.start();

      // Monitor audio levels for silence detection.
      _lastAudioAboveThreshold = DateTime.now();
      _levelSub = _recorder.levelStream.listen((level) {
        _eventController.add(VoiceAudioLevel(level));

        if (level.rms > 0.02) {
          _lastAudioAboveThreshold = DateTime.now();
        }
      });

      // Start silence detection timer.
      _silenceTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
        if (_lastAudioAboveThreshold != null) {
          final silenceDuration =
              DateTime.now().difference(_lastAudioAboveThreshold!);
          if (silenceDuration.inMilliseconds >
              (_config.silenceThreshold * 1000)) {
            // Silence detected — stop recording.
            stopListening();
          }
        }
      });
    } catch (e) {
      _setState(VoiceState.error);
      _eventController.add(VoiceError('Failed to start recording', e));
    }
  }

  /// Stop listening and process the recording.
  Future<TranscriptionResult?> stopListening() async {
    if (_state != VoiceState.listening) return null;

    _silenceTimer?.cancel();
    _levelSub?.cancel();
    _setState(VoiceState.processing);

    try {
      final audio = await _recorder.stop();
      if (audio.isEmpty) {
        _setState(VoiceState.idle);
        return null;
      }

      final result = await _stt.transcribe(audio, _config);
      _eventController.add(VoiceTranscriptionComplete(result));
      _setState(VoiceState.idle);

      return result;
    } catch (e) {
      _setState(VoiceState.error);
      _eventController.add(VoiceError('Transcription failed', e));
      // Reset to idle after error.
      await Future.delayed(const Duration(seconds: 2));
      _setState(VoiceState.idle);
      return null;
    }
  }

  /// Cancel current recording without processing.
  Future<void> cancelListening() async {
    _silenceTimer?.cancel();
    _levelSub?.cancel();
    await _recorder.cancel();
    _setState(VoiceState.idle);
  }

  /// Speak text using TTS.
  Future<void> speak(String text) async {
    if (_state == VoiceState.speaking) {
      await stopSpeaking();
    }

    _setState(VoiceState.speaking);

    try {
      await _tts.speak(text, _config);
      _eventController.add(const VoiceSpeakingComplete());
    } catch (e) {
      _eventController.add(VoiceError('TTS failed', e));
    } finally {
      _setState(VoiceState.idle);
    }
  }

  /// Stop current TTS playback.
  Future<void> stopSpeaking() async {
    await _tts.stop();
    _setState(VoiceState.idle);
  }

  /// Toggle listening state.
  Future<TranscriptionResult?> toggle() async {
    if (_state == VoiceState.listening) {
      return stopListening();
    } else if (_state == VoiceState.idle) {
      await startListening();
      return null;
    } else if (_state == VoiceState.speaking) {
      await stopSpeaking();
      return null;
    }
    return null;
  }

  /// Check if voice input is available on this platform.
  Future<bool> isAvailable() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('which', ['rec']);
        return result.exitCode == 0;
      } else if (Platform.isLinux) {
        final result = await Process.run('which', ['arecord']);
        return result.exitCode == 0;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// List available TTS voices.
  Future<List<String>> listVoices() async {
    if (Platform.isMacOS) {
      final result = await Process.run('say', ['-v', '?']);
      if (result.exitCode == 0) {
        return (result.stdout as String)
            .split('\n')
            .where((l) => l.trim().isNotEmpty)
            .map((l) => l.split(RegExp(r'\s+')).first)
            .toList();
      }
    }
    return [];
  }

  void _setState(VoiceState newState) {
    _state = newState;
    _eventController.add(VoiceStateChanged(newState));
  }

  /// Dispose resources.
  void dispose() {
    _silenceTimer?.cancel();
    _levelSub?.cancel();
    _recorder.dispose();
    _eventController.close();
  }
}
