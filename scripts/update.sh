#!/usr/bin/env bash
# Manual updates, never automatic. Default: only CHECK and report. --apply: pull this repo and
# reinstall what changed. Upstream versions only change when the pins in lib/common.sh change.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--apply]

  (default)  show the pinned versions, the newest upstream releases and whether this
             repository has new commits. Changes nothing.
  --apply    git pull --ff-only, then refresh config/tools; rebuild only if a pin changed.

Needs network access - unblock it in your firewall for the update, block it again afterwards.
EOF
}

apply=0
case "${1:-}" in
  --apply) apply=1 ;;
  -h|--help) usage; exit 0 ;;
  "") ;;
  *) usage; exit 2 ;;
esac

# latest_release REPO_URL PATTERN: the release GitHub marks as "latest" (what most users get).
# Falls back to the highest matching tag, which can be a pre-release track.
latest_release() {
  local web="${1%.git}" url
  url="$(curl --silent --proto '=https' --max-time 15 -o /dev/null -w '%{redirect_url}' "$web/releases/latest" || true)"
  if [[ "$url" == */releases/tag/* ]]; then
    echo "${url##*/}"
  else
    local tag
    tag="$(git ls-remote --tags --refs "$1" 2>/dev/null | awk -F/ '{print $3}' | grep -E "$2" | sort -V | tail -n1 || true)"
    [[ -n "$tag" ]] && echo "$tag (highest tag - may be a pre-release)"
  fi
  return 0
}

pins() { grep -E '^(LLAMA_CPP_TAG|OPENCODE_TAG|BUN_VERSION)=' "$REPO_ROOT/lib/common.sh"; }

log "pinned:  llama.cpp $LLAMA_CPP_TAG, OpenCode $OPENCODE_TAG, Bun $BUN_VERSION"
log "checking upstream (read-only)..."
up_llama="$(latest_release "$LLAMA_CPP_REPO" '^b[0-9]+$')"
up_oc="$(latest_release "$OPENCODE_REPO" '^v[0-9]+\.[0-9]+\.[0-9]+$')"
log "upstream: llama.cpp ${up_llama:-?}, OpenCode ${up_oc:-?}"
if [[ -n "$up_oc" && "${up_oc%% *}" != "$OPENCODE_TAG" ]]; then
  log "  OpenCode differs from the pin. To move: change OPENCODE_TAG, the OPENCODE_SHA256_* release"
  log "  hashes (and BUN_VERSION to match its package.json) in lib/common.sh and install-windows.ps1,"
  log "  re-check ki-config against its docs, test, commit."
fi

branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
if git -C "$REPO_ROOT" fetch --quiet origin "$branch" 2>/dev/null; then
  behind="$(git -C "$REPO_ROOT" rev-list --count "HEAD..origin/$branch")"
  log "this repository ($branch): $behind new commit(s) on origin"
else
  behind=0
  warn "could not reach origin for $branch"
fi

[[ "$apply" == 1 ]] || { log "nothing changed (run with --apply to update)"; exit 0; }
[[ "$behind" -gt 0 ]] || { log "already up to date"; exit 0; }

[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || die "local changes in $REPO_ROOT - commit or stash them first"
before="$(pins)"
git -C "$REPO_ROOT" pull --ff-only origin "$branch"
after="$(pins)"

if is_termux; then
  if [[ "$before" == "$after" ]]; then
    "$REPO_ROOT/install-termux.sh" --update
  else
    log "version pins changed - full rebuild"
    "$REPO_ROOT/install-termux.sh" --skip-deps
  fi
else
  if [[ "$before" == "$after" ]]; then
    "$REPO_ROOT/install-linux.sh" --config-only
  else
    log "version pins changed - full rebuild"
    "$REPO_ROOT/install-linux.sh" --skip-deps
  fi
fi
log "update done"
