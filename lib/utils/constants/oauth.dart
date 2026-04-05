// OAuth configuration constants — ported from Neomage src/constants/oauth.ts.

const String neomageAiInferenceScope = 'user:inference';
const String neomageAiProfileScope = 'user:profile';
const String oauthBetaHeader = 'oauth-2025-04-20';

const List<String> consoleOauthScopes = ['org:create_api_key', 'user:profile'];

const List<String> neomageAiOauthScopes = [
  'user:profile',
  'user:inference',
  'user:sessions:neomage',
  'user:mcp_servers',
  'user:file_upload',
];

const String oauthClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

const String consoleAuthorizeUrl =
    'https://platform.neomage.com/oauth/authorize';
const String neomageAiAuthorizeUrl =
    'https://neomage.com/cai/oauth/authorize';
const String oauthTokenUrl = 'https://platform.neomage.com/v1/oauth/token';
const String oauthManualRedirectUrl =
    'https://platform.neomage.com/oauth/code/callback';

const String mcpClientMetadataUrl =
    'https://neomage.ai/oauth/neomage-client-metadata';
const String mcpProxyUrl = 'https://mcp-proxy.anthropic.com';
const String mcpProxyPath = '/v1/mcp/{server_id}';
