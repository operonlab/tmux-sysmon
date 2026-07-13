#!/bin/bash
# demo-setup.sh — self-contained stage for docs/demo.tape. Builds everything the
# recording needs and starts an ISOLATED tmux server (socket: sm-demo, own
# config) — your real tmux server and config are never touched.
#
# Anonymous by construction: an identity-free shell prompt and a cockpit theme
# that OWNS status-left AND status-right (the default tmux status-right prints
# the machine's hostname — the theme replaces it so nothing leaks).
#
# HONEST BY DESIGN: the four CPU / MEM / DISK / NET capsules are the plugin's
# own #{sysmon_*} tokens, rewritten by sysmon.tmux into non-blocking readers.
# The values on screen are this machine's REAL live readings, not stand-ins.
set -u
unset TMUX TMUX_PANE
SOCK=sm-demo
WORK=/tmp/vhs-sysmon-demo
PLUGIN="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMUX_BIN="${TMUX_BIN:-tmux}"

mkdir -p "$WORK"

# ── clean, anonymous shell for the pane ──
cat > "$WORK/rc.sh" <<'RC'
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export LANG=en_US.UTF-8
PS1='\[\e[38;2;166;227;161m\] dev \[\e[38;2;137;180;250m\]\W\[\e[0m\] ❯ '
PROMPT_COMMAND=
RC

# ── cockpit theme (catppuccin mocha, hardcoded, portable). It fully owns
#    status-left and status-right; the plugin's pills are appended to the right. ──
cat > "$WORK/theme.conf" <<'CONF'
set -g default-terminal "tmux-256color"
set -as terminal-overrides ",xterm-256color:Tc"
set -g mouse on
setw -g automatic-rename off
set -g escape-time 0
set -g status on
set -g status-interval 2
set -g status-style "bg=#1E1E1E,fg=#cdd6f4"
set -g status-left '#[fg=#a6e3a1,bg=#1E1E1E]#[fg=#11111b,bg=#a6e3a1]  #[fg=#cdd6f4,bg=#313244] #S #[fg=#313244,bg=#1E1E1E] '
set -g status-left-length 40
set -g status-right-length 220
set -g window-status-format '#[fg=#6c7086] #I:#W '
set -g window-status-current-format '#[fg=#89b4fa,bold] #I:#W '
set -g window-status-separator ''
set -g pane-border-status top
set -g pane-border-format '#[align=centre]#{?pane_active,#[reverse],}#{pane_index}#[default] #{pane_current_command}'
set -g pane-border-style 'fg=#45475a'
set -g pane-active-border-style 'fg=#fab387,bold'
set -g message-style 'bg=#f9e2af,fg=#11111b,bold'
CONF

# ── build the cockpit status-right in the shell. Nerd half-circle end-caps are
#    written as OCTAL UTF-8 escapes so no PUA glyph ever lives in this file
#    (editors silently drop them). E0B6 = left cap (EE 82 B6), E0B4 = right cap. ──
pill() { # $1=accent hex  $2=label  $3=value
	printf '#[fg=%s,bg=#1E1E1E]\xee\x82\xb6#[fg=#11111b,bg=%s] %s #[fg=#cdd6f4,bg=#313244] %s #[fg=#313244,bg=#1E1E1E]\xee\x82\xb4 ' "$1" "$1" "$2" "$3"
}
SR=""
SR="${SR}$(pill '#89dceb' '' '%H:%M')"
SR="${SR}$(pill '#a6e3a1' 'CPU' '#{sysmon_cpu}')"
SR="${SR}$(pill '#f9e2af' 'MEM' '#{sysmon_mem}')"
SR="${SR}$(pill '#f5c2e7' 'DISK' '#{sysmon_disk}')"
SR="${SR}$(pill '#94e2d5' 'NET' '#{sysmon_net}')"

# ── isolated server: window 0 runs the clean shell EXPLICITLY (a session's first
#    window is created before default-command applies — classic prompt leak) ──
"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null
sleep 0.3
"$TMUX_BIN" -L "$SOCK" -f "$WORK/theme.conf" new-session -d -s demo -x 118 -y 15 -n workspace -c "$WORK" "bash --rcfile $WORK/rc.sh -i"
"$TMUX_BIN" -L "$SOCK" set -g default-command "bash --rcfile $WORK/rc.sh -i"

# ── sysmon config + the token-bearing status-right, then load the plugin. It
#    rewrites #{sysmon_*} into non-blocking #() readers AND warms the cache in a
#    fully-redirected background job, so the first on-camera render has real data.
#    (Do NOT add a bare `run-shell sysmon.sh cpu` warm here: run-shell echoes the
#    command's stdout into the active pane's copy-mode view, which both leaks the
#    value into the body and swallows the subsequent typed keys.) ──
"$TMUX_BIN" -L "$SOCK" set -g @sysmon-interval 2
"$TMUX_BIN" -L "$SOCK" set -g @sysmon-disk-path '/'
"$TMUX_BIN" -L "$SOCK" set -g status-right "$SR"
"$TMUX_BIN" -L "$SOCK" run-shell "$PLUGIN/sysmon.tmux"
