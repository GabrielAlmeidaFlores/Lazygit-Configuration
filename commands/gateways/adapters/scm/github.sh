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
  PAT=$(ui_print "$REMOTE_URL" | sed -n 's|https://\([^@]*\)@github\.com.*|\1|p')
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
# Prints a normalized JSON array including open and draft PRs:
# [{number, title, author, headRefName, baseRefName, isDraft}]
_scm_github_pr_list() {
  _gh pr list --state open \
    --json number,title,author,headRefName,baseRefName,isDraft 2>/dev/null \
    | jq '[.[] | {
        number:      .number,
        title:       .title,
        author:      .author.login,
        headRefName: .headRefName,
        baseRefName: .baseRefName,
        isDraft:     .isDraft
      }]'
}

# _scm_github_pr_view PR_ID
# Prints a normalized JSON object.
_scm_github_pr_view() {
  _gh pr view "$1" \
    --json title,body,author,additions,deletions,changedFiles,headRefOid \
    2>/dev/null \
    | jq '{
        title:        .title,
        body:         (.body // "No description provided."),
        author:       .author.login,
        additions:    .additions,
        deletions:    .deletions,
        changedFiles: .changedFiles,
        headRefOid:   .headRefOid
      }'
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
  SCM_INLINE_COMMENTS_RAW=$(_gh api "repos/{owner}/{repo}/pulls/$1/comments" 2>/dev/null || ui_print "[]")
  SCM_REVIEW_COMMENTS=$(_gh pr view "$1" --json comments \
    --jq '.comments[] | "[\(.author.login)] \(.body)"' 2>/dev/null || ui_print "")
}

# _scm_github_pr_resolve_comment PR_ID COMMENT_ID
# Resolves the review thread containing COMMENT_ID without removing the comment.
# Exit codes: 0 = resolved or already resolved, 1 = thread not found or API failure.
_scm_github_pr_resolve_comment() {
  local PR_ID="$1" COMMENT_ID="$2" REPO_SLUG OWNER REPO THREADS THREAD_STATE THREAD_ID IS_RESOLVED

  [[ "$PR_ID" =~ ^[0-9]+$ ]] || return 1
  [[ "$COMMENT_ID" =~ ^[0-9]+$ ]] || return 1

  REPO_SLUG=$(_gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || return 1
  OWNER="${REPO_SLUG%%/*}"
  REPO="${REPO_SLUG#*/}"
  [ -n "$OWNER" ] && [ -n "$REPO" ] && [ "$OWNER" != "$REPO" ] || return 1

  THREADS=$(_gh api graphql \
    -f query='query($owner: String!, $repo: String!, $pr: Int!) {
      repository(owner: $owner, name: $repo) {
        pullRequest(number: $pr) {
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 100) {
                nodes {
                  databaseId
                }
              }
            }
          }
        }
      }
    }' \
    -f owner="$OWNER" \
    -f repo="$REPO" \
    -F pr="$PR_ID" 2>/dev/null) || return 1

  THREAD_STATE=$(ui_print "$THREADS" | jq -r --argjson comment_id "$COMMENT_ID" '
    .data.repository.pullRequest.reviewThreads.nodes[]?
    | select(any(.comments.nodes[]?; .databaseId == $comment_id))
    | "\(.id)|\(.isResolved)"
  ' | head -n 1)

  [ -z "$THREAD_STATE" ] && return 1
  THREAD_ID="${THREAD_STATE%%|*}"
  IS_RESOLVED="${THREAD_STATE##*|}"
  [ "$IS_RESOLVED" = "true" ] && return 0

  _gh api graphql \
    -f query='mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread {
          isResolved
        }
      }
    }' \
    -f threadId="$THREAD_ID" \
    --jq '.data.resolveReviewThread.thread.isResolved' \
    2>/dev/null | grep -qx 'true'
}
# Posts a general comment. Prints "general" on success, returns 1 on failure.
_scm_github_pr_comment() {
  if _gh pr comment "$1" --body "$2" 2>/dev/null; then
    ui_print "general"
    return 0
  fi
  return 1
}

# _scm_github_pr_comment_inline PR_ID BODY FILE LINE COMMIT
# Posts an inline review comment at FILE:LINE using the GitHub REST API.
# Prints "inline" on success, returns 1 on failure.
_scm_github_pr_comment_inline() {
  local PR_NUM="$1" BODY="$2" FILE_PATH="$3" LINE="$4" COMMIT="$5"

  [ -n "$FILE_PATH" ] && [ -n "$LINE" ] && [ -n "$COMMIT" ] || return 1

  if _gh api "repos/{owner}/{repo}/pulls/${PR_NUM}/comments" \
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

  return 1
}
