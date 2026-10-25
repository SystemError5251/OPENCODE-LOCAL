# Local MCP tools (Phase 4)

Four small MCP servers in plain Python (standard library only, nothing from pip). OpenCode starts them
over stdio in the project directory; none of them opens a network port.

| Server | Tools | Needs |
|---|---|---|
| `ocl_files` | `info`, `largest`, `trash`, `list_trash`, `restore`, `move`, `write`, `replace` | – |
| `ocl_backup` | `create`, `list`, `diff`, `restore` | – |
| `ocl_crypto` | `status`, `encrypt`, `decrypt` | `gpg` |
| `ocl_video` | `info`, `convert`, `trim` | `ffmpeg`, `ffprobe` |

In OpenCode the tools appear as `<server>_<tool>`, e.g. `ocl_backup_create`.

## Safety rules shared by all tools

- Every path is resolved inside the project directory; `..`, absolute paths and symlinks that lead
  outside are rejected.
- Nothing is overwritten and nothing is deleted:
  - `trash` moves files to `.trash/` in the project, and `restore` puts them back.
  - `write` and `replace` (the edit tools of the `lite` agent) first copy the old version to `.trash/`.
    They refuse secrets files (`.env`, keys) and remove line numbers or a literal `\n` that a small model
    copied in by mistake.
  - Backup restores go into a new `restored-<id>/` folder.
  - Encrypt and decrypt write new files and keep the original.
  - Video outputs must not already exist (`ffmpeg -n`).
- Permissions (in `ki-config/opencode.json`):
  - Every `ocl_*` tool asks first.
  - Read-only tools and `ocl_backup_create` run without asking: `info`, `largest`, `list_trash`,
    backup `list` and `diff`, crypto `status`.

## Details

**Backups** are written to `~/.local/share/opencode-local/backups/<project>-<hash>/`, outside the project.
Each one is a `tar.gz` file plus a manifest with a SHA-256 for every file, which `diff` uses.
`.trash`, `node_modules`, `.venv`, `__pycache__`, `*.gguf` and `restored-*` are skipped. Restores
extract only regular files and directories, never symlinks or paths with `..`.

**Crypto** uses GnuPG with AES-256 symmetric encryption and a private gpg home, so your own keyring is
not touched.
- The passphrase is generated on the first `encrypt` and saved to
  `~/.local/share/opencode-local/keys/crypto.pass` (mode 0600).
- It is passed to gpg as a file, so the model never sees it.
- **Back up this file.** Without it, encrypted files cannot be recovered.
- To use a key you already have, set `OCL_CRYPTO_KEY=/path/to/file`.

**Video** offers fixed presets only (`mp4`, `mp4-small`, `webm`, `mp3`, `m4a`, `gif`). Free-form ffmpeg
arguments are not accepted. Inputs are limited to local files (`-protocol_whitelist file`). `trim`
copies streams without re-encoding, so it is fast but cuts at keyframes.

## Tests

```bash
python3 -m unittest discover -s ki-tools/tests -v
```
The tests start each server as a subprocess and talk JSON-RPC to it. The crypto and video tests are
skipped when `gpg` or `ffmpeg` is missing.

## Adding a tool

Create `<name>_server.py` next to the others and register functions with `@server.tool(...)`. Use
`inside()` / `new_output()` from `ocl_mcp.py` for every path. Then add an entry under `mcp` and an
`ocl_<name>_*` permission in `ki-config/opencode.json`.
