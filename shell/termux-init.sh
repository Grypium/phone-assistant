# Sourced from ~/.bashrc by install.sh. Set PA_NO_TMUX=1 before opening a session to skip all of this.
PA_HOME="${PA_HOME:-$HOME/phone-assistant}"

# Run `claude` so keepalive can reopen it after a crash: same conversation, same flags
# (e.g. --dangerously-skip-permissions, --model). See bin/claude-args for the details.
claude() {
  if [ -z "$TMUX" ]; then command claude "$@"; return; fi
  local out rc id flags run
  out=$("$PA_HOME/bin/claude-args" "$@"); rc=$?
  if [ $rc -ne 0 ]; then command claude "$@"; return; fi   # print mode, --help, subcommands, or helper failed
  { IFS= read -r id; IFS= read -r flags; IFS= read -r run; } <<< "$out"
  if [ -z "$id" ]; then
    id=$(cat /proc/sys/kernel/random/uuid); run="--session-id $id $run"
  fi
  tmux set -p @claude_session "$id"; tmux set -p @claude_args "$flags"
  eval "command claude $run"; rc=$?
  tmux set -pu @claude_session; tmux set -pu @claude_args   # exited normally: don't reopen it next time
  return $rc
}

# Every interactive Termux shell lives inside tmux, so it can be restored.
if [[ $- == *i* ]] && [ -z "$TMUX" ] && [ -z "$PA_NO_TMUX" ] && command -v tmux >/dev/null; then
  "$PA_HOME/bin/keepalive" restore
  "$PA_HOME/bin/keepalive" ensure-daemon
  # Attach to a session no other tab is showing: ones running Claude first, then the most recently active.
  _pa_t=$(tmux list-sessions -F '#{session_attached} #{session_activity} #{session_name}' 2>/dev/null |
    while read -r _a _act _name; do
      [ "$_a" = 0 ] || continue
      # sessions waiting for their own restored tab come last; then Claude first; then most recent output
      echo "$(tmux display -p -t "=$_name:" '#{?@pa_tab_pending,0,1}' </dev/null)" \
           "$(tmux list-panes -s -t "=$_name" -F '#{?@claude_session,1,0}' </dev/null | grep -c 1)" \
           "$(tmux list-windows -t "=$_name" -F '#{window_activity}' </dev/null | sort -n | tail -1) $_name"
    done | sort -k1,1nr -k2,2nr -k3,3nr | head -1 | cut -d' ' -f4-)
  # after a kill (no reboot) this tab is the only one: bring the other sessions' tabs back too
  "$PA_HOME/bin/keepalive" open-tabs "$_pa_t"
  if [ -n "$_pa_t" ]; then tmux set -ut "=$_pa_t:" @pa_tab_pending; tmux attach -t "=$_pa_t"; else tmux new-session; fi
  if [ $? -eq 0 ]; then
    # tmux exited normally. If no sessions are left you closed them on purpose: forget the snapshot.
    tmux has-session 2>/dev/null || "$PA_HOME/bin/keepalive" clear
    exit
  fi
  unset _pa_t   # tmux failed to start: fall through to a plain shell
fi
