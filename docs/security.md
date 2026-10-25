# Security

## Threat model

| Threat | Mitigation |
|---|---|
| Code or prompts leave the device | Only one provider (`llamacpp` → `127.0.0.1`), `enabled_providers` allowlist, sharing disabled, network blocked after setup |
| Agent runs a destructive or exfiltrating command | Every shell command asks first; `rm -r`, `sudo`, `curl`, `wget`, `ssh`, `git push`, package installers are denied outright |
| Agent edits files unnoticed | `edit: ask` – every write needs approval |
| Agent reads secrets | `.env`, SSH keys, `*.pem`, `*.key` reads are denied; no `cat` auto-allow that could bypass this |
| Agent leaves the project | `external_directory: deny`; on Termux only the current project is bind-mounted into Debian |
| Model server reachable from the network | `llama-server` binds to `127.0.0.1`; other addresses are refused without a 24+ character API key |
| Tampered downloads | Pinned versions (`lib/common.sh`), HTTPS only, Bun checked against `SHASUMS256.txt`, models checked against SHA-256, never `curl \| sh` |
| MCP tool does damage | Tools never delete or overwrite, paths are sandboxed to the project, every changing `ocl_*` tool asks first (see [ki-tools/README.md](../ki-tools/README.md)) |
| Encryption key leaks to the model | Passphrase lives outside the project (0600) and is passed to gpg as a file, never in tool input/output |
| Silent updates change behaviour | `autoupdate: false` + `OPENCODE_DISABLE_AUTOUPDATE=1`; updates only by changing the pins |

## What each setting does

### `ki-config/opencode.json`
- `enabled_providers: ["llamacpp"]` – every other provider (OpenAI, Anthropic, …) is ignored even if keys exist.
- `autoupdate: false`, `share: "disabled"` – no update checks, no session sharing.
- `lsp: false`, `formatter: false` – OpenCode would otherwise download language servers or call
  formatters such as `npx prettier`, which can reach the network.
- `experimental.openTelemetry: false` – tracing stays off (it is opt-in already; set explicitly).
- `permission` – rules are matched in order and the **last matching rule wins**, so the `"*": "ask"`
  catch-all comes first and the specific allows/denies after it.
  - `webfetch`, `websearch`: deny
  - `doom_loop`: deny (stops a model that repeats the same tool call)
  - `skill`: ask, `task` (subagents): allow – subagents inherit the same permission rules
  - `ocl_*`: ask – our MCP tools. Without this rule they would run unasked, because OpenCode allows
    unknown permissions by default. Read-only tools and `ocl_backup_create` are allowed after it.

### `ki-config/env.sh`
Sourced by the `opencode-local` launcher:

| Variable | Effect |
|---|---|
| `OPENCODE_DISABLE_AUTOUPDATE=1` | no update checks |
| `OPENCODE_DISABLE_MODELS_FETCH=1` | no download of the models.dev catalogue |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=1` | no language server downloads |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS=1` | no built-in cloud login plugins |
| `OPENCODE_DISABLE_CLAUDE_CODE=1` | ignore `~/.claude` prompts and skills |
| `NO_PROXY=localhost,127.0.0.1` | local traffic never goes through a proxy |

### Approval mode
Never start OpenCode with `--auto` – it approves every request that is not explicitly denied.
Choosing **always** in an approval prompt is valid only for the current session.

## Network lock-down

Download everything first (installer + `scripts/fetch-model.sh`), then cut the network.

### Android
Use a no-root firewall app (for example NetGuard or RethinkDNS) and block **Termux** for both Wi-Fi and
mobile data. llama-server and OpenCode talk over `127.0.0.1`, which these apps do not block.
Unblock temporarily only to update.

### Linux
To run fully offline per process without touching the system firewall:
```bash
unshare -rn opencode-local   # new network namespace with loopback only
```
Note: llama-server must then run in the same namespace, or use the system firewall instead.

### Model host in the home network (Phase 7)
**Recommended: SSH tunnel** (`scripts/tunnel.sh user@pc`). The PC's llama-server stays on its own
`127.0.0.1`, so nothing is exposed to the network. Traffic is encrypted and authenticated by SSH, and
OpenCode's config does not change. Use SSH keys (`ssh-keygen`, `ssh-copy-id`) and disable password login
on the PC. On Android the firewall app must allow Termux to reach the LAN, but not the internet.

**Alternative without SSH** (plain HTTP on the LAN, only with key + firewall):
1. Generate a key: `openssl rand -hex 24`, export it as `OCL_LLAMA_API_KEY` on host and client.
2. Start on the host: `scripts/start-llama.sh --host 192.168.1.10`.
3. Allow only the client, e.g. with ufw:
   ```bash
   sudo ufw allow from 192.168.1.20 to any port 8080 proto tcp
   sudo ufw deny 8080/tcp
   ```
4. On the client change `baseURL` in `~/.config/opencode/opencode.json` to `http://192.168.1.10:8080/v1`.

### Windows notes
- WSL2 mode is the same pinned, source-built setup as Linux.
- Native mode:
  - The OpenCode release zip is checked against a SHA-256 pinned in `install-windows.ps1`.
  - llama.cpp comes from winget (`ggml.llamacpp`); winget checks its own manifest hash, but the
    version is not pinned.
  - File modes like 0600 for the crypto key do not apply on Windows. Keep the key in your user profile
    and back it up.

## No session history, no logs

Nothing about a session is kept once OpenCode exits.

| What | Where it goes |
|---|---|
| OpenCode sessions, messages, undo snapshots, its own logs (incl. tool calls), cache | private per-run folder `opencode-local-<uid>/run.*` in `$XDG_RUNTIME_DIR` or `/dev/shm` (RAM) if available, else `$TMPDIR`; deleted by `opencode-local` when OpenCode exits |
| Temp files of OpenCode, tools and commands it runs | same folder (`TMPDIR` points there) |
| Leftovers of a run that was killed (closed terminal, reboot) | deleted at the next start of `opencode-local` |
| llama-server and SSH tunnel output | discarded (`/dev/null`); `OCL_DEBUG_LOG=1` writes them to `~/.local/state/opencode-local/` for troubleshooting |
| Python bytecode of the MCP tools | not written (`PYTHONDONTWRITEBYTECODE=1`) |

Consequences: a session cannot be resumed after you quit, and undo works only within a session.

What stays, on purpose: the config, models, MCP tools, the crypto key
(`~/.local/share/opencode-local/keys/crypto.pass` – **back it up**), backups
(`~/.local/share/opencode-local/backups/`), the project's `.trash/`, and the Phase 0 / benchmark reports you
create yourself (`~/.local/state/opencode-local/`).

Data from versions before 1.1 (`~/.local/share/opencode`, `~/.local/state/opencode`, `~/.cache/opencode`,
`sessions.log`, `llama-server.log`, `tunnel.log`) is removed once with `scripts/wipe-sessions.sh`; on Termux it
also cleans the Debian side.

Limits: on Termux inside proot there is no RAM-backed folder, so the run folder is on flash storage and is
deleted normally, not overwritten (flash memory cannot be reliably overwritten anyway; use Android's device
encryption). Your shell's own history (`~/.bash_history`) is not touched. On native Windows the launcher uses
`%TEMP%` and deletes it afterwards; this path is untested.
