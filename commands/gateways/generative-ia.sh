#!/bin/bash
# Gateway for interacting with AI/LLM services
# Routes requests to the configured provider adapter (cursor | copilot)
#
# Configuration (via config.env):
#   AI_PROVIDER      - Active provider: cursor | copilot (default: cursor)
#   MODEL            - Primary AI model (empty = provider default)
#   FALLBACK_MODEL   - Fallback model if primary fails (empty = no fallback)
#   MAX_RETRIES      - Number of retry attempts per model (default: 2)
#   TIMEOUT          - Request timeout in seconds (default: 60)
#
# Function: generative_ia(prompt, [verbose])
#   Sends a prompt to the AI service and returns the response
#   Parameters:
#     prompt   (string)  - The text prompt to send to the AI
#     verbose  (0|1)     - When 1, prints AI thinking/progress to stderr
#   Returns:
#     Success (0) - Outputs the AI response to stdout
#     Failure (1) - Outputs error message to stderr
#
# Usage:
#   As a sourced function:
#     source /path/to/generative-ia.sh
#     response=$(generative_ia "Your prompt here")
#     response=$(generative_ia "Your prompt here" 1)
#   As a standalone script:
#     ./generative-ia.sh "Your prompt here"
#     ./generative-ia.sh "Your prompt here" 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../../config.env"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "⚠️  Warning: config.env not found at $CONFIG_FILE, using defaults" >&2
fi

AI_PROVIDER="${AI_PROVIDER:-cursor}"
MAX_RETRIES="${MAX_RETRIES:-2}"
TIMEOUT="${TIMEOUT:-60}"

case "$AI_PROVIDER" in
  copilot)
    source "$SCRIPT_DIR/adapters/copilot.sh"
    _GENERATIVE_IA_IMPL="_generative_ia_copilot"
    ;;
  cursor)
    source "$SCRIPT_DIR/adapters/cursor.sh"
    _GENERATIVE_IA_IMPL="_generative_ia_cursor"
    ;;
  *)
    echo "❌ Error: Unknown AI_PROVIDER '$AI_PROVIDER'. Use 'cursor' or 'copilot'." >&2
    return 1 2>/dev/null || exit 1
    ;;
esac

generative_ia() {
  "$_GENERATIVE_IA_IMPL" "$@"
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  if [ $# -eq 0 ]; then
    echo "Usage: $0 \"Your prompt here\" [verbose]" >&2
    echo "   or: source $0 && generative_ia \"Your prompt here\" [1]" >&2
    exit 1
  fi

  generative_ia "$1" "${2:-0}"
fi
