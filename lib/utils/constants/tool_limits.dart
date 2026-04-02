// Tool result size limits — ported from OpenClaude src/constants/toolLimits.ts.

/// Default maximum size in characters for tool results before disk persistence.
const int defaultMaxResultSizeChars = 50000;

/// Maximum size for tool results in tokens.
const int maxToolResultTokens = 100000;

/// Bytes per token estimate for byte-to-token conversion.
const int bytesPerToken = 4;

/// Maximum size for tool results in bytes (derived from token limit).
const int maxToolResultBytes = maxToolResultTokens * bytesPerToken;

/// Default maximum aggregate size in characters for tool_result blocks
/// within a single user message (one turn's batch of parallel tool results).
const int maxToolResultsPerMessageChars = 200000;

/// Maximum character length for tool summary strings in compact views.
const int toolSummaryMaxLength = 50;
