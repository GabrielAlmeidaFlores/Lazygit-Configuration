#!/bin/bash
# azure-devops.sh — Azure DevOps SCM adapter
#
# Implements the scm_* API for dev.azure.com and visualstudio.com remotes
# using the Azure DevOps REST API via curl.
#
# Authentication priority:
#   1. AZURE_DEVOPS_PAT in settings.yaml (Personal Access Token)
#   2. az account get-access-token     (if az CLI is installed and logged in)
#   3. Returns 1 with a clear error message.
#
# Required PAT scopes: Code (Read), Pull Request Threads (Read & Write).
#
# Supported remote URL formats:
#   https://dev.azure.com/{org}/{project}/_git/{repo}
#   https://{org}@dev.azure.com/{org}/{project}/_git/{repo}
#   https://{org}.visualstudio.com/{project}/_git/{repo}
#   git@ssh.dev.azure.com:v3/{org}/{project}/{repo}
#
# Internal functions (prefixed _scm_azure_) are called by gateway.sh only.

_AZ_TOKEN=""
_AZ_ORG=""
_AZ_PROJECT=""
_AZ_REPO=""
_AZ_API_BASE=""
SCM_INLINE_COMMENTS_RAW="[]"
SCM_REVIEW_COMMENTS=""

# _scm_azure_init REMOTE_URL
# Parses the remote URL, extracts org/project/repo, resolves authentication.
# Returns 1 on failure; does not call exit so the caller may handle errors.
_scm_azure_init() {
  local REMOTE_URL="$1"

  case "$REMOTE_URL" in
    https://dev.azure.com/*|https://*@dev.azure.com/*)
      local STRIPPED
      STRIPPED=$(ui_print "$REMOTE_URL" | sed 's|https://[^@]*@||; s|https://||')
      _AZ_ORG=$(ui_print "$STRIPPED" | cut -d'/' -f2)
      _AZ_PROJECT=$(ui_print "$STRIPPED" | cut -d'/' -f3)
      _AZ_REPO=$(ui_print "$STRIPPED" | cut -d'/' -f5)
      ;;
    https://*.visualstudio.com/*)
      _AZ_ORG=$(ui_print "$REMOTE_URL" | sed 's|https://\([^.]*\)\.visualstudio\.com.*|\1|')
      _AZ_PROJECT=$(ui_print "$REMOTE_URL" | sed 's|.*/\([^/]*\)/_git/.*|\1|')
      _AZ_REPO=$(ui_print "$REMOTE_URL" | sed 's|.*/_git/\([^/]*\).*|\1|')
      ;;
    git@ssh.dev.azure.com:v3/*)
      local PATH_PART
      PATH_PART=$(ui_print "$REMOTE_URL" | sed 's|git@ssh.dev.azure.com:v3/||')
      _AZ_ORG=$(ui_print "$PATH_PART" | cut -d'/' -f1)
      _AZ_PROJECT=$(ui_print "$PATH_PART" | cut -d'/' -f2)
      _AZ_REPO=$(ui_print "$PATH_PART" | cut -d'/' -f3)
      ;;
  esac

  if [ -z "$_AZ_ORG" ] || [ -z "$_AZ_PROJECT" ] || [ -z "$_AZ_REPO" ]; then
    ui_stacktrace "Azure DevOps — init failed" \
      "Could not parse remote URL: $REMOTE_URL"
    return 1
  fi

  _AZ_API_BASE="https://dev.azure.com/${_AZ_ORG}/${_AZ_PROJECT}/_apis/git/repositories/${_AZ_REPO}"

  _scm_azure_resolve_auth || return 1
}

# _scm_azure_resolve_auth
# Sets _AZ_TOKEN from AZURE_DEVOPS_PAT or az CLI.
# Returns 1 with a ui_stacktrace on failure; does not call exit.
_scm_azure_resolve_auth() {
  if [ -n "$AZURE_DEVOPS_PAT" ]; then
    _AZ_TOKEN=$(ui_print_raw ":${AZURE_DEVOPS_PAT}" | base64)
    return 0
  fi

  if command -v az >/dev/null 2>&1; then
    local BEARER AZ_ERR
    AZ_ERR=$(mktemp)
    BEARER=$(az account get-access-token \
      --resource "499b84ac-1321-427f-aa17-267ca6975798" \
      --query accessToken -o tsv 2>"$AZ_ERR")
    local AZ_EXIT=$?
    if [ $AZ_EXIT -eq 0 ] && [ -n "$BEARER" ]; then
      _AZ_TOKEN="bearer:${BEARER}"
      rm -f "$AZ_ERR"
      return 0
    fi
    ui_stacktrace "Azure DevOps — auth failed" \
      "az account get-access-token returned exit $AZ_EXIT" \
      "$(cat "$AZ_ERR" 2>/dev/null | head -3)"
    rm -f "$AZ_ERR"
  fi

  ui_stacktrace "Azure DevOps — not authenticated" \
    "Set AZURE_DEVOPS_PAT in settings.yaml or run 'az login'." \
    "Required PAT scopes: Code (Read), Pull Request Threads (Read & Write)."
  return 1
}

# _az_curl METHOD URL [BODY]
# Executes a curl request to the Azure DevOps REST API.
# Returns curl's exit code; callers must check for errors.
_az_curl() {
  local METHOD="$1" URL="$2" BODY="${3:-}"
  local AUTH_HEADER

  if ui_print "$_AZ_TOKEN" | grep -q "^bearer:"; then
    AUTH_HEADER="Authorization: Bearer ${_AZ_TOKEN#bearer:}"
  else
    AUTH_HEADER="Authorization: Basic ${_AZ_TOKEN}"
  fi

  local ARGS=("-s" "-X" "$METHOD" "$URL" "-H" "$AUTH_HEADER")
  [ -n "$BODY" ] && ARGS+=("-H" "Content-Type: application/json" "-d" "$BODY")
  curl "${ARGS[@]}"
}

# _scm_azure_pr_list
# Prints a normalized JSON array: [{number, title, author, headRefName, baseRefName, isDraft}]
_scm_azure_pr_list() {
  local RAW ERR_FILE
  ERR_FILE=$(mktemp)
  RAW=$(_az_curl GET \
    "${_AZ_API_BASE}/pullrequests?api-version=7.1&searchCriteria.status=active" \
    2>"$ERR_FILE")
  local CURL_EXIT=$?

  if [ $CURL_EXIT -ne 0 ] || [ -z "$RAW" ]; then
    ui_stacktrace "Azure DevOps — pr_list failed" \
      "curl exit: $CURL_EXIT" \
      "$(cat "$ERR_FILE" | head -3)"
    rm -f "$ERR_FILE"; return 1
  fi
  rm -f "$ERR_FILE"

  local PARSED JQ_ERR
  JQ_ERR=$(mktemp)
  PARSED=$(ui_print "$RAW" | jq -r '[.value[] | {
    number:      .pullRequestId,
    title:       .title,
    author:      .createdBy.displayName,
    headRefName: (.sourceRefName | ltrimstr("refs/heads/")),
    baseRefName: (.targetRefName | ltrimstr("refs/heads/")),
    isDraft:     (.isDraft // false)
  }]' 2>"$JQ_ERR")

  if [ $? -ne 0 ]; then
    ui_stacktrace "Azure DevOps — pr_list parse failed" \
      "$(cat "$JQ_ERR" | head -3)" \
      "Response: ${RAW:0:120}"
    rm -f "$JQ_ERR"; return 1
  fi
  rm -f "$JQ_ERR"
  ui_print "$PARSED"
}

# _scm_azure_pr_view PR_ID
# Prints a normalized JSON object. Returns 1 if PR_ID is missing or the call fails.
_scm_azure_pr_view() {
  if [ -z "$1" ]; then
    ui_stacktrace "Azure DevOps — pr_view" "PR_ID parameter is required."
    return 1
  fi

  local RAW ERR_FILE
  ERR_FILE=$(mktemp)
  RAW=$(_az_curl GET \
    "${_AZ_API_BASE}/pullrequests/$1?api-version=7.1" \
    2>"$ERR_FILE")
  local CURL_EXIT=$?

  if [ $CURL_EXIT -ne 0 ] || [ -z "$RAW" ]; then
    ui_stacktrace "Azure DevOps — pr_view #$1 failed" \
      "curl exit: $CURL_EXIT" \
      "$(cat "$ERR_FILE" | head -3)"
    rm -f "$ERR_FILE"; return 1
  fi
  rm -f "$ERR_FILE"

  local PARSED JQ_ERR
  JQ_ERR=$(mktemp)
  PARSED=$(ui_print "$RAW" | jq '{
    title:        .title,
    body:         (.description // "No description provided."),
    author:       .createdBy.displayName,
    additions:    0,
    deletions:    0,
    changedFiles: 0,
    headRefOid:   .lastMergeSourceCommit.commitId,
    targetRef:    (.targetRefName | ltrimstr("refs/heads/")),
    sourceRef:    (.sourceRefName | ltrimstr("refs/heads/"))
  }' 2>"$JQ_ERR")

  if [ $? -ne 0 ]; then
    ui_stacktrace "Azure DevOps — pr_view #$1 parse failed" \
      "$(cat "$JQ_ERR" | head -3)"
    rm -f "$JQ_ERR"; return 1
  fi
  rm -f "$JQ_ERR"
  ui_print "$PARSED"
}

# _scm_azure_pr_diff PR_ID
# Fetches updated refs and produces a local git diff, truncated to 400 lines.
# Returns 1 if PR_ID is missing, refs cannot be determined, or fetch fails.
_scm_azure_pr_diff() {
  if [ -z "$1" ]; then
    ui_stacktrace "Azure DevOps — pr_diff" "PR_ID parameter is required."
    return 1
  fi

  local PR_INFO REFS TARGET_REF SOURCE_REF
  PR_INFO=$(scm_pr_view "$1") || return 1

  REFS=$(ui_print "$PR_INFO" | jq -r '[.targetRef, .sourceRef] | join("\t")')
  TARGET_REF=$(ui_print "$REFS" | cut -f1)
  SOURCE_REF=$(ui_print "$REFS" | cut -f2)

  if [ -z "$TARGET_REF" ] || [ "$TARGET_REF" = "null" ] || \
     [ -z "$SOURCE_REF" ] || [ "$SOURCE_REF" = "null" ]; then
    ui_stacktrace "Azure DevOps — pr_diff #$1" \
      "Could not resolve branch refs from PR data." \
      "targetRef='$TARGET_REF'  sourceRef='$SOURCE_REF'"
    return 1
  fi

  local FETCH_ERR
  FETCH_ERR=$(mktemp)
  git fetch --quiet origin \
    "refs/heads/${TARGET_REF}:refs/remotes/origin/${TARGET_REF}" \
    "refs/heads/${SOURCE_REF}:refs/remotes/origin/${SOURCE_REF}" \
    2>"$FETCH_ERR"
  local FETCH_EXIT=$?

  if [ $FETCH_EXIT -ne 0 ]; then
    ui_stacktrace "Azure DevOps — pr_diff #$1: git fetch failed" \
      "exit: $FETCH_EXIT" \
      "$(cat "$FETCH_ERR" | head -3)"
    rm -f "$FETCH_ERR"; return 1
  fi
  rm -f "$FETCH_ERR"

  git diff "origin/${TARGET_REF}...origin/${SOURCE_REF}" 2>/dev/null \
    | head -n 400
}

# _scm_azure_pr_get_comments PR_ID
# Fetches existing thread comments on the PR.
# Sets SCM_INLINE_COMMENTS_RAW (empty JSON array) and SCM_REVIEW_COMMENTS (text).
# Returns 1 if PR_ID is missing or the API call fails.
_scm_azure_pr_get_comments() {
  if [ -z "$1" ]; then
    ui_stacktrace "Azure DevOps — pr_get_comments" "PR_ID parameter is required."
    return 1
  fi

  local RAW ERR_FILE
  ERR_FILE=$(mktemp)
  RAW=$(_az_curl GET "${_AZ_API_BASE}/pullrequests/$1/threads?api-version=7.1" \
    2>"$ERR_FILE")
  local CURL_EXIT=$?

  if [ $CURL_EXIT -ne 0 ] || [ -z "$RAW" ]; then
    ui_stacktrace "Azure DevOps — pr_get_comments #$1 failed" \
      "curl exit: $CURL_EXIT" \
      "$(cat "$ERR_FILE" | head -3)"
    rm -f "$ERR_FILE"
    SCM_INLINE_COMMENTS_RAW="[]"
    SCM_REVIEW_COMMENTS=""
    return 1
  fi
  rm -f "$ERR_FILE"

  SCM_INLINE_COMMENTS_RAW=$(ui_print "$RAW" | jq '[
    .value[]
    | .id as $thread_id
    | .threadContext as $thread_context
    | .comments[]
    | select(.commentType == 1)
    | {
        id: .id,
        threadId: $thread_id,
        user: {login: .author.displayName},
        path: ($thread_context.filePath // ""),
        line: ($thread_context.rightFileEnd.line // null),
        body: .content
      }
  ]' 2>/dev/null || ui_print "[]")
  SCM_REVIEW_COMMENTS=$(ui_print "$RAW" | jq -r \
    '.value[].comments[] | select(.commentType == 1) | "[\(.author.displayName)] \(.content)"' \
    2>/dev/null || ui_print "")
}

# _scm_azure_pr_resolve_comment PR_ID COMMENT_ID
# Marks the thread containing COMMENT_ID as fixed without removing the comment.
# Exit codes: 0 = fixed or already fixed, 1 = thread not found or API failure.
_scm_azure_pr_resolve_comment() {
  local PR_ID="$1" COMMENT_ID="$2" RAW THREAD_STATE THREAD_ID THREAD_STATUS RESULT

  [[ "$PR_ID" =~ ^[0-9]+$ ]] || return 1
  [[ "$COMMENT_ID" =~ ^[0-9]+$ ]] || return 1

  RAW=$(_az_curl GET "${_AZ_API_BASE}/pullrequests/$PR_ID/threads?api-version=7.1" 2>/dev/null) || return 1
  THREAD_STATE=$(ui_print "$RAW" | jq -r --argjson comment_id "$COMMENT_ID" '
    .value[]?
    | select(any(.comments[]?; .id == $comment_id))
    | "\(.id)|\(.status)"
  ' | head -n 1)

  [ -z "$THREAD_STATE" ] && return 1
  THREAD_ID="${THREAD_STATE%%|*}"
  THREAD_STATUS="${THREAD_STATE##*|}"
  [ "$THREAD_STATUS" = "2" ] && return 0

  RESULT=$(_az_curl PATCH \
    "${_AZ_API_BASE}/pullrequests/$PR_ID/threads/$THREAD_ID?api-version=7.1" \
    '{"status":2}' 2>/dev/null) || return 1
  ui_print "$RESULT" | jq -e '.status == 2' >/dev/null 2>&1
}

# _scm_azure_pr_comment PR_ID BODY
# Posts a general thread comment. Prints "general" on success, returns 1 on failure.
_scm_azure_pr_comment() {
  local PR_ID="$1" BODY="$2"
  local PAYLOAD
  PAYLOAD=$(jq -n --arg body "$BODY" \
    '{"comments":[{"parentCommentId":0,"content":$body,"commentType":1}],"status":1}')

  local RESULT ERR_FILE
  ERR_FILE=$(mktemp)
  RESULT=$(_az_curl POST \
    "${_AZ_API_BASE}/pullrequests/${PR_ID}/threads?api-version=7.1" \
    "$PAYLOAD" 2>"$ERR_FILE")
  local CURL_EXIT=$?

  if [ $CURL_EXIT -ne 0 ]; then
    ui_stacktrace "Azure DevOps — pr_comment #$PR_ID failed" \
      "curl exit: $CURL_EXIT" \
      "$(cat "$ERR_FILE" | head -3)"
    rm -f "$ERR_FILE"; return 1
  fi
  rm -f "$ERR_FILE"

  if ui_print "$RESULT" | jq -e '.id' >/dev/null 2>&1; then
    ui_print "general"
    return 0
  fi

  ui_stacktrace "Azure DevOps — pr_comment #$PR_ID" \
    "Unexpected API response (no .id field)" \
    "${RESULT:0:120}"
  return 1
}

# _scm_azure_pr_comment_inline PR_ID BODY FILE LINE COMMIT
# Posts an inline thread comment at FILE:LINE.
# Prints "inline" on success, returns 1 on failure.
_scm_azure_pr_comment_inline() {
  local PR_ID="$1" BODY="$2" FILE_PATH="$3" LINE="$4"

  [ -n "$FILE_PATH" ] && [ -n "$LINE" ] || return 1

  local PAYLOAD
  PAYLOAD=$(jq -n \
    --arg body "$BODY" \
    --arg file "/$FILE_PATH" \
    --argjson line "$LINE" \
    '{
      "comments": [{"parentCommentId": 0, "content": $body, "commentType": 1}],
      "status": 1,
      "threadContext": {
        "filePath": $file,
        "rightFileStart": {"line": $line, "offset": 1},
        "rightFileEnd":   {"line": $line, "offset": 1}
      }
    }')

  local RESULT ERR_FILE
  ERR_FILE=$(mktemp)
  RESULT=$(_az_curl POST \
    "${_AZ_API_BASE}/pullrequests/${PR_ID}/threads?api-version=7.1" \
    "$PAYLOAD" 2>"$ERR_FILE")
  local CURL_EXIT=$?
  rm -f "$ERR_FILE"

  if [ $CURL_EXIT -eq 0 ] && ui_print "$RESULT" | jq -e '.id' >/dev/null 2>&1; then
    ui_print "inline"
    return 0
  fi

  return 1
}
