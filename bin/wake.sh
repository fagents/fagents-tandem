#!/bin/bash
# Wake an agent via TIOCSTI. Best-effort — prints warning on failure, never blocks.
#
# Usage: wake.sh <agent> <message>
#   wake.sh rivet "[Kai]: Review ready"
#   wake.sh kai "[Juho]: New feature — fix reconnect"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
AGENTS_DIR="$ROOT/.tandem"

TARGET="${1:-}"
MESSAGE="${2:-}"
[ -z "$TARGET" ] || [ -z "$MESSAGE" ] && { echo "Usage: wake.sh <agent> <message>" >&2; exit 1; }

TTY_DEV=$(tr -d '[:space:]' < "$AGENTS_DIR/${TARGET}.tty" 2>/dev/null) || {
    echo "WARN: no TTY registered for $TARGET" >&2
    echo "  $TARGET must check .tandem/handoff/state.json manually" >&2
    exit 0
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
}
