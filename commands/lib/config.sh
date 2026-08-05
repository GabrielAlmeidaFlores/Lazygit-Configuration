#!/bin/bash
# lib/config.sh — Configuration loader for AI-powered Lazygit commands
#
# Loads all settings from settings.yaml via yq and exports them as shell variables
# compatible with all existing scripts. Sourced by gateways/generative-ia.sh.
#
# Requires: yq (brew install yq)
#
# Globals exported after sourcing:
#   AI_PROVIDER, MODEL, FALLBACK_MODEL, MAX_RETRIES, TIMEOUT
#   CURSOR_BIN, CURSOR_MODE, COPILOT_BIN, CODEX_BIN, AZURE_DEVOPS_PAT
#   CURSOR_MODELS, COPILOT_MODELS, CODEX_MODELS
#   CURSOR_DEFAULT_MODEL, COPILOT_DEFAULT_MODEL, CODEX_DEFAULT_MODEL
#   PROMPT_COMMIT_TEMPLATE, PROMPT_BRANCH_TEMPLATE
#   PROMPT_ANALYSIS_TEMPLATE, PROMPT_ANALYSIS_PASS2_TEMPLATE
#   PROMPT_ANALYSIS_PASS3_TEMPLATE, PROMPT_COMMENT_TEMPLATE
#   PROMPT_INSTRUCTIONS_ARCHITECTURE, PROMPT_INSTRUCTIONS_SECURITY
#   PROMPT_INSTRUCTIONS_CODE_QUALITY, PROMPT_INSTRUCTIONS_TEST_COVERAGE
#   PROMPT_INSTRUCTIONS_PERFORMANCE, PROMPT_INSTRUCTIONS_SPELLING
#   PROMPT_INSTRUCTIONS_BUGS, PROMPT_INSTRUCTIONS_FIX_VALIDATION
#
# Functions defined after sourcing:
#   config_select_provider
#   config_get_default_model
#   config_select_model

_CFG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CONFIG_DIR="${_CONFIG_DIR:-$(cd "${_CFG_LIB_DIR}/../.." && pwd)}"
_CONFIG_FILE="${_CONFIG_FILE:-${_CONFIG_DIR}/settings.yaml}"
_CONFIG_STATE="${_CONFIG_STATE:-${_CONFIG_DIR}/config.state.yaml}"

if ! command -v ui_error >/dev/null 2>&1; then
  [ -f "${_CFG_LIB_DIR}/ui.sh" ] && source "${_CFG_LIB_DIR}/ui.sh"
fi

# _cfg_str EXPR FILE
# Reads a yq expression from FILE and strips the literal "" that yq v4 emits
# when a YAML value is an empty string. Outputs the raw string or nothing.
# Exit codes: always 0.
_cfg_str() {
  local _v
  _v=$(yq "${1}" "${2}")
  [ "$_v" = '""' ] || [ "$_v" = "''" ] || [ "$_v" = "null" ] || ui_print "$_v"
}

# _cfg_validate
# Validates the loaded configuration values. Calls ui_error for each problem
# found and returns the total number of errors, allowing the caller to exit.
# Checks: provider name, numeric types, required prompt templates.
# Exit codes: 0 = all valid, N = number of errors found.
_cfg_validate() {
  local _ERRORS=0

  case "$AI_PROVIDER" in
    cursor|copilot|codex) ;;
    *)
      ui_error "settings.yaml: ai.provider must be 'cursor', 'copilot', or 'codex' (got: '${AI_PROVIDER}')"
      _ERRORS=$((_ERRORS + 1))
      ;;
  esac

  if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]] || [ "$MAX_RETRIES" -lt 1 ]; then
    ui_error "settings.yaml: ai.max_retries must be a positive integer (got: '${MAX_RETRIES}')"
    _ERRORS=$((_ERRORS + 1))
  fi

  if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [ "$TIMEOUT" -lt 1 ]; then
    ui_error "settings.yaml: ai.timeout must be a positive integer (got: '${TIMEOUT}')"
    _ERRORS=$((_ERRORS + 1))
  fi

  local _KEY _VAR
  while IFS=: read -r _KEY _VAR; do
    [ -z "${!_VAR}" ] && ui_error "settings.yaml: ${_KEY} is empty or missing" && _ERRORS=$((_ERRORS + 1))
  done <<'EOF'
prompts.commit:PROMPT_COMMIT_TEMPLATE
prompts.branch:PROMPT_BRANCH_TEMPLATE
prompts.analysis_pass1:PROMPT_ANALYSIS_TEMPLATE
prompts.analysis_pass2:PROMPT_ANALYSIS_PASS2_TEMPLATE
prompts.analysis_pass3:PROMPT_ANALYSIS_PASS3_TEMPLATE
prompts.comment:PROMPT_COMMENT_TEMPLATE
EOF

  return $_ERRORS
}

if [ "${_CFG_SKIP_LOAD:-0}" != "1" ]; then

  if ! command -v yq &>/dev/null; then
    ui_error "'yq' not found. Install it: brew install yq"
    exit 1
  fi

  if [ ! -f "$_CONFIG_FILE" ]; then
    ui_error "settings.yaml not found at ${_CONFIG_FILE}"
    exit 1
  fi

  AI_PROVIDER=$(yq '.ai.provider // "copilot"'            "$_CONFIG_FILE")
  MODEL=$(_cfg_str '.ai.model // ""'                      "$_CONFIG_FILE")
  FALLBACK_MODEL=$(_cfg_str '.ai.fallback_model // ""'    "$_CONFIG_FILE")
  MAX_RETRIES=$(yq '.ai.max_retries // 2'                 "$_CONFIG_FILE")
  TIMEOUT=$(yq '.ai.timeout // 60'                        "$_CONFIG_FILE")
  CURSOR_BIN=$(_cfg_str '.providers.cursor.bin // ""'     "$_CONFIG_FILE")
  CURSOR_MODE=$(yq '.providers.cursor.mode // "ask"'      "$_CONFIG_FILE")
  COPILOT_BIN=$(_cfg_str '.providers.copilot.bin // ""'   "$_CONFIG_FILE")
  CODEX_BIN=$(_cfg_str '.providers.codex.bin // ""'       "$_CONFIG_FILE")
  AZURE_DEVOPS_PAT="${AZURE_DEVOPS_PAT:-$(_cfg_str '.azure_devops.pat // ""' "$_CONFIG_FILE")}"
  CURSOR_MODELS=$(yq '.providers.cursor.models // ""'     "$_CONFIG_FILE")
  COPILOT_MODELS=$(yq '.providers.copilot.models // ""'   "$_CONFIG_FILE")
  CODEX_MODELS=$(_cfg_str '.providers.codex.models // ""' "$_CONFIG_FILE")
  CURSOR_DEFAULT_MODEL=$(_cfg_str '.providers.cursor.default_model // "gpt-5.4-nano-none"' "$_CONFIG_FILE")
  COPILOT_DEFAULT_MODEL=$(_cfg_str '.providers.copilot.default_model // "gemini-3.1-pro-preview"' "$_CONFIG_FILE")
  CODEX_DEFAULT_MODEL=$(_cfg_str '.providers.codex.default_model // "gpt-5.6-luna"' "$_CONFIG_FILE")

  PROMPT_COMMIT_TEMPLATE=$(yq '.prompts.commit'                            "$_CONFIG_FILE")
  PROMPT_BRANCH_TEMPLATE=$(yq '.prompts.branch'                            "$_CONFIG_FILE")
  PROMPT_ANALYSIS_TEMPLATE=$(yq '.prompts.analysis_pass1'                  "$_CONFIG_FILE")
  PROMPT_ANALYSIS_PASS2_TEMPLATE=$(yq '.prompts.analysis_pass2'            "$_CONFIG_FILE")
  PROMPT_ANALYSIS_PASS3_TEMPLATE=$(yq '.prompts.analysis_pass3'            "$_CONFIG_FILE")
  PROMPT_COMMENT_TEMPLATE=$(yq '.prompts.comment'                          "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_ARCHITECTURE=$(yq '.prompts.instructions.architecture'   "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_SECURITY=$(yq '.prompts.instructions.security'           "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_CODE_QUALITY=$(yq '.prompts.instructions.code_quality'   "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_TEST_COVERAGE=$(yq '.prompts.instructions.test_coverage' "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_PERFORMANCE=$(yq '.prompts.instructions.performance'     "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_SPELLING=$(yq '.prompts.instructions.spelling'           "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_BUGS=$(yq '.prompts.instructions.bugs'                   "$_CONFIG_FILE")
  PROMPT_INSTRUCTIONS_FIX_VALIDATION=$(yq '.prompts.instructions.fix_validation' "$_CONFIG_FILE")

  _cfg_validate || exit 1

fi

# config_select_provider
# Shows an fzf picker for the AI provider, pre-selecting the last used value
# from config.state.yaml (last used appears at the top of the list).
# Saves the selection to config.state.yaml and updates AI_PROVIDER.
# Returns 1 if the user cancels without selecting.
config_select_provider() {
  local LAST_PROVIDER=""
  if [ -f "$_CONFIG_STATE" ]; then
    LAST_PROVIDER=$(yq '.last_provider // ""' "$_CONFIG_STATE" 2>/dev/null)
    [ "$LAST_PROVIDER" = "null" ] && LAST_PROVIDER=""
    [ "$LAST_PROVIDER" = '""' ]   && LAST_PROVIDER=""
  fi
  [ -z "$LAST_PROVIDER" ] && LAST_PROVIDER="${AI_PROVIDER:-copilot}"
  case "$LAST_PROVIDER" in
    cursor|copilot|codex) ;;
    *) LAST_PROVIDER="${AI_PROVIDER:-copilot}" ;;
  esac

  local SELECTED PROVIDER
  SELECTED=$({
    ui_print "$LAST_PROVIDER"
    for PROVIDER in cursor copilot codex; do
      [ "$PROVIDER" != "$LAST_PROVIDER" ] && ui_print "$PROVIDER"
    done
  } | fzf \
    --prompt="  AI Provider  " \
    --header="Select AI provider — last used: ${LAST_PROVIDER}" \
    --height=15% \
    --border=rounded \
    --margin=0,1,0,1
  )

  [ -z "$SELECTED" ] && return 1

  export AI_PROVIDER="$SELECTED"

  if [ ! -f "$_CONFIG_STATE" ]; then
    ui_print "last_provider: \"${SELECTED}\"" > "$_CONFIG_STATE"
    ui_print 'last_model: ""'                >> "$_CONFIG_STATE"
  else
    SELECTED="$SELECTED" yq -i '.last_provider = env(SELECTED)' "$_CONFIG_STATE"
  fi
}

# config_get_default_model [PROVIDER]
# Returns the configured global model or the explicit default for PROVIDER.
# Exit codes: 0 = model returned, 1 = provider unsupported.
config_get_default_model() {
  local PROVIDER="${1:-$AI_PROVIDER}"

  [ -n "$MODEL" ] && ui_print "$MODEL" && return 0

  case "$PROVIDER" in
    cursor)  ui_print "$CURSOR_DEFAULT_MODEL" ;;
    copilot) ui_print "$COPILOT_DEFAULT_MODEL" ;;
    codex)   ui_print "$CODEX_DEFAULT_MODEL" ;;
    *)       return 1 ;;
  esac
}

# config_select_model [PROVIDER]
# Shows an fzf picker for the selected provider's models and updates MODEL.
# The default option retains the model configured in settings.yaml.
# Returns 1 if the user cancels or the provider is unsupported.
config_select_model() {
  local PROVIDER="${1:-$AI_PROVIDER}" MODEL_LIST SELECTED
  local DEFAULT_CURSOR_MODELS="default
gpt-5.4-nano-none  (low — fastest and most economical)
gpt-5.4-mini-low  (medium — economical coding)
gpt-5.3-codex-low  (medium — coding)
gemini-3.6-flash-minimal  (low — fast general use)
claude-sonnet-5-low  (medium — balanced reasoning)"
  local DEFAULT_COPILOT_MODELS="default
gemini-3.1-pro-preview  (medium — fast and capable)
claude-sonnet-4.5  (medium — balanced quality)
claude-sonnet-4.6  (medium-high — latest sonnet)
gpt-5.3-codex  (high — advanced coding)
claude-opus-4.6  (high — premium quality)"
  local DEFAULT_CODEX_MODELS="default
gpt-5.6-terra  (medium — balanced coding)
gpt-5.6-luna  (low — fast and economical)
gpt-5.5  (high — complex coding and research)"

  case "$PROVIDER" in
    cursor)
      MODEL_LIST="${CURSOR_MODELS:+default
$(ui_print "$CURSOR_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
      MODEL_LIST="${MODEL_LIST:-$DEFAULT_CURSOR_MODELS}"
      ;;
    copilot)
      MODEL_LIST="${COPILOT_MODELS:+default
$(ui_print "$COPILOT_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
      MODEL_LIST="${MODEL_LIST:-$DEFAULT_COPILOT_MODELS}"
      ;;
    codex)
      MODEL_LIST="${CODEX_MODELS:+default
$(ui_print "$CODEX_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
      MODEL_LIST="${MODEL_LIST:-$DEFAULT_CODEX_MODELS}"
      ;;
    *)
      ui_error "Unsupported AI provider '${PROVIDER}' for model selection"
      return 1
      ;;
  esac

  SELECTED=$(ui_print "$MODEL_LIST" | fzf \
    --prompt="  Model (${PROVIDER})  " \
    --header="Select the model used for this generation" \
    --height=50% \
    --border=rounded \
    --margin=0,1,0,1)

  [ -z "$SELECTED" ] && return 1

  SELECTED=$(ui_print "$SELECTED" | sed 's/[[:space:]]*(.*)//')
  if [ "$SELECTED" = "default" ]; then
    MODEL=$(config_get_default_model "$PROVIDER") || return 1
    export MODEL
  else
    export MODEL="$SELECTED"
  fi
}
