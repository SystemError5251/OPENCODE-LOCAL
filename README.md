# OPENCODE-LOCAL
Fully local, offline AI coding assistant built on OpenCode and llama.cpp. Runs on Termux (Android), Linux and Windows. No cloud, no API keys, no telemetry. Hardened permissions, local MCP tools and multilingual setup for maximum privacy.

> Version 1.1.0 – all phases of the [project plan](docs/project-plan.md) are implemented.
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
| Linux | built from source | official release binary, sha256-pinned (`--from-source` builds it with Bun) |
| Termux (Android) | built natively in Termux | release binary inside Debian (`proot-distro`); only the current project is visible to it |
| Windows (WSL2, recommended) | same as Linux, inside WSL | same as Linux, inside WSL |
| Windows (native) | winget package `ggml.llamacpp` | official release zip, SHA-256 pinned |

Pinned versions (in [`lib/common.sh`](lib/common.sh)): llama.cpp `b11857`, OpenCode `v1.19.4`, Bun `1.4.4`.

## Quick start

You need internet once, for the install and the model download (about 2 GB). Copy each block as it is;
every line is safe to run again.

### Termux (Android)

Install Termux from F-Droid or GitHub (the Play Store version is outdated), then:

```bash
pkg install -y git
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git ~/opencode-local || git -C ~/opencode-local pull
cd ~/opencode-local
./quickstart.sh
```

`quickstart.sh` installs llama.cpp (built in Termux, takes 10–20 minutes), a Debian environment with the
official OpenCode release (sha256-checked), downloads a model that fits your RAM and prints the next
step. Then start OpenCode in a project folder:

```bash
mkdir -p ~/projects/myproject && cd ~/projects/myproject && opencode-local
```

### Linux (and WSL2)

```bash
sudo apt-get install -y git     # or dnf / pacman
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git ~/opencode-local || git -C ~/opencode-local pull
cd ~/opencode-local
./quickstart.sh
```

If it prints an `export PATH=...` line, run it and add it to `~/.bashrc`. Then:

```bash
mkdir -p ~/projects/myproject && cd ~/projects/myproject && opencode-local
```

### Windows

WSL2 is recommended: run the Linux steps inside it. Without WSL, in PowerShell:

```powershell
git clone https://github.com/SystemError5251/OPENCODE-LOCAL.git $HOME\opencode-local
cd $HOME\opencode-local
powershell -ExecutionPolicy Bypass -File .\install-windows.ps1 -Mode Native -FetchModel qwen3-1.7b
```

Open a new terminal, `cd` into a project folder and run `opencode-local`. Native mode needs Python 3 for
the MCP tools, and gpg / ffmpeg for the crypto / video tools.

### Options and what to expect

| | |
|---|---|
| Other model | `./quickstart.sh --model qwen3-4b` (list: `scripts/fetch-model.sh --list`) |
| Build OpenCode from source | `./quickstart.sh --from-source` (slow, needs a lot more RAM and network) |
| See every step first | `./quickstart.sh --dry-run` |
| Speed test | `scripts/bench.sh` |
| Stop the model | `scripts/start-llama.sh --stop` (Termux: then `termux-wake-unlock`) |

`opencode-local` starts the model in the background if needed and waits until it is loaded. On a phone
the first answer of a session takes minutes: OpenCode sends about 7,500 tokens of instructions with every
request, and a phone CPU reads them slowly. Later answers in the same session are faster. For simple things
like creating a folder, the normal shell is quicker.

When the install and download are done, block the network – see [docs/security.md](docs/security.md#network-lock-down).

### Troubleshooting

| Problem | Fix |
|---|---|
| `fatal: destination path ... already exists` | harmless: the second half of that line updates the existing copy |
| `No such file or directory` for `./quickstart.sh` or `scripts/...` | you are not in the repo folder: `cd ~/opencode-local` |
| `opencode: No such file or directory` | OpenCode is missing (interrupted install): run `./quickstart.sh` again |
| An old model or context size is used | `scripts/start-llama.sh --stop`, then start `opencode-local` again |
| `opencode-local: command not found` (Linux) | run the `export PATH=...` line that `quickstart.sh` printed |
| Model server does not start | run `scripts/start-llama.sh` without options: it stays in the foreground and shows the error |

## A PC as model host (more quality)

Phone models (1–4B) are weak, especially at editing files. A PC in your home network can run a 7–14B model for the phone:

```bash
# on the PC (Linux/WSL): install and start the model - it stays on the PC's 127.0.0.1
./quickstart.sh --model qwen2.5-coder-7b && scripts/start-llama.sh --background
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
| `scripts/` | `phase0-check`, `fetch-model`, `start-llama`, `ensure-llama`, `bench`, `tunnel`, `update`, `wipe-sessions`, `opencode-local` launcher |
| `quickstart.sh` | one-command install + model download for Termux and Linux |
| `install-*.sh`, `install-windows.ps1` | installers per platform |
| `lib/common.sh` | version pins and shared helpers |
| `tests/run-all.sh` | every offline check (also run by CI) |
| `docs/` | [project plan](docs/project-plan.md), [security](docs/security.md), [Phase 0 results](docs/phase0-results.md), [test checklist](docs/test-checklist.md), [simulation results](docs/simulation-results.md) |

## Security defaults

- Only the local `llamacpp` provider is enabled; auto-update, sharing, LSP downloads and the remote model catalogue are off.
- Reading is free (except `.env`, keys, `*.pem`); every edit and every shell command asks first.
- `rm -r`, `sudo`, `curl`, `wget`, `ssh`, `git push`, package installers, web fetch/search are denied.
- Access outside the project directory is denied.
- Local MCP tools never delete or overwrite; every `ocl_*` tool that changes something asks first.
- No session history or logs: each OpenCode session (messages, snapshots, logs, cache, temp files) lives in a
  private temporary folder, in RAM where possible, that is deleted when OpenCode exits. Server and tunnel
  output is discarded. `scripts/wipe-sessions.sh` removes data from older versions once.
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

Phone-sized models (1–4B) are much weaker than cloud models, especially at tool calls. Keep tasks
small, or use a PC as model host (see above).
