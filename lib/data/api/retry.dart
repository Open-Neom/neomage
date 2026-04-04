// Retry logic with exponential backoff — ported from NeomClaw src/services/api/withRetry.ts.

import 'dart:math';

import 'errors.dart';

/// Retry configuration.
class RetryConfig {
  /// Maximum number of retry attempts.
  final int maxRetries;

  /// Base delay in milliseconds for exponential backoff.
  final int baseDelayMs;

  /// Maximum delay in milliseconds.
  final int maxDelayMs;

  /// Maximum consecutive 529 errors before giving up.
  final int max529Retries;

  /// Whether to retry indefinitely for unattended sessions.
  final bool persistent;

  /// Maximum backoff in milliseconds for persistent retries.
  final int persistentMaxBackoffMs;

  const RetryConfig({
    this.maxRetries = 10,
    this.baseDelayMs = 500,
    this.maxDelayMs = 32000,
    this.max529Retries = 3,
    this.persistent = false,
    this.persistentMaxBackoffMs = 5 * 60 * 1000,
  });

  /// Default retry configuration for interactive sessions.
  static const RetryConfig defaultConfig = RetryConfig();

  /// Conservative retry configuration for background tasks.
  static const RetryConfig backgroundConfig = RetryConfig(
    maxRetries: 3,
    max529Retries: 1,
  );
}

/// Context tracked across retry attempts.
class RetryContext {
  /// Current attempt number (starts at 0).
  int attempt;

  /// Number of consecutive 529 (overloaded) errors.
  int consecutive529s;

  /// Timestamp of the most recent retry.
  DateTime? lastRetry;

  /// Creates a fresh retry context with zero attempts.
  RetryContext() : attempt = 0, consecutive529s = 0;
}

/// Calculate delay for the next retry attempt.
Duration calculateRetryDelay({
  required int attempt,
  required RetryConfig config,
  String? retryAfterHeader,
}) {
  // Respect server's Retry-After header
  if (retryAfterHeader != null) {
    final seconds = int.tryParse(retryAfterHeader);
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    // Try parsing as HTTP date
    final date = DateTime.tryParse(retryAfterHeader);
    if (date != null) {
      final diff = date.difference(DateTime.now());
      if (diff > Duration.zero) return diff;
    }
  }

  // Exponential backoff with jitter
  final random = Random();
  final exponentialMs = (pow(2, attempt) * config.baseDelayMs).toInt();
  final jitterMs = (random.nextDouble() * 0.25 * exponentialMs).toInt();
  final totalMs = exponentialMs + jitterMs;
  final clampedMs = totalMs.clamp(config.baseDelayMs, config.maxDelayMs);

  return Duration(milliseconds: clampedMs);
}

/// Determine whether an error should be retried.
RetryDecision shouldRetry({
  required ApiError error,
  required RetryContext context,
  required RetryConfig config,
}) {
  // Never retry auth or content errors
  if (!error.isRetryable) {
    return RetryDecision.abort(error.message);
  }

  // Check 529 limit
  if (error.type == ApiErrorType.overloaded) {
    context.consecutive529s++;
    if (context.consecutive529s > config.max529Retries && !config.persistent) {
      return RetryDecision.abort(repeated529ErrorMessage);
    }
  } else {
    context.consecutive529s = 0;
  }

  // Check max retries
  if (context.attempt >= config.maxRetries && !config.persistent) {
    return RetryDecision.abort(
      'Max retries (${config.maxRetries}) exceeded: ${error.message}',
    );
  }

  final delay = calculateRetryDelay(
    attempt: context.attempt,
    config: config,
    retryAfterHeader: error.retryAfter,
  );

  return RetryDecision.retry(delay);
}

/// Decision about whether to retry.
class RetryDecision {
  /// Whether the operation should be retried.
  final bool shouldRetry;

  /// How long to wait before retrying (null if aborting).
  final Duration? delay;

  /// Reason for aborting (null if retrying).
  final String? abortReason;

  const RetryDecision._({
    required this.shouldRetry,
    this.delay,
    this.abortReason,
  });

  /// Create a decision to retry after the given [delay].
  factory RetryDecision.retry(Duration delay) =>
      RetryDecision._(shouldRetry: true, delay: delay);

  /// Create a decision to abort with the given [reason].
  factory RetryDecision.abort(String reason) =>
      RetryDecision._(shouldRetry: false, abortReason: reason);
}

/// Execute an operation with retry logic.
///
/// Returns the result of a successful attempt or throws with the last error.
/// [onRetry] is called before each retry with the current attempt number and delay.
Future<T> withRetry<T>({
  required Future<T> Function(int attempt) operation,
  RetryConfig config = RetryConfig.defaultConfig,
  void Function(int attempt, Duration delay, ApiError error)? onRetry,
}) async {
  final context = RetryContext();

  while (true) {
    context.attempt++;
    try {
      return await operation(context.attempt);
    } catch (e) {
      final error = e is ApiError ? e : classifyException(e);
      final decision = shouldRetry(
        error: error,
        context: context,
        config: config,
      );

      if (!decision.shouldRetry) {
        throw ApiError(
          type: error.type,
          message: decision.abortReason ?? error.message,
          statusCode: error.statusCode,
        );
      }

      onRetry?.call(context.attempt, decision.delay!, error);
      await Future.delayed(decision.delay!);
    }
  }
}
