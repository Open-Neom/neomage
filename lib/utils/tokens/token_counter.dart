/// Token counting and estimation utilities ported from Neomage TypeScript.
///
/// Provides approximate tokenization compatible with cl100k_base (Neomage/GPT-4),
/// token budgets, cost estimation, and context window management.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// TokenEncoder abstraction
// ---------------------------------------------------------------------------

/// Abstract interface for text tokenizers.
abstract class TokenEncoder {
  /// Encodes [text] into a list of token IDs.
  List<int> encode(String text);

  /// Decodes a list of [tokens] back into text.
  String decode(List<int> tokens);

  /// Returns the number of tokens in [text].
  int count(String text) => encode(text).length;
}

// ---------------------------------------------------------------------------
// Cl100kEncoder — approximate cl100k_base tokenizer
// ---------------------------------------------------------------------------

/// Regex pattern used to split text into rough BPE-compatible chunks, modeled
/// after the cl100k_base tokenizer used by Neomage and GPT-4.
final RegExp _cl100kSplitPattern = RegExp(
  r"'(?:[sdmt]|ll|ve|re)|" // contractions
  r'[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}][\p{Ll}]+|' // Title-case words
  r'[\p{Lu}\p{Lt}]+(?=[\p{Lu}\p{Lt}][\p{Ll}])|' // ALLCAPS before title
  r'\p{L}+|' // other letter runs
  r'\p{N}{1,3}|' // numbers up to 3 digits
  r' ?[^\s\p{L}\p{N}]+[\r\n]*|' // punctuation + optional newline
  r'\s*[\r\n]+|' // newline runs
  r'\s+(?!\S)|' // trailing whitespace
  r'\s+', // other whitespace
  unicode: true,
);

/// CJK Unicode range test.
bool _isCjk(int codeUnit) {
  return (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) || // CJK Unified
      (codeUnit >= 0x3400 && codeUnit <= 0x4DBF) || // CJK Ext A
      (codeUnit >= 0x20000 && codeUnit <= 0x2A6DF) || // CJK Ext B
      (codeUnit >= 0x2A700 && codeUnit <= 0x2B73F) || // CJK Ext C
      (codeUnit >= 0x2B740 && codeUnit <= 0x2B81F) || // CJK Ext D
      (codeUnit >= 0xF900 && codeUnit <= 0xFAFF) || // CJK Compat
      (codeUnit >= 0x3000 && codeUnit <= 0x303F) || // CJK Symbols
      (codeUnit >= 0x3040 && codeUnit <= 0x309F) || // Hiragana
      (codeUnit >= 0x30A0 && codeUnit <= 0x30FF) || // Katakana
      (codeUnit >= 0xAC00 && codeUnit <= 0xD7AF); // Hangul
}

/// Approximate cl100k_base tokenizer using heuristic BPE-like splitting.
///
/// This is *not* a faithful BPE implementation but produces token counts that
/// are typically within 5-10 % of the real cl100k_base encoder for English
/// prose and source code.
class Cl100kEncoder extends TokenEncoder {
  /// Singleton instance.
  static final Cl100kEncoder instance = Cl100kEncoder._();

  Cl100kEncoder._();

  /// Factory constructor returning the shared instance.
  factory Cl100kEncoder() => instance;

  @override
  List<int> encode(String text) {
    if (text.isEmpty) return const [];
    final matches = _cl100kSplitPattern.allMatches(text);
    final tokens = <int>[];
    var id = 0;
    for (final m in matches) {
      final chunk = m.group(0)!;
      // Estimate sub-tokens per chunk based on character class.
      final subTokens = _estimateChunkTokens(chunk);
      for (var i = 0; i < subTokens; i++) {
        tokens.add(id++);
      }
    }
    // Fallback: if regex didn't match anything, approximate.
    if (tokens.isEmpty) {
      final est = _heuristicCount(text);
      for (var i = 0; i < est; i++) {
        tokens.add(i);
      }
    }
    return tokens;
  }

  @override
  String decode(List<int> tokens) {
    // Without a real vocabulary this is a no-op placeholder.
    return '[decoded ${tokens.length} tokens]';
  }

  @override
  int count(String text) {
    if (text.isEmpty) return 0;
    final matches = _cl100kSplitPattern.allMatches(text);
    var total = 0;
    for (final m in matches) {
      total += _estimateChunkTokens(m.group(0)!);
    }
    return total == 0 ? _heuristicCount(text) : total;
  }

  int _estimateChunkTokens(String chunk) {
    if (chunk.isEmpty) return 0;
    // CJK characters are typically 1 token per character.
    var cjkChars = 0;
    for (final cu in chunk.runes) {
      if (_isCjk(cu)) cjkChars++;
    }
    if (cjkChars > 0) {
      final nonCjk = chunk.length - cjkChars;
      return cjkChars + (nonCjk / 4).ceil();
    }
    // Code-like tokens: ~3 chars per token.
    if (RegExp(r'[{}\[\]();=<>!&|^~]').hasMatch(chunk)) {
      return (chunk.length / 3).ceil();
    }
    // English prose: ~4 chars per token.
    return math.max(1, (chunk.length / 4).ceil());
  }

  int _heuristicCount(String text) => math.max(1, (text.length / 4).ceil());
}

// ---------------------------------------------------------------------------
// TokenBudget
// ---------------------------------------------------------------------------

/// Tracks a token budget with reservation support.
class TokenBudget {
  TokenBudget({required this.total, int used = 0}) : _used = used;

  /// Maximum number of tokens allowed.
  final int total;

  int _used;

  /// Number of tokens consumed so far.
  int get used => _used;

  /// Number of tokens still available.
  int get remaining => math.max(0, total - _used);

  /// Usage as a percentage (0.0 to 1.0).
  double get percentage => total == 0 ? 1.0 : _used / total;

  /// Whether the budget has been fully consumed.
  bool get isExhausted => _used >= total;

  /// Reserves [amount] tokens from the budget.
  ///
  /// Returns `true` if the reservation succeeded (enough budget remaining).
  bool reserve(int amount) {
    if (_used + amount > total) return false;
    _used += amount;
    return true;
  }

  /// Releases [amount] tokens back to the budget.
  void release(int amount) {
    _used = math.max(0, _used - amount);
  }

  @override
  String toString() =>
      'TokenBudget(used: $_used, total: $total, '
      '${(percentage * 100).toStringAsFixed(1)}%)';
}

// ---------------------------------------------------------------------------
// Model pricing
// ---------------------------------------------------------------------------

/// Per-token pricing for a single model in USD.
class ModelPricing {
  const ModelPricing({
    required this.name,
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.cacheReadPerMillion = 0,
    this.cacheWritePerMillion = 0,
    this.maxInputTokens = 200000,
    this.maxOutputTokens = 8192,
  });

  final String name;
  final double inputPerMillion;
  final double outputPerMillion;
  final double cacheReadPerMillion;
  final double cacheWritePerMillion;
  final int maxInputTokens;
  final int maxOutputTokens;
}

/// Known model pricing constants (as of early 2025).
class ModelPricingTable {
  ModelPricingTable._();

  static const neomageSonnet = ModelPricing(
    name: 'claude-sonnet-4-20250514',
    inputPerMillion: 3.0,
    outputPerMillion: 15.0,
    cacheReadPerMillion: 0.30,
    cacheWritePerMillion: 3.75,
    maxInputTokens: 200000,
    maxOutputTokens: 8192,
  );

  static const neomageOpus = ModelPricing(
    name: 'claude-opus-4-20250514',
    inputPerMillion: 15.0,
    outputPerMillion: 75.0,
    cacheReadPerMillion: 1.50,
    cacheWritePerMillion: 18.75,
    maxInputTokens: 200000,
    maxOutputTokens: 32000,
  );

  static const neomageHaiku = ModelPricing(
    name: 'claude-3-5-haiku-20241022',
    inputPerMillion: 0.80,
    outputPerMillion: 4.0,
    cacheReadPerMillion: 0.08,
    cacheWritePerMillion: 1.0,
    maxInputTokens: 200000,
    maxOutputTokens: 8192,
  );

  static const gpt4o = ModelPricing(
    name: 'gpt-4o',
    inputPerMillion: 2.50,
    outputPerMillion: 10.0,
    maxInputTokens: 128000,
    maxOutputTokens: 16384,
  );

  static const gpt4oMini = ModelPricing(
    name: 'gpt-4o-mini',
    inputPerMillion: 0.15,
    outputPerMillion: 0.60,
    maxInputTokens: 128000,
    maxOutputTokens: 16384,
  );

  /// Look up pricing by model name. Falls back to [neomageSonnet].
  static ModelPricing forModel(String model) {
    final lower = model.toLowerCase();
    if (lower.contains('opus')) return neomageOpus;
    if (lower.contains('haiku')) return neomageHaiku;
    if (lower.contains('gpt-4o-mini')) return gpt4oMini;
    if (lower.contains('gpt-4o')) return gpt4o;
    return neomageSonnet;
  }
}

// ---------------------------------------------------------------------------
// CostEstimate
// ---------------------------------------------------------------------------

/// Estimated cost for a single API call.
class CostEstimate {
  const CostEstimate({
    required this.inputCost,
    required this.outputCost,
    this.cacheCost = 0,
  });

  final double inputCost;
  final double outputCost;
  final double cacheCost;

  /// Total estimated cost in USD.
  double get totalCost => inputCost + outputCost + cacheCost;

  /// Human-readable cost string.
  String get formatted {
    if (totalCost < 0.01) {
      return '\$${(totalCost * 100).toStringAsFixed(3)}c';
    }
    return '\$${totalCost.toStringAsFixed(4)}';
  }

  @override
  String toString() =>
      'CostEstimate(input: \$${inputCost.toStringAsFixed(4)}, '
      'output: \$${outputCost.toStringAsFixed(4)}, '
      'cache: \$${cacheCost.toStringAsFixed(4)}, '
      'total: $formatted)';
}

// ---------------------------------------------------------------------------
// ContextWindow
// ---------------------------------------------------------------------------

/// Represents the token capacity of a model's context window.
class ContextWindow {
  const ContextWindow({
    required this.maxInput,
    required this.maxOutput,
    this.used = 0,
  });

  final int maxInput;
  final int maxOutput;
  final int used;

  /// Tokens still available in the input context.
  int get available => math.max(0, maxInput - used);

  /// Utilization as a percentage (0.0 to 100.0).
  double get utilizationPercent =>
      maxInput == 0 ? 100.0 : (used / maxInput) * 100;

  /// Returns a copy with updated [used] count.
  ContextWindow withUsed(int used) =>
      ContextWindow(maxInput: maxInput, maxOutput: maxOutput, used: used);

  @override
  String toString() =>
      'ContextWindow(used: $used/$maxInput, '
      '${utilizationPercent.toStringAsFixed(1)}%)';
}

// ---------------------------------------------------------------------------
// TokenCounter
// ---------------------------------------------------------------------------

/// High-level token counting, truncation, splitting, and cost estimation.
class TokenCounter {
  TokenCounter({TokenEncoder? encoder}) : _encoder = encoder ?? Cl100kEncoder();

  final TokenEncoder _encoder;

  /// Per-message overhead tokens (role, separators, etc.).
  static const int _messageOverhead = 4;

  /// Per-tool-call overhead tokens.
  static const int _toolOverhead = 20;

  /// Counts the tokens in [text] using the configured encoder.
  int countTokens(String text, {String? model}) => _encoder.count(text);

  /// Counts total tokens for a list of chat [messages].
  ///
  /// Each message is expected to have `role` and `content` keys. An overhead
  /// of [_messageOverhead] tokens is added per message to account for special
  /// tokens and role markers.
  int countMessageTokens(List<Map<String, String>> messages) {
    var total = 3; // Every conversation has a fixed priming overhead.
    for (final msg in messages) {
      total += _messageOverhead;
      final role = msg['role'] ?? '';
      final content = msg['content'] ?? '';
      total += _encoder.count(role);
      total += _encoder.count(content);
    }
    return total;
  }

  /// Estimates tokens for a tool-use invocation.
  int countToolUseTokens(String tool, String input) {
    return _toolOverhead + _encoder.count(tool) + _encoder.count(input);
  }

  /// Estimates the token cost of an image based on its dimensions and detail
  /// level.
  ///
  /// Uses the tile-based formula from OpenAI / Anthropic documentation:
  /// - `low` detail: fixed 85 tokens
  /// - `high` detail: 170 tokens per 512x512 tile + 85 base
  int estimateImageTokens(int width, int height, {String detail = 'auto'}) {
    if (detail == 'low') return 85;
    // Scale down to fit within 2048x2048 then tile at 512x512.
    var w = width.toDouble();
    var h = height.toDouble();
    if (w > 2048 || h > 2048) {
      final scale = 2048 / math.max(w, h);
      w = (w * scale).ceilToDouble();
      h = (h * scale).ceilToDouble();
    }
    // Scale shortest side to 768.
    final minSide = math.min(w, h);
    if (minSide > 768) {
      final scale = 768 / minSide;
      w = (w * scale).ceilToDouble();
      h = (h * scale).ceilToDouble();
    }
    final tilesX = (w / 512).ceil();
    final tilesY = (h / 512).ceil();
    return 170 * tilesX * tilesY + 85;
  }

  /// Estimates tokens for a PDF with the given [pageCount].
  ///
  /// Rough heuristic: ~1500 tokens per page of text-heavy content.
  int estimatePdfTokens(int pageCount) => pageCount * 1500;

  /// Truncates [text] to at most [maxTokens], returning the truncated string.
  ///
  /// Binary-searches for the character boundary that yields [maxTokens].
  String truncateToTokens(String text, int maxTokens) {
    if (_encoder.count(text) <= maxTokens) return text;
    // Binary search for the right length.
    var lo = 0;
    var hi = text.length;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (_encoder.count(text.substring(0, mid)) <= maxTokens) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return text.substring(0, lo);
  }

  /// Splits [text] into chunks of approximately [chunkSize] tokens.
  ///
  /// If [overlap] is provided, each chunk overlaps with the previous one by
  /// that many tokens.
  List<String> splitByTokens(String text, int chunkSize, {int overlap = 0}) {
    if (text.isEmpty) return [];
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      // Find end position for this chunk.
      var end = text.length;
      while (_encoder.count(text.substring(start, end)) > chunkSize &&
          end > start + 1) {
        end =
            start +
            ((end - start) *
                    chunkSize /
                    _encoder.count(text.substring(start, end)))
                .floor();
        if (end <= start) end = start + 1;
      }
      chunks.add(text.substring(start, end));
      if (end >= text.length) break;
      // Move start back by overlap.
      if (overlap > 0 && chunks.length > 1) {
        final overlapChars = (overlap * 4).clamp(0, end - start);
        start = end - overlapChars;
      } else {
        start = end;
      }
    }
    return chunks;
  }

  /// Estimates the cost of an API call given input and output token counts.
  CostEstimate estimateCost(
    int inputTokens,
    int outputTokens, {
    String model = 'claude-sonnet-4-20250514',
    int cacheRead = 0,
    int cacheWrite = 0,
  }) {
    final pricing = ModelPricingTable.forModel(model);
    final inputCost = (inputTokens - cacheRead) * pricing.inputPerMillion / 1e6;
    final outputCost = outputTokens * pricing.outputPerMillion / 1e6;
    final cacheCost =
        cacheRead * pricing.cacheReadPerMillion / 1e6 +
        cacheWrite * pricing.cacheWritePerMillion / 1e6;
    return CostEstimate(
      inputCost: inputCost,
      outputCost: outputCost,
      cacheCost: cacheCost,
    );
  }
}

// ---------------------------------------------------------------------------
// Quick heuristic
// ---------------------------------------------------------------------------

/// Quick heuristic token estimate: roughly 1 token per 4 characters for
/// English text.
int estimateTokens(String text) => math.max(1, (text.length / 4).ceil());
