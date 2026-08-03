#!/usr/bin/env bats
# test_cfg_str.bats — Unit tests for the _cfg_str helper in lib/config.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"

setup() {
  load helpers/mock_yq

  source "$LIB_DIR/ui.sh"

  export _CONFIG_FILE="/dev/null"
  export _CONFIG_STATE="/dev/null"
  export _CFG_SKIP_LOAD=1
  source "$LIB_DIR/config.sh"
  unset _CFG_SKIP_LOAD
}

@test "_cfg_str: returns empty string when yq outputs literal double-quotes" {
  MOCK_YQ_OUTPUT='""'
  result=$(_cfg_str '.ai.model // ""' "$_CONFIG_FILE")
  [ -z "$result" ]
}

@test "_cfg_str: returns empty string when yq outputs null" {
  MOCK_YQ_OUTPUT="null"
  result=$(_cfg_str '.ai.model // ""' "$_CONFIG_FILE")
  [ -z "$result" ]
}

@test "_cfg_str: returns value unchanged for non-empty strings" {
  MOCK_YQ_OUTPUT="claude-sonnet-4.5"
  result=$(_cfg_str '.ai.model // ""' "$_CONFIG_FILE")
  [ "$result" = "claude-sonnet-4.5" ]
}

@test "_cfg_str: returns value unchanged for paths with slashes" {
  MOCK_YQ_OUTPUT="/usr/local/bin/copilot"
  result=$(_cfg_str '.providers.copilot.bin // ""' "$_CONFIG_FILE")
  [ "$result" = "/usr/local/bin/copilot" ]
}

@test "_cfg_str: returns empty string for single-quoted empty (yq edge case)" {
  MOCK_YQ_OUTPUT="''"
  result=$(_cfg_str '.azure_devops.pat // ""' "$_CONFIG_FILE")
  [ -z "$result" ]
}
