# OPENCODE-LOCAL
Fully local, offline AI coding assistant built on OpenCode and llama.cpp. Runs on Termux (Android), Linux and Windows. No cloud, no API keys, no telemetry. Hardened permissions, local MCP tools and multilingual setup for maximum privacy.

> Version 1.0.0 – all phases of the [project plan](docs/project-plan.md) are implemented.
> Deutsche Kurzanleitung: [README.de.md](README.de.md)

## How it works

```
opencode-local (launcher, offline env)
   │
OpenCode  ──HTTP, 127.0.0.1:8080──►  llama-server (llama.cpp)  ──►  GGUF model on disk
   │                                   └─ or: SSH tunnel to a PC in your home network
   └─ stdio ──► local MCP tools: files, backup, crypto, video
```

| Platform | llama.cpp | OpenCode |
|---|---|---|
| Linux | built from source | built from source with Bun |
| Termux (Android) | built natively in Termux | built inside Debian (`proot-distro`); only the current project is visible to it |
| Windows (WSL2, recommended) | same as Linux, inside WSL | same as Linux, inside WSL |
| Windows (native) | winget package `ggml.llamacpp` | official release zip, SHA-256 pinned |

Pinned versions (in [`lib/common.sh`](lib/common.sh)): llama.cpp `b11857`, OpenCode `v1.19.4`, Bun `1.4.4`.

## Quick start

Internet is needed once, for the install and the model download.

### Termux (Android)
```bash
pkg install git
git clone https://github.com/systemerror5251/opencode-local.git && cd opencode-local
scripts/phase0-check.sh            # device data + Phase 0 checklist
./install-termux.sh --dry-run      # see what will happen
./install-termux.sh --prebuilt-opencode   # official OpenCode release (sha256-pinned); drop the flag to build from source
scripts/fetch-model.sh qwen3-1.7b
scripts/bench.sh                   # tokens/s
mkdir -p ~/projects/myproject && cd ~/projects/myproject && opencode-local
```
`opencode-local` starts llama-server in the background if needed and waits until the model is loaded.
Stop it with `scripts/start-llama.sh --stop`.

### Linux
```bash
git clone https://github.com/systemerror5251/opencode-local.git && cd opencode-local
scripts/phase0-check.sh
./install-linux.sh --dry-run
./install-linux.sh
scripts/fetch-model.sh qwen3-1.7b
mkdir -p ~/projects/myproject && cd ~/projects/myproject && opencode-local
```

### Windows
```powershell
git clone https://github.com/systemerror5251/opencode-local.git; cd opencode-local
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -DryRun
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1                # WSL2 (recommended)
# or native:
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b
```
Then, in a new terminal, `cd` into a project and run `opencode-local`. WSL mode downloads models inside
WSL: `wsl -- bash /mnt/c/.../opencode-local/scripts/fetch-model.sh qwen3-1.7b`.
Native mode needs Python 3 for the MCP tools, and gpg / ffmpeg for the crypto / video tools.

Afterwards cut the network – see [docs/security.md](docs/security.md#network-lock-down).

## A PC as model host (more quality)

Phone models (1–3B) are weak. A PC in your home network can run a 7–14B model for the phone:

```bash
# on the PC (Linux/WSL): install and start the model - it stays on the PC's 127.0.0.1
./install-linux.sh && scripts/fetch-model.sh qwen2.5-coder-7b && scripts/start-llama.sh --background
# on the phone (Termux): pkg install openssh, then
scripts/start-llama.sh --stop          # free port 8080
scripts/tunnel.sh user@192.168.1.10    # encrypted SSH tunnel to the PC
cd ~/projects/myproject && opencode-local
scripts/tunnel.sh --stop               # back to the local model
```
Nothing in OpenCode's config changes; it still talks to `127.0.0.1`. Your firewall app must allow
Termux to reach the local network (LAN) for this.

## Updating (never automatic)

```bash
scripts/update.sh           # check only: pinned vs upstream versions, new commits in this repo
scripts/update.sh --apply   # git pull, then refresh config/tools; rebuilds only if a version pin changed
```
Manual equivalents: `./install-termux.sh --update` (Termux), `./install-linux.sh --config-only` (Linux),
`install-windows.ps1 -ConfigOnly` (Windows).

## Repository layout

| Path | Content |
|---|---|
| `ki-config/` | hardened `opencode.json`, global `AGENTS.md`, agent prompts (`coder`, `review`), `env.sh` |
| `ki-models/` | curated model list with checksums, [how to choose](ki-models/README.md) |
| `ki-tools/` | local MCP servers: files (trash/restore), backup, crypto (gpg), video (ffmpeg) – [details](ki-tools/README.md) |
| `scripts/` | `phase0-check`, `fetch-model`, `start-llama`, `ensure-llama`, `bench`, `tunnel`, `update`, `opencode-local` launcher |
| `install-*.sh`, `install-windows.ps1` | installers per platform |
| `lib/common.sh` | version pins and shared helpers |
| `tests/run-all.sh` | every offline check (also run by CI) |
| `docs/` | [project plan](docs/project-plan.md), [security](docs/security.md), [Phase 0 results](docs/phase0-results.md), [test checklist](docs/test-checklist.md) |

## Security defaults

- Only the local `llamacpp` provider is enabled; auto-update, sharing, LSP downloads and the remote model catalogue are off.
- Reading is free (except `.env`, keys, `*.pem`); every edit and every shell command asks first.
- `rm -r`, `sudo`, `curl`, `wget`, `ssh`, `git push`, package installers, web fetch/search are denied.
- Access outside the project directory is denied.
- Local MCP tools never delete or overwrite; every `ocl_*` tool that changes something asks first.
- llama-server listens on `127.0.0.1` only; other addresses require a long API key. The PC host uses an SSH tunnel instead.
- All downloads are HTTPS, pinned and checksum-verified; nothing is piped into a shell.

Details and reasoning: [docs/security.md](docs/security.md).

## Development

```bash
tests/run-all.sh
```
Runs shellcheck, syntax and JSON checks, the MCP server tests, the PowerShell parser (if `pwsh` is
installed) and installer dry runs. See [CHANGELOG.md](CHANGELOG.md).

## Limits

Phone-sized models (1–3B) are much weaker than cloud models, especially at tool calls. Keep tasks
small, or use a PC as model host (see above).
