// API error classification — ported from NeomClaw src/services/api/errors.ts.

/// Classified API error types.
enum ApiErrorType {
  /// 429 Too Many Requests
  rateLimited,

  /// 529 Overloaded
  overloaded,

  /// 401 Unauthorized
  authenticationError,

  /// 403 Forbidden
  permissionDenied,

  /// Prompt exceeds model's context window
  promptTooLong,

  /// Image or PDF exceeds size limits
  mediaTooLarge,

  /// Invalid tool use parameters
  invalidToolUse,

  /// Tool use mismatch (model vs available tools)
  toolUseMismatch,

  /// Content refused by safety policy
  contentRefused,

  /// Connection timeout
  connectionTimeout,

  /// SSL/TLS certificate error
  sslError,

  /// Connection reset by peer
  connectionReset,

  /// Server error (5xx)
  serverError,

  /// Invalid request (400)
  invalidRequest,

  /// Unknown/unclassified error
  unknown,
}

/// Error messages shown to users.
const String repeated529ErrorMessage = 'Repeated 529 Overloaded errors';
const String apiTimeoutErrorMessage = 'Request timed out';
const String promptTooLongErrorMessage = 'Prompt is too long';

/// A classified API error with context.
class ApiError {
  /// The classified error category.
  final ApiErrorType type;

  /// Human-readable error description.
  final String message;

  /// HTTP status code, if applicable.
  final int? statusCode;

  /// Value of the Retry-After header, if present.
  final String? retryAfter;

  /// Number of tokens exceeding the context window (for promptTooLong errors).
  final int? tokenGap;

  /// The raw error payload from the API response.
  final Map<String, dynamic>? rawError;

  const ApiError({
    required this.type,
    required this.message,
    this.statusCode,
    this.retryAfter,
    this.tokenGap,
    this.rawError,
  });

  /// Whether this error type is safe to retry automatically.
  bool get isRetryable => switch (type) {
    ApiErrorType.rateLimited => true,
    ApiErrorType.overloaded => true,
    ApiErrorType.connectionTimeout => true,
    ApiErrorType.connectionReset => true,
    ApiErrorType.serverError => true,
    _ => false,
  };

  /// Whether this is an authentication or authorization error.
  bool get isAuthError =>
      type == ApiErrorType.authenticationError ||
      type == ApiErrorType.permissionDenied;

  @override
  String toString() => 'ApiError($type: $message)';
}

/// Classify an HTTP error response into an [ApiError].
ApiError classifyApiError({
  required int statusCode,
  required String body,
  String? retryAfterHeader,
}) {
  // Rate limit
  if (statusCode == 429) {
    return ApiError(
      type: ApiErrorType.rateLimited,
      message: 'Rate limited. Please wait before retrying.',
      statusCode: statusCode,
      retryAfter: retryAfterHeader,
    );
  }

  // Overloaded
  if (statusCode == 529) {
    return ApiError(
      type: ApiErrorType.overloaded,
      message: 'API is overloaded. Retrying...',
      statusCode: statusCode,
      retryAfter: retryAfterHeader,
    );
  }

  // Auth
  if (statusCode == 401) {
    return ApiError(
      type: ApiErrorType.authenticationError,
      message: 'Invalid API key or authentication failed.',
      statusCode: statusCode,
    );
  }

  if (statusCode == 403) {
    return ApiError(
      type: ApiErrorType.permissionDenied,
      message: 'Permission denied. Check your API key permissions.',
      statusCode: statusCode,
    );
  }

  // Bad request — check for specific sub-types
  if (statusCode == 400) {
    final lowerBody = body.toLowerCase();

    // Prompt too long
    if (lowerBody.contains('prompt is too long') ||
        lowerBody.contains('max_tokens') && lowerBody.contains('exceed')) {
      final tokenGap = _parseTokenGap(body);
      return ApiError(
        type: ApiErrorType.promptTooLong,
        message: promptTooLongErrorMessage,
        statusCode: statusCode,
        tokenGap: tokenGap,
      );
    }

    // Media size errors
    if (lowerBody.contains('image') && lowerBody.contains('size') ||
        lowerBody.contains('pdf') && lowerBody.contains('size')) {
      return ApiError(
        type: ApiErrorType.mediaTooLarge,
        message: 'Image or PDF exceeds size limits.',
        statusCode: statusCode,
      );
    }

    // Tool use errors
    if (lowerBody.contains('tool_use') || lowerBody.contains('tool use')) {
      return ApiError(
        type: ApiErrorType.invalidToolUse,
        message: 'Invalid tool use parameters.',
        statusCode: statusCode,
      );
    }

    return ApiError(
      type: ApiErrorType.invalidRequest,
      message: 'Invalid request: $body',
      statusCode: statusCode,
    );
  }

  // Server errors
  if (statusCode >= 500) {
    return ApiError(
      type: ApiErrorType.serverError,
      message: 'Server error ($statusCode). Retrying...',
      statusCode: statusCode,
    );
  }

  return ApiError(
    type: ApiErrorType.unknown,
    message: 'Unexpected error ($statusCode): $body',
    statusCode: statusCode,
  );
}

/// Classify an exception (connection error, timeout, etc.) into an [ApiError].
ApiError classifyException(Object error) {
  final msg = error.toString().toLowerCase();

  if (msg.contains('timeout') || msg.contains('timed out')) {
    return ApiError(
      type: ApiErrorType.connectionTimeout,
      message: apiTimeoutErrorMessage,
    );
  }

  if (msg.contains('connection reset') ||
      msg.contains('econnreset') ||
      msg.contains('broken pipe')) {
    return ApiError(
      type: ApiErrorType.connectionReset,
      message: 'Connection reset. Retrying...',
    );
  }

  if (msg.contains('certificate') ||
      msg.contains('ssl') ||
      msg.contains('tls')) {
    return ApiError(
      type: ApiErrorType.sslError,
      message: 'SSL/TLS certificate error.',
    );
  }

  return ApiError(type: ApiErrorType.unknown, message: error.toString());
}

/// Parse token gap from "prompt is too long" error messages.
int? _parseTokenGap(String body) {
  // Pattern: "...N tokens too long..." or "...exceeds N..."
  final match = RegExp(r'(\d+)\s*tokens?\s*too\s*long').firstMatch(body);
  if (match != null) {
    return int.tryParse(match.group(1)!);
  }
  return null;
}

/// Convert an API error to an assistant-facing message.
String getAssistantMessageFromError(ApiError error) => switch (error.type) {
  ApiErrorType.rateLimited =>
    'I was rate limited. Please wait a moment before sending another message.',
  ApiErrorType.overloaded =>
    'The API is currently overloaded. Please try again in a moment.',
  ApiErrorType.authenticationError =>
    'Authentication failed. Please check your API key in settings.',
  ApiErrorType.permissionDenied =>
    'Permission denied. Your API key may not have access to this model.',
  ApiErrorType.promptTooLong =>
    'The conversation is too long for this model. Try clearing the conversation or using a model with a larger context window.',
  ApiErrorType.mediaTooLarge =>
    'An image or PDF in the conversation exceeds the size limit.',
  ApiErrorType.contentRefused =>
    'The request was refused by the safety system.',
  _ => 'An error occurred: ${error.message}',
};
