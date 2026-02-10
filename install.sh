#!/usr/bin/env bash
set -euo pipefail

SKILL_DIR="${HOME}/.claude/skills"
TEMPLATE_DIR="${HOME}/claude-session-init-templates"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing claude-session-init..."

# 1. Create directories
mkdir -p "$SKILL_DIR"
mkdir -p "$TEMPLATE_DIR"

# 2. Copy skill file
cp "$SCRIPT_DIR/start.md" "$SKILL_DIR/start.md"
echo "  Skill installed to $SKILL_DIR/start.md"

# 3. Copy templates
cp "$SCRIPT_DIR/templates/"* "$TEMPLATE_DIR/"
echo "  Templates installed to $TEMPLATE_DIR/"

# 4. Update template path in the installed skill
sed -i "s|~/Hermes/CLAUDE-templates/|~/claude-session-init-templates/|g" "$SKILL_DIR/start.md"
echo "  Template paths updated in skill file"

echo ""
echo "Done. Use /start or /init in any Claude Code session to bootstrap a project."
