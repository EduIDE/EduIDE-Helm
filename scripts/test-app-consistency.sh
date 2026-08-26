#!/usr/bin/env bash
# The three consumers of appDefinitions.apps must agree.
#
# An installation offers an app in three places: the AppDefinition custom
# resource that makes it deployable, the landing page entry that lets a student
# pick it, and the preloading DaemonSet that pulls its image onto every node.
# These used to be three hand-maintained lists in two repositories, addressed by
# array index. Production ended up offering c-templates while preloading
# everything except c-templates - students picking it waited for a cold
# multi-gigabyte pull.
#
# They are all derived from one map now. This asserts the derivation, so a
# template change cannot quietly reintroduce the skew.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART="$ROOT/charts/eduide"
FAILED=0

ok()  { printf '  PASS  %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; [[ -n "${2:-}" ]] && printf '        %s\n' "$2"; FAILED=1; }

# charts/*/charts/ is gitignored - dependencies are resolved, not vendored - so
# a fresh checkout has none and `helm template` refuses outright. Resolve once
# up front rather than leaving this script only working where someone happened
# to have run `helm dependency update` by hand.
"$(dirname "${BASH_SOURCE[0]}")/resolve-deps.sh" "$CHART" >/dev/null || {
  echo "could not resolve chart dependencies" >&2; exit 1; }

render() {
  helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true "$@" 2>/dev/null
}

echo "=== app definitions, landing page and preloading agree ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }

declared=$(yq -r '.appDefinitions.apps | keys | .[]' "$CHART/values.yaml" | sort)
defs=$(yq -r 'select(.kind=="AppDefinition") | .metadata.name' <<<"$OUT" | grep -v '^---$' | sort)

if [[ "$declared" == "$defs" ]]; then
  ok "$(wc -l <<<"$defs" | tr -d ' ') AppDefinitions, one per declared app"
else
  bad "AppDefinitions do not match the declared apps" "$(diff <(echo "$declared") <(echo "$defs") | tr '\n' ' ')"
fi

# Every image an AppDefinition references, and every sidecar image, has to be
# on the node before a session starts.
app_images=$(yq -r 'select(.kind=="AppDefinition") | .spec.image, (.spec.sidecars // [])[].image' <<<"$OUT" \
                | grep -v '^---$' | sort -u)
preloaded=$(yq -r 'select(.kind=="DaemonSet" and .metadata.name=="image-preloading")
                   | .spec.template.spec.initContainers[].image' <<<"$OUT" | grep -v '^---$' | sort -u)

missing=$(comm -23 <(echo "$app_images") <(echo "$preloaded"))
if [[ -z "$missing" ]]; then
  ok "every app and sidecar image is preloaded"
else
  bad "images offered but not preloaded" "$(tr '\n' ' ' <<<"$missing")"
fi

# The landing page must not advertise an app that was never deployed.
offered=$(yq -r 'select(.kind=="ConfigMap" and (.metadata.name|test("landing")))
                 | .data | to_entries[0].value' <<<"$OUT" \
          | sed -n '/additionalApps: \[/,/^ *\],/p' \
          | grep -oE 'serviceAuthToken: "[^"]+"' | sed 's/.*"\(.*\)"/\1/' | sort -u)
if [[ -z "$offered" ]]; then
  bad "landing page offers no apps at all" ""
else
  orphan=$(comm -23 <(echo "$offered") <(echo "$defs"))
  if [[ -z "$orphan" ]]; then
    ok "$(wc -l <<<"$offered" | tr -d ' ') apps offered, all of them deployed"
  else
    bad "landing page offers apps with no AppDefinition" "$(tr '\n' ' ' <<<"$orphan")"
  fi
fi

# The landing page's own default app has to be one of them, or the page loads
# pointing at nothing.
default=$(yq -r '.landingPage.appDefinition' "$CHART/values.yaml")
if grep -qx "$default" <<<"$defs"; then
  ok "landingPage.appDefinition '$default' exists"
else
  bad "landingPage.appDefinition '$default' has no AppDefinition" ""
fi

echo
echo "=== versions ==="

# A release is `helm install --version X` with no overrides. Every EduIDE image
# must then carry a tag that release published, not a floating one.
APP_VERSION=$(yq -r '.appVersion' "$CHART/Chart.yaml")
floating=$(grep -oE "ghcr\.io/eduide/[^ \";']+" <<<"$OUT" | sort -u | grep -E ':(latest|main|next)$')
if [[ -z "$floating" ]]; then
  ok "no floating tags in a default render"
else
  bad "default render uses floating tags" "$(tr '\n' ' ' <<<"$floating")"
fi

ide=$(grep -oE "ghcr\.io/eduide/eduide/[^ \";']+" <<<"$OUT" | sort -u)
wrong=$(grep -v ":${APP_VERSION}\$" <<<"$ide")
if [[ -z "$wrong" ]]; then
  ok "every IDE image defaults to appVersion ${APP_VERSION}"
else
  bad "IDE images not on appVersion ${APP_VERSION}" "$(tr '\n' ' ' <<<"$wrong")"
fi

# Cloud and landing page release on their own cadence, so they must be
# overridable without touching anything else.
for pair in "cloud:eduide-cloud/operator" "landingPage:eduidec-landing-page"; do
  key="${pair%%:*}"; repo="${pair##*:}"
  got=$(render --set "versions.${key}=9.9.9" | grep -oE "ghcr\.io/eduide/${repo}:[^ \";']+" | sort -u)
  if [[ "$got" == "ghcr.io/eduide/${repo}:9.9.9" ]]; then
    ok "versions.${key} overrides ${repo} independently"
  else
    bad "versions.${key} did not take effect" "$got"
  fi
done

echo
echo "=== the dependency cache adds no routing ==="

# The cache subchart has its own `gateway:` table, and so does this chart. Helm
# coalesces the parent's into it, which it announces as
#   warning: cannot overwrite table with non table for
#   eduide-shared-cache.gateway.parentRefs
# The subchart's map wins, so its HTTPRoutes stay off and only this chart's
# three routes render. That is the behaviour being relied on, so assert it:
# if coalescing ever starts propagating `gateway.enabled: true` down, the cache
# would publish routes for hostnames nobody configured.
with_cache=$(render --set eduide-shared-cache.enabled=true \
  | yq -r 'select(.kind=="HTTPRoute") | .metadata.name' 2>/dev/null | grep -vE '^(---|null)$' | sort)
without=$(render | yq -r 'select(.kind=="HTTPRoute") | .metadata.name' 2>/dev/null \
  | grep -vE '^(---|null)$' | sort)
if [[ "$with_cache" == "$without" ]]; then
  ok "enabling the cache adds no HTTPRoute"
else
  bad "the cache added routes" "$(comm -23 <(echo "$with_cache") <(echo "$without") | tr '\n' ' ')"
fi

echo
echo "=== rendered names are valid Kubernetes names ==="

# RFC 1123: lowercase alphanumerics and dashes. Easy to break from a values file
# without noticing, because helm template happily renders an invalid name and
# only the API server rejects it. A camelCase dependency alias did exactly this:
# it becomes .Chart.Name in the subchart, which built `sharedCache-redis`.
for extra in "" "--set eduide-shared-cache.enabled=true"; do
  # shellcheck disable=SC2086
  names=$(render $extra | yq -r '.metadata.name' 2>/dev/null | grep -vE '^(---|null)$' | sort -u)
  bad_names=$(grep -vE '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' <<<"$names" || true)
  label="${extra:-defaults}"
  if [[ -z "$bad_names" ]]; then
    ok "$(wc -l <<<"$names" | tr -d ' ') names valid (${label})"
  else
    bad "invalid resource names (${label})" "$(tr '\n' ' ' <<<"$bad_names")"
  fi
done

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
