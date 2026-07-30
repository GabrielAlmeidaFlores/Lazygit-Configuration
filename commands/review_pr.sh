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

# _resolve_gh_auth
# Resolves the GitHub PAT for the current repository without exporting GH_TOKEN
# globally (which would break the Copilot CLI that rejects classic PATs).
# Sets _GH_PAT for use in specific gh and gh api calls only.
# Priority:
#   1. PAT embedded in the remote origin URL (https://TOKEN@github.com/...)
#   2. git config --local github.user  →  gh auth token -u <user>
#   3. Default active gh account (no PAT override)
_GH_PAT=""
_resolve_gh_auth() {
  local REMOTE_URL PAT
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)
  PAT=$(ui_print "$REMOTE_URL" | sed -n 's|https://\([^@]*\)@github\.com.*|\1|p')
  if [ -n "$PAT" ]; then
    _GH_PAT="$PAT"
    return 0
  fi

  local LOCAL_GH_USER TOKEN
  LOCAL_GH_USER=$(git config --local github.user 2>/dev/null)
  if [ -n "$LOCAL_GH_USER" ]; then
    TOKEN=$(gh auth token -u "$LOCAL_GH_USER" 2>/dev/null)
    [ -n "$TOKEN" ] && _GH_PAT="$TOKEN"
  fi
}

# gh_run CMD [ARGS...]
# Runs a gh command with the resolved local PAT when available.
# Use this wrapper for all gh and gh api calls instead of gh directly.
gh_run() {
  if [ -n "$_GH_PAT" ]; then
    GH_TOKEN="$_GH_PAT" gh "$@"
  else
    gh "$@"
  fi
}

_resolve_gh_auth

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
  ui_print "$RESULT"
}

ui_header "AI PR Review"
ui_step "Fetching open PRs..."

PR_JSON=$(gh_run pr list --state open --json number,title,author,headRefName 2>/dev/null)

if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "[]" ]; then
  ui_error "No open PRs found in this repository."
  exit 0
fi

PR_LIST=$(ui_print "$PR_JSON" | jq -r '.[] | "#\(.number)  \(.title)  [\(.author.login) → \(.headRefName)]"')

SELECTED_PR=$(ui_print "$PR_LIST" | fzf \
  --prompt="  Select PR  " \
  --header="Open PRs — Enter to select, Ctrl+C to exit" \
  --height=50% \
  --border=rounded \
  --ansi)

[ -z "$SELECTED_PR" ] && ui_cancel && exit 0

PR_NUMBER=$(ui_print "$SELECTED_PR" | grep -oE '^#[0-9]+' | tr -d '#')
PR_TITLE=$(ui_print "$SELECTED_PR" | sed -E 's/^#[0-9]+  //' | sed 's/  \[.*//')

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
$(ui_print "$CURSOR_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_CURSOR_MODELS}"
else
  MODEL_LIST="${COPILOT_MODELS:+default
$(ui_print "$COPILOT_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_COPILOT_MODELS}"
fi

SELECTED_MODEL=$(ui_print "$MODEL_LIST" | fzf \
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

ANALYSES_RAW=$(ui_print "Architecture
Security
Code Quality
Test Coverage
Performance
Spelling & Grammar
All" | fzf \
  --multi \
  --prompt="  Analyses (Tab to select)  " \
  --header="Select one or more analysis types — Enter to confirm" \
  --height=50% \
  --border=rounded)

[ -z "$ANALYSES_RAW" ] && ui_cancel && exit 0

if ui_print "$ANALYSES_RAW" | grep -q "^All$"; then
  ANALYSES_RAW="Architecture
Security
Code Quality
Test Coverage
Performance
Spelling & Grammar"
fi

ui_panel \
  "PR #${PR_NUMBER}  ·  ${PR_TITLE}" \
  "Model: ${MODEL_LABEL}  ·  Provider: ${CURRENT_PROVIDER}"

ui_step "Fetching PR data..."

PR_INFO=$(gh_run pr view "$PR_NUMBER" --json title,body,author,additions,deletions,changedFiles,headRefOid 2>/dev/null)

if [ -z "$PR_INFO" ]; then
  ui_error "Failed to fetch PR #${PR_NUMBER} data."
  exit 1
fi

PR_BODY=$(ui_print "$PR_INFO" | jq -r '.body // "No description provided."')
PR_AUTHOR=$(ui_print "$PR_INFO" | jq -r '.author.login')
PR_ADDITIONS=$(ui_print "$PR_INFO" | jq -r '.additions')
PR_DELETIONS=$(ui_print "$PR_INFO" | jq -r '.deletions')
PR_FILES=$(ui_print "$PR_INFO" | jq -r '.changedFiles')
PR_COMMIT=$(ui_print "$PR_INFO" | jq -r '.headRefOid')
PR_DIFF=$(gh_run pr diff "$PR_NUMBER" 2>/dev/null | head -n 400)

ui_info "+${PR_ADDITIONS}  -${PR_DELETIONS}  across ${PR_FILES} file(s)"

# get_diff_location FILENAME DIFF
# Scans DIFF for the first added line belonging to a file matching FILENAME.
# Prints "file/path.ext:line_number" on success, nothing if not found.
get_diff_location() {
  local FILENAME="$1" DIFF="$2"
  ui_print "$DIFF" | awk -v fn="$FILENAME" '
    $0 ~ ("\\+\\+\\+ b/.*" fn) {
      file_path = substr($0, 7)
      in_file = 1; current_line = 0; next
    }
    /^diff --git/ && in_file { exit }
    in_file && /^@@ / {
      sub(/^@@ -[0-9,]* \+/, ""); sub(/,.*/, ""); sub(/ @@.*/, "")
      current_line = $0 + 0; next
    }
    in_file && /^\+[^+]/ && file_path != "" && current_line > 0 {
      print file_path ":" current_line; exit
    }
    in_file && /^-/ { next }
    in_file && current_line > 0 { current_line++ }
  '
}

# post_review_comment PR_NUMBER BODY FILE_PATH LINE COMMIT_SHA
# Posts an inline review comment on FILE_PATH:LINE.
# Falls back to a general PR comment if the inline post fails.
# Prints "inline" or "general" to indicate which method succeeded.
post_review_comment() {
  local PR_NUM="$1" BODY="$2" FILE_PATH="$3" LINE="$4" COMMIT="$5"

  if [ -n "$FILE_PATH" ] && [ -n "$LINE" ] && [ -n "$COMMIT" ]; then
    if gh_run api "repos/{owner}/{repo}/pulls/${PR_NUM}/comments" \
        --method POST \
        --field body="$BODY" \
        --field commit_id="$COMMIT" \
        --field path="$FILE_PATH" \
        --field line="$LINE" \
        --field side="RIGHT" \
        >/dev/null 2>&1; then
      ui_print "inline"
      return 0
    fi
  fi

  if gh_run pr comment "$PR_NUM" --body "$BODY" 2>/dev/null; then
    ui_print "general"
    return 0
  fi

  return 1
}

RESULTS_DIR=$(mktemp -d /tmp/pr_review_XXXXXX)
trap 'rm -rf "$RESULTS_DIR"' EXIT
ALL_ISSUES=()
ANALYSES_ORDER=()

# get_instructions ANALYSIS_NAME
# Returns the instruction text for a given analysis type, sourced from
# config.env variables (PROMPT_INSTRUCTIONS_*) with hardcoded fallbacks.
get_instructions() {
  case "$1" in
    "Architecture")         ui_print "${PROMPT_INSTRUCTIONS_ARCHITECTURE:-Check for architectural issues: separation of concerns, coupling, SOLID violations.}" ;;
    "Security")             ui_print "${PROMPT_INSTRUCTIONS_SECURITY:-Check for security issues: exposed secrets, injection risks, unsanitized inputs.}" ;;
    "Code Quality")         ui_print "${PROMPT_INSTRUCTIONS_CODE_QUALITY:-Check for code quality issues: duplication, complexity, poor naming, missing error handling.}" ;;
    "Test Coverage")        ui_print "${PROMPT_INSTRUCTIONS_TEST_COVERAGE:-Check for test coverage issues: missing tests for new functionality, edge cases.}" ;;
    "Performance")          ui_print "${PROMPT_INSTRUCTIONS_PERFORMANCE:-Check for performance issues: N+1 queries, inefficient loops, blocking operations.}" ;;
    "Spelling & Grammar")   ui_print "${PROMPT_INSTRUCTIONS_SPELLING:-Detect language and check for spelling mistakes, typos, missing accents in Portuguese/Spanish, grammatical errors in comments and strings.}" ;;
  esac
}

# run_analysis ANALYSIS_NAME INSTRUCTIONS
# Runs 3 sequential AI passes for the given analysis type:
#   Pass 1 — initial analysis of the diff
#   Pass 2 — second analysis informed by Pass 1 findings
#   Pass 3 — validates the deduplicated combined issues from passes 1 and 2
# Writes ANALYSIS_STATUS and issues to $RESULTS_DIR files.
# Returns 130 on cancellation, 1 on failure.
run_analysis() {
  local ANALYSIS_NAME="$1"
  local INSTRUCTIONS="$2"
  local ANALYSIS_KEY="${ANALYSIS_NAME// /_}"

  # _ai_call PROMPT
  # Calls generative_ia and sets _AI_STATUS and _AI_ISSUES from the response.
  # _AI_STATUS: "OK" | "ISSUES_FOUND" | "ERROR". Returns 130 on cancellation.
  _ai_call() {
    local PROMPT="$1"
    _AI_STATUS="" _AI_ISSUES=""
    local RESPONSE EXIT_CODE
    RESPONSE=$(generative_ia "$PROMPT" 1)
    EXIT_CODE=$?
    [ $EXIT_CODE -eq 130 ] && return 130
    [ $EXIT_CODE -ne 0 ] || [ -z "$RESPONSE" ] && _AI_STATUS="ERROR" && return 1

    _AI_STATUS=$(ui_print "$RESPONSE" | grep -i "^[[:space:]]*ANALYSIS_STATUS:" | head -1 | sed 's/.*ANALYSIS_STATUS:[[:space:]]*//')

    if [ -z "$_AI_STATUS" ]; then
      local LOWER
      LOWER=$(ui_print "$RESPONSE" | tr '[:upper:]' '[:lower:]')
      if ui_print "$LOWER" | grep -qE "no .*(issue|problem|violation|concern|finding)|looks good|nothing (found|detected|identified)|no significant|lgtm|clean code|well.written"; then
        _AI_STATUS="OK"
      else
        _AI_STATUS="ISSUES_FOUND"
        _AI_ISSUES=$(ui_print "$RESPONSE" | grep -iE "^[-*•]|^ISSUE:|^[0-9]+\." | sed 's/^[-*•[:space:]]*//' | sed 's/^ISSUE:[[:space:]]*//' | grep -v "^$")
        return 0
      fi
    fi

    if [ "$_AI_STATUS" = "ISSUES_FOUND" ]; then
      _AI_ISSUES=$(ui_print "$RESPONSE" | grep "^ISSUE:" | sed 's/^ISSUE: //')
    fi
  }

  ui_step "Analyzing  ${ANALYSIS_NAME}  —  pass 1 of 3"
  local P1_PROMPT
  P1_PROMPT=$(render_template "$PROMPT_ANALYSIS_TEMPLATE" \
    "__ANALYSIS_NAME__" "$ANALYSIS_NAME" \
    "__PR_TITLE__"      "$PR_TITLE"      \
    "__PR_AUTHOR__"     "$PR_AUTHOR"     \
    "__PR_BODY__"       "$PR_BODY"       \
    "__PR_DIFF__"       "$PR_DIFF"       \
    "__INSTRUCTIONS__"  "$INSTRUCTIONS")

  _ai_call "$P1_PROMPT"
  local P1_EC=$?
  [ $P1_EC -eq 130 ] && return 130
  [ $P1_EC -ne 0 ]   && ui_print "ERROR" > "$RESULTS_DIR/${ANALYSIS_KEY}.status" && return 1
  local P1_STATUS="$_AI_STATUS" P1_ISSUES="$_AI_ISSUES"
  local P1_RESULT="ANALYSIS_STATUS: ${P1_STATUS}"
  [ -n "$P1_ISSUES" ] && P1_RESULT="${P1_RESULT}
${P1_ISSUES}"

  ui_step "Analyzing  ${ANALYSIS_NAME}  —  pass 2 of 3"
  local P2_PROMPT
  P2_PROMPT=$(render_template "$PROMPT_ANALYSIS_PASS2_TEMPLATE" \
    "__ANALYSIS_NAME__" "$ANALYSIS_NAME" \
    "__PR_TITLE__"      "$PR_TITLE"      \
    "__PR_AUTHOR__"     "$PR_AUTHOR"     \
    "__PR_BODY__"       "$PR_BODY"       \
    "__PR_DIFF__"       "$PR_DIFF"       \
    "__INSTRUCTIONS__"  "$INSTRUCTIONS" \
    "__PASS1_RESULT__"  "$P1_RESULT")

  _ai_call "$P2_PROMPT"
  local P2_EC=$?
  [ $P2_EC -eq 130 ] && return 130
  [ $P2_EC -ne 0 ]   && ui_print "ERROR" > "$RESULTS_DIR/${ANALYSIS_KEY}.status" && return 1
  local P2_ISSUES="$_AI_ISSUES"

  local COMBINED_ISSUES
  COMBINED_ISSUES=$(ui_print "$P1_ISSUES
$P2_ISSUES" \
    | grep -v "^$" | sort -u | sed 's/^/ISSUE: /')

  ui_step "Analyzing  ${ANALYSIS_NAME}  —  pass 3 of 3"
  local P3_PROMPT
  P3_PROMPT=$(render_template "$PROMPT_ANALYSIS_PASS3_TEMPLATE" \
    "__ANALYSIS_NAME__" "$ANALYSIS_NAME" \
    "__PR_TITLE__"      "$PR_TITLE"      \
    "__PR_AUTHOR__"     "$PR_AUTHOR"     \
    "__PR_BODY__"       "$PR_BODY"       \
    "__PR_DIFF__"       "$PR_DIFF"       \
    "__INSTRUCTIONS__"  "$INSTRUCTIONS" \
    "__COMBINED_ISSUES__" "$COMBINED_ISSUES")

  _ai_call "$P3_PROMPT"
  local P3_EC=$?
  [ $P3_EC -eq 130 ] && return 130

  local FINAL_STATUS FINAL_ISSUES
  if [ $P3_EC -ne 0 ]; then
    FINAL_STATUS="$P1_STATUS"
    FINAL_ISSUES="$P1_ISSUES"
  else
    FINAL_STATUS="$_AI_STATUS"
    FINAL_ISSUES="$_AI_ISSUES"
  fi

  ui_print "$FINAL_STATUS" > "$RESULTS_DIR/${ANALYSIS_KEY}.status"

  if [ "$FINAL_STATUS" = "ISSUES_FOUND" ] && [ -n "$FINAL_ISSUES" ]; then
    ui_print "$FINAL_ISSUES" > "$RESULTS_DIR/${ANALYSIS_KEY}.issues"
  fi
}

ANALYSIS_PIDS=()
ANALYSIS_EXIT_CODES=()

TOTAL_ANALYSES=$(ui_print "$ANALYSES_RAW" | grep -v "^$" | wc -l | tr -d ' ')
ui_info "Running ${TOTAL_ANALYSES} analysis in parallel..."

ANALYSIS_INDEX=0
while IFS= read -r ANALYSIS; do
  [ -z "$ANALYSIS" ] && continue
  ANALYSES_ORDER+=("$ANALYSIS")
  INSTRUCTIONS=$(get_instructions "$ANALYSIS")
  
  (
    run_analysis "$ANALYSIS" "$INSTRUCTIONS"
    exit $?
  ) &
  
  ANALYSIS_PIDS[$ANALYSIS_INDEX]=$!
  ANALYSIS_INDEX=$((ANALYSIS_INDEX + 1))
done <<< "$ANALYSES_RAW"

for i in "${!ANALYSIS_PIDS[@]}"; do
  wait "${ANALYSIS_PIDS[$i]}"
  ANALYSIS_EXIT_CODES[$i]=$?
done

for EXIT_CODE in "${ANALYSIS_EXIT_CODES[@]}"; do
  if [ $EXIT_CODE -eq 130 ]; then
    ui_cancel
    exit 0
  fi
done

for ANALYSIS_NAME in "${ANALYSES_ORDER[@]}"; do
  ANALYSIS_KEY="${ANALYSIS_NAME// /_}"
  ISSUES_FILE="$RESULTS_DIR/${ANALYSIS_KEY}.issues"
  if [ -f "$ISSUES_FILE" ]; then
    while IFS= read -r ISSUE_LINE; do
      [ -n "$ISSUE_LINE" ] && ALL_ISSUES+=("[$ANALYSIS_NAME] $ISSUE_LINE")
    done < "$ISSUES_FILE"
  fi
done

ui_section "Results  —  PR #${PR_NUMBER}"

ui_table_start
for ANALYSIS_NAME in "${ANALYSES_ORDER[@]}"; do
  ANALYSIS_KEY="${ANALYSIS_NAME// /_}"
  STATUS=$(cat "$RESULTS_DIR/${ANALYSIS_KEY}.status" 2>/dev/null || ui_print "ERROR")
  case "$STATUS" in
    OK)           ui_table_row "$ANALYSIS_NAME" "no issues"       "ok" ;;
    ISSUES_FOUND)
      COUNT=$(grep -c . "$RESULTS_DIR/${ANALYSIS_KEY}.issues" 2>/dev/null || ui_print "0")
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

LANG_CHOICE=$(ui_print "PT — Portuguese
EN — English
ES — Spanish" | fzf \
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


COMMENTS_POSTED=0
TOTAL_ISSUES=${#ALL_ISSUES[@]}
ISSUE_INDEX=0
STOP=0

for ISSUE in "${ALL_ISSUES[@]}"; do
  [ $STOP -eq 1 ] && break
  ISSUE_INDEX=$((ISSUE_INDEX + 1))

  CATEGORY=$(ui_print "$ISSUE" | sed 's/^\[\([^]]*\)\].*/\1/')
  TEXT=$(ui_print "$ISSUE" | sed 's/^\[[^]]*\] //')
  PR_CONTEXT="PR #${PR_NUMBER}  ·  ${PR_TITLE}"

  FILENAME=$(ui_print "$TEXT" | grep -oE '[a-zA-Z0-9_-]+\.(ts|js|tsx|jsx|py|rb|go|java|cs|php|kt|rs|cpp|c|h|vue|json)' | head -1)
  SNIPPET=""
  if [ -n "$FILENAME" ]; then
    SNIPPET=$(ui_print "$PR_DIFF" | awk -v fn="$FILENAME" '
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

      COMMENT_PROMPT=$(render_template "$PROMPT_COMMENT_TEMPLATE" \
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
            LOCATION=$(get_diff_location "$FILENAME" "$PR_DIFF")
            DIFF_PATH="${LOCATION%%:*}"
            DIFF_LINE="${LOCATION##*:}"
            POST_RESULT=$(post_review_comment \
              "$PR_NUMBER" "$GENERATED_COMMENT" \
              "$DIFF_PATH" "$DIFF_LINE" "$PR_COMMIT")
            if [ $? -eq 0 ]; then
              [ "$POST_RESULT" = "inline" ] \
                && ui_success "Inline comment posted on ${DIFF_PATH}:${DIFF_LINE}" \
                || ui_success "Comment posted."
              COMMENTS_POSTED=$((COMMENTS_POSTED + 1))
            else
              ui_error "Failed to post comment via gh."
            fi
            break
            ;;
          edit)
            TEMP_FILE=$(mktemp /tmp/pr_comment_XXXXXX.txt)
            ui_print "$GENERATED_COMMENT" > "$TEMP_FILE"
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
