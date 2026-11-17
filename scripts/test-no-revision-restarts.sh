#!/usr/bin/env bash
# A deploy with no changes must not restart anything, and the certificate
# alerts must only look at namespaces EduIDE uses.
#
# 1. Pod templates carry no Release.Revision annotation (it changes on every
#    upgrade and rolled every pod), but still carry the checksums of the
#    ConfigMaps and Secrets they consume, so real config changes roll them.
# 2. The two certificate alerts are filtered to EduIDE's namespaces.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
CLUSTER_CHART="$ROOT/charts/eduide-cluster"
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }
expect() { if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CHART" >/dev/null || {
  echo "could not resolve chart dependencies" >&2; exit 1; }

render() {
  helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret "$@" 2>/dev/null
}

echo "=== pod templates ignore the release revision ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }
for w in operator-deployment service-deployment landing-page-deployment image-preloading; do
  n=$(yq -r "select(.metadata.name==\"$w\") | (.spec.template.metadata.annotations // {}) | keys | map(select(. == \"helm.sh/revision\")) | length" <<<"$OUT")
  expect "$w: no helm.sh/revision annotation" "0" "$n"
done

echo "=== consumed config still rolls pods ==="
ann() { yq -r "select(.metadata.name==\"$1\") | .spec.template.metadata.annotations[\"$2\"] // \"\""; }
before=$(ann operator-deployment checksum/operator-config <<<"$OUT")
[[ -n "$before" ]] && ok "operator: checksum/operator-config present" || bad "operator: checksum/operator-config present"
for pair in service-deployment:checksum/config service-deployment:checksum/secret landing-page-deployment:checksum/config; do
  [[ -n "$(ann "${pair%%:*}" "${pair#*:}" <<<"$OUT")" ]] && ok "${pair}" || bad "${pair} missing"
done

echo "=== secrets and config changes roll the pods ==="
sig() { yq -r "select(.metadata.name==\"$1\") | .spec.template.metadata.annotations | to_entries | map(.value) | join(\",\")" <<<"$2"; }
differs() {
  local label=$1 w=$2; shift 2
  if [[ "$(sig "$w" "$OUT")" != "$(sig "$w" "$(render "$@")")" ]]; then ok "$label rolls $w"; else bad "$label rolls $w"; fi
}
differs "service.authToken" operator-deployment --set service.authToken=other
differs "service.authToken" service-deployment --set service.authToken=other
differs "operator logging config" operator-deployment --set operator.logging.override=true
ADMIN=(--set service.adminApiTokenSecret.create=true)
OUT_ADMIN=$(render "${ADMIN[@]}")
if [[ "$(sig service-deployment "$OUT_ADMIN")" != "$(sig service-deployment "$(render "${ADMIN[@]}" --set service.adminApiToken=Zm9v)")" ]]; then
  ok "adminApiToken rolls service-deployment"
else
  bad "adminApiToken rolls service-deployment"
fi
differs "landingPage config" landing-page-deployment --set landingPage.appDefinition=python-standalone

echo "=== no Release.Revision left in the templates ==="
if grep -rn 'Release.Revision' "$CHART/templates" >/dev/null; then bad "Release.Revision still used"; else ok "Release.Revision unused"; fi

echo "=== certificate alerts are namespace scoped ==="

cluster() {
  helm template t "$CLUSTER_CHART" -f "$CLUSTER_CHART/values-example.yaml" \
    --set monitoring.enabled=true --set monitoring.alerting.enabled=true \
    --set monitoring.certManager.enabled=true "$@" 2>/dev/null
}
alert_expr() { yq -r "select(.kind==\"PrometheusRule\") | .spec.groups[].rules[] | select(.alert==\"$1\") | .expr"; }
RULES=$(cluster --set 'monitoring.targetNamespaces={eduide-prod,eduide-test}')
for a in EduIDECertificateExpiringSoon EduIDECertificateNotReady; do
  e=$(alert_expr "$a" <<<"$RULES")
  if [[ "$e" == *'namespace=~"^(eduide-prod|eduide-test|'*'eduide-system'*')$"'* ]]; then
    ok "$a: filtered to environments and eduide-system"
  else
    bad "$a: filtered to environments and eduide-system" "$e"
  fi
  if [[ "$e" == *'namespace="cert-manager", name="theia-cloud-ca-certificate"'* ]]; then
    ok "$a: includes the CA certificate by name"
  else
    bad "$a: includes the CA certificate by name" "$e"
  fi
done

e=$(alert_expr EduIDECertificateNotReady <<<"$(cluster --set 'monitoring.targetNamespaces=null' --set gateway.namespace=eduide-system --set monitoring.alerting.namespace=eduide-system --namespace eduide-system)")
[[ "$e" == *'namespace=~"^(eduide-system)$"'* ]] && ok "empty targetNamespaces: only eduide-system" || bad "empty targetNamespaces: only eduide-system" "$e"

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
