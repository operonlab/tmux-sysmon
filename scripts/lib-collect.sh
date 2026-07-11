#!/usr/bin/env bash
# lib-collect.sh — shared metrics-emit logic for the platform collectors.
#
# Sourced by collect-macos.sh and collect-linux.sh. Centralizes the network
# rate delta (cached counters across refreshes) and the contract JSON so both
# platforms emit byte-for-byte the same schema. Not executed directly.

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "${_LIB_DIR}/helpers.sh"

# sysmon_emit <cpu_pct> <mem_used_kb> <mem_total_kb> <disk_used_kb> \
#             <disk_total_kb> <net_rx_bytes> <net_tx_bytes>
#
# Consumes raw counters gathered by a platform collector and prints one line of
# contract JSON to stdout. Network bytes are cumulative interface counters; the
# per-second rate is derived by differencing against the previous sample stored
# in <runtime-dir>/net.prev. The first run after a cold cache therefore reports
# a zero rate; subsequent runs report the real throughput.
sysmon_emit() {
	_cpu=${1:-0}
	_muk=${2:-0}
	_mtk=${3:-0}
	_duk=${4:-0}
	_dtk=${5:-0}
	_rx=${6:-0}
	_tx=${7:-0}

	# Sanitize integer inputs (cpu is allowed to carry a decimal).
	case "$_muk" in '' | *[!0-9]*) _muk=0 ;; esac
	case "$_mtk" in '' | *[!0-9]*) _mtk=0 ;; esac
	case "$_duk" in '' | *[!0-9]*) _duk=0 ;; esac
	case "$_dtk" in '' | *[!0-9]*) _dtk=0 ;; esac
	case "$_rx" in '' | *[!0-9]*) _rx=0 ;; esac
	case "$_tx" in '' | *[!0-9]*) _tx=0 ;; esac

	_dir=$(sysmon_runtime_dir 2>/dev/null) || _dir=""
	_now=$(date +%s 2>/dev/null)
	case "$_now" in '' | *[!0-9]*) _now=0 ;; esac

	_rxb=0
	_txb=0
	if [ -n "$_dir" ] && [ -f "$_dir/net.prev" ]; then
		IFS=' ' read -r _prx _ptx _pep <"$_dir/net.prev" 2>/dev/null
		case "$_prx" in '' | *[!0-9]*) _prx=-1 ;; esac
		case "$_ptx" in '' | *[!0-9]*) _ptx=-1 ;; esac
		case "$_pep" in '' | *[!0-9]*) _pep=0 ;; esac
		_dt=$((_now - _pep))
		if [ "$_dt" -gt 0 ] && [ "$_prx" -ge 0 ]; then
			# Guard against counter resets (interface reset / reboot).
			[ "$_rx" -ge "$_prx" ] && _rxb=$(((_rx - _prx) / _dt))
			[ "$_tx" -ge "$_ptx" ] && _txb=$(((_tx - _ptx) / _dt))
		fi
	fi

	if [ -n "$_dir" ]; then
		printf '%s %s %s\n' "$_rx" "$_tx" "$_now" >"$_dir/net.prev.tmp" 2>/dev/null &&
			mv "$_dir/net.prev.tmp" "$_dir/net.prev" 2>/dev/null
	fi

	_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)

	awk -v cpu="$_cpu" -v muk="$_muk" -v mtk="$_mtk" -v duk="$_duk" \
		-v dtk="$_dtk" -v rxb="$_rxb" -v txb="$_txb" -v ts="$_ts" '
		function hr(b) {
			if (b < 1024)            { return sprintf("%dB/s", b) }
			else if (b < 1048576)    { return sprintf("%dK/s", int(b / 1024)) }
			else if (b < 1073741824) { return sprintf("%.1fM/s", b / 1048576) }
			else                     { return sprintf("%.1fG/s", b / 1073741824) }
		}
		BEGIN {
			mug = muk / 1048576; mtg = mtk / 1048576
			mpct = (mtk > 0) ? (muk / mtk * 100) : 0
			dug = duk / 1048576; dtg = dtk / 1048576
			dpct = (dtk > 0) ? (duk / dtk * 100) : 0
			cp = cpu + 0; if (cp < 0) cp = 0; if (cp > 100) cp = 100
			nd = sprintf("\342\206\223 %s \342\206\221 %s", hr(rxb), hr(txb))
			printf "{\"ts\":\"%s\",\"cpu_pct\":%.1f,\"cpu_display\":\"%.0f%%\",\"mem_used_gb\":%.1f,\"mem_total_gb\":%.1f,\"mem_pct\":%.1f,\"mem_display\":\"%.1f/%.0fG %.0f%%\",\"net_rx_bps\":%d,\"net_tx_bps\":%d,\"net_display\":\"%s\",\"disk_used_gb\":%.1f,\"disk_total_gb\":%.1f,\"disk_pct\":%.1f,\"disk_display\":\"%.0f/%.0fG %.0f%%\"}\n", ts, cp, cp, mug, mtg, mpct, mug, mtg, mpct, rxb, txb, nd, dug, dtg, dpct, dug, dtg, dpct
		}'
}
