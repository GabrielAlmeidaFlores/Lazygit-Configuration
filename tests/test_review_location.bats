#!/usr/bin/env bats

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  source "$REPO_ROOT/commands/lib/ui.sh"
  REVIEW_HELPERS="$BATS_TEST_TMPDIR/review_location.sh"
  awk '/^RESULTS_DIR=/ { exit } /^# get_diff_location/ { capture=1 } capture { print }' "$REPO_ROOT/commands/review_pr.sh" > "$REVIEW_HELPERS"
  source "$REVIEW_HELPERS"
  DIFF='diff --git a/src/services/auth.ts b/src/services/auth.ts
index 1111111..2222222 100644
--- a/src/services/auth.ts
+++ b/src/services/auth.ts
@@ -8,4 +8,5 @@ export function authenticate(token: string) {
   const user = lookup(token)
+  logger.debug(token)
   return user
 }'
}

@test "_parse_issue_location: preserves the full path and new-file line" {
  _parse_issue_location "src/services/auth.ts:10 - Sensitive token is logged"

  [ "$_ISSUE_PATH" = "src/services/auth.ts" ]
  [ "$_ISSUE_LINE" = "10" ]
}

@test "_resolve_comment_location: uses the validated analysis location" {
  _resolve_comment_location "src/services/auth.ts:10" "src/services/auth.ts" "Sensitive token is logged" "$DIFF"

  [ "$_DIFF_PATH" = "src/services/auth.ts" ]
  [ "$_DIFF_LINE" = "10" ]
}

@test "_resolve_comment_location: rejects a location from another similarly named file" {
  _resolve_comment_location "src/auth.ts:10" "src/auth.ts" "Sensitive token is logged" "$DIFF"

  [ "$_DIFF_PATH" = "" ]
  [ "$_DIFF_LINE" = "" ]
}
