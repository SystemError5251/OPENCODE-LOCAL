#!/usr/bin/env bash
# Run every offline check in this repository. Used by CI and before each commit.
# Needs: bash, python3, jq. Optional (skipped if missing): shellcheck, pwsh, gpg, ffmpeg.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

fails=0
pass() { printf '\033[32mPASS\033[0m %s\n' "$1"; }
fail() { printf '\033[31mFAIL\033[0m %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf '\033[33mSKIP\033[0m %s\n' "$1"; }
check() { local name="$1"; shift; if "$@" >/tmp/ocl-check.log 2>&1; then pass "$name"; else fail "$name"; sed 's/^/    /' /tmp/ocl-check.log | tail -20; fi; }

shell_files=(quickstart.sh install-linux.sh install-termux.sh lib/common.sh ki-config/env.sh scripts/*.sh scripts/opencode-local tests/run-all.sh)

for f in "${shell_files[@]}"; do check "bash -n $f" bash -n "$f"; done
if command -v shellcheck >/dev/null; then
  check "shellcheck" shellcheck -x "${shell_files[@]}"
else
  skip "shellcheck (not installed)"
fi

for f in ki-config/opencode.json ki-models/models.json; do check "json $f" python3 -m json.tool "$f"; done
check "python compile ki-tools" python3 -m py_compile ki-tools/*.py
check "MCP server tests" python3 -m unittest discover -s ki-tools/tests

if command -v pwsh >/dev/null; then
  # shellcheck disable=SC2016 # PowerShell code, must not expand in bash
  check "pwsh parse install-windows.ps1" pwsh -NoProfile -c \
    '$e=$null; [System.Management.Automation.Language.Parser]::ParseFile("install-windows.ps1",[ref]$null,[ref]$e) | Out-Null; if ($e.Count) { $e | % { $_.Message }; exit 1 }'
else
  skip "pwsh parse (pwsh not installed)"
fi

# Every MCP server in the config must exist in ki-tools/ and have an ocl_ name covered by "ocl_*": "ask".
check "config references existing MCP servers" python3 - <<'PY'
import json, os
c = json.load(open("ki-config/opencode.json"))
perm = list(c["permission"])
assert "ocl_*" in perm and c["permission"]["ocl_*"] == "ask"
for name, s in c["mcp"].items():
    assert name.startswith("ocl_"), name
    assert os.path.isfile(os.path.join("ki-tools", os.path.basename(s["command"][-1]))), s
for k in perm[perm.index("ocl_*") + 1:]:
    assert c["permission"][k] == "allow" and k.startswith("ocl_"), k
PY

# Dry runs in a throwaway HOME.
tmp_home="$(mktemp -d)"
check "install-linux.sh --dry-run" env HOME="$tmp_home" ./install-linux.sh --dry-run
check "install-termux.sh --dry-run" env HOME="$tmp_home" PREFIX="$tmp_home/prefix" ./install-termux.sh --dry-run
check "install-termux.sh --update --dry-run" env HOME="$tmp_home" PREFIX="$tmp_home/prefix" ./install-termux.sh --update --dry-run
check "start-llama.sh refuses 0.0.0.0 without key" bash -c "! HOME=$tmp_home OCL_LLAMA_API_KEY= scripts/start-llama.sh -n -m x.gguf --host 0.0.0.0"
check "quickstart.sh --dry-run" env HOME="$tmp_home" ./quickstart.sh --dry-run --model qwen3-1.7b
check "wipe-sessions.sh --dry-run" env HOME="$tmp_home" scripts/wipe-sessions.sh --dry-run
check "fetch-model.sh --list" env HOME="$tmp_home" scripts/fetch-model.sh --list
check "tunnel.sh --dry-run" env HOME="$tmp_home" scripts/tunnel.sh -n user@pc
rm -rf "$tmp_home"

echo
if [[ "$fails" -eq 0 ]]; then echo "all checks passed"; else echo "$fails check(s) failed"; exit 1; fi
