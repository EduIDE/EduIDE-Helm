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
for image in $(yq -r '.appDefinitions.catalog[] | select(.landingPage.buildSystems) | .image' "$ROOT/charts/eduide/values.yaml" | sort -u); do
  name="${image#eduide/}"
  mkdir -p "$dir/templates-$name"
  yq -o=json -I=0 "[.appDefinitions.catalog[] | select(.image == \"$image\") | .landingPage.buildSystems[]]" \
    "$ROOT/charts/eduide/values.yaml" > "$dir/templates-$name/templates-$name.json"
done

if "$CHECK" "$dir" >/dev/null; then ok "lists matching the catalog pass"; else bad "matching lists must pass"; fi

echo '[{"id":"maven","label":"Apache Maven"},{"id":"gradle","label":"Gradle"}]' > "$dir/templates-java-17-standalone/templates-java-17-standalone.json"
out=$("$CHECK" "$dir")
if [[ $? -eq 0 ]] && grep -q "::warning::catalog label 'Maven'" <<<"$out"; then ok "a differing label warns but passes"; else bad "a differing label must warn, not fail"; fi

echo '[{"id":"other","label":"Other","order":1}]' > "$dir/templates-java-17-standalone/templates-java-17-standalone.json"
if "$CHECK" "$dir" >/dev/null; then bad "an id missing from the image must fail"; else ok "an id missing from the image fails"; fi

rm -r "$dir/templates-java-17-standalone"
if "$CHECK" "$dir" >/dev/null; then bad "a missing list must fail"; else ok "a missing list fails"; fi

[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
