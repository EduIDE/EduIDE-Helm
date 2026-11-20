#!/usr/bin/env bash
# Render the environments of EduIDE-deployment that run the 3.x chart.
#
#   ./scripts/render-envs.sh <output-dir> [path-to-EduIDE-deployment] [charts-dir]
#
# Used by the render-diff CI job, which runs this on the PR base and head and
# diffs the two trees. charts-dir defaults to the charts/ next to this script;
# the job passes it so that one copy of this script renders both sides.
#
# Only environments/<name>/env.yaml with spec.platform.chartVersion >= MIN_VERSION
# are rendered. The deployment repo is still Java-shaped, so today that is none
# and the job passes with an empty diff.

set -euo pipefail

MIN_VERSION=3.0.0-rc.9
OUT="${1:?usage: render-envs.sh <output-dir> [deployment-repo] [charts-dir]}"
DEPLOY="${2:-}"
CHARTS_ARG="${3:-}"

if [[ -z "$DEPLOY" ]]; then
  for candidate in ../EduIDE-deployment ../../EduIDE-deployment ./EduIDE-deployment; do
    [[ -d "$candidate/environments" ]] && { DEPLOY="$candidate"; break; }
  done
fi
if [[ ! -d "${DEPLOY:-/nonexistent}/environments" ]]; then
  echo "Could not find EduIDE-deployment. Pass its path as the second argument." >&2
  exit 2
fi
if [[ -n "$CHARTS_ARG" ]]; then
  CHARTS_DIR="$(cd "$CHARTS_ARG" && pwd)"
else
  CHARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts"
fi
mkdir -p "$OUT"

# semver order with prereleases below their release: 3.0.0-rc.9 < 3.0.0
at_least() {
  local a="${1//-/~}" b="${MIN_VERSION//-/~}"
  [[ "$(printf '%s\n%s\n' "$a" "$b" | sort -V | head -1)" == "$b" ]]
}

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-deps.sh" "$CHARTS_DIR/eduide" >/dev/null 2>&1 \
  || echo "warning: could not resolve dependencies for $CHARTS_DIR/eduide" >&2

rendered=0
for dir in "$DEPLOY"/environments/*/; do
  env_name="$(basename "$dir")"
  [[ -f "$dir/env.yaml" && -f "$dir/values.yaml" ]] || continue
  version="$(yq -r '.spec.platform.chartVersion // ""' "$dir/env.yaml")"
  if [[ -z "$version" ]] || ! at_least "$version"; then
    echo "skip $env_name (chartVersion '${version:-none}' is below $MIN_VERSION)"
    continue
  fi
  ns="$(yq -r '.spec.namespace // "default"' "$dir/env.yaml")"
  helm template "$env_name" "$CHARTS_DIR/eduide" -f "$dir/values.yaml" --namespace "$ns" > "$OUT/$env_name.yaml"
  printf '  rendered %-45s %s resources\n' "$env_name" "$(grep -c '^kind:' "$OUT/$env_name.yaml" || true)"
  rendered=$((rendered + 1))
done

echo "rendered $rendered manifest sets into $OUT"
