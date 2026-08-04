#!/bin/bash
# generative-ia.sh — Gateway for AI/LLM services
#
# Routes calls to the active provider adapter based on AI_PROVIDER, which is
# loaded from settings.yaml via lib/config.sh and set interactively at runtime.
# Supported providers: cursor | copilot | codex
#
# Configuration: settings.yaml (loaded via commands/lib/config.sh)
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

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

_GW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v ui_error >/dev/null 2>&1; then
  _UI_LIB="$_GW_DIR/../lib/ui.sh"
  [ -f "$_UI_LIB" ] && source "$_UI_LIB"
fi

source "$_GW_DIR/../lib/config.sh"
source "$_GW_DIR/../lib/utils.sh"

_LOADED_PROVIDER=""

# generative_ia PROMPT [VERBOSE]
# Public entry point. Resolves AI_PROVIDER at call time and dispatches to the
# matching adapter. The adapter is sourced only when the provider changes,
# avoiding redundant file reads across multiple calls in the same session.
generative_ia() {
  local _PROVIDER="${AI_PROVIDER:-copilot}"
  local _ADAPTER_FILE="$_GW_DIR/adapters/ia/${_PROVIDER}.sh"

  if [ "$_PROVIDER" != "$_LOADED_PROVIDER" ]; then
    if [ ! -f "$_ADAPTER_FILE" ]; then
      ui_error "Adapter for provider '${_PROVIDER}' not found at ${_ADAPTER_FILE}" >&2
      ui_info "Supported providers: cursor, copilot, codex" >&2
      return 1
    fi
    source "$_ADAPTER_FILE"
    _LOADED_PROVIDER="$_PROVIDER"
  fi

  case "$_PROVIDER" in
    cursor)  _generative_ia_cursor  "$@" ;;
    copilot) _generative_ia_copilot "$@" ;;
    codex)   _generative_ia_codex   "$@" ;;
    *)
      ui_error "Unknown AI_PROVIDER '${_PROVIDER}'. Supported: cursor, copilot, codex" >&2
      return 1
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  if [ $# -eq 0 ]; then
    ui_error "Usage: $0 \"prompt\" [verbose]" >&2
    ui_info "   or: source $0 && generative_ia \"prompt\" [1]" >&2
    exit 1
  fi
  generative_ia "$1" "${2:-0}"
fi
