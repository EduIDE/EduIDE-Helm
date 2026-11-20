#!/usr/bin/env bash
# Lints and renders charts/eduide and charts/eduide-cluster with the CI and test3 values and checks the rules that must hold.
# Dependencies come from the published OCI repository. CP_CHARTS points at a checkout of
# EduIDE-control-plane/charts to test against unreleased subcharts: the dependencies are then
# rewritten to file:// in a temp copy. Needs helm and yq (mikefarah).
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok: $*"; }

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
cp -R charts/eduide "$tmp/eduide"
cp -R charts/eduide-cluster "$tmp/eduide-cluster"
rm -rf "$tmp"/eduide/charts "$tmp"/eduide-cluster/charts
if [ -n "${CP_CHARTS:-}" ]; then
  CP_CHARTS=$(cd "$CP_CHARTS" && pwd)
  for c in eduide:eduide-control-plane eduide:eduide-landing-page eduide-cluster:eduide-control-plane-crds; do
    yq -i '(.dependencies[] | select(.name == "'${c#*:}'") | .repository) = "file://'"$CP_CHARTS/${c#*:}"'"' "$tmp/${c%%:*}/Chart.yaml"
  done
fi
for c in eduide eduide-cluster; do helm dependency update "$tmp/$c" >/dev/null || fail "helm dependency update $c"; done
chart="$tmp/eduide"
cluster="$tmp/eduide-cluster"

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

# The IDE image tag follows the chart appVersion unless a deployment or a template says otherwise.
app=$(yq .appVersion "$chart/Chart.yaml")
tags=$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns | yq -N 'select(.kind == "IDETemplate") | .spec.image' | sed 's/.*://' | sort -u)
[ "$tags" = "$app" ] || fail "default image tag is '$tags', want appVersion $app"
[ "$(helm template r "$chart" -f "$chart/ci/test-values.yaml" -n ns --set images.tag=pr-1 | yq -N 'select(.kind == "IDETemplate") | .spec.image' | sed 's/.*://' | sort -u)" = pr-1 ] || fail "images.tag override ignored"
ok "image tag defaults to appVersion $app"

# --- eduide-cluster ---
helm lint "$cluster" -f "$cluster/ci/test-values.yaml" >/dev/null || fail "helm lint eduide-cluster"
co=$(helm template c "$cluster" -n eduide-system -f "$cluster/ci/test-values.yaml") || fail "helm template eduide-cluster"
[ "$(yq -N 'select(.kind == "CustomResourceDefinition") | .metadata.name' <<<"$co" | wc -l)" -eq 4 ] || fail "expected the 4 control plane CRDs"
! grep -q 'theia' <<<"$co" || fail "Theia Cloud leftovers in the cluster chart"
[ "$(yq -N 'select(.kind == "ConfigMap" and .metadata.name == "eduide-cluster-identity") | .metadata.namespace + "/" + .data.clusterName' <<<"$co")" = "eduide-system/ci" ] || fail "cluster identity ConfigMap"
[ "$(yq -N 'select(.kind == "EnvoyProxy") | .spec.mergeGateways' <<<"$co")" = true ] || fail "EnvoyProxy does not default mergeGateways to true"
[ "$(yq -N 'select(.kind == "GatewayClass") | .metadata.name' <<<"$co")" = envoy ] || fail "GatewayClass missing"
[ "$(helm template c "$cluster" -n eduide-system -f "$cluster/ci/test-values.yaml" --set envoyProxy.spec.mergeGateways=false | yq -N 'select(.kind == "EnvoyProxy") | .spec.mergeGateways')" = false ] || fail "EnvoyProxy spec cannot override mergeGateways"
[ "$(yq -N 'select(.kind == "EnvoyProxy") | .spec.provider.kubernetes.envoyDeployment.replicas' <<<"$co")" = 1 ] || fail "EnvoyProxy replicas default"
ok "eduide-cluster: CRDs, identity, GatewayClass, EnvoyProxy, no Theia Cloud"

# The guard must refuse a cluster that still has the Theia Cloud CRDs. lookup is empty in helm template, so the
# test wrapper chart swaps it for a value; the real template is included unchanged.
mkdir -p "$tmp/guard/templates"
printf 'apiVersion: v2\nname: guard\nversion: 0.0.0\n' > "$tmp/guard/Chart.yaml"
cp "$cluster/templates/_helpers.tpl" "$tmp/guard/templates/_helpers.tpl"
printf '{{- include "eduide-cluster.theiaGuard" (dict "found" .Values.found "allow" .Values.allowRemovingTheiaCloud) }}\n' > "$tmp/guard/templates/guard.yaml"
if helm template g "$tmp/guard" --set found=true >/dev/null 2>&1; then fail "guard accepted a cluster with Theia Cloud CRDs"; fi
msg=$(helm template g "$tmp/guard" --set found=true 2>&1 || true)
grep -q 'allowRemovingTheiaCloud' <<<"$msg" || fail "guard message does not name the override"
helm template g "$tmp/guard" --set found=true --set allowRemovingTheiaCloud=true >/dev/null || fail "guard ignores allowRemovingTheiaCloud"
helm template g "$tmp/guard" --set found=false >/dev/null || fail "guard fails on a clean cluster"
grep -q 'appdefinitions.theia.cloud' "$cluster/templates/theia-guard.yaml" || fail "guard template does not look up appdefinitions.theia.cloud"
ok "Theia Cloud CRD guard"
echo "all eduide checks passed"
