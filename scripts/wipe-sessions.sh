#!/usr/bin/env bash
# Delete every trace of past OpenCode sessions: sessions, messages, snapshots, logs and caches
# that OpenCode or older versions of this project wrote to disk. Since the launcher keeps each
# session in a temporary directory, this is only needed once, for data from before that change.
# Keeps: config, models, MCP tools, the crypto key, backups and trash in your projects.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-y] [-n]

  -y, --yes      do not ask for confirmation
  -n, --dry-run  only list what would be deleted
On Termux this also cleans the Debian (proot) side, where OpenCode runs.
Note: this also deletes the history of a normal (non-local) OpenCode install for this user.
EOF
}

yes=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) yes=1; shift ;;
    -n|--dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

data="${XDG_DATA_HOME:-$HOME/.local/share}"
state="${XDG_STATE_HOME:-$HOME/.local/state}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}"
targets=("$data/opencode" "$state/opencode" "$cache/opencode"
  "$OCL_STATE/sessions.log" "$OCL_STATE/llama-server.log" "$OCL_STATE/tunnel.log")
for d in "${XDG_RUNTIME_DIR:-}" /dev/shm "${TMPDIR:-/tmp}"; do
  [[ -n "$d" ]] && targets+=("$d/opencode-local-$(id -u)")
done

found=()
for t in "${targets[@]}"; do [[ -e "$t" ]] && found+=("$t"); done
if [[ ${#found[@]} -eq 0 ]]; then
  log "nothing to delete here"
else
  printf '  %s\n' "${found[@]}" >&2
  if [[ "$DRY_RUN" != 1 && "$yes" != 1 ]]; then
    read -r -p "Delete these permanently? [y/N] " answer
    [[ "$answer" == [yY]* ]] || die "cancelled"
  fi
  for t in "${found[@]}"; do run rm -rf -- "$t"; done
  [[ "$DRY_RUN" == 1 ]] || log "deleted ${#found[@]} item(s)"
fi

if is_termux && have proot-distro; then
  guest_args=(--yes)
  [[ "$DRY_RUN" == 1 ]] && guest_args=(--dry-run)
  log "cleaning the Debian side"
  proot-distro login debian --bind "$REPO_ROOT:/opt/opencode-local" -- \
    bash /opt/opencode-local/scripts/wipe-sessions.sh "${guest_args[@]}"
fi
