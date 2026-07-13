# tmux-sysmon demo — recorded with vhs (https://github.com/charmbracelet/vhs)
#   cd tmux-sysmon && vhs docs/demo.tape
#
# Runs entirely inside a throwaway, isolated tmux server (-L vhsdemo-sysmon,
# -f /dev/null) so it never touches your real tmux. The setup is hidden; the
# recording shows the four #{sysmon_*} tokens rendering live CPU / memory /
# disk / network readouts in the status bar.

Output "docs/demo.gif"
Set Shell "bash"
Set FontSize 15
Set Width 1200
Set Height 660
Set Padding 12
Set TypingSpeed 40ms

Hide
Type "tmux -L vhsdemo-sysmon -f /dev/null new-session -d -s demo 'bash --norc -i'"
Enter
Type "tmux -L vhsdemo-sysmon attach -t demo"
Enter
Sleep 800ms
Type "PS1='❯ '; clear"
Enter
Type "tmux -L vhsdemo-sysmon set -g status-interval 2 \; set -g status-right-length 200"
Enter
Type "tmux -L vhsdemo-sysmon set -g @sysmon-disk-path '/System/Volumes/Data'"
Enter
Type "tmux -L vhsdemo-sysmon set -g status-right ' CPU #{sysmon_cpu} | MEM #{sysmon_mem} | DISK #{sysmon_disk} | NET #{sysmon_net} '"
Enter
Type "./sysmon.tmux"
Enter
Type "clear"
Enter
Sleep 7s
Show
Type "# tmux-sysmon: live CPU / MEM / DISK / NET in the status bar"
Enter
Sleep 2.5s
Type "curl -s https://example.com > /dev/null && echo refreshed"
Enter
Sleep 4s
Hide
Type "tmux -L vhsdemo-sysmon kill-server"
Enter
Sleep 500ms
