#!/usr/bin/env bash
# global.nodeSelector pins every EduIDE pod to one node pool. A workload that
# misses it still schedules, just somewhere else, so nothing fails until a
# session starts on a node without preloaded images. Assert every one here.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
CLUSTER_CHART="$ROOT/charts/eduide-cluster"
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }

"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CHART" >/dev/null || {
  echo "could not resolve chart dependencies" >&2; exit 1; }

render() {
  helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret "$@" 2>/dev/null
}

# expect <label> <expected> <actual>
expect() {
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

POOL='global={"nodeSelector":{"aet.cit.tum.de/pool":"pve","zone":"a"}}'
selector() { yq -r "select(.metadata.name==\"$1\") | .spec.template.spec.nodeSelector | to_entries | map(.key + \"=\" + .value) | join(\",\")"; }
args() { yq -r 'select(.metadata.name=="operator-deployment") | .spec.template.spec.containers[0].args | join(" ")'; }

echo "=== unset renders no selector ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }
for w in operator-deployment service-deployment landing-page-deployment image-preloading; do
  expect "$w: no nodeSelector" "" "$(selector "$w" <<<"$OUT")"
done
if [[ "$(args <<<"$OUT")" != *--sessionNodeSelector* ]]; then
  ok "operator: no --sessionNodeSelector"
else
  bad "operator: no --sessionNodeSelector" "$(args <<<"$OUT")"
fi

echo
echo "=== global.nodeSelector reaches every workload ==="

OUT=$(render --set-json "$POOL") || { echo "  chart does not render"; exit 1; }
for w in operator-deployment service-deployment landing-page-deployment image-preloading; do
  expect "$w: pinned" "aet.cit.tum.de/pool=pve,zone=a" "$(selector "$w" <<<"$OUT")"
done
if [[ "$(args <<<"$OUT")" == *"--sessionNodeSelector aet.cit.tum.de/pool=pve,zone=a"* ]]; then
  ok "operator: --sessionNodeSelector with sorted pairs"
else
  bad "operator: --sessionNodeSelector with sorted pairs" "$(args <<<"$OUT")"
fi

echo
echo "=== preloading.nodeSelector ==="

expect "set alone, still pins preloading" "disk=big" \
  "$(render --set preloading.nodeSelector.disk=big | selector image-preloading)"
expect "wins over global.nodeSelector" "disk=big" \
  "$(render --set-json "$POOL" --set preloading.nodeSelector.disk=big | selector image-preloading)"

echo
echo "=== eduide-cluster ==="

cluster() { helm template t "$CLUSTER_CHART" -f "$CLUSTER_CHART/values-example.yaml" "$@" 2>/dev/null | selector conversion-webhook; }
expect "conversion-webhook: no nodeSelector when unset" "" "$(cluster)"
expect "conversion-webhook: pinned" "aet.cit.tum.de/pool=pve,zone=a" "$(cluster --set-json "$POOL")"

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
