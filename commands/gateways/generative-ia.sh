#!/bin/bash
# Gateway for interacting with AI/LLM services
# Currently configured to use GitHub Copilot CLI
#
# Configuration (via commands/config.env):
#   AVAILABLE_MODELS - Array of AI models; first entry is the default
#   MAX_RETRIES      - Number of retry attempts (default: 2)
#   TIMEOUT          - Request timeout in seconds (default: 30)
#
# Function: generative_ia(prompt, [verbose])
#   Sends a prompt to the AI service and returns the response
#   Parameters:
#     prompt   (string)  - The text prompt to send to the AI
#     verbose  (0|1)     - When 1, prints AI thinking/progress to stderr
#   Returns:
#     Success (0) - Outputs the AI response to stdout
#     Failure (1) - Outputs error message to stderr
#   Behavior:
#     - Validates that a prompt is provided
#     - Checks if the Copilot binary exists and is executable
#     - Attempts the AI call up to MAX_RETRIES times
#     - Uses exponential backoff between retries (2^(attempt-1) seconds)
#     - Handles timeout errors (exit code 124)
#     - Returns error after all retries are exhausted
#
# Usage:
#   As a sourced function:
#     source /path/to/generative-ia.sh
#     response=$(generative_ia "Your prompt here")
#     response=$(generative_ia "Your prompt here" 1)   # with verbose/thinking output
#   As a standalone script:
#     ./generative-ia.sh "Your prompt here"
#     ./generative-ia.sh "Your prompt here" 1          # with verbose/thinking output

COPILOT_BIN="$(which copilot)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../config.env"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "⚠️  Warning: config.env not found at $CONFIG_FILE, using defaults" >&2
  AVAILABLE_MODELS=("gpt-4.1")
  MAX_RETRIES=2
  TIMEOUT=30
fi

MODEL="${AVAILABLE_MODELS[0]:-gpt-4.1}"

select_model() {
  local count=${#AVAILABLE_MODELS[@]}
  echo "🤖 Select AI model:"
  for ((i = 0; i < count; i++)); do
    local label=""
    [ $i -eq 0 ] && label=" (default)"
    echo "  $((i + 1))) ${AVAILABLE_MODELS[$i]}$label"
  done
  echo ""
  read -p "Choose [1-$count] (Enter for default): " MODEL_CHOICE
  echo ""

  if [[ -z "$MODEL_CHOICE" ]]; then
    MODEL="${AVAILABLE_MODELS[0]}"
  elif [[ "$MODEL_CHOICE" =~ ^[0-9]+$ ]] && [ "$MODEL_CHOICE" -ge 1 ] && [ "$MODEL_CHOICE" -le "$count" ]; then
    MODEL="${AVAILABLE_MODELS[$((MODEL_CHOICE - 1))]}"
  else
    echo "⚠️  Invalid choice, using default: ${AVAILABLE_MODELS[0]}" >&2
    MODEL="${AVAILABLE_MODELS[0]}"
  fi

  echo "✅ Using model: $MODEL"
  echo ""
}

generative_ia() {
  local PROMPT="$1"
  local VERBOSE="${2:-0}"
  local _AI_PID="" _CANCELLED=0 _TEMP_OUT

  if [ -z "$PROMPT" ]; then
    echo "❌ Error: No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ ! -x "$COPILOT_BIN" ]; then
    echo "❌ Error: Copilot binary not found or not executable at $COPILOT_BIN" >&2
    return 1
  fi

  _TEMP_OUT=$(mktemp)

  # Allow Ctrl+C to cancel the background AI process
  _ai_cancel() {
    _CANCELLED=1
    [ -n "$_AI_PID" ] && kill "$_AI_PID" 2>/dev/null && wait "$_AI_PID" 2>/dev/null
    rm -f "$_TEMP_OUT"
    echo "" >&2
    echo "🚫 AI request cancelled." >&2
  }
  trap '_ai_cancel' INT

  if [ "$VERBOSE" = "1" ]; then
    echo "🧠 AI thinking... (Ctrl+C to cancel)" >&2
  fi

  local ATTEMPT=1

  while [ $ATTEMPT -le $MAX_RETRIES ] && [ $_CANCELLED -eq 0 ]; do
    if [ "$VERBOSE" = "1" ]; then
      timeout $TIMEOUT "$COPILOT_BIN" --model "$MODEL" -p "$PROMPT" >"$_TEMP_OUT" 2>&1 &
    else
      timeout $TIMEOUT "$COPILOT_BIN" --model "$MODEL" -p "$PROMPT" --silent >"$_TEMP_OUT" 2>&1 &
    fi
    _AI_PID=$!
    wait "$_AI_PID"
    local EXIT_CODE=$?
    _AI_PID=""

    [ $_CANCELLED -eq 1 ] && break

    local RESPONSE
    RESPONSE=$(cat "$_TEMP_OUT")

    if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
      rm -f "$_TEMP_OUT"
      trap - INT
      echo "$RESPONSE"
      return 0
    fi

    if [ $EXIT_CODE -eq 124 ]; then
      echo "⚠️  Warning: AI call timed out (attempt $ATTEMPT/$MAX_RETRIES)" >&2
    else
      echo "⚠️  Warning: AI call failed with exit code $EXIT_CODE (attempt $ATTEMPT/$MAX_RETRIES)" >&2
    fi

    ATTEMPT=$((ATTEMPT + 1))

    if [ $ATTEMPT -le $MAX_RETRIES ] && [ $_CANCELLED -eq 0 ]; then
      sleep $((2 ** (ATTEMPT - 1)))
    fi
  done

  rm -f "$_TEMP_OUT"
  trap - INT

  if [ $_CANCELLED -eq 1 ]; then
    return 130
  fi

  echo "❌ Error: AI call failed after $MAX_RETRIES attempts" >&2
  return 1
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  if [ $# -eq 0 ]; then
    echo "Usage: $0 \"Your prompt here\" [verbose]" >&2
    echo "   or: source $0 && generative_ia \"Your prompt here\" [1]" >&2
    exit 1
  fi

  generative_ia "$1" "${2:-0}"
fi
