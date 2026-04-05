# Local Models

This directory is for local AI model configurations. The goal is to run models entirely on-device — no internet, no API keys, no data leaving the machine.

## Why Local Models?

Cloud APIs are powerful but depend on connectivity, cost money per token, and send user data to third-party servers. Local models solve all three:

- **Offline-first**: Works without internet. Always available.
- **Zero cost**: No API fees. Run as many queries as you want.
- **Private**: Nothing leaves your machine. Ever.

## Why Small Models Matter

The most important factor for local inference is **model size**. Smaller models:

- Load faster (seconds, not minutes)
- Use less RAM (run on 8-16GB machines)
- Respond faster (20-30 tokens/second on Apple Silicon)
- Will only get better — every generation of model optimization produces smaller models with equal or greater capability

A 3B parameter model today matches what a 13B model could do two years ago. This trend continues. What runs locally on a laptop today will eventually rival cloud models — and it will still be free, private, and instant.

## Suggested Structure

Each model should have its own directory with:

```
models/
└── your-model-name/
    ├── Modelfile           # Ollama config: base model, system prompt, parameters
    ├── model.json          # Metadata: size, capabilities, hardware requirements
    └── training_data/      # Fine-tuning dataset (if applicable)
```

### Example Modelfile

```
FROM qwen2.5:3b

SYSTEM """Your custom system prompt here."""

PARAMETER temperature 0.7
PARAMETER num_ctx 8192
PARAMETER top_p 0.9
PARAMETER repeat_penalty 1.15
PARAMETER num_predict 1024
PARAMETER stop "<|im_end|>"
PARAMETER stop "<|im_start|>"
```

### Example model.json

```json
{
  "name": "your-model",
  "version": "1.0.0",
  "base_model": "qwen2.5:3b",
  "parameters": "3B",
  "size": "~1.9GB",
  "context_window": 8192,
  "license": "Apache-2.0"
}
```

## Adding a New Model

1. Create a directory under `models/`
2. Write a `Modelfile` pointing to a base model
3. Add a `model.json` with metadata
4. Run `ollama create <name> -f Modelfile`
5. Test with `ollama run <name>`

## Recommended Base Models

| Model | Size | Best For |
|-------|------|----------|
| qwen2.5:1.5b | ~1 GB | Ultra-fast responses, low RAM |
| qwen2.5:3b | ~1.9 GB | Good balance of speed and quality |
| qwen2.5-coder:7b | ~4.7 GB | Code generation and reasoning |
| gemma4:latest | ~9.6 GB | High quality, requires 16GB+ RAM |

## Requirements

- [Ollama](https://ollama.com) installed and running
- Apple Silicon M1+ / 8GB RAM minimum (16GB recommended)
- Also works on x86_64 with AVX2 or NVIDIA GPU
