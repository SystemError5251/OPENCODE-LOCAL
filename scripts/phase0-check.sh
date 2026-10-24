#!/usr/bin/env bash
# Phase 0 feasibility check. Read-only: installs nothing, changes nothing except writing the report.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [-o REPORT.md]

Collects device data (RAM, free disk, CPU, Android version) and checks whether the
tools needed for the later phases are present. Prints a Markdown report and saves it to
\$OCL_STATE (default: $OCL_STATE).
EOF
}

report=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) report="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
mkdir -p "$OCL_STATE"
report="${report:-$OCL_STATE/phase0-report-$(date +%Y%m%d-%H%M%S).md}"

mem_gb() { awk '/^MemTotal:/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?"; }
mem_avail_gb() { awk '/^MemAvailable:/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo "?"; }
disk_free_gb() { df -Pk "$HOME" | awk 'NR==2 {printf "%.1f", $4/1024/1024}'; }

platform="linux"
android=""
if is_termux; then
  platform="termux"
  android="$(getprop ro.build.version.release 2>/dev/null || echo "?")"
elif grep -qi microsoft /proc/version 2>/dev/null; then
  platform="wsl"
fi

check() { # check NAME -> yes (version) / no
  if have "$1"; then
    local v
    v="$("$1" --version 2>/dev/null | head -n1 | cut -c1-50 || true)"
    echo "yes${v:+ ($v)}"
  else
    echo "no"
  fi
}

ram="$(mem_gb)"
tier="pc"
ram_int="${ram%.*}"
if [[ "$platform" == termux ]]; then
  if [[ "$ram_int" =~ ^[0-9]+$ ]] && (( ram_int >= 11 )); then tier="phone-12gb"; else tier="phone-8gb"; fi
fi

{
  echo "# Phase 0 report"
  echo
  echo "Generated: $(date -Iseconds)"
  echo
  echo "## Device"
  echo
  echo "| Item | Value |"
  echo "|---|---|"
  echo "| Platform | $platform |"
  [[ -n "$android" ]] && echo "| Android version | $android |"
  echo "| CPU architecture | $(uname -m) |"
  echo "| CPU cores | $(nproc 2>/dev/null || echo ?) |"
  echo "| RAM total (GB) | $ram |"
  echo "| RAM available (GB) | $(mem_avail_gb) |"
  echo "| Free disk in \$HOME (GB) | $(disk_free_gb) |"
  echo "| Suggested model tier | $tier (see ki-models/models.json) |"
  echo
  echo "## Tools"
  echo
  echo "| Tool | Present |"
  echo "|---|---|"
  for t in git cmake make clang gcc curl unzip jq bun opencode llama-server proot-distro; do
    echo "| $t | $(check "$t") |"
  done
  echo
  echo "## Next steps"
  echo
  if [[ "$platform" == termux ]]; then
    echo "- Run \`./install-termux.sh --dry-run\`, then \`./install-termux.sh\`."
    echo "- After the install, run \`proot-distro login debian -- opencode --version\` to answer the key Phase 0 question:"
    echo "  does OpenCode run inside Debian proot on this phone?"
  else
    echo "- Run \`./install-linux.sh --dry-run\`, then \`./install-linux.sh\`."
  fi
  echo "- Copy the results into docs/phase0-results.md."
} | tee "$report"

log "report saved to $report"
