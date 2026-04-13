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

This creates `.tandem/`, launcher scripts, project docs, and installs the tandem skill.

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

## Updating

Refresh scripts and check for template changes:

```bash
bash path/to/fagents-tandem/setup.sh --update
```

Scripts in `.tandem/bin/` are always refreshed. For docs (TEAM.md, CLAUDE.md, AGENTS.md), the diff is shown and you're asked to apply or skip per file. Skipped updates are saved to `.tandem/updates/` for later manual merge. Your customizations are never overwritten without confirmation.

## What it's not

- Not a messaging system or inbox
- Not a multi-task scheduler
- Not a daemon — agents run their own CLI sessions
- Not limited to Claude + Codex — works with any two CLI agents
