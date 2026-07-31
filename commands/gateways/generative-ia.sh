#!/bin/bash
# generative-ia.sh — Gateway for AI/LLM services
#
# Routes calls to the active provider adapter based on AI_PROVIDER in config.env.
# Supported providers: cursor | copilot
#
# Configuration (via commands/config.env):
#   AI_PROVIDER    — Active provider: cursor | copilot  (default: copilot)
#   MODEL          — Primary model   (empty = provider default)
#   FALLBACK_MODEL — Fallback model  (empty = no fallback)
#   MAX_RETRIES    — Retry attempts per model  (default: 2)
#   TIMEOUT        — Request timeout in seconds  (default: 60)
#
# generative_ia PROMPT [VERBOSE]
#   Sends PROMPT to the configured provider and prints the response to stdout.
#   VERBOSE=1 prints progress indicators to the terminal.
#   Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.
#
# Sourced usage:
#   source /path/to/generative-ia.sh
#   response=$(generative_ia "prompt")
#
# Standalone usage:
#   ./generative-ia.sh "prompt" [1]

export PATH="/Users/gabrielfloresousion/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v ui_error >/dev/null 2>&1; then
  _UI_LIB="$SCRIPT_DIR/../lib/ui.sh"
  [ -f "$_UI_LIB" ] && source "$_UI_LIB"
fi

CONFIG_FILE="$SCRIPT_DIR/../../config.env"

if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
else
  if command -v ui_warning >/dev/null 2>&1; then
    ui_warning "config.env not found at $CONFIG_FILE, using defaults" >&2
  fi
  MAX_RETRIES=2
  TIMEOUT=60
fi

PROVIDER="${AI_PROVIDER:-copilot}"
ADAPTER_FILE="$SCRIPT_DIR/adapters/ia/${PROVIDER}.sh"

if [ ! -f "$ADAPTER_FILE" ]; then
  if command -v ui_error >/dev/null 2>&1; then
    ui_error "Adapter for provider '$PROVIDER' not found at $ADAPTER_FILE" >&2
    ui_info "Supported providers: cursor, copilot" >&2
  fi
  exit 1
fi

source "$ADAPTER_FILE"

# generative_ia PROMPT [VERBOSE]
# Public entry point. Dispatches to the active provider adapter.
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

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  if [ $# -eq 0 ]; then
    if command -v ui_error >/dev/null 2>&1; then
      ui_error "Usage: $0 \"prompt\" [verbose]" >&2
      ui_info "   or: source $0 && generative_ia \"prompt\" [1]" >&2
    fi
    exit 1
  fi
  generative_ia "$1" "${2:-0}"
fi
