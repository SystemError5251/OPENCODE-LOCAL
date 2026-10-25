# Test checklist (on the device)

Automated checks (`tests/run-all.sh`) cannot cover the phone, the real model or your network.
Go through this list after installing or updating, and tick what works.

## 1. Update to the current version (Termux)
```bash
cd ~/opencode-local && git pull && ./quickstart.sh
```
- [ ] finishes with "Done." and no error

## 2. Model and speed (Phase 1)
```bash
scripts/fetch-model.sh qwen3-1.7b
scripts/bench.sh
```
- [ ] download ends with "checksum ok"; note the printed sha256 (to pin it in `ki-models/models.json`)
- [ ] bench shows `pp512` and `tg128` numbers → copy them into `docs/phase0-results.md`

## 3. Chat and tool calls (Phase 2)
```bash
mkdir -p ~/projects/test && cd ~/projects/test && echo 'print("hi")' > hello.py && opencode-local
```
- [ ] OpenCode starts, bottom line shows `coder · local`
- [ ] "What does hello.py do?" → it reads the file (no approval needed for reading)
- [ ] "Add a function add(a, b) to hello.py" → **asks** before editing
- [ ] "Run python3 hello.py" → **asks** before running

## 4. Security (Phase 3)
In the same session:
- [ ] "Run curl https://example.com" → refused (denied, no prompt)
- [ ] "Delete hello.py with rm -rf" → refused
- [ ] "Read ~/.bashrc" or "/etc/passwd" → refused (outside the project)
- [ ] `echo SECRET=1 > .env`, then "Show me .env" → refused
- [ ] With the firewall app blocking Termux: OpenCode still works

## 5. MCP tools (Phase 4)
- [ ] "Make a backup of the project" → `ocl_backup_create` runs, prints a backup id
- [ ] "Move hello.py to the trash" → **asks**, afterwards `.trash/` exists; "restore it" → file is back
- [ ] "Encrypt hello.py" → **asks**, creates `hello.py.gpg`, mentions the key file
- [ ] Back up the key: `proot-distro login debian -- cat /root/.local/share/opencode-local/keys/crypto.pass`
  and store it somewhere safe (password manager)
- [ ] optional: copy a short video into the project, "Show info for video.mp4" → duration and resolution

## 6. PC as model host (Phase 7, optional)
On the PC: `./install-linux.sh`, `scripts/fetch-model.sh qwen2.5-coder-7b`, `scripts/start-llama.sh --background`,
SSH server running. On the phone:
```bash
pkg install openssh
scripts/start-llama.sh --stop
scripts/tunnel.sh user@<PC-IP>
cd ~/projects/test && opencode-local
```
- [ ] `scripts/tunnel.sh --status` says "ready"; answers are noticeably better
- [ ] `scripts/tunnel.sh --stop` → next `opencode-local` starts the phone model again

## 7. Updates (Phase 6)
- [ ] `scripts/update.sh` lists versions and says "nothing changed" – it must not install anything

## 8. Windows (Phase 5, if you have a Windows PC)
- [ ] `install-windows.ps1 -DryRun` lists the steps
- [ ] after the install, `opencode-local` in a project folder starts OpenCode

Report back what failed (copy the error text), plus the bench numbers and the sha256.
