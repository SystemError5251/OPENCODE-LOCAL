# Phase 0/1 results

Fill in one column per device. A simulation run in a cloud container (x86, not a phone) is in
`docs/simulation-results.md`. Get the values from `scripts/phase0-check.sh` and `scripts/bench.sh`.

## Devices

| Item | Phone | PC |
|---|---|---|
| Model / name | | |
| Android / OS version | | |
| CPU architecture | | |
| RAM total (GB) | 8 | |
| Free disk (GB) | | |

## Feasibility (yes / no + notes)

| Question | Phone | PC |
|---|---|---|
| llama.cpp builds natively | | |
| llama-server starts with the test model | | |
| `proot-distro install debian` works | n/a | n/a |
| Bun runs (`bun --version`) | | |
| OpenCode builds from source | | |
| `opencode --version` runs | | |
| OpenCode chats with llama-server | | |
| Tool calls work (model reads a file) | | |

## Speed (tokens/s from `scripts/bench.sh`)

| Model | Device | Threads | Prompt (pp512) | Generation (tg128) |
|---|---|---|---|---|
| qwen2.5-coder-0.5b | | | | |
| qwen2.5-coder-1.5b | | | | |
| qwen2.5-coder-3b | | | | |
| qwen3-1.7b | | | | |
| qwen3-4b | | | | |

## Decision

- [ ] Debian proot works → continue on the phone
- [ ] Too slow / not working → PC as model host (Phase 7)
- [ ] Native Android binary needed (plan B)

Notes:
