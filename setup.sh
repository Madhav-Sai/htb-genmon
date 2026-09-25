#!/usr/bin/env bash
# htb-genmon installer
# https://github.com/Madhav-Sai/htb-genmon

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/htb-genmon"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/htb-genmon"
UNIT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/systemd/user"
INTERVAL="${INTERVAL:-120}"

c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'
c_dim=$'\033[90m'; c_b=$'\033[1m'; c_0=$'\033[0m'

ok()   { printf '%s  ok %s %s\n'   "$c_ok"   "$c_0" "$*"; }
warn() { printf '%s  !! %s %s\n'   "$c_warn" "$c_0" "$*"; }
err()  { printf '%s  xx %s %s\n'   "$c_err"  "$c_0" "$*" >&2; }
step() { printf '\n%s==>%s %s%s%s\n' "$c_ok" "$c_0" "$c_b" "$*" "$c_0"; }

banner() {
cat <<'EOF'

  ┌──────────────────────────────────────────────┐
  │   htb-genmon                                 │
  │   active HackTheBox target in your Xfce bar  │
  └──────────────────────────────────────────────┘
EOF
}

# --------------------------------------------------------------- checks ----
check_deps() {
	step "Checking dependencies"
	local missing=()

	for c in awk sed iconv od cut; do
		command -v "$c" >/dev/null 2>&1 || missing+=("$c")
	done
	[ ${#missing[@]} -eq 0 ] && ok "core utilities present"

	if command -v htb-king >/dev/null 2>&1; then
		ok "htb-king at $(command -v htb-king)"
	else
		warn "htb-king not on PATH - set HTB_BIN in the config after install"
	fi

	if command -v xclip >/dev/null 2>&1; then
		ok "xclip present (click-to-copy enabled)"
	else
		warn "xclip missing - click-to-copy will not work"
		printf '     %sinstall with: sudo apt install xclip%s\n' "$c_dim" "$c_0"
	fi

	if [ -f /usr/lib/x86_64-linux-gnu/xfce4/panel/plugins/libgenmon.so ] \
	   || [ -f /usr/lib/xfce4/panel/plugins/libgenmon.so ] \
	   || dpkg -s xfce4-genmon-plugin >/dev/null 2>&1; then
		ok "xfce4-genmon-plugin installed"
	else
		warn "xfce4-genmon-plugin not detected"
		printf '     %sinstall with: sudo apt install xfce4-genmon-plugin%s\n' "$c_dim" "$c_0"
	fi

	if [ -n "$(fc-list : family 2>/dev/null | grep -i 'nerd font' | head -1 || true)" ]; then
		ok "a Nerd Font is installed"
	else
		warn "no Nerd Font found - OS glyphs will render as boxes"
		printf '     %ssee: https://www.nerdfonts.com/font-downloads%s\n' "$c_dim" "$c_0"
	fi

	if [ ${#missing[@]} -gt 0 ]; then
		err "missing required tools: ${missing[*]}"
		exit 1
	fi
}

# -------------------------------------------------------------- install ----
install_files() {
	step "Installing"

	mkdir -p "$BIN_DIR" "$CONF_DIR" "$CACHE_DIR"
	install -m 0755 "$SRC/bin/htb-cache" "$BIN_DIR/htb-cache"
	ok "$BIN_DIR/htb-cache"

	if [ -e "$CONF_DIR/config" ]; then
		ok "config already exists, left untouched"
	else
		install -m 0644 "$SRC/config.example" "$CONF_DIR/config"
		ok "$CONF_DIR/config"
	fi

	case ":$PATH:" in
		*":$BIN_DIR:"*) : ;;
		*) warn "$BIN_DIR is not on your PATH"
		   # shellcheck disable=SC2016  # print $HOME literally for the user to copy
		   printf '     %sadd: export PATH="$HOME/.local/bin:$PATH"%s\n' "$c_dim" "$c_0" ;;
	esac
}

# ------------------------------------------------------------ scheduling ---
install_timer() {
	step "Setting up the refresh schedule (every ${INTERVAL}s)"

	if command -v systemctl >/dev/null 2>&1 && systemctl --user show-environment >/dev/null 2>&1; then
		mkdir -p "$UNIT_DIR"
		sed "s|@BIN@|$BIN_DIR/htb-cache|g" "$SRC/systemd/htb-genmon.service" \
			> "$UNIT_DIR/htb-genmon.service"
		sed "s|@INTERVAL@|$INTERVAL|g" "$SRC/systemd/htb-genmon.timer" \
			> "$UNIT_DIR/htb-genmon.timer"
		systemctl --user daemon-reload
		systemctl --user enable --now htb-genmon.timer >/dev/null 2>&1
		ok "systemd user timer enabled"
		printf '     %sstatus: systemctl --user status htb-genmon.timer%s\n' "$c_dim" "$c_0"
		return
	fi

	if command -v crontab >/dev/null 2>&1; then
		local job="*/$(( INTERVAL / 60 < 1 ? 1 : INTERVAL / 60 )) * * * * $BIN_DIR/htb-cache"
		( crontab -l 2>/dev/null | grep -v 'htb-cache' ; echo "$job" ) | crontab -
		ok "cron job installed"
		return
	fi

	warn "no systemd or cron found - schedule $BIN_DIR/htb-cache yourself"
}

# ----------------------------------------------------------- panel setup ---
add_panel_plugin() {
	step "Adding the panel widget"

	if ! command -v xfconf-query >/dev/null 2>&1; then
		warn "xfconf-query not found - add the widget manually (see below)"
		return 1
	fi
	if ! xfconf-query -c xfce4-panel -l >/dev/null 2>&1; then
		warn "Xfce panel not reachable from this session - add it manually"
		return 1
	fi

	local before after id
	before=$(xfconf-query -c xfce4-panel -l | grep -c '^/plugins/plugin-[0-9]*$' || true)
	xfce4-panel --add=genmon >/dev/null 2>&1 || {
		warn "could not add the genmon plugin automatically"
		return 1
	}
	sleep 2
	after=$(xfconf-query -c xfce4-panel -l | grep -c '^/plugins/plugin-[0-9]*$' || true)

	if [ "$after" -le "$before" ]; then
		warn "plugin count unchanged - add it manually"
		return 1
	fi

	id=$(xfconf-query -c xfce4-panel -l \
		| grep -o '^/plugins/plugin-[0-9]*$' \
		| sed 's|.*-||' | sort -n | tail -1)

	local font
	font=$(fc-list : family 2>/dev/null | tr ',' '\n' | grep -i 'nerd font' \
		| grep -iv 'mono$' | sed -n '1p' | sed 's/^ *//;s/ *$//')
	[ -n "$font" ] || font="JetBrainsMono Nerd Font"

	xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/command" \
		-n -t string -s "cat $CACHE_DIR/status" 2>/dev/null || \
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/command" \
		-s "cat $CACHE_DIR/status"
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/use-label" \
		-n -t bool -s false 2>/dev/null || true
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/update-period" \
		-n -t int -s 10000 2>/dev/null || true
	xfconf-query -c xfce4-panel -p "/plugins/plugin-$id/font" \
		-n -t string -s "$font 11" 2>/dev/null || true

	ok "genmon widget added as plugin-$id (font: $font 11)"
	return 0
}

manual_instructions() {
	cat <<EOF

  ${c_b}ACTION REQUIRED - add the widget to your panel yourself:${c_0}

    1. Right-click your panel  ->  Panel  ->  Add New Items
    2. Choose ${c_b}Generic Monitor${c_0} and click Add, then Close
    3. Right-click the new widget  ->  Properties
    4. Paste this into the ${c_b}Command${c_0} field:

           ${c_ok}${c_b}cat $CACHE_DIR/status${c_0}

    5. Untick ${c_b}Label${c_0}
    6. Set ${c_b}Period${c_0} to ${c_b}10${c_0}
    7. Click the font button and pick ${c_b}JetBrainsMono Nerd Font 11${c_0}
       (without a Nerd Font the OS logo shows as an empty box)
    8. Save

  Nothing appears until you do this. The widget only reads the cache
  file - it will show your machine as soon as the command is set.

EOF
}

# ------------------------------------------------------------------ main ---
banner
check_deps
install_files
install_timer

step "First run"
if "$BIN_DIR/htb-cache"; then
	ok "cache written to $CACHE_DIR/status"
	printf '\n%s  panel will show:%s\n\n' "$c_dim" "$c_0"
	sed -n '1p' "$CACHE_DIR/status" \
		| sed -e 's/<[^>]*>//g' -e 's/&#9679;/*/g' -e 's/&amp;/\&/g' -e 's/^/    /'
	printf '\n'
else
	warn "first run failed - check that htb-king works and a machine is spawned"
fi

if [ "${NO_PANEL:-0}" != "1" ]; then
	add_panel_plugin || manual_instructions
else
	manual_instructions
fi

step "Done"
cat <<EOF
  config    $CONF_DIR/config
  script    $BIN_DIR/htb-cache
  cache     $CACHE_DIR/status
  refresh   every ${INTERVAL}s

  Edit colors, spacing and visible fields in the config file,
  then run htb-cache once to see the change immediately.

  Uninstall with: ./uninstall.sh
EOF
