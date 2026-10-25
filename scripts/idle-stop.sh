#!/usr/bin/env bash
# Stop a background llama-server once nobody uses it, to give the RAM back and let the phone
# sleep. Started by start-llama.sh --background; the next opencode-local starts the server again.
# "In use" means: an opencode-local session is open, or the server is answering a request.
# Writes nothing except removing the server's PID file when it stops the server.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

pid="${1:?usage: idle-stop.sh SERVER_PID}"
port="${OCL_LLAMA_PORT:-8080}"
idle_s="${OCL_LLAMA_IDLE_S:-$(( ${OCL_LLAMA_IDLE_MIN:-10} * 60 ))}"
every="${OCL_IDLE_CHECK_S:-30}"
pidfile="$OCL_STATE/llama-server.pid"
sessions="$OCL_STATE/sessions"
[[ "$idle_s" -gt 0 ]] || exit 0

auth=()
key="${OCL_LLAMA_API_KEY:-}"
[[ -n "$key" && "$key" != local-no-key ]] && auth=(-H "Authorization: Bearer $key")

session_open() {
  local f
  for f in "$sessions"/*; do
    [[ -f "$f" ]] || continue
    if kill -0 "${f##*/}" 2>/dev/null; then return 0; fi
    rm -f "$f"  # left behind by a killed terminal
  done
  return 1
}
busy() { curl --silent --max-time 5 "${auth[@]}" "http://127.0.0.1:$port/slots" 2>/dev/null | grep -q '"is_processing":true'; }

last=$SECONDS
while kill -0 "$pid" 2>/dev/null; do
  sleep "$every"
  if session_open || busy; then
    last=$SECONDS
  elif (( SECONDS - last >= idle_s )); then
    kill "$pid" 2>/dev/null || true
    [[ "$(cat "$pidfile" 2>/dev/null)" == "$pid" ]] && rm -f "$pidfile"
    exit 0
  fi
done
