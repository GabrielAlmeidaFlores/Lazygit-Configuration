#!/bin/bash
# gen_branch_with_ia.sh — AI-powered branch name generator for Lazygit
#
# Generates a conventional branch name from staged changes using the
# configured AI provider. Presents the result for review before creating.
#
# Dependencies: git (staged changes required)
# Config:       commands/config.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

clear

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
  CONTEXT_SECTION="

USER PROVIDED CONTEXT:
$USER_CONTEXT

Consider this context when categorizing the changes and suggesting the branch name."
fi

PROMPT="As a Senior Developer, categorize these git changes and suggest a branch name.

FILES:
$FILES_CHANGED

STATS:
$DIFF_STAT

DIFF SNIPPET:
$DIFF_SNIPPET

LANGUAGE REQUIREMENT (CRITICAL):
- MUST use ONLY English language for the branch name.
- NO Spanish, Portuguese, or any other language allowed.

DECISION LOGIC:
1. If existing logic is being corrected, replaced, or adjusted → fix/
2. If new files or new modules are added → feat/
3. If only config, deps, docker, ci, build files changed → chore/
4. If code structure changes but behavior is same → refactor/
5. If only markdown or comments → docs/

STRICT RULES:
- Use kebab-case. Be specific. No emojis.
- Output ONLY the branch name. No explanations.
$CONTEXT_SECTION"

RAW_NAME=$(generative_ia "$PROMPT" "$VERBOSE")
EXIT_CODE=$?
[ $EXIT_CODE -eq 130 ] && exit 0
[ $EXIT_CODE -ne 0 ] && ui_error "Failed to get AI response." && exit 1

CLEAN_NAME=$(echo "$RAW_NAME" | grep -oE '(feat|fix|chore|refactor|docs|test|ci|hotfix)/[a-z0-9][a-z0-9-]*' | head -n1)
[ -z "$CLEAN_NAME" ] && CLEAN_NAME=$(echo "$RAW_NAME" | tr -d '`()[]{}!@#$%^&*+=|\\<>?,;:'"'"'"' | grep -oE '[a-z0-9/][a-z0-9/_-]*' | tail -n1)

TEMP_FILE=$(mktemp)
echo "$CLEAN_NAME" > "$TEMP_FILE"

while true; do
  FINAL_NAME=$(cat "$TEMP_FILE")
  ui_content_box "Suggested Branch Name" "$FINAL_NAME"
  ui_prompt_proceed "create branch"

  case "$UI_ACTION" in
    proceed)
      if [ -n "$FINAL_NAME" ]; then
        git checkout -b "$FINAL_NAME"
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
