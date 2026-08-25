#!/usr/bin/env bash
# Render every real environment against the charts in this repo.
#
#   ./scripts/render-envs.sh <output-dir> [path-to-EduIDE-deployment] [charts-dir]
#
# charts-dir defaults to the charts/ next to this script. The render-diff job
# passes it explicitly so that ONE copy of this script renders both the base and
# the head chart trees. Rendering each side with its own copy of the script would
# fold script changes (the mask list, say) into the diff, when the only thing the
# job is meant to surface is what the charts do differently.
#
# Used by the render-diff CI job, which runs this on the PR base and head and
# diffs the two trees. That diff answers the only question that matters when
# changing a chart: "what will this actually do to production?"
#
# Environment values live in EduIDE-deployment, nested under a `theia-cloud:`
# key of the umbrella chart's values, and use YAML anchors that only resolve in
# the context of the whole file - hence `explode(.)` before extracting.
#
# NOTE: two templates call `lookup`, which returns empty under `helm template`
# and would otherwise produce a false diff on every single PR. Both are masked
# here. See MASKS below.

set -euo pipefail

OUT="${1:?usage: render-envs.sh <output-dir> [deployment-repo] [charts-dir]}"
DEPLOY="${2:-}"
CHARTS_ARG="${3:-}"

if [[ -z "$DEPLOY" ]]; then
  for candidate in ../EduIDE-deployment ../../EduIDE-deployment ./EduIDE-deployment; do
    [[ -d "$candidate/deployments" ]] && { DEPLOY="$candidate"; break; }
  done
fi
[[ -d "${DEPLOY:-/nonexistent}/deployments" ]] || {
  echo "Could not find EduIDE-deployment. Pass its path as the second argument." >&2
  exit 2
}

if [[ -n "$CHARTS_ARG" ]]; then
  CHARTS_DIR="$(cd "$CHARTS_ARG" && pwd)"
else
  CHARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts"
fi
[[ -d "$CHARTS_DIR/theia-cloud" ]] || {
  echo "No theia-cloud chart under $CHARTS_DIR" >&2
  exit 2
}
echo "rendering from $CHARTS_DIR"
mkdir -p "$OUT"

# --- MASKS ---------------------------------------------------------------
# Lines whose value is nondeterministic under `helm template`. If you add a
# `lookup` to a template, add it here too or render-diff becomes noise.
#
#   redis-password       theia-shared-cache regenerates it via randAlphaNum
#                        when the lookup finds no existing Secret.
#   minInstances/max     theia-appdefinitions preserves live scaling values;
#                        under `helm template` they fall back to bootstrap
#                        defaults. (Lives in EduIDE-deployment, listed here so
#                        the mask set stays in one place.)
mask() {
  sed -E \
    -e 's/^([[:space:]]*redis-password:).*/\1 <masked>/' \
    -e 's/^([[:space:]]*minInstances:).*/\1 <masked>/' \
    -e 's/^([[:space:]]*maxInstances:).*/\1 <masked>/'
}

rendered=0
for dir in "$DEPLOY"/deployments/*/; do
  env_name="$(basename "$dir")"
  case "$env_name" in *shared-gateway*) continue ;; esac
  [[ -f "$dir/values.yaml" ]] || continue

  values="$(mktemp)"
  yq -r 'explode(.) | ."theia-cloud"' "$dir/values.yaml" > "$values"
  ns="$(yq -r '.hosts.configuration.landing // "default"' "$values")"

  if ! helm template theia-cloud "$CHARTS_DIR/theia-cloud" \
        -f "$values" --namespace "$ns" 2> "$OUT/$env_name.err" | mask > "$OUT/$env_name.yaml"; then
    echo "RENDER FAILED for $env_name:" >&2
    cat "$OUT/$env_name.err" >&2
    exit 1
  fi
  rm -f "$values" "$OUT/$env_name.err"
  printf '  rendered %-45s %s resources\n' "$env_name" "$(grep -c '^kind:' "$OUT/$env_name.yaml" || true)"
  rendered=$((rendered + 1))
done

# The cluster-scoped charts take no per-environment values.
for chart in theia-cloud-base theia-cloud-crds; do
  helm template "$chart" "$CHARTS_DIR/$chart" --namespace default | mask > "$OUT/_$chart.yaml"
  printf '  rendered %-45s %s resources\n' "$chart" "$(grep -c '^kind:' "$OUT/_$chart.yaml" || true)"
  rendered=$((rendered + 1))
done

[[ $rendered -gt 0 ]] || { echo "rendered nothing - check the deployment repo path" >&2; exit 1; }
echo "rendered $rendered manifest sets into $OUT"
