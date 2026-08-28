#!/bin/bash
# gen_branch_with_ia.sh — AI-powered branch name generator for Lazygit
#
# Generates a conventional branch name from staged changes using the
# configured AI provider. Presents the result for review before creating.
#
# Dependencies: git (staged changes required), yq
# Config:       settings.yaml  (prompts.branch)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

# _cleanup_ui
# Stops any active UI spinner before the script exits.
# Exit codes: always 0.
_cleanup_ui() {
  ui_spinner_stop
}

# _cancel
# Cleans up the UI and exits after an interruption.
# Exit codes: 130 = cancelled by user.
_cancel() {
  ui_spinner_stop
  ui_cancel
  exit 130
}

trap '_cleanup_ui' EXIT
trap '_cancel' INT TERM

clear
ui_header "🌿  AI Branch Name"

config_select_provider || { ui_cancel; exit 0; }
config_select_model || { ui_cancel; exit 0; }

FILES_CHANGED=$(git diff --cached --name-only | head -n 10)
if [ -z "$FILES_CHANGED" ]; then
  ui_error "No staged changes found."
  exit 1
fi

DIFF_STAT=$(git diff --cached --stat | head -n 15)
DIFF_SNIPPET=$(git diff --cached --unified=3 | head -n 60)

ui_prompt "Optional context (Enter to skip)"
USER_CONTEXT="$UI_INPUT"

VERBOSE=1
CONTEXT_SECTION=""
if [ -n "$USER_CONTEXT" ]; then
  CONTEXT_SECTION="USER PROVIDED CONTEXT:
$USER_CONTEXT

Consider this context when categorizing the changes and suggesting the branch name."
fi

PROMPT=$(render_template "$PROMPT_BRANCH_TEMPLATE" \
  "__FILES__"   "$FILES_CHANGED" \
  "__STATS__"   "$DIFF_STAT"     \
  "__DIFF__"    "$DIFF_SNIPPET"  \
  "__CONTEXT__" "$CONTEXT_SECTION")

ui_spinner_start "🧠  Generating branch name..."
RAW_NAME=$(generative_ia "$PROMPT" 0)
EXIT_CODE=$?
ui_spinner_stop
[ $EXIT_CODE -eq 130 ] && exit 0
[ $EXIT_CODE -ne 0 ] && ui_error "Failed to get AI response." && exit 1

CLEAN_NAME=$(ui_print "$RAW_NAME" | grep -oE '(feat|fix|chore|refactor|docs|test|ci|hotfix)/[a-z0-9][a-z0-9-]*' | head -n1)
[ -z "$CLEAN_NAME" ] && CLEAN_NAME=$(ui_print "$RAW_NAME" | tr -d '`()[]{}!@#$%^&*+=|\\<>?,;:'"'"'"' | grep -oE '[a-z0-9/][a-z0-9/_-]*' | tail -n1)

TEMP_FILE=$(mktemp)
ui_print "$CLEAN_NAME" > "$TEMP_FILE"

while true; do
  FINAL_NAME=$(cat "$TEMP_FILE")
  ui_content_box "Suggested Branch Name" "$FINAL_NAME"
  ui_prompt_proceed "create branch"

  case "$UI_ACTION" in
    proceed)
      if [ -n "$FINAL_NAME" ]; then
        GIT_OUT=$(git checkout -b "$FINAL_NAME" 2>&1)
        ui_content_box "Git Output" "$GIT_OUT"
        ui_success "Switched to: $FINAL_NAME"
      else
        ui_error "Branch name is empty. Aborted."
      fi
      break
      ;;
    edit)
      ${EDITOR:-nano} "$TEMP_FILE"
      ;;
    *)
      ui_cancel
      break
      ;;
  esac
done

rm -f "$TEMP_FILE"
