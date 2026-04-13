import '../models/normalized_message.dart';

/// Abstract interface for normalizing provider-specific AI response formats
/// into a unified [NormalizedMessage].
abstract class MessageNormalizerService {
  /// Normalizes a raw [providerResponse] map from the given [provider] into
  /// a [NormalizedMessage].
  ///
  /// Supported providers: 'anthropic', 'openai', 'gemini'.
  /// Unknown providers fall back to plain text extraction.
  NormalizedMessage normalize(
    Map<String, dynamic> providerResponse,
    String provider,
  );
}
