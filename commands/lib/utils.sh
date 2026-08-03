#!/bin/bash
# lib/utils.sh — Shared utility functions for AI-powered Lazygit commands
#
# Sourced by gateways/generative-ia.sh — available in all main scripts.
#
# Functions defined:
#   render_template

# render_template TEMPLATE KEY1 VAL1 [KEY2 VAL2 ...]
# Replaces every occurrence of __KEY__ placeholders in TEMPLATE with their
# corresponding values. Pairs are processed left-to-right; pass as many
# KEY/VAL pairs as needed. Prints the rendered string.
render_template() {
  local RESULT="$1"; shift
  while [ $# -ge 2 ]; do
    RESULT="${RESULT//$1/$2}"; shift 2
  done
  ui_print "$RESULT"
}
