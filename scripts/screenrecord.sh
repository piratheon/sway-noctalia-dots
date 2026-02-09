#!/bin/bash
set -euo pipefail

SCREEN_DIR=$(xdg-user-dir VIDEOS)
FILENAME="screenrecord-$(date +%F-%T).mp4"
TARGET="$SCREEN_DIR/$FILENAME"
RUNDIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/screenrecord"
PIDFILE="$RUNDIR/pid"
WRF_PIDFILE="$RUNDIR/wf-pid"

notif(){ notify-send -t 4000 "SCREENRECORD" "$1"; }

mkdir -p "$RUNDIR"

# If another controller is running, kill its wf-recorder and exit
if [[ -f "$PIDFILE" ]]; then
  oldpid=$(<"$PIDFILE")
  if kill -0 "$oldpid" 2>/dev/null; then
    # kill wf-recorder started by previous run (if recorded)
    if [[ -f "$WRF_PIDFILE" ]]; then
      oldwrf=$(<"$WRF_PIDFILE")
      if kill -0 "$oldwrf" 2>/dev/null; then
        kill "$oldwrf" 2>/dev/null && notif "Stopped previous screenrecord (pid $oldwrf)"
      fi
      rm -f "$WRF_PIDFILE"
    else
      # best-effort: try to find a wf-recorder child of oldpid
      child=$(pgrep -P "$oldpid" wf-recorder || true)
      if [[ -n "$child" ]]; then
        kill "$child" 2>/dev/null && notif "Stopped previous screenrecord (pid $child)"
      fi
    fi
    # also kill the old controller script itself
    kill "$oldpid" 2>/dev/null || true
    rm -f "$PIDFILE"
    exit 0
  else
    # stale PID file
    rm -f "$PIDFILE" || true
  fi
fi

# No existing run: start a new recording
echo $$ > "$PIDFILE"
mkdir -p "$SCREEN_DIR"

# get first monitor source name (optional)
AUDIO_SRC=$(pactl list sources short | awk '/monitor/ {print $2; exit}' || true)

notif "Recording started"

cleanup_and_exit(){
  rm -f "$WRF_PIDFILE" "$PIDFILE"
  exit "${1:-0}"
}

trap '[[ -f "$WRF_PIDFILE" ]] && kill $(<"$WRF_PIDFILE") 2>/dev/null || true; cleanup_and_exit 130' INT TERM EXIT

# Start wf-recorder in background so we can track its PID and wait
if [[ ${1:-} == "-g" ]]; then
  GEOM=$(slurp -d) || { notif "Selection canceled"; cleanup_and_exit 1; }
  if [[ -n "$AUDIO_SRC" ]]; then
    wf-recorder --audio="$AUDIO_SRC" --geometry="$GEOM" -f "$TARGET" &
  else
    wf-recorder --geometry="$GEOM" -f "$TARGET" &
  fi
else
  if [[ -n "$AUDIO_SRC" ]]; then
    wf-recorder --audio="$AUDIO_SRC" -f "$TARGET" &
  else
    wf-recorder -f "$TARGET" &
  fi
fi

wrf_pid=$!
echo "$wrf_pid" > "$WRF_PIDFILE"

# Wait for wf-recorder to finish
wait "$wrf_pid"
rc=$?

trap - EXIT

if [[ -f "$TARGET" ]]; then
  notif "Saved: $TARGET"
  printf '%s' "$TARGET" | wl-copy
  cleanup_and_exit "$rc"
else
  notif "No output file created"
  cleanup_and_exit 1
fi
