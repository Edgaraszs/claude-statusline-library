#!/bin/bash
# Status line converted from ~/.zshrc PROMPT:
#   PROMPT='%F{yellow}%n%f %1~ %F{green}${vcs_info_msg_0_}%f %# '

input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

username=$(whoami)

# %1~ : last path component, with ~ shown for the home directory
if [ "$cwd" = "$HOME" ]; then
  dir="~"
else
  dir=$(basename "$cwd")
fi

# vcs_info "(%b)" : current git branch, if any
git_branch=""
if git -C "$cwd" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks branch --show-current 2>/dev/null)
  [ -n "$branch" ] && git_branch="($branch)"
fi

printf "\033[33m%s\033[0m %s" "$username" "$dir"
[ -n "$git_branch" ] && printf " \033[32m%s\033[0m" "$git_branch"
exit 0
