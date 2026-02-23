#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/gateways/generative-ia.sh"


FILES_CHANGED=$(git diff --cached --name-only | head -n 10)
if [ -z "$FILES_CHANGED" ]; then
  echo "❌ Error: No changes staged."
  exit 1
fi

DIFF_STAT=$(git diff --cached --stat | head -n 15)
DIFF_SNIPPET=$(git diff --cached --unified=3 | head -n 60)

PROMPT="As a Senior Developer, categorize these git changes and suggest a branch name.

FILES:
$FILES_CHANGED

STATS:
$DIFF_STAT

DIFF SNIPPET:
$DIFF_SNIPPET

LANGUAGE REQUIREMENT (CRITICAL):
- MUST use ONLY English language for the branch name.
- NO Spanish, Portuguese, or any other language allowed.
- All words in the branch name MUST be in English.

DECISION LOGIC:
1. If existing logic is being corrected, replaced, or adjusted → fix/
2. If new files or new modules are added → feat/
3. If only config, deps, docker, ci, build files changed → chore/
4. If code structure changes but behavior is same → refactor/
5. If only markdown or comments → docs/

If unsure between fix and feat:
- Changing existing lines = fix
- Adding entirely new capability = feat
- If modifying existing logic, prefer fix.
- DO NOT default to feat.

STRICT RULES:
- Use ONLY English language for the branch name.
- DO NOT include emojis in the branch name.
- Use kebab-case for the description.
- Be SPECIFIC. (e.g., 'fix/auth-token-validation' NOT 'fix/bug').
- Output ONLY the branch name. No explanations. No prose."

RAW_NAME=$(generative_ia "$PROMPT" | tr -d '"' | xargs)
if [ $? -ne 0 ]; then
  echo "❌ Error: Failed to get AI response."
  exit 1
fi

CLEAN_NAME=$(echo "$RAW_NAME" | awk '{print $NF}' | tr -d '`')

case "$CLEAN_NAME" in
fix/*)
  EMOJI="🐛"
  ;;
feat/*)
  EMOJI="✨"
  ;;
chore/*)
  EMOJI="🔨"
  ;;
refactor/*)
  EMOJI="♻️"
  ;;
docs/*)
  EMOJI="📝"
  ;;
style/*)
  EMOJI="💄"
  ;;
test/*)
  EMOJI="✅"
  ;;
perf/*)
  EMOJI="⚡"
  ;;
*)
  EMOJI=""
  ;;
esac

echo -e "\n🤖 AI Suggested: \033[1;32m$CLEAN_NAME\033[0m"
if [ -n "$EMOJI" ]; then
  echo -e "   Emoji prefix: $EMOJI"
fi

read -p "Press [Enter] to create branch, [e] to edit, or [Ctrl+C] to cancel: " ACTION

if [[ "$ACTION" == "e" ]]; then
  TEMP_BRANCH_FILE=$(mktemp)
  echo "$CLEAN_NAME" >"$TEMP_BRANCH_FILE"
  ${EDITOR:-nano} "$TEMP_BRANCH_FILE"
  FINAL_NAME=$(cat "$TEMP_BRANCH_FILE")
  rm "$TEMP_BRANCH_FILE"
else
  FINAL_NAME="$CLEAN_NAME"
fi

if [ "$FINAL_NAME" == "$CLEAN_NAME" ] && [ -n "$EMOJI" ]; then
  FINAL_NAME="$EMOJI-$FINAL_NAME"
fi

if [ -n "$FINAL_NAME" ]; then
  git checkout -b "$FINAL_NAME"
  echo "✅ Switched to: $FINAL_NAME"
else
  echo "❌ Operation cancelled."
  exit 1
fi
