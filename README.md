# OPENCODE-LOCAL
Fully local, offline AI coding assistant built on OpenCode and llama.cpp. Runs on Termux (Android), Linux and Windows. No cloud, no API keys, no telemetry. Hardened permissions, local MCP tools and multilingual setup for maximum privacy.

> Status: Phases 0–3 (feasibility, local model, OpenCode wiring, hardening). MCP tools and the
> Windows installer are still open – see [docs/project-plan.md](docs/project-plan.md).

## How it works

```
opencode-local (launcher, offline env)
   │
OpenCode  ──HTTP, 127.0.0.1:8080──►  llama-server (llama.cpp)  ──►  GGUF model on disk
```

| Platform | llama.cpp | OpenCode |
|---|---|---|
| Linux / WSL2 | built from source | built from source with Bun |
| Termux | built natively in Termux | built inside Debian (`proot-distro`); only the current project is visible to it |

Pinned versions (in [`lib/common.sh`](lib/common.sh)): llama.cpp `b11857`, OpenCode `v1.19.4`, Bun `1.4.4`.

## Quick start

Internet is needed once, for the install and the model download.

### Termux (Android)
```bash
pkg install git
git clone https://github.com/systemerror5251/opencode-local.git && cd opencode-local
scripts/phase0-check.sh            # device data + Phase 0 checklist
./install-termux.sh --dry-run      # see what will happen
./install-termux.sh
scripts/fetch-model.sh qwen2.5-coder-1.5b
scripts/bench.sh                   # tokens/s
cd ~/projects/myproject && opencode-local
```
`opencode-local` starts llama-server in the background if needed. Stop it with `scripts/start-llama.sh --stop`.

### Linux / WSL2
```bash
git clone https://github.com/systemerror5251/opencode-local.git && cd opencode-local
scripts/phase0-check.sh
./install-linux.sh --dry-run
./install-linux.sh
scripts/fetch-model.sh qwen2.5-coder-1.5b
scripts/start-llama.sh --background
cd ~/projects/myproject && opencode-local
```

Then cut the network for Termux / the machine – see [docs/security.md](docs/security.md#network-lock-down).

## Repository layout

| Path | Content |
|---|---|
| `ki-config/` | hardened `opencode.json`, global `AGENTS.md`, agent prompts (`coder`, `review`), `env.sh` |
| `ki-models/` | curated model list with checksums, [how to choose](ki-models/README.md) |
| `ki-tools/` | local MCP servers (Phase 4, placeholder) |
| `scripts/` | `phase0-check.sh`, `fetch-model.sh`, `start-llama.sh`, `bench.sh`, `opencode-local` launcher |
| `lib/common.sh` | version pins and shared helpers |
| `docs/` | [project plan](docs/project-plan.md), [security](docs/security.md), [Phase 0 results](docs/phase0-results.md) |

## Security defaults

- Only the local `llamacpp` provider is enabled; auto-update, sharing, LSP downloads and the remote model catalogue are off.
- Reading is free (except `.env`, keys, `*.pem`); every edit and every shell command asks first.
- `rm -r`, `sudo`, `curl`, `wget`, `ssh`, `git push`, package installers, web fetch/search are denied.
- Access outside the project directory is denied.
- llama-server listens on `127.0.0.1` only; other addresses require a long API key.
- All downloads are HTTPS, pinned and checksum-verified; nothing is piped into a shell.

Details and reasoning: [docs/security.md](docs/security.md).

## Limits

Phone-sized models (1–3B) are much weaker than cloud models, especially at tool calls. Keep tasks
small, or use a PC in your home network as model host (Phase 7).
