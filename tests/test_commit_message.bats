#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  source "$REPO_ROOT/commands/lib/ui.sh"
  COMMIT_HELPERS="$BATS_TEST_TMPDIR/commit_message.sh"
  awk '/^# _commit_body/ { capture=1 } /^# _sync_pr_description/ { exit } capture { print }' "$REPO_ROOT/commands/gen_commit_with_ia.sh" > "$COMMIT_HELPERS"
  source "$COMMIT_HELPERS"
}

@test "_commit_body: accepts a body directly after the title" {
  run _commit_body "feat: add validation
Explains why validation is required."

  [ "$status" -eq 0 ]
  [ "$output" = "Explains why validation is required." ]
}

@test "_commit_body: removes the optional blank line after the title" {
  run _commit_body "feat: add validation

Explains why validation is required.

**Validation**:
- Adds required checks."

  [ "$status" -eq 0 ]
  [ "$output" = $'Explains why validation is required.\n\n**Validation**:\n- Adds required checks.' ]
}
