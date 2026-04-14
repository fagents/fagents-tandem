# Workspace Team Protocol

Two agents share this workspace. Human lead coordinates.

## Handoff Protocol

Features are built in phases. One agent owns each phase; the other reviews or waits. State is tracked in `.tandem/handoff/state.json`.

### Phases

```
COORDINATE -> PLAN -> REVIEW_PLAN -> IMPLEMENT -> REVIEW_CODE -> SIMPLIFY -> QUALITY_REVIEW -> COMMIT
               |________________|          |_________________|        |_____________________|
                 request-changes             request-changes             request-changes
```

| Phase | Owner | Work |
|-------|-------|------|
| COORDINATE | either | Discuss scope |
| PLAN | planner | Draft `.tandem/handoff/plan.md` |
| REVIEW_PLAN | reviewer | Review plan, write `.tandem/handoff/review.md` |
| IMPLEMENT | implementer | Write code |
| REVIEW_CODE | reviewer | Review code, write `.tandem/handoff/review.md` |
| SIMPLIFY | implementer | Run your tool (Claude: `/simplify`, Codex: manual cleanup). Both: shellcheck, linter, tests, bug hunt, DRY. Fix what you find. |
| QUALITY_REVIEW | reviewer | Run your tool (Codex: `/review` or `codex review --uncommitted`, Claude: independent review). Both: missed tests, safe DRY-ups, readability. Write findings to review.md. If issues found, request-changes back to SIMPLIFY for fixes. |
| COMMIT | implementer | Ask human, then commit + push |

### Handoff Rules

Each agent has a partner. By default, hand review phases (REVIEW_PLAN, REVIEW_CODE, QUALITY_REVIEW) to your partner, and work phases (PLAN, IMPLEMENT, SIMPLIFY, COMMIT) stay with you. The human can override this at any time.

After handing off, STOP. Do not continue working. Wait for the other agent or the human to hand back to you.

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

# One-off messages (no state change)
bash $H msg --from claude codex "quick note"
bash $H msg --from codex claude "heads up"
```

Or start a feature:
```bash
.tandem/bin/feature "description of what to build"
```

### Before Committing

At the COMMIT phase, always ask the human before running git commit. Wait for confirmation. The human may want to review changes in Zed or another tool first.

### Rules

1. Check state at session start. If you're the owner, pick up where you left off.
2. Don't touch work you don't own.
3. Write handoff files before transitioning.
4. One transition per handoff -- don't skip phases.
5. Human can override state.json directly.

### Wake

Transitions poke the other agent's terminal via TIOCSTI. Messages are prefixed with sender:
```
[kai]: REVIEW_CODE r2. Run: bash .tandem/bin/handoff.sh status. Read: .tandem/handoff/impl-notes.md
```

### TTY Registration

Start agents via the launcher scripts for automatic registration:

```bash
./launch-claude    # registers .tandem/claude.tty, then starts claude
./launch-codex     # registers .tandem/codex.tty, then starts codex
```

Manual fallback: `bash .tandem/bin/handoff.sh register claude` (or codex)

## Code Quality

Both agents follow the same quality bar. These apply to all phases, not just SIMPLIFY/QUALITY_REVIEW.

### Testing

- New features and bug fixes include tests in the same commit.
- Run the relevant test scope for the change before declaring done.
- If the full suite was not run, state what was skipped and why.
- If tests can't be written, state why explicitly.

### No Magic Numbers

- Named constants over inline literals.
- Thresholds, ports, sizes, intervals, retry counts -- all named and documented.

### DRY

- Don't duplicate logic -- extract shared helpers when the same pattern appears twice.
- But don't over-abstract: three similar lines beats a premature abstraction.
- When reviewing, flag near-duplicate blocks.

### Reusability

- Search for existing utilities and abstractions before writing new code.
- Reuse what fits, but don't force code into the wrong abstraction.
- Avoid unrelated scope creep -- small refactors that improve correctness or maintainability are fine.
- New files are fine when they improve module boundaries.

### No Bugs

- Test the golden path AND edge cases.
- Handle errors at system boundaries (user input, external APIs), trust internal code.
- Validate assumptions with data, not guesses.

### Readability

- Code should be self-documenting -- comments explain WHY, not WHAT.
- No unnecessary comments, no commented-out code.
- Keep functions short and focused.

### Security

- Never commit secrets, tokens, .env contents.
- Validate untrusted input.
- Keep trust boundaries explicit.

### Commit Discipline

- Commit messages: focus on WHY, not WHAT.
- One logical change per commit.
- Push clean -- don't leave uncommitted or unpushed work.
