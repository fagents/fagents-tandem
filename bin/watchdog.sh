#!/bin/bash
# fagents-tandem watchdog: in-session liveness nudge for idle state owners.
#
# Reads .tandem/handoff/state.json and pokes the current owner via wake.sh
# when idle past threshold. Distinguishes wake-sent vs wake-failed via
# wake.sh exit code. Flags dead or non-interactive TTYs as a loud,
# operator-visible event without consuming a wake attempt.
#
# Read-only on tandem state. Never writes to state.json, events.jsonl, or
# handoff/*.md. The watchdog only writes to its own log.
#
# Usage:
#   bash watchdog.sh <project-dir>            daemon mode (loops)
#   bash watchdog.sh --once <project-dir>     run one tick, exit
#   WATCHDOG_ONCE=1 bash watchdog.sh <dir>    same as --once
#
# Env vars:
#   WATCHDOG_THRESHOLD_SECONDS    idle threshold before first poke (default 1800)
#   WATCHDOG_INTERVAL_SECONDS     poll interval, daemon mode (default 300)
#   WATCHDOG_BACKOFF_FACTOR       multiplier for repeated-poke backoff (default 2)
#   WATCHDOG_MAX_BACKOFF_SECONDS  cap on backoff window (default 7200 = 2h)
#   WATCHDOG_VERBOSE              "1" to log owner-active happy-path events
#   WATCHDOG_ONCE                 "1" same as --once
#   WATCHDOG_NOW_EPOCH            override "now" for tests (epoch seconds)

set -euo pipefail

ONCE="${WATCHDOG_ONCE:-}"
PROJECT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --once)    ONCE=1; shift ;;
        --help|-h) sed -n '2,/^$/p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *)         PROJECT="$1"; shift ;;
    esac
done

[ -n "$PROJECT" ] || { echo "Usage: watchdog.sh [--once] <project-dir>" >&2; exit 1; }
[ -d "$PROJECT" ] || { echo "watchdog: $PROJECT is not a directory" >&2; exit 1; }
[ -d "$PROJECT/.tandem" ] || { echo "watchdog: $PROJECT/.tandem missing" >&2; exit 1; }

THRESHOLD="${WATCHDOG_THRESHOLD_SECONDS:-1800}"
INTERVAL="${WATCHDOG_INTERVAL_SECONDS:-300}"
BACKOFF_FACTOR="${WATCHDOG_BACKOFF_FACTOR:-2}"
MAX_BACKOFF="${WATCHDOG_MAX_BACKOFF_SECONDS:-7200}"
VERBOSE="${WATCHDOG_VERBOSE:-}"

STATE="$PROJECT/.tandem/handoff/state.json"
LOG="$PROJECT/.tandem/watchdog.log"
WAKE="$PROJECT/.tandem/bin/wake.sh"
PROJECT_NAME="$(basename "$PROJECT")"

# Convert ISO 8601 timestamp to Unix epoch (seconds). GNU date first, then
# BSD date with Z form, then BSD date with offset form (sed-stripped colon
# because BSD %z does not accept HH:MM offsets).
to_epoch() {
    local ts="$1" out stripped
    out=$(date -d "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return 0; }
    out=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return 0; }
    stripped=$(printf '%s' "$ts" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    out=$(date -j -f '%Y-%m-%dT%H:%M:%S%z' "$stripped" +%s 2>/dev/null) && [ -n "$out" ] && { echo "$out"; return 0; }
    echo "0"
    return 1
}

now_epoch() {
    if [ -n "${WATCHDOG_NOW_EPOCH:-}" ]; then
        echo "$WATCHDOG_NOW_EPOCH"
    else
        date +%s
    fi
}

now_ts() {
    if [ -n "${WATCHDOG_NOW_EPOCH:-}" ]; then
        date -u -r "$WATCHDOG_NOW_EPOCH" +%FT%TZ 2>/dev/null \
            || date -u -d "@$WATCHDOG_NOW_EPOCH" +%FT%TZ 2>/dev/null \
            || date -u +%FT%TZ
    else
        date -u +%FT%TZ
    fi
}

# log_event <kind> <k=v> [<k=v> ...]
# Values that match a strict integer literal (no leading zeros, optional minus)
# become JSON numbers; everything else becomes JSON strings. Strict pattern
# rejects "0123" so a leading-zero string is preserved as a string.
log_event() {
    local kind="$1"; shift
    local now_e now_t
    now_e=$(now_epoch)
    now_t=$(now_ts)
    local args=(--arg ts "$now_t" --argjson epoch "$now_e" --arg kind "$kind")
    local pairs=()
    while [ $# -gt 0 ]; do
        local k="${1%%=*}"
        local v="${1#*=}"
        if [[ "$v" =~ ^-?(0|[1-9][0-9]*)$ ]]; then
            args+=(--argjson "$k" "$v")
        else
            args+=(--arg "$k" "$v")
        fi
        pairs+=("\"$k\": \$$k")
        shift
    done
    local pairs_str
    pairs_str=$(printf ',%s' "${pairs[@]}")
    pairs_str=${pairs_str:1}
    jq -nc "${args[@]}" "{ts:\$ts, epoch:\$epoch, kind:\$kind, $pairs_str}" >> "$LOG"
}

# tty_valid <owner>: echoes reason and returns 1 on failure; returns 0 on success.
tty_valid() {
    local owner="$1"
    local tty_file="$PROJECT/.tandem/${owner}.tty"
    [ -f "$tty_file" ] || { echo "missing"; return 1; }
    local dev
    dev=$(tr -d '[:space:]' < "$tty_file" 2>/dev/null)
    [ -n "$dev" ] || { echo "empty"; return 1; }
    [ -c "$dev" ] || { echo "not-char-device"; return 1; }
    [ -w "$dev" ] || { echo "not-writable"; return 1; }
    python3 -c '
import os, sys
try:
    fd = os.open(sys.argv[1], os.O_RDWR)
    ok = os.isatty(fd)
    os.close(fd)
    sys.exit(0 if ok else 1)
except OSError:
    sys.exit(1)
' "$dev" 2>/dev/null || { echo "not-isatty"; return 1; }
    return 0
}

# Most recent wake-sent event for current (owner, updated). Tab-separated
# epoch and backoff_step on stdout; empty output if none.
last_wake_for_state() {
    local owner="$1" updated="$2"
    [ -f "$LOG" ] || return 0
    grep -F "\"kind\":\"wake-sent\"" "$LOG" 2>/dev/null \
        | jq -r --arg owner "$owner" --arg updated "$updated" \
            'select(.owner == $owner and .updated == $updated) | "\(.epoch)\t\(.backoff_step // 1)"' \
            2>/dev/null \
        | tail -n 1
}

# Most recent dead-tty event for (owner, tty_file_mtime).
last_dead_tty_for_owner() {
    local owner="$1" mtime="$2"
    [ -f "$LOG" ] || return 0
    grep -F "\"kind\":\"dead-tty\"" "$LOG" 2>/dev/null \
        | jq -r --arg owner "$owner" --arg mtime "$mtime" \
            'select(.owner == $owner and (.tty_mtime // "") == $mtime) | .epoch' \
            2>/dev/null \
        | tail -n 1
}

# tty_file_mtime <owner>: prints mtime as epoch seconds, empty if absent.
tty_file_mtime() {
    local owner="$1"
    local tty_file="$PROJECT/.tandem/${owner}.tty"
    [ -f "$tty_file" ] || { echo ""; return 0; }
    stat -f %m "$tty_file" 2>/dev/null \
        || stat -c %Y "$tty_file" 2>/dev/null \
        || echo ""
}

run_tick() {
    local now
    now=$(now_epoch)

    if [ ! -f "$STATE" ]; then
        log_event "no-active-task" "owner=" "idle_seconds=0"
        return 0
    fi

    # Tolerate malformed / partial state.json: jq exit non-zero -> log
    # invalid-state and return 0 for this tick. Daemon survives transient
    # races where handoff.sh writes state.json with normal redirection.
    local state_tsv
    if ! state_tsv=$(jq -r '"\(.owner // "")\t\(.updated // "")"' "$STATE" 2>/dev/null); then
        log_event "invalid-state" "reason=jq-parse-failed"
        return 0
    fi
    local owner updated
    IFS=$'\t' read -r owner updated <<<"$state_tsv"

    if [ -z "$owner" ] || [ -z "$updated" ]; then
        log_event "no-active-task" "owner=$owner" "idle_seconds=0"
        return 0
    fi

    local updated_epoch idle
    updated_epoch=$(to_epoch "$updated")
    idle=$((now - updated_epoch))

    if [ "$idle" -lt "$THRESHOLD" ]; then
        if [ "$VERBOSE" = "1" ]; then
            log_event "owner-active" "owner=$owner" "updated=$updated" "idle_seconds=$idle"
        fi
        return 0
    fi

    local mtime reason
    mtime=$(tty_file_mtime "$owner")
    if ! reason=$(tty_valid "$owner"); then
        local last_dead
        last_dead=$(last_dead_tty_for_owner "$owner" "$mtime")
        if [ -z "$last_dead" ]; then
            log_event "dead-tty" "owner=$owner" "updated=$updated" "idle_seconds=$idle" \
                "reason=$reason" "tty_mtime=$mtime" "tty_path=$PROJECT/.tandem/${owner}.tty"
            echo "[watchdog] DEAD-TTY: $PROJECT_NAME owner=$owner reason=$reason" >&2
        fi
        return 0
    fi

    # Rate-limit wakes via exponential backoff per (owner, updated)
    local last last_epoch=0 last_step=0 next_step=1
    last=$(last_wake_for_state "$owner" "$updated" || true)
    if [ -n "$last" ]; then
        last_epoch=$(printf '%s' "$last" | cut -f1)
        last_step=$(printf '%s' "$last" | cut -f2)
        next_step=$((last_step + 1))
        # Wake N+1 must wait `THRESHOLD * BACKOFF_FACTOR^N` since wake N. With
        # last_step=1 this yields THRESHOLD * FACTOR (3600s at defaults), not
        # THRESHOLD itself.
        local backoff=$THRESHOLD
        local k=$last_step
        while [ "$k" -gt 0 ]; do
            backoff=$((backoff * BACKOFF_FACTOR))
            k=$((k - 1))
        done
        [ "$backoff" -gt "$MAX_BACKOFF" ] && backoff=$MAX_BACKOFF
        local since_last=$((now - last_epoch))
        if [ "$since_last" -lt "$backoff" ]; then
            log_event "rate-limited" "owner=$owner" "updated=$updated" "idle_seconds=$idle" \
                "since_last_wake=$since_last" "backoff_seconds=$backoff" "backoff_step=$last_step"
            return 0
        fi
    fi

    local wake_msg wake_stderr wake_exit=0
    wake_msg="[watchdog]: ${owner} idle ${idle}s in ${PROJECT_NAME}. Run: bash .tandem/bin/handoff.sh status"
    wake_stderr=$(bash "$WAKE" "$owner" "$wake_msg" 2>&1) || wake_exit=$?

    if [ "$wake_exit" -eq 0 ]; then
        log_event "wake-sent" "owner=$owner" "updated=$updated" "idle_seconds=$idle" \
            "backoff_step=$next_step"
    else
        log_event "wake-failed" "owner=$owner" "updated=$updated" "idle_seconds=$idle" \
            "wake_exit_code=$wake_exit" "wake_stderr=$wake_stderr"
        echo "[watchdog] WAKE-FAILED: $PROJECT_NAME owner=$owner exit=$wake_exit" >&2
    fi
}

if [ "$ONCE" = "1" ]; then
    run_tick
else
    while true; do
        run_tick
        sleep "$INTERVAL"
    done
fi
