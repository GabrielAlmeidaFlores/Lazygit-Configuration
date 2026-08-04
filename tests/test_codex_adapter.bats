#!/usr/bin/env bats
# test_codex_adapter.bats — Unit tests for the Codex CLI adapter

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"
ADAPTER="$REPO_ROOT/commands/gateways/adapters/ia/codex.sh"

setup() {
  source "$LIB_DIR/ui.sh"
  export CODEX_BIN=/bin/echo
  MODEL="gpt-5.6-sol"
  FALLBACK_MODEL=""
  MAX_RETRIES=1
  TIMEOUT=5
  source "$ADAPTER"
}

@test "_generative_ia_codex: invokes non-interactive read-only execution" {
  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"exec --sandbox read-only --model gpt-5.6-sol -"* ]]
  [[ "$output" != *"review this diff"* ]]
  [[ "$output" != *"--ask-for-approval"* ]]
}

@test "_generative_ia_codex: uses the Codex default model when MODEL is empty" {
  MODEL=""

  run _generative_ia_codex "review this diff"

  [ "$status" -eq 0 ]
  [[ "$output" == *"exec --sandbox read-only -"* ]]
  [[ "$output" != *"review this diff"* ]]
  [[ "$output" != *"--model"* ]]
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
