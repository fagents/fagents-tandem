# fagents-tandem

Not a replacement for [fagents](https://github.com/fagents/fagents) -- an experiment.

fagents gives your agents a team. fagents-tandem gives two of them a shared workbench.

Two AI coding agents share a project and take turns: one plans, the other reviews, one implements, the other reviews code. File-based state machine with terminal wake. No server, no daemon, no dependencies beyond bash, jq, and python3.

## Setup

```bash
git clone https://github.com/fagents/fagents-tandem.git
cd your-project
bash path/to/fagents-tandem/setup.sh
```

This creates `.tandem/`, launcher scripts, project docs, and installs the tandem skill. Optionally installs [Zed](https://zed.dev) for human code review.

Start your agents:

```bash
./launch-claude    # terminal 1
./launch-codex     # terminal 2
```

Each launcher registers the agent's TTY and starts the CLI. No manual setup needed.

## Usage

Start a feature:
```bash
.tandem/bin/feature "add user authentication"
```

Check status:
```bash
bash .tandem/bin/handoff.sh status
```

Hand off:
```bash
bash .tandem/bin/handoff.sh next --to codex --summary "plan ready"
bash .tandem/bin/handoff.sh accept --to claude --summary "plan approved"
bash .tandem/bin/handoff.sh request-changes --summary "see review.md"
bash .tandem/bin/handoff.sh done

# Quick message (no state change)
bash .tandem/bin/handoff.sh msg --from claude codex "check this file"
```

## How it works

Every feature follows this cycle:

```
COORDINATE → PLAN → REVIEW_PLAN → IMPLEMENT → REVIEW_CODE → SIMPLIFY → QUALITY_REVIEW → COMMIT
```

One agent owns each phase. Reviews can iterate (REVIEW_PLAN → PLAN, REVIEW_CODE → IMPLEMENT, QUALITY_REVIEW → SIMPLIFY). A revision counter tracks rounds.

Handoff files in `.tandem/handoff/`:
- `state.json` — who owns what phase
- `plan.md` — feature plan
- `review.md` — review findings
- `impl-notes.md` — implementation notes
- `events.jsonl` — transition history

When you hand off, the other agent gets a message injected into their terminal via TIOCSTI (requires sudo). If wake fails, state.json is still the source of truth.

## Wake

TIOCSTI injects keystrokes into another terminal session. Works on macOS Sequoia and Linux (Ubuntu 24.04+). Requires sudo.

```bash
# Manual wake
sudo bash .tandem/bin/wake.sh codex "[claude]: check .tandem/handoff/review.md"
```

`wake.sh` exit codes: `0` delivered, `1` usage, `2` no TTY registered, `3` sudo / TIOCSTI failure. Callers that want best-effort tolerance (`handoff.sh` transitions, `feature`) suffix `|| true`. The watchdog uses the exit code to distinguish wake-sent from wake-failed.

## Watchdog

A liveness nudge for long-running auto-chain projects. Polls `state.json` and pokes the current state owner via `wake.sh` when idle past a threshold. Read-only on tandem state, never mutates `state.json` or `events.jsonl`. Distinguishes wake-sent from wake-failed via `wake.sh` exit codes, and emits a loud operator-visible `dead-tty` alert when the owner's registered TTY is missing, empty, not a character device, not writable, or not interactive (e.g. `/dev/null` would otherwise pass naive char-device checks).

```bash
# Run alongside the agents in a separate tmux/screen pane:
bash .tandem/bin/watchdog.sh "$PWD"

# Or one-shot under cron / systemd-timer:
bash .tandem/bin/watchdog.sh --once "$PWD"
```

Tunables (env vars):
- `WATCHDOG_THRESHOLD_SECONDS` (default 1800): owner-idle threshold before first poke
- `WATCHDOG_INTERVAL_SECONDS` (default 300): daemon-mode poll interval
- `WATCHDOG_BACKOFF_FACTOR` (default 2): multiplier for repeated-poke backoff
- `WATCHDOG_MAX_BACKOFF_SECONDS` (default 7200): cap on backoff window
- `WATCHDOG_VERBOSE=1`: log owner-active happy-path events
- `WATCHDOG_ONCE=1`: same as `--once`

Audit log lives at `.tandem/watchdog.log` (JSONL). Event kinds: `wake-sent`, `wake-failed`, `dead-tty`, `rate-limited`, `no-active-task`, `owner-active` (verbose only).

## Updating

Refresh scripts and check for template changes:

```bash
bash path/to/fagents-tandem/setup.sh --update
```

Scripts in `.tandem/bin/` are always refreshed. For docs (TEAM.md, CLAUDE.md, AGENTS.md), the diff is shown and you're asked to apply or skip per file. Skipped updates are saved to `.tandem/updates/` for later manual merge. Your customizations are never overwritten without confirmation.

## What it's not

- Not a messaging system or inbox
- Not a multi-task scheduler
- Not a process supervisor -- the watchdog nudges idle owners but does not restart, kill, or supervise the agent CLIs
- Not limited to Claude + Codex — works with any two CLI agents
