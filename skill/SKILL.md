---
name: tandem
description: Multi-agent handoff protocol for paired development
allowed-tools: Bash(bash .tandem/bin/*)
---
# Tandem — Paired Agent Protocol

**This skill applies only when the current project contains a `.tandem/` directory.**
If `.tandem/` does not exist, ignore these instructions.

## Starting a Feature

When the user asks to start a feature, build something, or requests new work, **immediately run**:

```bash
bash .tandem/bin/feature "description from the user"
```

Do NOT just print the command or describe the protocol. Run it.

Options: `--to claude` or `--to codex` to assign, `--task slug` for a custom name.

## Sending Messages

For quick notes, questions, or heads-ups that don't need a handoff:

```bash
bash .tandem/bin/handoff.sh msg --from claude codex "check fagents-cli/whatsapp.mjs line 42"
bash .tandem/bin/handoff.sh msg --from codex claude "pushed the fix, pull and verify"
```

Use `msg` for lightweight communication. Use `next`/`accept`/`request-changes` for structured phase transitions.

## At Session Start

If started via `./launch-claude` or `./launch-codex`, your TTY is already registered. Check state:

```bash
bash .tandem/bin/handoff.sh status
```

If started without the launcher, register manually (do NOT use `tty` directly -- it fails in sandboxed shells):
```bash
bash .tandem/bin/handoff.sh register claude   # if you are Claude Code
bash .tandem/bin/handoff.sh register codex    # if you are Codex CLI
```

If you own the current phase, pick up where you left off. If not, wait for a handoff.

## State Machine

```
COORDINATE → PLAN → REVIEW_PLAN → IMPLEMENT → REVIEW_CODE → SIMPLIFY → QUALITY_REVIEW → COMMIT
```

Reviews iterate: REVIEW_PLAN → PLAN, REVIEW_CODE → IMPLEMENT, QUALITY_REVIEW → SIMPLIFY.

| Phase | Owner | Work |
|-------|-------|------|
| COORDINATE | either | Discuss scope |
| PLAN | planner | Draft `.tandem/handoff/plan.md` |
| REVIEW_PLAN | reviewer | Review plan, write `.tandem/handoff/review.md` |
| IMPLEMENT | implementer | Write code |
| REVIEW_CODE | reviewer | Review code, write `.tandem/handoff/review.md` |
| SIMPLIFY | implementer | /simplify, shellcheck, linter, tests, bug hunt |
| QUALITY_REVIEW | reviewer | Independent quality pass, missed tests |
| COMMIT | implementer | Commit + push |

## Commands

```bash
# Forward (advance phase)
bash .tandem/bin/handoff.sh next --to <agent> --summary "..."
bash .tandem/bin/handoff.sh accept --to <agent> --summary "..."

# Backward (iterate review)
bash .tandem/bin/handoff.sh request-changes --summary "..."

# Other
bash .tandem/bin/handoff.sh status
bash .tandem/bin/handoff.sh take --as <agent> --summary "..."
bash .tandem/bin/handoff.sh done
```

## Handoff Files

Write these before transitioning:
- `.tandem/handoff/plan.md` — plan draft
- `.tandem/handoff/review.md` — review findings (Current Findings + Review Log)
- `.tandem/handoff/impl-notes.md` — what changed, what to look at

## Rules

1. Don't touch work you don't own.
2. Write handoff files before transitioning.
3. One transition per handoff — don't skip phases.
4. Human can override `.tandem/handoff/state.json` directly.
