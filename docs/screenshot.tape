# tmux-sysmon hero screenshot — recorded with vhs (https://github.com/charmbracelet/vhs)
#   cd tmux-sysmon && vhs docs/screenshot.tape
#
# Fully self-contained & anonymous: docs/demo-setup.sh stages an identity-free
# Starship shell and a catppuccin-mocha ISOLATED tmux server (socket sm-demo) —
# your real tmux server and config are never touched. The plugin's own
# scripts/sysmon.sh readers drive the NET/CPU/MEM/DISK capsule on row 2 (this
# machine's REAL live readings). Tight height so the two-row pill cockpit + a
# couple narration lines fill the frame with no dead space.
#
# A throwaway .gif is written to /tmp only because vhs needs a recording target;
# the committed artifact is docs/screenshot.png (from the Screenshot command).

Output "/tmp/tmux-sysmon-shot.gif"
Require tmux

Set Shell "bash"
Set FontFamily "MesloLGS Nerd Font Mono"
Set FontSize 20
Set Width 2496
Set Height 520
Set Padding 20
Set TypingSpeed 20ms

Hide
Type "bash docs/demo-setup.sh"
Enter
Sleep 3s
Type "clear; tmux -L sm-demo attach -t demo"
Enter
Sleep 2500ms

# the money shot: narration line, then the four live sysmon capsules on row 2
Type "# tmux-sysmon: live CPU / MEM / DISK / NET, read from a cache — never blocks tmux"
Enter
Sleep 1500ms

# stir the network counters -> the NET capsule ticks up on the next refresh
Type "curl -s https://example.com > /dev/null && echo refreshed"
Enter
Sleep 4s
Show
Sleep 500ms
Screenshot docs/screenshot.png
Sleep 500ms

Hide
Type "tmux -L sm-demo kill-server"
Enter
Sleep 500ms
