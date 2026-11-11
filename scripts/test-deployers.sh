#!/usr/bin/env bash
# The deployer ServiceAccounts in eduide-cluster can install the eduide chart
# and nothing more. A kind the eduide chart starts rendering, or a right its
# Roles start granting, has to be added to the deployer in the same change, or
# the next deploy is refused. Nothing else would notice until then, so check
# every kind and every rule the eduide chart renders against the deployer's.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
CLUSTER_CHART="$ROOT/charts/eduide-cluster"
NS=eduide-x
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }

"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CHART" >/dev/null || {
  echo "could not resolve chart dependencies" >&2; exit 1; }

cluster() {
  helm template c "$CLUSTER_CHART" -n eduide-system -f "$CLUSTER_CHART/values-example.yaml" "$@" 2>/dev/null
}

# Representative: every optional kind on, the garbage collector included.
# operator.clusterWideRbac stays off; the deployer is not meant to grant
# cluster-wide operator rights.
TENANT=$(helm template t "$CHART" -n "$NS" --set skipPreflight=true \
  --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret \
  --set theia-workspace-garbage-collector.enabled=true \
  --set landingPage.replicas=2 --set service.replicas=2 \
  --set service.adminApiTokenSecret.create=true --set service.adminApiToken=x \
  --set operator.logging.override=true 2>/dev/null) || { echo "  eduide does not render"; exit 1; }
DEPLOYERS=$(cluster --set deployers.enabled=true --set "deployers.namespaces={$NS}") || {
  echo "  eduide-cluster does not render"; exit 1; }

# One line per granted "group resource verb name", with "core" for the core
# group and "*" when the rule names no resources.
grants() {
  yq -N -r '.rules[] as $r | $r.apiGroups[] as $g | $r.resources[] as $res | $r.verbs[] as $v
    | ($r.resourceNames // ["*"])[] as $n | [($g | sub("^$"; "core")), $res, $v, $n] | join(" ")'
}
ROLE=$(yq "select(.kind == \"Role\" and .metadata.namespace == \"$NS\")" <<<"$DEPLOYERS" | grants)
CLUSTER_ROLE=$(yq 'select(.kind == "ClusterRole")' <<<"$DEPLOYERS" | grants)

# allows <grants> <group> <resource> <verb> <name>
allows() { grep -qxF -e "$2 $3 $4 $5" -e "$2 $3 $4 *" <<<"$1"; }

plural() {
  local k; k=$(tr '[:upper:]' '[:lower:]' <<<"$1")
  case "$k" in *y) echo "${k%y}ies" ;; *s) echo "${k}es" ;; *) echo "${k}s" ;; esac
}

echo "=== every object the eduide chart renders, the deployer can manage ==="

while read -r apiVersion kind name; do
  group=core; [[ "$apiVersion" == */* ]] && group=${apiVersion%/*}
  res=$(plural "$kind")
  case "$kind" in
    ClusterRole|ClusterRoleBinding) grants=$CLUSTER_ROLE ;;
    *) grants=$ROLE ;;
  esac
  missing=()
  for verb in get create update patch delete; do
    # Kubernetes cannot limit create to a name, so it is never name-scoped.
    n=$name; [[ $verb == create ]] && n='*'
    allows "$grants" "$group" "$res" "$verb" "$n" || missing+=("$verb")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "$kind $name"
  else
    bad "$kind $name" "deployer lacks ${missing[*]} on $group/$res"
  fi
done < <(yq -N -r 'select(.kind) | [.apiVersion, .kind, .metadata.name] | join(" ")' <<<"$TENANT" | sort -u)

echo
echo "=== every right the eduide chart grants, the deployer holds ==="

# Kubernetes refuses a Role or ClusterRole with rights its creator does not
# hold, and so refuses a ClusterRoleBinding to one.
check_rules() {
  local kind=$1 grants=$2 group res verb n
  while read -r group res verb n; do
    [[ -z "$group" ]] && continue
    if ! allows "$grants" "$group" "$res" "$verb" "$n"; then
      bad "$kind grants $verb on $group/$res" "the deployer does not hold it"
    fi
  done < <(yq "select(.kind == \"$kind\")" <<<"$TENANT" | grants | sort -u)
}
before=$FAILED
check_rules Role "$ROLE"
check_rules ClusterRole "$CLUSTER_ROLE"
[[ $FAILED == "$before" ]] && ok "every Role and ClusterRole rule"

# A RoleBinding to a ClusterRole the chart does not render itself needs `bind`.
RENDERED_CRS=$(yq -N -r 'select(.kind == "ClusterRole") | .metadata.name' <<<"$TENANT")
while read -r ref; do
  [[ -z "$ref" ]] && continue
  if grep -qxF "$ref" <<<"$RENDERED_CRS"; then continue; fi
  if allows "$ROLE" rbac.authorization.k8s.io clusterroles bind "$ref"; then
    ok "bind ClusterRole $ref"
  else
    bad "bind ClusterRole $ref" "the deployer Role has no bind on it"
  fi
done < <(yq -N -r 'select(.kind == "RoleBinding" and .roleRef.kind == "ClusterRole") | .roleRef.name' <<<"$TENANT" | sort -u)

echo
echo "=== eduide-cluster renders deployers only when asked ==="

count() { yq -N -r 'select(.kind) | .metadata.name' | grep -c deployer; }
expect() { if [[ "$3" == "$2" ]]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

expect "off by default" 0 "$(cluster --set "deployers.namespaces={$NS}" | count)"
expect "one namespace renders eight objects" 8 "$(count <<<"$DEPLOYERS")"
TWO=$(cluster --set deployers.enabled=true --set 'deployers.namespaces={eduide-a,eduide-b}')
expect "two namespaces render sixteen" 16 "$(count <<<"$TWO")"
expect "no Namespace object" 0 "$(yq -N -r 'select(.kind == "Namespace") | .metadata.name' <<<"$TWO" | wc -l | tr -d ' ')"

# Objects outside a tenant namespace are shared by every tenant, so their names
# and the names their rules allow must carry the namespace.
for ns in eduide-a eduide-b; do
  shared=$(yq -N -r "select((.metadata.namespace != \"$ns\") and (.subjects[0].namespace == \"$ns\"))
    | [.roleRef.name, .metadata.name] | .[]" <<<"$TWO" | sort -u)
  expect "$ns: shared Roles and bindings named for it" \
    "eduide-deployer-$ns eduide-deployer-identity-$ns" "$(tr '\n' ' ' <<<"$shared" | sed 's/ $//')"
  names=$(yq -N -r "select(.metadata.name | test(\"-$ns\$\") or .metadata.namespace == \"$ns\") | select(.kind == \"Role\" or .kind == \"ClusterRole\")
    | .rules[].resourceNames // [] | .[]" <<<"$TWO" | sort | tr '\n' ' ')
  expect "$ns: resourceNames" "$ns eduide-cluster-identity operator-api-access operator-api-access-cluster-$ns service-api-access " "$names"
done

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
