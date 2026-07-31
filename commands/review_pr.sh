#!/bin/bash
# review_pr.sh — Interactive AI-powered PR review for Lazygit
#
# Lists open PRs, runs focused AI analyses, and posts natural code review
# comments on the pull request. All AI prompts are configured in config.env.
# Supports GitHub and Azure DevOps — provider is detected automatically from
# the git remote URL.
#
# Dependencies: fzf, jq, curl  (gh for GitHub; az or AZURE_DEVOPS_PAT for Azure)
# Config:       commands/config.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PATH="/Users/gabrielfloresousion/homebrew/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"
source "$SCRIPT_DIR/gateways/adapters/scm/gateway.sh"

clear

for dep in fzf jq curl; do
  if ! command -v "$dep" &>/dev/null; then
    ui_error "'$dep' not found. Please install it before continuing."
    exit 1
  fi
done

scm_detect

# render_template TEMPLATE KEY1 VAL1 [KEY2 VAL2 ...]
# Replaces all __KEY__ placeholders in TEMPLATE with their corresponding values.
render_template() {
  local RESULT="$1"; shift
  while [ $# -ge 2 ]; do
    RESULT="${RESULT//$1/$2}"; shift 2
  done
  ui_print "$RESULT"
}

ui_header "🔍  AI PR Review"
ui_spinner_start "Fetching open PRs..."
PR_JSON=$(scm_pr_list 2>/dev/null)
ui_spinner_stop

if [ -z "$PR_JSON" ] || [ "$PR_JSON" = "[]" ]; then
  ui_error "No open PRs found in this repository."
  exit 0
fi

PR_LIST=$(ui_print "$PR_JSON" | jq -r '.[] |
  "#\(.number)  \(.title)\(if .isDraft then "  [DRAFT]" else "" end)  [\(.author) · \(.baseRefName) ← \(.headRefName)]"')

SELECTED_PR=$(ui_print "$PR_LIST" | fzf \
  --prompt="  Select PR  " \
  --header="Open PRs — Enter to select, Ctrl+C to exit" \
  --height=50% \
  --border=rounded \
  --margin=0,1,0,1 \
  --ansi)

[ -z "$SELECTED_PR" ] && ui_cancel && exit 0

PR_NUMBER=$(ui_print "$SELECTED_PR" | grep -oE '^#[0-9]+' | tr -d '#')
PR_TITLE=$(ui_print "$SELECTED_PR" | sed -E 's/^#[0-9]+  //' | sed 's/  \[.*//')

CURRENT_PROVIDER="${AI_PROVIDER:-copilot}"

DEFAULT_CURSOR_MODELS="default
gpt-4o-mini  (low — fast and economical)
gpt-4o  (medium — balanced)
gpt-4.1  (medium — balanced)
claude-4-5-sonnet  (medium — strong reasoning)
gemini-2.5-pro  (medium — multimodal)
claude-4-5  (medium-high — latest sonnet)
claude-4-opus  (high — premium quality)
o3  (high — deep reasoning)"

DEFAULT_COPILOT_MODELS="default
gemini-3.1-pro-preview  (medium — fast and capable)
claude-sonnet-4.5  (medium — balanced quality)
claude-sonnet-4.6  (medium-high — latest sonnet)
gpt-5.3-codex  (high — advanced coding)
claude-opus-4.6  (high — premium quality)"

if [ "$CURRENT_PROVIDER" = "cursor" ]; then
  MODEL_LIST="${CURSOR_MODELS:+default
$(ui_print "$CURSOR_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_CURSOR_MODELS}"
else
  MODEL_LIST="${COPILOT_MODELS:+default
$(ui_print "$COPILOT_MODELS" | tr ',' '\n' | sed 's/^ *//')}"
  MODEL_LIST="${MODEL_LIST:-$DEFAULT_COPILOT_MODELS}"
fi

SELECTED_ANALYSIS_MODEL=$(ui_print "$MODEL_LIST" | fzf \
  --prompt="  Analysis model ($CURRENT_PROVIDER)  " \
  --header="Model used to analyze the code — runs the 3-pass review for each analysis type" \
  --height=50% \
  --border=rounded \
  --margin=0,1,0,1)

[ -z "$SELECTED_ANALYSIS_MODEL" ] && ui_cancel && exit 0

SELECTED_ANALYSIS_MODEL=$(ui_print "$SELECTED_ANALYSIS_MODEL" | sed 's/[[:space:]]*(.*)//')

if [ "$SELECTED_ANALYSIS_MODEL" != "default" ]; then
  export MODEL="$SELECTED_ANALYSIS_MODEL"
  ANALYSIS_MODEL_LABEL="$SELECTED_ANALYSIS_MODEL"
else
  ANALYSIS_MODEL_LABEL="${MODEL:-default}"
fi

ANALYSES_RAW=$(ui_print "Architecture  (separation of concerns, SOLID, coupling)
Security  (secrets, injection risks, auth bypasses)
Code Quality  (duplication, naming, complexity, error handling)
Test Coverage  (missing tests, edge cases, untested logic)
Performance  (N+1 queries, inefficient loops, blocking ops)
Bugs  (null dereferences, race conditions, logic errors)
Spelling & Grammar  (typos, accents, grammar in strings)
Fix Validation  (validates fixes from existing PR comments)
All  (runs all analyses above)" | fzf \
  --multi \
  --prompt="  Analyses (Tab to select)  " \
  --header="Select one or more analysis types — Enter to confirm" \
  --height=50% \
  --border=rounded \
  --margin=0,1,0,1)

[ -z "$ANALYSES_RAW" ] && ui_cancel && exit 0

ANALYSES_RAW=$(ui_print "$ANALYSES_RAW" | sed 's/[[:space:]]*([^)]*)//')

if ui_print "$ANALYSES_RAW" | grep -q "^All$"; then
  ANALYSES_RAW="Architecture
Security
Code Quality
Test Coverage
Performance
Bugs
Spelling & Grammar
Fix Validation"
fi

ui_panel \
  "PR #${PR_NUMBER}  ·  ${PR_TITLE}" \
  "Analysis model: ${ANALYSIS_MODEL_LABEL}  ·  Provider: ${CURRENT_PROVIDER}"

ui_spinner_start "Fetching PR data..."
PR_INFO=$(scm_pr_view "$PR_NUMBER" 2>/dev/null)

if [ -z "$PR_INFO" ]; then
  ui_error "Failed to fetch PR #${PR_NUMBER} data."
  exit 1
fi

PR_BODY=$(ui_print "$PR_INFO" | jq -r '.body // "No description provided."')
PR_AUTHOR=$(ui_print "$PR_INFO" | jq -r '.author')
PR_ADDITIONS=$(ui_print "$PR_INFO" | jq -r '.additions')
PR_DELETIONS=$(ui_print "$PR_INFO" | jq -r '.deletions')
PR_FILES=$(ui_print "$PR_INFO" | jq -r '.changedFiles')
PR_COMMIT=$(ui_print "$PR_INFO" | jq -r '.headRefOid')
PR_DIFF=$(scm_pr_diff "$PR_NUMBER" 2>/dev/null)
ui_spinner_stop

ui_spinner_start "Fetching existing PR comments..."
scm_pr_get_comments "$PR_NUMBER"
ui_spinner_stop
PR_COMMENTS_RAW="${SCM_INLINE_COMMENTS_RAW:-[]}"
PR_COMMENTS=$(ui_print "$PR_COMMENTS_RAW" | jq -r '.[] | "[\(.user.login // .author)] \(.path // ""):\(.line // "") - \(.body // .content)"' 2>/dev/null || ui_print "")
PR_REVIEW_COMMENTS="${SCM_REVIEW_COMMENTS:-}"

PR_COMMENTS_WITH_IDS=$(ui_print "$PR_COMMENTS_RAW" | jq -r '.[] | "\(.id)|[\(.user.login // .author)] \(.path // ""):\(.line // "") - \(.body // .content)"' 2>/dev/null || ui_print "")

EXISTING_COMMENTS=""
if [ -n "$PR_COMMENTS" ] || [ -n "$PR_REVIEW_COMMENTS" ]; then
  EXISTING_COMMENTS="EXISTING COMMENTS ON THIS PR:

Inline Comments:
${PR_COMMENTS:-None}

General Comments:
${PR_REVIEW_COMMENTS:-None}

DO NOT report issues that have already been mentioned in the comments above."
fi

INLINE_COUNT=$(ui_print "$PR_COMMENTS_RAW" | jq 'length' 2>/dev/null || ui_print "0")
COMMENT_STATUS="${INLINE_COUNT} existing comment(s)"

ui_panel \
  "📊  +${PR_ADDITIONS}  📊  -${PR_DELETIONS}  ·  ${PR_FILES} file(s) changed" \
  "💬  ${COMMENT_STATUS}"

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

# _diff_line_valid FILE_PATH LINE DIFF
# Returns 0 if LINE is within a diff hunk for FILE_PATH in DIFF, 1 otherwise.
_diff_line_valid() {
  local FILE_PATH="$1" TARGET="$2" DIFF="$3"
  ui_print "$DIFF" | awk -v fn="$FILE_PATH" -v target="$TARGET" '
    $0 ~ ("\\+\\+\\+ b/.*" fn) { in_file=1; cur=0; next }
    /^diff --git/ && in_file { exit }
    in_file && /^@@ / {
      sub(/^@@ -[0-9,]* \+/, ""); sub(/,.*/, ""); sub(/ @@.*/, "")
      cur = $0 + 0; next
    }
    in_file && (/^\+[^+]/ || /^ /) && cur > 0 {
      if (cur == target) { found=1; exit }
      cur++
    }
    in_file && /^-/ { next }
    END { exit (found ? 0 : 1) }
  '
}

# _find_nearest_diff_line FILE_PATH TARGET_LINE DIFF
# Returns the line number in DIFF that is closest to TARGET_LINE for FILE_PATH.
# Falls back to the first added line in the file.
_find_nearest_diff_line() {
  local FILE_PATH="$1" TARGET="$2" DIFF="$3"
  ui_print "$DIFF" | awk -v fn="$FILE_PATH" -v target="$TARGET" '
    $0 ~ ("\\+\\+\\+ b/.*" fn) { fp=substr($0,7); in_file=1; cur=0; next }
    /^diff --git/ && in_file { exit }
    in_file && /^@@ / {
      sub(/^@@ -[0-9,]* \+/, ""); sub(/,.*/, ""); sub(/ @@.*/, "")
      cur = $0 + 0; next
    }
    in_file && /^\+[^+]/ && cur > 0 {
      d = cur - target; if (d < 0) d = -d
      if (best_dist == "" || d < best_dist) { best_dist=d; best=cur; best_fp=fp }
      cur++
    }
    in_file && /^-/ { next }
    in_file && cur > 0 { cur++ }
    END { if (best > 0) print best_fp ":" best }
  '
}

# _find_diff_line_by_keyword FILE_PATH KEYWORD DIFF
# Searches added lines in FILE_PATH for KEYWORD and returns the first match as path:line.
_find_diff_line_by_keyword() {
  local FILE_PATH="$1" KEYWORD="$2" DIFF="$3"
  [ -z "$KEYWORD" ] && return 1
  ui_print "$DIFF" | awk -v fn="$FILE_PATH" -v kw="$KEYWORD" '
    $0 ~ ("\\+\\+\\+ b/.*" fn) { fp=substr($0,7); in_file=1; cur=0; next }
    /^diff --git/ && in_file { exit }
    in_file && /^@@ / {
      sub(/^@@ -[0-9,]* \+/, ""); sub(/,.*/, ""); sub(/ @@.*/, "")
      cur = $0 + 0; next
    }
    in_file && /^\+[^+]/ && cur > 0 {
      if (index($0, kw) > 0) { print fp ":" cur; exit }
      cur++
    }
    in_file && /^-/ { next }
    in_file && cur > 0 { cur++ }
  '
}

# post_review_comment PR_NUMBER BODY FILE_PATH LINE COMMIT_SHA
# Delegates to scm_pr_comment_inline, which attempts an inline comment and
# falls back to a general comment automatically. Prints "inline" or "general".
post_review_comment() {
  scm_pr_comment_inline "$1" "$2" "$3" "$4" "$5"
}

# _build_comment_prompt ISSUE SNIPPET FILENAME PR_TITLE COMMENT_LANG
# Renders the comment generation prompt with all context placeholders.
_build_comment_prompt() {
  render_template "$PROMPT_COMMENT_TEMPLATE" \
    "__ISSUE__"        "$1" \
    "__SNIPPET__"      "$2" \
    "__FILENAME__"     "$3" \
    "__PR_TITLE__"     "$4" \
    "__COMMENT_LANG__" "$5"
}

# _parse_comment_response RESPONSE
# Extracts the LOCATION and comment text from the AI response.
# Sets _COMMENT_TEXT (clean comment) and _COMMENT_LOCATION ("file:line" or "unknown").
_parse_comment_response() {
  local RESPONSE="$1"
  _COMMENT_LOCATION=$(ui_print "$RESPONSE" | grep -i "^LOCATION:" | head -1 | sed 's/^LOCATION:[[:space:]]*//')
  _COMMENT_TEXT=$(ui_print "$RESPONSE" | grep -iv "^LOCATION:" | sed -n '/[^[:space:]]/,$p')
  [ -z "$_COMMENT_LOCATION" ] && _COMMENT_LOCATION="unknown"
  [ -z "$_COMMENT_TEXT" ]     && _COMMENT_TEXT="$RESPONSE"
}

# _resolve_comment_location AI_LOCATION FILENAME ISSUE_TEXT DIFF
# Determines the best file:line for the inline comment.
# Priority:
#   1. AI-provided location — verified to be within a diff hunk
#   2. Keyword search in the diff using terms from the issue text
#   3. Nearest diff hunk line to the AI-suggested line number
#   4. First added line in the file (get_diff_location)
# Sets _DIFF_PATH and _DIFF_LINE.
_resolve_comment_location() {
  local AI_LOC="$1" FILENAME="$2" ISSUE_TEXT="$3" DIFF="$4"
  _DIFF_PATH="" _DIFF_LINE=""

  if [ -n "$AI_LOC" ] && [ "$AI_LOC" != "unknown" ]; then
    local AI_PATH AI_LINE
    AI_PATH="${AI_LOC%%:*}"
    AI_LINE="${AI_LOC##*:}"
    if [[ "$AI_LINE" =~ ^[0-9]+$ ]]; then
      local VERIFY_PATH="${AI_PATH:-$FILENAME}"
      if _diff_line_valid "$VERIFY_PATH" "$AI_LINE" "$DIFF"; then
        _DIFF_PATH="$VERIFY_PATH"
        _DIFF_LINE="$AI_LINE"
        return 0
      fi
      local NEAREST
      NEAREST=$(_find_nearest_diff_line "$VERIFY_PATH" "$AI_LINE" "$DIFF")
      if [ -n "$NEAREST" ]; then
        _DIFF_PATH="${NEAREST%%:*}"
        _DIFF_LINE="${NEAREST##*:}"
        return 0
      fi
    fi
  fi

  if [ -n "$FILENAME" ] && [ -n "$ISSUE_TEXT" ]; then
    local KEYWORD KEYWORD_MATCH
    KEYWORD=$(ui_print "$ISSUE_TEXT" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]{3,}\(' | head -1 | tr -d '(')
    [ -z "$KEYWORD" ] && KEYWORD=$(ui_print "$ISSUE_TEXT" | grep -oE '[a-zA-Z_][a-zA-Z0-9_]{4,}' | grep -v "^\(the\|and\|for\|not\|with\|this\|that\|from\|into\|have\|been\)$" | head -1)
    if [ -n "$KEYWORD" ]; then
      KEYWORD_MATCH=$(_find_diff_line_by_keyword "$FILENAME" "$KEYWORD" "$DIFF")
      if [ -n "$KEYWORD_MATCH" ]; then
        _DIFF_PATH="${KEYWORD_MATCH%%:*}"
        _DIFF_LINE="${KEYWORD_MATCH##*:}"
        return 0
      fi
    fi
  fi

  local FALLBACK
  FALLBACK=$(get_diff_location "$FILENAME" "$DIFF")
  _DIFF_PATH="${FALLBACK%%:*}"
  _DIFF_LINE="${FALLBACK##*:}"
}

RESULTS_DIR=$(mktemp -d /tmp/pr_review_XXXXXX)
trap 'rm -rf "$RESULTS_DIR"' EXIT
ALL_ISSUES=()
ANALYSES_ORDER=()

# _get_analysis_icon ANALYSIS_NAME
# Returns a Nerd Fonts icon for the given analysis type.
_get_analysis_icon() {
  case "$1" in
    "Architecture")       ui_print_raw '🏗️' ;;
    "Security")           ui_print_raw '🔒' ;;
    "Code Quality")       ui_print_raw '💎' ;;
    "Test Coverage")      ui_print_raw '🧪' ;;
    "Performance")        ui_print_raw '🚀' ;;
    "Bugs")               ui_print_raw '🐛' ;;
    "Fix Validation")     ui_print_raw '🔧' ;;
    "Spelling & Grammar") ui_print_raw '📝' ;;
    *)                    ui_print_raw '→' ;;
  esac
}

# get_instructions ANALYSIS_NAME
# Returns the instruction text for a given analysis type, sourced from
# config.env variables (PROMPT_INSTRUCTIONS_*) with hardcoded fallbacks.
get_instructions() {
  case "$1" in
    "Architecture")       ui_print "${PROMPT_INSTRUCTIONS_ARCHITECTURE:-Check for architectural issues: separation of concerns, coupling, SOLID violations.}" ;;
    "Security")           ui_print "${PROMPT_INSTRUCTIONS_SECURITY:-Check for security issues: exposed secrets, injection risks, unsanitized inputs.}" ;;
    "Code Quality")       ui_print "${PROMPT_INSTRUCTIONS_CODE_QUALITY:-Check for code quality issues: duplication, complexity, poor naming, missing error handling.}" ;;
    "Test Coverage")      ui_print "${PROMPT_INSTRUCTIONS_TEST_COVERAGE:-Check for test coverage issues: missing tests for new functionality, edge cases.}" ;;
    "Performance")        ui_print "${PROMPT_INSTRUCTIONS_PERFORMANCE:-Check for performance issues: N+1 queries, inefficient loops, blocking operations.}" ;;
    "Bugs")               ui_print "${PROMPT_INSTRUCTIONS_BUGS:-Check for potential bugs: null dereferences, off-by-one errors, race conditions, incorrect logic, resource leaks.}" ;;
    "Fix Validation")     ui_print "${PROMPT_INSTRUCTIONS_FIX_VALIDATION:-Review existing PR comments requesting fixes and validate if they have been addressed in the current diff.}" ;;
    "Spelling & Grammar") ui_print "${PROMPT_INSTRUCTIONS_SPELLING:-Detect language and check for spelling mistakes, typos, missing accents in Portuguese/Spanish, grammatical errors in comments and strings.}" ;;
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

  ICON=$(_get_analysis_icon "$ANALYSIS_NAME")
  ui_spinner_start "🔍  ${ICON}  ${ANALYSIS_NAME}  ·  pass 1 of 3"
  local P1_PROMPT
  P1_PROMPT=$(render_template "$PROMPT_ANALYSIS_TEMPLATE" \
    "__ANALYSIS_NAME__"      "$ANALYSIS_NAME" \
    "__PR_TITLE__"           "$PR_TITLE"      \
    "__PR_AUTHOR__"          "$PR_AUTHOR"     \
    "__PR_BODY__"            "$PR_BODY"       \
    "__PR_DIFF__"            "$PR_DIFF"       \
    "__EXISTING_COMMENTS__"  "$EXISTING_COMMENTS" \
    "__INSTRUCTIONS__"       "$INSTRUCTIONS")

  _ai_call "$P1_PROMPT"
  ui_spinner_stop
  local P1_EC=$?
  [ $P1_EC -eq 130 ] && return 130
  [ $P1_EC -ne 0 ]   && ui_print "ERROR" > "$RESULTS_DIR/${ANALYSIS_KEY}.status" && return 1
  local P1_STATUS="$_AI_STATUS" P1_ISSUES="$_AI_ISSUES"
  local P1_RESULT="ANALYSIS_STATUS: ${P1_STATUS}"
  [ -n "$P1_ISSUES" ] && P1_RESULT="${P1_RESULT}
${P1_ISSUES}"

  ICON=$(_get_analysis_icon "$ANALYSIS_NAME")
  ui_spinner_start "👁  ${ICON}  ${ANALYSIS_NAME}  ·  pass 2 of 3"
  local P2_PROMPT
  P2_PROMPT=$(render_template "$PROMPT_ANALYSIS_PASS2_TEMPLATE" \
    "__ANALYSIS_NAME__"      "$ANALYSIS_NAME" \
    "__PR_TITLE__"           "$PR_TITLE"      \
    "__PR_AUTHOR__"          "$PR_AUTHOR"     \
    "__PR_BODY__"            "$PR_BODY"       \
    "__PR_DIFF__"            "$PR_DIFF"       \
    "__EXISTING_COMMENTS__"  "$EXISTING_COMMENTS" \
    "__INSTRUCTIONS__"       "$INSTRUCTIONS" \
    "__PASS1_RESULT__"       "$P1_RESULT")

  _ai_call "$P2_PROMPT"
  ui_spinner_stop
  local P2_EC=$?
  [ $P2_EC -eq 130 ] && return 130
  [ $P2_EC -ne 0 ]   && ui_print "ERROR" > "$RESULTS_DIR/${ANALYSIS_KEY}.status" && return 1
  local P2_ISSUES="$_AI_ISSUES"

  local COMBINED_ISSUES
  COMBINED_ISSUES=$(ui_print "$P1_ISSUES
$P2_ISSUES" \
    | grep -v "^$" | sort -u | sed 's/^/ISSUE: /')

  ICON=$(_get_analysis_icon "$ANALYSIS_NAME")
  ui_spinner_start "🛡️  ${ICON}  ${ANALYSIS_NAME}  ·  pass 3 of 3"
  local P3_PROMPT
  P3_PROMPT=$(render_template "$PROMPT_ANALYSIS_PASS3_TEMPLATE" \
    "__ANALYSIS_NAME__"      "$ANALYSIS_NAME" \
    "__PR_TITLE__"           "$PR_TITLE"      \
    "__PR_AUTHOR__"          "$PR_AUTHOR"     \
    "__PR_BODY__"            "$PR_BODY"       \
    "__PR_DIFF__"            "$PR_DIFF"       \
    "__EXISTING_COMMENTS__"  "$EXISTING_COMMENTS" \
    "__INSTRUCTIONS__"       "$INSTRUCTIONS" \
    "__COMBINED_ISSUES__"    "$COMBINED_ISSUES")

  _ai_call "$P3_PROMPT"
  ui_spinner_stop
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

  if [ "$ANALYSIS_NAME" = "Fix Validation" ] && [ "$FINAL_STATUS" = "OK" ]; then
    ui_print "$FINAL_ISSUES" > "$RESULTS_DIR/${ANALYSIS_KEY}.resolved_comments"
  fi
}

ANALYSIS_PIDS=()
ANALYSIS_EXIT_CODES=()

TOTAL_ANALYSES=$(ui_print "$ANALYSES_RAW" | grep -v "^$" | wc -l | tr -d ' ')
ui_panel "🛠  Running ${TOTAL_ANALYSES} analyses in parallel  🕐"

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
  ICON=$(_get_analysis_icon "$ANALYSIS_NAME")
  LABEL="${ICON}  ${ANALYSIS_NAME}"
  STATUS=$(cat "$RESULTS_DIR/${ANALYSIS_KEY}.status" 2>/dev/null || ui_print "ERROR")
  case "$STATUS" in
    OK)
      if [ "$ANALYSIS_NAME" = "Fix Validation" ] && [ -f "$RESULTS_DIR/${ANALYSIS_KEY}.resolved_comments" ]; then
        RESOLVED_COUNT=$(grep -c "FIXED" "$RESULTS_DIR/${ANALYSIS_KEY}.resolved_comments" 2>/dev/null || ui_print_raw '0')
        RESOLVED_COUNT=$(ui_print_raw "$RESOLVED_COUNT" | tr -d '\n\r ')
        if [ -n "$RESOLVED_COUNT" ] && [ "$RESOLVED_COUNT" -gt 0 ] 2>/dev/null; then
          ui_table_row "$LABEL" "${RESOLVED_COUNT} fix(es) validated" "ok"
        else
          ui_table_row "$LABEL" "no fixes to validate" "ok"
        fi
      else
        ui_table_row "$LABEL" "no issues" "ok"
      fi
      ;;
    ISSUES_FOUND)
      COUNT=$(grep -c . "$RESULTS_DIR/${ANALYSIS_KEY}.issues" 2>/dev/null || ui_print_raw '0')
      COUNT=$(ui_print_raw "$COUNT" | tr -d '\n\r ')
      ui_table_row "$LABEL" "${COUNT} issue(s) found" "warn" ;;
    *)  ui_table_row "$LABEL" "analysis failed" "error" ;;
  esac
done
ui_table_end

if [ -f "$RESULTS_DIR/Fix_Validation.resolved_comments" ]; then
  RESOLVED_COMMENTS=$(cat "$RESULTS_DIR/Fix_Validation.resolved_comments" 2>/dev/null)

  if [ -n "$RESOLVED_COMMENTS" ] && ui_print "$RESOLVED_COMMENTS" | grep -q "FIXED"; then
    ui_step "Resolving fixed comments..."
    RESOLVED_COUNT=0

    while IFS= read -r ISSUE_LINE; do
      if ui_print "$ISSUE_LINE" | grep -q "FIXED"; then
        COMMENT_TEXT=$(ui_print "$ISSUE_LINE" | sed 's/.*FIXED - //' | sed 's/ Evidence:.*//')

        if [ -n "$COMMENT_TEXT" ] && [ -n "$PR_COMMENTS_WITH_IDS" ]; then
          while IFS='|' read -r COMMENT_ID COMMENT_FULL; do
            if [ -n "$COMMENT_ID" ] && ui_print "$COMMENT_FULL" | grep -qF "$COMMENT_TEXT"; then
              if scm_pr_comment_reply "$COMMENT_ID" "Fixed and validated by AI analysis" 2>/dev/null; then
                RESOLVED_COUNT=$((RESOLVED_COUNT + 1))
              fi
              break
            fi
          done <<< "$PR_COMMENTS_WITH_IDS"
        fi
      fi
    done <<< "$RESOLVED_COMMENTS"

    if [ $RESOLVED_COUNT -gt 0 ]; then
      ui_success "Marked ${RESOLVED_COUNT} comment(s) as resolved"
    fi
  fi
fi

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

SELECTED_COMMENT_MODEL=$(ui_print "$MODEL_LIST" | fzf \
  --prompt="  Comment generation model ($CURRENT_PROVIDER)  " \
  --header="Model used to write PR comments for each issue found — can differ from the analysis model" \
  --height=50% \
  --border=rounded \
  --margin=0,1,0,1)

[ -z "$SELECTED_COMMENT_MODEL" ] && ui_cancel && exit 0

SELECTED_COMMENT_MODEL=$(ui_print "$SELECTED_COMMENT_MODEL" | sed 's/[[:space:]]*(.*)//')

COMMENT_MODEL="$SELECTED_COMMENT_MODEL"
if [ "$COMMENT_MODEL" = "default" ]; then
  COMMENT_MODEL="${MODEL:-}"
fi

LANG_CHOICE=$(ui_print "PT — Portuguese
EN — English
ES — Spanish" | fzf \
  --prompt="  Comment language  " \
  --header="Select the language for PR comments" \
  --height=20% \
  --border=rounded \
  --margin=0,1,0,1)

[ -z "$LANG_CHOICE" ] && ui_cancel && exit 0

case "$LANG_CHOICE" in
  "PT"*) COMMENT_LANG="Brazilian Portuguese" ;;
  "EN"*) COMMENT_LANG="English" ;;
  "ES"*) COMMENT_LANG="Spanish" ;;
  *)     COMMENT_LANG="English" ;;
esac

COMMENTS_POSTED=0
AUTO_POST_PIDS=()
AUTO_POST_COUNT=0
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
    auto_post)
      COMMENT_PROMPT=$(_build_comment_prompt \
        "$ISSUE" "$SNIPPET" "$FILENAME" "$PR_TITLE" "$COMMENT_LANG")

      ui_step "Generating and posting in background..."

      (
        [ -n "$COMMENT_MODEL" ] && export MODEL="$COMMENT_MODEL"
        GENERATED=$(generative_ia "$COMMENT_PROMPT" 0)
        if [ $? -eq 0 ] && [ -n "$GENERATED" ]; then
          _parse_comment_response "$GENERATED"
          _resolve_comment_location "$_COMMENT_LOCATION" "$FILENAME" "$TEXT" "$PR_DIFF"
          post_review_comment "$PR_NUMBER" "$_COMMENT_TEXT" \
            "$_DIFF_PATH" "$_DIFF_LINE" "$PR_COMMIT" >/dev/null 2>&1
        fi
      ) &
      AUTO_POST_PIDS+=($!)
      AUTO_POST_COUNT=$((AUTO_POST_COUNT + 1))
      continue
      ;;
    generate)
      [ -n "$COMMENT_MODEL" ] && export MODEL="$COMMENT_MODEL"
      ui_spinner_start "Generating comment in ${COMMENT_LANG}..."

      COMMENT_PROMPT=$(_build_comment_prompt \
        "$ISSUE" "$SNIPPET" "$FILENAME" "$PR_TITLE" "$COMMENT_LANG")

      RAW_COMMENT=$(generative_ia "$COMMENT_PROMPT" 0)
      EXIT_CODE=$?

      if [ $EXIT_CODE -eq 130 ]; then
        ui_cancel
        STOP=1
        break
      fi

      if [ $EXIT_CODE -ne 0 ] || [ -z "$RAW_COMMENT" ]; then
        ui_error "Failed to generate comment. Skipping."
        continue
      fi

      _parse_comment_response "$RAW_COMMENT"
      GENERATED_COMMENT="$_COMMENT_TEXT"

      while true; do
        ui_content_box "Generated Comment" "$GENERATED_COMMENT"
        ui_prompt_review
        REVIEW="$UI_ACTION"

        case "$REVIEW" in
          post)
            _resolve_comment_location "$_COMMENT_LOCATION" "$FILENAME" "$TEXT" "$PR_DIFF"
            POST_RESULT=$(post_review_comment \
              "$PR_NUMBER" "$GENERATED_COMMENT" \
              "$_DIFF_PATH" "$_DIFF_LINE" "$PR_COMMIT")
            if [ $? -eq 0 ]; then
              [ "$POST_RESULT" = "inline" ] \
                && ui_success "Inline comment posted on ${_DIFF_PATH}:${_DIFF_LINE}" \
                || ui_success "Comment posted."
              COMMENTS_POSTED=$((COMMENTS_POSTED + 1))
            else
              ui_error "Failed to post comment."
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

if [ ${#AUTO_POST_PIDS[@]} -gt 0 ]; then
  ui_spinner_start "Waiting for ${AUTO_POST_COUNT} background comment(s)..."
  for pid in "${AUTO_POST_PIDS[@]}"; do
    wait "$pid" 2>/dev/null
  done
  ui_spinner_stop
  ui_success "Background posting complete."
fi

TOTAL_POSTED=$((COMMENTS_POSTED + AUTO_POST_COUNT))
ui_panel \
  "Done  ·  PR #${PR_NUMBER}" \
  "${COMMENTS_POSTED} manual + ${AUTO_POST_COUNT} auto-posted = ${TOTAL_POSTED} comment(s)"
ui_press_enter
