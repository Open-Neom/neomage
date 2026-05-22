// Tests for encoding_utils.dart — XML escape/unescape, truncate, sanitize,
// bytes formatter, hash stability, token estimators, markdown detection.

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/utils/encoding_utils.dart' as enc;

void main() {
  group('estimateTokens', () {
    test('empty → 0 (ceil(0/4))', () {
      expect(enc.estimateTokens(''), 0);
    });
    test('1 char → 1', () {
      expect(enc.estimateTokens('a'), 1);
    });
    test('4 chars → 1', () {
      expect(enc.estimateTokens('abcd'), 1);
    });
    test('5 chars → 2', () {
      expect(enc.estimateTokens('abcde'), 2);
    });
  });

  group('estimateMessageTokens', () {
    test('empty list → 0', () {
      expect(enc.estimateMessageTokens([]), 0);
    });

    test('plain string content counts', () {
      final n = enc.estimateMessageTokens([
        {'role': 'user', 'content': 'abcd'}, // 1 token + 4 overhead
      ]);
      expect(n, 5);
    });

    test('tool_use content block is serialized and counted', () {
      final n = enc.estimateMessageTokens([
        {
          'role': 'assistant',
          'content': [
            {
              'type': 'tool_use',
              'input': {'command': 'ls -la'},
            }
          ]
        }
      ]);
      expect(n, greaterThan(4));
    });

    test('tool_result content block counts text', () {
      final n = enc.estimateMessageTokens([
        {
          'role': 'tool',
          'content': [
            {'type': 'tool_result', 'content': 'output text'}
          ]
        }
      ]);
      expect(n, greaterThan(4));
    });

    test('unknown block type ignored but overhead still added', () {
      final n = enc.estimateMessageTokens([
        {
          'role': 'assistant',
          'content': [
            {'type': 'surprise'}
          ]
        }
      ]);
      expect(n, 4);
    });
  });

  group('escapeXml / unescapeXml', () {
    test('round-trip preserves content', () {
      const raw = 'a & b <c> "d" \'e\'';
      expect(enc.unescapeXml(enc.escapeXml(raw)), raw);
    });
    test('escapes in correct order (& first)', () {
      final out = enc.escapeXml('A & <b>');
      expect(out, contains('&amp;'));
      expect(out, contains('&lt;'));
    });
    test('prompt injection tag is neutered', () {
      final out = enc.escapeXml('</system>');
      expect(out, isNot(contains('</system>')));
    });
  });

  group('truncate', () {
    test('no truncation under limit', () {
      expect(enc.truncate('hi', 100), 'hi');
    });
    test('exact length unchanged', () {
      expect(enc.truncate('abcde', 5), 'abcde');
    });
    test('truncates with ellipsis', () {
      expect(enc.truncate('abcdefgh', 6), 'abc...');
    });
    test('custom suffix', () {
      expect(enc.truncate('abcdefgh', 6, suffix: '…'), 'abcde…');
    });
  });

  group('truncateLines', () {
    test('no truncation under line limit', () {
      expect(enc.truncateLines('a\nb', 10), 'a\nb');
    });
    test('truncates with suffix', () {
      final out = enc.truncateLines('a\nb\nc\nd\ne', 2);
      expect(out.split('\n').first, 'a');
      expect(out, contains('...'));
    });
  });

  group('xmlTag / parseXmlTag', () {
    test('round-trip extracts content', () {
      final w = enc.xmlTag('note', 'hello');
      expect(enc.parseXmlTag(w, 'note'), 'hello');
    });
    test('missing close tag returns null', () {
      expect(enc.parseXmlTag('<note>hi', 'note'), isNull);
    });
    test('missing open tag returns null', () {
      expect(enc.parseXmlTag('bye</note>', 'note'), isNull);
    });
    test('parseXmlTag nested same tag finds first closing (known limit)', () {
      // Document behavior: inner close is matched.
      final inner = enc.parseXmlTag('<n>a<n>b</n>c</n>', 'n');
      expect(inner, 'a<n>b');
    });
  });

  group('base64Encode / Decode', () {
    test('round-trip', () {
      const s = 'Hello, 世界 🌍';
      expect(enc.base64Decode(enc.base64Encode(s)), s);
    });
  });

  group('sanitizeFilename', () {
    test('removes unsafe chars', () {
      expect(enc.sanitizeFilename('a/b:c?d*.txt'), 'a_b_c_d_.txt');
    });
    test('collapses whitespace', () {
      expect(enc.sanitizeFilename('a  b   c'), 'a_b_c');
    });
    test('strips leading dots', () {
      expect(enc.sanitizeFilename('...hidden'), 'hidden');
    });
    test('deduplicates underscores', () {
      expect(enc.sanitizeFilename('a///b'), 'a_b');
    });
  });

  group('formatBytes', () {
    test('bytes < 1024', () {
      expect(enc.formatBytes(0), '0 B');
      expect(enc.formatBytes(1023), '1023 B');
    });
    test('KB branch', () {
      expect(enc.formatBytes(1024), '1.0 KB');
    });
    test('MB branch', () {
      expect(enc.formatBytes(5 * 1024 * 1024), '5.0 MB');
    });
    test('GB branch', () {
      expect(enc.formatBytes(2 * 1024 * 1024 * 1024), '2.0 GB');
    });
  });

  group('formatDuration', () {
    test('ms branch', () {
      expect(enc.formatDuration(const Duration(milliseconds: 250)), '250ms');
    });
    test('seconds branch', () {
      expect(enc.formatDuration(const Duration(seconds: 5)), '5s');
    });
    test('minutes branch', () {
      expect(enc.formatDuration(const Duration(minutes: 2, seconds: 3)), '2m 3s');
    });
    test('hours branch', () {
      expect(enc.formatDuration(const Duration(hours: 1, minutes: 30)), '1h 30m');
    });
  });

  group('simpleHash', () {
    test('deterministic', () {
      expect(enc.simpleHash('hello'), enc.simpleHash('hello'));
    });
    test('different inputs → different hashes (non-collision sample)', () {
      expect(enc.simpleHash('hello'), isNot(enc.simpleHash('world')));
    });
    test('result is non-negative', () {
      expect(enc.simpleHash('test'), greaterThanOrEqualTo(0));
    });
    test('empty → 0', () {
      expect(enc.simpleHash(''), 0);
    });
  });

  group('containsMarkdown', () {
    test('plain text → false', () {
      expect(enc.containsMarkdown('hello world'), isFalse);
    });
    test('bold text → true', () {
      expect(enc.containsMarkdown('**bold**'), isTrue);
    });
    test('header → true', () {
      expect(enc.containsMarkdown('# title'), isTrue);
    });
    test('list → true', () {
      expect(enc.containsMarkdown('- item'), isTrue);
    });
    test('long string only checks first 500 chars', () {
      // No markdown in first 500 chars, only after → returns false.
      final text = '${'plain text ' * 50}**bold**';
      expect(text.length, greaterThan(500));
      expect(enc.containsMarkdown(text), isFalse);
    });
  });

  group('escapeDiffTokens round-trip', () {
    test('preserves & and \$', () {
      const s = r'$var and & entity';
      expect(enc.unescapeDiffTokens(enc.escapeDiffTokens(s)), s);
    });
  });
}
