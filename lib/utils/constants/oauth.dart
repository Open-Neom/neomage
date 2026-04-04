// OAuth configuration constants — ported from NeomClaw src/constants/oauth.ts.

const String neomClawAiInferenceScope = 'user:inference';
const String neomClawAiProfileScope = 'user:profile';
const String oauthBetaHeader = 'oauth-2025-04-20';

const List<String> consoleOauthScopes = ['org:create_api_key', 'user:profile'];

const List<String> neomClawAiOauthScopes = [
  'user:profile',
  'user:inference',
  'user:sessions:neomclaw',
  'user:mcp_servers',
  'user:file_upload',
];

const String oauthClientId = '9d1c250a-e61b-44d9-88ed-5944d1962f5e';

const String consoleAuthorizeUrl =
    'https://platform.neomclaw.com/oauth/authorize';
const String neomClawAiAuthorizeUrl =
    'https://neomclaw.com/cai/oauth/authorize';
const String oauthTokenUrl = 'https://platform.neomclaw.com/v1/oauth/token';
const String oauthManualRedirectUrl =
    'https://platform.neomclaw.com/oauth/code/callback';

const String mcpClientMetadataUrl =
    'https://neomclaw.ai/oauth/neom-claw-client-metadata';
const String mcpProxyUrl = 'https://mcp-proxy.anthropic.com';
const String mcpProxyPath = '/v1/mcp/{server_id}';
