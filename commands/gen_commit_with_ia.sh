#!/bin/bash
# gen_commit_with_ia.sh — AI-powered commit message generator for Lazygit
#
# Generates a conventional commit message from staged changes using the
# configured AI provider. Presents the result for review before committing.
#
# Dependencies: git (staged changes required)
# Config:       commands/config.env  (PROMPT_COMMIT_TEMPLATE)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

clear
ui_header "AI Commit Message"

FILES=$(git diff --cached --name-only | head -n 15 | tr '\n' ', ')
if [ -z "$FILES" ]; then
  ui_error "No staged changes found."
  exit 1
fi

DIFF_SNIPPET=$(git diff --cached --unified=3 --no-color | head -n 200)

ui_prompt "Optional context (Enter to skip)"
USER_CONTEXT="$UI_INPUT"

VERBOSE=1
CONTEXT_SECTION=""
[ -n "$USER_CONTEXT" ] && CONTEXT_SECTION="USER PROVIDED CONTEXT: $USER_CONTEXT"

# render_template TEMPLATE KEY1 VAL1 [KEY2 VAL2 ...]
# Replaces all __KEY__ placeholders in TEMPLATE with their corresponding values.
render_template() {
  local RESULT="$1"; shift
  while [ $# -ge 2 ]; do
    RESULT="${RESULT//$1/$2}"; shift 2
  done
  echo "$RESULT"
}

PROMPT=$(render_template "$PROMPT_COMMIT_TEMPLATE" \
  "__DIFF__"    "$DIFF_SNIPPET" \
  "__CONTEXT__" "$CONTEXT_SECTION")

RAW_MSG=$(generative_ia "$PROMPT" "$VERBOSE")
EXIT_CODE=$?
[ $EXIT_CODE -eq 130 ] && exit 0
[ $EXIT_CODE -ne 0 ] && ui_error "Failed to get AI response." && exit 1

TEMP_MSG_FILE=$(mktemp)
echo "$RAW_MSG" > "$TEMP_MSG_FILE"

while true; do
  RAW_MSG=$(cat "$TEMP_MSG_FILE")
  ui_content_box "Suggested Commit Message" "$RAW_MSG"
  ui_prompt_proceed "commit"

  case "$UI_ACTION" in
    proceed)
      if [ -n "$RAW_MSG" ]; then
        git commit -F "$TEMP_MSG_FILE"
        ui_success "Committed successfully."
      else
        ui_error "Message is empty. Commit aborted."
      fi
      break
      ;;
    edit)
      ${EDITOR:-nano} "$TEMP_MSG_FILE"
      ;;
    *)
      ui_cancel
      break
      ;;
  esac
done

rm -f "$TEMP_MSG_FILE"
