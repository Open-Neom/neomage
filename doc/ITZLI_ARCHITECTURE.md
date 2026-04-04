# Itzli v1 — Arquitectura del Modelo

## Overview

**Itzli v1** (codename: Itzli Semilla v1) es el primer modelo de IA local del ecosistema Open Neom. Especializado en Flutter/Dart y el framework Sint, corre directamente en la máquina del usuario via Ollama.

| Propiedad | Valor |
|-----------|-------|
| Modelo base | Qwen 2.5 3B |
| Parámetros | 3 billones |
| Tamaño en disco | ~2.3 GB (Q4_K_M) |
| Contexto | 8,192 tokens |
| Licencia | Apache 2.0 |
| Hardware mínimo | Apple Silicon M1 / 8GB RAM |
| Creador | Open Neom |

## Arquitectura

```
┌─────────────────────────────────────────┐
│           Itzli v1 (Ollama)             │
├─────────────────────────────────────────┤
│  System Prompt (personalidad Itzli)     │
│  ├── Identidad Open Neom               │
│  ├── Conocimiento Flutter/Dart/Sint     │
│  ├── Limitaciones honestas             │
│  └── Tono directo, sin cortesía vacía  │
├─────────────────────────────────────────┤
│  Parámetros de generación              │
│  ├── temperature: 0.7                   │
│  ├── top_p: 0.9                         │
│  ├── repeat_penalty: 1.15              │
│  ├── num_ctx: 8192                      │
│  └── num_predict: 1024                  │
├─────────────────────────────────────────┤
│  Qwen 2.5 3B (GGUF Q4_K_M)            │
│  └── Pesos cuantizados 4-bit           │
└─────────────────────────────────────────┘
         ↕ HTTP (localhost:11434)
┌─────────────────────────────────────────┐
│  Neom Claw / Itzli Desktop              │
│  └── OllamaIaService → OllamaBrain     │
└─────────────────────────────────────────┘
```

## Modificaciones sobre el modelo base

Itzli v1 **no modifica los pesos** del modelo base. Las customizaciones son:

1. **System prompt** — Personalidad Itzli horneada via Modelfile
2. **Parámetros** — temperature/top_p/repeat_penalty optimizados para código
3. **Stop tokens** — `<|im_end|>`, `<|im_start|>`, `<|endoftext|>` para evitar loops

El modelo base (Qwen 2.5 3B) se descarga intacto de Ollama's registry.

## Plan de Fine-Tuning

### Fase 1: Prompt Engineering (actual)
- System prompt con conocimiento de Sint/Open Neom
- Dataset de ejemplo para validación
- Sin modificación de pesos

### Fase 2: QLoRA Fine-Tuning (pendiente)
- **Método**: QLoRA (4-bit quantization + LoRA adapters)
- **Dataset**: Conversaciones Flutter/Dart reales del ecosistema Open Neom
- **Target layers**: attention + mlp
- **LoRA rank**: 16, alpha: 32
- **Épocas**: 3
- **Learning rate**: 2e-4

### Fase 3: Exportación
- Merge adapter con modelo base
- Conversión a GGUF via llama.cpp
- Cuantización Q4_K_M
- Registro como modelo Ollama custom

## Performance en Apple Silicon M1

| Métrica | Valor estimado |
|---------|----------------|
| Carga del modelo | ~3 segundos |
| Tokens/segundo | 15-25 tok/s |
| Tiempo primer token | <500ms |
| RAM en uso | ~3-4 GB |
| Respuesta típica (100 tok) | 4-7 segundos |

### Recomendaciones por hardware

| RAM | Modelo recomendado |
|-----|-------------------|
| 8 GB | Itzli v1 (3B) — funcional, puede swappear |
| 16 GB | Itzli v1 (3B) — óptimo, sin swap |
| 32 GB+ | Considera modelos 7B+ para mejor calidad |

## Comparación con otros modelos

| Modelo | Params | Tamaño | Velocidad M1 | Calidad código | Costo |
|--------|--------|--------|--------------|----------------|-------|
| **Itzli v1** | 3B | 2.3 GB | Rápido | Buena | Gratis (local) |
| Itzli Semilla (7B) | 7B | 4.7 GB | Medio | Muy buena | Gratis (local) |
| Gemma 4 | 9B | 9.6 GB | Lento | Excelente | Gratis (local) |
| Gemini Flash | Cloud | — | Variable | Excelente | Firebase free tier |
| Claude Sonnet | Cloud | — | Variable | Superior | API key |

**Itzli v1 es ideal para**: snippets rápidos, debugging, consultas de API, generación de boilerplate Sint/Flutter. Para razonamiento complejo o refactoring masivo, usa modelos cloud.

## API

Itzli v1 expone la API estándar de Ollama (OpenAI-compatible):

```bash
# Chat
curl http://localhost:11434/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"itzli","messages":[{"role":"user","content":"Crea un SintController"}]}'

# Listar modelos
curl http://localhost:11434/api/tags

# Info del modelo
ollama show itzli --system
```

## Archivos

```
neom_claw/
├── Modelfile                              # Personalidad + parámetros
├── itzli_config.json                      # Metadata y config fine-tuning
├── scripts/
│   ├── build_itzli.sh                     # Build automatizado
│   └── fine_tune_itzli.py                 # QLoRA fine-tuning (futuro)
├── training_data/
│   └── example_conversations.jsonl        # Dataset de entrenamiento
├── adapters/                              # LoRA adapters (post fine-tune)
└── docs/
    └── ITZLI_ARCHITECTURE.md              # Este documento
```
