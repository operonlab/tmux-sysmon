#!/usr/bin/env bash
# sysmon.sh — non-blocking status-line reader for one metric field.
#
# tmux calls this from `#(...)` on every status refresh, once per placeholder.
# The contract is strictly non-blocking: it only ever READS the cached JSON and
# prints the requested `*_display` string. When the cache is older than the
# configured interval it kicks off a fully-detached background refresh (a single
# collector run behind an atomic lock) and returns the stale value immediately.
#
# No `set -e`: a non-zero exit here would surface as an error in the status bar.
# Any failure degrades to empty output.
#
# Usage: sysmon.sh <cpu|mem|disk|net>

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/helpers.sh"

field="${1:-}"
case "$field" in
	cpu | mem | disk | net) : ;;
	*) exit 0 ;;
esac

dir=$(sysmon_runtime_dir 2>/dev/null) || exit 0
cache="$dir/metrics.json"

interval=$(get_tmux_option "@sysmon-interval" "5")
case "$interval" in '' | *[!0-9]*) interval=5 ;; esac
[ "$interval" -lt 1 ] && interval=1

provider=$(get_tmux_option "@sysmon-provider" "")
disk_path=$(get_tmux_option "@sysmon-disk-path" "/")

now=$(date +%s 2>/dev/null)
case "$now" in '' | *[!0-9]*) now=0 ;; esac

# Time cap for the background collector / provider. Kept a little above the
# interval so a normal ~1s collector never trips it, but a wedged provider
# eventually releases (only where a `timeout` helper exists — see run_capped).
cap=$((interval + 3))
[ "$cap" -lt 5 ] && cap=5

run_refresh() {
	_tmp="$cache.$$.tmp"
	_out=""
	if [ -n "$provider" ]; then
		_out=$(run_capped "$cap" sh -c "$provider" 2>/dev/null)
	else
		case "$(uname -s)" in
			Darwin) _out=$(run_capped "$cap" "$CURRENT_DIR/collect-macos.sh" "$disk_path" 2>/dev/null) ;;
			Linux) _out=$(run_capped "$cap" "$CURRENT_DIR/collect-linux.sh" "$disk_path" 2>/dev/null) ;;
			*) _out="" ;;
		esac
	fi
	# Only replace the cache when we got something JSON-shaped. On timeout or
	# failure the old cache is left in place so the last-known value keeps showing.
	case "$_out" in
		'{'*) printf '%s' "$_out" >"$_tmp" 2>/dev/null && mv "$_tmp" "$cache" 2>/dev/null ;;
		*) rm -f "$_tmp" 2>/dev/null ;;
	esac
}

maybe_refresh() {
	_mtime=$(stat_mtime "$cache")
	_age=$((now - _mtime))
	[ "$_age" -lt "$interval" ] && return 0

	_lock="$dir/refresh.lock"
	# Steal a lock left behind by a crashed / wedged refresh.
	_steal=$((interval * 6))
	[ "$_steal" -lt 30 ] && _steal=30
	if [ -d "$_lock" ]; then
		_lmt=$(stat_mtime "$_lock")
		[ $((now - _lmt)) -ge "$_steal" ] && rmdir "$_lock" 2>/dev/null
	fi

	# mkdir is atomic: exactly one caller wins and spawns the refresh.
	if mkdir "$_lock" 2>/dev/null; then
		(
			trap '' HUP
			run_refresh
			rmdir "$_lock" 2>/dev/null
		) </dev/null >/dev/null 2>&1 &
	fi
}

maybe_refresh

# Emit the requested display string (empty when the cache is not yet warm).
if [ -f "$cache" ]; then
	sed -n 's/.*"'"${field}_display"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
		"$cache" 2>/dev/null | head -1
fi
exit 0
