#!/usr/bin/env bash
# Start llama-server for OpenCode. Binds to 127.0.0.1 unless told otherwise.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

host="${OCL_LLAMA_HOST:-127.0.0.1}"
port="${OCL_LLAMA_PORT:-8080}"
ctx="${OCL_LLAMA_CTX:-8192}"
threads="${OCL_LLAMA_THREADS:-$(nproc 2>/dev/null || echo 4)}"
model="${OCL_LLAMA_MODEL:-}"
api_key="${OCL_LLAMA_API_KEY:-}"
background=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] [-- extra llama-server args]

  -m, --model FILE    GGUF file (default: first *.gguf in $OCL_MODELS)
  -c, --ctx N         context size (default: $ctx)
  -t, --threads N     CPU threads (default: $threads)
  -p, --port N        port (default: $port)
      --host ADDR     bind address (default: 127.0.0.1)
                      Any other address requires OCL_LLAMA_API_KEY to be set.
  -b, --background    run detached; PID file in $OCL_STATE
      --stop          stop a background server
  -n, --dry-run       print the command only

Logs go to $OCL_STATE/llama-server.log.
EOF
}

extra=()
stop=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m|--model) model="$2"; shift 2 ;;
    -c|--ctx) ctx="$2"; shift 2 ;;
    -t|--threads) threads="$2"; shift 2 ;;
    -p|--port) port="$2"; shift 2 ;;
    --host) host="$2"; shift 2 ;;
    -b|--background) background=1; shift ;;
    --stop) stop=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; extra=("$@"); break ;;
    *) usage; exit 2 ;;
  esac
done

mkdir -p "$OCL_STATE"
pidfile="$OCL_STATE/llama-server.pid"
logfile="$OCL_STATE/llama-server.log"

if [[ "$stop" == 1 ]]; then
  if [[ -f "$pidfile" ]] && kill "$(cat "$pidfile")" 2>/dev/null; then
    log "llama-server stopped"
  else
    warn "no running llama-server found"
  fi
  rm -f "$pidfile"
  exit 0
fi

server="$(command -v llama-server || true)"
[[ -n "$server" || "$DRY_RUN" == 1 ]] || die "llama-server not found in PATH. Run the installer first."

if [[ -z "$model" ]]; then
  model="$(find "$OCL_MODELS" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | sort | head -n1 || true)"
  [[ -n "$model" ]] || die "no model found in $OCL_MODELS. Run scripts/fetch-model.sh first."
fi
[[ -f "$model" || "$DRY_RUN" == 1 ]] || die "model file not found: $model"

# Never expose the server without a key. Placeholder keys from env.sh do not count.
if [[ "$host" != "127.0.0.1" && "$host" != "localhost" && "$host" != "::1" ]]; then
  if [[ -z "$api_key" || "$api_key" == "local-no-key" || ${#api_key} -lt 24 ]]; then
    die "binding to $host needs OCL_LLAMA_API_KEY (at least 24 random characters, e.g. from: openssl rand -hex 24)"
  fi
  warn "listening on $host:$port - restrict access with a firewall rule (docs/security.md)"
fi

cmd=("${server:-llama-server}" --model "$model" --host "$host" --port "$port"
  --ctx-size "$ctx" --threads "$threads" --jinja --alias local --no-webui)
[[ -n "$api_key" && "$api_key" != "local-no-key" ]] && cmd+=(--api-key "$api_key")
cmd+=("${extra[@]}")

# Hide the key in printed output.
printable="${cmd[*]}"
[[ -n "$api_key" ]] && printable="${printable//$api_key/***}"
log "$printable"
[[ "$DRY_RUN" == 1 ]] && exit 0

echo "--- $(date -Iseconds) $printable" >> "$logfile"
if [[ "$background" == 1 ]]; then
  nohup "${cmd[@]}" >> "$logfile" 2>&1 &
  echo $! > "$pidfile"
  log "started in background (pid $(cat "$pidfile")), log: $logfile"
else
  "${cmd[@]}" 2>&1 | tee -a "$logfile"
fi
