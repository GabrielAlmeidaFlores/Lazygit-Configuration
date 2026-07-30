#!/bin/bash
# review_pr.sh — Interactive AI-powered PR review for Lazygit
#
# Lists open PRs, runs focused AI analyses, and posts natural code review
# comments on GitHub. All AI prompts are configured in config.env.
#
# Dependencies: gh, fzf, jq
# Config:       commands/config.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="/Users/gabrielfloresousion/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

clear

for dep in gh fzf jq; do
  if ! command -v "$dep" &>/dev/null; then
    ui_error "'$dep' not found. Please install it before continuing."
    exit 1
  fi
done

# render_template TEMPLATE KEY1 VAL1 [KEY2 VAL2 ...]
# Replaces all __KEY__ placeholders in TEMPLATE with their corresponding values.
render_template() {
  local RESULT="$1"; shift
  while [ $# -ge 2 ]; do
    RESULT="${RESULT//$1/$2}"; shift 2
  done
  echo "$RESULT"
}

ui_header "AI PR Review"
ui_step "Fetching open PRs..."

PR_JSON=$(gh pr list --state open --json number,title,author,headRefName 2>/dev/null)

if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "[]" ]; then
  ui_error "No open PRs found in this repository."
  exit 0
fi

PR_LIST=$(echo "$PR_JSON" | jq -r '.[] | "#\(.number)  \(.title)  [\(.author.login) → \(.headRefName)]"')

SELECTED_PR=$(echo "$PR_LIST" | fzf \
  --prompt="  Select PR  " \
  --header="Open PRs — Enter to select, Ctrl+C to exit" \
  --height=50% \
  --border=rounded \
  --ansi)

[ -z "$SELECTED_PR" ] && ui_cancel && exit 0

PR_NUMBER=$(echo "$SELECTED_PR" | grep -oE '^#[0-9]+' | tr -d '#')
PR_TITLE=$(echo "$SELECTED_PR" | sed -E 's/^#[0-9]+  //' | sed 's/  \[.*//')

CURRENT_PROVIDER="${AI_PROVIDER:-copilot}"

DEFAULT_CURSOR_MODELS="default
claude-4-5-sonnet
claude-4-5
claude-4-opus
gpt-4o
gpt-4.1
o3
gemini-2.5-pro"

DEFAULT_COPILOT_MODELS="default
claude-sonnet-4.6
claude-sonnet-4.5
claude-opus-4.6
gpt-5.3-codex
gemini-3.1-pro-preview"

if [ "$CURRENT_PROVIDER" = "cursor" ]; then
  MODEL_LIST="${CURSOR_MODELS:+default
$(echo "$CURSOR_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_CURSOR_MODELS}"
else
  MODEL_LIST="${COPILOT_MODELS:+default
$(echo "$COPILOT_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_COPILOT_MODELS}"
fi

SELECTED_MODEL=$(echo "$MODEL_LIST" | fzf \
  --prompt="  Model ($CURRENT_PROVIDER)  " \
  --header="AI model for this session — Enter to confirm" \
  --height=50% \
  --border=rounded)

[ -z "$SELECTED_MODEL" ] && ui_cancel && exit 0

if [ "$SELECTED_MODEL" != "default" ]; then
  export MODEL="$SELECTED_MODEL"
  MODEL_LABEL="$SELECTED_MODEL"
else
  MODEL_LABEL="${MODEL:-default}"
fi

ANALYSES_RAW=$(printf "Architecture\nSecurity\nCode Quality\nTest Coverage\nPerformance\nAll" | fzf \
  --multi \
  --prompt="  Analyses (Tab to select)  " \
  --header="Select one or more analysis types — Enter to confirm" \
  --height=50% \
  --border=rounded)

[ -z "$ANALYSES_RAW" ] && ui_cancel && exit 0

if echo "$ANALYSES_RAW" | grep -q "^All$"; then
  ANALYSES_RAW="Architecture
Security
Code Quality
Test Coverage
Performance"
fi

ui_panel \
  "PR #${PR_NUMBER}  ·  ${PR_TITLE}" \
  "Model: ${MODEL_LABEL}  ·  Provider: ${CURRENT_PROVIDER}"

ui_step "Fetching PR data..."

PR_INFO=$(gh pr view "$PR_NUMBER" --json title,body,author,additions,deletions,changedFiles 2>/dev/null)

if [ -z "$PR_INFO" ]; then
  ui_error "Failed to fetch PR #${PR_NUMBER} data."
  exit 1
fi

PR_BODY=$(echo "$PR_INFO" | jq -r '.body // "No description provided."')
PR_AUTHOR=$(echo "$PR_INFO" | jq -r '.author.login')
PR_ADDITIONS=$(echo "$PR_INFO" | jq -r '.additions')
PR_DELETIONS=$(echo "$PR_INFO" | jq -r '.deletions')
PR_FILES=$(echo "$PR_INFO" | jq -r '.changedFiles')
PR_DIFF=$(gh pr diff "$PR_NUMBER" 2>/dev/null | head -n 400)

ui_info "+${PR_ADDITIONS}  -${PR_DELETIONS}  across ${PR_FILES} file(s)"

RESULTS_DIR=$(mktemp -d /tmp/pr_review_XXXXXX)
trap 'rm -rf "$RESULTS_DIR"' EXIT
ALL_ISSUES=()
ANALYSES_ORDER=()

# get_instructions ANALYSIS_NAME
# Returns the instruction text for a given analysis type, sourced from
# config.env variables (PROMPT_INSTRUCTIONS_*) with hardcoded fallbacks.
get_instructions() {
  case "$1" in
    "Architecture")  echo "${PROMPT_INSTRUCTIONS_ARQUITETURA:-Check for architectural issues: separation of concerns, coupling, SOLID violations.}" ;;
    "Security")      echo "${PROMPT_INSTRUCTIONS_SEGURANCA:-Check for security issues: exposed secrets, injection risks, unsanitized inputs.}" ;;
    "Code Quality")  echo "${PROMPT_INSTRUCTIONS_QUALIDADE:-Check for code quality issues: duplication, complexity, poor naming, missing error handling.}" ;;
    "Test Coverage") echo "${PROMPT_INSTRUCTIONS_TESTES:-Check for test coverage issues: missing tests for new functionality, edge cases.}" ;;
    "Performance")   echo "${PROMPT_INSTRUCTIONS_PERFORMANCE:-Check for performance issues: N+1 queries, inefficient loops, blocking operations.}" ;;
  esac
}

DEFAULT_ANALYSIS_TEMPLATE="You are a senior software engineer performing a focused code review.

Analyze ONLY for: __ANALYSIS_NAME__

PR TITLE: __PR_TITLE__
PR AUTHOR: __PR_AUTHOR__
PR DESCRIPTION:
__PR_BODY__

CODE DIFF (up to 400 lines):
__PR_DIFF__

SPECIFIC ANALYSIS FOCUS:
__INSTRUCTIONS__

STRICT OUTPUT FORMAT — do not deviate:
If no issues found:
  ANALYSIS_STATUS: OK

If issues found:
  ANALYSIS_STATUS: ISSUES_FOUND
  ISSUE: <one concise description per line, include filename if identifiable from diff>
  ISSUE: <another issue>

No preamble, no explanation, no closing remarks. Output only the structured lines above."

# run_analysis ANALYSIS_NAME INSTRUCTIONS
# Calls generative_ia with a focused prompt for the given analysis type.
# Writes ANALYSIS_STATUS (OK or ISSUES_FOUND) to $RESULTS_DIR/<key>.status
# and issues to $RESULTS_DIR/<key>.issues. Appends to ALL_ISSUES array.
# Returns 130 on user cancellation, 1 on AI failure, 0 on success.
run_analysis() {
  local ANALYSIS_NAME="$1"
  local INSTRUCTIONS="$2"
  local ANALYSIS_KEY="${ANALYSIS_NAME// /_}"

  ui_step "Analyzing  ${ANALYSIS_NAME}  (Ctrl+C to cancel)"

  local TEMPLATE="${PROMPT_ANALYSIS_TEMPLATE:-$DEFAULT_ANALYSIS_TEMPLATE}"
  local PROMPT
  PROMPT=$(render_template "$TEMPLATE" \
    "__ANALYSIS_NAME__" "$ANALYSIS_NAME" \
    "__PR_TITLE__"      "$PR_TITLE"      \
    "__PR_AUTHOR__"     "$PR_AUTHOR"     \
    "__PR_BODY__"       "$PR_BODY"       \
    "__PR_DIFF__"       "$PR_DIFF"       \
    "__INSTRUCTIONS__"  "$INSTRUCTIONS")

  local RESPONSE
  RESPONSE=$(generative_ia "$PROMPT" 1)
  local EXIT_CODE=$?

  [ $EXIT_CODE -eq 130 ] && return 130

  if [ $EXIT_CODE -ne 0 ] || [ -z "$RESPONSE" ]; then
    echo "ERROR" > "$RESULTS_DIR/${ANALYSIS_KEY}.status"
    return 1
  fi

  local STATUS
  STATUS=$(echo "$RESPONSE" | grep "^ANALYSIS_STATUS:" | head -1 | sed 's/ANALYSIS_STATUS: //')
  echo "$STATUS" > "$RESULTS_DIR/${ANALYSIS_KEY}.status"

  if [ "$STATUS" = "ISSUES_FOUND" ]; then
    local ISSUES
    ISSUES=$(echo "$RESPONSE" | grep "^ISSUE:" | sed 's/^ISSUE: //')
    echo "$ISSUES" > "$RESULTS_DIR/${ANALYSIS_KEY}.issues"
    while IFS= read -r ISSUE_LINE; do
      [ -n "$ISSUE_LINE" ] && ALL_ISSUES+=("[$ANALYSIS_NAME] $ISSUE_LINE")
    done <<< "$ISSUES"
  fi
}

while IFS= read -r ANALYSIS; do
  [ -z "$ANALYSIS" ] && continue
  ANALYSES_ORDER+=("$ANALYSIS")
  INSTRUCTIONS=$(get_instructions "$ANALYSIS")
  run_analysis "$ANALYSIS" "$INSTRUCTIONS"
  RESULT=$?
  if [ $RESULT -eq 130 ]; then
    ui_cancel
    exit 0
  fi
done <<< "$ANALYSES_RAW"

ui_section "Results  —  PR #${PR_NUMBER}"

ui_table_start
for ANALYSIS_NAME in "${ANALYSES_ORDER[@]}"; do
  ANALYSIS_KEY="${ANALYSIS_NAME// /_}"
  STATUS=$(cat "$RESULTS_DIR/${ANALYSIS_KEY}.status" 2>/dev/null || echo "ERROR")
  case "$STATUS" in
    OK)           ui_table_row "$ANALYSIS_NAME" "no issues"       "ok" ;;
    ISSUES_FOUND)
      COUNT=$(grep -c . "$RESULTS_DIR/${ANALYSIS_KEY}.issues" 2>/dev/null || echo 0)
      ui_table_row "$ANALYSIS_NAME" "${COUNT} issue(s) found" "warn" ;;
    *)            ui_table_row "$ANALYSIS_NAME" "analysis failed"  "error" ;;
  esac
done
ui_table_end

if [ ${#ALL_ISSUES[@]} -eq 0 ]; then
  ui_success "No issues found. PR looks good!"
  ui_press_enter
  exit 0
fi

ui_checklist_start "Issues found" "${#ALL_ISSUES[@]}"
for ISSUE in "${ALL_ISSUES[@]}"; do
  ui_checklist_item "$ISSUE"
done
ui_checklist_end

LANG_CHOICE=$(printf "PT — Portuguese\nEN — English\nES — Spanish" | fzf \
  --prompt="  Comment language  " \
  --header="Select the language for PR comments" \
  --height=20% \
  --border=rounded)

[ -z "$LANG_CHOICE" ] && ui_cancel && exit 0

case "$LANG_CHOICE" in
  "PT"*) COMMENT_LANG="Brazilian Portuguese" ;;
  "EN"*) COMMENT_LANG="English" ;;
  "ES"*) COMMENT_LANG="Spanish" ;;
  *)     COMMENT_LANG="English" ;;
esac

DEFAULT_COMMENT_TEMPLATE="You are a developer writing a code review comment on GitHub.

Write a code review comment in __COMMENT_LANG__ about this specific issue:

__ISSUE__

PR context: \"__PR_TITLE__\"

RULES:
- Language: __COMMENT_LANG__
- Sound like a human reviewer, direct and natural
- No markdown headers, no bullet points, no titles
- No formal openers such as Hi, Hello or I noticed
- No closing remarks or sign-offs
- 1 to 3 sentences maximum
- Mention the problem clearly and optionally hint at the fix
- Output ONLY the comment text, nothing else"

COMMENTS_POSTED=0
TOTAL_ISSUES=${#ALL_ISSUES[@]}
ISSUE_INDEX=0
STOP=0

for ISSUE in "${ALL_ISSUES[@]}"; do
  [ $STOP -eq 1 ] && break
  ISSUE_INDEX=$((ISSUE_INDEX + 1))

  CATEGORY=$(echo "$ISSUE" | sed 's/^\[\([^]]*\)\].*/\1/')
  TEXT=$(echo "$ISSUE" | sed 's/^\[[^]]*\] //')
  PR_CONTEXT="PR #${PR_NUMBER}  ·  ${PR_TITLE}"

  FILENAME=$(echo "$TEXT" | grep -oE '[a-zA-Z0-9_-]+\.(ts|js|tsx|jsx|py|rb|go|java|cs|php|kt|rs|cpp|c|h|vue|json)' | head -1)
  SNIPPET=""
  if [ -n "$FILENAME" ]; then
    SNIPPET=$(echo "$PR_DIFF" | awk -v fn="$FILENAME" '
      $0 ~ ("diff --git.*" fn) { found=1; count=0; next }
      /^diff --git/ && found    { exit }
      found {
        if ($0 !~ /^index |^--- |^\+\+\+ |^@@/) { print; count++ }
        if (count >= 15) exit
      }
    ')
  fi

  ui_issue_card "$ISSUE_INDEX" "$TOTAL_ISSUES" "$CATEGORY" "$TEXT" "$PR_CONTEXT"
  [ -n "$SNIPPET" ] && ui_code_snippet "$FILENAME" "$SNIPPET"

  ui_prompt_triage
  TRIAGE="$UI_ACTION"

  case "$TRIAGE" in
    quit)
      ui_cancel
      STOP=1
      break
      ;;
    ignore)
      ui_info "Ignored."
      continue
      ;;
    generate)
      ui_step "Generating comment in ${COMMENT_LANG}..."

      local_TEMPLATE="${PROMPT_COMMENT_TEMPLATE:-$DEFAULT_COMMENT_TEMPLATE}"
      COMMENT_PROMPT=$(render_template "$local_TEMPLATE" \
        "__ISSUE__"        "$ISSUE"        \
        "__PR_TITLE__"     "$PR_TITLE"     \
        "__COMMENT_LANG__" "$COMMENT_LANG")

      GENERATED_COMMENT=$(generative_ia "$COMMENT_PROMPT" 0)
      EXIT_CODE=$?

      if [ $EXIT_CODE -eq 130 ]; then
        ui_cancel
        STOP=1
        break
      fi

      if [ $EXIT_CODE -ne 0 ] || [ -z "$GENERATED_COMMENT" ]; then
        ui_error "Failed to generate comment. Skipping."
        continue
      fi

      while true; do
        ui_content_box "Generated Comment" "$GENERATED_COMMENT"
        ui_prompt_review
        REVIEW="$UI_ACTION"

        case "$REVIEW" in
          post)
            if gh pr comment "$PR_NUMBER" --body "$GENERATED_COMMENT" 2>/dev/null; then
              ui_success "Comment posted."
              COMMENTS_POSTED=$((COMMENTS_POSTED + 1))
            else
              ui_error "Failed to post comment via gh."
            fi
            break
            ;;
          edit)
            TEMP_FILE=$(mktemp /tmp/pr_comment_XXXXXX.txt)
            echo "$GENERATED_COMMENT" > "$TEMP_FILE"
            ${EDITOR:-nano} "$TEMP_FILE"
            GENERATED_COMMENT=$(cat "$TEMP_FILE")
            rm -f "$TEMP_FILE"
            ;;
          quit)
            ui_cancel
            STOP=1
            break
            ;;
          skip)
            ui_info "Skipped."
            break
            ;;
        esac
      done
      ;;
  esac
done

ui_panel "Done  ·  ${COMMENTS_POSTED} comment(s) posted on PR #${PR_NUMBER}"
ui_press_enter
