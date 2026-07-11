#!/usr/bin/env bash
# stat-mtime.sh — regression guard for the cross-platform stat_mtime() helper.
#
# The interval throttle and the mkdir refresh lock both depend on stat_mtime()
# returning a real epoch mtime on BOTH stat dialects (BSD/macOS and GNU/busybox
# Linux). On GNU/busybox stat, `-f` means "file system" (not "format"), so a
# `stat -f %m FILE` first-try prints a multi-line filesystem block to stdout and
# exits non-zero — non-empty, non-numeric, which sanitizes to 0. A 0 mtime makes
# every cache look infinitely stale, defeating the throttle and the lock, so the
# collector re-runs on every status redraw. The functional smoke suite cannot
# catch this: it warms the cache first, so it never exercises the stale path
# against a GNU stat. This test does, by shimming a GNU-style `stat` onto PATH.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=scripts/helpers.sh
. "${REPO_DIR}/scripts/helpers.sh"

WORK="$(mktemp -d 2>/dev/null || mktemp -d -t sysmon-stat)"
FAILS=0
cleanup() { rm -rf "$WORK" 2>/dev/null || true; }
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

f="${WORK}/probe"
: >"$f"

# Real mtime, obtained with whichever native dialect works on this host.
real=$(stat -c %Y "$f" 2>/dev/null)
[ -z "$real" ] && real=$(stat -f %m "$f" 2>/dev/null)

echo "platform: $(uname -s) — probe mtime: ${real}"

# ── 1. Native dialect: stat_mtime matches the host's own stat ──
check "native stat_mtime matches real mtime" "$real" "$(stat_mtime "$f")"

# ── 2. GNU/busybox dialect (simulated): -c works, -f %m prints an fs block ──
# A synthetic `stat` that behaves like GNU/busybox regardless of the host, so
# the guard reproduces the Linux failure even when run on macOS.
SHIM="${WORK}/bin"
mkdir -p "$SHIM"
cat >"${SHIM}/stat" <<EOF
#!/bin/sh
if [ "\$1" = "-c" ] && [ "\$2" = "%Y" ]; then
	printf '%s\n' "${real}"
	exit 0
fi
if [ "\$1" = "-f" ] && [ "\$2" = "%m" ]; then
	# GNU: -f = file system; %m is taken as a (missing) FILE, the real file
	# still prints its fs status block to stdout, and the exit is non-zero.
	printf '  File: "%s"\n  ID: 0 Namelen: 255 Type: ext2/ext3\n' "\$3"
	exit 1
fi
echo "stat shim: unexpected args: \$*" >&2
exit 2
EOF
chmod +x "${SHIM}/stat"

got=$(PATH="${SHIM}:${PATH}" stat_mtime "$f")
check "GNU-dialect stat_mtime returns real mtime" "$real" "$got"
check "GNU-dialect stat_mtime is not sanitized to 0" "no" "$([ "$got" = "0" ] && echo yes || echo no)"

# ── 3. Missing file returns 0 ──
check "missing file returns 0" "0" "$(stat_mtime "${WORK}/does-not-exist")"

echo ""
if [ "$FAILS" -eq 0 ]; then
	echo "ALL STAT-MTIME CHECKS PASSED"
	exit 0
else
	echo "STAT-MTIME FAILURES: $FAILS"
	exit 1
fi
