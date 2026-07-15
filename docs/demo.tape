# tmux-sysmon demo — live CPU / MEM / DISK / NET capsules in a cockpit status bar.
# Fully self-contained: docs/demo-setup.sh stages an anonymous shell and a
# catppuccin-mocha ISOLATED tmux server (socket sm-demo), then loads the plugin
# so the four #{sysmon_*} tokens render this machine's REAL readings. The theme
# owns status-left AND status-right (the default status-right leaks the hostname),
# and the plugin's pills sit at the tail — behind the clock capsule.
# Re-record from the repo root with:  vhs docs/demo.tape
Output "docs/demo.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2392
Set Height 806
Set Padding 20
Set TypingSpeed 35ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L sm-demo attach -t demo"
Enter
Sleep 2500ms
Show

# the cockpit: clock capsule, then the four live sysmon capsules on the right
Sleep 3s
Type "# tmux-sysmon: live CPU / MEM / DISK / NET, read from a cache — never blocks tmux"
Enter
Sleep 2500ms

# stir the network counters -> the NET capsule ticks up on the next refresh
Type "curl -s https://example.com > /dev/null && echo refreshed"
Enter
Sleep 4s

Hide
Ctrl+B
Type "d"
Sleep 400ms
Type "tmux -L sm-demo kill-server"
Enter
Sleep 500ms
