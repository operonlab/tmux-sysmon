#!/usr/bin/env bash
# collect-macos.sh — gather CPU / memory / disk / network for macOS.
#
# Prints one line of contract JSON to stdout (see docs/provider-contract.md).
# No `set -e`: this runs inside the status-line refresh path where a non-zero
# exit is treated as an error by tmux. On any failure a field degrades to zero.
#
# Usage: collect-macos.sh [disk-path]   (disk-path defaults to /)

set -u

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib-collect.sh
. "${CURRENT_DIR}/lib-collect.sh"

disk_path="${1:-/}"

# ── CPU ──────────────────────────────────────────────────────────────────────
# `top -l 2` takes two samples ~1s apart; the FIRST is since-boot and useless,
# the SECOND is a true instantaneous reading. `-n 0` skips the process list so
# the sample is cheap. Busy% = 100 - idle%.
cpu_pct=$(top -l 2 -n 0 2>/dev/null | awk '
	/CPU usage/ { line = $0 }
	END {
		if (match(line, /[0-9.]+% idle/)) {
			s = substr(line, RSTART, RLENGTH); gsub(/% idle/, "", s)
			p = 100 - s; if (p < 0) p = 0; if (p > 100) p = 100
			printf "%.1f", p
		} else { print "0.0" }
	}')

# ── MEMORY ───────────────────────────────────────────────────────────────────
# Total from hw.memsize; "used" = (active + wired + compressed) pages, i.e. the
# Activity-Monitor-style Memory Used figure.
pagesize=$(sysctl -n hw.pagesize 2>/dev/null)
case "$pagesize" in '' | *[!0-9]*) pagesize=4096 ;; esac
memsize=$(sysctl -n hw.memsize 2>/dev/null)
case "$memsize" in '' | *[!0-9]*) memsize=0 ;; esac
mem_total_kb=$((memsize / 1024))

used_pages=$(vm_stat 2>/dev/null | awk '
	/Pages active/          { gsub(/\./, "", $3); act = $3 }
	/Pages wired down/      { gsub(/\./, "", $4); wir = $4 }
	/occupied by compressor/ { gsub(/\./, "", $5); comp = $5 }
	END { printf "%d", act + wir + comp }')
case "$used_pages" in '' | *[!0-9]*) used_pages=0 ;; esac
mem_used_kb=$((used_pages * pagesize / 1024))

# ── DISK ─────────────────────────────────────────────────────────────────────
disk=$(df -k -P "$disk_path" 2>/dev/null | awk 'NR==2 { print $2, $3 }')
disk_total_kb=${disk%% *}
disk_used_kb=${disk##* }

# ── NETWORK ──────────────────────────────────────────────────────────────────
# Sum the per-interface link-layer byte counters (excluding loopback). The
# trailing seven columns are fixed (Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll)
# so Ibytes = NF-4 and Obytes = NF-1 regardless of whether the Address column
# is populated.
net=$(netstat -ibn 2>/dev/null | awk '
	NR > 1 && $1 != "lo0" && $3 ~ /^<Link/ { rx += $(NF - 4); tx += $(NF - 1) }
	END { printf "%d %d", rx + 0, tx + 0 }')
rx_bytes=${net%% *}
tx_bytes=${net##* }

sysmon_emit "$cpu_pct" "$mem_used_kb" "$mem_total_kb" \
	"$disk_used_kb" "$disk_total_kb" "$rx_bytes" "$tx_bytes"
