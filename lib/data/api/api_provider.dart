import '../../domain/models/message.dart';
import '../../domain/models/tool_definition.dart';

/// Supported API provider types.
enum ApiProviderType {
  gemini,
  qwen,
  openai,
  deepseek,
  anthropic,
  ollama,
  bedrock,
  vertex,
  custom,
}

/// Configuration for the API provider.
class ApiConfig {
  final ApiProviderType type;
  final String baseUrl;
  final String? apiKey;
  final String model;
  final int maxTokens;
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

class MessageStartEvent extends StreamEvent {
  final String messageId;
  final String model;
  const MessageStartEvent({required this.messageId, required this.model});
}

class ContentBlockStartEvent extends StreamEvent {
  final int index;
  final ContentBlock block;
  const ContentBlockStartEvent({required this.index, required this.block});
}

class ContentBlockDeltaEvent extends StreamEvent {
  final int index;
  final String text;
  const ContentBlockDeltaEvent({required this.index, required this.text});
}

class ContentBlockStopEvent extends StreamEvent {
  final int index;
  const ContentBlockStopEvent({required this.index});
}

class MessageDeltaEvent extends StreamEvent {
  final StopReason? stopReason;
  final TokenUsage? usage;
  const MessageDeltaEvent({this.stopReason, this.usage});
}

class MessageStopEvent extends StreamEvent {
  const MessageStopEvent();
}

class ErrorEvent extends StreamEvent {
  final String message;
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
