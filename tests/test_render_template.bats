#!/usr/bin/env bats
# test_render_template.bats — Unit tests for render_template in lib/utils.sh

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB_DIR="$REPO_ROOT/commands/lib"

setup() {
  source "$LIB_DIR/ui.sh"
  source "$LIB_DIR/utils.sh"
}

@test "render_template: replaces a single placeholder" {
  result=$(render_template "Hello __NAME__!" "__NAME__" "World")
  [ "$result" = "Hello World!" ]
}

@test "render_template: replaces multiple placeholders in one call" {
  result=$(render_template "__GREETING__ __NAME__!" "__GREETING__" "Hi" "__NAME__" "Alice")
  [ "$result" = "Hi Alice!" ]
}

@test "render_template: replaces all occurrences of the same placeholder" {
  result=$(render_template "__X__ and __X__" "__X__" "foo")
  [ "$result" = "foo and foo" ]
}

@test "render_template: returns template unchanged when no matching placeholder" {
  result=$(render_template "No placeholders here" "__MISSING__" "value")
  [ "$result" = "No placeholders here" ]
}

@test "render_template: handles empty replacement value" {
  result=$(render_template "Before __MID__ After" "__MID__" "")
  [ "$result" = "Before  After" ]
}

@test "render_template: handles multiline replacement value" {
  local diff_value="line1
line2
line3"
  result=$(render_template "DIFF:\n__DIFF__\nEND" "__DIFF__" "$diff_value")
  [[ "$result" == *"line1"* ]]
  [[ "$result" == *"line2"* ]]
  [[ "$result" == *"line3"* ]]
}

@test "render_template: handles placeholder at start of template" {
  result=$(render_template "__PREFIX__ rest" "__PREFIX__" "START")
  [ "$result" = "START rest" ]
}

@test "render_template: handles placeholder at end of template" {
  result=$(render_template "rest __SUFFIX__" "__SUFFIX__" "END")
  [ "$result" = "rest END" ]
}
