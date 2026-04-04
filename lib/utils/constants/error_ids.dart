// Error IDs for tracking error sources — ported from NeomClaw src/constants/errorIds.ts.
// These IDs help trace which logError() call generated an error.
// Each category reserves a numeric range for future expansion.

const int eToolUseSummaryGenerationFailed = 344;

/// Structured error-ID constants used by [logError] and error reporting.
///
/// Organised by subsystem so that a numeric ID instantly narrows down the
/// origin of a failure during debugging and telemetry analysis.
class ErrorId {
  ErrorId._();

  // ---------------------------------------------------------------------------
  // API errors (100–199)
  // ---------------------------------------------------------------------------
  static const String apiConnectionFailed = 'api_connection_failed';
  static const String apiAuthFailed = 'api_auth_failed';
  static const String apiKeyMissing = 'api_key_missing';
  static const String apiKeyInvalid = 'api_key_invalid';
  static const String apiRateLimited = 'api_rate_limited';
  static const String apiModelNotFound = 'api_model_not_found';
  static const String apiContextExceeded = 'api_context_exceeded';
  static const String apiMaxTokensExceeded = 'api_max_tokens_exceeded';
  static const String apiStreamError = 'api_stream_error';
  static const String apiTimeout = 'api_timeout';

  // ---------------------------------------------------------------------------
  // Tool errors (200–299)
  // ---------------------------------------------------------------------------
  static const String toolNotFound = 'tool_not_found';
  static const String toolExecutionFailed = 'tool_execution_failed';
  static const String toolTimedOut = 'tool_timed_out';
  static const String toolInvalidInput = 'tool_invalid_input';
  static const String toolPermissionDenied = 'tool_permission_denied';
  static const String toolOutputTruncated = 'tool_output_truncated';
  static const String toolSandboxViolation = 'tool_sandbox_violation';

  // ---------------------------------------------------------------------------
  // File-system errors (300–399)
  // ---------------------------------------------------------------------------
  static const String fileNotFound = 'file_not_found';
  static const String fileReadError = 'file_read_error';
  static const String fileWriteError = 'file_write_error';
  static const String filePermissionDenied = 'file_permission_denied';
  static const String fileTooLarge = 'file_too_large';
  static const String fileBinary = 'file_binary';
  static const String fileEncodingError = 'file_encoding_error';
  static const String fileLocked = 'file_locked';

  // ---------------------------------------------------------------------------
  // Git errors (400–499)
  // ---------------------------------------------------------------------------
  static const String gitNotFound = 'git_not_found';
  static const String gitNotRepo = 'git_not_repo';
  static const String gitCommandFailed = 'git_command_failed';
  static const String gitMergeConflict = 'git_merge_conflict';
  static const String gitAuthFailed = 'git_auth_failed';
  static const String gitDirtyWorkingTree = 'git_dirty_working_tree';

  // ---------------------------------------------------------------------------
  // Session errors (500–599)
  // ---------------------------------------------------------------------------
  static const String sessionNotFound = 'session_not_found';
  static const String sessionCorrupted = 'session_corrupted';
  static const String sessionWriteFailed = 'session_write_failed';
  static const String sessionMigrationFailed = 'session_migration_failed';
  static const String sessionLimitReached = 'session_limit_reached';

  // ---------------------------------------------------------------------------
  // MCP errors (600–699)
  // ---------------------------------------------------------------------------
  static const String mcpConnectionFailed = 'mcp_connection_failed';
  static const String mcpServerCrashed = 'mcp_server_crashed';
  static const String mcpProtocolError = 'mcp_protocol_error';
  static const String mcpToolNotFound = 'mcp_tool_not_found';
  static const String mcpTimeout = 'mcp_timeout';
  static const String mcpConfigInvalid = 'mcp_config_invalid';

  // ---------------------------------------------------------------------------
  // Config errors (700–799)
  // ---------------------------------------------------------------------------
  static const String configInvalid = 'config_invalid';
  static const String configReadFailed = 'config_read_failed';
  static const String configWriteFailed = 'config_write_failed';
  static const String configMigrationFailed = 'config_migration_failed';

  // ---------------------------------------------------------------------------
  // Hook errors (800–899)
  // ---------------------------------------------------------------------------
  static const String hookFailed = 'hook_failed';
  static const String hookTimeout = 'hook_timeout';
  static const String hookInvalidConfig = 'hook_invalid_config';

  // ---------------------------------------------------------------------------
  // General / uncategorised errors (900–999)
  // ---------------------------------------------------------------------------
  static const String unknownError = 'unknown_error';
  static const String internalError = 'internal_error';
  static const String compactionFailed = 'compaction_failed';
  static const String serializationError = 'serialization_error';
  static const String migrationError = 'migration_error';
  static const String platformUnsupported = 'platform_unsupported';
}
