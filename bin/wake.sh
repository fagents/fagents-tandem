#!/bin/bash
# Wake an agent via TIOCSTI. Prints warning on failure.
#
# Exit codes:
#   0  message delivered (TIOCSTI succeeded)
#   1  usage error
#   2  no TTY registered for the target
#   3  sudo/TIOCSTI failure (target TTY exists but write failed)
#
# Callers that want best-effort tolerance (handoff.sh transitions, feature)
# should use `bash wake.sh ... || true`. The watchdog uses the exit code to
# distinguish wake-sent from wake-failed.
#
# Usage: wake.sh <agent> <message>
#   wake.sh rivet "[Kai]: Review ready"
#   wake.sh kai "[Juho]: New feature -- fix reconnect"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_DIR="$ROOT/.tandem"

TARGET="${1:-}"
MESSAGE="${2:-}"
[ -z "$TARGET" ] || [ -z "$MESSAGE" ] && { echo "Usage: wake.sh <agent> <message>" >&2; exit 1; }

TTY_DEV=$(tr -d '[:space:]' < "$AGENTS_DIR/${TARGET}.tty" 2>/dev/null) || {
    echo "WARN: no TTY registered for $TARGET" >&2
    echo "  $TARGET must check .tandem/handoff/state.json manually" >&2
    exit 2
}

sudo -n python3 -c "
import fcntl, termios, os, sys, time
fd = os.open(sys.argv[1], os.O_RDWR)
for ch in sys.argv[2]:
    fcntl.ioctl(fd, termios.TIOCSTI, ch.encode())
time.sleep(0.5)
fcntl.ioctl(fd, termios.TIOCSTI, b'\r')
os.close(fd)
" "$TTY_DEV" "$MESSAGE" 2>&1 || {
    echo "WARN: wake failed for $TARGET (sudo/TIOCSTI error)" >&2
    echo "  $TARGET must check .tandem/handoff/state.json manually" >&2
    exit 3
}
