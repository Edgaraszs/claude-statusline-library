#!/usr/bin/env bash
#
# Claude Code Statusline Library installer.
#
# Local:
#   ./install.sh                 # interactive picker
#   ./install.sh rate-limit      # install a template by name
#
# Remote:
#   curl -fsSL https://raw.githubusercontent.com/Edgaraszs/claude-statusline-library/main/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/Edgaraszs/claude-statusline-library/main/install.sh | bash -s -- rate-limit
#
set -euo pipefail

REPO_SLUG="Edgaraszs/claude-statusline-library"
REPO_BRANCH="main"
REPO_RAW="https://raw.githubusercontent.com/$REPO_SLUG/$REPO_BRANCH"

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
TARGET="$CLAUDE_DIR/statusline.sh"
SETTINGS="$CLAUDE_DIR/settings.json"

TEMPLATE=""
ASSUME_YES=0
DO_LIST=0
SKIP_SETTINGS=0

# name|description — keep in sync with the README table.
TEMPLATE_META='user-dir-branch|Username, current directory (~ for home), and git branch — a zsh-style prompt.
dir-branch-context|Current directory, git branch, and context window usage percentage.
rate-limit|Current directory, git branch, model, and multi-line 5h / 7d rate limit bars.'

# Sample stdin payload used to preview a template before installing it.
SAMPLE_JSON='{"hook_event_name":"Status","model":{"id":"claude-opus-5","display_name":"Opus 5"},"workspace":{"current_dir":"'"$PWD"'","project_dir":"'"$PWD"'"},"context_window":{"used_percentage":42.3},"rate_limits":{"five_hour":{"used_percentage":37},"seven_day":{"used_percentage":81}}}'

# ---- output helpers ----------------------------------------------------

if [ -t 1 ]; then
  C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'; C_OFF=$'\033[0m'
else
  C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''; C_OFF=''
fi

info()  { printf '%s\n' "$*"; }
step()  { printf '%s==>%s %s\n' "$C_CYAN$C_BOLD" "$C_OFF" "$*"; }
warn()  { printf '%swarning:%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

usage() {
  cat <<EOF
${C_BOLD}Claude Code Statusline Library installer${C_OFF}

Usage: install.sh [template] [options]

Options:
  -l, --list             List available templates and exit.
  -t, --target PATH      Where to write the script (default: $TARGET).
  -s, --settings PATH    settings.json to update (default: $SETTINGS).
      --no-settings      Copy the script but leave settings.json alone.
  -y, --yes              Don't prompt; accept defaults.
  -h, --help             Show this help.

With no template argument, an interactive picker is shown.
EOF
}

# ---- arg parsing -------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    -l|--list)      DO_LIST=1 ;;
    -y|--yes)       ASSUME_YES=1 ;;
    --no-settings)  SKIP_SETTINGS=1 ;;
    -t|--target)    [ $# -ge 2 ] || die "--target needs a path"; TARGET="$2"; shift ;;
    -s|--settings)  [ $# -ge 2 ] || die "--settings needs a path"; SETTINGS="$2"; shift ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1 (try --help)" ;;
    *)              [ -z "$TEMPLATE" ] || die "only one template can be installed at a time"
                    TEMPLATE="$1" ;;
  esac
  shift
done

# ---- source: local checkout or remote repo -----------------------------

SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  SRC_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi
if [ -z "$SRC_DIR" ] || ! compgen -G "$SRC_DIR/templates/*/statusline.sh" >/dev/null 2>&1; then
  SRC_DIR=""   # not a checkout — fall back to downloading
fi

download() {  # url dest
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$1" -o "$2" 2>/dev/null
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$2" "$1"
  else
    die "need curl or wget to download templates"
  fi
}

template_names() {
  if [ -n "$SRC_DIR" ]; then
    local d
    for d in "$SRC_DIR"/templates/*/; do
      [ -f "$d/statusline.sh" ] || continue
      basename "$d"
    done
  else
    printf '%s\n' "$TEMPLATE_META" | cut -d'|' -f1
  fi
}

describe() {  # name
  local line
  line=$(printf '%s\n' "$TEMPLATE_META" | grep -m1 "^$1|" || true)
  if [ -n "$line" ]; then printf '%s' "${line#*|}"; else printf '%s' "(no description)"; fi
}

fetch_template() {  # name dest
  if [ -n "$SRC_DIR" ]; then
    [ -f "$SRC_DIR/templates/$1/statusline.sh" ] || die "no such template: $1"
    cp "$SRC_DIR/templates/$1/statusline.sh" "$2"
  else
    download "$REPO_RAW/templates/$1/statusline.sh" "$2" \
      || die "could not fetch template '$1' from $REPO_SLUG — check the name (--list) and your connection"
  fi
}

# ---- actions -----------------------------------------------------------

list_templates() {
  info "${C_BOLD}Available templates${C_OFF}"
  info ""
  local n
  while read -r n; do
    [ -n "$n" ] || continue
    printf '  %s%-20s%s %s\n' "$C_CYAN" "$n" "$C_OFF" "$(describe "$n")"
  done <<EOF
$(template_names)
EOF
  info ""
}

MENU_STTY=''

menu_restore() {
  [ -n "$MENU_STTY" ] && stty "$MENU_STTY" <&3 2>/dev/null
  printf '\033[?25h' >&3 2>/dev/null
  exec 3>&-
  MENU_STTY=''
}

# Arrow-key picker. Sets PICKED. Returns 1 when the terminal can't do raw
# mode, so the caller falls back to typing a number.
pick_arrows() {  # name...
  local names=("$@") count=$# sel=0 key rest i cols namew descw drawn=0 desc

  command -v stty >/dev/null 2>&1 || return 1
  command -v tput >/dev/null 2>&1 || return 1
  [ -n "${TERM:-}" ] && [ "$TERM" != dumb ] || return 1

  # No `2>/dev/null` on this exec: with only redirections it applies them to
  # the shell itself, which would silence stderr for the rest of the run.
  exec 3<>/dev/tty || return 1
  MENU_STTY=$(stty -g <&3 2>/dev/null) || { exec 3>&-; return 1; }
  # min 1 time 0: block until a key, no line buffering, no echo.
  stty -echo -icanon min 1 time 0 <&3 2>/dev/null || { menu_restore; return 1; }
  trap 'menu_restore; exit 130' INT TERM

  cols=$(tput cols 2>/dev/null) || cols=80
  [ "$cols" -ge 40 ] 2>/dev/null || cols=80
  namew=0
  for i in "${names[@]}"; do [ ${#i} -gt "$namew" ] && namew=${#i}; done
  descw=$(( cols - namew - 6 ))
  [ "$descw" -ge 10 ] || descw=10

  printf '\033[?25l' >&3
  printf '\n%sPick a template%s  %s↑/↓ move · enter install · q quit%s\n\n' \
    "$C_BOLD" "$C_OFF" "$C_DIM" "$C_OFF" >&3

  while :; do
    # Redraw in place: jump back over the rows printed last pass.
    [ "$drawn" -eq 1 ] && printf '\033[%dA' "$count" >&3
    for ((i = 0; i < count; i++)); do
      # Truncate so no row wraps — a wrapped row would desync the cursor math.
      desc=$(describe "${names[$i]}")
      desc=${desc:0:$descw}
      if [ "$i" -eq "$sel" ]; then
        printf '\033[K %s❯ %-*s%s  %s%s%s\n' \
          "$C_CYAN$C_BOLD" "$namew" "${names[$i]}" "$C_OFF" "$C_DIM" "$desc" "$C_OFF"
      else
        printf '\033[K   %-*s  %s%s%s\n' "$namew" "${names[$i]}" "$C_DIM" "$desc" "$C_OFF"
      fi
    done >&3
    drawn=1

    IFS= read -rsn1 key <&3 || break
    # Arrows arrive as ESC [ A / ESC [ B — pull the two bytes that follow.
    if [ "$key" = $'\e' ]; then
      IFS= read -rsn2 -t 1 rest <&3 2>/dev/null || rest=''
      key="$key$rest"
    fi
    case "$key" in
      $'\e[A'|k|K) sel=$(( (sel - 1 + count) % count )) ;;
      $'\e[B'|j|J) sel=$(( (sel + 1) % count )) ;;
      '')          break ;;                       # enter
      q|Q|$'\e')   menu_restore; trap - INT TERM; die "cancelled" ;;
      [1-9])       if [ "$key" -le "$count" ]; then sel=$(( key - 1 )); break; fi ;;
    esac
  done

  menu_restore
  trap - INT TERM
  PICKED="${names[$sel]}"
}

# Fallback for terminals without raw mode: type a number.
pick_numeric() {  # name...
  local names=("$@") i choice

  printf '%sAvailable templates%s\n\n' "$C_BOLD" "$C_OFF" >&2
  for i in "${!names[@]}"; do
    printf '  %s%2d)%s %s%-20s%s %s\n' \
      "$C_BOLD" "$((i + 1))" "$C_OFF" "$C_CYAN" "${names[$i]}" "$C_OFF" "$(describe "${names[$i]}")" >&2
  done
  printf '\n' >&2

  while :; do
    printf 'Select a template [1-%d], or q to quit: ' "${#names[@]}" >&2
    read -r choice < /dev/tty || die "no input"
    case "$choice" in
      q|Q|'') die "cancelled" ;;
      *[!0-9]*) printf '%s\n' "Enter a number." >&2 ;;
      *)
        if [ "$choice" -ge 1 ] && [ "$choice" -le "${#names[@]}" ]; then
          PICKED="${names[$((choice - 1))]}"
          return 0
        fi
        printf '%s\n' "Out of range." >&2
        ;;
    esac
  done
}

# Sets PICKED to the chosen template name.
pick_template() {
  # -r /dev/tty can pass on a device that still won't open, so probe it for
  # real — in a subshell, so the fd doesn't leak into this shell.
  ( exec 3<>/dev/tty ) 2>/dev/null \
    || die "no template given and no terminal to ask on (pass a name, or --list)"

  local names=() n
  while read -r n; do [ -n "$n" ] && names+=("$n"); done <<EOF
$(template_names)
EOF
  [ ${#names[@]} -gt 0 ] || die "no templates found"

  pick_arrows "${names[@]}" || pick_numeric "${names[@]}"
}

preview_template() {  # script-path
  local cache out
  cache=$(mktemp -d 2>/dev/null) || return 0
  # Point the cache at a throwaway dir so a preview never writes real state.
  out=$(printf '%s' "$SAMPLE_JSON" | XDG_CACHE_HOME="$cache" "$1" 2>/dev/null || true)
  rm -rf "$cache"

  [ -n "$out" ] || { warn "template produced no output on the sample payload"; return 0; }
  printf '\n%sPreview (sample data)%s\n\n' "$C_DIM" "$C_OFF"
  printf '%s\n\n' "$out"
}

confirm() {  # prompt
  [ "$ASSUME_YES" -eq 1 ] && return 0
  [ -r /dev/tty ] || return 0
  local reply
  printf '%s [Y/n] ' "$1" >&2
  read -r reply < /dev/tty || return 1
  case "$reply" in n|N|no|NO) return 1 ;; *) return 0 ;; esac
}

# Path as written into settings.json — tilde form when it lives under $HOME.
settings_path_for() {
  case "$1" in
    "$HOME"/*) printf '~%s' "${1#$HOME}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

update_settings() {  # command-string
  if ! command -v jq >/dev/null 2>&1; then
    warn "jq not found — settings.json not updated."
    info ""
    info "Add this to $SETTINGS yourself:"
    info ""
    info '  {'
    info '    "statusLine": {'
    info '      "type": "command",'
    info "      \"command\": \"$1\""
    info '    }'
    info '  }'
    info ""
    return 1
  fi

  mkdir -p "$(dirname "$SETTINGS")"
  [ -f "$SETTINGS" ] || printf '{}\n' > "$SETTINGS"
  jq -e . "$SETTINGS" >/dev/null 2>&1 || die "$SETTINGS is not valid JSON — fix it and re-run"

  local tmp
  tmp=$(mktemp)
  jq --arg cmd "$1" '.statusLine.type = "command" | .statusLine.command = $cmd' \
    "$SETTINGS" > "$tmp" && mv -f "$tmp" "$SETTINGS"
  info "  ${C_GREEN}updated${C_OFF} $SETTINGS"
}

# ---- main --------------------------------------------------------------

[ "$DO_LIST" -eq 1 ] && { list_templates; exit 0; }

command -v jq >/dev/null 2>&1 \
  || warn "jq is not installed. Every template needs it to parse Claude Code's stdin JSON. (brew install jq / apt install jq)"

if [ -z "$TEMPLATE" ]; then
  pick_template          # runs in this shell so the tty restore isn't racy
  TEMPLATE="$PICKED"
fi

step "Installing template ${C_BOLD}$TEMPLATE${C_OFF}"

staged=$(mktemp)
trap 'rm -f "$staged"' EXIT
fetch_template "$TEMPLATE" "$staged"
chmod +x "$staged"

preview_template "$staged"
confirm "Install to $TARGET?" || die "cancelled"

mkdir -p "$(dirname "$TARGET")"
cp "$staged" "$TARGET"
chmod +x "$TARGET"
info "  ${C_GREEN}installed${C_OFF} $TARGET"

if [ "$SKIP_SETTINGS" -eq 1 ]; then
  info "  ${C_DIM}skipped settings.json (--no-settings)${C_OFF}"
  info ""
  info "${C_YELLOW}Script installed.${C_OFF} Point statusLine.command at it to use it."
elif update_settings "$(settings_path_for "$TARGET")"; then
  info ""
  info "${C_GREEN}Done.${C_OFF} Restart Claude Code to see the new status line."
else
  info "${C_YELLOW}Script installed, settings not changed.${C_OFF} See the note above."
fi
