#!/usr/bin/env bash
# Download a GGUF model listed in ki-models/models.json and verify its SHA-256.
set -euo pipefail
# shellcheck source=SCRIPTDIR/../lib/common.sh
source "$(dirname "$0")/../lib/common.sh"

MODELS_JSON="$REPO_ROOT/ki-models/models.json"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--list] [--dry-run] MODEL_ID

Downloads MODEL_ID from Hugging Face into $OCL_MODELS and checks its SHA-256.
If models.json has no sha256 for the model, the official hash is read from the
Hugging Face API and printed so you can pin it in models.json.
A file that fails verification is deleted.
The downloaded model becomes the default that scripts/start-llama.sh starts.

  --list     show available model IDs
  --dry-run  print what would be downloaded
EOF
}

have jq || die "jq is required (Termux: pkg install jq, Debian: apt install jq)"
have curl || die "curl is required"

list=0
id=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) list=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; exit 2 ;;
    *) id="$1"; shift ;;
  esac
done

if [[ "$list" == 1 ]]; then
  jq -r '.models[] | [.id, .tier, "\(.size_gb) GB", .notes] | @tsv' "$MODELS_JSON" \
    | while IFS=$'\t' read -r mid tier size notes; do
        printf '%-20s %-11s %-8s %s\n' "$mid" "$tier" "$size" "$notes"
      done
  exit 0
fi
[[ -n "$id" ]] || { usage; exit 2; }

entry="$(jq -c --arg id "$id" '.models[] | select(.id == $id)' "$MODELS_JSON")"
[[ -n "$entry" ]] || die "unknown model id: $id (use --list)"

repo="$(jq -r .repo <<<"$entry")"
file="$(jq -r .file <<<"$entry")"
rev="$(jq -r .revision <<<"$entry")"
sha="$(jq -r '.sha256 // ""' <<<"$entry")"
url="https://huggingface.co/$repo/resolve/$rev/$file"
dest="$OCL_MODELS/$file"

if [[ -z "$sha" ]]; then
  log "no pinned sha256 in models.json, reading it from the Hugging Face API"
  api="https://huggingface.co/api/models/$repo/tree/$rev"
  sha="$(curl --fail --silent --show-error --proto '=https' "$api" \
    | jq -r --arg f "$file" '.[] | select(.path == $f) | .lfs.oid // empty')"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "could not read the sha256 for $file from $api"
  log "official sha256: $sha"
  log "pin it: set \"sha256\": \"$sha\" for \"$id\" in ki-models/models.json"
fi

log "model:  $id ($(jq -r .size_gb <<<"$entry") GB)"
log "source: $url"
log "target: $dest"
[[ "$DRY_RUN" == 1 ]] && exit 0

mkdir -p "$OCL_MODELS"
if [[ -f "$dest" ]] && verify_sha256 "$dest" "$sha"; then
  log "already downloaded and verified"
  printf '%s\n' "$dest" > "$OCL_MODELS/default"
  log "default model: $file"
  exit 0
fi

download "$url" "$dest.part"
if ! verify_sha256 "$dest.part" "$sha"; then
  rm -f "$dest.part"
  die "download deleted because the checksum did not match"
fi
mv "$dest.part" "$dest"
echo "$sha  $file" > "$dest.sha256"
log "ready: $dest"
printf '%s\n' "$dest" > "$OCL_MODELS/default"
log "default model: $file (scripts/start-llama.sh starts it; restart a running server with --stop first)"
log "start it with: scripts/start-llama.sh --model $dest"
