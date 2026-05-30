#!/usr/bin/env bash
# wlab — install wlab.sh to PATH
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)

chmod +x "$REPO/wlab.sh"
mkdir -p "$HOME/.local/bin"
ln -sf "$REPO/wlab.sh" "$HOME/.local/bin/wlab"
echo "[wlab] symlinked → ~/.local/bin/wlab"
