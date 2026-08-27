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
# Environment values live in EduIDE-deployment, which has two layouts while the
# restructure lands:
#
#   environments/<name>/values.yaml   plain values for the eduide chart
#   deployments/<fqdn>/values.yaml    the old umbrella's values, nested under a
#                                     `theia-cloud:` key and using YAML anchors
#                                     that only resolve within the whole file -
#                                     hence `explode(.)` before extracting
#
# Whichever is present is used. Rendering the old layout against the new chart
# is meaningless (different value keys entirely), so the layout is chosen from
# the deployment checkout, not from the chart.
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
    if [[ -d "$candidate/environments" || -d "$candidate/deployments" ]]; then
      DEPLOY="$candidate"; break
    fi
  done
fi
if [[ ! -d "${DEPLOY:-/nonexistent}/environments" && ! -d "${DEPLOY:-/nonexistent}/deployments" ]]; then
  echo "Could not find EduIDE-deployment. Pass its path as the second argument." >&2
  exit 2
fi

if [[ -n "$CHARTS_ARG" ]]; then
  CHARTS_DIR="$(cd "$CHARTS_ARG" && pwd)"
else
  CHARTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/charts"
fi
# The tenant chart was called theia-cloud before the split into
# eduide (tenant) and eduide-cluster (cluster-scoped). Accept both so this
# script can render a base checkout that predates the rename.
TENANT_CHART=eduide
[[ -d "$CHARTS_DIR/$TENANT_CHART" ]] || TENANT_CHART=theia-cloud
[[ -d "$CHARTS_DIR/$TENANT_CHART" ]] || {
  echo "No eduide or theia-cloud chart under $CHARTS_DIR" >&2
  exit 2
}

# The layout follows the chart generation, not whatever the deployment checkout
# happens to have. The old values are keyed under `theia-cloud:` and mean
# nothing to the eduide chart, so rendering one against the other produces a
# failure that looks like a chart bug and is not one.
if [[ "$TENANT_CHART" == eduide ]]; then LAYOUT=environments; else LAYOUT=deployments; fi

if [[ ! -d "$DEPLOY/$LAYOUT" ]]; then
  # Expected while the restructure is in flight: the head chart is `eduide` but
  # EduIDE-deployment's main branch still carries `deployments/`. There is
  # nothing comparable, and saying so beats failing.
  echo "::notice::$TENANT_CHART needs the $LAYOUT/ layout, which this EduIDE-deployment checkout does not have."
  echo "::notice::Nothing to render. Merge the matching EduIDE-deployment PR, or point this at that branch."
  mkdir -p "$OUT"
  exit 0
fi
echo "rendering from $CHARTS_DIR (chart $TENANT_CHART, $LAYOUT layout)"
mkdir -p "$OUT"

# charts/*/charts/ is gitignored, so a fresh checkout has no dependencies and
# `helm template` refuses to render. render-diff renders two chart trees, so
# both need resolving; the base tree may predate the dependencies entirely,
# which is why a failure there is not fatal.
"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/resolve-deps.sh" \
  "$CHARTS_DIR/$TENANT_CHART" >/dev/null 2>&1 \
  || echo "warning: could not resolve dependencies for $CHARTS_DIR/$TENANT_CHART" >&2

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
    -e 's/^([[:space:]]*prometheusPassword:).*/\1 <masked>/' \
    -e 's/^([[:space:]]*minInstances:).*/\1 <masked>/' \
    -e 's/^([[:space:]]*maxInstances:).*/\1 <masked>/'
}

# Rendering the same input twice must produce the same output. This is what
# actually keeps the mask list honest: prometheusPassword was a second
# randAlphaNum in the same subchart as redis-password, was never masked, and put
# a spurious secret change in every single render diff - which is how a diff
# stops being read.
assert_deterministic() {
  local chart="$1" name="$2"; shift 2
  local a b
  a="$(helm template determinism-check "$chart" "$@" 2>/dev/null | mask)"
  b="$(helm template determinism-check "$chart" "$@" 2>/dev/null | mask)"
  if [[ "$a" != "$b" ]]; then
    echo "RENDER IS NONDETERMINISTIC for ${name}:" >&2
    diff <(printf '%s' "$a") <(printf '%s' "$b") | grep '^[<>]' | head -6 | sed 's/^/    /' >&2
    echo "  A template gained a lookup or a random value. Add it to mask() above." >&2
    return 1
  fi
}

rendered=0
for dir in "$DEPLOY"/$LAYOUT/*/; do
  env_name="$(basename "$dir")"
  case "$env_name" in *shared-gateway*) continue ;; esac
  [[ -f "$dir/values.yaml" ]] || continue

  values="$(mktemp)"
  extra=()
  if [[ "$LAYOUT" == environments ]]; then
    # The deploy supplies these from the environment's GitHub secrets. Rendering
    # needs them present, not correct - they are constants here, so they add no
    # diff noise.
    secrets="$(mktemp)"
    printf 'keycloak:\n  cookieSecret: render-only\nservice:\n  adminApiToken: cmVuZGVyLW9ubHk=\n' > "$secrets"
    extra+=(-f "$secrets")
    # Plain values, plus the base every deploy applies first.
    cp "$dir/values.yaml" "$values"
    [[ -f "$DEPLOY/environments/_base.yaml" ]] && extra+=(-f "$DEPLOY/environments/_base.yaml")
    ns="$(yq -r '.spec.namespace // "default"' "$dir/env.yaml" 2>/dev/null || echo default)"
  else
    yq -r 'explode(.) | ."theia-cloud"' "$dir/values.yaml" > "$values"
    ns="$(yq -r '.hosts.configuration.landing // "default"' "$values")"
  fi

  assert_deterministic "$CHARTS_DIR/$TENANT_CHART" "$env_name" "${extra[@]}" -f "$values" --namespace "$ns" || exit 1

  if ! helm template theia-cloud "$CHARTS_DIR/$TENANT_CHART" \
        "${extra[@]}" -f "$values" --namespace "$ns" 2> "$OUT/$env_name.err" | mask > "$OUT/$env_name.yaml"; then
    echo "RENDER FAILED for $env_name:" >&2
    cat "$OUT/$env_name.err" >&2
    exit 1
  fi
  rm -f "$values" "$OUT/$env_name.err" "${secrets:-}"
  printf '  rendered %-45s %s resources\n' "$env_name" "$(grep -c '^kind:' "$OUT/$env_name.yaml" || true)"
  rendered=$((rendered + 1))
done

# The cluster-scoped charts take no per-environment values.
for chart in eduide-cluster; do
  # Same reason as the kubeconform job: bare defaults are not a valid install
  # for the cluster chart, so render its example instead where one exists.
  CEX=()
  [[ -f "$CHARTS_DIR/$chart/values-example.yaml" ]] && CEX=(-f "$CHARTS_DIR/$chart/values-example.yaml")
  helm template "$chart" "$CHARTS_DIR/$chart" "${CEX[@]}" --namespace default | mask > "$OUT/_$chart.yaml"
  printf '  rendered %-45s %s resources\n' "$chart" "$(grep -c '^kind:' "$OUT/_$chart.yaml" || true)"
  rendered=$((rendered + 1))
done

[[ $rendered -gt 0 ]] || { echo "rendered nothing - check the deployment repo path" >&2; exit 1; }
echo "rendered $rendered manifest sets into $OUT"
