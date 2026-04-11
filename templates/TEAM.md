# Workspace Team Protocol

Two agents share this workspace. Human lead coordinates.

## Handoff Protocol

Features are built in phases. One agent owns each phase; the other reviews or waits. State is tracked in `.tandem/handoff/state.json`.

### Phases

```
COORDINATE → PLAN → REVIEW_PLAN → IMPLEMENT → REVIEW_CODE → SIMPLIFY → QUALITY_REVIEW → COMMIT
                ↑_______________↓         ↑________________↓       ↑____________________↓
                  request-changes           request-changes            request-changes
```

| Phase | Owner | Work |
|-------|-------|------|
| COORDINATE | either | Discuss scope |
| PLAN | planner | Draft `.tandem/handoff/plan.md` |
| REVIEW_PLAN | reviewer | Review plan, write `.tandem/handoff/review.md` |
| IMPLEMENT | implementer | Write code |
| REVIEW_CODE | reviewer | Review code, write `.tandem/handoff/review.md` |
| SIMPLIFY | implementer | /simplify, shellcheck, linter, tests, bug hunt, drying |
| QUALITY_REVIEW | reviewer | Independent quality pass, missed tests, safe dryups |
| COMMIT | implementer | Commit + push |

### Commands

```bash
H=.tandem/bin/handoff.sh

bash $H status
bash $H init --task <slug> --repo <repo> --owner <agent> --summary "..."
bash $H next --to <agent> --summary "..."
bash $H accept --to <agent> --summary "..."
bash $H request-changes --summary "..."
bash $H take --as <agent> --summary "..."
bash $H done
```

Or start a feature:
```bash
.tandem/bin/feature "description of what to build"
```

### Rules

1. Check state at session start. If you're the owner, pick up where you left off.
2. Don't touch work you don't own.
3. Write handoff files before transitioning.
4. One transition per handoff — don't skip phases.
5. Human can override state.json directly.

### Wake

Transitions poke the other agent's terminal via TIOCSTI. Messages are prefixed with sender:
```
[kai]: REVIEW_CODE r2. Run: bash .tandem/bin/handoff.sh status. Read: .tandem/handoff/impl-notes.md
```

### TTY Registration

Each agent registers their own TTY at session start (the tandem skill instructs them to do this):

```bash
tty > .tandem/claude.tty    # Claude Code registers itself
tty > .tandem/codex.tty     # Codex CLI registers itself
```

Or manually from another terminal:
```bash
# Find TTYs: look for claude/codex in process list
ps -eo tty,pid,comm | grep -E 'claude|codex'
echo /dev/ttys002 > .tandem/claude.tty
echo /dev/ttys003 > .tandem/codex.tty
```
