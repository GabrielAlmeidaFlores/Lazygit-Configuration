#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  source "$REPO_ROOT/commands/lib/ui.sh"
  source "$REPO_ROOT/commands/gateways/adapters/ia/_helpers.sh"
}

@test "_build_model_fallback_chain: follows the Cursor model order" {
  _build_model_fallback_chain "gpt-5.4-nano-none" "gpt-5.4-nano-none (low),gpt-5.4-mini-low (medium),gpt-5.3-codex-low (medium)"

  [ "${MODEL_FALLBACK_CHAIN[*]}" = "gpt-5.4-nano-none gpt-5.4-mini-low gpt-5.3-codex-low" ]
}

@test "_build_model_fallback_chain: follows the Copilot model order" {
  _build_model_fallback_chain "gemini-3.1-pro-preview" "gemini-3.1-pro-preview (medium),claude-sonnet-4.5 (medium),claude-sonnet-4.6 (medium-high)"

  [ "${MODEL_FALLBACK_CHAIN[*]}" = "gemini-3.1-pro-preview claude-sonnet-4.5 claude-sonnet-4.6" ]
}

@test "_build_model_fallback_chain: follows the Codex model order" {
  _build_model_fallback_chain "gpt-5.6-terra" "gpt-5.6-terra (medium),gpt-5.6-luna (low),gpt-5.5 (high)"

  [ "${MODEL_FALLBACK_CHAIN[*]}" = "gpt-5.6-terra gpt-5.6-luna gpt-5.5" ]
}
