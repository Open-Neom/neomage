// Tests for model_catalog.dart — aliases, fallback chains, provider IDs,
// allowlist enforcement, cost math, deprecated remapping.

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/utils/model/model_catalog.dart';

void main() {
  group('resolveModel', () {
    test('direct ID hits registry', () {
      expect(resolveModel('claude-opus-4-6')?.id, 'claude-opus-4-6');
    });
    test('alias "opus" → opus-4-6', () {
      expect(resolveModel('opus')?.id, 'claude-opus-4-6');
    });
    test('alias "fast" → haiku', () {
      expect(resolveModel('fast')?.id, 'claude-haiku-3-5');
    });
    test('case + whitespace insensitive', () {
      expect(resolveModel('  OPUS  ')?.id, 'claude-opus-4-6');
    });
    test('provider-specific ID resolves', () {
      // bedrock id
      expect(
        resolveModel('us.anthropic.claude-opus-4-6-v1:0')?.id,
        'claude-opus-4-6',
      );
    });
    test('partial display name resolves', () {
      expect(resolveModel('sonnet 4.5'), isNotNull);
    });
    test('totally unknown returns null', () {
      expect(resolveModel('no-such-model-42'), isNull);
    });
    test('empty string matches first registry entry via partial match', () {
      // Known quirk: `entry.key.contains('')` is always true so empty string
      // falls through to the first registry entry. Documented here so the
      // behavior cannot silently change.
      expect(resolveModel(''), isNotNull);
    });
  });

  group('getModelDisplayName', () {
    test('known model returns catalog display name', () {
      expect(getModelDisplayName('claude-opus-4-6'), 'Opus 4.6');
    });
    test('unknown model returns title-cased fallback', () {
      expect(getModelDisplayName('custom-model'), 'Custom Model');
    });
    test('prefix stripped for claude-*', () {
      expect(getModelDisplayName('claude-foo-bar'), 'Foo Bar');
    });
  });

  group('calculateCost', () {
    test('zero usage = zero cost', () {
      expect(calculateCost('claude-opus-4-6', const TokenUsage()), 0.0);
    });

    test('unknown model returns 0.0 (graceful)', () {
      expect(
        calculateCost('fake', const TokenUsage(inputTokens: 100000)),
        0.0,
      );
    });

    test('1M input tokens = inputPerMillion', () {
      final c = calculateCost(
        'claude-sonnet-4-6',
        const TokenUsage(inputTokens: 1000000),
      );
      expect(c, closeTo(3.0, 0.0001));
    });

    test('cache-read tokens use cache rate, not input rate', () {
      final normal = calculateCost(
        'claude-sonnet-4-6',
        const TokenUsage(inputTokens: 1000000),
      );
      final cached = calculateCost(
        'claude-sonnet-4-6',
        const TokenUsage(cacheReadTokens: 1000000),
      );
      expect(cached, lessThan(normal));
      // cacheRead should be 0.30 vs 3.0
      expect(cached, closeTo(0.30, 0.0001));
    });
  });

  group('TokenUsage + operator', () {
    test('sums all four counters', () {
      const a = TokenUsage(
        inputTokens: 1,
        outputTokens: 2,
        cacheCreationTokens: 3,
        cacheReadTokens: 4,
      );
      const b = TokenUsage(
        inputTokens: 10,
        outputTokens: 20,
        cacheCreationTokens: 30,
        cacheReadTokens: 40,
      );
      final s = a + b;
      expect(s.inputTokens, 11);
      expect(s.outputTokens, 22);
      expect(s.totalTokens, 11 + 22 + 33 + 44);
    });
  });

  group('formatCost', () {
    test('tiny uses 4 decimals', () {
      expect(formatCost(0.0001), r'$0.0001');
    });
    test('medium uses 3 decimals', () {
      expect(formatCost(0.5), r'$0.500');
    });
    test('large uses 2 decimals', () {
      expect(formatCost(12.345), r'$12.35');
    });
  });

  group('getDefaultModel', () {
    test('env ANTHROPIC_MODEL wins', () {
      final m = getDefaultModel(environment: {'ANTHROPIC_MODEL': 'foo'});
      expect(m, 'foo');
    });
    test('env fallback chain: MAGE_MODEL used if ANTHROPIC missing', () {
      final m = getDefaultModel(environment: {'MAGE_MODEL': 'mage'});
      expect(m, 'mage');
    });
    test('settings used when no env', () {
      final m = getDefaultModel(settings: {'model': 'settings-model'});
      expect(m, 'settings-model');
    });
    test('absolute default when nothing provided', () {
      expect(getDefaultModel(), 'claude-sonnet-4-6');
    });
    test('env takes precedence over settings', () {
      final m = getDefaultModel(
        environment: {'ANTHROPIC_MODEL': 'from-env'},
        settings: {'model': 'from-settings'},
      );
      expect(m, 'from-env');
    });
  });

  group('isModelAllowed', () {
    test('null allowlist = allowed', () {
      expect(isModelAllowed('claude-opus-4-6', null), isTrue);
    });
    test('empty allowlist = allowed (fallback)', () {
      expect(isModelAllowed('claude-opus-4-6', []), isTrue);
    });
    test('exact ID in allowlist', () {
      expect(
        isModelAllowed('claude-opus-4-6', ['claude-opus-4-6']),
        isTrue,
      );
    });
    test('family alias "opus" permits any opus model', () {
      expect(isModelAllowed('claude-opus-4-6', ['opus']), isTrue);
    });
    test('family alias "haiku" rejects sonnet', () {
      expect(isModelAllowed('claude-sonnet-4-6', ['haiku']), isFalse);
    });
    test('provider ID in allowlist matches canonical', () {
      expect(
        isModelAllowed(
          'claude-opus-4-6',
          ['us.anthropic.claude-opus-4-6-v1:0'],
        ),
        isTrue,
      );
    });
    test('unknown model → false', () {
      expect(isModelAllowed('non-existent', ['opus']), isFalse);
    });
  });

  group('remapDeprecatedModel', () {
    test('claude-3-opus → opus-4-6', () {
      expect(remapDeprecatedModel('claude-3-opus'), 'claude-opus-4-6');
    });
    test('claude-3-5-sonnet → sonnet-4-6', () {
      expect(remapDeprecatedModel('claude-3-5-sonnet'), 'claude-sonnet-4-6');
    });
    test('non-deprecated passes through', () {
      expect(remapDeprecatedModel('claude-opus-4-6'), 'claude-opus-4-6');
    });
    test('dated deprecated also remaps', () {
      expect(
        remapDeprecatedModel('claude-3-opus-20240229'),
        'claude-opus-4-6',
      );
    });
  });

  group('getProviderModelId', () {
    test('returns configured provider id', () {
      final c = resolveModel('claude-opus-4-6')!;
      expect(
        getProviderModelId(c, ModelProvider.bedrock),
        'us.anthropic.claude-opus-4-6-v1:0',
      );
    });
    test('returns null when provider not mapped', () {
      final c = resolveModel('gpt-4o')!;
      expect(getProviderModelId(c, ModelProvider.bedrock), isNull);
    });
  });
}
