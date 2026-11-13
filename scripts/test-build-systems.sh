#!/usr/bin/env bash
# check-build-systems.sh passes on a matching template list and fails on a
# missing id or a missing list.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/scripts/check-build-systems.sh"
FAILED=0
ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; FAILED=1; }

dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

# One list per catalog image, built from the catalog itself.
while read -r image ids; do
  name="${image#eduide/}"
  mkdir -p "$dir/templates-$name"
  jq -n --arg ids "$ids" '$ids | split(",") | map({id: ., label: ., order: 1})' > "$dir/templates-$name/templates-$name.json"
done < <(yq -r '.appDefinitions.catalog | to_entries | .[] | select(.value.landingPage.buildSystems)
                | .value.image + " " + (.value.landingPage.buildSystems | map(.id) | join(","))' "$ROOT/charts/eduide/values.yaml")

if "$CHECK" "$dir" >/dev/null; then ok "lists matching the catalog pass"; else bad "matching lists must pass"; fi

echo '[{"id":"other","label":"Other","order":1}]' > "$dir/templates-java-17-standalone/templates-java-17-standalone.json"
if "$CHECK" "$dir" >/dev/null; then bad "an id missing from the image must fail"; else ok "an id missing from the image fails"; fi

rm -r "$dir/templates-java-17-standalone"
if "$CHECK" "$dir" >/dev/null; then bad "a missing list must fail"; else ok "a missing list fails"; fi

[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
