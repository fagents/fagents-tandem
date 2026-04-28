#!/usr/bin/env bash
# Tests for fagents-tandem/bin/watchdog.sh.
#
# Each test creates a synthetic project under a temp dir with .tandem/handoff/
# and a mock wake.sh that records its invocations and obeys MOCK_WAKE_EXIT.
# Tests use --once mode and WATCHDOG_NOW_EPOCH for deterministic timing.
#
# Live PTY tests use python pty.openpty() so the watchdog's isatty probe sees
# a real interactive terminal during the wake path.

set -euo pipefail

# Disable job-control monitor mode so background-process termination on exit
# doesn't print "Terminated:" lines after the test summary.
set +m

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_PASSED=0
TESTS_FAILED=0

assert() {
    local name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "ok - $name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "not ok - $name (expected '$expected', got '$actual')"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# Per-test temp dir + cleanup chain
TMP_ROOT=$(mktemp -d)
PTY_PIDS=()
cleanup() {
    for pid in "${PTY_PIDS[@]:-}"; do
        [ -n "$pid" ] && { kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null; } || true
    done
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

new_project() {
    PROJECT_DIR=$(mktemp -d -p "$TMP_ROOT")
    mkdir -p "$PROJECT_DIR/.tandem/handoff" "$PROJECT_DIR/.tandem/bin"
    INVOCATIONS_FILE="$PROJECT_DIR/.wake-invocations"
    : > "$INVOCATIONS_FILE"
    cat > "$PROJECT_DIR/.tandem/bin/wake.sh" <<EOF
#!/usr/bin/env bash
# Mock wake.sh: records args, returns \${MOCK_WAKE_EXIT:-0}.
printf '%s\n' "\$*" >> "$INVOCATIONS_FILE"
exit "\${MOCK_WAKE_EXIT:-0}"
EOF
    chmod +x "$PROJECT_DIR/.tandem/bin/wake.sh"
}

make_state() {
    local owner="$1" updated="$2"
    jq -nc \
        --arg task "test-task" \
        --arg state "PLAN" \
        --arg owner "$owner" \
        --arg repo "test" \
        --arg summary "test" \
        --arg prev_owner "" \
        --argjson rev 1 \
        --arg updated "$updated" \
        '{task:$task, state:$state, owner:$owner, repo:$repo, summary:$summary, prev_owner:$prev_owner, rev:$rev, updated:$updated}' \
        > "$PROJECT_DIR/.tandem/handoff/state.json"
}

# iso_at <epoch>: print ISO 8601 UTC for a given epoch.
iso_at() {
    local e="$1"
    date -u -r "$e" +%FT%TZ 2>/dev/null \
        || date -u -d "@$e" +%FT%TZ 2>/dev/null
}

# Open a pty pair, plant the slave path in <project>/.tandem/<owner>.tty.
# The python holder runs in the background to keep the master open;
# its PID is recorded for cleanup.
make_pty_for_owner() {
    local owner="$1"
    local out_file
    out_file=$(mktemp -p "$TMP_ROOT")
    python3 -c '
import pty, os, sys, time
master, slave = pty.openpty()
sys.stdout.write(os.ttyname(slave) + "\n")
sys.stdout.flush()
while True:
    time.sleep(3600)
' > "$out_file" &
    local pid=$!
    PTY_PIDS+=("$pid")
    local tries=0
    while [ ! -s "$out_file" ] && [ "$tries" -lt 50 ]; do
        sleep 0.05
        tries=$((tries + 1))
    done
    local pty_path
    pty_path=$(tr -d '\n' < "$out_file")
    [ -n "$pty_path" ] || { echo "make_pty_for_owner: failed to get pty path" >&2; return 1; }
    printf '%s' "$pty_path" > "$PROJECT_DIR/.tandem/${owner}.tty"
}

run_watchdog_once() {
    WATCHDOG_NOW_EPOCH="$1" bash "$ROOT/bin/watchdog.sh" --once "$PROJECT_DIR" 2>/dev/null
}

log_kind_count() {
    local kind="$1" out
    [ -f "$PROJECT_DIR/.tandem/watchdog.log" ] || { echo 0; return; }
    # `grep -c` exits non-zero on zero matches; capture the count and tolerate.
    out=$(grep -cF "\"kind\":\"$kind\"" "$PROJECT_DIR/.tandem/watchdog.log" 2>/dev/null || true)
    echo "${out:-0}"
}

invocations_count() { wc -l < "$INVOCATIONS_FILE" | tr -d ' '; }

NOW=1777000000
PAST_RECENT=$((NOW - 100))    # 100s ago, below default 30 min threshold
PAST_STALE=$((NOW - 3600))    # 1h ago, above default 30 min threshold

# ---------- Tests ----------

# Idle below threshold (100s < 1800s default): no events, no wake.
new_project
make_state "claude" "$(iso_at "$PAST_RECENT")"
run_watchdog_once "$NOW"
assert "idle below threshold: zero events"  "0" "$(log_kind_count wake-sent)"
assert "idle below threshold: zero invocations" "0" "$(invocations_count)"

# Idle above threshold, valid PTY, mocked wake exits 0 -> wake-sent.
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
assert "wake-sent emitted" "1" "$(log_kind_count wake-sent)"
assert "mock wake invoked once" "1" "$(invocations_count)"
INV=$(head -n 1 "$INVOCATIONS_FILE")
case "$INV" in
    *"claude"*"idle"*"3600s"*) echo "ok - mock wake message includes owner + idle"; TESTS_PASSED=$((TESTS_PASSED + 1)) ;;
    *) echo "not ok - mock wake message includes owner + idle (got '$INV')"; TESTS_FAILED=$((TESTS_FAILED + 1)) ;;
esac

# Idle above threshold, valid PTY, mocked wake exits 3 -> wake-failed (alert).
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
MOCK_WAKE_EXIT=3 run_watchdog_once "$NOW"
assert "wake-failed emitted" "1" "$(log_kind_count wake-failed)"
assert "wake-sent NOT emitted on failure" "0" "$(log_kind_count wake-sent)"
assert "mock wake invoked once even on failure" "1" "$(invocations_count)"

# dead-tty: missing TTY file
new_project
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
assert "dead-tty (missing) emitted" "1" "$(log_kind_count dead-tty)"
REASON=$(jq -r 'select(.kind == "dead-tty") | .reason' "$PROJECT_DIR/.tandem/watchdog.log" 2>/dev/null)
assert "dead-tty reason = missing" "missing" "$REASON"
assert "no wake invoked on dead-tty" "0" "$(invocations_count)"

# dead-tty: empty TTY file
new_project
: > "$PROJECT_DIR/.tandem/claude.tty"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
REASON=$(jq -r 'select(.kind == "dead-tty") | .reason' "$PROJECT_DIR/.tandem/watchdog.log" 2>/dev/null)
assert "dead-tty reason = empty" "empty" "$REASON"

# dead-tty: not-char-device (regular file)
new_project
TMP_REGFILE=$(mktemp -p "$TMP_ROOT")
echo "$TMP_REGFILE" > "$PROJECT_DIR/.tandem/claude.tty"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
REASON=$(jq -r 'select(.kind == "dead-tty") | .reason' "$PROJECT_DIR/.tandem/watchdog.log" 2>/dev/null)
assert "dead-tty reason = not-char-device" "not-char-device" "$REASON"

# dead-tty: not-isatty (/dev/null) -- the codex correctness case
new_project
echo "/dev/null" > "$PROJECT_DIR/.tandem/claude.tty"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
REASON=$(jq -r 'select(.kind == "dead-tty") | .reason' "$PROJECT_DIR/.tandem/watchdog.log" 2>/dev/null)
assert "dead-tty reason = not-isatty (/dev/null)" "not-isatty" "$REASON"
assert "no wake on /dev/null" "0" "$(invocations_count)"

# Rate limiting: two consecutive ticks for same (owner, updated) -> only 1 wake.
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
run_watchdog_once "$((NOW + 60))"   # 60s later, same owner+updated, way below backoff
assert "rate limit: still 1 wake-sent" "1" "$(log_kind_count wake-sent)"
assert "rate limit: 1 rate-limited event" "1" "$(log_kind_count rate-limited)"
assert "rate limit: still 1 mock invocation" "1" "$(invocations_count)"

# Backoff escalation: with THRESHOLD=1800, factor=2, last wake at NOW.
# After wake N=1, the next-wake window is THRESHOLD * FACTOR^1 = 3600s.
# Boundary: +1801s must still be rate-limited; +3601s must be allowed.
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
run_watchdog_once "$((NOW + 1801))"
assert "backoff: still rate-limited at +1801s (was off-by-one in r2)" "1" "$(log_kind_count wake-sent)"
run_watchdog_once "$((NOW + 3599))"
assert "backoff: still rate-limited at +3599s" "1" "$(log_kind_count wake-sent)"
run_watchdog_once "$((NOW + 3601))"
assert "backoff: allowed after threshold * factor (3600s)" "2" "$(log_kind_count wake-sent)"

# Backoff continues to grow: after second wake (step=2), next is THRESHOLD * FACTOR^2 = 7200.
# Place the second wake at NOW2 = NOW+3601; third must wait until NOW2+7200.
NOW2=$((NOW + 3601))
run_watchdog_once "$((NOW2 + 7199))"
assert "backoff step 2: rate-limited at +7199 from second wake" "2" "$(log_kind_count wake-sent)"
run_watchdog_once "$((NOW2 + 7201))"
assert "backoff step 2: allowed at +7201 from second wake" "3" "$(log_kind_count wake-sent)"

# State transition resets rate-limit window.
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
# Now the owner transitions: same owner, NEW updated timestamp
make_state "claude" "$(iso_at "$NOW")"
# 100s later, idle below threshold against the new updated -> no wake
run_watchdog_once "$((NOW + 100))"
assert "transition: no extra wake while idle below threshold" "1" "$(log_kind_count wake-sent)"
# 1801s after the new updated -> idle above threshold, fresh state -> wake
make_state "claude" "$(iso_at "$NOW")"
run_watchdog_once "$((NOW + 1801))"
assert "transition: fresh wake on new (owner, updated)" "2" "$(log_kind_count wake-sent)"

# state.json absent -> no-active-task event, no wake.
new_project
run_watchdog_once "$NOW"
assert "state absent: no-active-task" "1" "$(log_kind_count no-active-task)"
assert "state absent: no wake" "0" "$(invocations_count)"

# Owner empty in state.json -> no-active-task.
new_project
make_state "" "$(iso_at "$PAST_STALE")"
run_watchdog_once "$NOW"
assert "owner empty: no-active-task" "1" "$(log_kind_count no-active-task)"

# Malformed state.json -> invalid-state event, watchdog exits 0 (daemon survives).
new_project
echo "{not valid json" > "$PROJECT_DIR/.tandem/handoff/state.json"
EXIT=0
WATCHDOG_NOW_EPOCH="$NOW" bash "$ROOT/bin/watchdog.sh" --once "$PROJECT_DIR" 2>/dev/null || EXIT=$?
assert "malformed state: watchdog exits 0" "0" "$EXIT"
assert "malformed state: invalid-state emitted" "1" "$(log_kind_count invalid-state)"
assert "malformed state: no wake invoked" "0" "$(invocations_count)"

# Empty state.json (transient race during handoff.sh write). jq accepts
# zero-byte input, exits 0 with no output, owner+updated parse to empty -> the
# existing no-active-task path handles it. Daemon survives. We assert this
# gracefully degrades rather than emitting a noisy invalid-state alarm for
# what is normally a sub-millisecond race window.
new_project
: > "$PROJECT_DIR/.tandem/handoff/state.json"
EXIT=0
WATCHDOG_NOW_EPOCH="$NOW" bash "$ROOT/bin/watchdog.sh" --once "$PROJECT_DIR" 2>/dev/null || EXIT=$?
assert "empty state: watchdog exits 0" "0" "$EXIT"
assert "empty state: no-active-task (not invalid-state)" "1" "$(log_kind_count no-active-task)"
assert "empty state: zero invalid-state events" "0" "$(log_kind_count invalid-state)"

# WATCHDOG_VERBOSE=1 + idle owner -> owner-active event.
new_project
make_state "claude" "$(iso_at "$PAST_RECENT")"
WATCHDOG_VERBOSE=1 run_watchdog_once "$NOW"
assert "verbose: owner-active emitted" "1" "$(log_kind_count owner-active)"

# Default (verbose off) -> zero owner-active events.
new_project
make_state "claude" "$(iso_at "$PAST_RECENT")"
run_watchdog_once "$NOW"
assert "default: no owner-active events" "0" "$(log_kind_count owner-active)"

# Read-only invariant: hash state.json + handoff/*.md before and after a tick.
new_project
make_pty_for_owner "claude"
make_state "claude" "$(iso_at "$PAST_STALE")"
echo "plan body" > "$PROJECT_DIR/.tandem/handoff/plan.md"
echo "review body" > "$PROJECT_DIR/.tandem/handoff/review.md"
echo "impl notes" > "$PROJECT_DIR/.tandem/handoff/impl-notes.md"
HASH_BEFORE=$(shasum -a 256 \
    "$PROJECT_DIR/.tandem/handoff/state.json" \
    "$PROJECT_DIR/.tandem/handoff/plan.md" \
    "$PROJECT_DIR/.tandem/handoff/review.md" \
    "$PROJECT_DIR/.tandem/handoff/impl-notes.md" \
    | awk '{print $1}' | sort | tr '\n' ' ')
run_watchdog_once "$NOW"
HASH_AFTER=$(shasum -a 256 \
    "$PROJECT_DIR/.tandem/handoff/state.json" \
    "$PROJECT_DIR/.tandem/handoff/plan.md" \
    "$PROJECT_DIR/.tandem/handoff/review.md" \
    "$PROJECT_DIR/.tandem/handoff/impl-notes.md" \
    | awk '{print $1}' | sort | tr '\n' ' ')
assert "read-only invariant: handoff files unchanged" "$HASH_BEFORE" "$HASH_AFTER"

# wake.sh contract: TTY-missing -> exit 2 (not 0).
# Test against the canonical wake.sh with a synthetic target whose .tty does
# not exist. Pre- and post-cleanup defensively in case any future wake.sh
# regression starts creating .tty files.
WAKE_TARGET="watchdog-test-nonexistent-$$"
WAKE_TARGET_TTY="$ROOT/.tandem/${WAKE_TARGET}.tty"
rm -f "$WAKE_TARGET_TTY"
WAKE_EXIT=0
bash "$ROOT/bin/wake.sh" "$WAKE_TARGET" "msg" >/dev/null 2>&1 || WAKE_EXIT=$?
rm -f "$WAKE_TARGET_TTY"
assert "wake.sh: TTY-missing exits 2" "2" "$WAKE_EXIT"

# wake.sh contract: usage error -> exit 1.
WAKE_EXIT=0
bash "$ROOT/bin/wake.sh" >/dev/null 2>&1 || WAKE_EXIT=$?
assert "wake.sh: usage error exits 1" "1" "$WAKE_EXIT"

# Lint: shellcheck on watchdog.sh, wake.sh, feature.
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck "$ROOT/bin/watchdog.sh" "$ROOT/bin/wake.sh" "$ROOT/bin/feature" >/dev/null 2>&1; then
        echo "ok - shellcheck on bin/{watchdog.sh,wake.sh,feature}"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        echo "not ok - shellcheck on bin/{watchdog.sh,wake.sh,feature}"
        shellcheck "$ROOT/bin/watchdog.sh" "$ROOT/bin/wake.sh" "$ROOT/bin/feature" || true
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
fi

echo
echo "$TESTS_PASSED passed, $TESTS_FAILED failed"
[ "$TESTS_FAILED" -eq 0 ]
