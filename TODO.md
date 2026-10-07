# TODO

## Support other coding agents

The app only reads `~/.claude/claudebar/*.json`, written by `claudebar-hook`.
Any agent that can run a command on lifecycle events can feed it.

- [ ] Add optional `agent` field to `SessionStatus` (optional so old status files still decode)
- [ ] `claudebar-hook --agent <claude|gemini|codex>`
- [ ] Show the agent per row in the menu (label or icon)
- [ ] **Gemini CLI**: map hooks `BeforeAgent` → working, `AfterAgent` → idle, `Notification` → waiting, `SessionEnd` → end
- [ ] **Codex CLI**: `notify` in `~/.codex/config.toml` (JSON comes as argv, not stdin; only "turn done"). Check whether its newer hooks cover working/waiting
- [ ] `install.sh`: register Gemini/Codex hooks only if those CLIs are installed
- [ ] Verify current event names and payload fields in each tool's docs before building
- [ ] Antigravity: IDE, no known hook system. Revisit if one appears

Stays Claude-only for now: `AgentsProbe` (`claude agents --json`) and
`SessionTerminator` (refuses non-`claude` processes, safe default).

## Housekeeping

- [ ] `install.sh` replaces existing hooks for UserPromptSubmit/Stop/Notification/SessionEnd instead of appending. Merge instead
- [ ] Maybe rename app / move status dir out of `~/.claude` once multi-agent lands
