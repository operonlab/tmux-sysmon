#!/usr/bin/env bash
# smoke.sh — headless functional test for tmux-sysmon.
#
# Two parts:
#   1. Collector functional smoke — really runs the platform collector twice and
#      asserts the contract JSON is complete and well-formed. This is the part
#      that runs "for real" on the Linux CI runner (collect-linux.sh).
#   2. tmux integration — on a PRIVATE `tmux -L` socket only, never the default
#      server: sources sysmon.tmux, checks the status tokens are rewritten into
#      #() calls, that sysmon.sh returns a value, and that teardown reverses it.
#
# Everything is isolated: TMUX_TMPDIR is redirected to a scratch dir so neither
# the metrics cache nor any tmux socket can touch a real environment.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t sysmon)"
export TMUX_TMPDIR="$WORK"
RTD="${WORK}/tmux-sysmon-$(id -u)"

SOCKETS=""
FAILS=0

cleanup() {
	for s in $SOCKETS; do
		tmux -L "$s" kill-server 2>/dev/null || true
	done
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

has_field() {
	# has_field <json> <key>  → echoes yes/no
	_pat="\"$2\":"
	case "$1" in
		*"$_pat"*) echo "yes" ;;
		*) echo "no" ;;
	esac
}

contains() {
	# contains <haystack> <needle>  → echoes yes/no
	case "$1" in
		*"$2"*) echo "yes" ;;
		*) echo "no" ;;
	esac
}

is_json_obj() {
	# is_json_obj <string>  → echoes yes/no
	case "$1" in
		'{'*'}') echo "yes" ;;
		*) echo "no" ;;
	esac
}

file_exists() {
	# file_exists <path>  → echoes yes/no
	[ -f "$1" ] && echo "yes" || echo "no"
}

echo "tmux version: $(tmux -V 2>/dev/null || echo 'not installed')"
echo "platform: $(uname -s)"

# ══════════════════════ Part 1: collector functional smoke ══════════════════════
echo "── Part 1: platform collector emits a complete contract JSON"
case "$(uname -s)" in
	Linux) COLLECT="${REPO_DIR}/scripts/collect-linux.sh" ;;
	Darwin) COLLECT="${REPO_DIR}/scripts/collect-macos.sh" ;;
	*) COLLECT="" ;;
esac

if [ -n "$COLLECT" ]; then
	j1="$("$COLLECT" / 2>/dev/null)"
	sleep 1
	j2="$("$COLLECT" / 2>/dev/null)"

	check "first run produced JSON object" "yes" "$(is_json_obj "$j1")"
	check "second run produced JSON object" "yes" "$(is_json_obj "$j2")"

	for key in cpu_display mem_display disk_display net_display \
		cpu_pct mem_used_gb mem_total_gb mem_pct \
		disk_used_gb disk_total_gb disk_pct \
		net_rx_bps net_tx_bps ts; do
		check "field present: $key" "yes" "$(has_field "$j2" "$key")"
	done

	cpu=$(printf '%s' "$j2" | sed -n 's/.*"cpu_pct":\([0-9.][0-9.]*\).*/\1/p' | head -1)
	check "cpu_pct in 0..100" "yes" "$(awk -v c="$cpu" 'BEGIN{ print (c!="" && c>=0 && c<=100) ? "yes" : "no" }')"

	# net_display always ends each rate with a "/s" unit (B/s, K/s, M/s, G/s).
	check "net_display carries a rate unit" "yes" "$(contains "$j2" '/s')"

	check "net sampling state file written" "yes" "$(file_exists "${RTD}/net.prev")"
else
	echo "  SKIP: no built-in collector for $(uname -s) (a custom @sysmon-provider is required there)"
fi

# ══════════════════════ Part 2: tmux integration (isolated socket) ══════════════════════
echo "── Part 2: sysmon.tmux rewrites status tokens; teardown.sh reverses it"
SOCK="sysmontest$$"
SOCKETS="$SOCK"
tmux -L "$SOCK" -f /dev/null new-session -d -s main -x 200 -y 50
tmux -L "$SOCK" set-option -g status-right 'load #{sysmon_cpu} mem #{sysmon_mem} disk #{sysmon_disk} net #{sysmon_net}'
tmux -L "$SOCK" set-option -g @sysmon-interval 2

tmux -L "$SOCK" run-shell "'${REPO_DIR}/sysmon.tmux'"
sleep 0.4
sr="$(tmux -L "$SOCK" show-option -gqv status-right)"

check "cpu token rewritten to #() call" "yes" "$(contains "$sr" "sysmon.sh' cpu)")"
check "mem token rewritten to #() call" "yes" "$(contains "$sr" "sysmon.sh' mem)")"
check "disk token rewritten to #() call" "yes" "$(contains "$sr" "sysmon.sh' disk)")"
check "net token rewritten to #() call" "yes" "$(contains "$sr" "sysmon.sh' net)")"
check "no raw #{sysmon_*} token remains" "no" "$(contains "$sr" '#{sysmon_')"

# sysmon.sh read path: warm the cache deterministically, then read through it via
# run-shell so the script's internal `tmux` calls target THIS private socket.
if [ -n "$COLLECT" ]; then
	mkdir -p "$RTD" 2>/dev/null
	"$COLLECT" / >"${RTD}/metrics.json" 2>/dev/null
	tmux -L "$SOCK" run-shell "'${REPO_DIR}/scripts/sysmon.sh' cpu > '${WORK}/read.txt' 2>&1"
	sleep 0.5
	val="$(head -1 "${WORK}/read.txt" 2>/dev/null)"
	check "sysmon.sh returns a cpu display value" "yes" "$(contains "$val" '%')"
fi

# Let any warm-up background refresh finish before tearing down.
sleep 1.5
tmux -L "$SOCK" run-shell "'${REPO_DIR}/scripts/teardown.sh'"
sleep 0.4
sr2="$(tmux -L "$SOCK" show-option -gqv status-right)"

check "teardown restores raw cpu token" "yes" "$(contains "$sr2" '#{sysmon_cpu}')"
check "teardown removed the #() call" "no" "$(contains "$sr2" "sysmon.sh' cpu)")"
check "teardown cleared metrics cache" "no" "$(file_exists "${RTD}/metrics.json")"

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "ALL SMOKE CHECKS PASSED"
	exit 0
else
	echo "SMOKE FAILURES: $FAILS"
	exit 1
fi
