#!/usr/bin/env bash
# Fetch a chart's dependencies, if it has any.
#
#   ./scripts/resolve-deps.sh charts/eduide
#   ./scripts/resolve-deps.sh                 # every chart under charts/
#
# charts/*/charts/ is gitignored: dependencies are resolved, not vendored, which
# is what keeps Chart.lock, Chart.yaml and HEAD from drifting apart the way they
# did before. The cost is that every command touching a chart on a fresh
# checkout has to fetch them first, and `helm template`, `helm package` and
# `helm dependency list` all refuse outright when they are missing.
#
# That was rediscovered four times in one afternoon - kubeconform, render-envs,
# test-app-consistency and the PR preview publish - so it lives in one place now
# and every caller uses it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

resolve_one() {
  local chart="$1"
  [[ -f "$chart/Chart.yaml" ]] || return 0
  yq -e '.dependencies' "$chart/Chart.yaml" >/dev/null 2>&1 || return 0

  # build honours Chart.lock and is reproducible; update re-resolves and is the
  # fallback when the lock is stale or absent.
  if helm dependency build "$chart" >/dev/null 2>&1; then
    echo "  resolved $(basename "$chart") (from Chart.lock)"
  elif helm dependency update "$chart" >/dev/null 2>&1; then
    echo "  resolved $(basename "$chart") (re-resolved)"
  else
    echo "  FAILED to resolve dependencies for $chart" >&2
    helm dependency build "$chart" 2>&1 | tail -3 >&2
    return 1
  fi
}

failed=0
if [[ $# -gt 0 ]]; then
  for c in "$@"; do resolve_one "$c" || failed=1; done
else
  for c in "$ROOT"/charts/*/; do resolve_one "${c%/}" || failed=1; done
fi
exit $failed
