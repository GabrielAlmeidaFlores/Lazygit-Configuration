#!/usr/bin/env bats
# test_github_thread_resolution.bats — Unit tests for GitHub review-thread resolution

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"
ADAPTER="$REPO_ROOT/commands/gateways/adapters/scm/github.sh"

setup() {
  source "$LIB_DIR/ui.sh"
  source "$ADAPTER"
}

@test "_scm_github_pr_resolve_comment: resolves the matching open thread" {
  _gh() {
    case "$*" in
      *"repo view"*) ui_print "owner/repository" ;;
      *"resolveReviewThread"*) ui_print "true" ;;
      *) ui_print '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"THREAD_ID","isResolved":false,"comments":{"nodes":[{"databaseId":123}]}}]}}}}}' ;;
    esac
  }

  run _scm_github_pr_resolve_comment 6 123

  [ "$status" -eq 0 ]
}

@test "_scm_github_pr_resolve_comment: skips an already resolved thread" {
  _gh() {
    case "$*" in
      *"repo view"*) ui_print "owner/repository" ;;
      *"resolveReviewThread"*) return 1 ;;
      *) ui_print '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[{"id":"THREAD_ID","isResolved":true,"comments":{"nodes":[{"databaseId":123}]}}]}}}}}' ;;
    esac
  }

  run _scm_github_pr_resolve_comment 6 123

  [ "$status" -eq 0 ]
}

@test "_scm_github_pr_resolve_comment: rejects a comment without a thread" {
  _gh() {
    case "$*" in
      *"repo view"*) ui_print "owner/repository" ;;
      *) ui_print '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}' ;;
    esac
  }

  run _scm_github_pr_resolve_comment 6 123

  [ "$status" -eq 1 ]
}

@test "_scm_github_pr_comment_inline: rejects a comment without a location" {
  _gh() { return 99; }

  run _scm_github_pr_comment_inline 6 "Review comment" "" "" "commit"

  [ "$status" -eq 1 ]
}

@test "_scm_github_pr_comment_inline: posts an inline review comment" {
  _gh() { return 0; }

  run _scm_github_pr_comment_inline 6 "Review comment" "src/app.ts" 12 "commit"

  [ "$status" -eq 0 ]
  [ "$output" = "inline" ]
}
