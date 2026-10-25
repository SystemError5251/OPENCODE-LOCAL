# shellcheck shell=bash
# Shared helpers for the OPENCODE-LOCAL scripts. Source it, do not execute it.

# --- Version pins ------------------------------------------------------------
# Change these deliberately and re-test; never track "latest".
LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp.git"
LLAMA_CPP_TAG="b11857"
OPENCODE_REPO="https://github.com/sst/opencode.git"
OPENCODE_TAG="v1.19.4"
# Official release archives for --prebuilt-opencode (sha256 of the .tar.gz, checked 2026-10-25).
OPENCODE_SHA256_LINUX_X64="849bd6b3d959a1d2ef200ed1634a51c79a45ca236aa26665d75debd694805cce"
OPENCODE_SHA256_LINUX_ARM64="8568230ccd847dc93e95b9f6894379077d3e014a16b48040743573e77c23e85f"
BUN_VERSION="1.4.4" # must match "packageManager" in OpenCode's package.json

# --- Paths -------------------------------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCL_HOME="${OCL_HOME:-$HOME/.local/share/opencode-local}"
OCL_STATE="${OCL_STATE:-$HOME/.local/state/opencode-local}"
OCL_MODELS="${OCL_MODELS:-$OCL_HOME/models}"
OCL_BIN="${OCL_BIN:-$HOME/.local/bin}"
OPENCODE_CONFIG_DIR_TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"

DRY_RUN="${DRY_RUN:-0}"

# No logs by default: server and tunnel output is discarded. OCL_DEBUG_LOG=1 writes it to $OCL_STATE
# for troubleshooting; delete those files afterwards (scripts/wipe-sessions.sh).
debug_log() { if [[ "${OCL_DEBUG_LOG:-0}" == 1 ]]; then echo "$OCL_STATE/$1"; else echo /dev/null; fi; }

# --- Logging -----------------------------------------------------------------
log()  { printf '\033[1;34m[ocl]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[1;33m[ocl] warning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ocl] error:\033[0m %s\n' "$*" >&2; exit 1; }

# Run a command, or only print it in dry-run mode.
run() {
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '\033[2m[dry-run]\033[0m %s\n' "$*" >&2
  else
    "$@"
  fi
}

have() { command -v "$1" >/dev/null 2>&1; }

is_termux() { [[ -n "${TERMUX_VERSION:-}" || -d /data/data/com.termux/files/usr ]] && [[ "${PREFIX:-}" == *com.termux* ]]; }

# --- Checksums -----------------------------------------------------------------
sha256_of() {
  if have sha256sum; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

# verify_sha256 FILE EXPECTED -> exits non-zero on mismatch
verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    warn "checksum mismatch for $file"
    warn "  expected: $expected"
    warn "  actual:   $actual"
    return 1
  fi
  log "checksum ok: $(basename "$file")"
}

# --- Downloads -------------------------------------------------------------------
# download URL DEST: HTTPS only, resumable, fails on HTTP errors. Never pipes into a shell.
download() {
  local url="$1" dest="$2"
  [[ "$url" == https://* ]] || die "refusing non-HTTPS download: $url"
  run curl --fail --location --proto '=https' --tlsv1.2 --retry 3 -C - -o "$dest" "$url"
}

# --- Build helpers ---------------------------------------------------------------
# build_llama_cpp PREFIX: clone the pinned tag and build static llama-server + llama-bench.
build_llama_cpp() {
  local prefix="$1" src="$OCL_HOME/src/llama.cpp" jobs
  jobs="$(nproc 2>/dev/null || echo 2)"
  run mkdir -p "$OCL_HOME/src" "$prefix"
  if [[ -d "$src/.git" ]]; then
    run git -C "$src" fetch --depth 1 origin tag "$LLAMA_CPP_TAG"
    run git -C "$src" checkout -q "$LLAMA_CPP_TAG"
  else
    run git clone --depth 1 --branch "$LLAMA_CPP_TAG" "$LLAMA_CPP_REPO" "$src"
  fi
  # LLAMA_OPENSSL=OFF: no HTTPS client, so the server can never download models by itself
  #   (LLAMA_CURL is deprecated and no longer does this).
  # LLAMA_USE_PREBUILT_UI=OFF: do not fetch the web UI from Hugging Face during the build.
  # BUILD_SHARED_LIBS=OFF: self-contained binaries that keep working after the build dir is gone.
  run cmake -S "$src" -B "$src/build" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
    -DLLAMA_OPENSSL=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF
  run cmake --build "$src/build" --target llama-server llama-bench -j"$jobs"
  for b in llama-server llama-bench; do
    run install -m 0755 "$src/build/bin/$b" "$prefix/$b"
  done
  log "llama.cpp $LLAMA_CPP_TAG installed to $prefix"
}

# install_bun: fetch the pinned Bun release zip from GitHub and verify it against SHASUMS256.txt.
install_bun() {
  local arch asset tmp base
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" ;;
    aarch64|arm64) arch="aarch64" ;;
    *) die "unsupported CPU for Bun: $(uname -m)" ;;
  esac
  asset="bun-linux-$arch"
  base="https://github.com/oven-sh/bun/releases/download/bun-v$BUN_VERSION"
  if have bun && [[ "$(bun --version 2>/dev/null)" == "$BUN_VERSION" ]]; then
    log "bun $BUN_VERSION already installed"
    return 0
  fi
  tmp="$(mktemp -d)"
  download "$base/$asset.zip" "$tmp/$asset.zip"
  download "$base/SHASUMS256.txt" "$tmp/SHASUMS256.txt"
  if [[ "$DRY_RUN" != 1 ]]; then
    verify_sha256 "$tmp/$asset.zip" "$(awk -v f="$asset.zip" '$2==f {print $1}' "$tmp/SHASUMS256.txt")" \
      || die "bun download failed verification"
  fi
  run unzip -q -o "$tmp/$asset.zip" -d "$tmp"
  run install -D -m 0755 "$tmp/$asset/bun" "$HOME/.bun/bin/bun"
  run rm -rf "$tmp"
  export PATH="$HOME/.bun/bin:$PATH"
  log "bun $BUN_VERSION installed to ~/.bun/bin"
}

# build_opencode: clone the pinned OpenCode tag and build a single native binary.
build_opencode() {
  local src="$OCL_HOME/src/opencode" out
  run mkdir -p "$OCL_HOME/src" "$OCL_BIN"
  if [[ -d "$src/.git" ]]; then
    run git -C "$src" fetch --depth 1 origin tag "$OPENCODE_TAG"
    run git -C "$src" checkout -q "$OPENCODE_TAG"
  else
    run git clone --depth 1 --branch "$OPENCODE_TAG" "$OPENCODE_REPO" "$src"
  fi
  run bash -c "cd '$src' && bun install --frozen-lockfile"
  run bash -c "cd '$src/packages/opencode' && OPENCODE_DISABLE_AUTOUPDATE=1 bun run script/build.ts --single --skip-embed-web-ui"
  if [[ "$DRY_RUN" == 1 ]]; then
    printf '\033[2m[dry-run]\033[0m install dist/opencode-*/bin/opencode -> %s/opencode\n' "$OCL_BIN" >&2
    return 0
  fi
  out="$(find "$src/packages/opencode/dist" -path '*/bin/opencode' -type f | head -n1)"
  [[ -n "$out" ]] || die "OpenCode build produced no binary"
  install -m 0755 "$out" "$OCL_BIN/opencode"
  log "OpenCode $OPENCODE_TAG installed to $OCL_BIN/opencode"
}

# install_opencode_prebuilt: the official release binary for $OPENCODE_TAG, checked against the pinned sha256.
# Much lighter than build_opencode (no Bun, no ~2500 npm packages), which matters on a phone.
install_opencode_prebuilt() {
  local arch sha tmp asset
  case "$(uname -m)" in
    x86_64|amd64) arch="x64" sha="$OPENCODE_SHA256_LINUX_X64" ;;
    aarch64|arm64) arch="arm64" sha="$OPENCODE_SHA256_LINUX_ARM64" ;;
    *) die "no prebuilt OpenCode for $(uname -m); build from source instead" ;;
  esac
  asset="opencode-linux-$arch.tar.gz"
  tmp="$(mktemp -d)"
  run mkdir -p "$OCL_BIN"
  download "https://github.com/sst/opencode/releases/download/$OPENCODE_TAG/$asset" "$tmp/$asset"
  if [[ "$DRY_RUN" != 1 ]]; then
    verify_sha256 "$tmp/$asset" "$sha" || { rm -rf "$tmp"; die "OpenCode download failed verification"; }
  fi
  run tar -xzf "$tmp/$asset" -C "$tmp"
  run install -m 0755 "$tmp/opencode" "$OCL_BIN/opencode"
  run rm -rf "$tmp"
  log "OpenCode $OPENCODE_TAG (official release) installed to $OCL_BIN/opencode"
}

# --- Config ------------------------------------------------------------------------
# install_config: copy ki-config/ into ~/.config/opencode, backing up what is there.
install_config() {
  local dst="$OPENCODE_CONFIG_DIR_TARGET" stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  if [[ -e "$dst/opencode.json" || -e "$dst/opencode.jsonc" || -e "$dst/AGENTS.md" ]]; then
    run cp -a "$dst" "$dst.bak-$stamp"
    log "existing config backed up to $dst.bak-$stamp"
  fi
  run mkdir -p "$dst/agents"
  run install -m 0644 "$REPO_ROOT/ki-config/opencode.json" "$dst/opencode.json"
  run install -m 0644 "$REPO_ROOT/ki-config/AGENTS.md" "$dst/AGENTS.md"
  for f in "$REPO_ROOT"/ki-config/agents/*.md; do
    run install -m 0644 "$f" "$dst/agents/$(basename "$f")"
  done
  run mkdir -p "$OCL_HOME"
  run install -m 0644 "$REPO_ROOT/ki-config/env.sh" "$OCL_HOME/env.sh"
  # Local MCP servers (Phase 4), referenced from opencode.json.
  run mkdir -p "$OCL_HOME/tools"
  for f in "$REPO_ROOT"/ki-tools/*.py; do
    run install -m 0644 "$f" "$OCL_HOME/tools/$(basename "$f")"
  done
  log "config and MCP tools installed to $dst and $OCL_HOME/tools"
}
