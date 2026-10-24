#!/usr/bin/env bash
# Install OPENCODE-LOCAL on Linux (also used inside Debian proot on Termux and in WSL2).
set -euo pipefail
# shellcheck source=SCRIPTDIR/lib/common.sh
source "$(dirname "$0")/lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Builds llama.cpp ($LLAMA_CPP_TAG) and OpenCode ($OPENCODE_TAG) from source,
installs Bun $BUN_VERSION (checksum-verified) and the hardened config.
Needs internet once; afterwards everything runs offline.

  -n, --dry-run      print every step without changing anything
      --skip-deps    do not install system packages
      --no-llama     skip llama.cpp (used by install-termux.sh, which builds it natively)
      --no-opencode  skip Bun and OpenCode
      --config-only  only (re)install ki-config/ and ki-tools/ (use after git pull)
EOF
}

skip_deps=0 no_llama=0 no_opencode=0 config_only=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--dry-run) DRY_RUN=1; shift ;;
    --skip-deps) skip_deps=1; shift ;;
    --no-llama) no_llama=1; shift ;;
    --no-opencode) no_opencode=1; shift ;;
    --config-only) config_only=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

is_termux && die "this is Termux - use ./install-termux.sh"

sudo_cmd=()
[[ "$(id -u)" -ne 0 ]] && sudo_cmd=(sudo)

install_deps() {
  if have apt-get; then
    run "${sudo_cmd[@]}" apt-get update
    run "${sudo_cmd[@]}" apt-get install -y --no-install-recommends \
      git cmake build-essential curl unzip jq ca-certificates python3 gnupg ffmpeg
  elif have dnf; then
    run "${sudo_cmd[@]}" dnf install -y git cmake gcc-c++ make curl unzip jq python3 gnupg2 ffmpeg-free
  elif have pacman; then
    run "${sudo_cmd[@]}" pacman -S --needed --noconfirm git cmake base-devel curl unzip jq python gnupg ffmpeg
  else
    die "no supported package manager (apt, dnf, pacman); install git cmake g++ make curl unzip jq python3 gnupg ffmpeg yourself and use --skip-deps"
  fi
}

log "OPENCODE-LOCAL installer (linux)$([[ "$DRY_RUN" == 1 ]] && echo ' [dry run]')"

if [[ "$config_only" == 0 ]]; then
  [[ "$skip_deps" == 1 ]] || install_deps
  [[ "$no_llama" == 1 ]] || build_llama_cpp "$OCL_BIN"
  if [[ "$no_opencode" == 0 ]]; then
    install_bun
    build_opencode
  fi
fi

install_config
run install -D -m 0755 "$REPO_ROOT/scripts/opencode-local" "$OCL_BIN/opencode-local"

case ":$PATH:" in
  *":$OCL_BIN:"*) ;;
  *) warn "$OCL_BIN is not in PATH. Add this to your shell profile: export PATH=\"$OCL_BIN:\$PATH\"" ;;
esac

cat >&2 <<EOF

Done. Next steps:
  1. scripts/fetch-model.sh --list
  2. scripts/fetch-model.sh qwen2.5-coder-1.5b
  3. scripts/start-llama.sh --background
  4. cd into a project and run: opencode-local
After step 2 you can cut the network (see docs/security.md).
EOF
