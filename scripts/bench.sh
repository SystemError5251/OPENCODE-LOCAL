#!/usr/bin/env bash
# Phase 1: measure prompt processing and generation speed (tokens/s) with llama-bench.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [MODEL.gguf] [threads]

Runs llama-bench (512-token prompt, 128 generated tokens) and appends the
Markdown result table to $OCL_STATE/bench.md.
Copy the numbers into docs/phase0-results.md.
EOF
}
[[ "${1:-}" == -h || "${1:-}" == --help ]] && { usage; exit 0; }

have llama-bench || die "llama-bench not found in PATH. Run the installer first."
model="${1:-$(find "$OCL_MODELS" -maxdepth 1 -name '*.gguf' -type f 2>/dev/null | sort | head -n1 || true)}"
[[ -n "$model" && -f "$model" ]] || die "no model given and none found in $OCL_MODELS"
threads="${2:-$(nproc 2>/dev/null || echo 4)}"

mkdir -p "$OCL_STATE"
{
  echo
  echo "## $(basename "$model") - $(date -Iseconds) - $(uname -m), $threads threads"
  echo
  llama-bench -m "$model" -t "$threads" -p 512 -n 128 -o md
} | tee -a "$OCL_STATE/bench.md"
log "results appended to $OCL_STATE/bench.md"
