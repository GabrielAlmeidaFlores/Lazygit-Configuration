#!/usr/bin/env bash
# helpers/mock_yq.sh — yq stub for isolated BATS tests
#
# Sources this file to override the real yq binary with a controllable mock.
# Tests set MOCK_YQ_OUTPUT before calling functions that use yq internally.
#
# Usage in .bats files:
#   load helpers/mock_yq
#   MOCK_YQ_OUTPUT="copilot"
#   run _cfg_str '.ai.provider // "copilot"' "$FIXTURE_FILE"
#
# MOCK_YQ_OUTPUT   string returned by every yq invocation during the test
# MOCK_YQ_EXIT     exit code returned (default 0)

MOCK_YQ_OUTPUT="${MOCK_YQ_OUTPUT:-}"
MOCK_YQ_EXIT="${MOCK_YQ_EXIT:-0}"

yq() {
  [ -n "$MOCK_YQ_OUTPUT" ] && printf '%s\n' "$MOCK_YQ_OUTPUT"
  return "${MOCK_YQ_EXIT:-0}"
}
export -f yq
