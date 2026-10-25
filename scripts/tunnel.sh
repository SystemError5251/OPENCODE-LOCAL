#!/usr/bin/env bash
# Phase 7: use a PC in the home network as model host through an encrypted SSH tunnel.
# The PC keeps llama-server on its own 127.0.0.1; this device forwards its 127.0.0.1:PORT there.
# OpenCode's config does not change - it still talks to 127.0.0.1.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

port="${OCL_LLAMA_PORT:-8080}"
remote_port="${OCL_REMOTE_PORT:-8080}"
pidfile="$OCL_STATE/tunnel.pid"

usage() {
  cat <<EOF
Usage: $(basename "$0") USER@PC [--port N] [--remote-port N]
       $(basename "$0") --stop | --status

Opens an SSH tunnel 127.0.0.1:$port -> PC:127.0.0.1:$remote_port in the background.
On the PC: install with ./install-linux.sh, then run scripts/start-llama.sh --background
(it stays on 127.0.0.1 there, nothing is exposed to the network).

Stop a local llama-server first (scripts/start-llama.sh --stop), otherwise the port is taken.
EOF
}

target="" action="start"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port="$2"; shift 2 ;;
    --remote-port) remote_port="$2"; shift 2 ;;
    --stop) action="stop"; shift ;;
    --status) action="status"; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 2 ;;
    *) target="$1"; shift ;;
  esac
done
mkdir -p "$OCL_STATE"

running() { [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; }

case "$action" in
  stop)
    if running; then kill "$(cat "$pidfile")"; log "tunnel stopped"; else warn "no tunnel running"; fi
    rm -f "$pidfile"
    exit 0 ;;
  status)
    if running; then log "tunnel running (pid $(cat "$pidfile"))"; else log "no tunnel"; fi
    if curl --silent --fail --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
      log "model server on 127.0.0.1:$port is ready"
    else
      log "no ready model server on 127.0.0.1:$port"
    fi
    exit 0 ;;
esac

[[ "$target" == *@* ]] || { usage; exit 2; }
[[ "$target" != -* ]] || die "invalid target"
have ssh || [[ "$DRY_RUN" == 1 ]] || die "ssh not found (Termux: pkg install openssh)"
running && die "a tunnel is already running (pid $(cat "$pidfile")); use --stop first"

cmd=(ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3
  -L "127.0.0.1:$port:127.0.0.1:$remote_port" "$target")
log "${cmd[*]}"
[[ "$DRY_RUN" == 1 ]] && exit 0

"${cmd[@]}" >> "$OCL_STATE/tunnel.log" 2>&1 &
echo $! > "$pidfile"
for _ in $(seq 1 15); do
  if curl --silent --fail --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
    log "tunnel up: OpenCode now uses the model on $target"
    exit 0
  fi
  running || die "ssh exited - see $OCL_STATE/tunnel.log (first connection? run 'ssh $target' once to accept the host key)"
  sleep 1
done
warn "tunnel is running but the PC's llama-server does not answer yet (is it started there?)"
