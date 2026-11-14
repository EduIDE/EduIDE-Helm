#!/usr/bin/env bash
# Write templates-<image>.json (id, label) for every catalog image that lists
# buildSystems, read from the published image itself.
#
#   ./scripts/fetch-image-templates.sh <image-tag> <out-dir>
#
# The template folders are /home/theia/templates/<id>/template.json in the
# image. Exporting the whole image would stream several GB, so only the small
# layers are read: the template files sit in a layer of a few KB to MB, the
# toolchains in layers of hundreds of MB.
# shortcut: layers over 10 MB are skipped, raise MAX_LAYER if a template set outgrows it.
# Needs GNU tar (TAR=gtar on macOS), crane (override with CRANE=...), jq and yq.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAG="${1:?usage: fetch-image-templates.sh <image-tag> <out-dir>}"
OUT="${2:?usage: fetch-image-templates.sh <image-tag> <out-dir>}"
CRANE="${CRANE:-crane}"
TAR="${TAR:-tar}"
MAX_LAYER="${MAX_LAYER:-10000000}"
mkdir -p "$OUT"

for image in $(yq -r '.appDefinitions.catalog[] | select(.landingPage.buildSystems) | .image' "$ROOT/charts/eduide/values.yaml" | sort -u); do
  name="${image#eduide/}"
  ref="ghcr.io/eduide/${image}:${TAG}"
  work=$(mktemp -d)
  for digest in $("$CRANE" manifest --platform linux/amd64 "$ref" | jq -r --argjson max "$MAX_LAYER" '.layers[] | select(.size < $max) | .digest' | sort -u); do
    "$CRANE" blob "ghcr.io/eduide/${image}@${digest}" | "$TAR" -xz -C "$work" --wildcards 'home/theia/templates/*/template.json' 2>/dev/null || true
  done
  if ! compgen -G "$work/home/theia/templates/*/template.json" >/dev/null; then
    echo "::error::no template.json found in the small layers of ${ref}"
    rm -rf "$work"
    exit 1
  fi
  for f in "$work"/home/theia/templates/*/template.json; do
    jq --arg id "$(basename "$(dirname "$f")")" '{id: $id, label: .label}' "$f"
  done | jq -s '.' > "$OUT/templates-${name}.json"
  rm -rf "$work"
  echo "  read $(jq length "$OUT/templates-${name}.json") templates from ${ref}"
done
