#!/usr/bin/env bash
# Every landingPage.buildSystems id in the catalog must be a template the image
# really carries.
#
#   ./scripts/check-build-systems.sh <dir-with-templates-json>
#
# The chart cannot read an image, so buildSystems is a list in the catalog and
# could drift from the image. EduIDE's build writes each image's template list
# as the artifact templates-<image>.json (<image> is the catalog image without
# the "eduide/" prefix, e.g. templates-java-17-standalone.json); the directory
# may hold them in subfolders, as `gh run download` leaves them.
# release.yml downloads the artifacts of the build that produced the pinned
# appVersion and runs this before publishing the chart.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:?usage: check-build-systems.sh <dir-with-templates-json>}"
fail=0

while read -r image ids; do
  name="${image#eduide/}"
  file=$(find "$DIR" -name "templates-${name}.json" | head -n1)
  if [[ -z "$file" ]]; then
    echo "::error::no templates-${name}.json for catalog image ${image}"
    fail=1
    continue
  fi
  for id in ${ids//,/ }; do
    if jq -e --arg id "$id" 'any(.[]; .id == $id)' "$file" >/dev/null; then
      echo "  ok  ${name}: ${id}"
    else
      echo "::error::buildSystems id '${id}' is not a template of ${name} (has: $(jq -r 'map(.id) | join(", ")' "$file"))"
      fail=1
    fi
  done
done < <(yq -r '.appDefinitions.catalog | to_entries | .[]
                | select(.value.landingPage.buildSystems)
                | .value.image + " " + (.value.landingPage.buildSystems | map(.id) | join(","))' \
           "$ROOT/charts/eduide/values.yaml")

exit $fail
