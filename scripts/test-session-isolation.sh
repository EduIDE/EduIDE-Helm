#!/usr/bin/env bash
# Session isolation settings that nothing notices when they regress.
#
# oauth2-proxy treats a skip-auth route as an unanchored regular expression, so
# every route must be anchored to the exact path. Sidecar pods are reached
# through a policy the operator creates per session, so the chart must neither
# open traffic to sidecars in general nor withhold the operator's permission to
# create that policy.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
CLUSTER_CHART="$ROOT/charts/eduide-cluster"
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }

for c in "$CHART" "$CLUSTER_CHART"; do
  "$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$c" >/dev/null || {
    echo "could not resolve chart dependencies" >&2; exit 1; }
done

OUT=$(helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
  --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret 2>/dev/null) \
  || { echo "  chart does not render"; exit 1; }

echo "=== oauth2-proxy skip-auth routes ==="

cfg=$(yq -r 'select(.kind=="ConfigMap" and .metadata.name=="oauth2-proxy-config") | .data."oauth2-proxy.cfg"' <<<"$OUT")
routes=$(grep -E '^[[:space:]]*skip_auth_routes' <<<"$cfg")
if [[ -z "$routes" ]]; then
  ok "no skip_auth_routes configured"
else
  # Every quoted entry has to start with ^ and end with $
  unanchored=$(grep -oE '"[^"]*"' <<<"$routes" | grep -vE '^"\^.*\$"$' || true)
  if [[ -z "$unanchored" ]]; then
    ok "every skip_auth_routes entry is anchored"
  else
    bad "every skip_auth_routes entry is anchored" "$unanchored"
  fi
fi

echo
echo "=== sidecar network policy ==="

if grep -q 'theia-cloud.io/sidecar' <<<"$OUT"; then
  bad "no chart policy selects sidecars in general" "$(grep -n 'theia-cloud.io/sidecar' <<<"$OUT" | head -3)"
else
  ok "no chart policy selects sidecars in general"
fi

role=$(helm template t "$CLUSTER_CHART" --set gateway.create=false 2>/dev/null \
  | yq -r 'select(.kind=="ClusterRole" and (.metadata.name | test("operator"))) | .rules[] | select(.apiGroups[] == "networking.k8s.io") | .resources[] + ":" + (.verbs | sort | join(","))')
if [[ "$role" == "networkpolicies:create,delete,get" ]]; then
  ok "operator may create, get and delete networkpolicies"
else
  bad "operator may create, get and delete networkpolicies" "got '$role'"
fi

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
