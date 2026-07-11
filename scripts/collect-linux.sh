#!/usr/bin/env bash
# collect-linux.sh — gather CPU / memory / disk / network for Linux.
#
# Prints one line of contract JSON to stdout (see docs/provider-contract.md).
# No `set -e`: this runs inside the status-line refresh path where a non-zero
# exit is treated as an error by tmux. On any failure a field degrades to zero.
#
# Usage: collect-linux.sh [disk-path]   (disk-path defaults to /)

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-collect.sh
. "${CURRENT_DIR}/lib-collect.sh"

disk_path="${1:-/}"

# ── CPU ──────────────────────────────────────────────────────────────────────
# Two /proc/stat samples ~0.2s apart; busy% = (dTotal - dIdle) / dTotal. The
# aggregate `cpu` line fields are: user nice system idle iowait irq softirq
# steal — idle time is idle + iowait.
c1=$(awk '/^cpu /{ print $2,$3,$4,$5,$6,$7,$8,$9; exit }' /proc/stat 2>/dev/null)
sleep 0.2
c2=$(awk '/^cpu /{ print $2,$3,$4,$5,$6,$7,$8,$9; exit }' /proc/stat 2>/dev/null)
cpu_pct=$(awk -v a="$c1" -v b="$c2" 'BEGIN {
	n = split(a, A, " "); m = split(b, B, " ")
	if (n < 5 || m < 5) { print "0.0"; exit }
	t1 = 0; for (i = 1; i <= n; i++) t1 += A[i]
	t2 = 0; for (i = 1; i <= m; i++) t2 += B[i]
	id1 = A[4] + A[5]; id2 = B[4] + B[5]
	dt = t2 - t1; di = id2 - id1
	if (dt <= 0) { print "0.0" }
	else { p = 100 * (dt - di) / dt; if (p < 0) p = 0; if (p > 100) p = 100; printf "%.1f", p }
}')

# ── MEMORY ───────────────────────────────────────────────────────────────────
# Prefer MemAvailable (kernel's own estimate). Fall back to free+buffers+cached
# on kernels too old to expose it.
mem=$(awk '
	/^MemTotal:/     { t = $2 }
	/^MemAvailable:/ { a = $2; ha = 1 }
	/^MemFree:/      { f = $2 }
	/^Buffers:/      { bu = $2 }
	/^Cached:/       { ca = $2 }
	END { if (ha != 1) a = f + bu + ca; printf "%d %d", t, a }' /proc/meminfo 2>/dev/null)
mem_total_kb=${mem%% *}
mem_avail_kb=${mem##* }
case "$mem_total_kb" in '' | *[!0-9]*) mem_total_kb=0 ;; esac
case "$mem_avail_kb" in '' | *[!0-9]*) mem_avail_kb=0 ;; esac
mem_used_kb=$((mem_total_kb - mem_avail_kb))
[ "$mem_used_kb" -lt 0 ] && mem_used_kb=0

# ── DISK ─────────────────────────────────────────────────────────────────────
disk=$(df -k -P "$disk_path" 2>/dev/null | awk 'NR==2 { print $2, $3 }')
disk_total_kb=${disk%% *}
disk_used_kb=${disk##* }

# ── NETWORK ──────────────────────────────────────────────────────────────────
# /proc/net/dev columns after "iface:" are rx: bytes packets ... (8) then tx:
# bytes packets ... (8). rx bytes = $2, tx bytes = $10 once the colon is split.
net=$(awk 'NR > 2 {
	gsub(/:/, " ")
	if ($1 == "lo") next
	rx += $2; tx += $10
} END { printf "%d %d", rx + 0, tx + 0 }' /proc/net/dev 2>/dev/null)
rx_bytes=${net%% *}
tx_bytes=${net##* }

sysmon_emit "$cpu_pct" "$mem_used_kb" "$mem_total_kb" \
	"$disk_used_kb" "$disk_total_kb" "$rx_bytes" "$tx_bytes"
