#!/usr/bin/env bash
# The maintenance page and the settings that keep deploys from showing it.
#
# While the landing page has no ready pod, Envoy answers with a bare
# "no healthy upstream". The chart replaces that with files/maintenance.html,
# and makes rolling updates keep a ready pod around so it is rarely needed.
# None of this is visible until something goes down, so assert it here.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
PAGE="$CHART/files/maintenance.html"
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }

"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CHART" >/dev/null || {
  echo "could not resolve chart dependencies" >&2; exit 1; }

render() {
  # keycloak.cookieSecret is required (no committed default); like skipPreflight
  # and allowUnauthenticated above, a dummy value just lets the chart render.
  helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret "$@" 2>/dev/null
}

# expect <label> <expected> <actual>
expect() {
  if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi
}

echo "=== maintenance page ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }

body=$(yq -r 'select(.kind=="ConfigMap" and .metadata.name=="maintenance-page") | .data."response.body"' <<<"$OUT")
if [[ "$body" == *"EduIDE is currently unavailable"* ]]; then
  ok "ConfigMap maintenance-page carries the page"
else
  bad "ConfigMap maintenance-page carries the page" "body starts with: ${body:0:80}"
fi

POLICY='select(.kind=="BackendTrafficPolicy" and .metadata.name=="landing-maintenance-page")'
expect "policy targets landing-route" "HTTPRoute/landing-route" \
  "$(yq -r "$POLICY | .spec.targetRefs[] | .kind + \"/\" + .name" <<<"$OUT")"
expect "policy overrides 502, 503 and 504" "502 503 504" \
  "$(yq -r "$POLICY | .spec.responseOverride[0].match.statusCodes[].value" <<<"$OUT" | tr '\n' ' ' | sed 's/ $//')"
expect "policy body comes from the ConfigMap" "ConfigMap/maintenance-page" \
  "$(yq -r "$POLICY | .spec.responseOverride[0].response.body.valueRef | .kind + \"/\" + .name" <<<"$OUT")"
expect "policy answers with HTML" "text/html; charset=utf-8" \
  "$(yq -r "$POLICY | .spec.responseOverride[0].response.contentType" <<<"$OUT")"

count_maintenance() {
  yq -r 'select((.kind=="ConfigMap" and .metadata.name=="maintenance-page") or .kind=="BackendTrafficPolicy") | .metadata.name' \
    | grep -cvE '^(---|null)?$'
}
expect "maintenancePage.enabled=false renders neither" "0" \
  "$(render --set maintenancePage.enabled=false | count_maintenance)"
expect "landingPage.enabled=false renders neither" "0" \
  "$(render --set landingPage.enabled=false | count_maintenance)"

# Envoy serves the page while the landing page is down, so anything it links
# to would be down too. Keep it small, it lives in a ConfigMap and in Envoy.
size=$(wc -c <"$PAGE" | tr -d ' ')
if (( size < 16384 )); then ok "page is ${size} bytes"; else bad "page is too large" "${size} bytes, keep it under 16 KiB"; fi
external=$(grep -oiE '(src|href)=["'"'"']?[a-z]+://[^"'"'"' >]*' "$PAGE" || true)
if [[ -z "$external" ]]; then ok "page loads nothing from outside"; else bad "page loads external resources" "$external"; fi
# Envoy reads the body as a format string, where % starts a command operator.
# A stray one (height: 100%) makes Envoy reject the whole override silently -
# the policy still says Accepted and visitors get an empty 503.
if ! grep -q '%' "$PAGE"; then ok "page has no % for Envoy to misread"; else bad "page contains %" "$(grep -n '%' "$PAGE" | head -3 | tr '\n' ' ')"; fi

echo
echo "=== rolling updates keep a ready pod ==="

deploy() { yq -r "select(.kind==\"Deployment\" and .metadata.name==\"$1\") | $2" <<<"$OUT"; }

for d in landing-page-deployment service-deployment; do
  expect "$d: maxUnavailable 0" "0" "$(deploy "$d" '.spec.strategy.rollingUpdate.maxUnavailable')"
  expect "$d: preStop sleeps" "sleep 10" "$(deploy "$d" '.spec.template.spec.containers[0].lifecycle.preStop.exec.command | join(" ")')"
  expect "$d: 1 replica by default" "1" "$(deploy "$d" '.spec.replicas')"
  expect "$d: spreads across nodes" "ScheduleAnyway" \
    "$(deploy "$d" '.spec.template.spec.topologySpreadConstraints[0].whenUnsatisfiable')"
done
expect "service-deployment: readiness waits for the port" "http" \
  "$(deploy service-deployment '.spec.template.spec.containers[0].readinessProbe.tcpSocket.port')"

echo
echo "=== pod disruption budgets ==="

pdbs() { yq -r 'select(.kind=="PodDisruptionBudget") | .metadata.name' | grep -vE '^(---|null)?$' | sort | tr '\n' ' ' | sed 's/ $//'; }

expect "no PDB with a single replica" "" "$(pdbs <<<"$OUT")"
expect "a PDB per Deployment with two replicas" "landing-page-pdb service-pdb" \
  "$(render --set landingPage.replicas=2 --set service.replicas=2 | pdbs)"
expect "only the Deployment with two replicas gets one" "service-pdb" \
  "$(render --set service.replicas=2 | pdbs)"
expect "podDisruptionBudget.enabled=false renders none" "" \
  "$(render --set landingPage.replicas=2 --set service.replicas=2 --set podDisruptionBudget.enabled=false | pdbs)"
expect "no landing page PDB without a landing page" "service-pdb" \
  "$(render --set landingPage.replicas=2 --set service.replicas=2 --set landingPage.enabled=false | pdbs)"
expect "PDB selects the landing page pods" "landing-page" \
  "$(render --set landingPage.replicas=2 | yq -r 'select(.kind=="PodDisruptionBudget") | .spec.selector.matchLabels.app')"

echo
echo "=== landing page runs without root ==="

landing() { deploy landing-page-deployment "$1"; }

expect "containerPort is 8080" "8080" "$(landing '.spec.template.spec.containers[0].ports[0].containerPort')"
expect "readiness probe uses 8080" "8080" "$(landing '.spec.template.spec.containers[0].readinessProbe.httpGet.port')"
expect "Service targets 8080" "8080" \
  "$(yq -r 'select(.kind=="Service" and .metadata.name=="landing-page-service") | .spec.ports[0].targetPort' <<<"$OUT")"
# Routes address the Service, so its own port must not follow the container.
expect "Service stays on 80" "80" \
  "$(yq -r 'select(.kind=="Service" and .metadata.name=="landing-page-service") | .spec.ports[0].port' <<<"$OUT")"
expect "route still points at 80" "80" \
  "$(yq -r 'select(.kind=="HTTPRoute" and .metadata.name=="landing-route") | .spec.rules[0].backendRefs[0].port' <<<"$OUT")"
expect "pod: runAsNonRoot" "true" "$(landing '.spec.template.spec.securityContext.runAsNonRoot')"
expect "pod: seccomp RuntimeDefault" "RuntimeDefault" "$(landing '.spec.template.spec.securityContext.seccompProfile.type')"
expect "container: no privilege escalation" "false" "$(landing '.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation')"
expect "container: read-only root filesystem" "true" "$(landing '.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem')"
expect "container: drops all capabilities" "ALL" "$(landing '.spec.template.spec.containers[0].securityContext.capabilities.drop | join(" ")')"
# Without this nginx cannot write its pid file on the read-only root filesystem.
expect "/tmp is mounted" "/tmp" "$(landing '.spec.template.spec.containers[0].volumeMounts[] | select(.name=="tmp") | .mountPath')"
expect "/tmp is an emptyDir" "{}" "$(landing '.spec.template.spec.volumes[] | select(.name=="tmp") | .emptyDir')"

trusted() { yq -r 'select(.kind=="ConfigMap" and .metadata.name=="landing-page-config") | .data."config.js"' | grep trustedArtemisHosts | tr -d ' '; }

expect "no trustedArtemisHosts by default" "" "$(trusted <<<"$OUT")"
expect "trustedArtemisHosts renders quoted strings" 'trustedArtemisHosts:["a.example.edu","b.example.edu"],' \
  "$(render --set 'landingPage.trustedArtemisHosts={a.example.edu,b.example.edu}' | trusted)"

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
