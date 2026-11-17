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
| `exclamationmark.triangle.fill` | a reply failed (API error) and you haven't seen it yet |
| `hand.raised.fill` | Claude asks permission to use a tool |
| `questionmark.bubble.fill` | Claude asked you a question |
| `exclamationmark.bubble.fill` | Claude is waiting for you (no known reason, or mixed reasons) |

When several things happen at once, the most urgent one wins:
**permission > waiting > question > failed (unseen) > ready (unseen) > working > idle**.
"question" only shows when every waiting session is a question; a permission
wins because it blocks a tool that is already running.

> Portuguese version: [README.pt-BR.md](README.pt-BR.md). The app's menu and
> popups are in Portuguese.

## Requirements

- macOS 14 (Sonoma) or later
- Swift 6 toolchain (Xcode 16+) to build
- [Claude Code](https://docs.claude.com/claude-code) 2.1.139 or later installed
  (`claude` CLI; hooks use exec form, `args`). The failed state needs a Claude
  Code version with the `StopFailure` hook; versions without it keep the
  failed session as *working*

## Features

### The menu

Clicking the menu bar icon shows your usage limits at the top, then lists every
session, newest first, with background subagents grouped at the end:

```
Limite 5 h: 23% · renova 14:30          (5-hour limit, reset time)
Semanal: 41% · renova sex., 09:00       (weekly limit, reset time)
Atualizado há 3 min                     (age of the data)
──────────────
[checkmark.circle.fill]             my-app — pronto (há 2 min)
[ellipsis.circle]                   ClaudeBar · feat/x — processando (há 10 s)
[exclamationmark.triangle.fill]     api — falhou (há 1 min)
[hand.raised.fill]                  infra — pede permissão (há 20 s)
[questionmark.bubble.fill]          docs — fez uma pergunta (há 5 s)
[exclamationmark.bubble.fill]       [subagente] review-pr — aguardando você (há 1 min)
──────────────
Marcar tudo como visto        (mark all as seen)
──────────────
O que os ícones significam  ▸ (legend: every bar symbol and what it means)
──────────────
Notificações  ✓               (notifications on/off)
Ver exemplo de popup          (show a sample popup)
Ajustes…                 ⌘,   (settings)
──────────────
Integração com o Claude Code: ok  ▸  (hooks: status, install, remove)
Atualizar                     (refresh now)
Sair do ClaudeBar        ⌘Q   (quit)
```

The limit lines come from `~/.claude/claudebar/limits.json`, written by
`claudebar-hook statusline` (see [Command line](#command-line)).
Without data they read *indisponível* (unavailable), never 0%. A window that
already reset reads *renovado, aguardando dado novo* (reset, waiting for new
data) until the next Claude Code reply brings a fresh number. The age is not
a live clock: it is computed when the menu is built and does not tick while
the menu stays open.

Each session row opens a submenu with:

- the full project path,
- **Open project folder**: opens the `cwd` in Finder (only real folders; an
  `.app` is never launched),
- **Go to session** (*Ir para a sessão*): brings the terminal or app that hosts
  the session to the front (see [Going to a session](#going-to-a-session)); not
  shown for background subagents,
- for a failed reply, the API error code and details
  (e.g. `rate_limit — 429 Too Many Requests`),
- **Mark as seen** — clears the "ready" or "failed" highlight in the bar for
  that session (a failed row keeps the warning symbol until the next prompt),
- **Terminate** — when possible (see [Terminating a session](#terminating-a-session)).

Each row shows, at its left, the same SF Symbol the menu bar uses for that
state, and says the state in words (no emoji). The submenu **O que os ícones
significam** (*what the icons mean*) lists every bar symbol with its meaning.

- **VoiceOver** — the menu bar item reads e.g. "ClaudeBar. Sessões: 2. Claude
  está esperando você" (*Sessions: 2. Claude is waiting for you*); popups are
  announced (when VoiceOver allows announcements from background apps).

The app has no Dock icon and no window; it lives only in the menu bar
(`LSUIElement`).

### Claude Code integration

The **Integração** submenu shows whether the hooks are in place and lets you
manage them without the terminal. Its title is the status: `ok`, `hooks não
instalados` (not installed) or `⚠︎ precisa de atenção` (needs attention); the
first line inside says what is wrong.

- **Instalar hooks… / Reinstalar hooks…** — registers ClaudeBar's hooks and
  copies the hook executable to `~/.claude/claudebar/bin/`. Also how you
  repair missing, outdated or legacy entries.
- **Remover hooks…** — removes only ClaudeBar's entries and the copied
  executable.
- **Copiar JSON dos hooks** — shown instead of install when `settings.json`
  is read-only (generated by dotfiles, Nix…): copies the executable and puts
  the `hooks` JSON on the clipboard for you to paste into the tool that
  generates the file.
- **Testar integração** — an end-to-end check, then the sample popup. It
  answers "why doesn't the icon change?" with a ✓/✗ for each of: hooks
  registered in `settings.json`; hook executable present; executable equal to
  the one in this app; and the hook **actually ran and wrote** its state file
  (the app runs it the way Claude Code would, with a test session that is
  removed right after; a stuck hook is killed after 3 s, so the app never
  freezes). It also shows when the last real event arrived and warns about
  `disableAllHooks`. What the app can't see from here: `disableAllHooks` in a
  project's settings and `allowManagedHooksOnly` in managed settings — check
  `/hooks` inside Claude Code. And Claude Code holds hooks back until you
  accept the folder's trust dialog: with sessions open and no event received,
  the test says so.
- **Atualizar** also re-checks the integration.

Nothing is written without an alert first. It shows the real file (symlinks
resolved), the exact diff of the `hooks` block — never the rest of the file,
which may hold tokens in `env` —, where the backup goes, and whether the file
will be reformatted. Only the **Instalar** / **Remover** button writes. If
`settings.json` changes while the alert is open (Claude Code writes to it
too), you get a fresh preview instead of a blind write.

On first launch, and whenever the integration needs repair, the same alert
shows up on its own **once**, with **Pular** (skip) instead of cancel. Skipping
writes nothing and the app doesn't ask again until the state changes; the
submenu stays there. After you update the `.app`, the copied executable is
older than the bundled one, so the app offers to update it the same way.

With an invalid `settings.json` or `disableAllHooks: true`, the app only
reports it and offers no install.

### Alerts

Each alert has its own sound: one is informative, the waiting ones block
you, and one tells you the reply never came:

| Transition | Alert | Sound | Volume |
|---|---|---|---|
| working → ready | "Claude terminou" (*Claude is done*) + project name | `Glass` (bright bell, default) | 100% |
| → permission | "Claude pede permissão" (*Claude asks permission*) + Claude's message | `Submarine` (low pulse, default) | 75% |
| → question | "Claude fez uma pergunta" (*Claude asked a question*) + Claude's message, or project name | `Purr` (soft purr, default) | 75% |
| → waiting for you (no known reason) | "Claude está esperando você" (*Claude is waiting for you*) + Claude's message | `Submarine` (low pulse, default) | 75% |
| working → failed | "A resposta do Claude falhou" (*Claude's reply failed*) + project and error code | `Basso` (error thud, default) | 100% |

- Sounds are played with `NSSound`, not by the notification itself — it is the
  only way to pick a different sound and volume per alert. You can tell which
  alert fired without looking at the screen.
- The message shown for "waiting" is what Claude Code sends to the
  `Notification` hook (e.g. *"Claude needs your permission to use Bash"*),
  capped at 200 characters. Claude Code sends the permission prompt after a
  few seconds without typing, so "waiting" can take a moment to show up.
- A question shows up at once (`PreToolUse` on `AskUserQuestion`). Claude Code
  then sends a permission prompt for the same screen a few seconds later; it
  is ignored while the question is open, so the session stays on "question".
  If the reason changes while the session waits, the alert fires again.
- The "failed" alert only fires when the session was working right before the
  error, and does not repeat while it stays in error.
- **Reminder.** A session still waiting for you after about 5 minutes gets one
  more alert ("Ainda esperando: …", same sound). Answering cancels it; a new
  wait gets a new reminder. Turn it off or change the delay in **Ajustes…**.
- **Ajustes… → Nunca mostrar o conteúdo da mensagem** (off by default) replaces
  Claude's message with "<project> precisa de você" in the waiting alerts and
  the reminder — useful when sharing your screen. macOS no longer honours "hide
  this window from screen capture", so the only real protection is not drawing
  the text. The message is still stored in the state file (`0600`); this mode
  only changes what is shown. The "failed" alert and the error submenu keep
  showing the API error code (e.g. `rate_limit — 429`): it is not conversation
  content.
- Subagents never trigger alerts.
- No sound if the session's app is already in front (the popup still shows).
  App level only: with the Claude desktop app in front, any of its
  conversations counts; inside tmux the sound always plays.
- The **Notificações** toggle in the menu turns alerts on and off — popup and
  sound together. The choice is saved in `UserDefaults` and is on by default.
- **Ajustes… (⌘,)** opens a settings window: turn each alert on or off
  (finished, waiting for you — permission and question included — and failed),
  turn the sound off while keeping the popup, and pick each alert's sound from
  the macOS system sounds (it plays when you pick it). Permission and "waiting"
  share one sound. The menu toggle **Notificações** stays the master switch.
  The window also has **Abrir ao iniciar sessão no Mac** (start at login, off
  by default) and **Sobre o ClaudeBar** (the standard About panel).

#### Why the app draws its own popup

macOS Notification Center rejects ad-hoc signed apps:

```
requestAuthorization falhou: Notifications are not allowed for this application
status de autorização: 1 (denied)
```

This is not a permission you denied. The system refuses the API for any bundle
without a Developer ID (`TeamIdentifier=not set`), and `lsregister` does not
change that. So the alert is shown in the app's own floating `NSPanel`, in a
corner of the screen where the mouse is, away from the cursor (top-right
unless the cursor is there). It needs no signing and no permission.

"Claude terminou" and "A resposta do Claude falhou" disappear after 4 seconds
or on click. The three waiting alerts ("Claude está esperando você", "Claude
pede permissão", "Claude fez uma pergunta") stay until you click the popup or
that session stops waiting (you answered, it finished, or it was closed).
Clicking the popup takes you to the session (same as **Ir para a sessão**);
the sample popup only closes. A "terminou" or "falhou" never covers a waiting
popup that is still open: you only hear its sound. With two sessions waiting,
the popup shows the latest one; the menu bar icon keeps flagging the other.

If the app is ever signed with a Developer ID, `Notifier` switches to native
notifications by itself: it prefers them and only falls back to its own panel
when authorization is missing. The same fallback is used when running without
a bundle (`swift run`).

To debug (in zsh `log` is a builtin, so use the full path):

```bash
/usr/bin/log show --last 5m --info --debug --predicate 'subsystem == "com.joaomarcos.claudebar"'
```

To count how often the CLI is queried (one line per `claude agents --json`):

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.joaomarcos.claudebar" AND category == "agents"'
```

### Going to a session

**Ir para a sessão** walks up the process tree from the session's `claude`
process to the first regular app (terminal, editor, Claude desktop app) and
brings it to the front. It also marks the session as seen.

- **tmux:** inside tmux the tree ends at the tmux server, so ClaudeBar finds
  the pane by the session's TTY, switches the most recently used attached
  client to that pane and brings that client's terminal to the front. Only the
  default socket is supported, and a terminal must be attached.
- **It brings the window, not the tab.** Picking the exact tab would need
  Automation permission.
- **No permission needed:** only `sysctl`, `NSRunningApplication` and
  `NSWorkspace`.
- If the app can't be found, an alert says so; nothing else is opened.

| Host | Status |
|---|---|
| Claude desktop app | process tree resolves to the app (verified); activation not verified. Brings the app, not the conversation |
| Terminal.app | not verified |
| Ghostty | not verified |
| iTerm2 | not verified |
| VS Code | not verified |
| Cursor | not verified |
| Warp | not verified |
| tmux (default socket) | not verified |

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
  (on hook events, on process exit and        │
   every 60 s; ≤ 1 call / 2 s)                │
                                              ├──> ClaudeBar.app ──> 🔸 3
Claude Code ──(hooks)──> claudebar-hook ──────┘
                            │       what state each one is in
                            └─writes─> ~/.claude/claudebar/<session_id>.json
                                       (DispatchSource: reacts in ms)
```

- **`claude agents --json`** lists every open session, including ones that never
  fired a hook. It sets the **number** in the bar. It is queried (off the main
  thread, ~150 ms per call) when a hook writes, when a session process exits
  and every 60 seconds — at most once every 2 seconds. Process exit is observed
  by the system (`DispatchSource`), so a dead session disappears right away,
  without waiting for the next query.
- **Hooks** fire the moment the state changes. They set the **symbol**. But they
  only know about sessions that have already fired an event.

The two are joined by `sessionId`: the CLI decides which sessions exist, the
hook decides their state. If the CLI can't be reached, the app falls back to
what the hooks wrote instead of emptying the list. If a session is only known
to the CLI, its status (`idle` / `waiting` / `blocked`, or none = working) is
used instead.

| Hook | State written |
|---|---|
| `SessionStart` (`startup`, `resume`, `clear`) | `idle` (a new session shows up before its first prompt) |
| `UserPromptSubmit` | `working` |
| `Stop` | `idle` |
| `StopFailure` | `error` (the turn ended on an API error) |
| `PreToolUse` (`AskUserQuestion`) | `waiting --kind question` |
| `Notification` (`permission_prompt`) | `waiting --kind permission` (skipped while a question is open) |
| `Notification` (`elicitation_dialog`) | `waiting --kind question` |
| `PostToolUse`, `PostToolUseFailure` | `working`, only if the session was `waiting` (a permission was just approved) |
| `SessionEnd` | deletes the file |

Other notification types (idle reminder, auth, quota…) are not registered: the
idle reminder used to turn "ready" into "waiting" about a minute after every
reply.

A state file looks like this:

```json
{
  "branch" : "main",
  "cwd" : "/Users/me/code/my-project",
  "kind" : "permission",
  "message" : "Claude needs your permission to use Bash",
  "pid" : 23667,
  "sessionId" : "1f6c…",
  "state" : "waiting",
  "updatedAt" : 1791400000
}
```

`branch` is read by the hook straight from `.git/HEAD` (following the `gitdir:`
of a worktree), without running `git`. A detached HEAD shows as `@sha7`; a
reftable repository, or a folder outside git, shows no branch. It is refreshed
on every hook, so a `git checkout` done outside Claude shows up one turn late.
It appears in the menu next to the name, to tell apart two sessions of the same
project in different worktrees.

Two design choices that avoid classic problems:

- **The hook lives at `~/.claude/claudebar/bin/claudebar-hook`**, a copy of
  the one inside the bundle. `settings.json` points there, so moving or
  deleting the `.app` doesn't break the hooks.
- **One file per session.** Many sessions writing to the same file would race;
  splitting by `session_id` removes the problem. Writes are also atomic, so the
  app never reads half a JSON file.
- **The PID is stored with the state.** A session that dies from `kill` or a
  crash never fires `SessionEnd` and would leave a file saying "working"
  forever. The app deletes the file when the process is gone, when the PID now
  belongs to another program, or when it belongs to another `claude` that
  started after the file was written. Without that proof (no information), the
  file stays. A session with `pid 0` is only hidden from the list once the CLI
  answers without it.

The `claude` binary is looked up in known locations (`~/.local/bin`,
`/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`) and, as a last resort, with
`zsh -lc "command -v claude"`: a menu bar app does not inherit your shell's
`PATH`.

## Project structure

```
Package.swift                 SwiftPM, macOS 14, 3 targets + tests
Sources/ClaudeBarCore/        shared model + reading/writing the state directory
  GitHead.swift               branch read from .git/HEAD (by the hook, never runs git)
  HookInstaller.swift         adds/removes only ClaudeBar's hooks in settings.json (diff, backup)
  RateLimits.swift            5-hour/weekly usage limits from the status line JSON
  SessionNavigator.swift      process tree → app, tmux pane, activation
  SessionStatus.swift         session state (working/idle/waiting/error), PID
  Shell.swift                 runs processes without a shell (no injection)
  StatusDirectory.swift       ~/.claude/claudebar: permissions, atomic writes, cleanup
  StatusLineChain.swift       runs your previous status line (stdin/stdout, 5 s timeout)
  StatusLineInstall.swift     swaps and restores statusLine in settings.json (opt-in)
Sources/claudebar-hook/       CLI called by the hooks (no jq/python needed)
  main.swift                  reads the hook JSON from stdin, writes/deletes the state file
Sources/ClaudeBar/            SwiftUI app (MenuBarExtra)
  ClaudeBarApp.swift          entry point, menu bar label (symbol + count)
  MenuContent.swift           the menu
  HookSetup.swift             integration status, the diff alert, install/remove on click
  SessionStore.swift          wires both sources to the rules, detects transitions
  SessionMerge.swift          the merge rules as pure functions (what the tests cover)
  SessionRow.swift            one menu row: the merged view of both sources
  AgentsProbe.swift           runs `claude agents --json` and maps its status
  DirectoryWatcher.swift      DispatchSource watcher on the state directory
  ProcessExitWatcher.swift    DispatchSource watcher on session process exit
  SessionTerminator.swift     picks the target (SIGTERM or `claude stop`) and runs it
  ProcessProbe.swift          process topology: group leader? still claude?
  Notifier.swift              sound per alert, toggle, native vs. own popup
  StatusHUD.swift             the app's own popup (floating NSPanel)
  SettingsWindow.swift        settings window (NSWindow, not the Settings scene)
Tests/ClaudeBarTests/         subagents, count, icon, precedence, real kills, no network
Resources/AppIcon.icns        app icon, copied into the bundle by build-app.sh
scripts/build-app.sh          builds build/ClaudeBar.app (LSUIElement, ad-hoc signed)
scripts/install.sh            installs to ~/Applications and registers the hooks
scripts/uninstall.sh          removes the hooks (only ours) and the app
scripts/make-dmg.sh           universal DMG + SHA-256 in dist/ (publishes nothing)
VERSION                       app version (X.Y.Z), read by build-app.sh
```

## Installation

### From a DMG

1. Build it with `./scripts/make-dmg.sh` (full Xcode, not just the Command
   Line Tools). It writes `dist/ClaudeBar-<version>.dmg` (arm64 + x86_64)
   and the `.sha256` next to it. Check it with
   `cd dist && shasum -c ClaudeBar-<version>.dmg.sha256`.
2. Open the DMG and **drag ClaudeBar into Applications before opening it**.
   Opened straight from the DMG, macOS runs the app from a random read-only
   path (App Translocation).
3. The app is ad-hoc signed, not notarized, so macOS blocks the first launch.
   Go to System Settings → Privacy & Security → "Open Anyway". Do not turn
   Gatekeeper off.
4. When it opens, the app offers to register the hooks and shows the diff
   first (see [Claude Code integration](#claude-code-integration)). From the
   terminal instead:
   `/Applications/ClaudeBar.app/Contents/MacOS/claudebar-hook install`.

### From source

```bash
./scripts/install.sh
```

This script:

1. builds the app in release mode (`scripts/build-app.sh`),
2. copies it to `~/Applications/ClaudeBar.app`,
3. shows the diff of the `hooks` block in `~/.claude/settings.json` and asks
   before applying it (`claudebar-hook install`),
4. opens the app.

Things to know:

- Only ClaudeBar's entries change. Hooks of yours on the same events stay,
  even in the same group. Running it again says there is nothing to change.
- Before every write, the old file is backed up (`0600`) to
  `~/.claude/claudebar/backups/`. If `settings.json` doesn't exist, it is
  created.
- The file is reformatted (key order, spacing); outside `"hooks"` the content
  doesn't change.
- Claude Code reloads `settings.json`, so open sessions pick the hooks up
  (folders must be trusted).

To start at login: **Ajustes… → Abrir ao iniciar sessão no Mac** (off by
default). If macOS asks for approval, the window links to System Settings →
Login Items. After rebuilding the app, turn it on again.

### Moving or updating the app

The hooks don't point into the `.app`: they run a copy at
`~/.claude/claudebar/bin/claudebar-hook`. Moving, renaming or deleting
`ClaudeBar.app` doesn't break them. After you update the app, the copy is
older than the one in the bundle; the app detects that (and missing, legacy
or outdated entries, a read-only `settings.json`, `disableAllHooks`) without
writing anything, and offers the fix once (see
[Claude Code integration](#claude-code-integration)).

## Development

```bash
swift build                  # build
swift test                   # merge rules, count, icon, alerts, termination
./scripts/build-app.sh       # build the .app bundle

# change the state of a real session (the first one the CLI lists with a pid)
s=$(claude agents --json | jq -c '[.[] | select(.pid)][0]')
echo "$s" | jq -c '{session_id: .sessionId, cwd}' | \
  build/ClaudeBar.app/Contents/MacOS/claudebar-hook waiting --kind permission --pid "$(echo "$s" | jq .pid)"
```

A fake PID does not work: the app deletes a file whose PID is not a running
`claude` (PID 1 is `launchd`).

The version lives in `VERSION` (X.Y.Z). The build number is the commit count
(`git rev-list --count HEAD`); shallow clones restart the count.

`UNIVERSAL=1 ./scripts/build-app.sh` builds arm64 + x86_64 (without it, only
this Mac's architecture). `./scripts/make-dmg.sh` uses it and writes `dist/`.
The SHA changes on every build: the DMG is not reproducible.

Hook CLI usage:

```
claudebar-hook <working|idle|waiting|error|end> [--kind <permission|question>] [--if-waiting] [--pid <claude pid>]
claudebar-hook install|uninstall [--statusline] [--dry-run]
claudebar-hook status [--json]
claudebar-hook next
claudebar-hook statusline
```

It reads the hook payload (`session_id`, `cwd`, `message`; with `error`,
`error` and `error_details` instead of `message`) from stdin. Without
a `session_id` it writes nothing and exits 0. If it
fails to write, it only logs to stderr and exits cleanly — a hook must never
break the Claude session. Without `--pid` (exec form has no `$PPID`) it uses
its parent process, but only if that is a `claude` executable; otherwise it
writes `pid: 0`. `--kind` is kept only with `waiting`; an unknown value is
dropped (generic wait). `--if-waiting` writes only if the session's file
currently says `waiting`; otherwise (or with no file) it exits 0 without
touching it. A missing or invalid state exits with **1**, never 2: in Claude
Code, exit 2 blocks the prompt.

`install`/`uninstall` print the diff of the `hooks` block and apply it with a
backup; `--dry-run` only prints. `install` also copies itself to
`~/.claude/claudebar/bin/claudebar-hook`; `uninstall` deletes that copy
(unless the status line below is still installed).

`install --statusline` / `uninstall --statusline` touch only `statusLine`, never
the hooks, and are off by default (in the app: *Mostrar limites no rodapé do
Claude Code…* / *Parar de mostrar limites no rodapé…* in the integration
submenu, with the same diff and backup). Installing saves your current
`statusLine` object to `~/.claude/claudebar/statusline-original.json`
(`0600`), besides the timestamped `settings.json` backup, and points
`statusLine.command` at the stable hook, keeping `padding`, `refreshInterval`
and the rest. Installing twice never overwrites that file. Uninstalling puts
the original back as it was (or removes the key if you had none) and deletes
the file; if you changed `statusLine` yourself after installing, it is left
alone. With no previous status line, Claude Code hides some footer hints (like
`esc to interrupt`) and shows `5h 23% · sem 41%` instead. To undo by hand: copy
the content of `~/.claude/claudebar/statusline-original.json` back into
`statusLine` in `~/.claude/settings.json`, or delete the key if the file does
not exist.

`statusline` is meant to be Claude Code's `statusLine` command (installed by
`install --statusline`, or set by hand). From the JSON Claude Code sends on stdin it
keeps only `rate_limits` (5-hour and weekly windows) in
`~/.claude/claudebar/limits.json` (`0600`), and rewrites it only when a number
changed or the saved data is a minute old. Then it runs your previous status
line, saved in `~/.claude/claudebar/statusline-original.json`, with
`/bin/sh -c`, passing stdin, stdout and the exit code through, with a 5 s
timeout. With no previous status line (or if it fails to run or times out) it
prints a short summary such as `5h 23% · sem 41%` and exits 0. Limitations:
only Pro, Max and Ultra subscribers get `rate_limits`, and only after a
session's first reply; with two accounts in different terminals, the last
session that updated wins.

### Command line

`status` and `next` are for you to type (or script); they do not read stdin and
change nothing in your sessions.

```bash
alias cb=~/.claude/claudebar/bin/claudebar-hook

cb status          # one session per line: state<TAB>project<TAB>folder
cb status --json   # same data, in the format of the state files
cb next            # brings forward the session that has waited longest
```

`next` prints the project name and exits 0; with no session waiting (or when
it cannot find the app that hosts it) it prints why and exits 1. Inside tmux it
switches the client to the session's pane, like "go to session" in the menu.

In the tmux status bar, the number of sessions waiting for you:

```
set -g status-right '#(~/.claude/claudebar/bin/claudebar-hook status | grep -c ^waiting)'
```

`status` only sees sessions that have already fired a hook: it reads the state
files and does not call `claude agents`. Like the app, it deletes a state file
that is invalid or whose process no longer exists.

`swift run ClaudeBar` works too. Without a bundle there are no native
notifications, so the app uses its own popup and sound.

The termination tests include real processes: they spawn children, check
process-group detection, send `SIGTERM`, and make sure killing one session
does not take down a sibling.

## Security

- **No secrets in the project.** The app makes no network calls (see
  [Verify it yourself](#verify-it-yourself)), does not authenticate anywhere,
  and does not read conversation history — only project paths, `sessionId`,
  session state, the git branch and the hook's notification message.
- **The only file read inside your project is `.git/HEAD`** (or the `.git`
  gitfile of a worktree), by the hook, never by the app, and `git` is never
  run.
- **`~/.claude/claudebar` is `0700`, files are `0600`.** The contents show which
  projects you work on, so other users on the machine can't read them.
- **`sessionId` is sanitized** before it becomes a file name: only
  `[A-Za-z0-9-_]` is kept, everything else becomes `-`. A malicious
  `session_id` with `../` can't escape the directory.
- **No command goes through a shell.** `claude` and `tmux` are run via
  `Process` from a known path with separate arguments — no interpolation, so no
  injection. The only exception is
  `zsh -lc "command -v claude"`, used only as a last resort when the binary
  isn't in a known location. `claudebar-hook statusline` runs your previous
  status line with `/bin/sh -c`, but that command is text you wrote in your own
  settings and is passed as a single argument; ClaudeBar adds nothing to it.
- **Optional "never show content" mode** — see [Alerts](#alerts).
- **`message` is capped at 200 characters** before it is shown. For failures
  only the API error code/details are stored, never Claude's reply
  (`last_assistant_message` is not read in any state). For questions only
  the fact that Claude asked is stored, never the question text (`tool_input`
  is not read).
- **Status line: only `rate_limits` is read.** `transcript_path` and every
  other field of the status line JSON are ignored; no network call, no token,
  no Keychain.
- **Paths are never logged in the clear.** Any log line with a path, `cwd`,
  `sessionId` or hook message uses `privacy: .private(mask: .hash)`; never
  `.public`.
- **Hooks run without a shell.** They are registered in exec form
  (`command` + `args`), and the installer needs no `jq`: it is the hook binary
  itself, in Swift. `settings.json` backups are `0600`.

### Verify it yourself

ClaudeBar opens no network connections. A test (`NoNetworkTests`) fails
`swift test` if networking code is ever added to `Sources/`. To check the
running app:

    lsof -i -a -c ClaudeBar                     # prints nothing
    nettop -p ClaudeBar -L 0 -t external -n     # only the CSV header line; Ctrl-C to stop

With Little Snitch: open Network Monitor and search for "ClaudeBar". It should
never show a connection.

Note: ClaudeBar runs `claude agents --json` (and `claude stop` when you
terminate a subagent), plus local `tmux` commands when you go to a session
inside tmux. Any traffic from the `claude` commands shows up under
`claude`, not ClaudeBar: it belongs to Claude Code and follows its settings
(https://code.claude.com/docs/en/data-usage#telemetry-services).

## Uninstall

```bash
./scripts/uninstall.sh
```

It removes only ClaudeBar's hooks and status line from `settings.json` (with a
backup; your previous status line comes back), quits
the app and deletes `~/Applications/ClaudeBar.app`. Without the repository:
`~/.claude/claudebar/bin/claudebar-hook uninstall`. State and backups stay in
`~/.claude/claudebar`; delete that folder by hand if you want.
