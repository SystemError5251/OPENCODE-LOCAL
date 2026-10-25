# Models

`models.json` lists tested GGUF models per device tier. Model files are stored in
`~/.local/share/opencode-local/models/` and are never committed (see `.gitignore`).

| Tier | RAM | Use |
|---|---|---|
| `test` | any | smoke test only |
| `phone-8gb` | 6–8 GB | Qwen3 1.7B default |
| `phone-12gb` | 12+ GB | Qwen3 4B, 7B (slow) |
| `pc` | 32 GB / GPU | 14B |
| `legacy` | – | Qwen2.5-Coder 1.5B/3B: no working tool calls in OpenCode, kept for comparison |

`scripts/phase0-check.sh` suggests a tier for the current device.

## Download and verify

```bash
scripts/fetch-model.sh --list
scripts/fetch-model.sh qwen3-1.7b
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

OpenCode's system prompt plus the tool descriptions take about 7,000 tokens with the full `coder` agent
and about 2,900 with the default `lite` agent, before your first message (measured 2026-10-25). With the old 8192 context OpenCode compacted the conversation on every step
and never finished, so the default is now 16384 (`scripts/start-llama.sh`, `limit.context` in
`ki-config/opencode.json`). Change both together.

The context costs RAM on top of the model. For Qwen3 1.7B, 16384 tokens need about 1.8 GB (f16 KV cache),
so model plus context is roughly 3.6 GB. If an 8 GB phone runs out of memory, halve the KV cache with
`scripts/start-llama.sh -- --cache-type-k q8_0 --cache-type-v q8_0` (about 0.9 GB; not yet tested for
quality).

## Tool calling

OpenCode works through tool calls (read file, edit, run command). `start-llama.sh` passes `--jinja` so the
model's chat template handles them. Results from the 2026-10-25 test (`docs/simulation-results.md`):

| Model | Reads a file via tool | Edits a file |
|---|---|---|
| Qwen2.5-Coder 1.5B | no: writes the tool call as text | no |
| Qwen3 1.7B, `coder` agent | yes | no: wrong `oldString`, gives up, may overwrite the file |
| Qwen3 1.7B, `lite` agent | yes | yes: 6 of 6 on a 1-line file, 2 of 3 on a 25-line file, ~50 s each |
| Qwen3 4B | yes | not finished within 25 min on 4 x86 cores |

The `lite` agent edits through `ocl_files_write` and `ocl_files_replace`, which forgive the typical
small-model mistakes (line numbers copied from the read output, `\n` written as text). Check the result
anyway; for bigger changes plan on the PC host (Phase 7).
