#!/usr/bin/env bash
# teardown.sh — cleanly remove tmux-sysmon from a running server.
#
# Reverses the status-line interpolation (turning the #() calls back into the
# original #{sysmon_*} tokens), clears the plugin options, and deletes the
# runtime cache directory. Safe to run more than once.

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/helpers.sh"

SYSMON="${CURRENT_DIR}/sysmon.sh"

tok_cpu='#{sysmon_cpu}'
tok_mem='#{sysmon_mem}'
tok_disk='#{sysmon_disk}'
tok_net='#{sysmon_net}'
rep_cpu="#('${SYSMON}' cpu)"
rep_mem="#('${SYSMON}' mem)"
rep_disk="#('${SYSMON}' disk)"
rep_net="#('${SYSMON}' net)"

restore_status_option() {
	_opt="$1"
	_val="$(tmux show-option -gqv "$_opt")"
	_new="$_val"
	_new="${_new//"$rep_cpu"/$tok_cpu}"
	_new="${_new//"$rep_mem"/$tok_mem}"
	_new="${_new//"$rep_disk"/$tok_disk}"
	_new="${_new//"$rep_net"/$tok_net}"
	if [ "$_new" != "$_val" ]; then
		tmux set-option -gq "$_opt" "$_new"
	fi
}

restore_status_option "status-left"
restore_status_option "status-right"

# Clear plugin options (harmless if never set).
for opt in @sysmon-interval @sysmon-provider @sysmon-disk-path; do
	tmux set-option -gu "$opt" 2>/dev/null || true
done

# Remove the per-user runtime cache directory (a namespaced path we own).
base="${TMUX_TMPDIR:-/tmp}"
runtime="${base}/tmux-sysmon-$(id -u)"
case "$runtime" in
	*/tmux-sysmon-*) [ -d "$runtime" ] && [ ! -L "$runtime" ] && rm -rf "$runtime" ;;
esac

tmux display-message "tmux-sysmon removed (status tokens restored, cache cleared)" 2>/dev/null || true
