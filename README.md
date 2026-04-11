# fagents-tandem

Not a replacement for [fagents](https://github.com/fagents/fagents) -- an experiment.

fagents gives your agents a team. fagents-tandem gives two of them a shared workbench.

Two AI coding agents (Claude Code + Codex CLI) share a project and take turns: one plans, the other reviews, one implements, the other reviews code. File-based state machine with TIOCSTI terminal wake. No server, no daemon, no dependencies beyond bash, jq, and python3.

Token cost is real -- two agents means two billing streams. If that bothers you, use one agent. If it doesn't, find out what happens when they review each other's work.

## Setup

```bash
git clone https://github.com/fagents/fagents-tandem.git
cd your-project
bash path/to/fagents-tandem/setup.sh
```

Start Claude and Codex in separate terminals, then each agent registers (from project root):

```bash
bash .tandem/bin/handoff.sh register claude    # in the Claude terminal
bash .tandem/bin/handoff.sh register codex     # in the Codex terminal
```

Or manually:
```bash
ps -eo tty,pid,comm | grep -E 'claude|codex'
echo /dev/ttys002 > .tandem/claude.tty
echo /dev/ttys003 > .tandem/codex.tty
```

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

## What it's not

- Not a messaging system or inbox
- Not a multi-task scheduler
- Not a daemon — agents run their own CLI sessions
- Not limited to Claude + Codex — works with any two CLI agents
