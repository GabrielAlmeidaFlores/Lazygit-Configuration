#!/bin/bash
# lib/ui.sh — Terminal UI library
# Box-drawing borders, ANSI colors, no emojis. Compatible with bash 3.2+.
#
# Usage:
#   source "$SCRIPT_DIR/lib/ui.sh"
#
# Globals set by prompt functions (never use $(...) to call them):
#   UI_INPUT   — set by ui_prompt
#   UI_ACTION  — set by ui_prompt_proceed, ui_prompt_post,
#                         ui_prompt_triage, ui_prompt_review
#
# Layout
#   ui_header  "Title"                   Full-width header box
#   ui_panel   "line1" "line2" ...        Info box with multiple lines
#   ui_section "Title"                   Inline section separator with label
#   ui_spacer                            Blank line
#
# Messages
#   ui_success "msg"                     OK    msg  (green bold)
#   ui_error   "msg"                     FAIL  msg  (red bold)
#   ui_warning "msg"                     WARN  msg  (yellow)
#   ui_info    "msg"                           msg  (normal, indented)
#   ui_cancel                                  Cancelled.  (dim)
#   ui_step    "msg"                       →  msg  (cyan)
#
# Content
#   ui_content_box   "Title" "text"       Bordered box with green content
#   ui_code_snippet  "filename" "lines"   Bordered code block from diff
#   ui_issue_card    INDEX TOTAL CAT TEXT PR_CONTEXT
#
# Results table
#   ui_table_start
#   ui_table_row "Label" "Value" ["ok"|"warn"|"error"|""]
#   ui_table_end
#
# Checklist
#   ui_checklist_start "Title" N
#   ui_checklist_item  "text"
#   ui_checklist_end
#
# Prompts — write to /dev/tty, result in global, never call inside $(...)
#   ui_confirm         "Question"         [y/N]   → returns 0/1
#   ui_prompt          "Question"         free text → UI_INPUT
#   ui_prompt_proceed  "label"            [Enter]/[e]/[Ctrl+C] → UI_ACTION
#   ui_prompt_post                        [y]/[n]/[e] → UI_ACTION
#   ui_prompt_triage                      [g]/[n]/[q] → UI_ACTION
#   ui_prompt_review                      [y]/[e]/[n]/[q] → UI_ACTION
#   ui_press_enter                        Press Enter to exit

_CG="\033[0;32m"
_CGB="\033[1;32m"
_CR="\033[0;31m"
_CRB="\033[1;31m"
_CY="\033[0;33m"
_CC="\033[0;36m"
_CB="\033[1m"
_CD="\033[2m"
_C0="\033[0m"

_TERM_COLS=$(tput cols 2>/dev/null || echo 80)
_W=$(( _TERM_COLS > 64 ? _TERM_COLS - 1 : 63 ))
_IW=$((_W - 8))

_rep() {
  local N=$1 CHAR="$2" OUT="" I=0
  while [ $I -lt $N ]; do OUT="${OUT}${CHAR}"; I=$((I+1)); done
  printf '%s' "$OUT"
}

_top() { printf "  ╭%s╮\n" "$(_rep $((_W-4)) '─')"; }
_mid() { printf "  ├%s┤\n" "$(_rep $((_W-4)) '─')"; }
_bot() { printf "  ╰%s╯\n" "$(_rep $((_W-4)) '─')"; }

# _display_width STRING
# Returns the visual column width of STRING, accounting for double-width
# emoji characters (4-byte UTF-8 sequences display as 2 columns).
_display_width() {
  local TEXT="$1" WIDE
  WIDE=$(printf '%s' "$TEXT" | od -A n -t x1 | tr -s ' \n' '\n' | grep -cE '^f[0-4]$')
  printf '%d' $(( ${#TEXT} + WIDE ))
}

_row() {
  local TEXT="$1" COLOR="${2:-}"
  local TW
  TW=$(_display_width "$TEXT")
  [ "$TW" -gt "$_IW" ] && TEXT="${TEXT:0:$((_IW-3))}..." && TW=$((_IW))
  local PAD=$((_IW - TW))
  [ $PAD -lt 0 ] && PAD=0
  if [ -n "$COLOR" ]; then
    printf "  │  ${COLOR}%s${_C0}%${PAD}s  │\n" "$TEXT" ""
  else
    printf "  │  %s%${PAD}s  │\n" "$TEXT" ""
  fi
}

# ui_header "Title"
# Renders a full-width bordered header box with a bold title.
ui_header() {
  echo ""
  _top
  _row "$*" "$_CB"
  _bot
  echo ""
}

# ui_panel "line1" ["line2" ...]
# Renders a bordered info box with one row per argument.
ui_panel() {
  echo ""
  _top
  for LINE in "$@"; do _row "$LINE"; done
  _bot
  echo ""
}

# ui_section "Title"
# Renders an inline section separator: "  ──  Title  ──────────────"
ui_section() {
  local LABEL="$*"
  local DASHES=$((_W - ${#LABEL} - 8))
  [ $DASHES -lt 2 ] && DASHES=2
  echo ""
  printf "  ${_CB}──  %s${_C0}  %s\n" "$LABEL" "$(_rep $DASHES '─')"
  echo ""
}

_SPINNER_PID=""

# ui_spinner_start "message"
# Starts a background animated spinner on /dev/tty writing the given message.
# The spinner animates using braille frames (⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏) at 100ms intervals,
# overwriting the same terminal line with \r. Designed for sequential blocking
# operations where only one spinner runs at a time. Falls back to a static
# ui_step when /dev/tty is unavailable.
ui_spinner_start() {
  [ -n "$_SPINNER_PID" ] && return 0
  ( printf "" >/dev/tty ) 2>/dev/null || { ui_step "$1"; return 0; }
  local MSG="$1"
  local FRAMES="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  (
    local I=0
    while true; do
      local F="${FRAMES:$I:1}"
      ( printf "\r  ${_CC}%s${_C0}  %s  " "$F" "$MSG" >/dev/tty ) 2>/dev/null
      I=$(( (I + 1) % 10 ))
      sleep 0.2
    done
  ) &
  _SPINNER_PID=$!
}

# ui_spinner_stop
# Kills the running spinner process, clears the spinner line, and resets the PID.
# disown removes the job from bash's tracking table before killing so bash never
# prints a "Terminated" job-control notice to the terminal.
ui_spinner_stop() {
  if [ -n "$_SPINNER_PID" ]; then
    disown "$_SPINNER_PID" 2>/dev/null
    kill "$_SPINNER_PID" 2>/dev/null
    ( printf "\r\033[2K" >/dev/tty ) 2>/dev/null
    _SPINNER_PID=""
  fi
}

# ui_stacktrace "TITLE" ["DETAIL" ...]
# Renders a bordered error trace box to stderr for unrecoverable errors.
# TITLE is displayed in red bold; each subsequent argument is a detail line.
# Writes to stderr so it never pollutes captured stdout in $(...) calls.
ui_stacktrace() {
  local TITLE="$1"; shift
  local HEADER="❌  ${TITLE}"
  local TW
  TW=$(_display_width "$HEADER")
  local DASHES=$((_W - TW - 9))
  [ $DASHES -lt 1 ] && DASHES=1
  printf "\n  ╭─  ${_CRB}%s${_C0}  %s╮\n" "$HEADER" "$(_rep $DASHES '─')" >&2
  for LINE in "$@"; do
    [ -z "$LINE" ] && continue
    local LW PAD
    LW=$(_display_width "$LINE")
    PAD=$((_IW - LW))
    [ $PAD -lt 0 ] && PAD=0
    printf "  │  ${_CD}%s${_C0}%${PAD}s  │\n" "$LINE" "" >&2
  done
  printf "  ╰%s╯\n\n" "$(_rep $((_W-4)) '─')" >&2
}

ui_spacer() { echo ""; }

ui_success() { printf "  ${_CGB}✅${_C0}  %s\n"  "$*"; }
ui_error()   { printf "  ${_CRB}❌${_C0}  %s\n"  "$*"; }
ui_warning() { printf "  ${_CY}⚠️${_C0}  %s\n"   "$*"; }
ui_info()    { printf "  %s\n"                        "$*"; }
ui_cancel()  { printf "  ${_CD}🚫 Cancelled.${_C0}\n"; }
ui_step()    { printf "  ${_CC}→${_C0}  %s\n"   "$*"; }

# ui_print "text"
# Prints text followed by a newline. Use instead of echo in all scripts.
ui_print() { printf '%s\n' "$*"; }

# ui_print_raw "text"
# Prints text without a trailing newline.
ui_print_raw() { printf '%s' "$*"; }

# ui_icon "escape"
# Outputs a single character from a printf escape sequence or emoji.
ui_icon() { printf "$1"; }

# ui_content_box "Title" "text"
# Renders a bordered box with a bold title and green-colored content lines.
ui_content_box() {
  local TITLE="$1" CONTENT="$2"
  local TITLE_W
  TITLE_W=$(_display_width "$TITLE")
  local DASHES=$((_W - TITLE_W - 9))
  [ $DASHES -lt 1 ] && DASHES=1
  echo ""
  printf "  ╭─  ${_CB}%s${_C0}  %s╮\n" "$TITLE" "$(_rep $DASHES '─')"
  printf "  │%s│\n" "$(_rep $((_W-4)) ' ')"
  while IFS= read -r LINE; do
    local LINE_W
    LINE_W=$(_display_width "$LINE")
    if [ "$LINE_W" -gt "$_IW" ] 2>/dev/null; then
      printf '%s\n' "$LINE" | fold -s -w $_IW | while IFS= read -r WRAPPED; do
        local WRAP_W PAD
        WRAP_W=$(_display_width "$WRAPPED")
        PAD=$((_IW - WRAP_W))
        [ $PAD -lt 0 ] && PAD=0
        printf "  │  ${_CGB}%s${_C0}%${PAD}s  │\n" "$WRAPPED" ""
      done
    else
      local PAD=$((_IW - LINE_W))
      [ $PAD -lt 0 ] && PAD=0
      printf "  │  ${_CGB}%s${_C0}%${PAD}s  │\n" "$LINE" ""
    fi
  done <<< "$CONTENT"
  printf "  │%s│\n" "$(_rep $((_W-4)) ' ')"
  _bot
  echo ""
}

_COL=22

# ui_table_start
# Draws the top border of a results table. Follow with ui_table_row calls.
ui_table_start() {
  echo ""
  _top
}

# ui_table_row "Label" "Value" ["ok"|"warn"|"error"]
# Renders a single row with a bold label and a colored value.
ui_table_row() {
  local LABEL="$1" VALUE="$2" STATUS="${3:-}"
  local VCOLOR="$_C0"
  case "$STATUS" in
    ok)    VCOLOR="$_CG"  ;;
    warn)  VCOLOR="$_CY"  ;;
    error) VCOLOR="$_CR"  ;;
  esac
  local VCOL=$((_IW - _COL - 2))
  [ $VCOL -lt 4 ] && VCOL=4
  local LW VW
  LW=$(_display_width "$LABEL")
  local LPAD=$((_COL - LW))
  [ $LPAD -lt 0 ] && LPAD=0
  VW=$(_display_width "$VALUE")
  [ "$VW" -gt "$VCOL" ] && VALUE="${VALUE:0:$((VCOL-3))}..." && VW=$VCOL
  local VPAD=$(($VCOL - VW))
  [ $VPAD -lt 0 ] && VPAD=0
  printf "  │  ${_CB}%s${_C0}%${LPAD}s  ${VCOLOR}%s${_C0}%${VPAD}s  │\n" \
    "$LABEL" "" "$VALUE" ""
}

# ui_table_end
# Draws the bottom border of a results table.
ui_table_end() {
  _bot
  echo ""
}

# ui_checklist_start "Title" [N]
# Opens a checklist box with a bold title and optional item count.
ui_checklist_start() {
  local TITLE="$1" COUNT="${2:-}"
  local HEADER="$TITLE"
  [ -n "$COUNT" ] && HEADER="${TITLE}  (${COUNT})"
  echo ""
  _top
  _row "$HEADER" "$_CB"
  _mid
}

# ui_checklist_item "text"
# Renders a single [ ] item row inside a checklist box.
# Long items are word-wrapped; continuation lines are indented to align
# with the text start (after the "[ ] " prefix).
ui_checklist_item() {
  local TEXT="$1"
  local FIRST_W=$((_IW - 4))
  local CONT_W=$((_IW - 5))
  [ $FIRST_W -lt 4 ] && FIRST_W=4
  [ $CONT_W  -lt 4 ] && CONT_W=4
  local IS_FIRST=1
  printf '%s' "$TEXT" | fold -s -w $FIRST_W | while IFS= read -r CHUNK; do
    if [ "$IS_FIRST" = "1" ]; then
      local PAD=$(($FIRST_W - ${#CHUNK}))
      [ $PAD -lt 0 ] && PAD=0
      printf "  │  ${_CD}[ ]${_C0} %s%${PAD}s  │\n" "$CHUNK" ""
      IS_FIRST=0
    else
      local PAD=$(($CONT_W - ${#CHUNK}))
      [ $PAD -lt 0 ] && PAD=0
      printf "  │       %s%${PAD}s  │\n" "$CHUNK" ""
    fi
  done
}

# ui_checklist_end
# Closes a checklist box.
ui_checklist_end() {
  _bot
  echo ""
}

# ui_code_snippet "filename" "diff_lines"
# Renders a bordered code block. Lines starting with + are green, - are red.
ui_code_snippet() {
  local FILENAME="$1" CODE="$2"
  [ -z "$CODE" ] && return
  local FW DASHES
  FW=$(_display_width "$FILENAME")
  DASHES=$((_W - FW - 9))
  [ $DASHES -lt 1 ] && DASHES=1
  echo ""
  printf "  ╭─  ${_CD}%s${_C0}  %s╮\n" "$FILENAME" "$(_rep $DASHES '─')"
  while IFS= read -r LINE; do
    local COLOR="$_CD"
    case "$LINE" in
      "+"*) COLOR="$_CG" ;;
      "-"*) COLOR="$_CR" ;;
    esac
    local LW STRIPPED PAD
    LW=$(_display_width "$LINE")
    if [ "$LW" -gt "$_IW" ] 2>/dev/null; then
      STRIPPED="${LINE:0:$((_IW-3))}..."
      LW=$_IW
    else
      STRIPPED="$LINE"
    fi
    PAD=$((_IW - LW))
    [ $PAD -lt 0 ] && PAD=0
    printf "  │  ${COLOR}%s${_C0}%${PAD}s  │\n" "$STRIPPED" ""
  done <<< "$CODE"
  _bot
  echo ""
}

# ui_issue_card INDEX TOTAL CATEGORY TEXT PR_CONTEXT
# Renders a rich bordered card for a single PR issue.
# The issue text is word-wrapped. PR context is shown in dim at the bottom.
ui_issue_card() {
  local INDEX="$1" TOTAL="$2" CATEGORY="$3" TEXT="$4" PR_CONTEXT="$5"
  local HEADER="Issue ${INDEX} of ${TOTAL}  ·  ${CATEGORY}"
  echo ""
  _top
  _row "$HEADER" "$_CB"
  _mid
  echo "$TEXT" | fold -s -w $_IW | while IFS= read -r LINE; do
    _row "$LINE"
  done
  _row ""
  _row "$PR_CONTEXT" "$_CD"
  _bot
  echo ""
}

UI_INPUT=""
UI_ACTION=""

# ui_confirm "Question"
# Displays a [y/N] prompt. Returns 0 if the user answers y/Y, 1 otherwise.
ui_confirm() {
  local Q="${1:-Continue?}"
  local ANS
  printf "\n  %s ${_CD}[y/N]${_C0}  " "$Q" >/dev/tty
  read -r ANS </dev/tty
  [[ "$ANS" =~ ^[yY]$ ]]
}

# ui_prompt "Question"
# Displays a free-text input prompt. Stores the result in UI_INPUT.
# If the user presses Enter without typing, the arrow line is erased.
ui_prompt() {
  UI_INPUT=""
  printf "\n  %s\n  ${_CC}→${_C0}  " "$1" >/dev/tty
  read -r UI_INPUT </dev/tty
  [ -z "$UI_INPUT" ] && printf "\033[1A\033[2K\n" >/dev/tty
}

# ui_prompt_proceed "label"
# Displays [Enter] / [e] / [Ctrl+C] options. Stores result in UI_ACTION.
# UI_ACTION values: "proceed" | "edit" | "skip"
# Drains any buffered tty input before reading so that a keypress used to
# trigger the script (e.g. Lazygit keybinding) does not auto-confirm the prompt.
ui_prompt_proceed() {
  UI_ACTION=""
  local ANS _D
  while IFS= read -r -t 0.05 _D </dev/tty 2>/dev/null; do :; done
  printf "\n  ${_CD}[Enter]${_C0} %s   ${_CD}[e]${_C0} edit   ${_CD}[Ctrl+C]${_C0} cancel\n  ${_CC}→${_C0}  " "${1:-proceed}" >/dev/tty
  read -r ANS </dev/tty
  printf "\033[1A\033[2K\n" >/dev/tty
  case "$ANS" in
    [eE]) UI_ACTION="edit"    ;;
    "")   UI_ACTION="proceed" ;;
    *)    UI_ACTION="skip"    ;;
  esac
}

# ui_prompt_post
# Displays [y] / [n] / [e] options for posting a comment. Stores result in UI_ACTION.
# UI_ACTION values: "post" | "edit" | "skip"
ui_prompt_post() {
  UI_ACTION=""
  local ANS
  printf "\n  ${_CD}[y]${_C0} post   ${_CD}[n]${_C0} skip   ${_CD}[e]${_C0} edit\n  ${_CC}→${_C0}  " >/dev/tty
  read -r ANS </dev/tty
  printf "\033[1A\033[2K\n" >/dev/tty
  case "$ANS" in
    [yY]) UI_ACTION="post" ;;
    [eE]) UI_ACTION="edit" ;;
    *)    UI_ACTION="skip" ;;
  esac
}

# ui_press_enter
# Displays a "Press Enter to exit" prompt and waits.
ui_press_enter() {
  printf "\n  ${_CD}Press Enter to exit...${_C0}  " >/dev/tty
  read -r _ </dev/tty
}

# ui_prompt_triage
# Stage 1 triage prompt for PR issue review. Stores result in UI_ACTION.
# UI_ACTION values: "generate" | "auto_post" | "ignore" | "quit"
#
#   [g] generate + review  — generate comment, show it, then approve/edit/skip
#   [a] auto-post          — generate and post in background, move to next issue
#   [n] ignore             — skip this issue entirely
#   [q] quit               — stop the loop
ui_prompt_triage() {
  UI_ACTION=""
  local ANS
  printf "\n  ${_CD}[g]${_C0} generate + review   ${_CD}[a]${_C0} auto-post   ${_CD}[n]${_C0} ignore   ${_CD}[q]${_C0} quit\n  ${_CC}→${_C0}  " >/dev/tty
  read -r ANS </dev/tty
  printf "\033[1A\033[2K\n" >/dev/tty
  case "$ANS" in
    [gG]) UI_ACTION="generate"  ;;
    [aA]) UI_ACTION="auto_post" ;;
    [qQ]) UI_ACTION="quit"      ;;
    *)    UI_ACTION="ignore"    ;;
  esac
}

# ui_prompt_review
# Stage 2 comment review prompt for PR issue review. Stores result in UI_ACTION.
# UI_ACTION values: "post" | "edit" | "skip" | "quit"
ui_prompt_review() {
  UI_ACTION=""
  local ANS
  printf "\n  ${_CD}[y]${_C0} post   ${_CD}[e]${_C0} edit   ${_CD}[n]${_C0} skip   ${_CD}[q]${_C0} quit\n  ${_CC}→${_C0}  " >/dev/tty
  read -r ANS </dev/tty
  printf "\033[1A\033[2K\n" >/dev/tty
  case "$ANS" in
    [yY]) UI_ACTION="post" ;;
    [eE]) UI_ACTION="edit" ;;
    [qQ]) UI_ACTION="quit" ;;
    *)    UI_ACTION="skip" ;;
  esac
}

ui_print() {
  printf '%s\n' "$1"
}

ui_print_raw() {
  printf '%s' "$1"
}
