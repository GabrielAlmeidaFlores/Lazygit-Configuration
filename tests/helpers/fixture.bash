#!/usr/bin/env bash
# helpers/fixture.bash — shared fixture helpers for BATS tests
#
# setup_config_fixture PATH [OVERRIDES...]
# Creates a minimal valid settings.yaml at PATH for tests that need to source
# lib/config.sh. OVERRIDES are yq-style assignments applied after creation.
#
# teardown_fixture PATH
# Removes the fixture file created by setup_config_fixture.

FIXTURE_MIN_CONFIG='
ai:
  provider: copilot
  model:
  max_retries: 2
  timeout: 60
providers:
  cursor:
    bin:
    mode: ask
    models:
  copilot:
    bin:
    models:
azure_devops:
  pat:
prompts:
  commit: "COMMIT_PROMPT"
  branch: "BRANCH_PROMPT"
  analysis_pass1: "PASS1_PROMPT"
  analysis_pass2: "PASS2_PROMPT"
  analysis_pass3: "PASS3_PROMPT"
  comment: "COMMENT_PROMPT"
  instructions:
    architecture: "ARCH"
    security: "SEC"
    code_quality: "CQ"
    test_coverage: "TC"
    performance: "PERF"
    spelling: "SPELL"
    bugs: "BUGS"
    fix_validation: "FIXVAL"
'

setup_config_fixture() {
  local _PATH="$1"
  printf '%s\n' "$FIXTURE_MIN_CONFIG" > "$_PATH"
}

teardown_fixture() {
  rm -f "$1"
}
