#!/bin/bash
# fagents-tandem setup — paired agent coordination for any project.
#
# Usage:
#   bash setup.sh                    # fresh install in current directory
#   bash setup.sh --update           # refresh scripts + show doc updates
#
# Creates .tandem/, launcher scripts, and installs tandem skill for Claude/Codex.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PWD}"
TANDEM_DIR="$PROJECT_DIR/.tandem"
UPDATE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update)   UPDATE=1; shift ;;
        --help|-h)
            echo "Usage: bash setup.sh [--update]"
            echo "  --update   Refresh scripts + show template changes for docs"
            exit 0
            ;;
        *) echo "Usage: bash setup.sh [--update]" >&2; exit 1 ;;
    esac
done

# ── Doc update helper ──
update_doc() {
    local template="$1" target="$2"
    local name artifact_dir artifact
    name=$(basename "$target")
    artifact_dir="$TANDEM_DIR/updates"
    artifact="$artifact_dir/$name"
    if [ ! -f "$target" ]; then
        cp "$template" "$target"
        echo "  Created $name"
    elif diff -q "$template" "$target" >/dev/null 2>&1; then
        echo "  $name: up to date"
    elif [ -f "$artifact" ] && diff -q "$template" "$artifact" >/dev/null 2>&1; then
        echo "  $name: update pending (merge .tandem/updates/$name first)"
    else
        rm -f "$artifact"
        echo "  $name differs from template:"
        echo ""
        diff -u "$target" "$template" || true
        echo ""
        if [ -t 0 ]; then
            read -rp "  Apply update to $name? [y/N] " answer || answer=""
            case "$answer" in [Yy])
                cp "$template" "$target"
                echo "  Updated $name"
                return
                ;; esac
        fi
        mkdir -p "$artifact_dir"
        cp "$template" "$artifact"
        echo "  Skipped. New version saved to .tandem/updates/$name"
        echo "    Merge into your $name, then: rm .tandem/updates/$name"
    fi
}

echo "=== fagents-tandem setup ==="
echo ""

# ── Create .tandem/ ──
echo "Setting up .tandem/..."
mkdir -p "$TANDEM_DIR/bin" "$TANDEM_DIR/handoff"

# Copy scripts (always refresh — these are canonical)
for script in handoff.sh wake.sh feature; do
    if [[ -f "$SCRIPT_DIR/bin/$script" ]]; then
        cp "$SCRIPT_DIR/bin/$script" "$TANDEM_DIR/bin/$script"
        chmod +x "$TANDEM_DIR/bin/$script"
    fi
done

# .gitignore
cat > "$TANDEM_DIR/.gitignore" << 'EOF'
*
!.gitignore
!bin/
!bin/**
EOF

echo "  Created .tandem/bin/ with handoff.sh, wake.sh, feature"

# ── Launcher scripts ──
for launcher in launch-claude launch-codex; do
    if [[ ! -f "$PROJECT_DIR/$launcher" ]]; then
        cp "$SCRIPT_DIR/templates/$launcher" "$PROJECT_DIR/$launcher"
        chmod +x "$PROJECT_DIR/$launcher"
        echo "  Created $launcher"
    else
        echo "  $launcher already exists -- skipping"
    fi
done

# ── Clean up stale tandem hooks from previous setup.sh versions ──

# Claude: remove only tandem-owned hook commands from SessionStart entries, keep the rest
CLAUDE_SETTINGS="$PROJECT_DIR/.claude/settings.json"
if [ -f "$CLAUDE_SETTINGS" ] && jq -e '.hooks.SessionStart' "$CLAUDE_SETTINGS" &>/dev/null; then
    jq '
        .hooks.SessionStart |= [.[] | .hooks |= [.[] | select(.command | test("handoff.sh register claude") | not)] | select(.hooks | length > 0)]
        | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$CLAUDE_SETTINGS" > "$CLAUDE_SETTINGS.tmp" && mv "$CLAUDE_SETTINGS.tmp" "$CLAUDE_SETTINGS"
    echo "  Cleaned stale Claude tandem hook"
fi

# Codex: same — remove only tandem-owned hook commands, keep the rest
CODEX_HOOKS="$PROJECT_DIR/.codex/hooks.json"
if [ -f "$CODEX_HOOKS" ] && jq -e '.hooks.SessionStart' "$CODEX_HOOKS" &>/dev/null; then
    jq '
        .hooks.SessionStart |= [.[] | .hooks |= [.[] | select(.command | test("handoff.sh register codex") | not)] | select(.hooks | length > 0)]
        | if (.hooks.SessionStart | length) == 0 then del(.hooks.SessionStart) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end
    ' "$CODEX_HOOKS" > "$CODEX_HOOKS.tmp" && mv "$CODEX_HOOKS.tmp" "$CODEX_HOOKS"
    if jq -e '. == {}' "$CODEX_HOOKS" &>/dev/null; then
        rm -f "$CODEX_HOOKS"
    fi
    echo "  Cleaned stale Codex tandem hook"
fi

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
    echo "  Installed Codex skill: ${CODEX_HOME:-~/.codex}/skills/tandem/"
fi

# ── Project docs ──
if [[ -n "$UPDATE" ]]; then
    echo ""
    echo "Checking docs for updates..."
    for tmpl in TEAM.md CLAUDE.md AGENTS.md; do
        update_doc "$SCRIPT_DIR/templates/$tmpl" "$PROJECT_DIR/$tmpl"
    done
else
    for tmpl in TEAM.md CLAUDE.md AGENTS.md; do
        if [[ ! -f "$PROJECT_DIR/$tmpl" ]]; then
            cp "$SCRIPT_DIR/templates/$tmpl" "$PROJECT_DIR/$tmpl"
            echo "  Created $tmpl"
        else
            echo "  $tmpl already exists -- skipping"
        fi
    done
fi

# ── Done ──
echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Start Claude Code: ./launch-claude"
echo "  2. Start Codex CLI:   ./launch-codex"
echo "  3. Start a feature:   .tandem/bin/feature \"description\""
