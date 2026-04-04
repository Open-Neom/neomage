import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';

/// Supported API provider types.
enum ApiProviderType {
  /// Google Gemini models.
  gemini,

  /// Alibaba Qwen (DashScope) models.
  qwen,

  /// OpenAI and OpenAI-compatible APIs.
  openai,

  /// DeepSeek models.
  deepseek,

  /// Anthropic Claude models.
  anthropic,

  /// Local Ollama instance.
  ollama,

  /// AWS Bedrock.
  bedrock,

  /// Google Vertex AI.
  vertex,

  /// Custom OpenAI-compatible endpoint.
  custom,
}

/// Configuration for the API provider.
class ApiConfig {
  /// The provider backend to use.
  final ApiProviderType type;

  /// Base URL for the API endpoint.
  final String baseUrl;

  /// API key for authentication (null for keyless providers like Ollama).
  final String? apiKey;

  /// Model identifier to use for completions.
  final String model;

  /// Maximum output tokens per completion.
  final int maxTokens;

  /// Additional HTTP headers sent with every request.
  final Map<String, String> extraHeaders;

  const ApiConfig({
    required this.type,
    required this.baseUrl,
    this.apiKey,
    required this.model,
    this.maxTokens = 16384,
    this.extraHeaders = const {},
  });

  /// Default Anthropic configuration.
  factory ApiConfig.anthropic({
    required String apiKey,
    String model = 'claude-sonnet-4-20250514',
    int maxTokens = 16384,
  }) => ApiConfig(
    type: ApiProviderType.anthropic,
    baseUrl: 'https://api.anthropic.com',
    apiKey: apiKey,
    model: model,
    maxTokens: maxTokens,
  );

  /// OpenAI-compatible provider (OpenAI, Ollama, DeepSeek, etc).
  factory ApiConfig.openai({
    String? apiKey,
    String baseUrl = 'https://api.openai.com/v1',
    String model = 'gpt-4o',
    int maxTokens = 16384,
  }) => ApiConfig(
    type: ApiProviderType.openai,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    maxTokens: maxTokens,
  );

  /// Google Gemini.
  factory ApiConfig.gemini({
    required String apiKey,
    String baseUrl = 'https://generativelanguage.googleapis.com/v1beta',
    String model = 'gemini-2.5-flash',
    int maxTokens = 65536,
  }) => ApiConfig(
    type: ApiProviderType.gemini,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    maxTokens: maxTokens,
  );

  /// Alibaba Qwen (DashScope).
  factory ApiConfig.qwen({
    required String apiKey,
    String baseUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    String model = 'qwen-plus',
    int maxTokens = 32768,
  }) => ApiConfig(
    type: ApiProviderType.qwen,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    maxTokens: maxTokens,
  );

  /// DeepSeek.
  factory ApiConfig.deepseek({
    required String apiKey,
    String baseUrl = 'https://api.deepseek.com/v1',
    String model = 'deepseek-chat',
    int maxTokens = 32768,
  }) => ApiConfig(
    type: ApiProviderType.deepseek,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    maxTokens: maxTokens,
  );

  /// Local Ollama instance.
  factory ApiConfig.ollama({
    String baseUrl = 'http://localhost:11434/v1',
    String model = 'llama3.1',
    int maxTokens = 16384,
  }) => ApiConfig(
    type: ApiProviderType.ollama,
    baseUrl: baseUrl,
    model: model,
    maxTokens: maxTokens,
  );
}

/// Stream event from the API — mirrors Anthropic's SSE events.
sealed class StreamEvent {
  const StreamEvent();
}

/// Emitted when a new message begins streaming.
class MessageStartEvent extends StreamEvent {
  /// Unique identifier for this message.
  final String messageId;

  /// The model that generated this message.
  final String model;
  const MessageStartEvent({required this.messageId, required this.model});
}

/// Emitted when a new content block (text or tool use) starts.
class ContentBlockStartEvent extends StreamEvent {
  /// Index of this content block within the message.
  final int index;

  /// The initial content block data.
  final ContentBlock block;
  const ContentBlockStartEvent({required this.index, required this.block});
}

/// Emitted when incremental text is appended to a content block.
class ContentBlockDeltaEvent extends StreamEvent {
  /// Index of the content block being updated.
  final int index;

  /// The incremental text fragment.
  final String text;
  const ContentBlockDeltaEvent({required this.index, required this.text});
}

/// Emitted when a content block finishes streaming.
class ContentBlockStopEvent extends StreamEvent {
  /// Index of the completed content block.
  final int index;
  const ContentBlockStopEvent({required this.index});
}

/// Emitted with final message metadata (stop reason, token usage).
class MessageDeltaEvent extends StreamEvent {
  /// Why the model stopped generating.
  final StopReason? stopReason;

  /// Token usage statistics for this message.
  final TokenUsage? usage;
  const MessageDeltaEvent({this.stopReason, this.usage});
}

/// Emitted when the message stream is complete.
class MessageStopEvent extends StreamEvent {
  const MessageStopEvent();
}

/// Emitted when an error occurs during streaming.
class ErrorEvent extends StreamEvent {
  /// Human-readable error description.
  final String message;

  /// Error type identifier (e.g., 'api_error', 'overloaded_error').
  final String? type;
  const ErrorEvent({required this.message, this.type});
}

/// Abstract provider interface — implemented by Anthropic and OpenAI shim.
abstract class ApiProvider {
  ApiConfig get config;

  /// Stream a message completion.
  Stream<StreamEvent> createMessageStream({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  });

  /// Non-streaming message completion.
  Future<Message> createMessage({
    required List<Message> messages,
    required String systemPrompt,
    List<ToolDefinition> tools = const [],
    int? maxTokens,
  });
}
