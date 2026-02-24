#!/bin/bash
# Gateway for interacting with AI/LLM services
# Currently configured to use GitHub Copilot CLI
#
# Configuration (via commands/config.env):
#   MODEL       - AI model to use (default: gpt-4.1)
#   MAX_RETRIES - Number of retry attempts (default: 2)
#   TIMEOUT     - Request timeout in seconds (default: 30)
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

COPILOT_BIN="/home/flores/.nvm/versions/node/v22.15.0/bin/copilot"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.env"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "⚠️  Warning: config.env not found at $CONFIG_FILE, using defaults" >&2
  MODEL="gpt-4.1"
  MAX_RETRIES=2
  TIMEOUT=30
fi

generative_ia() {
  local PROMPT="$1"
  local VERBOSE="${2:-0}"

  if [ -z "$PROMPT" ]; then
    echo "❌ Error: No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ ! -x "$COPILOT_BIN" ]; then
    echo "❌ Error: Copilot binary not found or not executable at $COPILOT_BIN" >&2
    return 1
  fi

  if [ "$VERBOSE" = "1" ]; then
    echo "🧠 AI thinking..." >&2
  fi

  local ATTEMPT=1
  local RESPONSE=""

  while [ $ATTEMPT -le $MAX_RETRIES ]; do
    if [ "$VERBOSE" = "1" ]; then
      RESPONSE=$(timeout $TIMEOUT "$COPILOT_BIN" --model "$MODEL" -p "$PROMPT")
    else
      RESPONSE=$(timeout $TIMEOUT "$COPILOT_BIN" --model "$MODEL" -p "$PROMPT" --silent 2>&1)
    fi
    local EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
      echo "$RESPONSE"
      return 0
    fi

    if [ $EXIT_CODE -eq 124 ]; then
      echo "⚠️  Warning: AI call timed out (attempt $ATTEMPT/$MAX_RETRIES)" >&2
    else
      echo "⚠️  Warning: AI call failed with exit code $EXIT_CODE (attempt $ATTEMPT/$MAX_RETRIES)" >&2
    fi

    ATTEMPT=$((ATTEMPT + 1))

    if [ $ATTEMPT -le $MAX_RETRIES ]; then
      sleep $((2 ** (ATTEMPT - 1)))
    fi
  done

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
