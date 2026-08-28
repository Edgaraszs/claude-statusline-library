# Claude Code Statusline Library

A public, community-driven collection of status line templates for [Claude Code](https://claude.com/claude-code).

Grab one, drop it in your config, done. Or contribute your own.

## What is a status line?

Claude Code can render a custom status line at the bottom of the terminal. It runs a command you specify, feeds it session JSON on stdin, and prints the first line of stdout.

## Usage

1. Pick a template from [`templates/`](templates/).
2. Copy its script somewhere stable, e.g. `~/.claude/statusline.sh`:

   ```bash
   cp templates/user-dir-branch/statusline.sh ~/.claude/statusline.sh
   chmod +x ~/.claude/statusline.sh
   ```

3. Point your `~/.claude/settings.json` at it:

   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.claude/statusline.sh"
     }
   }
   ```

4. Restart Claude Code.

Tip: `/statusline` inside Claude Code can also set this up for you.

## Templates

| Template | Description |
| --- | --- |
| [`user-dir-branch`](templates/user-dir-branch/) | Username, current directory (`~` for home), and git branch — a zsh-style prompt. |

## Input format

Your script receives a JSON object on stdin. Useful fields:

```json
{
  "session_id": "abc123",
  "model": { "id": "claude-opus-4", "display_name": "Opus" },
  "workspace": { "current_dir": "/path/to/cwd", "project_dir": "/path/to/project" },
  "output_style": { "name": "default" },
  "version": "1.0.0"
}
```

Parse it with `jq`:

```bash
input=$(cat)
cwd=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
```

ANSI color codes work. Only the first line of output is displayed.

## Contributing

New templates welcome.

1. Create `templates/<your-template-name>/`.
2. Add `statusline.sh` (or a script in any language — just make it executable and self-contained).
3. Add a short `README.md` in the folder: what it shows, a screenshot or sample output, and any dependencies.
4. Add a row to the table above.
5. Open a pull request.

### Guidelines

- Keep it fast. The status line runs often; avoid slow network calls.
- Declare dependencies (`jq`, `git`, nerd fonts, etc.).
- Fail quietly. Never let a missing tool break the status line — guard with `2>/dev/null` and fallbacks.
- Use `git -C "$cwd" --no-optional-locks` so you don't fight the user's git index.
- Exit `0`.

## License

MIT
