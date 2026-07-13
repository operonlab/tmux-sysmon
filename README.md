# tmux-sysmon

> 中文說明請見 [docs/zh.md](docs/zh.md)

**CPU, memory, disk and network speed as four drop-in `#{...}` placeholders for
your tmux status line.** Works on **macOS and Linux** out of the box.

![tmux-sysmon status bar showing live CPU, memory, disk and network readings](docs/screenshot.png)

*The four `#{sysmon_*}` tokens rendering real CPU / memory / disk / network values, styled into a tmux status line.*

## What is this?

tmux can show a status bar along the bottom of the screen. tmux-sysmon adds four
little readouts you can place anywhere in it:

- **CPU** — how busy your processor is right now (e.g. `22%`)
- **Memory** — how much RAM is in use (e.g. `14.6/24G 61%`)
- **Disk** — how full your drive is (e.g. `240/460G 52%`)
- **Network** — current download / upload speed (e.g. `↓ 27K/s ↑ 18K/s`)

You drop the four tokens wherever you want them and style them with your own
theme — the plugin only produces the plain text values, no colors or icons of
its own, so it fits any status line.

Under the hood it follows a strict **non-blocking** rule: the status line only
ever reads a tiny cached file, and the actual measuring happens in the
background. That means these readouts can never freeze your tmux, even if a
measurement is slow.

> **Honest positioning.** This is a crowded corner of the tmux ecosystem —
> [tmux-cpu](https://github.com/tmux-plugins/tmux-cpu),
> [tmux-mem-cpu-load](https://github.com/thewtex/tmux-mem-cpu-load) and plain
> `sysstat` all overlap with it. tmux-sysmon's reasons to exist are: **all four
> metrics in one plugin**, a disciplined **non-blocking cache** (a wedged
> collector never stalls your bar), a documented **provider contract** so you
> can swap in your own collector (Rust, Go, anything — see
> [docs/provider-contract.md](docs/provider-contract.md)), and the **same
> `@`-option vocabulary** as the rest of this plugin family. If you only need
> one metric and already run another plugin, that's a perfectly good choice.

## Quickstart

New to tmux's `prefix` key? The default prefix is `Ctrl-b` — press `Ctrl-b`,
release it, then press the next key.

You need **tmux 1.8 or newer** (see [Requirements](#requirements)). Pick one of
the two paths, then do step 3.

### 1. Install the plugin

#### Path A — with TPM (the tmux plugin manager)

If you've never installed TPM, run these three lines first (copy-paste as-is):

```sh
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
printf '\n%s\n' "run '~/.tmux/plugins/tpm/tpm'" >> ~/.tmux.conf
tmux source ~/.tmux.conf
```

(If tmux isn't running yet, `tmux source` may print "no server running" —
that's fine, the setting just takes effect next time you start tmux.)

Then add tmux-sysmon. Put this line in your `~/.tmux.conf` **above** the
`run '~/.tmux/plugins/tpm/tpm'` line:

```tmux
set -g @plugin 'operonlab/tmux-sysmon'
```

#### Path B — without TPM (one line, no plugin manager)

Clone it anywhere, then add one line to `~/.tmux.conf`:

```sh
git clone https://github.com/operonlab/tmux-sysmon ~/.tmux/plugins/tmux-sysmon
printf '%s\n' "run-shell '~/.tmux/plugins/tmux-sysmon/sysmon.tmux'" >> ~/.tmux.conf
```

### 2. Put the tokens in your status line

Add any of the four placeholders to your `status-left` or `status-right`. For
example:

```tmux
set -g status-right 'CPU #{sysmon_cpu} | MEM #{sysmon_mem} | DISK #{sysmon_disk} | NET #{sysmon_net}'
```

Place these lines **before** the plugin's `@plugin` / `run-shell` line so the
tokens exist when the plugin rewrites them.

### 3. Reload (and, with TPM, install)

```sh
tmux source ~/.tmux.conf   # reload config
```

With **TPM**, also press `prefix + I` (capital i) once to fetch the plugin.

Within a few seconds the four readouts appear and refresh on their own.

## Demo

![tmux-sysmon demo](docs/demo.gif)

## Options

Set any of these in `~/.tmux.conf` **before** the plugin line. All are optional.

| Option | Default | What it does (plain words) |
|---|---|---|
| `@sysmon-interval` | `5` | How often (seconds) the values are re-measured in the background. Smaller = fresher but slightly more work. |
| `@sysmon-disk-path` | `/` | Which filesystem the disk readout measures. Point it at any mounted path. |
| `@sysmon-provider` | *(unset)* | Run **your own** collector instead of the built-in one. See the warning below. |

Also remember tmux's own `status-interval` (e.g. `set -g status-interval 5`)
controls how often the bar is *redrawn* — set it near `@sysmon-interval` so
fresh values actually show up.

### Custom provider (advanced)

> ⚠️ **`@sysmon-provider` executes a command you supply.** Only set it in a
> `~/.tmux.conf` you trust — it runs your code in the background on every
> refresh, exactly like any other config line that runs a program.

Point it at any program that prints the contract JSON to stdout:

```tmux
set -g @sysmon-provider '/opt/metrics/my-collector'
```

The full schema and a "bring your own Rust/Go collector" guide are in
[docs/provider-contract.md](docs/provider-contract.md).

## Uninstall

Run the bundled teardown script (restores your status tokens and clears the
cache), then delete the folder:

```sh
~/.tmux/plugins/tmux-sysmon/scripts/teardown.sh
rm -rf ~/.tmux/plugins/tmux-sysmon
```

(If you installed via TPM, also remove the `set -g @plugin '.../tmux-sysmon'`
line from `~/.tmux.conf`.)

## Troubleshooting / FAQ

**On macOS the disk readout shows almost nothing used (like `13/460G 3%`).**
This is real and expected. On modern macOS (APFS), `/` is the sealed **System**
volume, which is nearly empty; your files live on a separate **Data** volume. To
measure where your data actually is, point the option there:

```tmux
set -g @sysmon-disk-path '/System/Volumes/Data'
```

**The readouts are blank for the first few seconds.**
By design. The status line only reads a cache and never blocks, so on a cold
start the first refresh runs in the background; values appear on the next tick
(within `@sysmon-interval` seconds).

**Network speed shows `↓ 0B/s ↑ 0B/s` at first, then starts working.**
A speed is a *difference* between two measurements, so the very first sample has
nothing to compare against and reads zero. The next refresh fills it in. (This
is also why the second run in the tests always shows a real rate.)

**The `↓` / `↑` arrows show up as boxes or question marks.**
Those are plain Unicode arrows (U+2193 / U+2191), not Nerd Font glyphs. If they
don't render, your terminal font doesn't include them — switch to a font that
does, or provide a custom `@sysmon-provider` that formats `net_display` without
arrows.

**Values look frozen / never update.**
tmux only redraws the bar every `status-interval` seconds. If that's large (or
unset), lower it: `set -g status-interval 5`. Also confirm `@sysmon-interval`
isn't set to something huge.

**Nothing appears at all.**
Make sure the `#{sysmon_*}` tokens are in `status-left`/`status-right` and that
those lines come **before** the plugin line, then reload with
`tmux source ~/.tmux.conf`. You can sanity-check a collector by running it
directly: `~/.tmux/plugins/tmux-sysmon/scripts/collect-macos.sh /` (or
`collect-linux.sh`) should print one line of JSON.

## Requirements

- **tmux 1.8 or newer.** This floor is verified against primary sources, not
  guessed. The plugin depends on `@`-prefixed user options and the
  `show-options -q` / `-v` flags — all of which landed together in **tmux 1.8**
  (the "CHANGES FROM 1.7 TO 1.8" section of the official
  [tmux CHANGES](https://github.com/tmux/tmux/blob/master/CHANGES) adds `@` user
  options and `show-options -q`; the tmux 1.8 manual page gives the
  `show-options` synopsis as `[-gqsvw]`, i.e. `-v` is present). The status-line
  `#(shell-command)` mechanism the tokens plug into is far older; the plugin
  supplies its **own** non-blocking cache, so it never relies on any newer
  asynchronous-`#()` behaviour.
- **Tested on:** tmux `next-3.8` (development build) on macOS. The Linux
  collector is exercised for real in CI on `ubuntu-latest`.
- **No `jq` or other runtime dependencies** — collection uses only `awk`, `df`,
  and standard system tools already present on macOS and Linux.
- **Platform support:** macOS and Linux collectors are built in. On any other OS
  the status line stays blank unless you supply a `@sysmon-provider`.

## Credits / License

Field names and display formats follow a local metrics producer so that
producer can act as a drop-in provider. Released under the
[MIT License](LICENSE).
