// Diff service — port of neom_claw diff functionality.
// Provides Myers diff algorithm, patch application, three-way merge,
// and various diff formatting utilities.

import 'package:flutter_claw/core/platform/claw_io.dart';
import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Algorithm used to compute diffs.
enum DiffAlgorithm {
  /// Myers O(ND) diff — the default.
  myers,

  /// Patience diff — better for code with many identical lines.
  patience,

  /// Histogram diff — variant of patience, used by Git.
  histogram,
}

/// Type of a single diff line.
enum DiffLineType {
  /// Unchanged context line.
  context,

  /// Added line.
  add,

  /// Removed line.
  remove,
}

// ---------------------------------------------------------------------------
// Data classes
// ---------------------------------------------------------------------------

/// A single line within a diff hunk.
class DiffLine {
  /// Whether this line is context, an addition, or a removal.
  final DiffLineType type;

  /// Text content of the line (without the leading +/- marker).
  final String content;

  /// 1-based line number in the old file (null for additions).
  final int? oldLineNumber;

  /// 1-based line number in the new file (null for removals).
  final int? newLineNumber;

  const DiffLine({
    required this.type,
    required this.content,
    this.oldLineNumber,
    this.newLineNumber,
  });

  @override
  String toString() {
    final prefix = switch (type) {
      DiffLineType.context => ' ',
      DiffLineType.add => '+',
      DiffLineType.remove => '-',
    };
    return '$prefix$content';
  }
}

/// A contiguous group of changes in a diff.
class DiffHunk {
  /// 1-based starting line in the old file.
  final int oldStart;

  /// Number of lines from the old file in this hunk.
  final int oldCount;

  /// 1-based starting line in the new file.
  final int newStart;

  /// Number of lines from the new file in this hunk.
  final int newCount;

  /// The lines composing this hunk.
  final List<DiffLine> lines;

  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  /// Unified diff header for this hunk.
  String get header => '@@ -$oldStart,$oldCount +$newStart,$newCount @@';

  @override
  String toString() {
    final buf = StringBuffer(header);
    buf.writeln();
    for (final line in lines) {
      buf.writeln(line);
    }
    return buf.toString();
  }
}

/// Statistics about additions and deletions in a diff.
class DiffStats {
  final int additions;
  final int deletions;
  const DiffStats({required this.additions, required this.deletions});

  int get total => additions + deletions;

  @override
  String toString() => '+$additions -$deletions';
}

/// Diff result for a single file.
class FileDiff {
  /// Path of the file (new path if renamed).
  final String path;

  /// Original path if the file was renamed, otherwise same as [path].
  final String oldPath;

  /// The hunks that compose this diff.
  final List<DiffHunk> hunks;

  /// Summary statistics.
  final DiffStats stats;

  const FileDiff({
    required this.path,
    required this.oldPath,
    required this.hunks,
    required this.stats,
  });

  /// Whether the file was renamed.
  bool get isRename => path != oldPath;

  @override
  String toString() {
    final buf = StringBuffer();
    buf.writeln('--- a/$oldPath');
    buf.writeln('+++ b/$path');
    for (final hunk in hunks) {
      buf.write(hunk);
    }
    return buf.toString();
  }
}

/// A region where a three-way merge encountered a conflict.
class ConflictRegion {
  /// Lines from the base version.
  final List<String> base;

  /// Lines from "ours".
  final List<String> ours;

  /// Lines from "theirs".
  final List<String> theirs;

  /// 1-based start line in the merged output.
  final int startLine;

  const ConflictRegion({
    required this.base,
    required this.ours,
    required this.theirs,
    required this.startLine,
  });
}

/// Result of a three-way merge.
class MergeResult {
  /// The merged text. Contains conflict markers when [hasConflicts] is true.
  final String merged;

  /// List of conflict regions (empty when the merge is clean).
  final List<ConflictRegion> conflicts;

  const MergeResult({required this.merged, required this.conflicts});

  /// Whether the merge completed without conflicts.
  bool get hasConflicts => conflicts.isNotEmpty;
}

/// A span of text within a line, used for inline (word-level) highlighting.
class InlineSpan {
  /// The text fragment.
  final String text;

  /// Whether this span represents a changed region.
  final bool isChanged;

  const InlineSpan({required this.text, required this.isChanged});

  @override
  String toString() => isChanged ? '[$text]' : text;
}

// ---------------------------------------------------------------------------
// Internal Myers diff helpers
// ---------------------------------------------------------------------------

/// An edit operation produced by the Myers algorithm.
enum _EditType { insert, delete, equal }

class _Edit {
  final _EditType type;
  final int oldIndex; // index in old list
  final int newIndex; // index in new list
  const _Edit(this.type, this.oldIndex, this.newIndex);
}

/// Myers O(ND) shortest-edit-script with linear-space optimisation.
///
/// Returns a list of [_Edit] operations that transform [a] into [b].
List<_Edit> _myersDiff(List<String> a, List<String> b) {
  final n = a.length;
  final m = b.length;

  if (n == 0 && m == 0) return const [];
  if (n == 0) {
    return List.generate(m, (j) => _Edit(_EditType.insert, 0, j));
  }
  if (m == 0) {
    return List.generate(n, (i) => _Edit(_EditType.delete, i, 0));
  }

  // Standard Myers with O((N+M)*D) time, backtracking for the path.
  final max = n + m;
  // v[k+max] = x value on diagonal k.
  final vSize = 2 * max + 1;
  final v = List<int>.filled(vSize, 0);
  // Store each v snapshot for backtracking.
  final trace = <List<int>>[];

  outer:
  for (var d = 0; d <= max; d++) {
    trace.add(List<int>.from(v));
    for (var k = -d; k <= d; k += 2) {
      int x;
      if (k == -d || (k != d && v[k - 1 + max] < v[k + 1 + max])) {
        x = v[k + 1 + max]; // move down
      } else {
        x = v[k - 1 + max] + 1; // move right
      }
      var y = x - k;
      // Follow diagonal (equal elements).
      while (x < n && y < m && a[x] == b[y]) {
        x++;
        y++;
      }
      v[k + max] = x;
      if (x >= n && y >= m) break outer;
    }
  }

  // Backtrack through the trace to recover the edit script.
  final edits = <_Edit>[];
  var x = n;
  var y = m;
  for (var d = trace.length - 1; d > 0; d--) {
    final prev = trace[d - 1];
    final k = x - y;
    int prevK;
    if (k == -d || (k != d && prev[k - 1 + max] < prev[k + 1 + max])) {
      prevK = k + 1;
    } else {
      prevK = k - 1;
    }
    final prevX = prev[prevK + max];
    final prevY = prevX - prevK;

    // Diagonal moves (equals).
    while (x > prevX && y > prevY) {
      x--;
      y--;
      edits.add(_Edit(_EditType.equal, x, y));
    }

    if (d > 0) {
      if (x == prevX) {
        // Insert
        y--;
        edits.add(_Edit(_EditType.insert, x, y));
      } else {
        // Delete
        x--;
        edits.add(_Edit(_EditType.delete, x, y));
      }
    }
  }
  // Remaining diagonal at d=0.
  while (x > 0 && y > 0) {
    x--;
    y--;
    edits.add(_Edit(_EditType.equal, x, y));
  }

  return edits.reversed.toList();
}

// ---------------------------------------------------------------------------
// DiffService
// ---------------------------------------------------------------------------

/// Service for computing diffs, applying patches, and performing merges.
class DiffService {
  /// Default number of context lines around changes.
  final int defaultContextLines;

  DiffService({this.defaultContextLines = 3});

  // -------------------------------------------------------------------------
  // Core diff computation
  // -------------------------------------------------------------------------

  /// Compute the diff between [oldText] and [newText].
  ///
  /// Returns a list of [DiffHunk]s representing the changes. The [algorithm]
  /// parameter selects the diff strategy (currently Myers is the only fully
  /// implemented variant; the others fall back to Myers).
  List<DiffHunk> computeDiff(
    String oldText,
    String newText, {
    DiffAlgorithm algorithm = DiffAlgorithm.myers,
    int? contextLines,
  }) {
    final ctx = contextLines ?? defaultContextLines;
    final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
    final newLines = newText.isEmpty ? <String>[] : newText.split('\n');

    final edits = _myersDiff(oldLines, newLines);
    return _editsToHunks(edits, oldLines, newLines, ctx);
  }

  /// Compute a [FileDiff] by reading files at [oldPath] and [newPath].
  Future<FileDiff> computeFileDiff(String oldPath, String newPath) async {
    final oldFile = File(oldPath);
    final newFile = File(newPath);
    final oldText = await oldFile.exists() ? await oldFile.readAsString() : '';
    final newText = await newFile.exists() ? await newFile.readAsString() : '';

    final hunks = computeDiff(oldText, newText);
    final stats = _computeStats(hunks);
    return FileDiff(
      path: newPath,
      oldPath: oldPath,
      hunks: hunks,
      stats: stats,
    );
  }

  /// Compute diffs for every file that differs between [oldDir] and [newDir].
  Future<List<FileDiff>> computeDirectoryDiff(
    String oldDir,
    String newDir,
  ) async {
    final oldFiles = await _listFiles(oldDir);
    final newFiles = await _listFiles(newDir);
    final allRelative = <String>{...oldFiles, ...newFiles};
    final diffs = <FileDiff>[];

    for (final rel in allRelative) {
      final oldPath = '$oldDir/$rel';
      final newPath = '$newDir/$rel';
      final oldFile = File(oldPath);
      final newFile = File(newPath);

      final oldText = await oldFile.exists() ? await oldFile.readAsString() : '';
      final newText = await newFile.exists() ? await newFile.readAsString() : '';

      if (oldText == newText) continue;

      final hunks = computeDiff(oldText, newText);
      final stats = _computeStats(hunks);
      diffs.add(FileDiff(
        path: rel,
        oldPath: rel,
        hunks: hunks,
        stats: stats,
      ));
    }
    return diffs;
  }

  // -------------------------------------------------------------------------
  // Patch application
  // -------------------------------------------------------------------------

  /// Apply a list of [hunks] to [original] text and return the result.
  String applyPatch(String original, List<DiffHunk> hunks) {
    final lines = original.isEmpty ? <String>[] : original.split('\n');
    var offset = 0;

    for (final hunk in hunks) {
      final start = hunk.oldStart - 1 + offset;
      final toRemove = <int>[];
      final toInsert = <String>[];
      var idx = start;

      for (final line in hunk.lines) {
        switch (line.type) {
          case DiffLineType.context:
            idx++;
            break;
          case DiffLineType.remove:
            toRemove.add(idx);
            idx++;
            break;
          case DiffLineType.add:
            toInsert.add(line.content);
            break;
        }
      }

      // Remove lines in reverse order to keep indices stable.
      for (final i in toRemove.reversed) {
        if (i < lines.length) lines.removeAt(i);
      }
      // Insert at the position of the first removal (or current index).
      final insertAt = toRemove.isEmpty ? start : toRemove.first;
      for (var i = 0; i < toInsert.length; i++) {
        lines.insert(insertAt + i, toInsert[i]);
      }

      offset += toInsert.length - toRemove.length;
    }

    return lines.join('\n');
  }

  /// Reverse a patch so that applying the reversed hunks undoes the original.
  List<DiffHunk> reversePatch(List<DiffHunk> hunks) {
    return hunks.map((hunk) {
      final reversedLines = hunk.lines.map((line) {
        final newType = switch (line.type) {
          DiffLineType.add => DiffLineType.remove,
          DiffLineType.remove => DiffLineType.add,
          DiffLineType.context => DiffLineType.context,
        };
        return DiffLine(
          type: newType,
          content: line.content,
          oldLineNumber: line.newLineNumber,
          newLineNumber: line.oldLineNumber,
        );
      }).toList();

      return DiffHunk(
        oldStart: hunk.newStart,
        oldCount: hunk.newCount,
        newStart: hunk.oldStart,
        newCount: hunk.oldCount,
        lines: reversedLines,
      );
    }).toList();
  }

  // -------------------------------------------------------------------------
  // Formatting
  // -------------------------------------------------------------------------

  /// Format a [FileDiff] as a unified diff string.
  String formatUnifiedDiff(FileDiff diff, {int? contextLines}) {
    final buf = StringBuffer();
    buf.writeln('--- a/${diff.oldPath}');
    buf.writeln('+++ b/${diff.path}');

    for (final hunk in diff.hunks) {
      buf.writeln(hunk.header);
      for (final line in hunk.lines) {
        buf.writeln(line);
      }
    }
    return buf.toString();
  }

  /// Format a [FileDiff] as a side-by-side comparison.
  ///
  /// [width] controls the total character width of the output (default 120).
  String formatSideBySide(FileDiff diff, {int width = 120}) {
    final colWidth = (width - 3) ~/ 2; // 3 = " | " separator
    final buf = StringBuffer();

    for (final hunk in diff.hunks) {
      // Collect old/new columns.
      final oldCol = <String>[];
      final newCol = <String>[];

      for (final line in hunk.lines) {
        switch (line.type) {
          case DiffLineType.context:
            oldCol.add(line.content);
            newCol.add(line.content);
            break;
          case DiffLineType.remove:
            oldCol.add(line.content);
            newCol.add('');
            break;
          case DiffLineType.add:
            oldCol.add('');
            newCol.add(line.content);
            break;
        }
      }

      final rows = math.max(oldCol.length, newCol.length);
      for (var i = 0; i < rows; i++) {
        final left = i < oldCol.length ? oldCol[i] : '';
        final right = i < newCol.length ? newCol[i] : '';
        buf.write(_pad(left, colWidth));
        buf.write(' | ');
        buf.writeln(_pad(right, colWidth));
      }
    }
    return buf.toString();
  }

  // -------------------------------------------------------------------------
  // Patch parsing
  // -------------------------------------------------------------------------

  /// Parse a unified diff / patch string into a list of [FileDiff].
  List<FileDiff> parsePatch(String patchText) {
    final diffs = <FileDiff>[];
    final lines = patchText.split('\n');
    var i = 0;

    while (i < lines.length) {
      // Find next file header.
      if (i < lines.length && lines[i].startsWith('--- ')) {
        final oldPath = _stripPrefix(lines[i], '--- ');
        i++;
        if (i >= lines.length || !lines[i].startsWith('+++ ')) {
          continue;
        }
        final newPath = _stripPrefix(lines[i], '+++ ');
        i++;

        final hunks = <DiffHunk>[];

        while (i < lines.length && lines[i].startsWith('@@ ')) {
          final header = _parseHunkHeader(lines[i]);
          if (header == null) {
            i++;
            continue;
          }
          i++;

          final hunkLines = <DiffLine>[];
          var oldLine = header.oldStart;
          var newLine = header.newStart;

          while (i < lines.length &&
              !lines[i].startsWith('@@ ') &&
              !lines[i].startsWith('--- ')) {
            final raw = lines[i];
            if (raw.startsWith('+')) {
              hunkLines.add(DiffLine(
                type: DiffLineType.add,
                content: raw.substring(1),
                newLineNumber: newLine,
              ));
              newLine++;
            } else if (raw.startsWith('-')) {
              hunkLines.add(DiffLine(
                type: DiffLineType.remove,
                content: raw.substring(1),
                oldLineNumber: oldLine,
              ));
              oldLine++;
            } else if (raw.startsWith(' ') || raw.isEmpty) {
              final content = raw.isEmpty ? '' : raw.substring(1);
              hunkLines.add(DiffLine(
                type: DiffLineType.context,
                content: content,
                oldLineNumber: oldLine,
                newLineNumber: newLine,
              ));
              oldLine++;
              newLine++;
            } else {
              // Unknown line, skip.
            }
            i++;
          }

          hunks.add(DiffHunk(
            oldStart: header.oldStart,
            oldCount: header.oldCount,
            newStart: header.newStart,
            newCount: header.newCount,
            lines: hunkLines,
          ));
        }

        final stats = _computeStats(hunks);
        diffs.add(FileDiff(
          path: newPath,
          oldPath: oldPath,
          hunks: hunks,
          stats: stats,
        ));
      } else {
        i++;
      }
    }
    return diffs;
  }

  // -------------------------------------------------------------------------
  // Three-way merge
  // -------------------------------------------------------------------------

  /// Perform a three-way merge between [base], [ours], and [theirs].
  ///
  /// Returns a [MergeResult] containing the merged text and any conflict
  /// regions. Conflict markers follow the standard Git format.
  MergeResult threeWayMerge(String base, String ours, String theirs) {
    final baseLines = base.split('\n');
    final ourLines = ours.split('\n');
    final theirLines = theirs.split('\n');

    final ourEdits = _myersDiff(baseLines, ourLines);
    final theirEdits = _myersDiff(baseLines, theirLines);

    final ourChanges = _editsToCh(ourEdits, baseLines, ourLines);
    final theirChanges = _editsToCh(theirEdits, baseLines, theirLines);

    final merged = <String>[];
    final conflicts = <ConflictRegion>[];

    var baseIdx = 0;

    // Build indexed change maps: baseLineIndex -> replacement lines.
    final ourMap = <int, List<String>>{};
    final theirMap = <int, List<String>>{};
    final ourDeletes = <int>{};
    final theirDeletes = <int>{};

    for (final c in ourChanges) {
      if (c.type == _EditType.delete) ourDeletes.add(c.oldIndex);
      if (c.type == _EditType.insert) {
        ourMap.putIfAbsent(c.oldIndex, () => []).add(ourLines[c.newIndex]);
      }
    }
    for (final c in theirChanges) {
      if (c.type == _EditType.delete) theirDeletes.add(c.oldIndex);
      if (c.type == _EditType.insert) {
        theirMap.putIfAbsent(c.oldIndex, () => []).add(theirLines[c.newIndex]);
      }
    }

    for (baseIdx = 0; baseIdx < baseLines.length; baseIdx++) {
      final ourDel = ourDeletes.contains(baseIdx);
      final theirDel = theirDeletes.contains(baseIdx);
      final ourIns = ourMap[baseIdx];
      final theirIns = theirMap[baseIdx];

      // Both sides same change — no conflict.
      if (ourDel == theirDel && _listEq(ourIns, theirIns)) {
        if (!ourDel) merged.add(baseLines[baseIdx]);
        if (ourIns != null) merged.addAll(ourIns);
        continue;
      }

      // Only one side changed.
      if (!ourDel && ourIns == null) {
        if (!theirDel) merged.add(baseLines[baseIdx]);
        if (theirIns != null) merged.addAll(theirIns);
        continue;
      }
      if (!theirDel && theirIns == null) {
        if (!ourDel) merged.add(baseLines[baseIdx]);
        if (ourIns != null) merged.addAll(ourIns);
        continue;
      }

      // Conflict.
      final startLine = merged.length + 1;
      final ourBlock = <String>[];
      final theirBlock = <String>[];
      if (!ourDel) ourBlock.add(baseLines[baseIdx]);
      if (ourIns != null) ourBlock.addAll(ourIns);
      if (!theirDel) theirBlock.add(baseLines[baseIdx]);
      if (theirIns != null) theirBlock.addAll(theirIns);

      conflicts.add(ConflictRegion(
        base: [baseLines[baseIdx]],
        ours: ourBlock,
        theirs: theirBlock,
        startLine: startLine,
      ));

      merged.add('<<<<<<< ours');
      merged.addAll(ourBlock);
      merged.add('=======');
      merged.addAll(theirBlock);
      merged.add('>>>>>>> theirs');
    }

    // Handle trailing inserts past the end of base.
    final ourTrail = ourMap[baseLines.length];
    final theirTrail = theirMap[baseLines.length];
    if (ourTrail != null) merged.addAll(ourTrail);
    if (theirTrail != null) merged.addAll(theirTrail);

    return MergeResult(merged: merged.join('\n'), conflicts: conflicts);
  }

  // -------------------------------------------------------------------------
  // Inline diff highlighting
  // -------------------------------------------------------------------------

  /// Compute word-level inline diff between [oldLine] and [newLine].
  ///
  /// Returns a pair of span lists: the first for the old line, the second for
  /// the new line. Changed words are marked with [InlineSpan.isChanged] = true.
  (List<InlineSpan>, List<InlineSpan>) highlightInlineDiff(
    String oldLine,
    String newLine,
  ) {
    final oldTokens = _tokenize(oldLine);
    final newTokens = _tokenize(newLine);
    final edits = _myersDiff(oldTokens, newTokens);

    final oldSpans = <InlineSpan>[];
    final newSpans = <InlineSpan>[];

    for (final edit in edits) {
      switch (edit.type) {
        case _EditType.equal:
          oldSpans.add(InlineSpan(text: oldTokens[edit.oldIndex], isChanged: false));
          newSpans.add(InlineSpan(text: newTokens[edit.newIndex], isChanged: false));
          break;
        case _EditType.delete:
          oldSpans.add(InlineSpan(text: oldTokens[edit.oldIndex], isChanged: true));
          break;
        case _EditType.insert:
          newSpans.add(InlineSpan(text: newTokens[edit.newIndex], isChanged: true));
          break;
      }
    }

    return (_mergeSpans(oldSpans), _mergeSpans(newSpans));
  }

  // -------------------------------------------------------------------------
  // Private helpers
  // -------------------------------------------------------------------------

  /// Convert raw [_Edit] list into grouped [DiffHunk]s with context.
  List<DiffHunk> _editsToHunks(
    List<_Edit> edits,
    List<String> oldLines,
    List<String> newLines,
    int contextLines,
  ) {
    if (edits.isEmpty) return const [];

    // Find ranges of changes.
    final changeIndices = <int>[];
    for (var i = 0; i < edits.length; i++) {
      if (edits[i].type != _EditType.equal) changeIndices.add(i);
    }
    if (changeIndices.isEmpty) return const [];

    // Group changes that are close together.
    final groups = <List<int>>[];
    var currentGroup = <int>[changeIndices.first];

    for (var i = 1; i < changeIndices.length; i++) {
      if (changeIndices[i] - changeIndices[i - 1] <= contextLines * 2 + 1) {
        currentGroup.add(changeIndices[i]);
      } else {
        groups.add(currentGroup);
        currentGroup = [changeIndices[i]];
      }
    }
    groups.add(currentGroup);

    final hunks = <DiffHunk>[];
    for (final group in groups) {
      final first = group.first;
      final last = group.last;
      final startIdx = math.max(0, first - contextLines);
      final endIdx = math.min(edits.length - 1, last + contextLines);

      final hunkLines = <DiffLine>[];
      int? hunkOldStart;
      int? hunkNewStart;
      var oldCount = 0;
      var newCount = 0;

      for (var i = startIdx; i <= endIdx; i++) {
        final edit = edits[i];
        hunkOldStart ??= edit.oldIndex + 1;
        hunkNewStart ??= edit.newIndex + 1;

        switch (edit.type) {
          case _EditType.equal:
            hunkLines.add(DiffLine(
              type: DiffLineType.context,
              content: oldLines[edit.oldIndex],
              oldLineNumber: edit.oldIndex + 1,
              newLineNumber: edit.newIndex + 1,
            ));
            oldCount++;
            newCount++;
            break;
          case _EditType.delete:
            hunkLines.add(DiffLine(
              type: DiffLineType.remove,
              content: oldLines[edit.oldIndex],
              oldLineNumber: edit.oldIndex + 1,
            ));
            oldCount++;
            break;
          case _EditType.insert:
            hunkLines.add(DiffLine(
              type: DiffLineType.add,
              content: newLines[edit.newIndex],
              newLineNumber: edit.newIndex + 1,
            ));
            newCount++;
            break;
        }
      }

      hunks.add(DiffHunk(
        oldStart: hunkOldStart ?? 1,
        oldCount: oldCount,
        newStart: hunkNewStart ?? 1,
        newCount: newCount,
        lines: hunkLines,
      ));
    }
    return hunks;
  }

  /// Compute [DiffStats] from a list of hunks.
  DiffStats _computeStats(List<DiffHunk> hunks) {
    var additions = 0;
    var deletions = 0;
    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        if (line.type == DiffLineType.add) additions++;
        if (line.type == DiffLineType.remove) deletions++;
      }
    }
    return DiffStats(additions: additions, deletions: deletions);
  }

  /// List files recursively under [dir], returning relative paths.
  Future<List<String>> _listFiles(String dir) async {
    final directory = Directory(dir);
    if (!await directory.exists()) return const [];
    final result = <String>[];
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        result.add(entity.path.substring(dir.length + 1));
      }
    }
    return result;
  }

  /// Parse a hunk header like "@@ -1,5 +1,7 @@".
  _HunkHeader? _parseHunkHeader(String line) {
    final re = RegExp(r'^@@ -(\d+),?(\d*) \+(\d+),?(\d*) @@');
    final match = re.firstMatch(line);
    if (match == null) return null;
    return _HunkHeader(
      oldStart: int.parse(match.group(1)!),
      oldCount: match.group(2)!.isEmpty ? 1 : int.parse(match.group(2)!),
      newStart: int.parse(match.group(3)!),
      newCount: match.group(4)!.isEmpty ? 1 : int.parse(match.group(4)!),
    );
  }

  /// Strip a prefix like "--- a/" or "+++ b/" from a path.
  String _stripPrefix(String line, String prefix) {
    var result = line.substring(prefix.length);
    if (result.startsWith('a/') || result.startsWith('b/')) {
      result = result.substring(2);
    }
    return result;
  }

  /// Pad/truncate [text] to exactly [width] characters.
  String _pad(String text, int width) {
    if (text.length >= width) return text.substring(0, width);
    return text + ' ' * (width - text.length);
  }

  /// Tokenise a line into words and whitespace for inline diff.
  List<String> _tokenize(String line) {
    final tokens = <String>[];
    final re = RegExp(r'\S+|\s+');
    for (final match in re.allMatches(line)) {
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  /// Merge adjacent [InlineSpan]s that share the same [isChanged] flag.
  List<InlineSpan> _mergeSpans(List<InlineSpan> spans) {
    if (spans.isEmpty) return spans;
    final merged = <InlineSpan>[];
    var buf = StringBuffer(spans.first.text);
    var current = spans.first.isChanged;

    for (var i = 1; i < spans.length; i++) {
      if (spans[i].isChanged == current) {
        buf.write(spans[i].text);
      } else {
        merged.add(InlineSpan(text: buf.toString(), isChanged: current));
        buf = StringBuffer(spans[i].text);
        current = spans[i].isChanged;
      }
    }
    merged.add(InlineSpan(text: buf.toString(), isChanged: current));
    return merged;
  }

  /// Produce change list from edits (used by three-way merge).
  List<_Edit> _editsToCh(
    List<_Edit> edits,
    List<String> oldLines,
    List<String> newLines,
  ) {
    return edits.where((e) => e.type != _EditType.equal).toList();
  }

  /// Compare two nullable lists for equality.
  bool _listEq(List<String>? a, List<String>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Internal parsed hunk header.
class _HunkHeader {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  const _HunkHeader({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
  });
}
