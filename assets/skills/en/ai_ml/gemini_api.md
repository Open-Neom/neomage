# Gemini API Development

Build applications with Google's Gemini models for text, multimodal, function calling, structured output, and code execution.

- Current models: gemini-3-pro-preview (1M tokens, complex reasoning), gemini-3-flash-preview (1M tokens, fast/balanced), gemini-3-pro-image-preview (image generation)
- SDKs: Python (google-genai), JavaScript (@google/genai), Go (google.golang.org/genai) -- legacy SDKs are deprecated
- Key capabilities: text generation, multimodal understanding (images/audio/video/docs), function calling, structured output (JSON schema), code execution (sandboxed Python), context caching, embeddings
- Python quick start: from google import genai; client = genai.Client(); response = client.models.generate_content(model="gemini-3-flash-preview", contents="...")
- Use v1beta API by default (SDKs target it); v1 only when explicitly required
- REST API discovery spec is the source of truth for schemas: generativelanguage.googleapis.com/$discovery/rest?version=v1beta
- Documentation index at ai.google.dev/gemini-api/docs/llms.txt links to all pages in .md.txt format
- Models like gemini-2.5-*, gemini-2.0-*, gemini-1.5-* are legacy and deprecated
