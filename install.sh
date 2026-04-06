#!/bin/bash
# Install the /coffee skill for Claude Code
set -e

SKILL_DIR="$HOME/.claude/skills/coffee"

mkdir -p "$SKILL_DIR"

# If running from a cloned repo, copy locally
if [ -f "SKILL.md" ]; then
  cp SKILL.md "$SKILL_DIR/SKILL.md"
  echo "Installed /coffee skill from local file."
else
  # Otherwise fetch from GitHub
  curl -fsSL \
    https://raw.githubusercontent.com/cnighswonger/claude-code-coffee/main/SKILL.md \
    -o "$SKILL_DIR/SKILL.md"
  echo "Installed /coffee skill from GitHub."
fi

echo "Restart Claude Code to pick up the new skill."
echo "Usage: /coffee 30"
