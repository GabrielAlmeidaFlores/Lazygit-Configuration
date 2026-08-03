#!/usr/bin/env bash
# helpers/mock_fzf.sh — fzf stub for isolated BATS tests
#
# Overrides fzf to return a predetermined value without requiring a TTY.
# Tests set MOCK_FZF_OUTPUT before calling functions that use fzf.
#
# MOCK_FZF_OUTPUT   line returned as if the user selected it (default empty)
# MOCK_FZF_EXIT     exit code returned — 0 = selected, 130 = cancelled

MOCK_FZF_OUTPUT="${MOCK_FZF_OUTPUT:-}"
MOCK_FZF_EXIT="${MOCK_FZF_EXIT:-0}"

fzf() {
  [ "${MOCK_FZF_EXIT:-0}" -ne 0 ] && return "$MOCK_FZF_EXIT"
  [ -n "$MOCK_FZF_OUTPUT" ] && printf '%s\n' "$MOCK_FZF_OUTPUT"
  return 0
}
export -f fzf
