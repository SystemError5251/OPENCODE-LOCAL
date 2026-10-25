# Changelog

## Unreleased

Fixes from a simulation run of the test checklist (`docs/simulation-results.md`).

### Added
- `--prebuilt-opencode` for `install-linux.sh` and `install-termux.sh`: official OpenCode release binary,
  sha256-pinned, instead of the source build (no Bun, no ~2500 npm packages).
- Models `qwen3-1.7b` (new phone default) and `qwen3-4b`; every model hash in `models.json` is pinned.

### Changed
- Context 8192 → 16384 and `--parallel 1`: OpenCode's prompt plus tools already need ~7,500 tokens,
  with 8192 it compacted on every step and never finished.
- Qwen2.5-Coder 1.5B/3B moved to tier `legacy`: they write tool calls as text instead of calling them.

### Fixed
- llama.cpp build: `-DLLAMA_OPENSSL=OFF` replaces the deprecated, no-op `-DLLAMA_CURL=OFF`, so the server
  really cannot download models; `-DLLAMA_USE_PREBUILT_UI=OFF` stops the build fetching the web UI.
- Bash rules: `curl`/`wget` and `.env` are denied anywhere in a command line (e.g. inside `bash -c "…"`),
  not only at the start. Both got through after a click on "allow" before.
- `tunnel.sh --dry-run` works without ssh installed.

## 1.0.0 – 2026-10-24

First complete version of the project plan (Phases 0–7).

### Added
- **Phase 0/1:** `scripts/phase0-check.sh` (device report), `scripts/fetch-model.sh` (SHA-256 verified
  downloads), `scripts/bench.sh` (tokens/s), curated model list `ki-models/models.json`.
- **Phase 2:** source builds of llama.cpp `b11857` and OpenCode `v1.19.4` with Bun `1.4.4`
  (`install-linux.sh`, `install-termux.sh`); OpenCode runs in Debian proot on Android, llama.cpp natively.
- **Phase 3:** hardened `ki-config/opencode.json` (local provider only, ask before edit/shell,
  network and destructive commands denied, no access outside the project), `env.sh` offline flags,
  `docs/security.md`.
- **Phase 4:** local MCP tools in `ki-tools/` – files (trash/restore), backup, crypto (gpg), video
  (ffmpeg); standard library only, sandboxed to the project, never delete or overwrite.
- **Phase 5:** `install-windows.ps1` – WSL2 (recommended, same pinned build as Linux) or native
  (pinned, SHA-256 checked OpenCode release + winget llama.cpp).
- **Phase 6:** `scripts/update.sh` (check-only by default, `--apply` pulls and reinstalls; never
  automatic), `install-termux.sh --update`, German quick start (`README.de.md`), `tests/run-all.sh`
  and CI.
- **Phase 7:** `scripts/tunnel.sh` – a PC in the home network as model host over an SSH tunnel; the PC's
  llama-server stays on its own 127.0.0.1. `scripts/ensure-llama.sh` uses the tunnel if it is up and
  otherwise starts the local server.

### Fixed during development
- llama.cpp is built with static libraries so the installed binaries keep working without the build dir.
- Health checks treat HTTP 503 ("model loading") as not ready.
- No `cat *` auto-allow, which would have bypassed the `.env`/key read rules.
- MCP tools need an explicit `ocl_*: ask` rule; OpenCode allows unknown permissions by default.
