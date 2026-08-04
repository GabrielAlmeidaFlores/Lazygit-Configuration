#!/usr/bin/env bats
# test_config_environment.bats — Tests environment-based configuration overrides

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"

@test "config: preserves AZURE_DEVOPS_PAT from the environment" {
  source "$LIB_DIR/ui.sh"
  export _CONFIG_FILE="$REPO_ROOT/settings.yaml"
  export _CONFIG_STATE="$(mktemp /tmp/bats_state_XXXXXX.yaml)"
  AZURE_DEVOPS_PAT="environment_pat"

  source "$LIB_DIR/config.sh"

  [ "$AZURE_DEVOPS_PAT" = "environment_pat" ]
  rm -f "$_CONFIG_STATE"
}
