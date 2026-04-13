// Tests for token_counter.dart — tokenizer, budget, cost, context window.
//
// Focus: edge cases that break real users — empty strings, huge inputs,
// CJK, emojis, code, off-by-one at budget caps, binary-search truncation,
// chunking with overlap, image/PDF estimators.

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/utils/tokens/token_counter.dart';

void main() {
  group('Cl100kEncoder.count', () {
    final enc = Cl100kEncoder();

    test('empty string returns 0 (not 1)', () {
      expect(enc.count(''), 0);
    });

    test('single char returns at least 1', () {
      expect(enc.count('a'), greaterThanOrEqualTo(1));
    });

    test('whitespace-only counts > 0', () {
      expect(enc.count('   '), greaterThanOrEqualTo(1));
      expect(enc.count('\n\n\n'), greaterThanOrEqualTo(1));
    });

    test('CJK characters count roughly 1 token each', () {
      // 4 hanzi → ~4 tokens (cjk rule: 1 per char).
      final n = enc.count('日本語中');
      expect(n, greaterThanOrEqualTo(4));
    });

    test('mixed CJK + ASCII sums both branches', () {
      final n = enc.count('hello 日本');
      expect(n, greaterThanOrEqualTo(3));
    });

    test('emoji does not crash and returns > 0', () {
      expect(enc.count('🎉🔥💯'), greaterThan(0));
    });

    test('RTL (arabic) counts > 0', () {
      expect(enc.count('مرحبا بالعالم'), greaterThan(0));
    });

    test('very long string scales roughly linearly', () {
      final short = 'hello world ' * 10;
      final long = 'hello world ' * 10000;
      final ratio = enc.count(long) / enc.count(short);
      // Expect ~1000x (give a wide margin).
      expect(ratio, greaterThan(500));
    });

    test('code with brackets takes code path (3 chars/token)', () {
      // 100 semicolons pure punct - exercises code branch.
      final code = 'if (x > 0) { y[i] = !z && ~w; }';
      expect(enc.count(code), greaterThan(0));
    });

    test('encode() length matches count()', () {
      const text = 'The quick brown fox jumps over the lazy dog.';
      expect(enc.encode(text).length, enc.count(text));
    });

    test('encode empty returns empty list', () {
      expect(enc.encode(''), isEmpty);
    });

    test('singleton returns same instance', () {
      expect(identical(Cl100kEncoder(), Cl100kEncoder.instance), isTrue);
    });
  });

  group('TokenBudget', () {
    test('initial state', () {
      final b = TokenBudget(total: 1000);
      expect(b.used, 0);
      expect(b.remaining, 1000);
      expect(b.isExhausted, isFalse);
      expect(b.percentage, 0.0);
    });

    test('reserve succeeds below cap', () {
      final b = TokenBudget(total: 1000);
      expect(b.reserve(500), isTrue);
      expect(b.used, 500);
      expect(b.remaining, 500);
    });

    test('reserve at exact cap succeeds', () {
      final b = TokenBudget(total: 1000);
      expect(b.reserve(1000), isTrue);
      expect(b.isExhausted, isTrue);
    });

    test('reserve over cap fails and does not mutate', () {
      final b = TokenBudget(total: 1000);
      b.reserve(900);
      expect(b.reserve(101), isFalse); // 900+101 > 1000
      expect(b.used, 900); // unchanged
    });

    test('reserve exactly remaining succeeds', () {
      final b = TokenBudget(total: 1000);
      b.reserve(900);
      expect(b.reserve(100), isTrue);
      expect(b.remaining, 0);
    });

    test('release clamps at 0 (does not go negative)', () {
      final b = TokenBudget(total: 1000);
      b.reserve(200);
      b.release(500);
      expect(b.used, 0);
    });

    test('total = 0 means percentage = 100%', () {
      final b = TokenBudget(total: 0);
      expect(b.percentage, 1.0);
      expect(b.remaining, 0);
    });

    test('total = 0 rejects all reservations', () {
      final b = TokenBudget(total: 0);
      expect(b.reserve(1), isFalse);
    });

    test('remaining never negative after over-used construction', () {
      // Not allowed via API but defensively — construct with used > total
      final b = TokenBudget(total: 100, used: 200);
      expect(b.remaining, 0);
      expect(b.isExhausted, isTrue);
    });
  });

  group('ModelPricingTable.forModel', () {
    test('opus path', () {
      expect(ModelPricingTable.forModel('claude-opus-4-20250514').name,
          contains('opus'));
    });
    test('haiku path', () {
      expect(ModelPricingTable.forModel('claude-3-5-haiku-20241022').name,
          contains('haiku'));
    });
    test('gpt-4o-mini matches before gpt-4o', () {
      final p = ModelPricingTable.forModel('gpt-4o-mini');
      expect(p.inputPerMillion, 0.15);
    });
    test('gpt-4o plain', () {
      final p = ModelPricingTable.forModel('gpt-4o');
      expect(p.inputPerMillion, 2.50);
    });
    test('unknown model falls back to sonnet', () {
      expect(ModelPricingTable.forModel('totally-made-up').name,
          contains('sonnet'));
    });
    test('case-insensitive match', () {
      expect(ModelPricingTable.forModel('CLAUDE-OPUS-X').name, contains('opus'));
    });
  });

  group('TokenCounter.countMessageTokens', () {
    final tc = TokenCounter();

    test('empty list still has priming overhead of 3', () {
      expect(tc.countMessageTokens([]), 3);
    });

    test('one message adds 4 overhead + role + content', () {
      final n = tc.countMessageTokens([
        {'role': 'user', 'content': 'hi'},
      ]);
      // 3 priming + 4 overhead + count(role) + count(content)
      expect(n, greaterThanOrEqualTo(3 + 4));
    });

    test('missing role/content does not throw', () {
      expect(() => tc.countMessageTokens([{}]), returnsNormally);
    });

    test('more messages → more tokens (monotonic)', () {
      final one = tc.countMessageTokens([
        {'role': 'user', 'content': 'hi'},
      ]);
      final three = tc.countMessageTokens([
        {'role': 'user', 'content': 'hi'},
        {'role': 'assistant', 'content': 'hi'},
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(three, greaterThan(one));
    });
  });

  group('TokenCounter.countToolUseTokens', () {
    test('includes tool overhead of 20', () {
      final tc = TokenCounter();
      final n = tc.countToolUseTokens('bash', '{"command":"ls"}');
      expect(n, greaterThanOrEqualTo(20));
    });

    test('empty input still includes overhead', () {
      final tc = TokenCounter();
      expect(tc.countToolUseTokens('', ''), 20);
    });
  });

  group('TokenCounter.estimateImageTokens', () {
    final tc = TokenCounter();

    test('low detail is fixed 85', () {
      expect(tc.estimateImageTokens(9999, 9999, detail: 'low'), 85);
    });

    test('tiny image is 170 + 85', () {
      expect(tc.estimateImageTokens(10, 10), 170 * 1 * 1 + 85);
    });

    test('512x512 fits in one tile', () {
      expect(tc.estimateImageTokens(512, 512), 170 + 85);
    });

    test('513x513 crosses tile boundary (2x2 tiles after scaling)', () {
      // Not scaled down (under 2048 and under 768 on shortest? 513>768 false)
      // shortest=513 < 768 so no scaling. 513/512→2 tiles → 2x2=4 tiles.
      expect(tc.estimateImageTokens(513, 513), 170 * 4 + 85);
    });

    test('huge image clamps via 2048 then 768', () {
      final n = tc.estimateImageTokens(5000, 5000);
      // After scaling: longest=2048, then shortest=768 → 768x768 → 2x2 = 4.
      expect(n, 170 * 4 + 85);
    });

    test('zero dim returns base', () {
      expect(tc.estimateImageTokens(0, 0), 85);
    });
  });

  group('TokenCounter.estimatePdfTokens', () {
    test('0 pages = 0', () {
      expect(TokenCounter().estimatePdfTokens(0), 0);
    });
    test('1 page = 1500', () {
      expect(TokenCounter().estimatePdfTokens(1), 1500);
    });
    test('100 pages = 150000', () {
      expect(TokenCounter().estimatePdfTokens(100), 150000);
    });
  });

  group('TokenCounter.truncateToTokens', () {
    final tc = TokenCounter();

    test('text under limit is returned unchanged', () {
      const s = 'hello world';
      expect(tc.truncateToTokens(s, 1000), s);
    });

    test('0 maxTokens returns empty string', () {
      expect(tc.truncateToTokens('hello world', 0), '');
    });

    test('truncation never exceeds maxTokens', () {
      final long = 'word ' * 2000;
      final out = tc.truncateToTokens(long, 50);
      expect(tc.countTokens(out), lessThanOrEqualTo(50));
    });

    test('result is a prefix of the original', () {
      final long = 'alpha beta gamma delta epsilon ' * 200;
      final out = tc.truncateToTokens(long, 30);
      expect(long.startsWith(out), isTrue);
    });
  });

  group('TokenCounter.splitByTokens', () {
    final tc = TokenCounter();

    test('empty returns empty list (not [""])', () {
      expect(tc.splitByTokens('', 100), isEmpty);
    });

    test('chunks concat back to original (no overlap)', () {
      final text = 'The quick brown fox. ' * 40;
      final chunks = tc.splitByTokens(text, 20);
      expect(chunks.join(), text);
    });

    test('each chunk respects size ~cap (small tolerance)', () {
      final text = 'lorem ipsum dolor sit amet ' * 100;
      final chunks = tc.splitByTokens(text, 30);
      for (final c in chunks) {
        // Allow 1.5x slack since the splitter uses proportional heuristics.
        expect(tc.countTokens(c), lessThanOrEqualTo(45));
      }
    });

    test('overlap produces chunks whose joined length > original', () {
      final text = 'alpha beta gamma delta ' * 20;
      final withOverlap = tc.splitByTokens(text, 20, overlap: 5);
      final joined = withOverlap.join();
      expect(joined.length, greaterThanOrEqualTo(text.length));
    });

    test('very small chunk size still terminates (no infinite loop)', () {
      final out = tc.splitByTokens('abcdefghijklmnop', 1);
      expect(out, isNotEmpty);
    });
  });

  group('TokenCounter.estimateCost', () {
    final tc = TokenCounter();

    test('zero usage = zero cost', () {
      final c = tc.estimateCost(0, 0, model: 'claude-sonnet-4-20250514');
      expect(c.totalCost, 0);
    });

    test('cache read discount reduces effective input cost', () {
      final noCache = tc.estimateCost(1000, 0);
      final withCache = tc.estimateCost(1000, 0, cacheRead: 1000);
      expect(withCache.totalCost, lessThan(noCache.totalCost));
    });

    test('formatted shows cents when < 1c', () {
      const c = CostEstimate(inputCost: 0.000001, outputCost: 0, cacheCost: 0);
      expect(c.formatted, endsWith('c'));
    });

    test('formatted shows dollars at >= 1c', () {
      const c = CostEstimate(inputCost: 0.50, outputCost: 0, cacheCost: 0);
      expect(c.formatted, startsWith(r'$0.5'));
    });
  });

  group('ContextWindow', () {
    test('available never negative when used > max', () {
      const cw = ContextWindow(maxInput: 100, maxOutput: 10, used: 200);
      expect(cw.available, 0);
    });

    test('maxInput=0 yields 100% utilization and not div-by-zero', () {
      const cw = ContextWindow(maxInput: 0, maxOutput: 0, used: 0);
      expect(cw.utilizationPercent, 100.0);
    });

    test('withUsed returns copy with same max fields', () {
      const cw = ContextWindow(maxInput: 1000, maxOutput: 100, used: 0);
      final after = cw.withUsed(500);
      expect(after.maxInput, 1000);
      expect(after.used, 500);
      expect(cw.used, 0); // original unchanged
    });
  });

  group('estimateTokens (heuristic top-level)', () {
    test('empty → 1 (min clamp)', () {
      expect(estimateTokens(''), 1);
    });
    test('4 chars → 1', () {
      expect(estimateTokens('abcd'), 1);
    });
    test('5 chars → 2 (ceil)', () {
      expect(estimateTokens('abcde'), 2);
    });
  });
}
