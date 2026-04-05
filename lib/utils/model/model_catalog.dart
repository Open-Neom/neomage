// Model catalog — port of neomage/src/utils/model/.
// Model configs, pricing, capabilities, provider mappings, aliases.

/// API providers.
enum ModelProvider {
  firstParty, // Anthropic direct
  bedrock, // AWS Bedrock
  vertex, // Google Cloud Vertex AI
  foundry, // Anthropic Foundry
  openai, // OpenAI compatible
  gemini, // Google Gemini
}

/// Model family.
enum ModelFamily { opus, sonnet, haiku }

/// A model configuration across all providers.
class ModelConfig {
  final String id;
  final String displayName;
  final ModelFamily family;
  final Map<ModelProvider, String> providerIds;
  final int maxInputTokens;
  final int maxOutputTokens;
  final bool supportsThinking;
  final bool supportsImages;
  final bool supportsComputerUse;
  final bool supportsPdfInput;
  final bool supportsWebSearch;
  final bool supportsCaching;
  final bool supports1mContext;
  final DateTime? releaseDate;
  final bool deprecated;

  const ModelConfig({
    required this.id,
    required this.displayName,
    required this.family,
    required this.providerIds,
    this.maxInputTokens = 200000,
    this.maxOutputTokens = 8192,
    this.supportsThinking = true,
    this.supportsImages = true,
    this.supportsComputerUse = false,
    this.supportsPdfInput = true,
    this.supportsWebSearch = false,
    this.supportsCaching = true,
    this.supports1mContext = false,
    this.releaseDate,
    this.deprecated = false,
  });
}

/// Model pricing (per million tokens).
class ModelPricing {
  final double inputPerMillion;
  final double outputPerMillion;
  final double? cacheCreationPerMillion;
  final double? cacheReadPerMillion;

  const ModelPricing({
    required this.inputPerMillion,
    required this.outputPerMillion,
    this.cacheCreationPerMillion,
    this.cacheReadPerMillion,
  });
}

// ── Model Registry ──

/// All known model configurations.
final modelRegistry = <String, ModelConfig>{
  // Opus 4.6
  'claude-opus-4-6': ModelConfig(
    id: 'claude-opus-4-6',
    displayName: 'Opus 4.6',
    family: ModelFamily.opus,
    providerIds: {
      ModelProvider.firstParty: 'claude-opus-4-6-20250514',
      ModelProvider.bedrock: 'us.anthropic.claude-opus-4-6-v1:0',
      ModelProvider.vertex: 'claude-opus-4-6@20250514',
      ModelProvider.foundry: 'claude-opus-4-6',
    },
    maxInputTokens: 200000,
    maxOutputTokens: 16384,
    supportsThinking: true,
    supportsImages: true,
    supportsComputerUse: true,
    supportsWebSearch: true,
    supportsCaching: true,
    supports1mContext: true,
  ),

  // Sonnet 4.6
  'claude-sonnet-4-6': ModelConfig(
    id: 'claude-sonnet-4-6',
    displayName: 'Sonnet 4.6',
    family: ModelFamily.sonnet,
    providerIds: {
      ModelProvider.firstParty: 'claude-sonnet-4-6-20250514',
      ModelProvider.bedrock: 'us.anthropic.claude-sonnet-4-6-v1:0',
      ModelProvider.vertex: 'claude-sonnet-4-6@20250514',
      ModelProvider.foundry: 'claude-sonnet-4-6',
    },
    maxInputTokens: 200000,
    maxOutputTokens: 16384,
    supportsThinking: true,
    supportsImages: true,
    supportsComputerUse: true,
    supportsWebSearch: true,
    supportsCaching: true,
    supports1mContext: true,
  ),

  // Sonnet 4.5
  'claude-sonnet-4-5': ModelConfig(
    id: 'claude-sonnet-4-5',
    displayName: 'Sonnet 4.5',
    family: ModelFamily.sonnet,
    providerIds: {
      ModelProvider.firstParty: 'claude-sonnet-4-5-20250220',
      ModelProvider.bedrock: 'us.anthropic.claude-sonnet-4-5-v2:0',
      ModelProvider.vertex: 'claude-sonnet-4-5@20250220',
      ModelProvider.foundry: 'claude-sonnet-4-5',
    },
    maxInputTokens: 200000,
    maxOutputTokens: 16384,
    supportsThinking: true,
    supportsImages: true,
    supportsWebSearch: true,
    supportsCaching: true,
  ),

  // Haiku 3.5
  'claude-haiku-3-5': ModelConfig(
    id: 'claude-haiku-3-5',
    displayName: 'Haiku 3.5',
    family: ModelFamily.haiku,
    providerIds: {
      ModelProvider.firstParty: 'claude-3-5-haiku-20241022',
      ModelProvider.bedrock: 'us.anthropic.claude-3-5-haiku-20241022-v1:0',
      ModelProvider.vertex: 'claude-3-5-haiku@20241022',
      ModelProvider.foundry: 'claude-3-5-haiku',
    },
    maxInputTokens: 200000,
    maxOutputTokens: 8192,
    supportsThinking: false,
    supportsImages: true,
    supportsCaching: true,
  ),

  // OpenAI models
  'gpt-4o': ModelConfig(
    id: 'gpt-4o',
    displayName: 'GPT-4o',
    family: ModelFamily.sonnet, // Comparable tier
    providerIds: {ModelProvider.openai: 'gpt-4o'},
    maxInputTokens: 128000,
    maxOutputTokens: 16384,
    supportsThinking: false,
    supportsImages: true,
    supportsCaching: false,
  ),

  'gpt-4o-mini': ModelConfig(
    id: 'gpt-4o-mini',
    displayName: 'GPT-4o Mini',
    family: ModelFamily.haiku,
    providerIds: {ModelProvider.openai: 'gpt-4o-mini'},
    maxInputTokens: 128000,
    maxOutputTokens: 16384,
    supportsThinking: false,
    supportsImages: true,
    supportsCaching: false,
  ),

  // Gemini models
  'gemini-2.5-pro': ModelConfig(
    id: 'gemini-2.5-pro',
    displayName: 'Gemini 2.5 Pro',
    family: ModelFamily.opus,
    providerIds: {ModelProvider.gemini: 'gemini-2.5-pro-preview-03-25'},
    maxInputTokens: 1000000,
    maxOutputTokens: 65536,
    supportsThinking: true,
    supportsImages: true,
    supportsCaching: false,
  ),
};

/// Model pricing table.
final modelPricing = <String, ModelPricing>{
  'claude-opus-4-6': const ModelPricing(
    inputPerMillion: 15.0,
    outputPerMillion: 75.0,
    cacheCreationPerMillion: 18.75,
    cacheReadPerMillion: 1.50,
  ),
  'claude-sonnet-4-6': const ModelPricing(
    inputPerMillion: 3.0,
    outputPerMillion: 15.0,
    cacheCreationPerMillion: 3.75,
    cacheReadPerMillion: 0.30,
  ),
  'claude-sonnet-4-5': const ModelPricing(
    inputPerMillion: 3.0,
    outputPerMillion: 15.0,
    cacheCreationPerMillion: 3.75,
    cacheReadPerMillion: 0.30,
  ),
  'claude-haiku-3-5': const ModelPricing(
    inputPerMillion: 0.80,
    outputPerMillion: 4.0,
    cacheCreationPerMillion: 1.0,
    cacheReadPerMillion: 0.08,
  ),
  'gpt-4o': const ModelPricing(inputPerMillion: 2.50, outputPerMillion: 10.0),
  'gpt-4o-mini': const ModelPricing(
    inputPerMillion: 0.15,
    outputPerMillion: 0.60,
  ),
};

// ── Model Aliases ──

/// Model alias → canonical ID.
const modelAliases = <String, String>{
  'opus': 'claude-opus-4-6',
  'sonnet': 'claude-sonnet-4-6',
  'haiku': 'claude-haiku-3-5',
  'best': 'claude-opus-4-6',
  'fast': 'claude-haiku-3-5',
  'gpt4o': 'gpt-4o',
  'gpt4o-mini': 'gpt-4o-mini',
  'gemini': 'gemini-2.5-pro',
};

/// Family aliases (for allowlists).
const modelFamilyAliases = {'sonnet', 'opus', 'haiku'};

/// Resolve a model name (alias or ID) to a ModelConfig.
ModelConfig? resolveModel(String name) {
  final lower = name.toLowerCase().trim();

  // Direct lookup
  if (modelRegistry.containsKey(lower)) return modelRegistry[lower];

  // Alias lookup
  final aliasId = modelAliases[lower];
  if (aliasId != null) return modelRegistry[aliasId];

  // Partial match (e.g., "sonnet-4-6" → "claude-sonnet-4-6")
  for (final entry in modelRegistry.entries) {
    if (entry.key.contains(lower)) return entry.value;
    if (entry.value.displayName.toLowerCase().contains(lower)) {
      return entry.value;
    }
  }

  // Provider-specific ID match
  for (final entry in modelRegistry.entries) {
    for (final providerId in entry.value.providerIds.values) {
      if (providerId.contains(lower)) return entry.value;
    }
  }

  return null;
}

/// Get the provider-specific model ID.
String? getProviderModelId(ModelConfig config, ModelProvider provider) {
  return config.providerIds[provider];
}

/// Get display name for a model ID.
String getModelDisplayName(String modelId) {
  final config = resolveModel(modelId);
  if (config != null) return config.displayName;

  // Generate display name from ID
  return modelId
      .replaceAll('claude-', '')
      .replaceAll('-', ' ')
      .split(' ')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ── Cost Calculation ──

/// Token usage for cost calculation.
class TokenUsage {
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationTokens;
  final int cacheReadTokens;

  const TokenUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationTokens = 0,
    this.cacheReadTokens = 0,
  });

  TokenUsage operator +(TokenUsage other) => TokenUsage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cacheCreationTokens: cacheCreationTokens + other.cacheCreationTokens,
    cacheReadTokens: cacheReadTokens + other.cacheReadTokens,
  );

  int get totalTokens =>
      inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens;
}

/// Calculate cost from token usage.
double calculateCost(String modelId, TokenUsage usage) {
  final pricing = modelPricing[modelId];
  if (pricing == null) return 0.0;

  var cost = 0.0;
  cost += (usage.inputTokens / 1000000) * pricing.inputPerMillion;
  cost += (usage.outputTokens / 1000000) * pricing.outputPerMillion;

  if (pricing.cacheCreationPerMillion != null) {
    cost +=
        (usage.cacheCreationTokens / 1000000) *
        pricing.cacheCreationPerMillion!;
  }
  if (pricing.cacheReadPerMillion != null) {
    cost += (usage.cacheReadTokens / 1000000) * pricing.cacheReadPerMillion!;
  }

  return cost;
}

/// Format cost as a string.
String formatCost(double cost) {
  if (cost < 0.01) return '\$${cost.toStringAsFixed(4)}';
  if (cost < 1.0) return '\$${cost.toStringAsFixed(3)}';
  return '\$${cost.toStringAsFixed(2)}';
}

// ── Model Selection ──

/// Get the default model based on environment and settings.
String getDefaultModel({
  Map<String, String>? environment,
  Map<String, dynamic>? settings,
}) {
  // 1. Environment variable
  final envModel =
      environment?['ANTHROPIC_MODEL'] ??
      environment?['MAGE_MODEL'] ??
      environment?['GEMINI_MODEL'] ??
      environment?['OPENAI_MODEL'];
  if (envModel != null) return envModel;

  // 2. Settings
  final settingsModel = settings?['model'] as String?;
  if (settingsModel != null) return settingsModel;

  // 3. Default
  return 'claude-sonnet-4-6';
}

/// Check if a model is in the allowlist.
bool isModelAllowed(String modelId, List<String>? allowlist) {
  if (allowlist == null || allowlist.isEmpty) return true;

  final resolved = resolveModel(modelId);
  if (resolved == null) return false;

  for (final allowed in allowlist) {
    // Exact match
    if (allowed == modelId || allowed == resolved.id) return true;

    // Family alias match
    if (modelFamilyAliases.contains(allowed)) {
      if (resolved.family.name == allowed) return true;
    }

    // Provider ID match
    for (final providerId in resolved.providerIds.values) {
      if (providerId == allowed) return true;
    }
  }

  return false;
}

// ── Legacy Model Remapping ──

/// Remap deprecated model IDs to current versions.
String remapDeprecatedModel(String modelId) {
  const remaps = {
    'claude-3-opus': 'claude-opus-4-6',
    'claude-3-opus-20240229': 'claude-opus-4-6',
    'claude-3-5-sonnet': 'claude-sonnet-4-6',
    'claude-3-5-sonnet-20241022': 'claude-sonnet-4-6',
    'claude-3-5-sonnet-20240620': 'claude-sonnet-4-6',
    'claude-3-haiku': 'claude-haiku-3-5',
    'claude-3-haiku-20240307': 'claude-haiku-3-5',
  };

  return remaps[modelId] ?? modelId;
}
