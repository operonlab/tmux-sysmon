#!/usr/bin/env bash
# helpers.sh — shared option / runtime helpers for tmux-sysmon.
#
# Meant to be sourced, not executed. It intentionally does NOT use `set -e`:
# it is pulled into scripts that tmux calls from a status line or hook, where
# any non-zero exit is treated by tmux as an error. Failures degrade to empty
# output instead.

# get_tmux_option <option-name> <default-value>
# Read a global tmux user option, falling back to a default when unset/empty.
get_tmux_option() {
	option_name="$1"
	default_value="$2"
	option_value=$(tmux show-option -gqv "$option_name" 2>/dev/null)
	if [ -z "$option_value" ]; then
		printf '%s' "$default_value"
	else
		printf '%s' "$option_value"
	fi
}

# sysmon_runtime_dir
# Print the per-user runtime directory used for the metrics cache and the net
# sampling state. Created mode 0700. Refuses to use a pre-planted symlink
# (returns non-zero) so a hostile actor cannot redirect our writes.
sysmon_runtime_dir() {
	_base="${TMUX_TMPDIR:-/tmp}"
	_dir="${_base}/tmux-sysmon-$(id -u)"
	if [ ! -d "$_dir" ]; then
		# Create atomically at mode 0700 (no umask window where it is briefly
		# world-accessible). -m implies no -p, which is fine: TMUX_TMPDIR / /tmp
		# is the always-present parent and only the final component is ours.
		mkdir -m 700 "$_dir" 2>/dev/null || return 1
	fi
	# Reject a symlink standing in for the directory (anti pre-plant).
	if [ ! -d "$_dir" ] || [ -L "$_dir" ]; then
		return 1
	fi
	printf '%s' "$_dir"
}

# stat_mtime <path>
# Print the file modification time as an epoch second, portably across the
# BSD stat (macOS) and GNU stat (Linux) flag dialects. Prints 0 when missing.
stat_mtime() {
	_f="$1"
	if [ ! -e "$_f" ]; then
		printf '0'
		return 0
	fi
	# Order matters. GNU/busybox stat reads `-f` as "file system" (not "format"),
	# so `stat -f %m FILE` there prints a multi-line fs block to stdout and exits
	# non-zero — non-empty and non-numeric, which would sanitize to 0 below and
	# make every cache look stale. So try GNU `-c %Y` first (empty on macOS) and
	# only then fall back to BSD `-f %m` (empty on GNU).
	_m=$(stat -c %Y "$_f" 2>/dev/null)
	if [ -z "$_m" ]; then
		_m=$(stat -f %m "$_f" 2>/dev/null)
	fi
	case "$_m" in
		'' | *[!0-9]*) _m=0 ;;
	esac
	printf '%s' "$_m"
}

# run_capped <seconds> <command> [args...]
# Run a command with a hard time cap when a timeout helper is available
# (GNU coreutils `timeout`, or `gtimeout` from Homebrew coreutils). Falls back
# to running uncapped when neither exists (stock macOS). Used so a wedged
# provider cannot pin the background refresh forever on platforms that have it.
run_capped() {
	_secs="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout "$_secs" "$@"
	elif command -v gtimeout >/dev/null 2>&1; then
		gtimeout "$_secs" "$@"
	else
		"$@"
	fi
}
