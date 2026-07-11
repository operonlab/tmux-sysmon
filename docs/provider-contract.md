# tmux-sysmon provider contract

tmux-sysmon separates **collection** from **rendering**. The status line only
ever reads a small JSON cache; something else writes it. By default that
"something" is the bundled `collect-macos.sh` / `collect-linux.sh`, but you can
substitute your own program with the `@sysmon-provider` option.

This document is the contract a provider must satisfy.

## How it fits together

```
                    writes JSON cache
  provider  ──────────────────────────────►  ${TMUX_TMPDIR:-/tmp}/tmux-sysmon-<uid>/metrics.json
  (built-in collector,                                     │
   or your own binary)                                     │  reads *_display only
                                                           ▼
                                              #{sysmon_cpu} #{sysmon_mem}
                                              #{sysmon_disk} #{sysmon_net}
```

`sysmon.sh` (the part tmux calls on every status refresh) **never runs the
provider inline**. When the cache is older than `@sysmon-interval` seconds it
spawns one fully-detached background refresh behind an atomic lock, and returns
the previous value immediately. A provider that is slow or hangs therefore
never blocks the status bar — the last-known value keeps showing until the
provider produces fresh output (or is time-capped and the old cache is kept).

## Output format

A provider is any command that prints **one JSON object to stdout** and exits.
It receives the configured disk path as `$1` (default `/`).

### Required fields

These four `*_display` strings are what the placeholders render. They are the
only fields `sysmon.sh` reads, so at minimum a provider must emit them:

| Field | Type | Example | Rendered by |
|---|---|---|---|
| `cpu_display` | string | `"22%"` | `#{sysmon_cpu}` |
| `mem_display` | string | `"14.6/24G 61%"` | `#{sysmon_mem}` |
| `disk_display` | string | `"240/460G 52%"` | `#{sysmon_disk}` |
| `net_display` | string | `"↓ 27K/s ↑ 18K/s"` | `#{sysmon_net}` |

You are free to format the strings however you like — they are rendered
verbatim. The examples above are what the built-in collectors produce.

### Recommended numeric fields

The built-in collectors also emit the raw numbers below. They are **not** read
by the status line, but including them keeps your provider a drop-in match for
the reference schema (useful for dashboards, logging, or other consumers):

| Field | Type | Meaning |
|---|---|---|
| `cpu_pct` | number | CPU busy percent, 0–100 |
| `mem_used_gb` / `mem_total_gb` / `mem_pct` | number | Memory used / total (GiB) and percent |
| `disk_used_gb` / `disk_total_gb` / `disk_pct` | number | Disk used / total (GiB) and percent |
| `net_rx_bps` / `net_tx_bps` | number | Receive / transmit **bytes per second** |
| `ts` | string | ISO-8601 UTC timestamp of the sample |

Extra fields are ignored, so a richer producer may add its own.

### Canonical example

```json
{"ts":"2026-07-11T05:53:23Z","cpu_pct":22.4,"cpu_display":"22%","mem_used_gb":14.6,"mem_total_gb":24.0,"mem_pct":60.8,"mem_display":"14.6/24G 61%","net_rx_bps":28058,"net_tx_bps":18467,"net_display":"↓ 27K/s ↑ 18K/s","disk_used_gb":240.4,"disk_total_gb":460.4,"disk_pct":52.2,"disk_display":"240/460G 52%"}
```

The parser is deliberately forgiving: it extracts each `"<key>_display":"..."`
with a simple, dependency-free scan, so both minified (one line, as above) and
pretty-printed JSON work. Display **values must not contain a double quote**.

## Using your own Rust / Go / anything collector

> ⚠️ `@sysmon-provider` runs a command you supply. Only set it in a
> `~/.tmux.conf` you trust — treat it like any other line that executes code.

Point the option at your program. It will be run in the background whenever the
cache goes stale:

```tmux
set -g @sysmon-provider '/opt/metrics/my-collector --format sysmon-json'
set -g @plugin 'joneshong/tmux-sysmon'
```

Requirements for the program:

1. Print exactly one contract JSON object to **stdout**, then exit 0.
2. Emit at least the four `*_display` fields; matching the numeric fields too
   makes it a clean drop-in.
3. Be reasonably quick. On platforms with a `timeout`/`gtimeout` helper the
   refresh is time-capped at `@sysmon-interval + 3` seconds; on a hang the
   previous cached value is what stays on screen.
4. `$1` is the configured `@sysmon-disk-path` (default `/`) — honor it if you
   report disk, ignore it otherwise.

### Why the field names look the way they do

The schema mirrors an existing local metrics producer (a Rust agent-metrics
daemon that already writes `cpu_display` / `mem_display` / `disk_display` /
`net_display` plus the numeric columns). Keeping the exact names means such a
producer can be wired in as a provider with no translation layer. If you are
starting fresh, just follow the table above.

### Minimal shell provider (illustration)

```sh
#!/bin/sh
# my-provider.sh — emit the four required display strings.
printf '{"cpu_display":"%s","mem_display":"%s","disk_display":"%s","net_display":"%s"}\n' \
  "$(get_cpu)" "$(get_mem)" "$(get_disk "${1:-/}")" "$(get_net)"
```
