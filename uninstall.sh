#!/usr/bin/env bash
set -uo pipefail
BIN_DIR="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/htb-genmon"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/htb-genmon"
UNIT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/systemd/user"

echo "==> Removing htb-genmon"
systemctl --user disable --now htb-genmon.timer 2>/dev/null || true
rm -f "$UNIT_DIR/htb-genmon.timer" "$UNIT_DIR/htb-genmon.service"
systemctl --user daemon-reload 2>/dev/null || true
crontab -l 2>/dev/null | grep -v 'htb-cache' | crontab - 2>/dev/null || true
rm -f "$BIN_DIR/htb-cache"
rm -rf "$CACHE_DIR"

read -rp "Also delete the config at $CONF_DIR? [y/N] " a
[[ "$a" =~ ^[Yy]$ ]] && rm -rf "$CONF_DIR"

echo "Done. Remove the Generic Monitor widget from the panel by hand."
