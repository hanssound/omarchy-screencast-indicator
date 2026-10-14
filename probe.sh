#!/bin/bash
# Who is capturing the screen. Lines are "A name" (capturing now) or "N name"
# (a capture tool that is running; only names a capture Hyprland reported).
set -o pipefail
dir=$(dirname "$0")

# Recorders that exist only while recording; KMS capture (gpu-screen-recorder)
# sends Hyprland no event, so these count as capturing on their own.
recorders='gpu-screen-recorder|wf-recorder|wl-screenrec'
# Tools that may sit idle; they only name an event-driven capture.
tools='omasnap|grim|grimblast|hyprshot|hyprpicker|wayfreeze|flameshot|spectacle|obs|kooha|wayvnc|gliff-server|wl-mirror|omarchy-capture-[a-z-]+'

# " via claude" when an AI agent (Claude Code, Codex) is up the process tree,
# so a capture an agent triggers says so instead of just "grim".
via() {
  local p=$1 comm key value parent
  while [[ $p -gt 1 ]]; do
    { read -r comm </proc/$p/comm; } 2>/dev/null || return
    [[ $comm =~ ^(claude|codex) ]] && { echo " via ${BASH_REMATCH[1]}"; return; }
    parent=0
    while read -r key value _; do
      [[ $key == PPid: ]] && { parent=$value; break; }
    done </proc/$p/status 2>/dev/null || return
    p=$parent
  done
}

active=false
# Read candidates first, before a short-lived screenshot tool can disappear.
while read -r pid; do
  [[ $pid =~ ^[0-9]+$ ]] || continue
  # Match the actual command/script, never a tool name inside arbitrary arguments.
  {
    IFS= read -r -d '' word || continue
    name=${word##*/}
    if [[ $name =~ ^(bash|sh|dash|zsh|python[0-9.]*)$ ]]; then
      name=""
      while IFS= read -r -d '' word; do
        [[ $word =~ ^-[^-]*c ]] && break
        [[ $word == -* ]] && continue
        name=${word##*/}
        break
      done
    fi
  } 2>/dev/null </proc/$pid/cmdline || continue
  if [[ $name =~ ^($recorders)$ ]]; then
    printf 'A %s%s\n' "$name" "$(via "$pid")"
    active=true
  elif [[ $name =~ ^($tools)$ ]]; then
    printf 'N %s%s\n' "$name" "$(via "$pid")"
  fi
done < <(pgrep -u "$UID" -f "(^|[ /])($recorders|$tools)( |$)" 2>/dev/null)

probe_status=0
if portal_apps=$(timeout -k 0.2s 1s pw-dump 2>/dev/null | jq -r -f "$dir/consumers.jq" 2>/dev/null) 2>/dev/null; then
  if [[ -n $portal_apps ]]; then
    while IFS= read -r name; do printf 'A %s\n' "$name"; done <<<"$portal_apps"
    active=true
  fi
else
  probe_status=1
fi

# N names are ignored when an A name exists, so skip the socket scan then.
if $active; then exit 0; fi
[[ -n ${XDG_RUNTIME_DIR:-} ]] || exit "$probe_status"

# Wayland clients that connected in the last few seconds. A screenshot tool is
# a fresh client when it captures, so this names tools the lists above miss.
sock=${WAYLAND_DISPLAY:-wayland-1}
[[ $sock == /* ]] || sock="$XDG_RUNTIME_DIR/$sock"
pids=$(ss -xpH 2>/dev/null | awk -v sock="$sock" '
  { line[NR] = $0; if ($5 == sock) peer[$8] = 1 }
  END {
    for (i = 1; i <= NR; i++) {
      split(line[i], f, " ")
      if (!(f[6] in peer)) continue
      t = line[i]
      while (match(t, /pid=[0-9]+/)) { print substr(t, RSTART + 4, RLENGTH - 4); t = substr(t, RSTART + RLENGTH) }
    }
  }' | sort -u | paste -sd,)
[[ -n $pids ]] && ps -o etimes=,pid=,comm= -p "$pids" | while read -r age pid comm; do
  # Clipboard watchers spawn a fresh wl-paste on every copy; they never capture.
  ((age <= 5)) && [[ ! $comm =~ ^wl-(paste|copy)$ ]] && echo "N $comm$(via "$pid")"
done
exit "$probe_status"
