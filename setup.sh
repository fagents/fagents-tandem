#!/bin/bash
# fagents-tandem setup — paired agent coordination for any project.
#
# Usage:
#   bash setup.sh                    # fresh install in current directory
#
# Creates .tandem/ runtime directory + installs tandem skill for Claude/Codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PWD}"
TANDEM_DIR="$PROJECT_DIR/.tandem"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            echo "Usage: bash setup.sh"
            exit 0
            ;;
        *) echo "Usage: bash setup.sh" >&2; exit 1 ;;
    esac
done

echo "=== fagents-tandem setup ==="
echo ""

# ── Create .tandem/ ──
echo "Setting up .tandem/..."
mkdir -p "$TANDEM_DIR/bin" "$TANDEM_DIR/handoff"

# Copy scripts
for script in handoff.sh wake.sh feature; do
    if [[ -f "$SCRIPT_DIR/bin/$script" ]]; then
        cp "$SCRIPT_DIR/bin/$script" "$TANDEM_DIR/bin/$script"
        chmod +x "$TANDEM_DIR/bin/$script"
    fi
done

# .gitignore — always write canonical version (overwrite stale from migration)
cat > "$TANDEM_DIR/.gitignore" << 'EOF'
# Everything is runtime except bin/
*
!.gitignore
!bin/
!bin/**
EOF

echo "  Created .tandem/bin/ with handoff.sh, wake.sh, feature"

# ── Install skill for Claude ──
if command -v claude &>/dev/null; then
    CLAUDE_SKILL_DIR="$HOME/.claude/skills/tandem"
    mkdir -p "$CLAUDE_SKILL_DIR"
    cp "$SCRIPT_DIR/skill/SKILL.md" "$CLAUDE_SKILL_DIR/SKILL.md"
    echo "  Installed Claude skill: ~/.claude/skills/tandem/"
fi

# ── Install skill for Codex ──
if command -v codex &>/dev/null; then
    CODEX_SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/tandem"
    mkdir -p "$CODEX_SKILL_DIR"
    cp "$SCRIPT_DIR/skill/SKILL.md" "$CODEX_SKILL_DIR/SKILL.md"
    echo "  Installed Codex skill: ~/.codex/skills/tandem/"
fi

# ── TEAM.md ──
if [[ ! -f "$PROJECT_DIR/TEAM.md" ]]; then
    cp "$SCRIPT_DIR/templates/TEAM.md" "$PROJECT_DIR/TEAM.md"
    echo "  Created TEAM.md from template"
else
    echo "  TEAM.md already exists — skipping"
fi

# ── Done ──
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Register your agents' TTYs:"
echo "     echo /dev/ttysXXX > .tandem/agent1.tty"
echo "     echo /dev/ttysYYY > .tandem/agent2.tty"
echo ""
echo "  2. Start your first feature:"
echo "     .tandem/bin/feature \"description of what to build\""
echo ""
echo "  3. Or check status:"
echo "     bash .tandem/bin/handoff.sh status"
