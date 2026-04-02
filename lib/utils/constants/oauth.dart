// OAuth configuration constants — ported from OpenClaude src/constants/oauth.ts.

const String claudeAiInferenceScope = 'user:inference';
const String claudeAiProfileScope = 'user:profile';
const String oauthBetaHeader = 'oauth-2025-04-20';

const List<String> consoleOauthScopes = [
  'org:create_api_key',
  'user:profile',
];

const List<String> claudeAiOauthScopes = [
  'user:profile',
  'user:inference',
  'user:sessions:claude_code',
  'user:mcp_servers',
  'user:file_upload',
];

const String oauthClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

const String consoleAuthorizeUrl = 'https://platform.claude.com/oauth/authorize';
const String claudeAiAuthorizeUrl = 'https://claude.com/cai/oauth/authorize';
const String oauthTokenUrl = 'https://platform.claude.com/v1/oauth/token';
const String oauthManualRedirectUrl =
    'https://platform.claude.com/oauth/code/callback';

const String mcpClientMetadataUrl =
    'https://claude.ai/oauth/claude-code-client-metadata';
const String mcpProxyUrl = 'https://mcp-proxy.anthropic.com';
const String mcpProxyPath = '/v1/mcp/{server_id}';
