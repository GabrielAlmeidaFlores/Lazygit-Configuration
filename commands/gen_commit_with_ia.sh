#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gateways/generative-ia.sh"


FILES=$(git diff --cached --name-only | head -n 15 | tr '\n' ', ')
if [ -z "$FILES" ]; then
  echo "❌ Error: No changes staged."
  exit 1
fi

DIFF_SNIPPET=$(git diff --cached --unified=3 --no-color | head -n 200)

# Prompt user for additional context
echo ""
echo "📋 Optional: Provide additional context for the AI (press Enter to skip):"
read -p "Context: " USER_CONTEXT
echo ""

VERBOSE=1

# Build context section if user provided input
CONTEXT_SECTION=""
if [ -n "$USER_CONTEXT" ]; then
  CONTEXT_SECTION="

USER PROVIDED CONTEXT:
$USER_CONTEXT

Consider this context when analyzing the changes and generating the commit message."
fi


PROMPT="As a Senior Staff Engineer, perform a deep technical analysis of this diff.
Your task is to generate a professional, high-quality git commit message.

FILES MODIFIED: $FILES

STRICT STRUCTURE:
1. <gitmoji> <type>(<scope>): <summary>
   [blank line]
   - <Detailed Bullet Points>

LANGUAGE REQUIREMENT (CRITICAL):
- MUST use ONLY English language for the entire commit message.
- NO Spanish, Portuguese, or any other language allowed.
- All technical terms, descriptions, and explanations MUST be in English.

MAPPING RULES (MANDATORY):
- New logic/functionality? ✨ feat
- Fixing a bug/error? 🐛 fix
- Refactoring/Cleaning code? ♻️ refactor
- Build/Config/CI/Docker? 🔧 chore
- Docs/Comments? 📝 docs
- CSS/Styling/UI? 💄 style

ANALYSIS REQUIREMENTS:
- Do not be vague. 'Update files' is forbidden.
- Explain the 'WHY' behind the change.
- Identify the specific class, function, or component being changed.
- If multiple things changed, list them as separate technical bullets.
- Output ONLY the commit message. No conversational filler.
$CONTEXT_SECTION

DIFF:
$DIFF_SNIPPET"

RAW_MSG=$(generative_ia "$PROMPT" "$VERBOSE")
if [ $? -ne 0 ]; then
  echo "❌ Error: Failed to get AI response."
  exit 1
fi

echo -e "\n📝 AI Suggested Commit Message:\n"
echo -e "----------------------------------------"
echo -e "\033[1;32m$RAW_MSG\033[0m"
echo -e "----------------------------------------\n"

TEMP_MSG_FILE=$(mktemp)
echo "$RAW_MSG" >"$TEMP_MSG_FILE"

read -p "Press [Enter] to commit, [e] to edit, or [Ctrl+C] to cancel: " ACTION

if [[ "$ACTION" == "e" ]]; then
  ${EDITOR:-nano} "$TEMP_MSG_FILE"
  RAW_MSG=$(cat "$TEMP_MSG_FILE")
fi

if [ -n "$RAW_MSG" ]; then
  git commit -m "$RAW_MSG"
  echo "✅ Committed successfully!"
else
  echo "❌ Error: Message is empty. Commit aborted."
fi

rm "$TEMP_MSG_FILE"
