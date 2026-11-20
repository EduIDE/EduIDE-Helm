#!/usr/bin/env bash
# Lints and renders charts/eduide-go with the test3 and CI values and checks the rules that must hold.
# The subcharts are not published yet: CP_CHARTS points at a checkout of EduIDE-control-plane/charts
# and the dependencies are rewritten to file:// in a temp copy. Needs helm and yq (mikefarah).
set -euo pipefail
cd "$(dirname "$0")/.."
CP_CHARTS=${CP_CHARTS:-../../EduIDE-control-plane/charts}
CP_CHARTS=$(cd "$CP_CHARTS" && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -R charts/eduide-go "$tmp/eduide-go"
for d in eduide-control-plane eduide-landing-page; do
  yq -i '(.dependencies[] | select(.name == "'$d'") | .repository) = "file://'"$CP_CHARTS/$d"'"' "$tmp/eduide-go/Chart.yaml"
done
helm dependency update "$tmp/eduide-go" >/dev/null
chart="$tmp/eduide-go"

for v in "$chart/ci/test-values.yaml" deployments/test3/values-test3.yaml; do
  helm lint "$chart" -f "$v" -n eduide-test3 >/dev/null || fail "helm lint -f $v"
  out=$(helm template r "$chart" -f "$v" -n eduide-test3) || fail "helm template -f $v"
  d() { echo "$out" | yq -o=json -I=0 "select($1)"; }
  ok "lint and template ($v)"

  hosts=$(helm template r "$chart" -f "$v" -n eduide-test3 | yq 'select(.kind == "Gateway") | .spec.listeners[].hostname' | sort -u)
  [ "$(echo "$hosts" | wc -l)" -eq 3 ] || fail "expected exactly three listener hosts, got: $hosts"
  echo "$hosts" | grep -q '\*' && fail "wildcard host in Gateway"
  inst=$(d '.kind == "Gateway"' | yq -p=json '.spec.listeners[] | select(.name == "https-instance") | .hostname')
  [ "$(echo "$hosts" | grep -c "^webview.$inst\$")" -eq 1 ] || fail "webview host is not webview.<instance>"
  [ "$(d '.kind == "Gateway"' | yq -p=json '[.spec.listeners[] | select(.protocol == "HTTPS")] | length')" -eq 3 ] || fail "expected 3 HTTPS listeners"
  [ "$(d '.kind == "Gateway"' | yq -p=json '[.spec.listeners[] | select(.protocol == "HTTP" and .port == 80)] | length')" -eq 3 ] || fail "expected 3 HTTP ACME listeners"
  ok "Gateway: three hosts, 3 HTTPS + 3 HTTP listeners, no wildcard"

  r=$(d '.kind == "HTTPRoute" and (.metadata.name | test("https-redirect$"))')
  [ "$(echo "$r" | yq -p=json '[.spec.parentRefs[].sectionName] | sort | join(",")')" = "http-instance,http-service,http-webview" ] || fail "redirect route is not attached to the three http listeners"
  [ "$(echo "$r" | yq -p=json '.spec.hostnames | sort | join(",")')" = "$(echo "$hosts" | paste -sd, -)" ] || fail "redirect route hostnames differ from the listener hosts"
  [ "$(echo "$r" | yq -p=json '.spec.rules[0].filters[0].requestRedirect | .scheme + .statusCode')" = "https301" ] || fail "redirect is not https 301"
  [ "$(echo "$r" | yq -p=json '.spec.rules[0].matches[0].path | .type + .value')" = "PathPrefix/" ] || fail "redirect must match PathPrefix / so exact ACME challenge paths stay more specific"
  ok "HTTP to HTTPS redirect route (301, ACME challenge paths stay more specific)"

  gw=$(d '.kind == "Gateway"' | yq -p=json '.metadata.name')
  [ "$(d '.kind == "Issuer" and .spec.acme' | yq -p=json '.spec.acme.solvers[0].http01.gatewayHTTPRoute.parentRefs[0].name')" = "$gw" ] || fail "Issuer solver does not point at the Gateway"
  [ "$(d '.kind == "Gateway"' | yq -p=json '.metadata.annotations["cert-manager.io/issuer"]')" = "$(d '.kind == "Issuer" and .spec.acme' | yq -p=json '.metadata.name')" ] || fail "Gateway annotation does not name the Issuer"
  ok "Issuer solver points at Gateway $gw"

  [ "$(d '.kind == "NetworkPolicy"' | wc -l)" -ge 3 ] || fail "NetworkPolicies missing"
  [ "$(d '.kind == "SecurityPolicy"' | wc -l)" -eq 1 ] || fail "SecurityPolicy missing"
  [ "$(d '.kind == "IDETemplate"' | wc -l)" -ge 1 ] || fail "IDETemplate missing"
  [ "$(d '.kind == "IDEPool"' | wc -l)" -ge 1 ] || fail "IDEPool missing"
  [ "$(d '.kind == "IDEPool"' | yq -N -p=json '.spec | has("targetIdle")' | sort -u)" = false ] || fail "IDEPool renders targetIdle, which the pool scaler owns"
  keys=$(d '.kind == "IDETemplate" and .metadata.name == "java-17"' | yq -p=json '[.spec.injectableKeys[].name] | join(",")')
  [ "$keys" = "GIT_URI,ARTEMIS_URL,ARTEMIS_TOKEN,TEMPLATE,GIT_USER,GIT_MAIL" ] || fail "injectable keys: $keys"
  grep -q 'name: webview\|webview\.' <<<"$out" || fail "webview host missing in render"
  ok "NetworkPolicy, SecurityPolicy, IDETemplate, IDEPool"
done

# GIT_URI accepts credentials only where a deployment asks for it (Artemis#14702).
[ "$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns | grep -c 'allowCredentials')" -eq 0 ] || fail "allowCredentials set by default"
[ "$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns --set templateDefaults.gitUriAllowCredentials=true | yq -N 'select(.kind == "IDETemplate") | .spec.injectableKeys[] | select(.allowCredentials == true) | .name' | sort -u)" = GIT_URI ] || fail "gitUriAllowCredentials does not set allowCredentials on GIT_URI only"
ok "gitUriAllowCredentials"

# The landing page offers only listed templates: the artemis editions are unlisted, the standalone ones keep the
# CRD default (listed), and a deployment can override either.
lv="$tmp/listed-values.yaml"
printf 'templates:\n  java-17-standalone: {}\n  c: {listed: true}\n' > "$lv"
lo=$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -f "$lv" -n ns | yq -N 'select(.kind == "IDETemplate") | .metadata.name + "=" + (.spec.listed | tostring)' | sort | paste -sd, -)
[ "$lo" = "c=true,java-17-standalone=,java-17=false" ] || fail "listed: $lo"
ok "listed (artemis editions unlisted, standalone listed, overridable)"

# The OIDC bridge follows the issuer host and only Envoy may reach it.
br=$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns --set oidcBridge.enabled=true) || fail "render with oidcBridge"
iss_host=$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns --show-only charts/eduide-control-plane/templates/config.yaml 2>/dev/null | grep -o 'issuerURL: [^ ]*' | head -1 | sed -E 's#issuerURL: "?https://([^/"]*).*#\1#')
[ -n "$iss_host" ] || fail "no issuer host in the test values"
[ "$(yq -N 'select(.kind == "BackendTLSPolicy") | .spec.validation.hostname' <<<"$br")" = "$iss_host" ] || fail "BackendTLSPolicy hostname is not the issuer host"
grep -q "proxy_pass https://$iss_host;" <<<"$br" || fail "bridge does not proxy to the issuer host"
[ "$(yq -N 'select(.kind == "NetworkPolicy" and .metadata.name == "r-oidc-bridge-from-envoy") | .spec.ingress[0].ports[0].port' <<<"$br")" = 8443 ] || fail "bridge NetworkPolicy missing"
! helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns | grep -q 'oidc-bridge' || fail "oidcBridge renders while disabled"
ok "oidcBridge"

# Mismatching landing page host must be refused.
if helm template r "$chart" -f "$chart/ci/test-values.yaml" --set eduide-landing-page.host=other.example.org >/dev/null 2>&1; then fail "landing page host mismatch accepted"; fi
ok "host mismatch refused"
echo "all eduide-go checks passed"
