#!/bin/bash
# lib/config.sh — Configuration loader for AI-powered Lazygit commands
#
# Loads all settings from config.yaml via yq and exports them as shell variables
# compatible with all existing scripts. Sourced by gateways/generative-ia.sh.
#
# Requires: yq (brew install yq)
#
# Globals exported after sourcing:
#   AI_PROVIDER, MODEL, FALLBACK_MODEL, MAX_RETRIES, TIMEOUT
#   CURSOR_BIN, CURSOR_MODE, COPILOT_BIN, AZURE_DEVOPS_PAT
#   CURSOR_MODELS, COPILOT_MODELS
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

_CFG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_CONFIG_DIR="$(cd "${_CFG_LIB_DIR}/../.." && pwd)"
_CONFIG_FILE="${_CONFIG_DIR}/config.yaml"
_CONFIG_STATE="${_CONFIG_DIR}/config.state.yaml"

if ! command -v ui_error >/dev/null 2>&1; then
  [ -f "${_CFG_LIB_DIR}/ui.sh" ] && source "${_CFG_LIB_DIR}/ui.sh"
fi

if ! command -v yq &>/dev/null; then
  ui_error "'yq' not found. Install it: brew install yq"
  exit 1
fi

if [ ! -f "$_CONFIG_FILE" ]; then
  ui_error "config.yaml not found at ${_CONFIG_FILE}"
  exit 1
fi

# _cfg_str EXPR FILE
# Reads a yq expression from FILE and strips the literal "" that yq v4 emits
# when a YAML value is an empty string. Outputs the raw string or nothing.
# Exit codes: always 0.
_cfg_str() {
  local _v
  _v=$(yq "${1}" "${2}")
  [ "$_v" = '""' ] || [ "$_v" = "null" ] || ui_print "$_v"
}

AI_PROVIDER=$(yq '.ai.provider // "copilot"'            "$_CONFIG_FILE")
MODEL=$(_cfg_str '.ai.model // ""'                      "$_CONFIG_FILE")
FALLBACK_MODEL=$(_cfg_str '.ai.fallback_model // ""'    "$_CONFIG_FILE")
MAX_RETRIES=$(yq '.ai.max_retries // 2'                 "$_CONFIG_FILE")
TIMEOUT=$(yq '.ai.timeout // 60'                        "$_CONFIG_FILE")
CURSOR_BIN=$(_cfg_str '.providers.cursor.bin // ""'     "$_CONFIG_FILE")
CURSOR_MODE=$(yq '.providers.cursor.mode // "ask"'      "$_CONFIG_FILE")
COPILOT_BIN=$(_cfg_str '.providers.copilot.bin // ""'   "$_CONFIG_FILE")
AZURE_DEVOPS_PAT=$(_cfg_str '.azure_devops.pat // ""'   "$_CONFIG_FILE")
CURSOR_MODELS=$(yq '.providers.cursor.models // ""'     "$_CONFIG_FILE")
COPILOT_MODELS=$(yq '.providers.copilot.models // ""'   "$_CONFIG_FILE")

PROMPT_COMMIT_TEMPLATE=$(yq '.prompts.commit'                          "$_CONFIG_FILE")
PROMPT_BRANCH_TEMPLATE=$(yq '.prompts.branch'                          "$_CONFIG_FILE")
PROMPT_ANALYSIS_TEMPLATE=$(yq '.prompts.analysis_pass1'                "$_CONFIG_FILE")
PROMPT_ANALYSIS_PASS2_TEMPLATE=$(yq '.prompts.analysis_pass2'          "$_CONFIG_FILE")
PROMPT_ANALYSIS_PASS3_TEMPLATE=$(yq '.prompts.analysis_pass3'          "$_CONFIG_FILE")
PROMPT_COMMENT_TEMPLATE=$(yq '.prompts.comment'                        "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_ARCHITECTURE=$(yq '.prompts.instructions.architecture'   "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_SECURITY=$(yq '.prompts.instructions.security'           "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_CODE_QUALITY=$(yq '.prompts.instructions.code_quality'   "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_TEST_COVERAGE=$(yq '.prompts.instructions.test_coverage' "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_PERFORMANCE=$(yq '.prompts.instructions.performance'     "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_SPELLING=$(yq '.prompts.instructions.spelling'           "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_BUGS=$(yq '.prompts.instructions.bugs'                   "$_CONFIG_FILE")
PROMPT_INSTRUCTIONS_FIX_VALIDATION=$(yq '.prompts.instructions.fix_validation' "$_CONFIG_FILE")

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

  local OTHER_PROVIDER
  [ "$LAST_PROVIDER" = "copilot" ] && OTHER_PROVIDER="cursor" || OTHER_PROVIDER="copilot"

  local SELECTED
  SELECTED=$(ui_print "${LAST_PROVIDER}
${OTHER_PROVIDER}" | fzf \
    --prompt="  AI Provider  " \
    --header="Select AI provider — last used: ${LAST_PROVIDER}" \
    --height=15% \
    --border=rounded \
    --margin=0,1,0,1)

  [ -z "$SELECTED" ] && return 1

  export AI_PROVIDER="$SELECTED"

  if [ ! -f "$_CONFIG_STATE" ]; then
    ui_print "last_provider: \"${SELECTED}\"" > "$_CONFIG_STATE"
    ui_print 'last_model: ""'                >> "$_CONFIG_STATE"
  else
    SELECTED="$SELECTED" yq -i '.last_provider = env(SELECTED)' "$_CONFIG_STATE"
  fi
}
