#!/usr/bin/env python3
"""
fine_tune_itzli.py — QLoRA fine-tuning for Itzli v1
Open Neom — Apache 2.0

Fine-tunes qwen2.5:3b on Flutter/Dart/Sint conversations using QLoRA.
Saves adapters to ./adapters/ and optionally exports to Ollama-compatible GGUF.

Requirements:
    pip install torch transformers peft datasets bitsandbytes accelerate

Usage:
    python scripts/fine_tune_itzli.py                    # Train
    python scripts/fine_tune_itzli.py --export-gguf      # Train + export
    python scripts/fine_tune_itzli.py --dry-run           # Validate dataset only
"""

import argparse
import json
import os
import sys
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parent.parent
DATASET_PATH = PROJECT_DIR / "training_data" / "example_conversations.jsonl"
ADAPTER_DIR = PROJECT_DIR / "adapters" / "itzli-v1-lora"
CONFIG_PATH = PROJECT_DIR / "itzli_config.json"

# ═══════════════════════════════════════════
# Configuration from itzli_config.json
# ═══════════════════════════════════════════

def load_config():
    with open(CONFIG_PATH) as f:
        return json.load(f)

# ═══════════════════════════════════════════
# Dataset loading
# ═══════════════════════════════════════════

def load_dataset(path: Path):
    """Load JSONL conversations into Hugging Face Dataset format."""
    conversations = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            entry = json.loads(line)
            conversations.append(entry)

    print(f"  Loaded {len(conversations)} conversations from {path.name}")
    return conversations


def format_for_training(conversations: list) -> list:
    """Convert conversations to ChatML format for Qwen2.5."""
    formatted = []
    for conv in conversations:
        messages = conv.get("messages", [])
        text_parts = []

        for msg in messages:
            role = msg["role"]
            content = msg["content"]
            text_parts.append(f"<|im_start|>{role}\n{content}<|im_end|>")

        text_parts.append("<|im_start|>assistant\n")
        formatted.append({"text": "\n".join(text_parts)})

    return formatted


def validate_dataset(path: Path) -> bool:
    """Validate dataset structure."""
    print(f"\n  Validating {path.name}...")
    errors = 0

    with open(path) as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if "messages" not in entry:
                    print(f"    Line {i}: missing 'messages' key")
                    errors += 1
                    continue
                for msg in entry["messages"]:
                    if "role" not in msg or "content" not in msg:
                        print(f"    Line {i}: message missing role/content")
                        errors += 1
            except json.JSONDecodeError as e:
                print(f"    Line {i}: invalid JSON — {e}")
                errors += 1

    if errors == 0:
        print(f"  ✓ Dataset valid ({i} entries)")
    else:
        print(f"  ✗ {errors} errors found")
    return errors == 0

# ═══════════════════════════════════════════
# Training
# ═══════════════════════════════════════════

def train(config: dict, dry_run: bool = False):
    """Run QLoRA fine-tuning."""

    if not DATASET_PATH.exists():
        print(f"  ✗ Dataset not found: {DATASET_PATH}")
        print("  Create training data in training_data/example_conversations.jsonl")
        sys.exit(1)

    if not validate_dataset(DATASET_PATH):
        sys.exit(1)

    if dry_run:
        print("\n  Dry run complete — dataset is valid.")
        return

    # Lazy imports — only needed for actual training
    try:
        import torch
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            TrainingArguments,
            Trainer,
            BitsAndBytesConfig,
        )
        from peft import LoraConfig, get_peft_model, prepare_model_for_kbit_training
        from datasets import Dataset
    except ImportError as e:
        print(f"\n  ✗ Missing dependency: {e}")
        print("  Install with: pip install torch transformers peft datasets bitsandbytes accelerate")
        sys.exit(1)

    ft_config = config.get("fine_tuning", {})
    base_model = config["base_model"].replace(":","_")
    model_id = f"Qwen/{base_model.replace('qwen2.5_3b','Qwen2.5-3B')}"

    print(f"\n  Base model: {model_id}")
    print(f"  Method: QLoRA (rank={ft_config.get('lora_rank', 16)})")
    print(f"  Adapter output: {ADAPTER_DIR}")

    # ── Quantization config (4-bit for M1 efficiency) ──
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=True,
    )

    # ── Load model + tokenizer ──
    print("\n  Loading base model...")
    tokenizer = AutoTokenizer.from_pretrained(model_id, trust_remote_code=True)
    model = AutoModelForCausalLM.from_pretrained(
        model_id,
        quantization_config=bnb_config,
        device_map="auto",
        trust_remote_code=True,
    )

    model = prepare_model_for_kbit_training(model)

    # ── LoRA config ──
    lora_config = LoraConfig(
        r=ft_config.get("lora_rank", 16),
        lora_alpha=ft_config.get("lora_alpha", 32),
        target_modules=ft_config.get("target_layers", ["attention", "mlp"]),
        lora_dropout=0.05,
        bias="none",
        task_type="CAUSAL_LM",
    )

    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ── Prepare dataset ──
    conversations = load_dataset(DATASET_PATH)
    formatted = format_for_training(conversations)
    dataset = Dataset.from_list(formatted)

    def tokenize(example):
        return tokenizer(
            example["text"],
            truncation=True,
            max_length=config.get("context_window", 8192),
            padding="max_length",
        )

    tokenized = dataset.map(tokenize, remove_columns=["text"])

    # ── Training args ──
    training_args = TrainingArguments(
        output_dir=str(ADAPTER_DIR),
        num_train_epochs=ft_config.get("epochs", 3),
        per_device_train_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=ft_config.get("learning_rate", 2e-4),
        warmup_steps=10,
        logging_steps=5,
        save_strategy="epoch",
        fp16=False,
        bf16=torch.cuda.is_bf16_supported() if torch.cuda.is_available() else False,
        optim="adamw_torch",
        report_to="none",
    )

    # ── Train ──
    print("\n  Starting QLoRA fine-tuning...")
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=tokenized,
    )

    trainer.train()

    # ── Save adapter ──
    ADAPTER_DIR.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(str(ADAPTER_DIR))
    tokenizer.save_pretrained(str(ADAPTER_DIR))
    print(f"\n  ✓ Adapter saved to {ADAPTER_DIR}")

# ═══════════════════════════════════════════
# Export to GGUF (for Ollama)
# ═══════════════════════════════════════════

def export_gguf():
    """Merge LoRA adapter with base model and export to GGUF."""
    print("\n  Exporting to GGUF (Ollama-compatible)...")
    print("  NOTE: This requires llama.cpp's convert tool.")
    print(f"  Steps:")
    print(f"    1. Merge adapter: python -m peft.merge_and_unload {ADAPTER_DIR}")
    print(f"    2. Convert: python llama.cpp/convert_hf_to_gguf.py merged_model/")
    print(f"    3. Quantize: ./llama.cpp/build/bin/llama-quantize model.gguf model-q4.gguf Q4_K_M")
    print(f"    4. Create Ollama model: ollama create itzli-ft -f Modelfile.finetuned")
    print(f"\n  Full automation coming in Itzli v2.")

# ═══════════════════════════════════════════
# CLI
# ═══════════════════════════════════════════

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Itzli v1 — QLoRA Fine-Tuning")
    parser.add_argument("--dry-run", action="store_true", help="Validate dataset only")
    parser.add_argument("--export-gguf", action="store_true", help="Export to GGUF after training")
    args = parser.parse_args()

    config = load_config()

    print(f"\n  Itzli v1 Fine-Tuning")
    print(f"  Base: {config['base_model']} | Method: QLoRA")
    print(f"  Dataset: {DATASET_PATH}")

    train(config, dry_run=args.dry_run)

    if args.export_gguf:
        export_gguf()
