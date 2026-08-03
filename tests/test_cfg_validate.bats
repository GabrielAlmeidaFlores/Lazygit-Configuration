#!/usr/bin/env bats
# test_cfg_validate.bats — Unit tests for _cfg_validate in lib/config.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"

setup() {
  source "$LIB_DIR/ui.sh"

  export _CONFIG_FILE="/dev/null"
  export _CONFIG_STATE="/dev/null"
  export _CFG_SKIP_LOAD=1
  source "$LIB_DIR/config.sh"
  unset _CFG_SKIP_LOAD

  _set_valid_vars
}

_set_valid_vars() {
  AI_PROVIDER="${1:-copilot}"
  MAX_RETRIES="${2:-2}"
  TIMEOUT="${3:-60}"
  PROMPT_COMMIT_TEMPLATE="${PROMPT_COMMIT_TEMPLATE:-PROMPT}"
  PROMPT_BRANCH_TEMPLATE="${PROMPT_BRANCH_TEMPLATE:-PROMPT}"
  PROMPT_ANALYSIS_TEMPLATE="${PROMPT_ANALYSIS_TEMPLATE:-PROMPT}"
  PROMPT_ANALYSIS_PASS2_TEMPLATE="${PROMPT_ANALYSIS_PASS2_TEMPLATE:-PROMPT}"
  PROMPT_ANALYSIS_PASS3_TEMPLATE="${PROMPT_ANALYSIS_PASS3_TEMPLATE:-PROMPT}"
  PROMPT_COMMENT_TEMPLATE="${PROMPT_COMMENT_TEMPLATE:-PROMPT}"
}

@test "_cfg_validate: passes with valid copilot config" {
  _set_valid_vars copilot 2 60
  run _cfg_validate
  [ "$status" -eq 0 ]
}

@test "_cfg_validate: passes with valid cursor config" {
  _set_valid_vars cursor 3 120
  run _cfg_validate
  [ "$status" -eq 0 ]
}

@test "_cfg_validate: rejects unknown provider" {
  AI_PROVIDER="openai"
  run _cfg_validate
  [ "$status" -gt 0 ]
  [[ "$output" == *"ai.provider"* ]]
}

@test "_cfg_validate: rejects non-numeric max_retries" {
  MAX_RETRIES="abc"
  run _cfg_validate
  [ "$status" -gt 0 ]
  [[ "$output" == *"max_retries"* ]]
}

@test "_cfg_validate: rejects zero max_retries" {
  MAX_RETRIES="0"
  run _cfg_validate
  [ "$status" -gt 0 ]
  [[ "$output" == *"max_retries"* ]]
}

@test "_cfg_validate: rejects non-numeric timeout" {
  TIMEOUT="fast"
  run _cfg_validate
  [ "$status" -gt 0 ]
  [[ "$output" == *"timeout"* ]]
}

@test "_cfg_validate: rejects empty commit template" {
  PROMPT_COMMIT_TEMPLATE=""
  run _cfg_validate
  [ "$status" -gt 0 ]
  [[ "$output" == *"prompts.commit"* ]]
}

@test "_cfg_validate: accumulates multiple errors" {
  AI_PROVIDER="badprovider"
  MAX_RETRIES="abc"
  TIMEOUT="0"
  PROMPT_COMMIT_TEMPLATE=""
  PROMPT_BRANCH_TEMPLATE=""
  run _cfg_validate
  [ "$status" -ge 4 ]
}
