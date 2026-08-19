#!/bin/bash
# kiro.sh — Kiro CLI adapter for generative_ia
#
# Configuration (via settings.yaml -> loaded by lib/config.sh):
#   MODEL             — Primary model (empty = configured Kiro default)
#   MAX_RETRIES       — Retry attempts per model (default: 2)
#   TIMEOUT           — Request timeout in seconds (default: 60)
#   KIRO_BIN          — Path to kiro-cli binary (empty = auto-detect from PATH)
#   KIRO_EFFORT       — Optional reasoning effort: low | medium | high | xhigh | max
#   KIRO_TRUST_TOOLS  — Optional comma-separated tool categories (empty = no tool trust)
#
# _generative_ia_kiro PROMPT [VERBOSE]
# Calls Kiro CLI in headless mode with PROMPT and prints the response to stdout.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.

KIRO_BIN="${KIRO_BIN:-$(command -v kiro-cli 2>/dev/null || true)}"

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_helpers.sh"

# _kiro_write_workspace_settings SETTINGS_DIR MODEL
# Writes workspace-level Kiro CLI settings for model selection in headless mode.
# Exit codes: 0 = success, 1 = failure.
_kiro_write_workspace_settings() {
  local SETTINGS_DIR="$1"
  local MODEL="$2"

  mkdir -p "$SETTINGS_DIR" || return 1

  if [ -n "$MODEL" ]; then
    ui_print "{\"chat\":{\"defaultModel\":\"${MODEL}\",\"showThinking\":false}}" > "${SETTINGS_DIR}/cli.json"
  else
    ui_print '{"chat":{"showThinking":false}}' > "${SETTINGS_DIR}/cli.json"
  fi
}

# _generative_ia_kiro PROMPT [VERBOSE]
# Calls Kiro CLI in headless mode with PROMPT and prints the response to stdout.
# Exit codes: 0 = success, 1 = failure, 130 = cancelled by user.
_generative_ia_kiro() {
  local PROMPT="$1"
  local VERBOSE="${2:-0}"
  local _AI_PID="" _CANCELLED=0 _TEMP_OUT _TEMP_ERR _TEMP_WS _SETTINGS_DIR
  local _SAVED_KIRO_LOG_NO_COLOR="${KIRO_LOG_NO_COLOR:-}"
  local _SAVED_NO_COLOR="${NO_COLOR:-}"

  if [ -z "$PROMPT" ]; then
    ui_error "No prompt provided to generative_ia" >&2
    return 1
  fi

  if [ -z "$KIRO_BIN" ]; then
    ui_error "Kiro CLI binary not found in PATH" >&2
    return 1
  fi

  if [ ! -x "$KIRO_BIN" ]; then
    ui_error "Kiro CLI binary not found or not executable at $KIRO_BIN" >&2
    return 1
  fi

  if ! _TEMP_OUT=$(mktemp); then
    ui_error "Could not create temporary file for Kiro response" >&2
    return 1
  fi

  if ! _TEMP_ERR=$(mktemp); then
    rm -f "$_TEMP_OUT"
    ui_error "Could not create temporary file for Kiro errors" >&2
    return 1
  fi

  if ! _TEMP_WS=$(mktemp -d); then
    rm -f "$_TEMP_OUT" "$_TEMP_ERR"
    ui_error "Could not create temporary workspace for Kiro model settings" >&2
    return 1
  fi

  _SETTINGS_DIR="$_TEMP_WS/.kiro/settings"

  _ai_cancel() {
    _CANCELLED=1
    [ -n "$_AI_PID" ] && kill "$_AI_PID" 2>/dev/null && wait "$_AI_PID" 2>/dev/null
    rm -rf "$_TEMP_WS"
    rm -f "$_TEMP_OUT" "$_TEMP_ERR"
    ui_cancel >&2
  }
  trap '_ai_cancel' INT

  export KIRO_LOG_NO_COLOR=1
  export NO_COLOR=1

  _build_model_fallback_chain "${MODEL:-$KIRO_DEFAULT_MODEL}" "$KIRO_MODELS"
  local MODELS_TO_TRY=("${MODEL_FALLBACK_CHAIN[@]}")

  local EFFORT_ARGS=()
  if [ -n "$KIRO_EFFORT" ]; then
    EFFORT_ARGS=(--effort "$KIRO_EFFORT")
  fi

  local TRUST_ARGS=()
  if [ -n "$KIRO_TRUST_TOOLS" ]; then
    TRUST_ARGS=(--trust-tools="$KIRO_TRUST_TOOLS")
  fi

  for CURRENT_MODEL in "${MODELS_TO_TRY[@]}"; do
    [ $_CANCELLED -eq 1 ] && break

    local MODEL_LABEL="default"
    if [ -n "$CURRENT_MODEL" ]; then
      MODEL_LABEL="$CURRENT_MODEL"
    fi

    if ! _kiro_write_workspace_settings "$_SETTINGS_DIR" "$CURRENT_MODEL"; then
      ui_error "Could not write Kiro workspace settings for model ${MODEL_LABEL}" >&2
      rm -rf "$_TEMP_WS"
      rm -f "$_TEMP_OUT" "$_TEMP_ERR"
      trap - INT
      return 1
    fi

    [ "$VERBOSE" = "1" ] && ui_step "🧠  Thinking  ($MODEL_LABEL)  Ctrl+C to cancel" >&2

    local ATTEMPT=1

    while [ $ATTEMPT -le $MAX_RETRIES ] && [ $_CANCELLED -eq 0 ]; do
      (
        cd "$_TEMP_WS" || exit 1
        _run_with_timeout $TIMEOUT "$KIRO_BIN" chat --no-interactive --wrap never "${EFFORT_ARGS[@]}" "${TRUST_ARGS[@]}" "$PROMPT"
      ) >"$_TEMP_OUT" 2>"$_TEMP_ERR" &
      _AI_PID=$!
      wait "$_AI_PID"
      local EXIT_CODE=$?
      _AI_PID=""

      [ $_CANCELLED -eq 1 ] && break

      local RESPONSE
      RESPONSE=$(<"$_TEMP_OUT")

      if [ $EXIT_CODE -eq 0 ] && [ -n "$RESPONSE" ]; then
        rm -rf "$_TEMP_WS"
        rm -f "$_TEMP_OUT" "$_TEMP_ERR"
        trap - INT
        [ -n "$_SAVED_KIRO_LOG_NO_COLOR" ] && export KIRO_LOG_NO_COLOR="$_SAVED_KIRO_LOG_NO_COLOR" || unset KIRO_LOG_NO_COLOR
        [ -n "$_SAVED_NO_COLOR" ] && export NO_COLOR="$_SAVED_NO_COLOR" || unset NO_COLOR
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
        [ -n "$ERROR_DETAIL" ] && ui_warning "Kiro: ${ERROR_DETAIL:0:300}" >&2
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

  rm -rf "$_TEMP_WS"
  rm -f "$_TEMP_OUT" "$_TEMP_ERR"
  trap - INT
  [ -n "$_SAVED_KIRO_LOG_NO_COLOR" ] && export KIRO_LOG_NO_COLOR="$_SAVED_KIRO_LOG_NO_COLOR" || unset KIRO_LOG_NO_COLOR
  [ -n "$_SAVED_NO_COLOR" ] && export NO_COLOR="$_SAVED_NO_COLOR" || unset NO_COLOR

  [ $_CANCELLED -eq 1 ] && return 130

  ui_error "AI call failed after exhausting all models" >&2
  return 1
}
