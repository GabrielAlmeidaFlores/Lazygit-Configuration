#!/usr/bin/env bats
# test_azure_thread_resolution.bats — Unit tests for Azure DevOps thread resolution

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"
ADAPTER="$REPO_ROOT/commands/gateways/adapters/scm/azure-devops.sh"

setup() {
  source "$LIB_DIR/ui.sh"
  source "$ADAPTER"
  _AZ_API_BASE="https://dev.azure.com/organization/project/_apis/git/repositories/repository"
}

@test "_scm_azure_pr_resolve_comment: marks the matching open thread as fixed" {
  _az_curl() {
    case "$1" in
      GET) ui_print '{"value":[{"id":456,"status":1,"comments":[{"id":123}]}]}' ;;
      PATCH) ui_print '{"id":456,"status":2}' ;;
    esac
  }

  run _scm_azure_pr_resolve_comment 6 123

  [ "$status" -eq 0 ]
}

@test "_scm_azure_pr_resolve_comment: skips an already fixed thread" {
  _az_curl() {
    ui_print '{"value":[{"id":456,"status":2,"comments":[{"id":123}]}]}'
  }

  run _scm_azure_pr_resolve_comment 6 123

  [ "$status" -eq 0 ]
}

@test "_scm_azure_pr_resolve_comment: rejects a comment without a thread" {
  _az_curl() {
    ui_print '{"value":[]}'
  }

  run _scm_azure_pr_resolve_comment 6 123

  [ "$status" -eq 1 ]
}

@test "_scm_azure_pr_comment_inline: rejects a comment without a location" {
  _az_curl() { return 99; }

  run _scm_azure_pr_comment_inline 6 "Review comment" "" "" "commit"

  [ "$status" -eq 1 ]
}
