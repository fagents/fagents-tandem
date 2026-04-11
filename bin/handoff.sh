#!/bin/bash
# Handoff protocol — state transitions + TIOCSTI wake.
#
# Usage:
#   handoff.sh init --task <name> --repo <repo> --owner <agent> --summary "kickoff"
#   handoff.sh next --to <agent> --summary "what's ready"
#   handoff.sh accept --to <agent> --summary "approved, proceed"
#   handoff.sh back --summary "needs changes, see review.md"
#   handoff.sh request-changes --summary "findings in review.md"
#   handoff.sh take --as <agent> --summary "claiming this"
#   handoff.sh status
#   handoff.sh done
#
# State lives in ROOT/.tandem/handoff/state.json (runtime, gitignored).
# Transition history appends to ROOT/.tandem/handoff/events.jsonl.
# Wake uses TIOCSTI (requires sudo for the poke only).

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HANDOFF_DIR="$ROOT/.tandem/handoff"
STATE_FILE="$HANDOFF_DIR/state.json"
EVENTS_FILE="$HANDOFF_DIR/events.jsonl"
AGENTS_DIR="$ROOT/.tandem"

mkdir -p "$HANDOFF_DIR"

# ── Helpers ──

die() { echo "ERROR: $1" >&2; exit 1; }

read_state() {
    [ -f "$STATE_FILE" ] || die "No active task. Use: handoff.sh init --task <name> --repo <repo> --owner <agent>"
    cat "$STATE_FILE"
}

# Parse state.json fields in one jq call.
parse_state() {
    local state="$1"
    eval "$(echo "$state" | jq -r '@sh "S_TASK=\(.task) S_STATE=\(.state) S_OWNER=\(.owner) S_REPO=\(.repo) S_SUMMARY=\(.summary) S_PREV_OWNER=\(.prev_owner) S_REV=\(.rev // 1) S_UPDATED=\(.updated)"')"
}

write_state() {
    local task="$1" state="$2" owner="$3" repo="$4" summary="$5" prev_owner="$6" rev="$7"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    jq -n \
        --arg task "$task" \
        --arg state "$state" \
        --arg owner "$owner" \
        --arg repo "$repo" \
        --arg summary "$summary" \
        --arg prev_owner "$prev_owner" \
        --argjson rev "$rev" \
        --arg updated "$ts" \
        '{task:$task,state:$state,owner:$owner,repo:$repo,summary:$summary,prev_owner:$prev_owner,rev:$rev,updated:$updated}' \
        > "$STATE_FILE"
}

append_event() {
    local action="$1" task="$2" repo="$3" from_state="$4" to_state="$5" from_owner="$6" to_owner="$7" rev="$8" summary="$9"
    local ts
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    jq -nc \
        --arg ts "$ts" \
        --arg action "$action" \
        --arg task "$task" \
        --arg repo "$repo" \
        --arg from_state "$from_state" \
        --arg to_state "$to_state" \
        --arg from_owner "$from_owner" \
        --arg to_owner "$to_owner" \
        --argjson rev "$rev" \
        --arg summary "$summary" \
        '{ts:$ts,action:$action,task:$task,repo:$repo,from_state:$from_state,to_state:$to_state,from_owner:$from_owner,to_owner:$to_owner,rev:$rev,summary:$summary}' \
        >> "$EVENTS_FILE"
}

wake() {
    local target="$1" message="$2"
    bash "$ROOT/.tandem/bin/wake.sh" "$target" "$message" || true
}

# ── Commands ──

cmd_status() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "No active task."
        return 0
    fi
    local state
    state=$(read_state)
    parse_state "$state"
    echo "$S_TASK | $S_STATE r$S_REV | owner: $S_OWNER | $S_SUMMARY ($S_UPDATED)"
}

cmd_init() {
    local task="" repo="" owner="" summary=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --task) task="$2"; shift 2 ;;
            --repo) repo="$2"; shift 2 ;;
            --owner) owner="$2"; shift 2 ;;
            --summary) summary="$2"; shift 2 ;;
            *) die "Unknown arg: $1" ;;
        esac
    done
    [ -z "$task" ] && die "--task required"
    [ -z "$owner" ] && die "--owner required"
    [ -z "$repo" ] && repo="general"
    [ -z "$summary" ] && summary="Task created"
    write_state "$task" "COORDINATE" "$owner" "$repo" "$summary" "" 1
    append_event "init" "$task" "$repo" "" "COORDINATE" "" "$owner" 1 "$summary"
    echo "Initialized: $task | COORDINATE r1 | owner: $owner"
}

cmd_next() {
    local to="" summary="" action="${ACTION:-next}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --to) to="$2"; shift 2 ;;
            --summary) summary="$2"; shift 2 ;;
            *) die "Unknown arg: $1" ;;
        esac
    done
    [ -z "$to" ] && die "--to required"

    local state
    state=$(read_state)
    parse_state "$state"
    local prev_owner="$S_OWNER"

    local next_state
    case "$S_STATE" in
        COORDINATE)   next_state="PLAN" ;;
        PLAN)         next_state="REVIEW_PLAN" ;;
        REVIEW_PLAN)  next_state="IMPLEMENT" ;;
        IMPLEMENT)    next_state="REVIEW_CODE" ;;
        REVIEW_CODE)  next_state="SIMPLIFY" ;;
        SIMPLIFY)     next_state="QUALITY_REVIEW" ;;
        QUALITY_REVIEW) next_state="COMMIT" ;;
        COMMIT)       next_state="IDLE" ;;
        *)            next_state="COORDINATE" ;;
    esac

    [ -z "$summary" ] && summary="Handed off to $to"
    write_state "$S_TASK" "$next_state" "$to" "$S_REPO" "$summary" "$prev_owner" "$S_REV"
    append_event "$action" "$S_TASK" "$S_REPO" "$S_STATE" "$next_state" "$prev_owner" "$to" "$S_REV" "$summary"
    echo "$S_TASK | $S_STATE → $next_state r$S_REV | owner: $to | $summary"

    local sender="${prev_owner:-$S_TASK}"
    # Point recipient at the relevant file for this transition
    local read_file=".tandem/handoff/plan.md"
    case "${S_STATE}:${next_state}" in
        COORDINATE:PLAN)         read_file=".tandem/handoff/plan.md" ;;
        PLAN:REVIEW_PLAN)        read_file=".tandem/handoff/plan.md" ;;
        REVIEW_PLAN:IMPLEMENT)   read_file=".tandem/handoff/plan.md" ;;
        IMPLEMENT:REVIEW_CODE)       read_file=".tandem/handoff/impl-notes.md" ;;
        REVIEW_CODE:SIMPLIFY)        read_file=".tandem/handoff/impl-notes.md" ;;
        SIMPLIFY:QUALITY_REVIEW)     read_file=".tandem/handoff/impl-notes.md" ;;
        QUALITY_REVIEW:COMMIT)       read_file=".tandem/handoff/impl-notes.md" ;;
    esac
    wake "$to" "[$sender]: $next_state r$S_REV. Run: bash .tandem/bin/handoff.sh status. Read: $read_file"
}

cmd_take() {
    local summary="" owner=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --summary) summary="$2"; shift 2 ;;
            --as) owner="$2"; shift 2 ;;
            *) die "Unknown arg: $1" ;;
        esac
    done
    [ -z "$owner" ] && die "--as required (who is taking ownership)"

    local state
    state=$(read_state)
    parse_state "$state"

    [ -z "$summary" ] && summary="$owner took ownership"
    write_state "$S_TASK" "$S_STATE" "$owner" "$S_REPO" "$summary" "$S_OWNER" "$S_REV"
    append_event "take" "$S_TASK" "$S_REPO" "$S_STATE" "$S_STATE" "$S_OWNER" "$owner" "$S_REV" "$summary"
    echo "$S_TASK | $S_STATE r$S_REV | owner: $owner (was $S_OWNER) | $summary"
}

cmd_back() {
    local summary="" action="${ACTION:-back}"
    while [ $# -gt 0 ]; do
        case "$1" in
            --summary) summary="$2"; shift 2 ;;
            *) die "Unknown arg: $1" ;;
        esac
    done

    local state
    state=$(read_state)
    parse_state "$state"

    [ -z "$S_PREV_OWNER" ] && die "No prev_owner to send back to"

    local back_state
    case "$S_STATE" in
        REVIEW_PLAN)    back_state="PLAN" ;;
        REVIEW_CODE)    back_state="IMPLEMENT" ;;
        QUALITY_REVIEW) back_state="SIMPLIFY" ;;
        SIMPLIFY)       back_state="IMPLEMENT" ;;
        *)            back_state="$S_STATE" ;;
    esac

    local new_rev=$((S_REV + 1))
    [ -z "$summary" ] && summary="Sent back for revision"
    write_state "$S_TASK" "$back_state" "$S_PREV_OWNER" "$S_REPO" "$summary" "$S_OWNER" "$new_rev"
    append_event "$action" "$S_TASK" "$S_REPO" "$S_STATE" "$back_state" "$S_OWNER" "$S_PREV_OWNER" "$new_rev" "$summary"
    echo "$S_TASK | $S_STATE → $back_state r$new_rev | owner: $S_PREV_OWNER | $summary"

    wake "$S_PREV_OWNER" "[$S_OWNER]: $back_state r$new_rev. Run: bash .tandem/bin/handoff.sh status. Read: .tandem/handoff/review.md"
}

cmd_done() {
    if [ -f "$STATE_FILE" ]; then
        local state
        state=$(read_state)
        parse_state "$state"
        append_event "done" "$S_TASK" "$S_REPO" "$S_STATE" "IDLE" "$S_OWNER" "" "$S_REV" "Task complete"
        rm -f "$STATE_FILE"
        echo "Task complete: $S_TASK → IDLE"
    else
        echo "No active task."
    fi
}

cmd_register() {
    local name="${1:-}"
    [ -z "$name" ] && die "Usage: handoff.sh register <name> (e.g. claude, codex)"
    [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || die "Invalid name '$name' (use letters, numbers, hyphens, underscores)"
    local tty_dev=""
    # Try tty first
    tty_dev=$(tty 2>/dev/null) || true
    # Fall back: walk up process tree to find first ancestor with a real TTY
    # (Claude Code / Codex sandbox shells report tty=?? but their parent has the real TTY)
    if [ -z "$tty_dev" ] || [ "$tty_dev" = "not a tty" ]; then
        tty_dev=""
        local pid=$$
        for _ in 1 2 3 4 5; do
            pid=$(ps -p "$pid" -o ppid= 2>/dev/null | tr -d '[:space:]')
            [ -z "$pid" ] && break
            local ptty
            ptty=$(ps -p "$pid" -o tty= 2>/dev/null | tr -d '[:space:]')
            if [ -n "$ptty" ] && [ "$ptty" != "??" ]; then
                tty_dev="/dev/$ptty"
                break
            fi
        done
    fi
    [ -z "$tty_dev" ] && die "Cannot detect TTY. Register manually: echo /dev/ttysXXX > .tandem/${name}.tty"
    echo "$tty_dev" > "$ROOT/.tandem/${name}.tty"
    echo "Registered $name: $tty_dev"
}

# ── Dispatch ──

CMD="${1:-status}"
shift || true

case "$CMD" in
    status)           cmd_status ;;
    init)             cmd_init "$@" ;;
    next)             cmd_next "$@" ;;
    accept)           ACTION=accept cmd_next "$@" ;;
    take)             cmd_take "$@" ;;
    back)             cmd_back "$@" ;;
    request-changes)  ACTION=request-changes cmd_back "$@" ;;
    done)             cmd_done ;;
    register)         cmd_register "$@" ;;
    *)                die "Unknown command: $CMD. Use: status|init|next|accept|take|back|request-changes|done|register" ;;
esac
