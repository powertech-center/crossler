#!/usr/bin/env bash
# Creates a symlink CLAUDE.md in the project root pointing to .claude/CLAUDE.md

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
TARGET="$SCRIPT_DIR/CLAUDE.md"
LINK="$ROOT_DIR/CLAUDE.md"

if [ -e "$LINK" ]; then
    echo "CLAUDE.md already exists in the project root."
else
    ln -s "$TARGET" "$LINK"
fi
