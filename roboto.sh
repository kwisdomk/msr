#!/usr/bin/env bash
# Mr. Roboto v2.0 - Linux/macOS launcher
# Requires: PowerShell 7+ (pwsh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh &>/dev/null; then
    echo "[ERROR] pwsh (PowerShell 7+) not found."
    echo "  Install: https://aka.ms/install-powershell"
    exit 1
fi

exec pwsh -ExecutionPolicy Bypass -File "$SCRIPT_DIR/roboto.ps1" "$@"
