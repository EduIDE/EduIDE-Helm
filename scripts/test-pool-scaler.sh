#!/usr/bin/env bash
# The pool scaler is optional. Off, it must render nothing. On, there must be
# exactly one scaler (no leader election), its configuration must carry the
# namespace and mode the chart owns, and AppDefinitions must keep targetIdle
# out of the render unless a value asks for it. The operator's metrics port and
# PodMonitor are operator.metricsPort's, tested with it.

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
  helm template t "$CHART" --namespace eduide-test1 --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret "$@" 2>/dev/null
}

# expect <label> <expected> <actual>
expect() {
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

count() { yq -r "select(.metadata.name | test(\"$1\")) | .kind" | grep -v -- "^---$" | grep -c . ; }
config() { yq -r 'select(.metadata.name=="pool-scaler-config") | .data."config.yaml"' | yq -r "$1"; }

echo "=== off by default ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }
expect "no pool-scaler resources" "0" "$(count '^pool-scaler' <<<"$OUT")"
expect "no targetIdle on any AppDefinition" "0" "$(yq -r 'select(.kind=="AppDefinition" and .spec.targetIdle != null) | .spec.targetIdle' <<<"$OUT" | grep -c .)"

echo
echo "=== enabled ==="

OUT=$(render --set poolScaler.enabled=true --set poolScaler.mode=active \
  --set-json 'global={"nodeSelector":{"pool":"pve"}}' \
  --set-json 'poolScaler.config={"timezone":"Europe/Berlin","mode":"shadow","namespace":"elsewhere"}') || { echo "  chart does not render"; exit 1; }
DEP='select(.kind=="Deployment" and .metadata.name=="pool-scaler")'
expect "one replica" "1" "$(yq -r "$DEP | .spec.replicas" <<<"$OUT")"
expect "Recreate" "Recreate" "$(yq -r "$DEP | .spec.strategy.type" <<<"$OUT")"
expect "chart sets the namespace" "eduide-test1" "$(config .namespace <<<"$OUT")"
expect "poolScaler.mode wins over config.mode" "active" "$(config .mode <<<"$OUT")"
expect "user config passes through" "Europe/Berlin" "$(config .timezone <<<"$OUT")"
expect "budget nodes follow global.nodeSelector" "pve" "$(config .budget.nodeSelector.pool <<<"$OUT")"
expect "only the ClusterRole is cluster-wide, named per namespace" "pool-scaler-eduide-test1" "$(yq -r 'select(.kind=="ClusterRole" and .metadata.name=="pool-scaler-eduide-test1") | .metadata.name' <<<"$OUT")"
expect "reads pool Deployments" "deployments" "$(yq -r 'select(.kind=="Role" and .metadata.name=="pool-scaler") | .rules[] | select(.apiGroups[0]=="apps") | .resources[]' <<<"$OUT")"
expect "writes only appdefinitions" "appdefinitions" "$(yq -r 'select(.kind=="Role" and .metadata.name=="pool-scaler") | .rules[] | select(.verbs[] == "patch") | .resources[]' <<<"$OUT")"
expect "no monitoring unless asked" "0" "$(yq -r 'select(.kind=="PrometheusRule" or .kind=="PodMonitor") | .kind' <<<"$OUT" | grep -c .)"

if render --set poolScaler.enabled=true --set poolScaler.mode=live >/dev/null; then
  bad "an unknown mode fails the render"
else
  ok "an unknown mode fails the render"
fi

echo
echo "=== monitoring ==="

OUT=$(render --set poolScaler.enabled=true --set poolScaler.monitoring.enabled=true) || { echo "  chart does not render"; exit 1; }
expect "PodMonitor, PrometheusRule and board, named per namespace" "ConfigMap,PodMonitor,PrometheusRule" "$(yq -r 'select(.kind=="PodMonitor" or .kind=="PrometheusRule" or .metadata.name=="pool-scaler-dashboard-eduide-test1") | select(.metadata.name | test("eduide-test1$")) | .kind' <<<"$OUT" | grep -v -- --- | sort | paste -sd, -)"
BOARD=$(yq -r 'select(.metadata.name=="pool-scaler-dashboard-eduide-test1") | .data[]' <<<"$OUT")
expect "board is valid JSON with a namespaced uid" "pool-scaler-eduide-test1" "$(jq -r .uid <<<"$BOARD")"
expect "no placeholder left in the board" "0" "$(grep -c __NAMESPACE__ <<<"$BOARD")"
expect "eight alerts" "8" "$(yq -r 'select(.kind=="PrometheusRule") | .spec.groups[].rules[].alert' <<<"$OUT" | grep -c .)"

echo
echo "=== targetIdle from values ==="

OUT=$(render --set appDefinitions.defaults.targetIdle=2 --set appDefinitions.apps.java-17.targetIdle=0) || { echo "  chart does not render"; exit 1; }
expect "app value, including 0" "0" "$(yq -r 'select(.kind=="AppDefinition" and .metadata.name=="java-17") | .spec.targetIdle' <<<"$OUT")"
expect "defaults value" "2" "$(yq -r 'select(.kind=="AppDefinition" and .metadata.name=="c") | .spec.targetIdle' <<<"$OUT")"

echo
echo "=== CRD in eduide-cluster ==="

"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CLUSTER_CHART" >/dev/null
CR() { helm template c "$CLUSTER_CHART" -f "$CLUSTER_CHART/values-example.yaml" --set monitoring.enabled=true --set-json 'monitoring.targetNamespaces=["eduide-test1"]' "$@" 2>/dev/null; }
expect "CRD has targetIdle with minimum 0" "0" "$(CR | yq -r 'select(.kind=="CustomResourceDefinition" and .metadata.name=="appdefinitions.theia.cloud") | .spec.versions[] | select(.name=="v1beta11") | .schema.openAPIV3Schema.properties.spec.properties.targetIdle.minimum')"

echo
if [[ $FAILED -ne 0 ]]; then echo "FAILED"; exit 1; fi
echo "all pool scaler checks passed"
