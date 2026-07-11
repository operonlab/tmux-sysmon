#!/usr/bin/env bash
# sysmon.tmux — TPM entry point for tmux-sysmon.
#
# TPM sources this once at tmux start. It rewrites any #{sysmon_cpu},
# #{sysmon_mem}, #{sysmon_disk} and #{sysmon_net} tokens found in status-left /
# status-right into non-blocking #() calls to scripts/sysmon.sh, then warms the
# cache with one background refresh so the first render has data sooner.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${CURRENT_DIR}/scripts/helpers.sh"

SYSMON="${CURRENT_DIR}/scripts/sysmon.sh"

# Literal placeholder tokens the user writes in their status string.
tok_cpu='#{sysmon_cpu}'
tok_mem='#{sysmon_mem}'
tok_disk='#{sysmon_disk}'
tok_net='#{sysmon_net}'

# Replacement #() calls. The script path is single-quoted so a path containing
# spaces still runs correctly under tmux's `/bin/sh -c`.
rep_cpu="#('${SYSMON}' cpu)"
rep_mem="#('${SYSMON}' mem)"
rep_disk="#('${SYSMON}' disk)"
rep_net="#('${SYSMON}' net)"

do_interpolation() {
	_in="$1"
	_in="${_in//"$tok_cpu"/$rep_cpu}"
	_in="${_in//"$tok_mem"/$rep_mem}"
	_in="${_in//"$tok_disk"/$rep_disk}"
	_in="${_in//"$tok_net"/$rep_net}"
	printf '%s' "$_in"
}

update_status_option() {
	_opt="$1"
	_val="$(tmux show-option -gqv "$_opt")"
	_new="$(do_interpolation "$_val")"
	if [ "$_new" != "$_val" ]; then
		tmux set-option -gq "$_opt" "$_new"
	fi
}

update_status_option "status-left"
update_status_option "status-right"

# Warm the cache in the background so the first status render is not blank.
( "$SYSMON" cpu >/dev/null 2>&1 ) </dev/null >/dev/null 2>&1 &
