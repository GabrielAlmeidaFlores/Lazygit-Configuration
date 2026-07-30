#!/bin/bash
# gen_commit_with_ia.sh — AI-powered commit message generator for Lazygit
#
# Generates a conventional commit message from staged changes using the
# configured AI provider. Presents the result for review before committing.
#
# Dependencies: git (staged changes required)
# Config:       commands/config.env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/ui.sh"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

clear

ui_header "AI Commit Message"

FILES=$(git diff --cached --name-only | head -n 15 | tr '\n' ', ')
if [ -z "$FILES" ]; then
  ui_error "No staged changes found."
  exit 1
fi

DIFF_SNIPPET=$(git diff --cached --unified=3 --no-color | head -n 200)

ui_prompt "Optional context (Enter to skip)"
USER_CONTEXT="$UI_INPUT"

VERBOSE=1
CONTEXT_SECTION=""
[ -n "$USER_CONTEXT" ] && CONTEXT_SECTION="USER PROVIDED CONTEXT: $USER_CONTEXT"

PROMPT="
Analyze the following DIFF code and follow the instructions below.

### START OF DIFF ###
$DIFF_SNIPPET
### END OF DIFF ###

$CONTEXT_SECTION

INSTRUCTIONS FOR SENIOR STAFF ENGINEER:
Generate a Pull Request-style summary based on the DIFF above.

STRICT STRUCTURE:
1. Single-line title (max 30 chars).
2. A blank line.
3. Detailed overview paragraph (3-4 sentences) explaining 'what' and 'why'.
4. Section: **<Category 1>**:
   - Bullet points for technical 'how' using \`inline code\`.
5. Section: **<Category 2>**:
   - Bullet points for logic details.

CRITICAL RULES:
- NO PREAMBLE: Start directly with the title. No 'Here is...' or 'Sure'.
- NO CODE COMPLETION: Do not try to finish the code in the diff.
- OUTPUT: ONLY the message.
"

RAW_MSG=$(generative_ia "$PROMPT" "$VERBOSE")
EXIT_CODE=$?
[ $EXIT_CODE -eq 130 ] && exit 0
[ $EXIT_CODE -ne 0 ] && ui_error "Failed to get AI response." && exit 1

TEMP_MSG_FILE=$(mktemp)
echo "$RAW_MSG" > "$TEMP_MSG_FILE"

while true; do
  RAW_MSG=$(cat "$TEMP_MSG_FILE")
  ui_content_box "Suggested Commit Message" "$RAW_MSG"
  ui_prompt_proceed "commit"

  case "$UI_ACTION" in
    proceed)
      if [ -n "$RAW_MSG" ]; then
        git commit -F "$TEMP_MSG_FILE"
        ui_success "Committed successfully."
      else
        ui_error "Message is empty. Commit aborted."
      fi
      break
      ;;
    edit)
      ${EDITOR:-nano} "$TEMP_MSG_FILE"
      ;;
    *)
      ui_cancel
      break
      ;;
  esac
done

rm -f "$TEMP_MSG_FILE"
