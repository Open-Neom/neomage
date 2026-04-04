// ignore_for_file: avoid_print
import 'package:neom_claw/neom_claw.dart';

/// Basic example: send a message to Gemini and print the streaming response.
void main() async {
  // 1. Configure the API provider (Gemini, OpenAI, DeepSeek, Qwen, Ollama, etc.)
  final config = ApiConfig.gemini(apiKey: 'YOUR_GEMINI_API_KEY');

  // 2. Create an OpenAI-compatible client
  //    Works with any provider — just change the config above.
  final client = OpenAiShim(config);

  // 3. Build the message list
  final messages = [
    Message(
      role: MessageRole.user,
      content: [TextBlock(text: 'Explain what Flutter is in one sentence.')],
    ),
  ];

  // 4. Stream the response
  print('Sending message to ${config.model}...\n');

  await for (final event in client.createMessageStream(
    messages: messages,
    systemPrompt: 'You are a helpful assistant.',
  )) {
    switch (event) {
      case ContentBlockDeltaEvent(:final text):
        print(text);
      case MessageDeltaEvent(:final usage):
        if (usage != null) {
          print('\nTokens: ${usage.outputTokens}');
        }
      case ErrorEvent(:final message):
        print('Error: $message');
      default:
        break;
    }
  }
}
