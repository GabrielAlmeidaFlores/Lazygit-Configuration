#!/bin/bash
# cursor.sh — Cursor Agent CLI adapter for generative_ia
#
# Configuration (via config.env):
#   MODEL        — Primary model    (empty = Cursor default)
#   FALLBACK_MODEL — Fallback model (empty = no fallback)
#   MAX_RETRIES  — Retry attempts per model  (default: 2)
#   TIMEOUT      — Request timeout in seconds  (default: 60)
#   CURSOR_BIN   — Path to agent binary  (empty = auto-detect from PATH)
#   CURSOR_MODE  — Agent mode: ask | plan  (default: ask)
#
# _generative_ia_cursor PROMPT [VERBOSE]
#   Calls the Cursor agent CLI with PROMPT and prints the response to stdout.
#   Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.

CURSOR_BIN="${CURSOR_BIN:-$(which agent)}"
CURSOR_MODE="${CURSOR_MODE:-ask}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

# _generative_ia_cursor PROMPT [VERBOSE]
# Calls the Cursor agent CLI with PROMPT and prints the response to stdout.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.
_generative_ia_cursor() {
  local PROMPT="$1"
  local VERBOSE="${2:-0}"
  local _AI_PID="" _CANCELLED=0 _TEMP_OUT

  if [ -z "$PROMPT" ]; then
    ui_error "No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ ! -x "$CURSOR_BIN" ]; then
    ui_error "Cursor agent binary not found or not executable at $CURSOR_BIN" >&2
    return 1
  fi

  _TEMP_OUT=$(mktemp)

  _ai_cancel() {
    _CANCELLED=1
    [ -n "$_AI_PID" ] && kill "$_AI_PID" 2>/dev/null && wait "$_AI_PID" 2>/dev/null
    rm -f "$_TEMP_OUT"
    ui_cancel >&2
  }
  trap '_ai_cancel' INT

  local MODELS_TO_TRY=()
  if [ -n "$MODEL" ]; then
    MODELS_TO_TRY+=("$MODEL")
  else
    MODELS_TO_TRY+=("")
  fi
  if [ -n "$FALLBACK_MODEL" ] && [ "$FALLBACK_MODEL" != "$MODEL" ]; then
    MODELS_TO_TRY+=("$FALLBACK_MODEL")
  fi

  for CURRENT_MODEL in "${MODELS_TO_TRY[@]}"; do
    [ $_CANCELLED -eq 1 ] && break

    local MODEL_ARGS=()
    local MODEL_LABEL="default"
    if [ -n "$CURRENT_MODEL" ]; then
      MODEL_ARGS=(--model "$CURRENT_MODEL")
      MODEL_LABEL="$CURRENT_MODEL"
    fi

    [ "$VERBOSE" = "1" ] && ui_step "🧠  Thinking  ($MODEL_LABEL)  Ctrl+C to cancel" >&2

    local ATTEMPT=1

    while [ $ATTEMPT -le $MAX_RETRIES ] && [ $_CANCELLED -eq 0 ]; do
      _run_with_timeout $TIMEOUT "$CURSOR_BIN" -p --trust --mode="$CURSOR_MODE" "${MODEL_ARGS[@]}" "$PROMPT" >"$_TEMP_OUT" 2>/dev/null &
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
        ui_print "$RESPONSE"
        return 0
      fi

      if [ $EXIT_CODE -eq 124 ]; then
        ui_warning "Call timed out  [$MODEL_LABEL]  attempt $ATTEMPT/$MAX_RETRIES" >&2
      else
        ui_warning "Call failed  [$MODEL_LABEL]  exit $EXIT_CODE  attempt $ATTEMPT/$MAX_RETRIES" >&2
      fi

      ATTEMPT=$((ATTEMPT + 1))
      if [ $ATTEMPT -le $MAX_RETRIES ] && [ $_CANCELLED -eq 0 ]; then
        sleep $((2 ** (ATTEMPT - 1)))
      fi
    done

    local LAST_MODEL_INDEX=$((${#MODELS_TO_TRY[@]} - 1))
    if [ $_CANCELLED -eq 0 ] && [ "$CURRENT_MODEL" != "${MODELS_TO_TRY[$LAST_MODEL_INDEX]}" ]; then
      ui_step "Switching to fallback model..." >&2
    fi
  done

  rm -f "$_TEMP_OUT"
  trap - INT

  [ $_CANCELLED -eq 1 ] && return 130

  ui_error "AI call failed after exhausting all models" >&2
  return 1
}
