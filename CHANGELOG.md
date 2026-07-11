# Changelog

All notable changes to tmux-sysmon are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-07-11

Initial release.

### Added

- Four status-line placeholders — `#{sysmon_cpu}`, `#{sysmon_mem}`,
  `#{sysmon_disk}`, `#{sysmon_net}` — each independently placeable in
  `status-left` / `status-right`.
- Built-in collectors for **macOS** (`collect-macos.sh`: `top -l 2`, `vm_stat` +
  `sysctl`, `df`, `netstat -ib` delta) and **Linux** (`collect-linux.sh`:
  `/proc/stat`, `/proc/meminfo`, `df`, `/proc/net/dev` delta).
- Strict **non-blocking** status contract: `sysmon.sh` only reads a JSON cache
  and returns immediately; stale caches trigger a fully-detached, lock-guarded
  background refresh, and a slow/hung collector keeps showing the last value.
- **Provider contract** (`docs/provider-contract.md`) and the `@sysmon-provider`
  option, so a custom collector (e.g. a Rust/Go daemon) can supply the same JSON
  in place of the built-ins.
- Options: `@sysmon-interval` (default `5`), `@sysmon-disk-path` (default `/`),
  `@sysmon-provider`.
- `teardown.sh` — restores rewritten status tokens, clears plugin options, and
  removes the runtime cache directory.
- Per-user runtime directory under `${TMUX_TMPDIR:-/tmp}/tmux-sysmon-<uid>/`,
  created mode `0700` with a symlink-pre-plant guard.
- CI: `shellcheck -S warning` across all shell files, plus a functional smoke
  suite that really runs the Linux collector and exercises the plugin on a
  private `tmux -L` socket.
