#!/bin/bash
# github.sh — GitHub SCM adapter
#
# Implements the scm_* API for github.com remotes using the gh CLI.
# Authentication priority:
#   1. PAT embedded in the remote URL  (https://TOKEN@github.com/...)
#   2. git config --local github.user  →  gh auth token -u <user>
#   3. Default active gh account       (no override needed)
#
# The resolved token is stored in _GH_PAT and injected per-call via
# GH_TOKEN=... to avoid breaking the Copilot CLI (which rejects classic PATs
# when GH_TOKEN is set globally).
#
# Internal functions (prefixed _scm_github_) are called by gateway.sh only.

_GH_PAT=""

# _scm_github_init REMOTE_URL
# Resolves the authentication token for this repository.
_scm_github_init() {
  local REMOTE_URL="$1" PAT LOCAL_GH_USER TOKEN
  PAT=$(echo "$REMOTE_URL" | sed -n 's|https://\([^@]*\)@github\.com.*|\1|p')
  if [ -n "$PAT" ]; then
    _GH_PAT="$PAT"
    return 0
  fi
  LOCAL_GH_USER=$(git config --local github.user 2>/dev/null)
  if [ -n "$LOCAL_GH_USER" ]; then
    TOKEN=$(gh auth token -u "$LOCAL_GH_USER" 2>/dev/null)
    [ -n "$TOKEN" ] && _GH_PAT="$TOKEN"
  fi
}

# _gh — runs gh with the resolved token when available.
_gh() {
  if [ -n "$_GH_PAT" ]; then
    GH_TOKEN="$_GH_PAT" gh "$@"
  else
    gh "$@"
  fi
}

# _scm_github_pr_list
# Prints a JSON array: [{number, title, author, headRefName}]
_scm_github_pr_list() {
  _gh pr list --state open \
    --json number,title,author,headRefName 2>/dev/null
}

# _scm_github_pr_view PR_ID
# Prints a JSON object: {title, body, author, additions, deletions, changedFiles, headRefOid}
_scm_github_pr_view() {
  _gh pr view "$1" \
    --json title,body,author,additions,deletions,changedFiles,headRefOid \
    2>/dev/null
}

# _scm_github_pr_diff PR_ID
# Prints the PR diff, truncated to 400 lines.
_scm_github_pr_diff() {
  _gh pr diff "$1" 2>/dev/null | head -n 400
}

# _scm_github_pr_get_comments PR_ID
# Fetches inline review comments and general PR comments.
# Sets SCM_INLINE_COMMENTS_RAW (JSON array) and SCM_REVIEW_COMMENTS (text).
_scm_github_pr_get_comments() {
  SCM_INLINE_COMMENTS_RAW=$(_gh api "repos/{owner}/{repo}/pulls/$1/comments" 2>/dev/null || echo "[]")
  SCM_REVIEW_COMMENTS=$(_gh pr view "$1" --json comments \
    --jq '.comments[] | "[\(.author.login)] \(.body)"' 2>/dev/null || echo "")
}

# _scm_github_pr_comment_reply COMMENT_ID BODY
# Posts a reply to an existing inline review comment.
_scm_github_pr_comment_reply() {
  _gh api "repos/{owner}/{repo}/pulls/comments/$1/replies" \
    --method POST \
    --field body="$2" \
    >/dev/null 2>&1
}
# Posts a general comment. Prints "general" on success, returns 1 on failure.
_scm_github_pr_comment() {
  if _gh pr comment "$1" --body "$2" 2>/dev/null; then
    echo "general"
    return 0
  fi
  return 1
}

# _scm_github_pr_comment_inline PR_ID BODY FILE LINE COMMIT
# Posts an inline review comment at FILE:LINE using the GitHub REST API.
# Falls back to a general comment if the inline post fails.
# Prints "inline" or "general" on success, returns 1 on failure.
_scm_github_pr_comment_inline() {
  local PR_NUM="$1" BODY="$2" FILE_PATH="$3" LINE="$4" COMMIT="$5"

  if [ -n "$FILE_PATH" ] && [ -n "$LINE" ] && [ -n "$COMMIT" ]; then
    if _gh api "repos/{owner}/{repo}/pulls/${PR_NUM}/comments" \
        --method POST \
        --field body="$BODY" \
        --field commit_id="$COMMIT" \
        --field path="$FILE_PATH" \
        --field line="$LINE" \
        --field side="RIGHT" \
        >/dev/null 2>&1; then
      echo "inline"
      return 0
    fi
  fi

  if _gh pr comment "$PR_NUM" --body "$BODY" 2>/dev/null; then
    echo "general"
    return 0
  fi

  return 1
}
