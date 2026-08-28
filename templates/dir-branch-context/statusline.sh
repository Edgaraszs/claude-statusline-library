#!/bin/bash
# Status line: current dir, git branch, context usage percentage

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

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

# Context window usage percentage
used=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

printf "\033[36m%s\033[0m" "$dir"
[ -n "$git_branch" ] && printf " \033[33m(%s)\033[0m" "$git_branch"
[ -n "$used" ] && printf " \033[35m%.0f%% context\033[0m" "$used"
exit 0
