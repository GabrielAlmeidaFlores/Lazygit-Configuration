#!/usr/bin/env bats
# test_codex_adapter.bats — Unit tests for the Codex CLI adapter

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"
ADAPTER="$REPO_ROOT/commands/gateways/adapters/ia/codex.sh"

setup() {
  source "$LIB_DIR/ui.sh"
  export CODEX_BIN=/bin/echo
  MODEL="gpt-5.6-sol"
  CODEX_DEFAULT_MODEL="gpt-5.6-luna"
  MAX_RETRIES=1
  TIMEOUT=5
  source "$ADAPTER"
}

@test "_generative_ia_codex: invokes non-interactive read-only execution" {
  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"exec --ephemeral --color never --sandbox read-only --model gpt-5.6-sol -"* ]]
  [[ "$output" != *"review this diff"* ]]
  [[ "$output" != *"--ask-for-approval"* ]]
}

@test "_generative_ia_codex: uses the configured default model when MODEL is empty" {
  MODEL=""

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"exec --ephemeral --color never --sandbox read-only --model gpt-5.6-luna -"* ]]
  [[ "$output" != *"review this diff"* ]]
}

@test "_generative_ia_codex: sends the prompt through stdin" {
  local MOCK_CODEX_BIN="$BATS_TEST_TMPDIR/codex-stdin"
  ui_print '#!/bin/bash
cat' > "$MOCK_CODEX_BIN"
  chmod +x "$MOCK_CODEX_BIN"
  CODEX_BIN="$MOCK_CODEX_BIN"

  run _generative_ia_codex "prompt through stdin"

  [ "$status" -eq 0 ]
  [ "$output" = "prompt through stdin" ]
}

@test "_generative_ia_codex: advances to the next configured model after an empty response" {
  local MOCK_CODEX_BIN="$BATS_TEST_TMPDIR/codex-fallback"
  local RESPONSE_FILE="$BATS_TEST_TMPDIR/codex-response"
  ui_print "fallback response" > "$RESPONSE_FILE"
  ui_print '#!/bin/bash
case "$*" in
  *gpt-5.6-terra*) exit 0 ;;
  *gpt-5.6-luna*) cat "$CODEX_RESPONSE_FILE" ;;
  *) exit 1 ;;
esac' > "$MOCK_CODEX_BIN"
  chmod +x "$MOCK_CODEX_BIN"
  export CODEX_RESPONSE_FILE="$RESPONSE_FILE"
  CODEX_BIN="$MOCK_CODEX_BIN"
  MODEL="gpt-5.6-terra"
  CODEX_MODELS="gpt-5.6-terra (medium),gpt-5.6-luna (low),gpt-5.5 (high)"

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"fallback response"* ]]
}

@test "_generative_ia_codex: identifies an empty response" {
  local MOCK_CODEX_BIN="$BATS_TEST_TMPDIR/codex-empty"
  ui_print '#!/bin/bash
exit 0' > "$MOCK_CODEX_BIN"
  chmod +x "$MOCK_CODEX_BIN"
  CODEX_BIN="$MOCK_CODEX_BIN"
  CODEX_MODELS=""

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 1 ]
  [[ "$output" == *"empty response"* ]]
}

@test "_generative_ia_codex: continues through configured models" {
  local MOCK_CODEX_BIN="$BATS_TEST_TMPDIR/codex-explicit-fallback"
  local RESPONSE_FILE="$BATS_TEST_TMPDIR/codex-response"
  ui_print "final fallback response" > "$RESPONSE_FILE"
  ui_print '#!/bin/bash
case "$*" in
  *gpt-5.5*) cat "$CODEX_RESPONSE_FILE" ;;
  *) exit 0 ;;
esac' > "$MOCK_CODEX_BIN"
  chmod +x "$MOCK_CODEX_BIN"
  export CODEX_RESPONSE_FILE="$RESPONSE_FILE"
  CODEX_BIN="$MOCK_CODEX_BIN"
  MODEL="gpt-5.6-terra"
  CODEX_MODELS="gpt-5.6-terra (medium),gpt-5.6-luna (low),gpt-5.5 (high)"

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"final fallback response"* ]]
}

@test "_generative_ia_codex: rejects a missing binary" {
  CODEX_BIN="/missing/codex"

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Codex binary not found"* ]]
}

@test "_generative_ia_codex: identifies a missing PATH binary" {
  CODEX_BIN=""

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Codex binary not found in PATH"* ]]
}

@test "_generative_ia_codex: reports temporary-file creation failures" {
  mktemp() {
    return 1
  }

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not create temporary file"* ]]
}
