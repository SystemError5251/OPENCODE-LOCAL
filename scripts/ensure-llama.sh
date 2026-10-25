#!/usr/bin/env bash
# Make sure a model server answers on 127.0.0.1: either an SSH tunnel to a PC host
# (scripts/tunnel.sh) or a local llama-server, which is started if nothing answers.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

port="${OCL_LLAMA_PORT:-8080}"
wait_s="${OCL_LLAMA_WAIT:-120}"

# --fail: llama-server answers 503 while the model is still loading.
healthy() { curl --silent --fail --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; }

healthy && exit 0
if ! curl --silent --max-time 2 "http://127.0.0.1:$port/health" >/dev/null 2>&1; then
  "$(dirname "$0")/start-llama.sh" --background
fi
log "waiting for the model to load (up to ${wait_s}s)"
for _ in $(seq 1 "$wait_s"); do
  healthy && { log "model ready"; exit 0; }
  sleep 1
done
die "llama-server did not become ready - rerun with OCL_DEBUG_LOG=1 and check $OCL_STATE/llama-server.log"
