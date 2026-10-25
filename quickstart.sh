#!/usr/bin/env bash
# One command from a fresh clone to a working setup: install for this platform (Termux or
# Linux/WSL), download a model that fits the device, and print how to start.
# Safe to run again: it repairs or completes an earlier, interrupted install.
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

  --model ID      model to download (default: picked from RAM; see scripts/fetch-model.sh --list)
  --from-source   build OpenCode from source instead of the official release binary
  -n, --dry-run   print every step without changing anything
EOF
}

model="" inst_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) model="${2:-}"; [[ -n "$model" ]] || { usage; exit 2; }; shift 2 ;;
    --from-source) inst_args+=(--from-source); shift ;;
    -n|--dry-run) DRY_RUN=1; inst_args+=(--dry-run); shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
export DRY_RUN
export OCL_QUICKSTART=1

# 12 GB RAM (shows as ~11 GB) and more: Qwen3 4B; below: Qwen3 1.7B (see ki-models/README.md).
if [[ -z "$model" ]]; then
  ram_gb="$(awk '/MemTotal/ {printf "%d", $2 / 1024 / 1024 + 0.5}' /proc/meminfo 2>/dev/null || echo 0)"
  if [[ "$ram_gb" -ge 11 ]]; then model="qwen3-4b"; else model="qwen3-1.7b"; fi
  log "RAM ${ram_gb} GB -> model $model (choose another with --model)"
fi

cd "$REPO_ROOT"
if is_termux; then
  ./install-termux.sh "${inst_args[@]}"
else
  ./install-linux.sh "${inst_args[@]}"
fi

fetch_args=("$model")
[[ "$DRY_RUN" == 1 ]] && fetch_args+=(--dry-run)
scripts/fetch-model.sh "${fetch_args[@]}"

# A server started before this run may still serve the old model or context size.
[[ "$DRY_RUN" == 1 ]] || scripts/start-llama.sh --stop >/dev/null 2>&1 || true

hint=""
if ! is_termux && ! command -v opencode-local >/dev/null 2>&1; then
  hint="  First make the launcher findable (add this line to ~/.bashrc as well):
    export PATH=\"$OCL_BIN:\$PATH\"
"
fi
cat >&2 <<EOF

Ready. Start OpenCode inside a project folder (never in your home folder):
${hint}  mkdir -p ~/projects/myproject && cd ~/projects/myproject && opencode-local

Optional: $REPO_ROOT/scripts/bench.sh measures tokens/s.
When you are done downloading, block the network for Termux/this machine (docs/security.md).
EOF
