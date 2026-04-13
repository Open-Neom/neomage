// Tests for errors.dart + retry.dart — classification, retry decisions,
// backoff math, Retry-After parsing.

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/data/api/errors.dart';
import 'package:neomage/data/api/retry.dart';

void main() {
  group('classifyApiError', () {
    test('429 → rateLimited with retry-after', () {
      final e = classifyApiError(
        statusCode: 429,
        body: 'slow down',
        retryAfterHeader: '10',
      );
      expect(e.type, ApiErrorType.rateLimited);
      expect(e.retryAfter, '10');
      expect(e.isRetryable, isTrue);
    });

    test('529 → overloaded and retryable', () {
      expect(
        classifyApiError(statusCode: 529, body: '').type,
        ApiErrorType.overloaded,
      );
    });

    test('401 → auth (not retryable)', () {
      final e = classifyApiError(statusCode: 401, body: '');
      expect(e.type, ApiErrorType.authenticationError);
      expect(e.isRetryable, isFalse);
      expect(e.isAuthError, isTrue);
    });

    test('403 → permissionDenied', () {
      expect(
        classifyApiError(statusCode: 403, body: '').type,
        ApiErrorType.permissionDenied,
      );
    });

    test('400 with "prompt is too long" → promptTooLong', () {
      final e = classifyApiError(
        statusCode: 400,
        body: 'error: prompt is too long, 123 tokens too long',
      );
      expect(e.type, ApiErrorType.promptTooLong);
      expect(e.tokenGap, 123);
    });

    test('400 with image/pdf size → mediaTooLarge', () {
      final e =
          classifyApiError(statusCode: 400, body: 'image size exceeds limit');
      expect(e.type, ApiErrorType.mediaTooLarge);
    });

    test('400 with tool_use → invalidToolUse', () {
      final e = classifyApiError(
        statusCode: 400,
        body: 'malformed tool_use parameter',
      );
      expect(e.type, ApiErrorType.invalidToolUse);
    });

    test('500 → serverError (retryable)', () {
      final e = classifyApiError(statusCode: 500, body: '');
      expect(e.type, ApiErrorType.serverError);
      expect(e.isRetryable, isTrue);
    });

    test('418 (unknown) → unknown (not retryable)', () {
      final e = classifyApiError(statusCode: 418, body: "I'm a teapot");
      expect(e.type, ApiErrorType.unknown);
      expect(e.isRetryable, isFalse);
    });
  });

  group('classifyException', () {
    test('timeout message → connectionTimeout', () {
      expect(
        classifyException(Exception('operation timed out')).type,
        ApiErrorType.connectionTimeout,
      );
    });
    test('ECONNRESET → connectionReset', () {
      expect(
        classifyException(Exception('ECONNRESET')).type,
        ApiErrorType.connectionReset,
      );
    });
    test('SSL → sslError', () {
      expect(
        classifyException(Exception('SSL certificate problem')).type,
        ApiErrorType.sslError,
      );
    });
    test('arbitrary text → unknown', () {
      expect(
        classifyException('random').type,
        ApiErrorType.unknown,
      );
    });
  });

  group('getAssistantMessageFromError', () {
    test('promptTooLong gets user-friendly text', () {
      final msg = getAssistantMessageFromError(const ApiError(
        type: ApiErrorType.promptTooLong,
        message: '',
      ));
      expect(msg.toLowerCase(), contains('context window'));
    });
    test('rateLimited mentions wait', () {
      final msg = getAssistantMessageFromError(const ApiError(
        type: ApiErrorType.rateLimited,
        message: '',
      ));
      expect(msg.toLowerCase(), contains('wait'));
    });
  });

  group('calculateRetryDelay', () {
    const cfg = RetryConfig();

    test('honors integer Retry-After header (seconds)', () {
      final d = calculateRetryDelay(
        attempt: 0,
        config: cfg,
        retryAfterHeader: '5',
      );
      expect(d.inSeconds, 5);
    });

    test('negative/zero Retry-After falls through to backoff', () {
      final d = calculateRetryDelay(
        attempt: 0,
        config: cfg,
        retryAfterHeader: '0',
      );
      // Should not be 0 seconds — falls through to exponential backoff.
      expect(d.inMilliseconds, greaterThan(0));
    });

    test('clamps at maxDelayMs', () {
      final d = calculateRetryDelay(attempt: 20, config: cfg);
      expect(d.inMilliseconds, lessThanOrEqualTo(cfg.maxDelayMs));
    });

    test('baseDelay is floor for small attempts', () {
      final d = calculateRetryDelay(attempt: 0, config: cfg);
      expect(d.inMilliseconds, greaterThanOrEqualTo(cfg.baseDelayMs));
    });

    test('delay grows with attempts', () {
      // Run many trials to defeat jitter randomness — check median.
      int early = 0;
      int late = 0;
      for (var i = 0; i < 20; i++) {
        early += calculateRetryDelay(attempt: 1, config: cfg).inMilliseconds;
        late += calculateRetryDelay(attempt: 4, config: cfg).inMilliseconds;
      }
      expect(late, greaterThan(early));
    });
  });

  group('shouldRetry', () {
    test('non-retryable error aborts immediately', () {
      final ctx = RetryContext();
      final dec = shouldRetry(
        error: const ApiError(
          type: ApiErrorType.authenticationError,
          message: 'bad key',
        ),
        context: ctx,
        config: const RetryConfig(),
      );
      expect(dec.shouldRetry, isFalse);
      expect(dec.abortReason, contains('bad key'));
    });

    test('529 past max529Retries aborts', () {
      final ctx = RetryContext();
      const cfg = RetryConfig(max529Retries: 2);
      for (var i = 0; i < 3; i++) {
        shouldRetry(
          error: const ApiError(
            type: ApiErrorType.overloaded,
            message: 'overloaded',
          ),
          context: ctx,
          config: cfg,
        );
      }
      final dec = shouldRetry(
        error: const ApiError(
          type: ApiErrorType.overloaded,
          message: 'overloaded',
        ),
        context: ctx,
        config: cfg,
      );
      expect(dec.shouldRetry, isFalse);
      expect(dec.abortReason, contains('529'));
    });

    test('non-529 resets consecutive529s counter', () {
      final ctx = RetryContext();
      const cfg = RetryConfig(max529Retries: 1);
      // One 529
      shouldRetry(
        error: const ApiError(
          type: ApiErrorType.overloaded,
          message: '',
        ),
        context: ctx,
        config: cfg,
      );
      // Then a timeout: resets counter.
      shouldRetry(
        error: const ApiError(
          type: ApiErrorType.connectionTimeout,
          message: '',
        ),
        context: ctx,
        config: cfg,
      );
      expect(ctx.consecutive529s, 0);
    });

    test('exceeding maxRetries aborts', () {
      final ctx = RetryContext()..attempt = 10;
      const cfg = RetryConfig(maxRetries: 10);
      final dec = shouldRetry(
        error: const ApiError(
          type: ApiErrorType.serverError,
          message: '',
        ),
        context: ctx,
        config: cfg,
      );
      expect(dec.shouldRetry, isFalse);
    });

    test('retryable + under cap returns retry with delay', () {
      final ctx = RetryContext();
      final dec = shouldRetry(
        error: const ApiError(
          type: ApiErrorType.connectionTimeout,
          message: '',
        ),
        context: ctx,
        config: const RetryConfig(),
      );
      expect(dec.shouldRetry, isTrue);
      expect(dec.delay, isNotNull);
    });
  });
}
