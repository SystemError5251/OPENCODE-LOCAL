# Simulation run of the test checklist (2026-10-25)

`docs/test-checklist.md` run in a cloud container instead of a phone: Ubuntu 24.04, x86_64,
4 CPU cores, 16 GB RAM. Everything that needs the phone, a real PC host or Windows is marked as such.
These numbers are **not** phone numbers; fill `docs/phase0-results.md` from the device.

## 1. Install

| Step | Result |
|---|---|
| `install-linux.sh` (system packages, llama.cpp `b11857` build) | ok |
| OpenCode build from source | not possible here: `bun install` needs `ghostty-web` from `api.github.com`, which this container blocks. Not a script bug, but it shows the source build depends on GitHub tarballs and `pkg.pr.new` besides npm. |
| `install-linux.sh --prebuilt-opencode` (new) | ok, `checksum ok: opencode-linux-x64.tar.gz`, `opencode --version` → 1.19.4 |
| Official `opencode-linux-arm64` 1.19.4 under qemu-aarch64 with an arm64 glibc | starts, `--version` → 1.19.4. So the prebuilt binary is a real option inside Debian proot. |

Found during the build:
- `-DLLAMA_CURL=OFF` no longer does anything in this llama.cpp version (deprecated). Downloads now go
  through the built-in HTTPS client, so the build uses `-DLLAMA_OPENSSL=OFF` instead.
- The build fetched the web UI from Hugging Face (falling back to an unpinned `latest`).
  Now off with `-DLLAMA_USE_PREBUILT_UI=OFF`; the server runs with `--no-webui` anyway.

## 2. Model and speed

`fetch-model.sh qwen2.5-coder-1.5b`: download ok, `checksum ok`.
All model hashes are now pinned in `ki-models/models.json`.

| Model | sha256 |
|---|---|
| qwen2.5-coder-0.5b | `1d9614638d18024d0fbb36575a15f1302a3adf044df10345688ec4f6e1c4ff32` |
| qwen2.5-coder-1.5b | `cc324af070c2ecbfd324a30884d2f951a7ff756aba85cb811a6ec436933bb046` (downloaded and verified) |
| qwen2.5-coder-3b | `724fb256bec1ff062b2f65e4569e871ad2e95ab2a3989723d1769c54294730b7` |
| qwen2.5-coder-7b | `1664fccab734674a50763490a8c6931b70e3f2f8ec10031b54806d30e5f956b6` |
| qwen2.5-coder-14b | `2946d28c9e1bb2bcae6d42e8678863a31775df6f740315c7d7e6d6b6411f5937` |
| qwen3-1.7b (new) | `061b54daade076b5d3362dac252678d17da8c68f07560be70818cace6590cb1a` (downloaded and verified) |
| qwen3-4b (new) | `7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5` (downloaded and verified) |

`scripts/bench.sh`, x86_64, 4 threads, CPU only:

| Model | pp512 (t/s) | tg128 (t/s) |
|---|---|---|
| qwen2.5-coder-1.5b Q4_K_M | 206.7 ± 24.4 | 17.6 ± 1.1 |
| qwen3-1.7b Q8_0 | 210.3 ± 8.8 | 22.1 ± 0.7 |
| qwen3-4b Q4_K_M | 94.1 ± 4.4 | 8.0 ± 0.3 |

## 3. and 4. Chat, permissions, security

Driven with `opencode run --format json`. To test the permission rules independently of model
quality, a scripted stand-in for llama-server issued exactly one tool call per test.
Without `--auto`, every `ask` is rejected; with `--auto`, every `ask` is approved, which shows what
the user would get by pressing "allow".

| Test | Result |
|---|---|
| read `hello.py` | runs without asking |
| edit `hello.py` | asks (rejected without approval, applied with approval) |
| `python3 hello.py` | asks, prints `hi` after approval |
| `curl https://example.com` | denied, even with approval |
| `rm -rf hello.py` | denied, even with approval; file still there |
| read `/etc/passwd`, `~/.bashrc` | denied (outside the project) |
| read `.env` | denied |
| `cat /etc/passwd` via bash | denied (outside the project) |
| `webfetch` | tool not offered to the model at all |
| `cat .env` via bash | **ran after approval** → now denied by new bash rules |
| `bash -c "curl ..."` | **ran after approval** → now denied (`*curl *` matches anywhere in the line) |
| Network cut (no proxy, no DNS) | OpenCode and llama-server keep working |

## 5. MCP tools

| Test | Result |
|---|---|
| `ocl_backup_create` | runs without asking, `backup 20261025-085154: 19 files, 10.1 KB` |
| `ocl_files_trash hello.py` | asks; after approval `.trash/` exists, `ocl_files_restore` brings it back |
| `ocl_crypto_encrypt hello.py` | asks; creates `hello.py.gpg`, original unchanged, reports the new key file |
| `ocl_video_info video.mp4` | duration 3.0 s, 640x360 h264 |
| `ocl_backup_list` | lists the backup |

## Real models in OpenCode

Same prompt with each real model, network cut: "What does hello.py do? Read it first."

| Model | Context | Result |
|---|---|---|
| qwen2.5-coder-1.5b | 8192 (old default) | never finished: OpenCode's prompt plus tools are ~7,500 tokens, so it compacted on every step; stopped after 5 min |
| qwen2.5-coder-1.5b | 16384 | finishes in 83 s, but writes the `read` call as JSON text instead of calling the tool |
| qwen3-1.7b | 16384 | calls `glob` and `read`, answers correctly, 206 s |
| qwen3-4b | 16384 | calls `read`, answers correctly, 510 s |

"Add a function add(a, b) to hello.py" (`--auto`):

| Model | Result |
|---|---|
| qwen3-1.7b | three `edit` attempts with a wrong `oldString`, no change after 10 min |
| qwen3-4b | read the file, then no edit within the 25 min limit (the CPU was shared with a parallel build, so slower than usual) |

Consequences in this change: default context 16384 with `--parallel 1`, Qwen3 1.7B as the
default phone model, Qwen2.5-Coder 1.5B/3B moved to tier `legacy`.

## Not covered here

- The phone itself: Termux, proot-distro, speed, heat, RAM. Memory on this x86 machine is not
  representative (extra buffers for its AMX CPU extension).
- 6. PC host via SSH tunnel: no SSH server here (the previous session tested it against a local sshd).
- 8. Windows: `install-windows.ps1 -Mode Native -DryRun` under PowerShell 7.4 on Linux lists all steps;
  the pinned zip hashes for x64 and arm64 match the real release files. `wsl.exe`, winget and the
  `.cmd` launcher need a real Windows PC.
- 7. `scripts/update.sh`: lists versions, says "nothing changed", installs nothing. The GitHub API is
  blocked here, so it showed the fallback (highest tag) instead of the latest release.
