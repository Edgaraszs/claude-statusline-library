#!/bin/bash
# Status line: current dir, git branch, model, rate_limits (5h, 7d)

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')

# %1~ : last path component, with ~ shown for the home directory
if [ "$cwd" = "$HOME" ]; then
  dir="~"
else
  dir=$(basename "$cwd")
fi

# Current git branch, if any (skip optional locks for speed/safety)
git_branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [ -n "$branch" ] && git_branch="$branch"
fi

# ---- rate limits, with cache fallback ----------------------------------
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/claude-statusline"
cache_file="$cache_dir/limits"

# usage percentage
h5=$(echo  "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
d7=$(echo  "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

stale=''
if [ -n "$h5" ] || [ -n "$d7" ]; then
  mkdir -p "$cache_dir"
  printf '%s %s\n' "${h5:-0}" "${d7:-0}" > "$cache_file.tmp" 2>/dev/null \
    && mv -f "$cache_file.tmp" "$cache_file" 2>/dev/null
elif [ -r "$cache_file" ]; then
  read -r h5 d7 < "$cache_file"
  stale='~'
fi

h5=${h5:-0}
d7=${d7:-0}

# green under 70, yellow under 90, red above
pct_color() {
  local p=${1%.*}
  if   [ "$p" -ge 90 ]; then printf '\033[31m'
  elif [ "$p" -ge 70 ]; then printf '\033[33m'
  else                      printf '\033[32m'
  fi
}

bar() {
  local p=${1%.*} w=12 i filled out=''
  filled=$(( p * w / 100 ))
  [ "$filled" -gt "$w" ] && filled=$w
  for ((i = 0; i < w; i++)); do
    [ "$i" -lt "$filled" ] && out+='█' || out+='░'
  done
  printf '%s' "$out"
}

row() {  # label, value, icon
  printf '  %s \033[2m%-9s\033[0m %s%s\033[0m \033[1m%3.0f%%\033[0m\n' \
    "$3" "$1" "$(pct_color "$2")" "$(bar "$2")" "$2"
}

sep() { printf '  \033[2m%s\033[0m\n' '────────────────────────────────'; }

printf '\033[36m %s\033[0m' "$dir"
[ -n "$git_branch" ] && printf '\033[33m %s\033[0m' "$git_branch"
printf ' %s' "$model"
printf '\n'

sep
row "5h limit" "$h5" ""
sep
row "7d limit" "$d7" ""
sep

exit 0
