#!/bin/bash
# ═══════════════════════════════════════════════════════
# build_itzli.sh — Build Itzli v1 model for Ollama
# Open Neom — Apache 2.0
# ═══════════════════════════════════════════════════════

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODEL_NAME="itzli"
BASE_MODEL="qwen2.5:3b"
MODELFILE="$PROJECT_DIR/Modelfile"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}  Itzli v1 — Build Script${NC}"
echo -e "${CYAN}  Open Neom${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo ""

# ── Step 1: Check Ollama ──
echo -e "${YELLOW}[1/6] Verificando Ollama...${NC}"
if ! command -v ollama &> /dev/null; then
    echo -e "${RED}  ✗ Ollama no esta instalado.${NC}"
    echo -e "  Descargalo en: https://ollama.com/download"
    exit 1
fi
echo -e "${GREEN}  ✓ Ollama encontrado: $(which ollama)${NC}"

# ── Step 2: Check Ollama server ──
echo -e "${YELLOW}[2/6] Verificando servidor Ollama...${NC}"
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo -e "  Iniciando Ollama server..."
    ollama serve &> /dev/null &
    sleep 3
    if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
        echo -e "${RED}  ✗ No se pudo iniciar Ollama.${NC}"
        exit 1
    fi
fi
echo -e "${GREEN}  ✓ Servidor Ollama activo${NC}"

# ── Step 3: Pull base model ──
echo -e "${YELLOW}[3/6] Verificando modelo base ($BASE_MODEL)...${NC}"
if ollama list | grep -q "$BASE_MODEL"; then
    echo -e "${GREEN}  ✓ $BASE_MODEL ya descargado${NC}"
else
    echo -e "  Descargando $BASE_MODEL (~2.3GB)..."
    if ollama pull "$BASE_MODEL"; then
        echo -e "${GREEN}  ✓ $BASE_MODEL descargado${NC}"
    else
        echo -e "${RED}  ✗ Error descargando $BASE_MODEL${NC}"
        exit 1
    fi
fi

# ── Step 4: Build Itzli ──
echo -e "${YELLOW}[4/6] Construyendo modelo Itzli v1...${NC}"
if [ ! -f "$MODELFILE" ]; then
    echo -e "${RED}  ✗ Modelfile no encontrado en: $MODELFILE${NC}"
    exit 1
fi

# Remove previous version if exists
if ollama list | grep -q "^$MODEL_NAME"; then
    echo -e "  Removiendo version anterior..."
    ollama rm "$MODEL_NAME" 2>/dev/null || true
fi

cd "$PROJECT_DIR"
if ollama create "$MODEL_NAME" -f Modelfile; then
    echo -e "${GREEN}  ✓ Modelo '$MODEL_NAME' creado exitosamente${NC}"
else
    echo -e "${RED}  ✗ Error creando modelo${NC}"
    echo -e "${YELLOW}  Rollback: el modelo base $BASE_MODEL sigue disponible.${NC}"
    exit 1
fi

# ── Step 5: Test ──
echo -e "${YELLOW}[5/6] Probando modelo...${NC}"
RESPONSE=$(curl -s http://localhost:11434/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "{\"model\":\"$MODEL_NAME\",\"messages\":[{\"role\":\"user\",\"content\":\"Quien eres? Responde en 1 linea.\"}],\"max_tokens\":80}" \
    2>/dev/null)

if echo "$RESPONSE" | python3 -c "import sys,json; r=json.load(sys.stdin); print(r['choices'][0]['message']['content'])" 2>/dev/null; then
    echo -e "${GREEN}  ✓ Modelo responde correctamente${NC}"
else
    echo -e "${RED}  ✗ El modelo no respondio. Verifica que Ollama tenga RAM suficiente.${NC}"
    echo -e "  Respuesta raw: $RESPONSE"
    exit 1
fi

# ── Step 6: Stats ──
echo -e "${YELLOW}[6/6] Estadisticas...${NC}"
echo ""
ollama list | grep "$MODEL_NAME"
echo ""

# RAM usage
if command -v vm_stat &> /dev/null; then
    PAGE_SIZE=$(vm_stat | head -1 | grep -oE '[0-9]+')
    FREE_PAGES=$(vm_stat | grep "Pages free" | awk '{print $3}' | tr -d '.')
    INACTIVE=$(vm_stat | grep "Pages inactive" | awk '{print $3}' | tr -d '.')
    AVAILABLE_MB=$(( (FREE_PAGES + INACTIVE) * PAGE_SIZE / 1048576 ))
    TOTAL_MB=$(sysctl -n hw.memsize 2>/dev/null)
    TOTAL_GB=$(( TOTAL_MB / 1073741824 ))
    echo -e "  RAM total: ${TOTAL_GB}GB"
    echo -e "  RAM disponible: ~${AVAILABLE_MB}MB"
fi

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  Itzli v1 listo.${NC}"
echo -e "${GREEN}  Ejecuta: ollama run itzli${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
