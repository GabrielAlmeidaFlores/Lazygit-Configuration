#!/bin/bash
# Gateway for interacting with AI/LLM services
# Currently configured to use GitHub Copilot CLI
#
# Configuration:
#   COPILOT_BIN - Path to the Copilot CLI binary
#   MAX_RETRIES - Number of retry attempts (default: 2)
#   TIMEOUT - Request timeout in seconds (default: 30)
#
# Function: generative_ia(prompt)
#   Sends a prompt to the AI service and returns the response
#   Parameters:
#     prompt (string) - The text prompt to send to the AI
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
#   As a standalone script:
#     ./generative-ia.sh "Your prompt here"

COPILOT_BIN="/home/flores/.nvm/versions/node/v22.15.0/bin/copilot"
MAX_RETRIES=2
TIMEOUT=30

generative_ia() {
  local PROMPT="$1"

  if [ -z "$PROMPT" ]; then
    echo "❌ Error: No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ ! -x "$COPILOT_BIN" ]; then
    echo "❌ Error: Copilot binary not found or not executable at $COPILOT_BIN" >&2
    return 1
  fi

  local ATTEMPT=1
  local RESPONSE=""

  while [ $ATTEMPT -le $MAX_RETRIES ]; do
    RESPONSE=$(timeout $TIMEOUT "$COPILOT_BIN" -p "$PROMPT" --silent 2>&1)
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
    echo "Usage: $0 \"Your prompt here\"" >&2
    echo "   or: source $0 && generative_ia \"Your prompt here\"" >&2
    exit 1
  fi

  generative_ia "$1"
fi
