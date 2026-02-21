#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"

mkdir -p "$BIN_DIR"

# Create symlink
ln -sf "${SCRIPT_DIR}/orch" "${BIN_DIR}/orch"
echo "Linked: ${BIN_DIR}/orch -> ${SCRIPT_DIR}/orch"

# Copy default config if user config doesn't exist
USER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/orch/orch.conf"
if [[ ! -f "$USER_CONFIG" ]]; then
    mkdir -p "$(dirname "$USER_CONFIG")"
    cp "${SCRIPT_DIR}/config/orch.conf" "$USER_CONFIG"
    echo "Config: $USER_CONFIG (created from defaults)"
else
    echo "Config: $USER_CONFIG (already exists, not overwritten)"
fi

# Create data dirs
mkdir -p "${HOME}/.local/share/orch"

# Verify PATH
if [[ ":$PATH:" != *":${BIN_DIR}:"* ]]; then
    echo ""
    echo "NOTE: ${BIN_DIR} is not in your PATH. Add to your shell profile:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done. Run 'orch --help' to get started."
