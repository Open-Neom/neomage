import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/utils/git/git_diff_utils.dart';

void main() {
  group('normalizeGitRemoteUrl', () {
    test('SSH form: git@github.com:owner/repo.git', () {
      expect(
        normalizeGitRemoteUrl('git@github.com:Open-Neom/neomage.git'),
        'github.com/open-neom/neomage',
      );
    });

    test('SSH form without .git suffix', () {
      expect(
        normalizeGitRemoteUrl('git@github.com:Open-Neom/neomage'),
        'github.com/open-neom/neomage',
      );
    });

    test('HTTPS form normalized to host/path lowercase', () {
      expect(
        normalizeGitRemoteUrl('https://github.com/Open-Neom/neomage.git'),
        'github.com/open-neom/neomage',
      );
    });

    test('HTTPS with embedded credentials strips them', () {
      expect(
        normalizeGitRemoteUrl('https://user:tok@github.com/o/r.git'),
        'github.com/o/r',
      );
    });

    test('SSH protocol form ssh://git@host/owner/repo.git', () {
      expect(
        normalizeGitRemoteUrl('ssh://git@github.com/o/r.git'),
        'github.com/o/r',
      );
    });

    test('empty / whitespace -> null', () {
      expect(normalizeGitRemoteUrl(''), isNull);
      expect(normalizeGitRemoteUrl('   '), isNull);
    });

    test('garbage input -> null', () {
      expect(normalizeGitRemoteUrl('not a url at all'), isNull);
    });
  });

  group('parseGitNumstat', () {
    test('parses standard 3-column lines', () {
      const input = '10\t2\tlib/foo.dart\n5\t0\tlib/bar.dart';
      final r = parseGitNumstat(input);
      expect(r.stats.filesCount, 2);
      expect(r.stats.linesAdded, 15);
      expect(r.stats.linesRemoved, 2);
      expect(r.perFileStats['lib/foo.dart']!.added, 10);
      expect(r.perFileStats['lib/bar.dart']!.removed, 0);
    });

    test('treats - - as binary file', () {
      const input = '-\t-\timages/logo.png';
      final r = parseGitNumstat(input);
      expect(r.stats.filesCount, 1);
      expect(r.stats.linesAdded, 0);
      expect(r.stats.linesRemoved, 0);
      expect(r.perFileStats['images/logo.png']!.isBinary, isTrue);
    });

    test('skips malformed lines (less than 3 fields)', () {
      const input = '10\tlib/onlytwo.dart\n5\t1\tlib/good.dart';
      final r = parseGitNumstat(input);
      expect(r.stats.filesCount, 1);
      expect(r.perFileStats.containsKey('lib/good.dart'), isTrue);
    });

    test('handles file paths containing tabs', () {
      // Path joined back with tab
      const input = '3\t1\tpath\twith\ttabs.dart';
      final r = parseGitNumstat(input);
      expect(r.perFileStats.containsKey('path\twith\ttabs.dart'), isTrue);
    });

    test('empty input -> zero stats, empty map', () {
      final r = parseGitNumstat('');
      expect(r.stats.filesCount, 0);
      expect(r.stats.linesAdded, 0);
      expect(r.perFileStats, isEmpty);
    });

    test('non-numeric counts default to 0', () {
      const input = 'foo\tbar\tweird.txt';
      final r = parseGitNumstat(input);
      expect(r.stats.linesAdded, 0);
      expect(r.stats.linesRemoved, 0);
    });
  });

  group('parseShortstat', () {
    test('full shortstat line', () {
      final s = parseShortstat(' 3 files changed, 12 insertions(+), 5 deletions(-)');
      expect(s, isNotNull);
      expect(s!.filesCount, 3);
      expect(s.linesAdded, 12);
      expect(s.linesRemoved, 5);
    });

    test('insertions only (no deletions)', () {
      final s = parseShortstat(' 1 file changed, 7 insertions(+)');
      expect(s, isNotNull);
      expect(s!.linesAdded, 7);
      expect(s.linesRemoved, 0);
    });

    test('deletions only', () {
      final s = parseShortstat(' 1 file changed, 4 deletions(-)');
      expect(s, isNotNull);
      expect(s!.linesAdded, 0);
      expect(s.linesRemoved, 4);
    });

    test('no match -> null', () {
      expect(parseShortstat('nothing here'), isNull);
      expect(parseShortstat(''), isNull);
    });
  });

  group('parseGitDiff', () {
    test('parses a single hunk for a single file', () {
      const diff = '''
diff --git a/foo.dart b/foo.dart
index abc..def 100644
--- a/foo.dart
+++ b/foo.dart
@@ -1,3 +1,4 @@
 line1
-old
+new
+added
 line3
''';
      final result = parseGitDiff(diff);
      expect(result.containsKey('foo.dart'), isTrue);
      final hunks = result['foo.dart']!;
      expect(hunks, hasLength(1));
      expect(hunks.first.oldStart, 1);
      expect(hunks.first.newStart, 1);
      expect(hunks.first.lines, contains('-old'));
      expect(hunks.first.lines, contains('+new'));
      expect(hunks.first.lines, contains('+added'));
    });

    test('handles multiple files', () {
      const diff = '''
diff --git a/a.dart b/a.dart
--- a/a.dart
+++ b/a.dart
@@ -1,1 +1,2 @@
 a
+b
diff --git a/c.dart b/c.dart
--- a/c.dart
+++ b/c.dart
@@ -10,1 +10,1 @@
-x
+y
''';
      final result = parseGitDiff(diff);
      expect(result.keys, containsAll(['a.dart', 'c.dart']));
    });

    test('empty input -> empty map', () {
      expect(parseGitDiff(''), isEmpty);
      expect(parseGitDiff('   '), isEmpty);
    });

    test('binary file diffs are skipped (no hunks)', () {
      const diff = '''
diff --git a/img.png b/img.png
index abc..def 100644
Binary files a/img.png and b/img.png differ
''';
      final result = parseGitDiff(diff);
      expect(result['img.png'], anyOf(isNull, isEmpty));
    });
  });

  group('parseGitRemote', () {
    test('SSH form parses host/owner/repo', () {
      final r = parseGitRemote('git@github.com:foo/bar.git');
      expect(r, isNotNull);
      expect(r!.host, 'github.com');
      expect(r.owner, 'foo');
      expect(r.name, 'bar');
    });

    test('HTTPS form parses host/owner/repo', () {
      final r = parseGitRemote('https://github.com/foo/bar.git');
      expect(r, isNotNull);
      expect(r!.host, 'github.com');
      expect(r.owner, 'foo');
      expect(r.name, 'bar');
    });

    test('rejects hosts without a TLD', () {
      expect(parseGitRemote('git@localhost:foo/bar.git'), isNull);
      expect(parseGitRemote('https://internal/foo/bar.git'), isNull);
    });

    test('rejects garbage', () {
      expect(parseGitRemote(''), isNull);
      expect(parseGitRemote('asdf'), isNull);
    });

    test('preserves port for https hosts', () {
      final r = parseGitRemote('https://gitlab.example.com:8443/o/r.git');
      expect(r, isNotNull);
      expect(r!.host, contains('8443'));
    });
  });

  group('parseGitHubRepository', () {
    test('plain owner/repo form', () {
      expect(parseGitHubRepository('foo/bar'), 'foo/bar');
    });

    test('owner/repo.git is stripped', () {
      expect(parseGitHubRepository('foo/bar.git'), 'foo/bar');
    });

    test('full GitHub HTTPS URL', () {
      expect(
        parseGitHubRepository('https://github.com/foo/bar.git'),
        'foo/bar',
      );
    });

    test('non-github host returns null', () {
      expect(
        parseGitHubRepository('https://gitlab.com/foo/bar.git'),
        isNull,
      );
    });

    test('garbage returns null', () {
      expect(parseGitHubRepository(''), isNull);
      expect(parseGitHubRepository('foo'), isNull);
      expect(parseGitHubRepository('foo/bar/baz'), isNull);
    });
  });

  group('deriveReviewState', () {
    test('draft trumps everything', () {
      expect(
        deriveReviewState(isDraft: true, reviewDecision: 'APPROVED'),
        PrReviewState.draft,
      );
    });

    test('APPROVED maps to approved', () {
      expect(
        deriveReviewState(isDraft: false, reviewDecision: 'APPROVED'),
        PrReviewState.approved,
      );
    });

    test('CHANGES_REQUESTED maps to changesRequested', () {
      expect(
        deriveReviewState(
          isDraft: false,
          reviewDecision: 'CHANGES_REQUESTED',
        ),
        PrReviewState.changesRequested,
      );
    });

    test('unknown decision maps to pending', () {
      expect(
        deriveReviewState(isDraft: false, reviewDecision: ''),
        PrReviewState.pending,
      );
      expect(
        deriveReviewState(isDraft: false, reviewDecision: 'NEUTRAL'),
        PrReviewState.pending,
      );
    });
  });
}
