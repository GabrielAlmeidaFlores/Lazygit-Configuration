#!/bin/bash
# gateway.sh — SCM provider gateway
#
# Detects the source control provider from the git remote URL and dispatches
# all PR operations to the correct implementation. Exposes a uniform API so
# review_pr.sh stays provider-agnostic.
#
# Supported providers:
#   github       — github.com remotes (uses gh CLI)
#   azure-devops — dev.azure.com / visualstudio.com remotes (uses REST API)
#
# Source this file, then call scm_detect before any other scm_* function.
#
# Public API:
#   scm_detect
#     Reads the remote URL, sets SCM_PROVIDER and provider-specific context
#     variables. Must be called before any other scm_* function.
#     Exits with an error if the provider is unsupported.
#
#   scm_pr_list
#     Prints a JSON array of open PRs with normalized fields:
#     [{number, title, author, headRefName}]
#
#   scm_pr_view PR_ID
#     Prints a JSON object with normalized fields:
#     {title, body, author, additions, deletions, changedFiles, headRefOid}
#
#   scm_pr_diff PR_ID
#     Prints the PR diff (max 400 lines).
#
#   scm_pr_comment PR_ID BODY
#     Posts a general (non-inline) comment on the PR.
#     Prints "general" on success.
#
#   scm_pr_comment_inline PR_ID BODY FILE LINE COMMIT
#     Posts an inline comment at FILE:LINE. Falls back to a general comment
#     if the inline post fails. Prints "inline" or "general" on success.

SCM_PROVIDER=""

_SCM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$_SCM_DIR/github.sh"
source "$_SCM_DIR/azure-devops.sh"

# scm_detect
# Reads git remote origin, sets SCM_PROVIDER and initialises the provider.
scm_detect() {
  local REMOTE_URL
  REMOTE_URL=$(git remote get-url origin 2>/dev/null)

  if [ -z "$REMOTE_URL" ]; then
    ui_error "No git remote 'origin' found."
    exit 1
  fi

  case "$REMOTE_URL" in
    *github.com*)
      SCM_PROVIDER="github"
      _scm_github_init "$REMOTE_URL"
      ;;
    *dev.azure.com*|*visualstudio.com*|*ssh.dev.azure.com*)
      SCM_PROVIDER="azure-devops"
      _scm_azure_init "$REMOTE_URL"
      ;;
    *)
      ui_error "Unsupported remote URL: $REMOTE_URL"
      ui_info  "Supported providers: github.com, dev.azure.com, visualstudio.com"
      exit 1
      ;;
  esac
}

scm_pr_list() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_list ;;
    azure-devops) _scm_azure_pr_list  ;;
  esac
}

scm_pr_view() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_view "$1" ;;
    azure-devops) _scm_azure_pr_view  "$1" ;;
  esac
}

scm_pr_diff() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_diff "$1" ;;
    azure-devops) _scm_azure_pr_diff  "$1" ;;
  esac
}

scm_pr_comment() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_comment "$1" "$2" ;;
    azure-devops) _scm_azure_pr_comment  "$1" "$2" ;;
  esac
}

scm_pr_comment_inline() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_comment_inline "$@" ;;
    azure-devops) _scm_azure_pr_comment_inline  "$@" ;;
  esac
}

# scm_pr_get_comments PR_ID
# Returns existing inline and general comments on the PR as two variables:
# Prints two lines: "inline:<json>" and "general:<json>"
scm_pr_get_comments() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_get_comments "$@" ;;
    azure-devops) _scm_azure_pr_get_comments  "$@" ;;
  esac
}

# scm_pr_comment_reply COMMENT_ID BODY
# Posts a reply to an existing inline comment. Falls back to general comment.
scm_pr_comment_reply() {
  case "$SCM_PROVIDER" in
    github)       _scm_github_pr_comment_reply "$@" ;;
    azure-devops) _scm_azure_pr_comment_reply  "$@" ;;
  esac
}
