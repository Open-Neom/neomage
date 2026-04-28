import 'dart:typed_data';

/// One event coming back from the Gemini Live WebSocket.
///
/// The server's response stream is multiplexed: it can carry audio chunks,
/// text deltas, turn-completion markers, and errors. Consumers pattern-match
/// on the runtime type to dispatch.
///
/// ```dart
/// client.events.listen((event) {
///   switch (event) {
///     case GeminiAudioOut(:final pcm): speaker.play(pcm);
///     case GeminiTextDelta(:final text): chatLog.appendDelta(text);
///     case GeminiTurnComplete(): speaker.flush();
///     case GeminiSetupComplete(): // ready to accept input
///     case GeminiInterrupted(): speaker.cancel();
///     case GeminiError(:final message): showToast(message);
///   }
/// });
/// ```
sealed class GeminiRealtimeEvent {
  const GeminiRealtimeEvent();
}

/// One chunk of synthesised audio coming back from the model.
///
/// Format: PCM 16-bit, **24 kHz**, mono, little-endian. Caller is responsible
/// for queueing chunks in arrival order — the API can split a single utterance
/// across many chunks.
final class GeminiAudioOut extends GeminiRealtimeEvent {
  final Uint8List pcm;
  const GeminiAudioOut(this.pcm);

  @override
  String toString() => 'GeminiAudioOut(${pcm.length} bytes)';
}

/// One incremental text fragment from the model. Concatenate as they arrive.
///
/// Emitted when the session was configured with `responseModalities`
/// containing `'TEXT'`, or when the model produces a transcript of the
/// audio it just spoke.
final class GeminiTextDelta extends GeminiRealtimeEvent {
  final String text;
  const GeminiTextDelta(this.text);

  @override
  String toString() => 'GeminiTextDelta(${text.length} chars)';
}

/// The model finished its current turn. After this event it expects more
/// input from the user before producing more output.
final class GeminiTurnComplete extends GeminiRealtimeEvent {
  const GeminiTurnComplete();

  @override
  String toString() => 'GeminiTurnComplete()';
}

/// The model's pending output was interrupted (because the user started
/// speaking again — server-side VAD, or an explicit `cancel`). Speakers
/// should stop draining queued audio.
final class GeminiInterrupted extends GeminiRealtimeEvent {
  const GeminiInterrupted();

  @override
  String toString() => 'GeminiInterrupted()';
}

/// The server accepted the initial setup message. Until this fires, the
/// client buffers inbound audio rather than sending it; this prevents
/// dropped first words on slow links.
final class GeminiSetupComplete extends GeminiRealtimeEvent {
  const GeminiSetupComplete();

  @override
  String toString() => 'GeminiSetupComplete()';
}

/// A non-fatal error. The connection stays open. Fatal errors close the
/// stream with `addError` instead.
final class GeminiRealtimeError extends GeminiRealtimeEvent {
  final String message;
  final String? code;
  const GeminiRealtimeError(this.message, {this.code});

  @override
  String toString() => 'GeminiRealtimeError($code: $message)';
}
