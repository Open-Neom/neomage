// API beta headers — ported from OpenClaude src/constants/betas.ts.

const String claudeCode20250219BetaHeader = 'claude-code-20250219';
const String interleavedThinkingBetaHeader =
    'interleaved-thinking-2025-05-14';
const String context1mBetaHeader = 'context-1m-2025-08-07';
const String contextManagementBetaHeader = 'context-management-2025-06-27';
const String structuredOutputsBetaHeader = 'structured-outputs-2025-12-15';
const String webSearchBetaHeader = 'web-search-2025-03-05';

/// Tool search beta header for Claude API / Foundry (1P).
const String toolSearchBetaHeader1p = 'advanced-tool-use-2025-11-20';

/// Tool search beta header for Vertex AI / Bedrock (3P).
const String toolSearchBetaHeader3p = 'tool-search-tool-2025-10-19';

const String effortBetaHeader = 'effort-2025-11-24';
const String taskBudgetsBetaHeader = 'task-budgets-2026-03-13';
const String promptCachingScopeBetaHeader =
    'prompt-caching-scope-2026-01-05';
const String fastModeBetaHeader = 'fast-mode-2026-02-01';
const String redactThinkingBetaHeader = 'redact-thinking-2026-02-12';
const String tokenEfficientToolsBetaHeader =
    'token-efficient-tools-2026-03-28';
const String summarizeConnectorTextBetaHeader =
    'summarize-connector-text-2026-03-13';
const String afkModeBetaHeader = 'afk-mode-2026-01-31';
const String advisorBetaHeader = 'advisor-tool-2026-03-01';

/// Betas that go in Bedrock extraBodyParams (not headers).
const Set<String> bedrockExtraParamsHeaders = {
  interleavedThinkingBetaHeader,
  context1mBetaHeader,
  toolSearchBetaHeader3p,
};

/// Betas allowed on Vertex countTokens API.
const Set<String> vertexCountTokensAllowedBetas = {
  claudeCode20250219BetaHeader,
  interleavedThinkingBetaHeader,
  contextManagementBetaHeader,
};
