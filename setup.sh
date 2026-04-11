#!/bin/bash
# fagents-tandem setup — paired agent coordination for any project.
#
# Usage:
#   bash setup.sh                    # fresh install in current directory
#   bash setup.sh --migrate          # migrate from .agents/ to .tandem/
#
# Creates .tandem/ runtime directory + installs tandem skill for Claude/Codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PWD}"
TANDEM_DIR="$PROJECT_DIR/.tandem"
MIGRATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --migrate) MIGRATE=1; shift ;;
        --help|-h)
            echo "Usage: bash setup.sh [--migrate]"
            echo "  --migrate   Migrate from .agents/ to .tandem/"
            exit 0
            ;;
        *) shift ;;
    esac
done

echo "=== fagents-tandem setup ==="
echo ""

# ── Migration from .agents/ ──
if [[ -n "$MIGRATE" ]]; then
    OLD_DIR="$PROJECT_DIR/.agents"
    if [[ ! -d "$OLD_DIR" ]]; then
        echo "No .agents/ directory found — nothing to migrate."
    else
        echo "Migrating tandem-owned files from .agents/ → .tandem/..."
        mkdir -p "$TANDEM_DIR/bin" "$TANDEM_DIR/handoff"

        # Move tandem-owned content only
        for f in "$OLD_DIR/bin/handoff.sh" "$OLD_DIR/bin/wake.sh" "$OLD_DIR/bin/feature"; do
            [[ -f "$f" ]] && mv "$f" "$TANDEM_DIR/bin/"
        done
        for f in "$OLD_DIR/handoff/"*; do
            [[ -f "$f" ]] && mv "$f" "$TANDEM_DIR/handoff/"
        done
        for f in "$OLD_DIR/"*.tty; do
            [[ -f "$f" ]] && mv "$f" "$TANDEM_DIR/"
        done
        [[ -f "$OLD_DIR/.gitignore" ]] && cp "$OLD_DIR/.gitignore" "$TANDEM_DIR/.gitignore"

        # Update refs in TEAM.md
        if [[ -f "$PROJECT_DIR/TEAM.md" ]]; then
            if sed --version 2>/dev/null | grep -q GNU; then
                sed -i 's|\.agents/bin/|.tandem/bin/|g; s|\.agents/handoff/|.tandem/handoff/|g' "$PROJECT_DIR/TEAM.md"
            else
                sed -i '' 's|\.agents/bin/|.tandem/bin/|g; s|\.agents/handoff/|.tandem/handoff/|g' "$PROJECT_DIR/TEAM.md"
            fi
            echo "  Updated TEAM.md refs"
        fi

        # Clean empty old dirs (only if we emptied them)
        rmdir "$OLD_DIR/bin" 2>/dev/null || true
        rmdir "$OLD_DIR/handoff" 2>/dev/null || true

        echo "  Migration complete. Old .agents/ may still contain non-tandem files."
    fi
    echo ""
fi

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

# .gitignore — track only bin/
if [[ ! -f "$TANDEM_DIR/.gitignore" ]]; then
    cat > "$TANDEM_DIR/.gitignore" << 'EOF'
# Everything is runtime except bin/
*
!.gitignore
!bin/
!bin/**
EOF
fi

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
    CODEX_SKILL_DIR="$HOME/.codex/skills/tandem"
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
