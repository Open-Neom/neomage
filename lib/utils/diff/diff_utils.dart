/// Diff utilities for computing, formatting, and applying text diffs.
///
/// Provides line-level, word-level, and character-level diffing,
/// patch creation/application, and semantic grouping of changes.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// The type of a diff element.
enum DiffType { add, remove, context }

/// Primitive edit operation used by shortest-edit-script.
enum EditOp { insert, delete, equal }

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A single line in a line-level diff.
class LineDiff {
  final int lineNumber;
  final String content;
  final DiffType type;

  const LineDiff({
    required this.lineNumber,
    required this.content,
    required this.type,
  });

  @override
  String toString() {
    final prefix = switch (type) {
      DiffType.add => '+',
      DiffType.remove => '-',
      DiffType.context => ' ',
    };
    return '$prefix$lineNumber: $content';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LineDiff &&
          lineNumber == other.lineNumber &&
          content == other.content &&
          type == other.type;

  @override
  int get hashCode => Object.hash(lineNumber, content, type);
}

/// A word-level diff element.
class WordDiff {
  final String text;
  final DiffType type;

  const WordDiff({required this.text, required this.type});

  @override
  String toString() => '${type.name}:"$text"';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WordDiff && text == other.text && type == other.type;

  @override
  int get hashCode => Object.hash(text, type);
}

/// A character-level diff element.
class CharDiff {
  final String char;
  final DiffType type;

  const CharDiff({required this.char, required this.type});

  @override
  String toString() => '${type.name}:"$char"';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CharDiff && char == other.char && type == other.type;

  @override
  int get hashCode => Object.hash(char, type);
}

/// Summary statistics for a diff.
class DiffStats {
  final int additions;
  final int deletions;
  final int modifications;
  final int unchanged;

  const DiffStats({
    required this.additions,
    required this.deletions,
    required this.modifications,
    required this.unchanged,
  });

  int get totalChanges => additions + deletions + modifications;

  @override
  String toString() => '+$additions -$deletions ~$modifications =$unchanged';
}

// ---------------------------------------------------------------------------
// Patch types
// ---------------------------------------------------------------------------

/// A single hunk in a patch.
class Hunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<LineDiff> lines;

  const Hunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  String get header => '@@ -$oldStart,$oldCount +$newStart,$newCount @@';
}

/// A set of hunks that together describe a transformation.
class PatchSet {
  final List<Hunk> hunks;

  const PatchSet({required this.hunks});

  /// Apply this patch to [text].
  PatchResult apply(String text) => applyPatch(text, this);

  /// Create a reversed patch that undoes this patch.
  PatchSet reverse() {
    final reversed = hunks.map((h) {
      final lines = h.lines.map((l) {
        final newType = switch (l.type) {
          DiffType.add => DiffType.remove,
          DiffType.remove => DiffType.add,
          DiffType.context => DiffType.context,
        };
        return LineDiff(
          lineNumber: l.lineNumber,
          content: l.content,
          type: newType,
        );
      }).toList();
      return Hunk(
        oldStart: h.newStart,
        oldCount: h.newCount,
        newStart: h.oldStart,
        newCount: h.oldCount,
        lines: lines,
      );
    }).toList();
    return PatchSet(hunks: reversed);
  }

  /// Serialize to a string representation.
  String serialize() => formatPatch(this);

  /// Deserialize from a unified diff string.
  static PatchSet deserialize(String text) => _parsePatch(text);
}

/// Result of applying a patch.
class PatchResult {
  final String text;
  final List<Hunk> appliedHunks;
  final List<Hunk> conflictHunks;

  const PatchResult({
    required this.text,
    required this.appliedHunks,
    required this.conflictHunks,
  });

  bool get isClean => conflictHunks.isEmpty;
}

// ---------------------------------------------------------------------------
// Semantic diff
// ---------------------------------------------------------------------------

/// Groups related diff lines into logical change blocks.
class SemanticDiff {
  final List<ChangeBlock> blocks;

  const SemanticDiff({required this.blocks});

  /// Create a semantic diff from raw line diffs.
  factory SemanticDiff.from(List<LineDiff> diffs) {
    final blocks = <ChangeBlock>[];
    var current = <LineDiff>[];

    for (final diff in diffs) {
      if (diff.type == DiffType.context) {
        if (current.isNotEmpty) {
          blocks.add(ChangeBlock(lines: List.unmodifiable(current)));
          current = [];
        }
      } else {
        current.add(diff);
      }
    }
    if (current.isNotEmpty) {
      blocks.add(ChangeBlock(lines: List.unmodifiable(current)));
    }
    return SemanticDiff(blocks: blocks);
  }

  /// Merge adjacent blocks that are within [gapThreshold] context lines.
  SemanticDiff merge({int gapThreshold = 3}) {
    if (blocks.length <= 1) return this;
    final merged = <ChangeBlock>[blocks.first];
    for (var i = 1; i < blocks.length; i++) {
      final prev = merged.last;
      final curr = blocks[i];
      final gap = curr.startLine - prev.endLine;
      if (gap <= gapThreshold) {
        merged[merged.length - 1] = ChangeBlock(
          lines: [...prev.lines, ...curr.lines],
        );
      } else {
        merged.add(curr);
      }
    }
    return SemanticDiff(blocks: merged);
  }

  /// Summary of all blocks.
  String get summary {
    final buf = StringBuffer();
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final adds = b.lines.where((l) => l.type == DiffType.add).length;
      final dels = b.lines.where((l) => l.type == DiffType.remove).length;
      buf.writeln(
        'Block ${i + 1}: +$adds -$dels lines (${b.startLine}-${b.endLine})',
      );
    }
    return buf.toString().trimRight();
  }
}

/// A contiguous block of related changes.
class ChangeBlock {
  final List<LineDiff> lines;

  const ChangeBlock({required this.lines});

  int get startLine => lines.isEmpty ? 0 : lines.first.lineNumber;

  int get endLine => lines.isEmpty ? 0 : lines.last.lineNumber;

  bool get isPureAdd => lines.every((l) => l.type == DiffType.add);
  bool get isPureRemove => lines.every((l) => l.type == DiffType.remove);
  bool get isModification => !isPureAdd && !isPureRemove;
}

// ---------------------------------------------------------------------------
// Core algorithms
// ---------------------------------------------------------------------------

/// Compute the longest common subsequence of two lists.
List<T> longestCommonSubsequence<T>(List<T> a, List<T> b) {
  final m = a.length;
  final n = b.length;
  // DP table
  final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
  for (var i = 1; i <= m; i++) {
    for (var j = 1; j <= n; j++) {
      if (a[i - 1] == b[j - 1]) {
        dp[i][j] = dp[i - 1][j - 1] + 1;
      } else {
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
  }
  // Backtrack
  final result = <T>[];
  var i = m, j = n;
  while (i > 0 && j > 0) {
    if (a[i - 1] == b[j - 1]) {
      result.add(a[i - 1]);
      i--;
      j--;
    } else if (dp[i - 1][j] >= dp[i][j - 1]) {
      i--;
    } else {
      j--;
    }
  }
  return result.reversed.toList();
}

/// Compute the shortest edit script (Myers' algorithm simplified).
List<EditOp> shortestEditScript<T>(List<T> a, List<T> b) {
  final m = a.length;
  final n = b.length;
  final max = m + n;
  if (max == 0) return [];

  // V array indexed from -max to max
  final v = List.filled(2 * max + 1, 0);
  final trace = <List<int>>[];

  int idx(int k) => k + max;

  outer:
  for (var d = 0; d <= max; d++) {
    trace.add(List.of(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[idx(k - 1)] < v[idx(k + 1)])) {
        x = v[idx(k + 1)];
      } else {
        x = v[idx(k - 1)] + 1;
      }
      var y = x - k;
      while (x < m && y < n && a[x] == b[y]) {
        x++;
        y++;
      }
      v[idx(k)] = x;
      if (x >= m && y >= n) break outer;
    }
  }

  // Backtrack through trace to build edit script
  final ops = <EditOp>[];
  var x = m, y = n;
  for (var d = trace.length - 1; d > 0; d--) {
    final prev = trace[d - 1];
    final k = x - y;
    int prevK;
    if (k == -d || (k != d && prev[idx(k - 1)] < prev[idx(k + 1)])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = prev[idx(prevK)];
    final prevY = prevX - prevK;

    // Diagonal moves (equals)
    while (x > prevX && y > prevY) {
      x--;
      y--;
      ops.add(EditOp.equal);
    }
    if (k == prevK + 1) {
      // Deletion
      x--;
      ops.add(EditOp.delete);
    } else {
      // Insertion
      y--;
      ops.add(EditOp.insert);
    }
  }
  // Remaining diagonal
  while (x > 0 && y > 0) {
    x--;
    y--;
    ops.add(EditOp.equal);
  }

  return ops.reversed.toList();
}

// ---------------------------------------------------------------------------
// Line diff
// ---------------------------------------------------------------------------

/// Compute a line-level diff between [oldText] and [newText].
List<LineDiff> computeLineDiff(String oldText, String newText) {
  final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
  final newLines = newText.isEmpty ? <String>[] : newText.split('\n');
  final lcs = longestCommonSubsequence(oldLines, newLines);

  final result = <LineDiff>[];
  var oi = 0, ni = 0, li = 0;

  while (oi < oldLines.length || ni < newLines.length) {
    if (li < lcs.length &&
        oi < oldLines.length &&
        ni < newLines.length &&
        oldLines[oi] == lcs[li] &&
        newLines[ni] == lcs[li]) {
      result.add(
        LineDiff(
          lineNumber: ni + 1,
          content: newLines[ni],
          type: DiffType.context,
        ),
      );
      oi++;
      ni++;
      li++;
    } else if (oi < oldLines.length &&
        (li >= lcs.length || oldLines[oi] != lcs[li])) {
      result.add(
        LineDiff(
          lineNumber: oi + 1,
          content: oldLines[oi],
          type: DiffType.remove,
        ),
      );
      oi++;
    } else if (ni < newLines.length &&
        (li >= lcs.length || newLines[ni] != lcs[li])) {
      result.add(
        LineDiff(lineNumber: ni + 1, content: newLines[ni], type: DiffType.add),
      );
      ni++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Word diff
// ---------------------------------------------------------------------------

/// Tokenize a string into words and whitespace tokens.
List<String> _tokenizeWords(String text) {
  final tokens = <String>[];
  final re = RegExp(r'\S+|\s+');
  for (final m in re.allMatches(text)) {
    tokens.add(m.group(0)!);
  }
  return tokens;
}

/// Compute a word-level diff between [oldLine] and [newLine].
List<WordDiff> computeWordDiff(String oldLine, String newLine) {
  final oldTokens = _tokenizeWords(oldLine);
  final newTokens = _tokenizeWords(newLine);
  final ops = shortestEditScript(oldTokens, newTokens);

  final result = <WordDiff>[];
  var oi = 0, ni = 0;
  for (final op in ops) {
    switch (op) {
      case EditOp.equal:
        result.add(WordDiff(text: oldTokens[oi], type: DiffType.context));
        oi++;
        ni++;
      case EditOp.delete:
        result.add(WordDiff(text: oldTokens[oi], type: DiffType.remove));
        oi++;
      case EditOp.insert:
        result.add(WordDiff(text: newTokens[ni], type: DiffType.add));
        ni++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Char diff
// ---------------------------------------------------------------------------

/// Compute a character-level diff between [oldStr] and [newStr].
List<CharDiff> computeCharDiff(String oldStr, String newStr) {
  final oldChars = oldStr.split('');
  final newChars = newStr.split('');
  final ops = shortestEditScript(oldChars, newChars);

  final result = <CharDiff>[];
  var oi = 0, ni = 0;
  for (final op in ops) {
    switch (op) {
      case EditOp.equal:
        result.add(CharDiff(char: oldChars[oi], type: DiffType.context));
        oi++;
        ni++;
      case EditOp.delete:
        result.add(CharDiff(char: oldChars[oi], type: DiffType.remove));
        oi++;
      case EditOp.insert:
        result.add(CharDiff(char: newChars[ni], type: DiffType.add));
        ni++;
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Patch creation
// ---------------------------------------------------------------------------

/// Create a [PatchSet] from [oldText] to [newText].
///
/// [contextLines] controls how many context lines surround each hunk.
PatchSet createPatch(String oldText, String newText, {int contextLines = 3}) {
  final diffs = computeLineDiff(oldText, newText);
  if (diffs.every((d) => d.type == DiffType.context)) {
    return const PatchSet(hunks: []);
  }

  // Find ranges of changes and expand with context
  final changeIndices = <int>[];
  for (var i = 0; i < diffs.length; i++) {
    if (diffs[i].type != DiffType.context) {
      changeIndices.add(i);
    }
  }

  if (changeIndices.isEmpty) return const PatchSet(hunks: []);

  // Group changes into hunks
  final hunkGroups = <List<int>>[
    [changeIndices.first],
  ];
  for (var i = 1; i < changeIndices.length; i++) {
    if (changeIndices[i] - changeIndices[i - 1] <= contextLines * 2 + 1) {
      hunkGroups.last.add(changeIndices[i]);
    } else {
      hunkGroups.add([changeIndices[i]]);
    }
  }

  final hunks = <Hunk>[];
  for (final group in hunkGroups) {
    final start = math.max(0, group.first - contextLines);
    final end = math.min(diffs.length - 1, group.last + contextLines);
    final lines = diffs.sublist(start, end + 1);

    var oldStart = 1, newStart = 1;
    // Count lines up to start
    for (var i = 0; i < start; i++) {
      if (diffs[i].type != DiffType.add) oldStart++;
      if (diffs[i].type != DiffType.remove) newStart++;
    }

    var oldCount = 0, newCount = 0;
    for (final l in lines) {
      if (l.type != DiffType.add) oldCount++;
      if (l.type != DiffType.remove) newCount++;
    }

    hunks.add(
      Hunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        lines: lines,
      ),
    );
  }

  return PatchSet(hunks: hunks);
}

// ---------------------------------------------------------------------------
// Patch application
// ---------------------------------------------------------------------------

/// Apply a [patch] to [text], returning a [PatchResult].
PatchResult applyPatch(String text, PatchSet patch) {
  if (patch.hunks.isEmpty) {
    return PatchResult(
      text: text,
      appliedHunks: const [],
      conflictHunks: const [],
    );
  }

  final lines = text.split('\n');
  final applied = <Hunk>[];
  final conflicts = <Hunk>[];
  var offset = 0;

  for (final hunk in patch.hunks) {
    final pos = hunk.oldStart - 1 + offset;

    // Verify context lines match
    var contextOk = true;
    var lineIdx = pos;
    for (final hl in hunk.lines) {
      if (hl.type == DiffType.context || hl.type == DiffType.remove) {
        if (lineIdx < 0 ||
            lineIdx >= lines.length ||
            lines[lineIdx] != hl.content) {
          contextOk = false;
          break;
        }
        lineIdx++;
      }
    }

    if (!contextOk) {
      conflicts.add(hunk);
      continue;
    }

    // Apply the hunk
    final newLines = <String>[];
    lineIdx = pos;
    for (final hl in hunk.lines) {
      switch (hl.type) {
        case DiffType.context:
          newLines.add(lines[lineIdx]);
          lineIdx++;
        case DiffType.remove:
          lineIdx++;
        case DiffType.add:
          newLines.add(hl.content);
      }
    }

    lines.replaceRange(pos, pos + hunk.oldCount, newLines);
    offset += hunk.newCount - hunk.oldCount;
    applied.add(hunk);
  }

  return PatchResult(
    text: lines.join('\n'),
    appliedHunks: applied,
    conflictHunks: conflicts,
  );
}

// ---------------------------------------------------------------------------
// Patch formatting / parsing
// ---------------------------------------------------------------------------

/// Format a [PatchSet] as a unified diff string.
String formatPatch(PatchSet patch) {
  final buf = StringBuffer();
  for (final hunk in patch.hunks) {
    buf.writeln(hunk.header);
    for (final line in hunk.lines) {
      final prefix = switch (line.type) {
        DiffType.add => '+',
        DiffType.remove => '-',
        DiffType.context => ' ',
      };
      buf.writeln('$prefix${line.content}');
    }
  }
  return buf.toString();
}

/// Parse a unified diff string into a [PatchSet].
PatchSet _parsePatch(String text) {
  final hunks = <Hunk>[];
  final lines = text.split('\n');
  final hunkHeaderRe = RegExp(r'^@@ -(\d+),(\d+) \+(\d+),(\d+) @@');

  var i = 0;
  while (i < lines.length) {
    final match = hunkHeaderRe.firstMatch(lines[i]);
    if (match == null) {
      i++;
      continue;
    }

    final oldStart = int.parse(match.group(1)!);
    final oldCount = int.parse(match.group(2)!);
    final newStart = int.parse(match.group(3)!);
    final newCount = int.parse(match.group(4)!);

    i++;
    final hunkLines = <LineDiff>[];
    var lineNum = 0;
    while (i < lines.length && !lines[i].startsWith('@@')) {
      final l = lines[i];
      if (l.isEmpty) {
        i++;
        continue;
      }
      final prefix = l[0];
      final content = l.length > 1 ? l.substring(1) : '';
      lineNum++;
      final type = switch (prefix) {
        '+' => DiffType.add,
        '-' => DiffType.remove,
        _ => DiffType.context,
      };
      hunkLines.add(
        LineDiff(lineNumber: lineNum, content: content, type: type),
      );
      i++;
    }

    hunks.add(
      Hunk(
        oldStart: oldStart,
        oldCount: oldCount,
        newStart: newStart,
        newCount: newCount,
        lines: hunkLines,
      ),
    );
  }
  return PatchSet(hunks: hunks);
}

// ---------------------------------------------------------------------------
// Statistics
// ---------------------------------------------------------------------------

/// Compute [DiffStats] between [oldText] and [newText].
DiffStats diffStats(String oldText, String newText) {
  final diffs = computeLineDiff(oldText, newText);
  var additions = 0, deletions = 0, unchanged = 0;
  final modifications = <int>[];

  // Group adjacent removes+adds as modifications
  var i = 0;
  while (i < diffs.length) {
    if (diffs[i].type == DiffType.context) {
      unchanged++;
      i++;
    } else if (diffs[i].type == DiffType.remove) {
      var removes = 0;
      while (i < diffs.length && diffs[i].type == DiffType.remove) {
        removes++;
        i++;
      }
      var adds = 0;
      while (i < diffs.length && diffs[i].type == DiffType.add) {
        adds++;
        i++;
      }
      if (adds > 0 && removes > 0) {
        final mods = math.min(adds, removes);
        modifications.add(mods);
        additions += adds - mods;
        deletions += removes - mods;
      } else {
        deletions += removes;
        additions += adds;
      }
    } else {
      additions++;
      i++;
    }
  }

  return DiffStats(
    additions: additions,
    deletions: deletions,
    modifications: modifications.fold(0, (a, b) => a + b),
    unchanged: unchanged,
  );
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

/// Generate a human-readable summary from a list of [LineDiff]s.
String generateSummary(List<LineDiff> diffs) {
  final adds = diffs.where((d) => d.type == DiffType.add).length;
  final removes = diffs.where((d) => d.type == DiffType.remove).length;
  final context = diffs.where((d) => d.type == DiffType.context).length;

  final parts = <String>[];
  if (adds > 0) parts.add('$adds line${adds == 1 ? '' : 's'} added');
  if (removes > 0) parts.add('$removes line${removes == 1 ? '' : 's'} removed');
  if (context > 0) {
    parts.add('$context line${context == 1 ? '' : 's'} unchanged');
  }

  if (parts.isEmpty) return 'No changes';
  return parts.join(', ');
}
