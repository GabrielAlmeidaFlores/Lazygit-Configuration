#!/bin/bash
# gen_commit_with_ia.sh — AI-powered commit message generator for Lazygit
#
# Generates a conventional commit message from staged changes using the
# configured AI provider. Presents the result for review before committing.
# After committing, syncs the commit body to the open PR description if one
# exists for the current branch.
#
# Dependencies: git (staged changes required), yq
# Config:       settings.yaml  (prompts.commit)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"
source "$SCRIPT_DIR/gateways/adapters/scm/gateway.sh"

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
ui_header "📝  AI Commit Message"

config_select_model || { ui_cancel; exit 0; }

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

PROMPT=$(render_template "$PROMPT_COMMIT_TEMPLATE" \
  "__DIFF__"    "$DIFF_SNIPPET" \
  "__CONTEXT__" "$CONTEXT_SECTION")

ui_spinner_start "🧠  Generating commit message..."
RAW_MSG=$(generative_ia "$PROMPT" 0)
EXIT_CODE=$?
ui_spinner_stop
[ $EXIT_CODE -eq 130 ] && exit 0
[ $EXIT_CODE -ne 0 ] && ui_error "Failed to get AI response." && exit 1

RAW_MSG=$(ui_print "$RAW_MSG" | grep -v "^Co-authored-by:")

TEMP_MSG_FILE=$(mktemp)
ui_print "$RAW_MSG" > "$TEMP_MSG_FILE"

COMMITTED=false

while true; do
  RAW_MSG=$(cat "$TEMP_MSG_FILE")
  ui_content_box "Suggested Commit Message" "$RAW_MSG"
  ui_prompt_proceed "commit"

  case "$UI_ACTION" in
    proceed)
      if [ -n "$RAW_MSG" ]; then
        git commit -F "$TEMP_MSG_FILE"
        ui_success "Committed successfully."
        COMMITTED=true
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

# _sync_pr_description TITLE BODY
# If an open PR exists for the current branch, updates its description with
# the commit body. Detects the provider from the remote URL automatically.
_sync_pr_description() {
  local TITLE="$1" BODY="$2"
  [ -z "$BODY" ] && return 0

  scm_detect 2>/dev/null || return 0

  case "$SCM_PROVIDER" in
    github)
      local PR_NUMBER
      PR_NUMBER=$(GH_TOKEN="$_GH_PAT" gh pr view --json number -q '.number' 2>/dev/null)
      [ -z "$PR_NUMBER" ] && return 0
      GH_TOKEN="$_GH_PAT" gh pr edit "$PR_NUMBER" --body "$BODY" >/dev/null 2>&1 \
        && ui_success "PR #${PR_NUMBER} description updated." \
        || ui_warning "Could not update PR description."
      ;;
    azure-devops)
      [ -z "$_AZ_API_BASE" ] && return 0
      local PR_JSON PR_ID
      PR_JSON=$(_az_curl GET "${_AZ_API_BASE}/pullrequests?api-version=7.1&searchCriteria.status=active&searchCriteria.sourceRefName=refs/heads/$(git branch --show-current)" 2>/dev/null)
      PR_ID=$(ui_print "$PR_JSON" | jq -r '.value[0].pullRequestId // empty' 2>/dev/null)
      [ -z "$PR_ID" ] && return 0
      local PAYLOAD
      PAYLOAD=$(jq -n --arg body "$BODY" '{"description": $body}')
      _az_curl PATCH "${_AZ_API_BASE}/pullrequests/${PR_ID}?api-version=7.1" "$PAYLOAD" >/dev/null 2>&1 \
        && ui_success "PR #${PR_ID} description updated." \
        || ui_warning "Could not update PR description."
      ;;
  esac
}

if [ "$COMMITTED" = true ]; then
  COMMIT_TITLE=$(ui_print "$RAW_MSG" | head -1)
  COMMIT_BODY=$(ui_print "$RAW_MSG" | tail -n +3)
  _sync_pr_description "$COMMIT_TITLE" "$COMMIT_BODY"
fi
