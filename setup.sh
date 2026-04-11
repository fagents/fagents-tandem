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

    # Add SessionStart hook for auto-registration
    SETTINGS="$PROJECT_DIR/.claude/settings.json"
    mkdir -p "$PROJECT_DIR/.claude"
    if [ -f "$SETTINGS" ]; then
        # Merge hook into existing settings
        jq '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": "bash .tandem/bin/handoff.sh register claude 2>/dev/null || true"}]}]' \
            "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    else
        cat > "$SETTINGS" << 'SEOF'
{
  "hooks": {
    "SessionStart": [
      {"hooks": [{"type": "command", "command": "bash .tandem/bin/handoff.sh register claude 2>/dev/null || true"}]}
    ]
  }
}
SEOF
    fi
    echo "  Installed Claude SessionStart hook (auto-register)"
fi

# ── Install skill for Codex ──
if command -v codex &>/dev/null; then
    CODEX_SKILL_DIR="${CODEX_HOME:-$HOME/.codex}/skills/tandem"
    mkdir -p "$CODEX_SKILL_DIR"
    cp "$SCRIPT_DIR/skill/SKILL.md" "$CODEX_SKILL_DIR/SKILL.md"
    echo "  Installed Codex skill: ${CODEX_HOME:-~/.codex}/skills/tandem/"

    # Add SessionStart hook for auto-registration (experimental codex_hooks feature)
    CODEX_HOOKS="$PROJECT_DIR/.codex/hooks.json"
    mkdir -p "$PROJECT_DIR/.codex"
    if [ -f "$CODEX_HOOKS" ]; then
        jq '.hooks.SessionStart = [{"hooks": [{"type": "command", "command": "bash .tandem/bin/handoff.sh register codex 2>/dev/null || true"}], "matcher": ["startup", "resume"]}]' \
            "$CODEX_HOOKS" > "$CODEX_HOOKS.tmp" && mv "$CODEX_HOOKS.tmp" "$CODEX_HOOKS"
    else
        cat > "$CODEX_HOOKS" << 'CEOF'
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": ["startup", "resume"],
        "hooks": [{"type": "command", "command": "bash .tandem/bin/handoff.sh register codex 2>/dev/null || true"}]
      }
    ]
  }
}
CEOF
    fi
    echo "  Installed Codex SessionStart hook (auto-register)"
fi

# ── Project docs ──
if [[ ! -f "$PROJECT_DIR/TEAM.md" ]]; then
    cp "$SCRIPT_DIR/templates/TEAM.md" "$PROJECT_DIR/TEAM.md"
    echo "  Created TEAM.md"
else
    echo "  TEAM.md already exists — skipping"
fi

if [[ ! -f "$PROJECT_DIR/CLAUDE.md" ]]; then
    cp "$SCRIPT_DIR/templates/CLAUDE.md" "$PROJECT_DIR/CLAUDE.md"
    echo "  Created CLAUDE.md"
else
    echo "  CLAUDE.md already exists — skipping"
fi

if [[ ! -f "$PROJECT_DIR/AGENTS.md" ]]; then
    cp "$SCRIPT_DIR/templates/AGENTS.md" "$PROJECT_DIR/AGENTS.md"
    echo "  Created AGENTS.md"
else
    echo "  AGENTS.md already exists — skipping"
fi

# ── Done ──
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Start Claude Code in one terminal -- it reads CLAUDE.md and self-registers."
echo "  2. Start Codex CLI in another terminal -- it reads AGENTS.md and self-registers."
echo "  3. Start a feature: .tandem/bin/feature \"description of what to build\""
