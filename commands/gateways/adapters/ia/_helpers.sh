#!/bin/bash
# _helpers.sh — Shared utilities for AI provider adapters
#
# _run_with_timeout DURATION CMD [ARGS...]
#   Runs CMD with a timeout of DURATION seconds.
#   Uses the system `timeout` or `gtimeout` command when available.
#   Falls back to a background process with a watcher on systems without either.
#   Returns 124 if the command timed out, otherwise the command's exit code.

# _run_with_timeout DURATION CMD [ARGS...]
# Runs CMD with a timeout of DURATION seconds.
# Uses system `timeout` or `gtimeout` when available; falls back to a
# background process with a watcher. Returns 124 on timeout.
_run_with_timeout() {
  local DURATION=$1
  shift

  if command -v timeout >/dev/null 2>&1; then
    timeout "$DURATION" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$DURATION" "$@"
  else
    "$@" <&0 &
    local PID=$!
    ( sleep "$DURATION" && kill "$PID" 2>/dev/null ) &
    local WATCHER=$!
    wait "$PID" 2>/dev/null
    local EXIT_CODE=$?
    kill "$WATCHER" 2>/dev/null
    wait "$WATCHER" 2>/dev/null
    if kill -0 "$PID" 2>/dev/null; then
      kill "$PID" 2>/dev/null
      wait "$PID" 2>/dev/null
      return 124
    fi
    return $EXIT_CODE
  fi
}
