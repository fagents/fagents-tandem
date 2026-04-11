# fagents-tandem

Paired agent coordination. Two AI coding agents (Claude Code + Codex CLI) share a project and take turns: one plans, the other reviews, one implements, the other reviews code. File-based state machine with TIOCSTI terminal wake.

No server, no daemon, no dependencies beyond bash, jq, and python3.

## Setup

```bash
git clone https://github.com/fagents/fagents-tandem.git
cd your-project
bash path/to/fagents-tandem/setup.sh
```

Register your agents' terminals:
```bash
echo /dev/ttys002 > .tandem/kai.tty
echo /dev/ttys003 > .tandem/rivet.tty
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
bash .tandem/bin/handoff.sh next --to rivet --summary "plan ready"
bash .tandem/bin/handoff.sh accept --to kai --summary "plan approved"
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
sudo bash .tandem/bin/wake.sh rivet "[kai]: check .tandem/handoff/review.md"
```

## Migration from .agents/

If you have an existing `.agents/` tandem setup:
```bash
bash path/to/fagents-tandem/setup.sh --migrate
```

## What it's not

- Not a messaging system or inbox
- Not a multi-task scheduler
- Not a daemon — agents run their own CLI sessions
- Not limited to Claude + Codex — works with any two CLI agents
