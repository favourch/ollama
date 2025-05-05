#!/bin/bash

set -e

OLLAMA_HOST="http://localhost:11434"
TEST_PROMPT="When were you created?"

# Check if 'ollama' is installed
if ! command -v ollama &> /dev/null; then
  echo "❌ Ollama is not installed. Please install it: https://ollama.com/download"
  exit 1
fi

# --- Prepare Model List ---
RECOMMENDED_MODELS=("tinyllama:1.1b-chat" "phi:2.7b-chat-v2-q4_0" "phi-3-mini-4k-instruct.Q4_0.gguf:Q4_0" "phi3:mini" "phi3:medium-q4_0" "qwen:0.5b" "llama3:instruct" "phi-4")

# Get installed models
INSTALLED_MODELS=()
while IFS= read -r line; do
  model_name=$(echo "$line" | awk '{print $1}')
  if [[ ! " ${RECOMMENDED_MODELS[*]} " =~ " ${model_name} " ]]; then
    INSTALLED_MODELS+=("$model_name")
  fi
done < <(ollama list | tail -n +2)

# Combine all options
ALL_MODELS=("${RECOMMENDED_MODELS[@]}" "${INSTALLED_MODELS[@]}")

# Show selection
echo "🧠 Select a model to run:"
for i in "${!ALL_MODELS[@]}"; do
  index=$((i + 1))
  echo "$index) ${ALL_MODELS[$i]}"
done

# Ask user to choose
echo ""
read -p "Enter the number of the model to run: " SELECTION

if ! [[ "$SELECTION" =~ ^[0-9]+$ ]] || [ "$SELECTION" -lt 1 ] || [ "$SELECTION" -gt "${#ALL_MODELS[@]}" ]; then
  echo "❌ Invalid selection."
  exit 1
fi

BASE_MODEL="${ALL_MODELS[$((SELECTION-1))]}"
echo "✅ You selected: $BASE_MODEL"
echo ""

# --- Start Ollama Server ---
if pgrep -f "ollama serve" > /dev/null; then
  echo "🟢 Ollama server is already running."
else
  echo "🔄 Starting Ollama server..."
  nohup ollama serve > /dev/null 2>&1 &
fi

# Wait for server to be ready
until curl -s "$OLLAMA_HOST" > /dev/null; do
  echo "⏳ Waiting for Ollama to be ready at $OLLAMA_HOST..."
  sleep 2
done

echo "✅ Ollama is ready!"

# Pull model
echo "📥 Pulling model '$BASE_MODEL'..."
ollama pull "$BASE_MODEL"

# Run model
echo "🚀 Running model: $BASE_MODEL..."
ollama run "$BASE_MODEL" &

sleep 5

# Test prompt
echo "🧠 Sending test prompt: '$TEST_PROMPT'"
RESPONSE=$(curl -s --max-time 90 -X POST "$OLLAMA_HOST/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "'"$BASE_MODEL"'",
    "messages": [{"role": "user", "content": "'"$TEST_PROMPT"'"}],
    "max_tokens": 1024,
    "temperature": 0.7
  }')

if echo "$RESPONSE" | grep -q "content"; then
  echo "✅ Model successfully responded:"
  echo "$RESPONSE" | jq -r '.choices[0].message.content'
else
  echo "❌ API check failed. Response:"
  echo "$RESPONSE"
fi
