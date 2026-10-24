# Models

`models.json` lists tested GGUF models per device tier. Model files are stored in
`~/.local/share/opencode-local/models/` and are never committed (see `.gitignore`).

| Tier | RAM | Use |
|---|---|---|
| `test` | any | smoke test only |
| `phone-8gb` | 6–8 GB | 1.5B default, 3B as upper limit |
| `phone-12gb` | 12+ GB | 7B, slow |
| `pc` | 32 GB / GPU | 14B |

`scripts/phase0-check.sh` suggests a tier for the current device.

## Download and verify

```bash
scripts/fetch-model.sh --list
scripts/fetch-model.sh qwen2.5-coder-1.5b
```

- Downloads only over HTTPS from `huggingface.co`, into a `.part` file.
- Compares the SHA-256 with `models.json`. On mismatch the file is deleted.
- If `sha256` in `models.json` is empty, the script reads the official hash from the Hugging Face API
  and prints it. **Copy it into `models.json` and commit it**, so later downloads (or other devices)
  are checked against a hash you already trust instead of asking the server again.

## Adding a model

Add an entry with `id`, `tier`, `repo`, `file`, `revision`, `size_gb`, `ctx` and `sha256`.
Prefer the publisher's own GGUF repository; use well-known community quantizations only when the
publisher has none in a single file. Pinning `revision` to a commit hash instead of `main` makes the
download fully reproducible.

## Context size

The context (`--ctx` in `scripts/start-llama.sh`) costs RAM on top of the model. On an 8 GB phone keep it
at 4096–8192. If you change it, also change `limit.context` in `ki-config/opencode.json` so OpenCode
compacts the conversation in time.

## Tool calling

OpenCode works through tool calls (read file, edit, run command). `start-llama.sh` passes `--jinja` so the
model's chat template handles them. Small models (≤3B) often get tool calls wrong; this is the main
reason for the PC-host option in Phase 7.
