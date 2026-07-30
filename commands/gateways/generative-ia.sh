#!/bin/bash
# Gateway for interacting with AI/LLM services
#
# Dispatches to the correct provider adapter based on AI_PROVIDER in config.env.
# Supported providers: cursor | copilot
#
# Configuration (via commands/config.env):
#   AI_PROVIDER      - Active provider: cursor | copilot (default: copilot)
#   MODEL            - Primary AI model (empty = provider default)
#   FALLBACK_MODEL   - Fallback model if primary fails (empty = no fallback)
#   MAX_RETRIES      - Number of retry attempts per model (default: 2)
#   TIMEOUT          - Request timeout in seconds (default: 60)
#
# Function: generative_ia(prompt, [verbose])
#   Sends a prompt to the configured AI provider and returns the response.
#   Parameters:
#     prompt   (string)  - The text prompt to send
#     verbose  (0|1)     - When 1, prints progress indicators to stderr
#   Returns:
#     Success (0)   - Outputs the AI response to stdout
#     Cancelled (130) - User pressed Ctrl+C
#     Failure (1)   - Outputs error message to stderr
#
# Usage (sourced):
#   source /path/to/generative-ia.sh
#   response=$(generative_ia "Your prompt here")
#   response=$(generative_ia "Your prompt here" 1)  # verbose
#
# Usage (standalone):
#   ./generative-ia.sh "Your prompt here"
#   ./generative-ia.sh "Your prompt here" 1

# ─── PATH (needed when launched from GUI apps like Lazygit) ───────────────────
export PATH="/Users/gabrielfloresousion/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# ─── Load ui.sh if not already sourced (needed when run standalone) ───────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if ! command -v ui_error >/dev/null 2>&1; then
  _UI_LIB="$SCRIPT_DIR/../lib/ui.sh"
  [ -f "$_UI_LIB" ] && source "$_UI_LIB"
fi

# ─── Load config ──────────────────────────────────────────────────────────────
CONFIG_FILE="$SCRIPT_DIR/../../config.env"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  echo "  WARN  config.env not found at $CONFIG_FILE, using defaults" >&2
  MAX_RETRIES=2
  TIMEOUT=60
fi

# ─── Load provider adapter ────────────────────────────────────────────────────
PROVIDER="${AI_PROVIDER:-copilot}"
ADAPTER_FILE="$SCRIPT_DIR/adapters/${PROVIDER}.sh"

if [ ! -f "$ADAPTER_FILE" ]; then
  echo "  FAIL  Adapter for provider '$PROVIDER' not found at $ADAPTER_FILE" >&2
  echo "        Supported providers: cursor, copilot" >&2
  exit 1
fi

source "$ADAPTER_FILE"

# ─── Public function: generative_ia ───────────────────────────────────────────
generative_ia() {
  case "$PROVIDER" in
    cursor)
      _generative_ia_cursor "$@"
      ;;
    copilot)
      _generative_ia_copilot "$@"
      ;;
    *)
      ui_error "Unknown AI_PROVIDER '$PROVIDER'. Supported: cursor, copilot" >&2
      return 1
      ;;
  esac
}

# ─── Standalone execution ─────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  if [ $# -eq 0 ]; then
    echo "Usage: $0 \"Your prompt here\" [verbose]" >&2
    echo "   or: source $0 && generative_ia \"Your prompt here\" [1]" >&2
    exit 1
  fi
  generative_ia "$1" "${2:-0}"
fi
