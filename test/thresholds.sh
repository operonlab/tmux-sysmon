#!/usr/bin/env bash
# thresholds.sh — regression guard for severity-based coloring.
#
# sysmon.sh, when @sysmon-thresholds is on, must wrap a metric's display value
# in the warn/crit tmux style picked from the metric's cached numeric percent.
# This test plants a synthetic (but contract-shaped) metrics.json with a known
# cpu_pct, then reads it back through sysmon.sh on a PRIVATE `tmux -L` socket so
# the script's internal option reads target THIS server, never the default one.
# The cache is written fresh with @sysmon-interval huge, so the non-blocking
# reader serves the planted pct and no background collector overwrites it.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t sysmon-thr)"
export TMUX_TMPDIR="$WORK"
RTD="${WORK}/tmux-sysmon-$(id -u)"
CACHE="${RTD}/metrics.json"

SOCK="sysmonthr$$"
FAILS=0

cleanup() {
	tmux -L "$SOCK" kill-server 2>/dev/null || true
	rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

check() {
	# check <label> <expected> <actual>
	if [ "$2" = "$3" ]; then
		echo "  PASS: $1 (= $3)"
	else
		echo "  FAIL: $1 — expected [$2] got [$3]"
		FAILS=$((FAILS + 1))
	fi
}

contains() {
	# contains <haystack> <needle>  → echoes yes/no
	case "$1" in
		*"$2"*) echo "yes" ;;
		*) echo "no" ;;
	esac
}

# Write a contract-shaped cache with a chosen cpu_pct / cpu_display.
plant_cache() {
	mkdir -p "$RTD" 2>/dev/null
	printf '{"ts":"2026-01-01T00:00:00Z","cpu_pct":%s,"cpu_display":"%s","mem_pct":10.0,"mem_display":"1/8G 10%%","net_display":"x","disk_pct":50.0,"disk_display":"5/10G 50%%"}\n' \
		"$1" "$2" >"$CACHE"
}

# Read cpu through sysmon.sh on the private socket; echo its output.
read_cpu() {
	tmux -L "$SOCK" run-shell "'${REPO_DIR}/scripts/sysmon.sh' cpu > '${WORK}/out.txt' 2>&1"
	sleep 0.2
	head -1 "${WORK}/out.txt" 2>/dev/null
}

WARN_STYLE='#[fg=#f9e2af]'
CRIT_STYLE='#[fg=#f38ba8]'

echo "tmux version: $(tmux -V 2>/dev/null || echo 'not installed')"

tmux -L "$SOCK" -f /dev/null new-session -d -s main -x 200 -y 50
tmux -L "$SOCK" set-option -g @sysmon-interval 999999

# ── 1. thresholds OFF → plain, even when hot (zero behavior change) ──
tmux -L "$SOCK" set-option -g @sysmon-thresholds off
plant_cache 90.0 "90%"
out="$(read_cpu)"
check "off: value present" "yes" "$(contains "$out" '90%')"
check "off: no style wrapped" "no" "$(contains "$out" "$CRIT_STYLE")"
check "off: no #[default] wrapped" "no" "$(contains "$out" '#[default]')"

# ── 2. thresholds ON, defaults (cpu warn 60 / crit 85) ──
tmux -L "$SOCK" set-option -g @sysmon-thresholds on

# crit tier: 90 >= 85
plant_cache 90.0 "90%"
out="$(read_cpu)"
check "crit: crit style wraps value" "yes" "$(contains "$out" "${CRIT_STYLE}90%#[default]")"
check "crit: not warn style" "no" "$(contains "$out" "$WARN_STYLE")"

# warn tier: 70 is >= 60 and < 85
plant_cache 70.0 "70%"
out="$(read_cpu)"
check "warn: warn style wraps value" "yes" "$(contains "$out" "${WARN_STYLE}70%#[default]")"
check "warn: not crit style" "no" "$(contains "$out" "$CRIT_STYLE")"

# ok tier: 10 < 60 → plain
plant_cache 10.0 "10%"
out="$(read_cpu)"
check "ok: value present" "yes" "$(contains "$out" '10%')"
check "ok: no style wrapped" "no" "$(contains "$out" '#[')"

# ── 3. custom thresholds are honored (crit lowered to 50) ──
tmux -L "$SOCK" set-option -g @sysmon-cpu-crit 50
plant_cache 55.0 "55%"
out="$(read_cpu)"
check "custom crit 50: 55 wraps crit style" "yes" "$(contains "$out" "${CRIT_STYLE}55%#[default]")"

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "ALL THRESHOLD CHECKS PASSED"
	exit 0
else
	echo "THRESHOLD FAILURES: $FAILS"
	exit 1
fi
