#!/usr/bin/env bash
# Every landingPage.buildSystems id in the catalog must be a template the image
# really carries.
#
#   ./scripts/check-build-systems.sh <dir-with-templates-json>
#
# The chart cannot read an image, so buildSystems is a list in the catalog and
# could drift from the image. EduIDE's build writes each image's template list
# as templates-<image>.json ([{id, label}], <image> is the catalog image without
# the "eduide/" prefix, e.g. templates-java-17-standalone.json); the directory
# may hold them in subfolders.
# release.yml writes them with fetch-image-templates.sh from the published
# images and runs this before publishing a new chart version. A catalog label
# that differs from the template's own label is a warning, a missing id an error.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${1:?usage: check-build-systems.sh <dir-with-templates-json>}"
fail=0

while IFS=$'\t' read -r image ids labels; do
  name="${image#eduide/}"
  file=$(find "$DIR" -name "templates-${name}.json" | head -n1)
  if [[ -z "$file" ]]; then
    echo "::error::no templates-${name}.json for catalog image ${image}"
    fail=1
    continue
  fi
  i=0
  IFS=, read -ra label_list <<<"$labels"
  for id in ${ids//,/ }; do
    want="${label_list[$i]:-}"
    i=$((i + 1))
    have=$(jq -r --arg id "$id" '.[] | select(.id == $id) | .label // ""' "$file")
    if [[ -n "$want" && -n "$have" && "$want" != "$have" ]]; then
      echo "::warning::catalog label '${want}' for ${name}/${id} differs from the template's '${have}'"
    fi
    if jq -e --arg id "$id" 'any(.[]; .id == $id)' "$file" >/dev/null; then
      echo "  ok  ${name}: ${id}"
    else
      echo "::error::buildSystems id '${id}' is not a template of ${name} (has: $(jq -r 'map(.id) | join(", ")' "$file"))"
      fail=1
    fi
  done
done < <(yq -r '.appDefinitions.catalog | to_entries | .[]
                | select(.value.landingPage.buildSystems)
                | .value.image + "\t" + (.value.landingPage.buildSystems | map(.id) | join(",")) + "\t" + (.value.landingPage.buildSystems | map(.label // "") | join(","))' \
           "$ROOT/charts/eduide/values.yaml")

exit $fail
