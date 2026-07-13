# tmux-sysmon hero screenshot — recorded with vhs (https://github.com/charmbracelet/vhs)
#   cd tmux-sysmon && vhs docs/screenshot.tape
#
# Runs entirely inside a throwaway, isolated tmux server (-L shot-sysmon,
# -f /dev/null) so it never touches your real tmux. The whole setup is hidden;
# the `Screenshot` freezes the status bar at the moment all four #{sysmon_*}
# tokens hold real, non-zero CPU / MEM / DISK / NET readings. Larger font and a
# short, status-bar-heavy frame make it clearer than the animated demo.gif.
#
# A throwaway .gif is written to /tmp only because vhs needs a recording target;
# the committed artifact is docs/screenshot.png (from the Screenshot command).

Output "/tmp/tmux-sysmon-shot.gif"
Set Shell "bash"
Set FontSize 20
Set Width 1600
Set Height 420
Set Padding 20

Hide
Type "tmux -L shot-sysmon -f /dev/null new-session -d -s hero 'bash --norc'"
Enter
Type "tmux -L shot-sysmon -f /dev/null attach -t hero"
Enter
Sleep 800ms
Type "PS1='❯ '; clear"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-interval 1"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-left-length 40"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-right-length 200"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g @sysmon-interval 2"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g @sysmon-disk-path /System/Volumes/Data"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-style 'bg=colour235,fg=colour250'"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g window-status-format ''"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g window-status-current-format ''"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-left '#[bg=colour31,fg=colour231,bold] tmux-sysmon #[default] '"
Enter
Type "tmux -L shot-sysmon -f /dev/null set -g status-right '#[fg=colour114]CPU #[fg=colour253]#{sysmon_cpu}  #[fg=colour240]|#[fg=colour111]  MEM #[fg=colour253]#{sysmon_mem}  #[fg=colour240]|#[fg=colour179]  DISK #[fg=colour253]#{sysmon_disk}  #[fg=colour240]|#[fg=colour176]  NET #[fg=colour253]#{sysmon_net} '"
Enter
Type "./sysmon.tmux"
Enter
Type "( for i in $(seq 1 60); do curl -s https://example.com -o /dev/null 2>/dev/null; sleep 0.2; done ) >/dev/null 2>&1 &"
Enter
Sleep 1s
Type "clear; printf '\n  tmux-sysmon: CPU / MEM / DISK / NET as drop-in #{...} status tokens\n  a non-blocking cache means the bar never freezes, even mid-measurement\n\n'"
Enter
Sleep 9s
Show
Sleep 2s
Screenshot docs/screenshot.png
Sleep 800ms
Hide
Type "tmux -L shot-sysmon -f /dev/null kill-server"
Enter
Sleep 500ms
