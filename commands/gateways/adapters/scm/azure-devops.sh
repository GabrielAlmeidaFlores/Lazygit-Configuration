#!/bin/bash
# azure-devops.sh — Azure DevOps SCM adapter
#
# Implements the scm_* API for dev.azure.com and visualstudio.com remotes
# using the Azure DevOps REST API via curl.
#
# Authentication priority:
#   1. AZURE_DEVOPS_PAT in config.env  (Personal Access Token)
#   2. az account get-access-token     (if az CLI is installed and logged in)
#   3. Exits with a clear error message.
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

# _scm_azure_init REMOTE_URL
# Parses the remote URL, extracts org/project/repo, resolves authentication.
_scm_azure_init() {
  local REMOTE_URL="$1"

  case "$REMOTE_URL" in
    https://dev.azure.com/*|https://*@dev.azure.com/*)
      local STRIPPED
      STRIPPED=$(echo "$REMOTE_URL" | sed 's|https://[^@]*@||; s|https://||')
      _AZ_ORG=$(echo "$STRIPPED" | cut -d'/' -f2)
      _AZ_PROJECT=$(echo "$STRIPPED" | cut -d'/' -f3)
      _AZ_REPO=$(echo "$STRIPPED" | cut -d'/' -f5)
      ;;
    https://*.visualstudio.com/*)
      _AZ_ORG=$(echo "$REMOTE_URL" | sed 's|https://\([^.]*\)\.visualstudio\.com.*|\1|')
      _AZ_PROJECT=$(echo "$REMOTE_URL" | sed 's|.*/\([^/]*\)/_git/.*|\1|')
      _AZ_REPO=$(echo "$REMOTE_URL" | sed 's|.*/_git/\([^/]*\).*|\1|')
      ;;
    git@ssh.dev.azure.com:v3/*)
      local PATH_PART
      PATH_PART=$(echo "$REMOTE_URL" | sed 's|git@ssh.dev.azure.com:v3/||')
      _AZ_ORG=$(echo "$PATH_PART" | cut -d'/' -f1)
      _AZ_PROJECT=$(echo "$PATH_PART" | cut -d'/' -f2)
      _AZ_REPO=$(echo "$PATH_PART" | cut -d'/' -f3)
      ;;
  esac

  if [ -z "$_AZ_ORG" ] || [ -z "$_AZ_PROJECT" ] || [ -z "$_AZ_REPO" ]; then
    ui_error "Could not parse Azure DevOps remote URL: $REMOTE_URL"
    exit 1
  fi

  _AZ_API_BASE="https://dev.azure.com/${_AZ_ORG}/${_AZ_PROJECT}/_apis/git/repositories/${_AZ_REPO}"

  _scm_azure_resolve_auth
}

# _scm_azure_resolve_auth
# Sets _AZ_TOKEN from AZURE_DEVOPS_PAT or az CLI. Exits on failure.
_scm_azure_resolve_auth() {
  if [ -n "$AZURE_DEVOPS_PAT" ]; then
    _AZ_TOKEN=$(printf '%s' ":${AZURE_DEVOPS_PAT}" | base64)
    return 0
  fi

  if command -v az >/dev/null 2>&1; then
    local BEARER
    BEARER=$(az account get-access-token \
      --resource "499b84ac-1321-427f-aa17-267ca6975798" \
      --query accessToken -o tsv 2>/dev/null)
    if [ -n "$BEARER" ]; then
      _AZ_TOKEN="bearer:${BEARER}"
      return 0
    fi
  fi

  ui_error "Azure DevOps authentication not configured."
  ui_info  "Set AZURE_DEVOPS_PAT in config.env or run 'az login'."
  ui_info  "Required PAT scopes: Code (Read), Pull Request Threads (Read & Write)."
  exit 1
}

# _az_curl METHOD URL [BODY]
# Executes a curl request to the Azure DevOps REST API.
_az_curl() {
  local METHOD="$1" URL="$2" BODY="${3:-}"
  local AUTH_HEADER

  if echo "$_AZ_TOKEN" | grep -q "^bearer:"; then
    AUTH_HEADER="Authorization: Bearer ${_AZ_TOKEN#bearer:}"
  else
    AUTH_HEADER="Authorization: Basic ${_AZ_TOKEN}"
  fi

  if [ -n "$BODY" ]; then
    curl -s -X "$METHOD" "$URL" \
      -H "$AUTH_HEADER" \
      -H "Content-Type: application/json" \
      -d "$BODY"
  else
    curl -s -X "$METHOD" "$URL" \
      -H "$AUTH_HEADER"
  fi
}

# _scm_azure_pr_list
# Prints a normalized JSON array: [{number, title, author, headRefName}]
_scm_azure_pr_list() {
  local RAW
  RAW=$(_az_curl GET \
    "${_AZ_API_BASE}/pullrequests?api-version=7.1&searchCriteria.status=active")

  echo "$RAW" | jq -r '[.value[] | {
    number:      .pullRequestId,
    title:       .title,
    author:      .createdBy.displayName,
    headRefName: (.sourceRefName | ltrimstr("refs/heads/"))
  }]' 2>/dev/null
}

# _scm_azure_pr_view PR_ID
# Prints a normalized JSON object.
_scm_azure_pr_view() {
  local RAW
  RAW=$(_az_curl GET \
    "${_AZ_API_BASE}/pullrequests/$1?api-version=7.1")

  echo "$RAW" | jq '{
    title:        .title,
    body:         (.description // "No description provided."),
    author:       .createdBy.displayName,
    additions:    0,
    deletions:    0,
    changedFiles: 0,
    headRefOid:   .lastMergeSourceCommit.commitId,
    targetRef:    (.targetRefName | ltrimstr("refs/heads/")),
    sourceRef:    (.sourceRefName | ltrimstr("refs/heads/"))
  }' 2>/dev/null
}

# _scm_azure_pr_diff PR_ID
# Fetches updated refs and produces a local git diff, truncated to 400 lines.
_scm_azure_pr_diff() {
  local PR_INFO TARGET_REF SOURCE_REF
  PR_INFO=$(scm_pr_view "$1")
  TARGET_REF=$(echo "$PR_INFO" | jq -r '.targetRef')
  SOURCE_REF=$(echo "$PR_INFO" | jq -r '.sourceRef')

  git fetch --quiet origin \
    "refs/heads/${TARGET_REF}:refs/remotes/origin/${TARGET_REF}" \
    "refs/heads/${SOURCE_REF}:refs/remotes/origin/${SOURCE_REF}" \
    2>/dev/null

  git diff "origin/${TARGET_REF}...origin/${SOURCE_REF}" 2>/dev/null \
    | head -n 400
}

# _scm_azure_pr_get_comments PR_ID
# Fetches existing thread comments on the PR.
# Sets SCM_INLINE_COMMENTS_RAW (empty JSON array — Azure format differs) and
# SCM_REVIEW_COMMENTS (plain text list of comment bodies).
_scm_azure_pr_get_comments() {
  local RAW
  RAW=$(_az_curl GET "${_AZ_API_BASE}/pullrequests/$1/threads?api-version=7.1")
  SCM_INLINE_COMMENTS_RAW="[]"
  SCM_REVIEW_COMMENTS=$(echo "$RAW" | jq -r \
    '.value[].comments[] | select(.commentType == 1) | "[\(.author.displayName)] \(.content)"' \
    2>/dev/null || echo "")
}

# _scm_azure_pr_comment_reply COMMENT_ID BODY
# Azure DevOps does not support direct replies by comment ID in the same way.
# Falls back to posting a new general thread comment.
_scm_azure_pr_comment_reply() {
  _scm_azure_pr_comment "$PR_NUMBER" "$2"
}
# Posts a general thread comment. Prints "general" on success.
_scm_azure_pr_comment() {
  local PR_ID="$1" BODY="$2"
  local PAYLOAD
  PAYLOAD=$(jq -n --arg body "$BODY" \
    '{"comments":[{"parentCommentId":0,"content":$body,"commentType":1}],"status":1}')

  local RESULT
  RESULT=$(_az_curl POST \
    "${_AZ_API_BASE}/pullrequests/${PR_ID}/threads?api-version=7.1" \
    "$PAYLOAD")

  echo "$RESULT" | jq -e '.id' >/dev/null 2>&1 && echo "general" && return 0
  return 1
}

# _scm_azure_pr_comment_inline PR_ID BODY FILE LINE COMMIT
# Posts an inline thread comment at FILE:LINE.
# Falls back to a general comment if the inline post fails.
# Prints "inline" or "general" on success.
_scm_azure_pr_comment_inline() {
  local PR_ID="$1" BODY="$2" FILE_PATH="$3" LINE="$4"

  if [ -n "$FILE_PATH" ] && [ -n "$LINE" ]; then
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

    local RESULT
    RESULT=$(_az_curl POST \
      "${_AZ_API_BASE}/pullrequests/${PR_ID}/threads?api-version=7.1" \
      "$PAYLOAD")

    if echo "$RESULT" | jq -e '.id' >/dev/null 2>&1; then
      echo "inline"
      return 0
    fi
  fi

  _scm_azure_pr_comment "$PR_ID" "$BODY"
}
