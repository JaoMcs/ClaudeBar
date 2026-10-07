# ClaudeBar

A native macOS menu bar app that tells you when Claude Code is done working —
across every open session at once.

```
🔸 2      ← two sessions open, one of them needs your attention
```

The number shows how many Claude Code sessions are open. The symbol next to it
shows what is happening in them:

| Symbol (SF Symbol) | Meaning |
|---|---|
| `circle.dotted` | nothing going on |
| `ellipsis.circle` | Claude is working |
| `checkmark.circle.fill` | a reply is ready and you haven't seen it yet |
| `exclamationmark.bubble.fill` | Claude is waiting for you (permission, a choice) |

When several things happen at once, the most urgent one wins:
**waiting > ready (unseen) > working > idle**.

> Portuguese version: [README.pt-BR.md](README.pt-BR.md). The app's menu and
> popups are in Portuguese.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build
- [Claude Code](https://docs.claude.com/claude-code) installed (`claude` CLI)
- `jq`, only for the install script (`brew install jq`)

## Features

### The menu

Clicking the menu bar icon lists every session, newest first, with background
subagents grouped at the end:

```
✅  my-app — pronto (há 2 min)
⏳  ClaudeBar — processando (há 10 s)
🔸  [subagente] review-pr — aguardando você (há 1 min)
──────────────
Marcar tudo como visto        (mark all as seen)
──────────────
Notificações  ✓               (notifications on/off)
Ver exemplo de popup          (show a sample popup)
──────────────
Atualizar                     (refresh now)
Sair do ClaudeBar        ⌘Q   (quit)
```

Each session row opens a submenu with:

- the full project path,
- **Mark as seen** — clears the green "ready" state for that session,
- **Terminate** — when possible (see [Terminating a session](#terminating-a-session)).

The app has no Dock icon and no window; it lives only in the menu bar
(`LSUIElement`).

### Alerts

There are two alerts, each with its own sound, because one is informative and
the other blocks you:

| Transition | Alert | Sound | Volume |
|---|---|---|---|
| working → ready | "Claude terminou" (*Claude is done*) + project name | `Glass` (bright bell) | 100% |
| → waiting for you | "Claude está esperando você" (*Claude is waiting for you*) + Claude's message | `Submarine` (low pulse) | 75% |

- Sounds are played with `NSSound`, not by the notification itself — it is the
  only way to pick a different sound and volume per alert. You can tell which
  alert fired without looking at the screen.
- The message shown for "waiting" is what Claude Code sends to the
  `Notification` hook (e.g. *"Claude needs your permission to use Bash"*),
  capped at 200 characters.
- Subagents never trigger alerts.
- The **Notificações** toggle in the menu turns the popup on and off. The choice
  is saved in `UserDefaults` and is on by default. Note: in the current code the
  sound still plays when the toggle is off (`Notifier.post` plays the sound
  before checking the toggle).

#### Why the app draws its own popup

macOS Notification Center rejects ad-hoc signed apps:

```
requestAuthorization falhou: Notifications are not allowed for this application
status de autorização: 1 (denied)
```

This is not a permission you denied. The system refuses the API for any bundle
without a Developer ID (`TeamIdentifier=not set`), and `lsregister` does not
change that. So the alert is shown in the app's own floating `NSPanel`, in the
top-right corner of the screen where the mouse is. It disappears after 4
seconds or on click, and needs no signing and no permission.

If the app is ever signed with a Developer ID, `Notifier` switches to native
notifications by itself: it prefers them and only falls back to its own panel
when authorization is missing. The same fallback is used when running without
a bundle (`swift run`).

To debug (in zsh `log` is a builtin, so use the full path):

```bash
/usr/bin/log show --last 5m --info --debug --predicate 'subsystem == "com.joaomarcos.claudebar"'
```

### Terminating a session

The right way to stop a session depends on what kind of session it is, so the
app picks the target per row:

| Situation | Action | Effect |
|---|---|---|
| Background subagent | `claude stop <id>` | Official shutdown, can be resumed with `claude attach <id>` |
| Terminal session (`pgid == pid`) | `SIGTERM` to the process | Conversation is saved (resume with `claude --resume`), but whatever was running stops right away and the terminal is left at an empty shell |
| **Claude desktop app session** | none — the menu explains why | Close it from the desktop app |
| Recycled or missing PID | none | — |

Every termination asks for confirmation first, describing exactly what will
happen. The menu reorders itself as sessions change state, so one wrong click
could otherwise kill the wrong session.

#### Why desktop app sessions can't be terminated from here

A desktop session does not lead its own process group. It runs inside the
`Claude.app` group, together with the app and its sibling sessions:

```
pessoal-55 (terminal)   pid=23667  pgid=23667   <- own group
code-26    (desktop)    pid=35282  pgid=16958   <- Claude.app group (15 processes)
```

Signalling it that way took down more than one session at once. The app now
uses `pgid == pid` to tell them apart and does not offer the option for hosted
sessions — it shows the reason instead of the button.

More guards in the same code path:

- **`SIGTERM`, not `SIGKILL`**: Claude Code can still close the transcript and
  run its exit hook.
- **PIDs get recycled.** Before sending a signal, the app checks with
  `proc_pidpath` that the PID still belongs to a Claude process, so stale state
  can never kill an unrelated process that inherited the number.
- **`pid: 0`** (what the hook writes when it gets no `--pid`) is treated as
  missing: signalling `0` would hit the whole process group.

### Subagents

An agent dispatched in the background shows up in the menu tagged
`[subagente]`, but it does **not** count toward the number in the bar, does
**not** change the icon, and does **not** play a sound — it is work you
delegated, not your own session waiting for a reply. It is terminated with
`claude stop`.

In-process subagents (the Task tool) do not show up at all: they run inside the
process of the session that created them, and `claude agents --json` only
lists `kind: "interactive"` and `kind: "background"` entries.

## How it works

Two sources, each good at what the other is bad at:

```
                        which sessions exist
claude agents --json ─────────────────────────┐
  (polled every 5 s, ~150 ms per call)        │
                                              ├──> ClaudeBar.app ──> 🔸 3
Claude Code ──(hooks)──> claudebar-hook ──────┘
                            │       what state each one is in
                            └─writes─> ~/.claude/claudebar/<session_id>.json
                                       (DispatchSource: reacts in ms)
```

- **`claude agents --json`** lists every open session, including ones that never
  fired a hook. It sets the **number** in the bar. It is only polled every 5
  seconds (off the main thread), so it is too slow to react to state changes.
- **Hooks** fire the moment the state changes. They set the **symbol**. But they
  only know about sessions that have already fired an event.

The two are joined by `sessionId`: the CLI decides which sessions exist, the
hook decides their state. If the CLI can't be reached, the app falls back to
what the hooks wrote instead of emptying the list. If a session is only known
to the CLI, its status (`idle` / `waiting` / `blocked`, or none = working) is
used instead.

| Hook | State written |
|---|---|
| `UserPromptSubmit` | `working` |
| `Stop` | `idle` |
| `Notification` | `waiting` |
| `SessionEnd` | deletes the file |

A state file looks like this:

```json
{
  "cwd" : "/Users/me/code/my-project",
  "message" : "Claude needs your permission to use Bash",
  "pid" : 23667,
  "sessionId" : "1f6c…",
  "state" : "waiting",
  "updatedAt" : 1791400000
}
```

Two design choices that avoid classic problems:

- **One file per session.** Many sessions writing to the same file would race;
  splitting by `session_id` removes the problem. Writes are also atomic, so the
  app never reads half a JSON file.
- **The PID is stored with the state.** A session that dies from `kill` or a
  crash never fires `SessionEnd` and would leave a file saying "working"
  forever. The app checks `kill(pid, 0)` and deletes orphaned files.

The `claude` binary is looked up in known locations (`~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) and, as a last resort, with
`zsh -lc "command -v claude"`: a menu bar app does not inherit your shell's
`PATH`.

## Project structure

```
Package.swift                 SwiftPM, macOS 14, 3 targets + tests
Sources/ClaudeBarCore/        shared model + reading/writing the state directory
  SessionStatus.swift         session state (working/idle/waiting), PID liveness
  StatusDirectory.swift       ~/.claude/claudebar: permissions, atomic writes, cleanup
Sources/claudebar-hook/       CLI called by the hooks (no jq/python needed)
  main.swift                  reads the hook JSON from stdin, writes/deletes the state file
Sources/ClaudeBar/            SwiftUI app (MenuBarExtra)
  ClaudeBarApp.swift          entry point, menu bar label (symbol + count)
  MenuContent.swift           the menu
  SessionStore.swift          wires both sources to the rules, detects transitions
  SessionMerge.swift          the merge rules as pure functions (what the tests cover)
  SessionRow.swift            one menu row: the merged view of both sources
  AgentsProbe.swift           runs `claude agents --json` and maps its status
  DirectoryWatcher.swift      DispatchSource watcher on the state directory
  SessionTerminator.swift     picks the target (SIGTERM or `claude stop`) and runs it
  ProcessProbe.swift          process topology: group leader? still claude?
  Notifier.swift              sound per alert, toggle, native vs. own popup
  StatusHUD.swift             the app's own popup (floating NSPanel)
  Shell.swift                 runs processes without a shell (no injection)
Tests/ClaudeBarTests/         subagents, count, icon, precedence and real kills
scripts/build-app.sh          builds build/ClaudeBar.app (LSUIElement, ad-hoc signed)
scripts/install.sh            installs to ~/Applications and registers the hooks
```

## Installation

```bash
./scripts/install.sh
```

This script:

1. builds the app in release mode (`scripts/build-app.sh`),
2. copies it to `~/Applications/ClaudeBar.app`,
3. backs up `~/.claude/settings.json` to `settings.json.bak.<timestamp>`,
4. registers the four hooks, passing `--pid $PPID` so the app knows which
   Claude process fired each one,
5. opens the app.

Things to know:

- `~/.claude/settings.json` must already exist.
- The rest of `settings.json` is kept, but any hooks you already had for
  `UserPromptSubmit`, `Stop`, `Notification` or `SessionEnd` are **replaced**.
  Merge them back from the backup if needed.
- Hooks only apply to **new** Claude Code sessions.

To start at login: System Settings → General → Login Items → add
`~/Applications/ClaudeBar.app`.

## Development

```bash
swift build                  # build
swift test                   # merge rules, count, icon, alerts, termination
./scripts/build-app.sh       # build the .app bundle

# simulate a session without Claude
echo '{"session_id":"test","cwd":"/tmp"}' | \
  build/ClaudeBar.app/Contents/MacOS/claudebar-hook working --pid 1
```

Hook CLI usage:

```
claudebar-hook <working|idle|waiting|end> [--pid <claude pid>]
```

It reads the hook payload (`session_id`, `cwd`, `message`) from stdin. If it
fails to write, it only logs to stderr and exits cleanly — a hook must never
break the Claude session.

`swift run ClaudeBar` works too. Without a bundle there are no native
notifications, so the app uses its own popup and sound.

The termination tests include real processes: they spawn children, check
process-group detection, send `SIGTERM`, and make sure killing one session
does not take down a sibling.

## Security

- **No secrets in the project.** The app makes no network calls, does not
  authenticate anywhere, and does not read conversation history — only project
  paths, `sessionId`, session state and the hook's notification message.
- **`~/.claude/claudebar` is `0700`, files are `0600`.** The contents show which
  projects you work on, so other users on the machine can't read them.
- **`sessionId` is sanitized** before it becomes a file name: only
  `[A-Za-z0-9-_]` is kept, everything else becomes `-`. A malicious
  `session_id` with `../` can't escape the directory.
- **No command goes through a shell.** `claude` is run via `Process` with
  separate arguments — no interpolation, so no injection. The only exception is
  `zsh -lc "command -v claude"`, used only as a last resort when the binary
  isn't in a known location.
- **`message` is capped at 200 characters** before it is shown.

## Uninstall

```bash
pkill -f ClaudeBar.app
rm -rf ~/Applications/ClaudeBar.app ~/.claude/claudebar
# then remove the four claudebar-hook entries from "hooks" in ~/.claude/settings.json
```
