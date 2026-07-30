#!/bin/bash
# lib/ui.sh — Terminal UI library
# Box-drawing + ANSI colors, no emojis. Bash 3.2+ compatible.
#
# Source in any script:
#   source "$SCRIPT_DIR/lib/ui.sh"
#
# ─── API ──────────────────────────────────────────────────────────────────────
#
# Layout
#   ui_header  "Title"               full-width header box
#   ui_panel   "line1" "line2" ...   info box (multiple lines)
#   ui_section "Title"               inline section separator with label
#   ui_spacer                        blank line
#
# Messages
#   ui_success "msg"                 OK    msg  (green)
#   ui_error   "msg"                 FAIL  msg  (red)
#   ui_warning "msg"                 WARN  msg  (yellow)
#   ui_info    "msg"                       msg  (normal, indented)
#   ui_cancel                              Cancelled.  (dim)
#   ui_step    "msg"                  →   msg  (cyan, for progress steps)
#
# Content box
#   ui_content_box "Title" "text"    bordered box with colored content inside
#
# Results table
#   ui_table_start                   draw top border
#   ui_table_row "Label" "Value" ["ok"|"warn"|"error"|""]
#   ui_table_end                     draw bottom border
#
# Checklist
#   ui_checklist_start "Title" N     header box with title and item count
#   ui_checklist_item  "text"        [ ] text row inside the box
#   ui_checklist_end                 bottom border
#
# Prompts
#   ui_confirm  "Question"           Question [y/N]  → returns 0 (yes) or 1 (no)
#   ui_prompt   "Question"           Question:       → echoes the user's input
#   ui_prompt_proceed "label"        [Enter] label / [e] edit / [Ctrl+C] cancel
#   ui_prompt_post                   [y] post / [n] skip / [e] edit
#   ui_press_enter                   Press Enter to exit...

# ─── Colors ───────────────────────────────────────────────────────────────────
_CG="\033[0;32m"    # green
_CGB="\033[1;32m"   # green bold
_CR="\033[0;31m"    # red
_CRB="\033[1;31m"   # red bold
_CY="\033[0;33m"    # yellow
_CC="\033[0;36m"    # cyan
_CB="\033[1m"       # bold
_CD="\033[2m"       # dim
_C0="\033[0m"       # reset

# ─── Layout constants ─────────────────────────────────────────────────────────
# Total printed width of a box line (including the 2-space left margin):
#   "  ╭" + (_W-4) dashes + "╮"  =  _W chars on screen
# Inner content width for a row:
#   "  │  " (5) + _IW chars + "  │" (3) = _W chars → _IW = _W - 8
_W=60
_IW=$((_W - 8))   # = 52

# ─── Internal helpers ─────────────────────────────────────────────────────────

# Repeat CHAR exactly N times
_rep() {
  local N=$1 CHAR="$2" OUT="" I=0
  while [ $I -lt $N ]; do OUT="${OUT}${CHAR}"; I=$((I+1)); done
  printf '%s' "$OUT"
}

# Box top/mid/bottom borders  (use _W-4 dashes so total width = _W)
_top() { printf "  ╭%s╮\n" "$(_rep $((_W-4)) '─')"; }
_mid() { printf "  ├%s┤\n" "$(_rep $((_W-4)) '─')"; }
_bot() { printf "  ╰%s╯\n" "$(_rep $((_W-4)) '─')"; }

# Padded interior row:  "  │  TEXT...PAD  │"
# Optionally wrap TEXT with a color code (COLOR/_C0).
_row() {
  local TEXT="$1" COLOR="${2:-}"
  # Truncate if text exceeds inner width
  [ ${#TEXT} -gt $_IW ] && TEXT="${TEXT:0:$((_IW-3))}..."
  local PAD=$((_IW - ${#TEXT}))
  if [ -n "$COLOR" ]; then
    printf "  │  ${COLOR}%s${_C0}%${PAD}s  │\n" "$TEXT" ""
  else
    printf "  │  %s%${PAD}s  │\n" "$TEXT" ""
  fi
}

# ─── Layout ───────────────────────────────────────────────────────────────────

ui_header() {
  echo ""
  _top
  _row "$*" "$_CB"
  _bot
  echo ""
}

ui_panel() {
  echo ""
  _top
  for LINE in "$@"; do _row "$LINE"; done
  _bot
  echo ""
}

# Inline section separator:  "  ──  LABEL  ─────────────"
ui_section() {
  local LABEL="$*"
  # 2 (margin) + 4 (── + spaces) + LABEL + 2 (spaces) + DASHES = _W
  local DASHES=$((_W - ${#LABEL} - 8))
  [ $DASHES -lt 2 ] && DASHES=2
  echo ""
  printf "  ${_CB}──  %s${_C0}  %s\n" "$LABEL" "$(_rep $DASHES '─')"
  echo ""
}

ui_spacer() { echo ""; }

# ─── Messages ─────────────────────────────────────────────────────────────────

ui_success() { printf "  ${_CGB}OK${_C0}    %s\n"   "$*"; }
ui_error()   { printf "  ${_CRB}FAIL${_C0}  %s\n"   "$*"; }
ui_warning() { printf "  ${_CY}WARN${_C0}  %s\n"    "$*"; }
ui_info()    { printf "  %s\n"                       "$*"; }
ui_cancel()  { printf "  ${_CD}Cancelled.${_C0}\n";       }
ui_step()    { printf "  ${_CC}→${_C0}  %s\n"       "$*"; }

# ─── Content box ──────────────────────────────────────────────────────────────
# "  ╭─  Title  ────────────────────────────────────────╮"
# "  │                                                  │"
# "  │  green-bold content line                         │"
# "  │                                                  │"
# "  ╰──────────────────────────────────────────────────╯"

ui_content_box() {
  local TITLE="$1" CONTENT="$2"
  # Header: "  ╭─  TITLE  DASHES╮"
  # chars:   2+1+1+2+TITLE+2+DASHES+1 = 9+TITLE+DASHES = _W
  local DASHES=$((_W - ${#TITLE} - 9))
  [ $DASHES -lt 1 ] && DASHES=1
  echo ""
  printf "  ╭─  ${_CB}%s${_C0}  %s╮\n" "$TITLE" "$(_rep $DASHES '─')"
  printf "  │%s│\n" "$(_rep $((_W-4)) ' ')"
  while IFS= read -r LINE; do
    [ ${#LINE} -gt $_IW ] && LINE="${LINE:0:$((_IW-3))}..."
    local PAD=$((_IW - ${#LINE}))
    printf "  │  ${_CGB}%s${_C0}%${PAD}s  │\n" "$LINE" ""
  done <<< "$CONTENT"
  printf "  │%s│\n" "$(_rep $((_W-4)) ' ')"
  _bot
  echo ""
}

# ─── Results table ────────────────────────────────────────────────────────────
# Layout per row:  "  │  LABEL    LPAD    VALUE    VPAD  │"
# Fixed label column width:
_COL=22

ui_table_start() {
  echo ""
  _top
}

ui_table_row() {
  local LABEL="$1" VALUE="$2" STATUS="${3:-}"
  local VCOLOR="$_C0"
  case "$STATUS" in
    ok)    VCOLOR="$_CG"  ;;
    warn)  VCOLOR="$_CY"  ;;
    error) VCOLOR="$_CR"  ;;
  esac
  # label col: _COL chars,  value col: _IW - _COL - 2 chars
  local VCOL=$((_IW - _COL - 2))
  [ $VCOL -lt 4 ] && VCOL=4
  local LPAD=$((_COL - ${#LABEL}))
  [ $LPAD -lt 0 ] && LPAD=0
  [ ${#VALUE} -gt $VCOL ] && VALUE="${VALUE:0:$((VCOL-3))}..."
  local VPAD=$(($VCOL - ${#VALUE}))
  [ $VPAD -lt 0 ] && VPAD=0
  printf "  │  ${_CB}%s${_C0}%${LPAD}s  ${VCOLOR}%s${_C0}%${VPAD}s  │\n" \
    "$LABEL" "" "$VALUE" ""
}

ui_table_end() {
  _bot
  echo ""
}

# ─── Checklist ────────────────────────────────────────────────────────────────
# Row format:  "  │  [ ] TEXT...PAD  │"
# chars:        2+1+2+4+TEXT+PAD+2+1 = 12+TEXT+PAD = _W  →  TEXT+PAD = _W-12
# TEXT max = _IW - 4  (since _IW = _W-8 and TEXT+PAD = _IW-4 when PAD>=0)

ui_checklist_start() {
  local TITLE="$1" COUNT="${2:-}"
  local HEADER="$TITLE"
  [ -n "$COUNT" ] && HEADER="${TITLE}  (${COUNT})"
  echo ""
  _top
  _row "$HEADER" "$_CB"
  _mid
}

ui_checklist_item() {
  local TEXT="$1"
  local MAX=$((_IW - 4))          # max text chars  (4 = "[ ] " prefix)
  [ ${#TEXT} -gt $MAX ] && TEXT="${TEXT:0:$((MAX-3))}..."
  local PAD=$((_IW - 4 - ${#TEXT}))
  [ $PAD -lt 0 ] && PAD=0
  printf "  │  ${_CD}[ ]${_C0} %s%${PAD}s  │\n" "$TEXT" ""
}

ui_checklist_end() {
  _bot
  echo ""
}

# ─── Prompts ──────────────────────────────────────────────────────────────────

ui_confirm() {
  local Q="${1:-Continue?}"
  local ANS
  printf "\n  %s ${_CD}[y/N]${_C0}  " "$Q"
  read -r ANS
  [[ "$ANS" =~ ^[yY]$ ]]
}

ui_prompt() {
  local Q="$1"
  local ANS
  printf "  %s: " "$Q"
  read -r ANS
  echo "$ANS"
}

ui_prompt_proceed() {
  local LABEL="${1:-proceed}"
  local ANS
  printf "\n  ${_CD}[Enter]${_C0} %s   ${_CD}[e]${_C0} edit   ${_CD}[Ctrl+C]${_C0} cancel  " "$LABEL"
  read -r ANS
  case "$ANS" in
    [eE]) echo "edit"    ;;
    "")   echo "proceed" ;;
    *)    echo "skip"    ;;
  esac
}

ui_prompt_post() {
  local ANS
  printf "\n  ${_CD}[y]${_C0} post   ${_CD}[n]${_C0} skip   ${_CD}[e]${_C0} edit  "
  read -r ANS
  case "$ANS" in
    [yY]) echo "post" ;;
    [eE]) echo "edit" ;;
    *)    echo "skip" ;;
  esac
}

ui_press_enter() {
  printf "\n  ${_CD}Press Enter to exit...${_C0}  "
  read -r _
}
