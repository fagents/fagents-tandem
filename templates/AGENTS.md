# Project

<!-- Add your Codex-specific instructions here. See PROJECT.md for shared project context. -->

## Tandem

This project uses paired agent coordination via `.tandem/`.
You are the Codex CLI side. A Claude Code agent works in the same project.

Start via `./launch-codex` for automatic TTY registration. Then check state:

```bash
bash .tandem/bin/handoff.sh status
```

If you started without the launcher, register manually: `bash .tandem/bin/handoff.sh register codex`

If you own the current phase, pick up where you left off. If not, wait for a handoff.

### State machine

```
COORDINATE -> PLAN -> REVIEW_PLAN -> IMPLEMENT -> REVIEW_CODE -> SIMPLIFY -> QUALITY_REVIEW -> COMMIT
```

### Commands

```bash
bash .tandem/bin/handoff.sh next --to <agent> --summary "..."
bash .tandem/bin/handoff.sh accept --to <agent> --summary "..."
bash .tandem/bin/handoff.sh request-changes --summary "..."
bash .tandem/bin/handoff.sh status
bash .tandem/bin/handoff.sh done

# Quick message (no state change)
bash .tandem/bin/handoff.sh msg --from codex claude "pushed the fix"
```

### Handoff files

- `.tandem/handoff/plan.md` -- plan draft
- `.tandem/handoff/review.md` -- review findings
- `.tandem/handoff/impl-notes.md` -- implementation notes

### Rules

1. Don't touch work you don't own.
2. Write handoff files before transitioning.
3. One transition per handoff -- don't skip phases.

See TEAM.md for the full protocol and code quality standards.
