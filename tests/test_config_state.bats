#!/usr/bin/env bats
# test_config_state.bats — Unit tests for config_select_provider in lib/config.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"

setup() {
  load helpers/mock_fzf

  export _CONFIG_FILE="/dev/null"
  export _CONFIG_STATE="$(mktemp /tmp/bats_state_XXXXXX.yaml)"
  rm -f "$_CONFIG_STATE"

  export AI_PROVIDER="copilot"

  export _CFG_SKIP_LOAD=1
  source "$LIB_DIR/ui.sh"
  source "$LIB_DIR/config.sh"
  unset _CFG_SKIP_LOAD

  MOCK_FZF_OUTPUT="copilot"
  MOCK_FZF_EXIT=0
}

teardown() {
  rm -f "$_CONFIG_STATE"
}

@test "config_select_provider: creates state file on first run" {
  MOCK_FZF_OUTPUT="copilot"
  config_select_provider
  [ -f "$_CONFIG_STATE" ]
}

@test "config_select_provider: state file contains last_provider key" {
  MOCK_FZF_OUTPUT="cursor"
  config_select_provider
  grep -q "last_provider" "$_CONFIG_STATE"
}

@test "config_select_provider: sets AI_PROVIDER to the selected value" {
  MOCK_FZF_OUTPUT="cursor"
  config_select_provider
  [ "$AI_PROVIDER" = "cursor" ]
}

@test "config_select_provider: sets AI_PROVIDER to copilot when copilot selected" {
  MOCK_FZF_OUTPUT="copilot"
  config_select_provider
  [ "$AI_PROVIDER" = "copilot" ]
}

@test "config_select_provider: sets AI_PROVIDER to codex when codex selected" {
  MOCK_FZF_OUTPUT="codex"
  config_select_provider
  [ "$AI_PROVIDER" = "codex" ]
}

@test "config_select_provider: persists codex as the last provider" {
  MOCK_FZF_OUTPUT="codex"
  config_select_provider
  [ "$(yq '.last_provider' "$_CONFIG_STATE")" = "codex" ]
}

@test "config_select_provider: returns 1 when user cancels" {
  MOCK_FZF_OUTPUT=""
  run config_select_provider
  [ "$status" -eq 1 ]
}

@test "config_select_provider: does not create state file when cancelled" {
  MOCK_FZF_OUTPUT=""
  config_select_provider || true
  [ ! -f "$_CONFIG_STATE" ]
}

@test "config_select_provider: state file contains last_model key" {
  MOCK_FZF_OUTPUT="copilot"
  config_select_provider
  grep -q "last_model" "$_CONFIG_STATE"
}

@test "config_select_model: sets the selected Codex model" {
  AI_PROVIDER="codex"
  CODEX_MODELS="gpt-5.6-terra (medium — balanced coding)"
  MODEL=""
  MOCK_FZF_OUTPUT="gpt-5.6-terra (medium — balanced coding)"

  config_select_model

  [ "$MODEL" = "gpt-5.6-terra" ]
}
