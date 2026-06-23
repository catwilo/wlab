#!/usr/bin/env bash
# wlab — install wlab.sh to PATH (atomic copy, never symlink)
set -euo pipefail
REPO=$(cd "$(dirname "$0")" && pwd)

chmod +x "$REPO/wlab.sh"
mkdir -p "$HOME/.local/bin"

_install_atomic() {
    local src="$1" dst="$2"
    local dstdir tmp
    dstdir="$(dirname "$dst")"
    mkdir -p "$dstdir"
    tmp="$(mktemp -d "$dstdir/.wlab-tmp.XXXXXX")/wlab"
    if cp -f "$src" "$tmp"; then
        chmod +x "$tmp"
        rm -f "$dst"
        mv -f "$tmp" "$dst" && echo "[wlab] installed -> $dst" || { echo "[wlab] ERROR: mv failed" >&2; exit 1; }
    else
        echo "[wlab] ERROR: cp failed" >&2; exit 1
    fi
    rm -rf "$(dirname "$tmp")" 2>/dev/null || true
}

_install_atomic "$REPO/wlab.sh" "$HOME/.local/bin/wlab"
