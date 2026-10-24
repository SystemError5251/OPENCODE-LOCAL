# OpenCode-KI – Project plan "local only" (Termux, Linux, Windows)

## 1. Vision and principle
A personal AI coding assistant in the terminal, with OpenCode as the interface, that runs completely
offline and locally. No cloud provider, no API keys, no telemetry. All data stays on your own device
or in your own home network.

## 2. Honest constraints
- No model training of our own. Ready-made open models run locally (GGUF via llama.cpp).
- On a phone, models up to about 4B parameters (Q4) are realistic. For code they are clearly weaker
  than large models.
- More quality comes from your own PC in the home network acting as model host. That is still local in
  the sense of "no third-party cloud"; the connection stays in your own network or goes over an SSH tunnel.
- Android support for OpenCode / Bun is unclear and is checked in Phase 0.

## 3. Goals
- Works without internet after installation
- Same configuration on Termux, Linux and Windows
- Maximum safety: confirmation before writes and shell commands, restricted working directory, network blocked
- Own tools via MCP (encryption, video, backup), reuse of the AIO plugins
- Multilingual interface and rules (de/en first)

## 4. Architecture
```
OpenCode (client)
   │  OpenAI-compatible, only 127.0.0.1 or home-network IP
   ▼
llama-server (llama.cpp)  ──►  GGUF model (local)
   │
   ▼
MCP tools (Python, local): crypto, video, backup, files
```
- `ki-config/`: `opencode.json`, `AGENTS.md`, agent prompts, permissions
- `ki-tools/`: local MCP servers
- `ki-models/`: model list and download checksums
- Installer per platform: `install-termux.sh`, `install-linux.sh`, `install-windows.ps1`

## 5. Platform strategy
| Platform | Approach | Risk |
|---|---|---|
| Linux | OpenCode + llama.cpp directly | low |
| Windows | WSL2 preferred, native as an alternative | medium |
| Termux | Debian via `proot-distro`, build OpenCode from source there; llama.cpp directly in Termux (faster) | high |

**Android binary:** check Phase 0 first. If Bun/OpenCode runs under Debian proot, no native Android
binary is needed. A real native Android binary is plan B and expensive (own toolchain build, possibly
source changes).

## 6. Model choice (local)
| Device | Recommended size | Note |
|---|---|---|
| Phone 6–8 GB RAM | 1–3B, Q4 | simple tasks only, short context |
| Phone 12+ GB RAM | up to about 4–7B, Q4 | slow, watch battery and heat |
| PC 16–32 GB RAM | 7–14B | usable for coding |
| PC with GPU | 14B+ | clearly better |

Prefer models with a coding focus; verify checksums on download. The concrete list is in
`ki-models/models.json`.

## 7. Security concept
- Turn off auto-update, sharing and telemetry in OpenCode
- No provider entries except the local endpoint
- Bind `llama-server` to `127.0.0.1` only; home-network access only with a token and a firewall rule
- Android: block Termux's network access with a firewall app after the models are downloaded
- Permissions: reading is free, writing and shell only with confirmation, destructive commands
  (`rm -rf`, `curl | sh`) blocked
- Restrict the working directory, log all commands
- Source code and models only from official sources, compare checksums

Details: [security.md](security.md).

## 8. Phases and milestones
| Phase | Content | Result | Status |
|---|---|---|---|
| 0 – Feasibility | Does Bun/OpenCode run in Debian proot? Does llama.cpp run in Termux? | Clear yes/no list per device | OpenCode runs in Debian proot on the 8 GB phone |
| 1 – Local model | Build llama.cpp, start a small model, measure speed | Tokens/second known | scripts ready: `fetch-model.sh`, `bench.sh` – numbers from the phone pending |
| 2 – Connect OpenCode | Build from source, add local provider, telemetry off | Chat with the local model | done: OpenCode runs on the phone |
| 3 – Security | Permissions, directory limits, firewall, logging | Hardened default config | done; firewall documented (manual) |
| 4 – Own tools | MCP: encryption, video, backup | AI performs tasks locally | done: `ki-tools/` (files, backup, crypto, video) |
| 5 – More platforms | Linux and Windows (WSL2), installer scripts | Same behaviour everywhere | done: `install-windows.ps1` (WSL2 or native) – not yet run on a real Windows PC |
| 6 – Polish | Languages, docs, update script without auto-update | Release v1 | done: `scripts/update.sh`, `README.de.md`, `tests/run-all.sh` + CI, v1.0.0 |
| 7 – Optional | PC as model host in the home network, native Android binary | More quality or less overhead | PC host done (`scripts/tunnel.sh`); native Android binary not needed, Debian proot works |

## 9. Risks
- **OpenCode does not run under Android/Termux:** Debian proot or PC host as fallback
- **Small models give weak results:** keep tasks small, plan for a PC host
- **Heat, battery, storage:** targeted wake lock, charger, choose a small model
- **Build from source fails:** pin versions, document dependencies (`lib/common.sh`)
- **Agent with shell access:** strict approvals, restricted directory, logging

## 10. Next steps
1. Record device data: RAM, free storage, Android version (`scripts/phase0-check.sh`)
2. Run Phase 0: `proot-distro install debian`, test Bun and OpenCode there (`install-termux.sh`)
3. Build `llama.cpp` in Termux and run a 1–3B model as a test (`fetch-model.sh`, `bench.sh`)
4. Record results in [phase0-results.md](phase0-results.md), then decide: Debian proot, PC host or native binary

## 11. Open questions
- The phone has 8 GB RAM (known): target 1–3B models (Q4) with short context, maybe 4B as a test.
  Free storage still to check (`df -h ~`).
- Is there a PC in the home network that could act as model host?
- Should the system later become a plugin of the AIO tool?
