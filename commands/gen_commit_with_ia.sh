#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gateways/generative-ia.sh"

FILES=$(git diff --cached --name-only | head -n 15 | tr '\n' ', ')
if [ -z "$FILES" ]; then
  echo "❌ Error: No changes staged."
  exit 1
fi

DIFF_SNIPPET=$(git diff --cached --unified=3 --no-color | head -n 200)

select_model

echo ""
read -p "📋 Optional Context (Enter to skip): " USER_CONTEXT
echo ""

VERBOSE=1

CONTEXT_SECTION=""
if [ -n "$USER_CONTEXT" ]; then
  CONTEXT_SECTION="USER PROVIDED CONTEXT: $USER_CONTEXT"
fi

PROMPT="
Analyze the following DIFF code and follow the instructions below.

### START OF DIFF ###
$DIFF_SNIPPET
### END OF DIFF ###

$CONTEXT_SECTION

INSTRUCTIONS FOR SENIOR STAFF ENGINEER:
Generate a Pull Request-style summary based on the DIFF above.

STRICT STRUCTURE:
1. Single-line title (max 70 chars).
2. A blank line.
3. Detailed overview paragraph (3-4 sentences) explaining 'what' and 'why'.
4. Section: **<Category 1>**:
   - Bullet points for technical 'how' using \`inline code\`.
5. Section: **<Category 2>**:
   - Bullet points for logic details.

CRITICAL RULES:
- NO PREAMBLE: Start directly with the title. No 'Here is...' or 'Sure'.
- LANGUAGE: STRICT English.
- NO CODE COMPLETION: Do not try to finish the code in the diff.
- OUTPUT: ONLY the message.
"

RAW_MSG=$(generative_ia "$PROMPT" "$VERBOSE")
EXIT_CODE=$?
if [ $EXIT_CODE -eq 130 ]; then
  exit 0
fi
if [ $EXIT_CODE -ne 0 ]; then
  echo "❌ Error: Failed to get AI response."
  exit 1
fi

TEMP_MSG_FILE=$(mktemp)

echo -e "\n📝 AI Suggested Commit Message:\n"
echo -e "----------------------------------------"
echo -e "\033[1;32m$RAW_MSG\033[0m"
echo -e "----------------------------------------\n"

echo "$RAW_MSG" >"$TEMP_MSG_FILE"

read -p "Press [Enter] to commit, [e] to edit, or [Ctrl+C] to cancel: " ACTION

if [[ "$ACTION" == "e" ]]; then
  ${EDITOR:-nano} "$TEMP_MSG_FILE"
  RAW_MSG=$(cat "$TEMP_MSG_FILE")
fi

if [ -n "$RAW_MSG" ]; then
  git commit -F "$TEMP_MSG_FILE"
  echo "✅ Committed successfully!"
else
  echo "❌ Error: Message is empty. Commit aborted."
fi

rm "$TEMP_MSG_FILE"
