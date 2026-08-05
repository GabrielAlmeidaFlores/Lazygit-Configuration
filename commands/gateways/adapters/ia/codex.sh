#!/bin/bash
# codex.sh — OpenAI Codex CLI adapter for generative_ia
#
# Configuration (via settings.yaml -> loaded by lib/config.sh):
#   MODEL          — Primary model (empty = configured Codex default)
#   MAX_RETRIES    — Retry attempts per model (default: 2)
#   TIMEOUT        — Request timeout in seconds (default: 60)
#   CODEX_BIN      — Path to codex binary (empty = auto-detect from PATH)
#
# _generative_ia_codex PROMPT [VERBOSE]
# Calls Codex in non-interactive, read-only mode and prints the response to stdout.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.

CODEX_BIN="${CODEX_BIN:-$(command -v codex 2>/dev/null || true)}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

# _generative_ia_codex PROMPT [VERBOSE]
# Calls Codex in non-interactive, read-only mode and prints the response to stdout.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.
_generative_ia_codex() {
  local PROMPT="$1"
  local VERBOSE="${2:-0}"
  local _AI_PID="" _CANCELLED=0 _TEMP_OUT _TEMP_PROMPT _TEMP_ERR

  if [ -z "$PROMPT" ]; then
    ui_error "No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ -z "$CODEX_BIN" ]; then
    ui_error "Codex binary not found in PATH" >&2
    return 1
  fi

  if [ ! -x "$CODEX_BIN" ]; then
    ui_error "Codex binary not found or not executable at $CODEX_BIN" >&2
    return 1
  fi

  if ! _TEMP_OUT=$(mktemp); then
    ui_error "Could not create temporary file for Codex response" >&2
    return 1
  fi

  if ! _TEMP_PROMPT=$(mktemp); then
    rm -f "$_TEMP_OUT"
    ui_error "Could not create temporary file for Codex prompt" >&2
    return 1
  fi

  if ! _TEMP_ERR=$(mktemp); then
    rm -f "$_TEMP_OUT" "$_TEMP_PROMPT"
    ui_error "Could not create temporary file for Codex errors" >&2
    return 1
  fi

  if ! ui_print "$PROMPT" > "$_TEMP_PROMPT"; then
    rm -f "$_TEMP_OUT" "$_TEMP_PROMPT" "$_TEMP_ERR"
    ui_error "Could not write Codex prompt" >&2
    return 1
  fi

  _ai_cancel() {
    _CANCELLED=1
    [ -n "$_AI_PID" ] && kill "$_AI_PID" 2>/dev/null && wait "$_AI_PID" 2>/dev/null
    rm -f "$_TEMP_OUT" "$_TEMP_PROMPT" "$_TEMP_ERR"
    ui_cancel >&2
  }
  trap '_ai_cancel' INT

  _build_model_fallback_chain "${MODEL:-$CODEX_DEFAULT_MODEL}" "$CODEX_MODELS"
  local MODELS_TO_TRY=("${MODEL_FALLBACK_CHAIN[@]}")

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
      _run_with_timeout $TIMEOUT "$CODEX_BIN" exec --ephemeral --color never --sandbox read-only "${MODEL_ARGS[@]}" - <"$_TEMP_PROMPT" >"$_TEMP_OUT" 2>"$_TEMP_ERR" &
      _AI_PID=$!
      wait "$_AI_PID"
      local EXIT_CODE=$?
      _AI_PID=""

      [ $_CANCELLED -eq 1 ] && break

      local RESPONSE
      RESPONSE=$(<"$_TEMP_OUT")

      if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
        rm -f "$_TEMP_OUT" "$_TEMP_PROMPT" "$_TEMP_ERR"
        trap - INT
        ui_print "$RESPONSE"
        return 0
      fi

      if [ $EXIT_CODE -eq 124 ]; then
        ui_warning "Call timed out  [$MODEL_LABEL]  attempt $ATTEMPT/$MAX_RETRIES" >&2
      elif [ $EXIT_CODE -eq 0 ]; then
        ui_warning "Call returned an empty response  [$MODEL_LABEL]  attempt $ATTEMPT/$MAX_RETRIES" >&2
      else
        ui_warning "Call failed  [$MODEL_LABEL]  exit $EXIT_CODE  attempt $ATTEMPT/$MAX_RETRIES" >&2
        local ERROR_DETAIL
        ERROR_DETAIL=$(tail -n 1 "$_TEMP_ERR")
        [ -n "$ERROR_DETAIL" ] && ui_warning "Codex: ${ERROR_DETAIL:0:300}" >&2
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

  rm -f "$_TEMP_OUT" "$_TEMP_PROMPT" "$_TEMP_ERR"
  trap - INT

  [ $_CANCELLED -eq 1 ] && return 130

  ui_error "AI call failed after exhausting all models" >&2
  return 1
}
