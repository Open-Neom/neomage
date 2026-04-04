// Provider profile management — port of:
//   neom_claw/src/utils/providerProfile.ts (314 LOC)
//   neom_claw/src/utils/providerRecommendation.ts (317 LOC)
//   neom_claw/src/utils/api.ts (718 LOC)
//
// Provider profile building for OpenAI/Ollama/Codex/Gemini,
// Ollama model recommendation and ranking, API schema generation,
// system prompt splitting, tool input normalization, and context helpers.

// ═══════════════════════════════════════════════════════════════════
// Provider Profile Types
// ═══════════════════════════════════════════════════════════════════

/// Supported provider profiles.
enum ProviderProfile { openai, ollama, codex, gemini }

/// Environment variables for a provider profile.
class ProfileEnv {
  final String? openaiBaseUrl;
  final String? openaiModel;
  final String? openaiApiKey;
  final String? codexApiKey;
  final String? chatgptAccountId;
  final String? codexAccountId;
  final String? geminiApiKey;
  final String? geminiModel;
  final String? geminiBaseUrl;

  const ProfileEnv({
    this.openaiBaseUrl,
    this.openaiModel,
    this.openaiApiKey,
    this.codexApiKey,
    this.chatgptAccountId,
    this.codexAccountId,
    this.geminiApiKey,
    this.geminiModel,
    this.geminiBaseUrl,
  });

  factory ProfileEnv.fromJson(Map<String, dynamic> json) => ProfileEnv(
    openaiBaseUrl: json['OPENAI_BASE_URL'] as String?,
    openaiModel: json['OPENAI_MODEL'] as String?,
    openaiApiKey: json['OPENAI_API_KEY'] as String?,
    codexApiKey: json['CODEX_API_KEY'] as String?,
    chatgptAccountId: json['CHATGPT_ACCOUNT_ID'] as String?,
    codexAccountId: json['CODEX_ACCOUNT_ID'] as String?,
    geminiApiKey: json['GEMINI_API_KEY'] as String?,
    geminiModel: json['GEMINI_MODEL'] as String?,
    geminiBaseUrl: json['GEMINI_BASE_URL'] as String?,
  );

  Map<String, dynamic> toJson() => {
    if (openaiBaseUrl != null) 'OPENAI_BASE_URL': openaiBaseUrl,
    if (openaiModel != null) 'OPENAI_MODEL': openaiModel,
    if (openaiApiKey != null) 'OPENAI_API_KEY': openaiApiKey,
    if (codexApiKey != null) 'CODEX_API_KEY': codexApiKey,
    if (chatgptAccountId != null) 'CHATGPT_ACCOUNT_ID': chatgptAccountId,
    if (codexAccountId != null) 'CODEX_ACCOUNT_ID': codexAccountId,
    if (geminiApiKey != null) 'GEMINI_API_KEY': geminiApiKey,
    if (geminiModel != null) 'GEMINI_MODEL': geminiModel,
    if (geminiBaseUrl != null) 'GEMINI_BASE_URL': geminiBaseUrl,
  };
}

/// Persisted profile file structure.
class ProfileFile {
  final ProviderProfile profile;
  final ProfileEnv env;
  final String createdAt;

  const ProfileFile({
    required this.profile,
    required this.env,
    required this.createdAt,
  });

  factory ProfileFile.fromJson(Map<String, dynamic> json) => ProfileFile(
    profile: ProviderProfile.values.firstWhere(
      (e) => e.name == json['profile'],
      orElse: () => ProviderProfile.openai,
    ),
    env: ProfileEnv.fromJson(json['env'] as Map<String, dynamic>? ?? {}),
    createdAt: json['createdAt'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {
    'profile': profile.name,
    'env': env.toJson(),
    'createdAt': createdAt,
  };
}

/// Resolved codex credentials.
class CodexCredentials {
  final String? apiKey;
  final String? accountId;
  const CodexCredentials({this.apiKey, this.accountId});
}

/// Callback type for resolving provider transport.
typedef ProviderRequestResolver =
    String Function({
      String? model,
      String? baseUrl,
      required String fallbackModel,
    });

/// Callback type for resolving codex API credentials.
typedef CodexCredentialResolver =
    CodexCredentials? Function({
      String? codexApiKey,
      Map<String, String>? processEnv,
    });

// ═══════════════════════════════════════════════════════════════════
// Constants
// ═══════════════════════════════════════════════════════════════════

const _defaultGeminiBaseUrl =
    'https://generativelanguage.googleapis.com/v1beta/openai';
const _defaultGeminiModel = 'gemini-2.0-flash';
const _defaultOpenaiBaseUrl = 'https://api.openai.com/v1';
const _defaultCodexBaseUrl = 'https://api.codex.com/v1';

// ═══════════════════════════════════════════════════════════════════
// API Key Sanitization
// ═══════════════════════════════════════════════════════════════════

/// Sanitize an API key, returning null for empty or placeholder values.
String? sanitizeApiKey(String? key) {
  if (key == null || key.isEmpty || key == 'SUA_CHAVE') return null;
  return key;
}

// ═══════════════════════════════════════════════════════════════════
// Profile Environment Builders
// ═══════════════════════════════════════════════════════════════════

/// Build an Ollama profile environment.
ProfileEnv buildOllamaProfileEnv({
  required String model,
  String? baseUrl,
  required String Function(String? baseUrl) getOllamaChatBaseUrl,
}) {
  return ProfileEnv(
    openaiBaseUrl: getOllamaChatBaseUrl(baseUrl),
    openaiModel: model,
  );
}

/// Build a Gemini profile environment. Returns null if no API key found.
ProfileEnv? buildGeminiProfileEnv({
  String? model,
  String? baseUrl,
  String? apiKey,
  Map<String, String>? processEnv,
}) {
  final env = processEnv ?? const {};
  final key = sanitizeApiKey(
    apiKey ?? env['GEMINI_API_KEY'] ?? env['GOOGLE_API_KEY'],
  );
  if (key == null) return null;

  return ProfileEnv(
    geminiModel: model ?? env['GEMINI_MODEL'] ?? _defaultGeminiModel,
    geminiApiKey: key,
    geminiBaseUrl: _firstNonEmpty([baseUrl, env['GEMINI_BASE_URL']]),
  );
}

/// Build an OpenAI profile environment. Returns null if no API key found.
ProfileEnv? buildOpenAIProfileEnv({
  required RecommendationGoal goal,
  String? model,
  String? baseUrl,
  String? apiKey,
  Map<String, String>? processEnv,
  ProviderRequestResolver? resolveProviderRequest,
}) {
  final env = processEnv ?? const {};
  final key = sanitizeApiKey(apiKey ?? env['OPENAI_API_KEY']);
  if (key == null) return null;

  final defaultModel = getGoalDefaultOpenAIModel(goal);
  final resolvedTransport = resolveProviderRequest != null
      ? resolveProviderRequest(
          model: env['OPENAI_MODEL'],
          baseUrl: env['OPENAI_BASE_URL'],
          fallbackModel: defaultModel,
        )
      : 'chat_completions';
  final useShellOpenAIConfig = resolvedTransport == 'chat_completions';

  return ProfileEnv(
    openaiBaseUrl:
        _firstNonEmpty([
          baseUrl,
          useShellOpenAIConfig ? env['OPENAI_BASE_URL'] : null,
        ]) ??
        _defaultOpenaiBaseUrl,
    openaiModel:
        _firstNonEmpty([
          model,
          useShellOpenAIConfig ? env['OPENAI_MODEL'] : null,
        ]) ??
        defaultModel,
    openaiApiKey: key,
  );
}

/// Build a Codex profile environment. Returns null if credentials unavailable.
ProfileEnv? buildCodexProfileEnv({
  String? model,
  String? baseUrl,
  String? apiKey,
  Map<String, String>? processEnv,
  CodexCredentialResolver? resolveCodexApiCredentials,
}) {
  final env = processEnv ?? const {};
  final key = sanitizeApiKey(apiKey ?? env['CODEX_API_KEY']);

  final credentials = resolveCodexApiCredentials != null
      ? resolveCodexApiCredentials(codexApiKey: key, processEnv: env)
      : null;

  if (credentials == null ||
      credentials.apiKey == null ||
      credentials.accountId == null) {
    return null;
  }

  return ProfileEnv(
    openaiBaseUrl: _firstNonEmpty([baseUrl]) ?? _defaultCodexBaseUrl,
    openaiModel: _firstNonEmpty([model]) ?? 'codexplan',
    codexApiKey: key,
    chatgptAccountId: credentials.accountId,
  );
}

/// Create a profile file with current timestamp.
ProfileFile createProfileFile({
  required ProviderProfile profile,
  required ProfileEnv env,
}) {
  return ProfileFile(
    profile: profile,
    env: env,
    createdAt: DateTime.now().toIso8601String(),
  );
}

/// Select auto profile based on recommended Ollama model availability.
ProviderProfile selectAutoProfile({required String? recommendedOllamaModel}) {
  return recommendedOllamaModel != null
      ? ProviderProfile.ollama
      : ProviderProfile.openai;
}

/// Build the full launch environment for a given profile.
///
/// Merges process env, persisted profile, and profile-specific defaults.
/// Cleans up keys that don't belong to the chosen profile.
Future<Map<String, String>> buildLaunchEnv({
  required ProviderProfile profile,
  required ProfileFile? persisted,
  required RecommendationGoal goal,
  Map<String, String>? processEnv,
  String Function(String? baseUrl)? getOllamaChatBaseUrl,
  Future<String> Function(RecommendationGoal goal)? resolveOllamaDefaultModel,
  ProviderRequestResolver? resolveProviderRequest,
  CodexCredentialResolver? resolveCodexApiCredentials,
  bool Function(String url)? isCodexBaseUrl,
}) async {
  final env = Map<String, String>.from(processEnv ?? {});
  final persistedEnv = (persisted?.profile == profile)
      ? persisted!.env
      : const ProfileEnv();

  final shellGeminiKey = sanitizeApiKey(
    env['GEMINI_API_KEY'] ?? env['GOOGLE_API_KEY'],
  );
  final persistedGeminiKey = sanitizeApiKey(persistedEnv.geminiApiKey);

  // ── Gemini ──
  if (profile == ProviderProfile.gemini) {
    env['NEOMCLAW_USE_GEMINI'] = '1';
    env.remove('NEOMCLAW_USE_OPENAI');
    env['GEMINI_MODEL'] =
        env['GEMINI_MODEL'] ?? persistedEnv.geminiModel ?? _defaultGeminiModel;
    env['GEMINI_BASE_URL'] =
        env['GEMINI_BASE_URL'] ??
        persistedEnv.geminiBaseUrl ??
        _defaultGeminiBaseUrl;
    final geminiKey = shellGeminiKey ?? persistedGeminiKey;
    if (geminiKey != null) {
      env['GEMINI_API_KEY'] = geminiKey;
    } else {
      env.remove('GEMINI_API_KEY');
    }
    _removeKeys(env, [
      'GOOGLE_API_KEY',
      'OPENAI_BASE_URL',
      'OPENAI_MODEL',
      'OPENAI_API_KEY',
      'CODEX_API_KEY',
      'CHATGPT_ACCOUNT_ID',
      'CODEX_ACCOUNT_ID',
    ]);
    return env;
  }

  // ── OpenAI-compatible profiles ──
  env['NEOMCLAW_USE_OPENAI'] = '1';
  _removeKeys(env, [
    'NEOMCLAW_USE_GEMINI',
    'GEMINI_API_KEY',
    'GEMINI_MODEL',
    'GEMINI_BASE_URL',
    'GOOGLE_API_KEY',
  ]);

  if (profile == ProviderProfile.ollama) {
    final getBaseUrl =
        getOllamaChatBaseUrl ?? ((_) => 'http://localhost:11434/v1');
    final resolveModel =
        resolveOllamaDefaultModel ?? ((_) async => 'llama3.1:8b');
    env['OPENAI_BASE_URL'] = persistedEnv.openaiBaseUrl ?? getBaseUrl(null);
    env['OPENAI_MODEL'] = persistedEnv.openaiModel ?? await resolveModel(goal);
    _removeKeys(env, [
      'OPENAI_API_KEY',
      'CODEX_API_KEY',
      'CHATGPT_ACCOUNT_ID',
      'CODEX_ACCOUNT_ID',
    ]);
    return env;
  }

  if (profile == ProviderProfile.codex) {
    final isCodex = isCodexBaseUrl ?? (_) => false;
    env['OPENAI_BASE_URL'] =
        (persistedEnv.openaiBaseUrl != null &&
            isCodex(persistedEnv.openaiBaseUrl!))
        ? persistedEnv.openaiBaseUrl!
        : _defaultCodexBaseUrl;
    env['OPENAI_MODEL'] = persistedEnv.openaiModel ?? 'codexplan';
    env.remove('OPENAI_API_KEY');

    final codexKey =
        sanitizeApiKey(env['CODEX_API_KEY']) ??
        sanitizeApiKey(persistedEnv.codexApiKey);
    final codexAccountId =
        env['CHATGPT_ACCOUNT_ID'] ??
        env['CODEX_ACCOUNT_ID'] ??
        persistedEnv.chatgptAccountId ??
        persistedEnv.codexAccountId;

    _setOrRemove(env, 'CODEX_API_KEY', codexKey);
    _setOrRemove(env, 'CHATGPT_ACCOUNT_ID', codexAccountId);
    env.remove('CODEX_ACCOUNT_ID');
    return env;
  }

  // ── Default: OpenAI profile ──
  final defaultOpenAIModel = getGoalDefaultOpenAIModel(goal);
  final shellTransport = resolveProviderRequest != null
      ? resolveProviderRequest(
          model: env['OPENAI_MODEL'],
          baseUrl: env['OPENAI_BASE_URL'],
          fallbackModel: defaultOpenAIModel,
        )
      : 'chat_completions';
  final persistedTransport = resolveProviderRequest != null
      ? resolveProviderRequest(
          model: persistedEnv.openaiModel,
          baseUrl: persistedEnv.openaiBaseUrl,
          fallbackModel: defaultOpenAIModel,
        )
      : 'chat_completions';

  final useShellConfig = shellTransport == 'chat_completions';
  final usePersistedConfig =
      (persistedEnv.openaiModel == null &&
          persistedEnv.openaiBaseUrl == null) ||
      persistedTransport == 'chat_completions';

  env['OPENAI_BASE_URL'] =
      (useShellConfig ? env['OPENAI_BASE_URL'] : null) ??
      (usePersistedConfig ? persistedEnv.openaiBaseUrl : null) ??
      _defaultOpenaiBaseUrl;
  env['OPENAI_MODEL'] =
      (useShellConfig ? env['OPENAI_MODEL'] : null) ??
      (usePersistedConfig ? persistedEnv.openaiModel : null) ??
      defaultOpenAIModel;
  env['OPENAI_API_KEY'] =
      env['OPENAI_API_KEY'] ?? persistedEnv.openaiApiKey ?? '';
  _removeKeys(env, ['CODEX_API_KEY', 'CHATGPT_ACCOUNT_ID', 'CODEX_ACCOUNT_ID']);
  return env;
}

// ═══════════════════════════════════════════════════════════════════
// Ollama Model Recommendation
// ═══════════════════════════════════════════════════════════════════

/// Recommendation goal for model selection.
enum RecommendationGoal { latency, balanced, coding }

/// Ollama model descriptor.
class OllamaModelDescriptor {
  final String name;
  final int? sizeBytes;
  final String? family;
  final List<String>? families;
  final String? parameterSize;
  final String? quantizationLevel;

  const OllamaModelDescriptor({
    required this.name,
    this.sizeBytes,
    this.family,
    this.families,
    this.parameterSize,
    this.quantizationLevel,
  });

  factory OllamaModelDescriptor.fromJson(Map<String, dynamic> json) =>
      OllamaModelDescriptor(
        name: json['name'] as String,
        sizeBytes: json['sizeBytes'] as int?,
        family: json['family'] as String?,
        families: (json['families'] as List?)?.cast<String>(),
        parameterSize: json['parameterSize'] as String?,
        quantizationLevel: json['quantizationLevel'] as String?,
      );
}

/// Ranked Ollama model with score and reasons.
class RankedOllamaModel extends OllamaModelDescriptor {
  final double score;
  final List<String> reasons;
  final String summary;

  const RankedOllamaModel({
    required super.name,
    super.sizeBytes,
    super.family,
    super.families,
    super.parameterSize,
    super.quantizationLevel,
    required this.score,
    required this.reasons,
    required this.summary,
  });
}

/// Benchmarked Ollama model with latency data.
class BenchmarkedOllamaModel extends RankedOllamaModel {
  final int? benchmarkMs;

  const BenchmarkedOllamaModel({
    required super.name,
    super.sizeBytes,
    super.family,
    super.families,
    super.parameterSize,
    super.quantizationLevel,
    required super.score,
    required super.reasons,
    required super.summary,
    this.benchmarkMs,
  });
}

// ── Recommendation Constants ──

const _codingHints = [
  'coder',
  'codellama',
  'codegemma',
  'codestral',
  'devstral',
  'starcoder',
  'deepseek-coder',
  'qwen2.5-coder',
  'qwen-coder',
];

const _generalHints = ['llama', 'qwen', 'mistral', 'gemma', 'phi', 'deepseek'];

const _instructHints = ['instruct', 'chat', 'assistant'];
const _nonChatHints = ['embed', 'embedding', 'rerank', 'bge', 'whisper'];

// ── Recommendation Helpers ──

/// Build a searchable haystack string from model metadata.
String _modelHaystack(OllamaModelDescriptor model) {
  return [
    model.name,
    model.family ?? '',
    ...(model.families ?? []),
    model.parameterSize ?? '',
    model.quantizationLevel ?? '',
  ].join(' ').toLowerCase();
}

/// Check if text contains any of the needles.
bool _includesAny(String text, List<String> needles) {
  return needles.any((n) => text.contains(n));
}

/// Check if a model is viable for chat (not embedding/reranking).
bool isViableOllamaChatModel(OllamaModelDescriptor model) {
  return !_includesAny(_modelHaystack(model), _nonChatHints);
}

/// Select the first viable chat model from a list.
T? selectRecommendedOllamaModel<T extends OllamaModelDescriptor>(
  List<T> models,
) {
  for (final model in models) {
    if (isViableOllamaChatModel(model)) return model;
  }
  return null;
}

/// Infer parameter count in billions from model metadata.
double? _inferParameterBillions(OllamaModelDescriptor model) {
  final text = '${model.parameterSize ?? ''} ${model.name}'.toLowerCase();
  final match = RegExp(r'(\d+(?:\.\d+)?)\s*b\b').firstMatch(text);
  if (match != null && match.group(1) != null) {
    return double.tryParse(match.group(1)!);
  }
  if (model.sizeBytes != null && model.sizeBytes! > 0) {
    return double.parse((model.sizeBytes! / 1e9).toStringAsFixed(1));
  }
  return null;
}

/// Get quantization bucket string for scoring.
String _quantizationBucket(OllamaModelDescriptor model) {
  return (model.quantizationLevel ?? model.name).toLowerCase();
}

/// Score a model's size tier for a given goal.
double _scoreSizeTier(
  double? paramsB,
  RecommendationGoal goal,
  List<String> reasons,
) {
  if (paramsB == null) {
    reasons.add('unknown size');
    return 0;
  }

  if (goal == RecommendationGoal.latency) {
    if (paramsB <= 4) {
      reasons.add('tiny model for low latency');
      return 32;
    }
    if (paramsB <= 8) {
      reasons.add('small model for fast responses');
      return 26;
    }
    if (paramsB <= 14) {
      reasons.add('mid-sized model with acceptable latency');
      return 16;
    }
    if (paramsB <= 24) {
      reasons.add('larger model may be slower');
      return 8;
    }
    reasons.add('large model likely slower locally');
    return paramsB <= 40 ? 0 : -8;
  }

  if (goal == RecommendationGoal.coding) {
    if (paramsB >= 7 && paramsB <= 14) {
      reasons.add('strong coding size tier');
      return 24;
    }
    if (paramsB > 14 && paramsB <= 34) {
      reasons.add('large coding-capable size tier');
      return 28;
    }
    if (paramsB > 34) {
      reasons.add('very large model with higher quality potential');
      return 18;
    }
    reasons.add('compact model may trade off coding depth');
    return 12;
  }

  // Balanced goal.
  if (paramsB >= 7 && paramsB <= 14) {
    reasons.add('great balanced size tier');
    return 26;
  }
  if (paramsB >= 3 && paramsB < 7) {
    reasons.add('compact balanced size tier');
    return 18;
  }
  if (paramsB > 14 && paramsB <= 24) {
    reasons.add('high quality balanced size tier');
    return 20;
  }
  if (paramsB > 24) {
    reasons.add('large model for quality-first usage');
    return 10;
  }
  reasons.add('very small model for general usage');
  return 8;
}

/// Score quantization level.
double _scoreQuantization(
  OllamaModelDescriptor model,
  RecommendationGoal goal,
  List<String> reasons,
) {
  final quant = _quantizationBucket(model);
  if (quant.contains('q4')) {
    reasons.add('efficient Q4 quantization');
    return goal == RecommendationGoal.latency ? 8 : 4;
  }
  if (quant.contains('q5')) {
    reasons.add('balanced Q5 quantization');
    return goal == RecommendationGoal.latency ? 6 : 5;
  }
  if (quant.contains('q8')) {
    reasons.add('higher quality Q8 quantization');
    return goal == RecommendationGoal.latency ? 2 : 5;
  }
  return 0;
}

/// Compare two ranked models for sorting.
int _compareRankedModels(
  RankedOllamaModel a,
  RankedOllamaModel b,
  RecommendationGoal goal,
) {
  if (b.score != a.score) return b.score.compareTo(a.score);

  final aSize = _inferParameterBillions(a) ?? double.infinity;
  final bSize = _inferParameterBillions(b) ?? double.infinity;

  if (goal == RecommendationGoal.latency) return aSize.compareTo(bSize);
  if (goal == RecommendationGoal.coding) return bSize.compareTo(aSize);

  const target = 14.0;
  return (aSize - target).abs().compareTo((bSize - target).abs());
}

/// Normalize a recommendation goal string to enum.
RecommendationGoal normalizeRecommendationGoal(String? goal) {
  switch (goal?.trim().toLowerCase()) {
    case 'latency':
      return RecommendationGoal.latency;
    case 'coding':
      return RecommendationGoal.coding;
    case 'balanced':
    default:
      return RecommendationGoal.balanced;
  }
}

/// Get the default OpenAI model for a goal.
String getGoalDefaultOpenAIModel(RecommendationGoal goal) {
  switch (goal) {
    case RecommendationGoal.latency:
      return 'gpt-4o-mini';
    case RecommendationGoal.coding:
    case RecommendationGoal.balanced:
      return 'gpt-4o';
  }
}

/// Rank Ollama models by composite score for a given goal.
List<RankedOllamaModel> rankOllamaModels({
  required List<OllamaModelDescriptor> models,
  required RecommendationGoal goal,
}) {
  final ranked = models.map((model) {
    final haystack = _modelHaystack(model);
    final reasons = <String>[];
    var score = 0.0;

    if (_includesAny(haystack, _nonChatHints)) {
      score -= 40;
      reasons.add('not a chat-first model');
    }
    if (_includesAny(haystack, _codingHints)) {
      score += goal == RecommendationGoal.coding
          ? 24
          : goal == RecommendationGoal.balanced
          ? 10
          : 4;
      reasons.add('coding-oriented model family');
    }
    if (_includesAny(haystack, _generalHints)) {
      score += goal == RecommendationGoal.latency
          ? 4
          : goal == RecommendationGoal.coding
          ? 6
          : 8;
      reasons.add('strong general-purpose model family');
    }
    if (_includesAny(haystack, _instructHints)) {
      score += goal == RecommendationGoal.latency ? 2 : 6;
      reasons.add('chat/instruct tuned');
    }
    if (haystack.contains('vision') || haystack.contains('vl')) {
      score -= 2;
      reasons.add('vision model adds extra overhead');
    }

    score += _scoreSizeTier(_inferParameterBillions(model), goal, reasons);
    score += _scoreQuantization(model, goal, reasons);

    return RankedOllamaModel(
      name: model.name,
      sizeBytes: model.sizeBytes,
      family: model.family,
      families: model.families,
      parameterSize: model.parameterSize,
      quantizationLevel: model.quantizationLevel,
      score: score,
      reasons: reasons,
      summary: reasons.take(3).join(', '),
    );
  }).toList();

  ranked.sort((a, b) => _compareRankedModels(a, b, goal));
  return ranked;
}

/// Recommend the best Ollama model for a given goal.
RankedOllamaModel? recommendOllamaModel({
  required List<OllamaModelDescriptor> models,
  required RecommendationGoal goal,
}) {
  return selectRecommendedOllamaModel(
    rankOllamaModels(models: models, goal: goal),
  );
}

/// Apply benchmark latency data to ranked models, re-sort by adjusted score.
List<BenchmarkedOllamaModel> applyBenchmarkLatency({
  required List<RankedOllamaModel> models,
  required Map<String, int?> benchmarkMs,
  required RecommendationGoal goal,
}) {
  final divisor = goal == RecommendationGoal.latency
      ? 120.0
      : goal == RecommendationGoal.coding
      ? 500.0
      : 240.0;

  final scoredModels = models.map((model) {
    final latency = benchmarkMs[model.name];
    final penalty = latency == null ? 0.0 : latency / divisor;
    final reasons = latency == null
        ? model.reasons
        : ['benchmarked at ${latency}ms', ...model.reasons];

    return BenchmarkedOllamaModel(
      name: model.name,
      sizeBytes: model.sizeBytes,
      family: model.family,
      families: model.families,
      parameterSize: model.parameterSize,
      quantizationLevel: model.quantizationLevel,
      benchmarkMs: latency,
      reasons: reasons,
      summary: reasons.take(3).join(', '),
      score: double.parse((model.score - penalty).toStringAsFixed(2)),
    );
  }).toList();

  final benchmarked = scoredModels.where((m) => m.benchmarkMs != null).toList();
  if (benchmarked.isEmpty) {
    scoredModels.sort((a, b) => _compareRankedModels(a, b, goal));
    return scoredModels;
  }

  final unbenchmarked = scoredModels
      .where((m) => m.benchmarkMs == null)
      .toList();
  benchmarked.sort((a, b) => _compareRankedModels(a, b, goal));
  return [...benchmarked, ...unbenchmarked];
}

// ═══════════════════════════════════════════════════════════════════
// API Schema Types (from api.ts)
// ═══════════════════════════════════════════════════════════════════

/// Cache scope for system prompt blocks.
enum CacheScope { global, org }

/// A block of system prompt text with cache scope.
class SystemPromptBlock {
  final String text;
  final CacheScope? cacheScope;
  const SystemPromptBlock({required this.text, this.cacheScope});
}

/// System prompt is a list of strings.
typedef SystemPrompt = List<String>;

// ═══════════════════════════════════════════════════════════════════
// System Prompt Splitting
// ═══════════════════════════════════════════════════════════════════

/// Split system prompt blocks by content type for API cache control.
///
/// Modes:
/// 1. skipGlobalCache + useGlobalCache: up to 3 blocks, org-level caching.
/// 2. useGlobalCache + dynamicBoundary found: up to 4 blocks with global cache.
/// 3. Default: up to 3 blocks with org-level caching.
List<SystemPromptBlock> splitSysPromptPrefix({
  required SystemPrompt systemPrompt,
  bool skipGlobalCacheForSystemPrompt = false,
  bool useGlobalCacheFeature = false,
  String? dynamicBoundary,
  Set<String>? cliSyspromptPrefixes,
}) {
  final prefixes = cliSyspromptPrefixes ?? {};

  // Mode 1: MCP tools present — skip global cache on system prompt.
  if (useGlobalCacheFeature && skipGlobalCacheForSystemPrompt) {
    String? attributionHeader;
    String? systemPromptPrefix;
    final rest = <String>[];

    for (final prompt in systemPrompt) {
      if (prompt.isEmpty || prompt == dynamicBoundary) continue;
      if (prompt.startsWith('x-anthropic-billing-header')) {
        attributionHeader = prompt;
      } else if (prefixes.contains(prompt)) {
        systemPromptPrefix = prompt;
      } else {
        rest.add(prompt);
      }
    }

    return [
      if (attributionHeader != null)
        SystemPromptBlock(text: attributionHeader, cacheScope: null),
      if (systemPromptPrefix != null)
        SystemPromptBlock(text: systemPromptPrefix, cacheScope: CacheScope.org),
      if (rest.isNotEmpty)
        SystemPromptBlock(text: rest.join('\n\n'), cacheScope: CacheScope.org),
    ];
  }

  // Mode 2: Global cache with dynamic boundary marker.
  if (useGlobalCacheFeature && dynamicBoundary != null) {
    final boundaryIndex = systemPrompt.indexWhere((s) => s == dynamicBoundary);
    if (boundaryIndex != -1) {
      String? attributionHeader;
      String? systemPromptPrefix;
      final staticBlocks = <String>[];
      final dynamicBlocks = <String>[];

      for (var i = 0; i < systemPrompt.length; i++) {
        final block = systemPrompt[i];
        if (block.isEmpty || block == dynamicBoundary) continue;
        if (block.startsWith('x-anthropic-billing-header')) {
          attributionHeader = block;
        } else if (prefixes.contains(block)) {
          systemPromptPrefix = block;
        } else if (i < boundaryIndex) {
          staticBlocks.add(block);
        } else {
          dynamicBlocks.add(block);
        }
      }

      return [
        if (attributionHeader != null)
          SystemPromptBlock(text: attributionHeader, cacheScope: null),
        if (systemPromptPrefix != null)
          SystemPromptBlock(text: systemPromptPrefix, cacheScope: null),
        if (staticBlocks.isNotEmpty)
          SystemPromptBlock(
            text: staticBlocks.join('\n\n'),
            cacheScope: CacheScope.global,
          ),
        if (dynamicBlocks.isNotEmpty)
          SystemPromptBlock(text: dynamicBlocks.join('\n\n'), cacheScope: null),
      ];
    }
  }

  // Mode 3: Default — org-level caching.
  String? attributionHeader;
  String? systemPromptPrefix;
  final rest = <String>[];

  for (final block in systemPrompt) {
    if (block.isEmpty) continue;
    if (block.startsWith('x-anthropic-billing-header')) {
      attributionHeader = block;
    } else if (prefixes.contains(block)) {
      systemPromptPrefix = block;
    } else {
      rest.add(block);
    }
  }

  return [
    if (attributionHeader != null)
      SystemPromptBlock(text: attributionHeader, cacheScope: null),
    if (systemPromptPrefix != null)
      SystemPromptBlock(text: systemPromptPrefix, cacheScope: CacheScope.org),
    if (rest.isNotEmpty)
      SystemPromptBlock(text: rest.join('\n\n'), cacheScope: CacheScope.org),
  ];
}

// ═══════════════════════════════════════════════════════════════════
// Context Helpers
// ═══════════════════════════════════════════════════════════════════

/// Append system context entries to the system prompt.
List<String> appendSystemContext({
  required SystemPrompt systemPrompt,
  required Map<String, String> context,
}) {
  return [
    ...systemPrompt,
    context.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
  ].where((s) => s.isNotEmpty).toList();
}

/// Prepend user context as a system-reminder message.
List<Map<String, dynamic>> prependUserContext({
  required List<Map<String, dynamic>> messages,
  required Map<String, String> context,
}) {
  if (context.isEmpty) return messages;

  final contextStr = context.entries
      .map((e) => '# ${e.key}\n${e.value}')
      .join('\n');

  final reminderMessage = <String, dynamic>{
    'type': 'user',
    'content':
        '<system-reminder>\nAs you answer the user\'s questions, you can use '
        'the following context:\n$contextStr\n\n'
        '      IMPORTANT: this context may or may not be relevant to your '
        'tasks. You should not respond to this context unless it is highly '
        'relevant to your task.\n</system-reminder>\n',
    'isMeta': true,
  };

  return [reminderMessage, ...messages];
}

// ═══════════════════════════════════════════════════════════════════
// Tool Input Normalization
// ═══════════════════════════════════════════════════════════════════

/// Normalize tool input for specific tools before execution.
///
/// Handles ExitPlanModeV2 plan injection, Bash command cleanup,
/// FileEdit normalization, FileWrite trailing whitespace, and
/// TaskOutput legacy parameter renaming.
Map<String, dynamic> normalizeToolInput({
  required String toolName,
  required Map<String, dynamic> input,
  String? cwd,
  String? agentId,
  Map<String, dynamic> Function(String? agentId)? getPlan,
}) {
  switch (toolName) {
    case 'ExitPlanModeV2':
      if (getPlan != null) {
        final plan = getPlan(agentId);
        return {...input, ...plan};
      }
      return input;

    case 'Bash':
      final command = input['command'] as String? ?? '';
      var normalized = command;
      if (cwd != null) {
        normalized = normalized.replaceAll('cd $cwd && ', '');
      }
      // Replace \\; with \; for find -exec commands.
      normalized = normalized.replaceAll(RegExp(r'\\\\;'), r'\;');
      return {
        'command': normalized,
        if (input['description'] != null) 'description': input['description'],
        if (input['timeout'] != null) 'timeout': input['timeout'],
        if (input['run_in_background'] != null)
          'run_in_background': input['run_in_background'],
        if (input['dangerouslyDisableSandbox'] != null)
          'dangerouslyDisableSandbox': input['dangerouslyDisableSandbox'],
      };

    case 'FileEdit':
      return {
        'file_path': input['file_path'],
        'old_string': input['old_string'],
        'new_string': input['new_string'],
        if (input['replace_all'] != null) 'replace_all': input['replace_all'],
      };

    case 'FileWrite':
      final filePath = input['file_path'] as String? ?? '';
      final content = input['content'] as String? ?? '';
      final isMarkdown = RegExp(
        r'\.(md|mdx)$',
        caseSensitive: false,
      ).hasMatch(filePath);
      return {
        'file_path': filePath,
        'content': isMarkdown ? content : _stripTrailingWhitespace(content),
      };

    case 'TaskOutput':
      final taskId =
          input['task_id'] ?? input['agentId'] ?? input['bash_id'] ?? '';
      final timeout =
          input['timeout'] ??
          ((input['wait_up_to'] is num)
              ? (input['wait_up_to'] as num).toInt() * 1000
              : 30000);
      return {
        'task_id': taskId,
        'block': input['block'] ?? true,
        'timeout': timeout,
      };

    default:
      return input;
  }
}

/// Strip injected fields before sending to API.
///
/// Removes plan/planFilePath from ExitPlanModeV2, and legacy synthetic
/// old_string/new_string from FileEdit when edits array is present.
Map<String, dynamic> normalizeToolInputForAPI({
  required String toolName,
  required Map<String, dynamic> input,
}) {
  switch (toolName) {
    case 'ExitPlanModeV2':
      final result = Map<String, dynamic>.from(input);
      result.remove('plan');
      result.remove('planFilePath');
      return result;

    case 'FileEdit':
      if (input.containsKey('edits')) {
        final result = Map<String, dynamic>.from(input);
        result.remove('old_string');
        result.remove('new_string');
        result.remove('replace_all');
        return result;
      }
      return input;

    default:
      return input;
  }
}

// ═══════════════════════════════════════════════════════════════════
// Private Helpers
// ═══════════════════════════════════════════════════════════════════

/// Strip trailing whitespace from each line.
String _stripTrailingWhitespace(String content) {
  return content.split('\n').map((line) => line.trimRight()).join('\n');
}

/// Return the first non-null, non-empty string from candidates.
String? _firstNonEmpty(List<String?> candidates) {
  for (final c in candidates) {
    if (c != null && c.isNotEmpty) return c;
  }
  return null;
}

/// Remove multiple keys from a map in one call.
void _removeKeys(Map<String, String> map, List<String> keys) {
  for (final key in keys) {
    map.remove(key);
  }
}

/// Set a key if value is non-null, otherwise remove it.
void _setOrRemove(Map<String, String> map, String key, String? value) {
  if (value != null) {
    map[key] = value;
  } else {
    map.remove(key);
  }
}
