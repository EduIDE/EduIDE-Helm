#!/usr/bin/env bash
# The three consumers of the app list must agree.
#
# An installation offers an app in three places: the AppDefinition custom
# resource that makes it deployable, the landing page entry that lets a student
# pick it, and the preloading DaemonSet that pulls its image onto every node.
# These used to be three hand-maintained lists in two repositories, addressed by
# array index. Production ended up offering c-templates while preloading
# everything except c-templates - students picking it waited for a cold
# multi-gigabyte pull.
#
# They are all derived from one map now (eduide.apps: the catalog entries
# appDefinitions.enabled names, plus appDefinitions.apps). This asserts the
# derivation, so a template change cannot quietly reintroduce the skew.

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
  # keycloak.cookieSecret is required (no committed default), like skipPreflight
  # and allowUnauthenticated above a dummy value just lets the chart render here.
  helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=false \
    --set keycloak.allowUnauthenticated=true --set keycloak.cookieSecret=test-render-secret "$@" 2>/dev/null
}

echo "=== app definitions, landing page and preloading agree ==="

OUT=$(render) || { echo "  chart does not render"; exit 1; }

declared=$(yq -r '.appDefinitions.enabled[]' "$CHART/values.yaml" | sort)
# Written out on purpose: every installation that keeps the defaults gets this
# set, so adding to it is a decision for each of them, not a side effect of
# adding an image to the catalog.
default_set=$(printf '%s\n' c-latest c-templates-latest java-17-latest java-17-templates-latest javascript-latest python-latest)
if [[ "$declared" == "$default_set" ]]; then
  ok "the chart enables exactly the default set"
else
  bad "appDefinitions.enabled is not the default set" "$(diff <(echo "$default_set") <(echo "$declared") | tr '\n' ' ')"
fi
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

# Unset has to stay absent rather than render an empty nodeSelector: production
# and parma have no node pool, and their DaemonSets must not change.
preload_selector() {
  yq -o=json -I=0 'select(.kind=="DaemonSet" and .metadata.name=="image-preloading")
                   | .spec.template.spec.nodeSelector' | grep -v '^---$'
}
got=$(preload_selector <<<"$OUT")
if [[ "$got" == "null" ]]; then
  ok "preloading has no nodeSelector by default"
else
  bad "preloading has a nodeSelector by default" "$got"
fi
got=$(render --set-json 'preloading.nodeSelector={"aet.cit.tum.de/pool":"eduide"}' | preload_selector)
if [[ "$got" == '{"aet.cit.tum.de/pool":"eduide"}' ]]; then
  ok "preloading.nodeSelector reaches the DaemonSet"
else
  bad "preloading.nodeSelector does not reach the DaemonSet" "$got"
fi

# The landing page must not advertise an app that was never deployed.
offered=$(yq -r 'select(.kind=="ConfigMap" and (.metadata.name|test("landing")))
                 | .data | to_entries[0].value' <<<"$OUT" \
          | sed -n '/additionalApps: \[/,/^  \],/p' \
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
echo "=== enabled, catalog and apps ==="

app_names() { yq -r 'select(.kind=="AppDefinition") | .metadata.name' | grep -v '^---$' | sort | tr '\n' ' '; }
offered_names() {
  yq -r 'select(.kind=="ConfigMap" and .metadata.name=="landing-page-config") | .data."config.js"' \
    | sed -n '/additionalApps: \[/,/^  \],/p' | grep -oE 'serviceAuthToken: "[^"]+"' \
    | sed 's/.*"\(.*\)"/\1/' | sort | tr '\n' ' '
}
preloaded_images() {
  yq -r 'select(.kind=="DaemonSet" and .metadata.name=="image-preloading") | .spec.template.spec.initContainers[].image' \
    | grep -v '^---$' | sort
}

out=$(render --set-json 'appDefinitions.enabled=["java-17-latest","python-latest"]')
if [[ "$(app_names <<<"$out")" == "java-17-latest python-latest " \
      && "$(offered_names <<<"$out")" == "java-17-latest python-latest " ]]; then
  ok "enabled restricts the AppDefinitions and the landing page"
else
  bad "enabled does not restrict the app list" "defs=[$(app_names <<<"$out")] offered=[$(offered_names <<<"$out")]"
fi

# Another university's own image: a foreign registry and a tag, used as given.
custom=$(mktemp)
cat > "$custom" <<'EOF'
appDefinitions:
  enabled: [python-latest]
  apps:
    haskell-latest:
      image: registry.example.edu/ide/haskell:2.1.0
      limitsMemory: 4000M
      landingPage:
        label: Haskell
        image: theia-logo.png
    python-latest:
      landingPage:
        label: Python 3
EOF
out=$(render -f "$custom")
rm -f "$custom"
hs=$(yq -r 'select(.kind=="AppDefinition" and .metadata.name=="haskell-latest") | .spec.image + " " + .spec.limitsMemory' <<<"$out" | grep -v '^---$')
if [[ "$hs" == "registry.example.edu/ide/haskell:2.1.0 4000M" \
      && "$(app_names <<<"$out")" == "haskell-latest python-latest " \
      && "$(offered_names <<<"$out")" == "haskell-latest python-latest " ]] \
   && preloaded_images <<<"$out" | grep -qx 'registry.example.edu/ide/haskell:2.1.0'; then
  ok "a custom app renders, is offered and preloaded, with its image passed through"
else
  bad "a custom app did not reach all three consumers" "appdef=[$hs] defs=[$(app_names <<<"$out")] offered=[$(offered_names <<<"$out")]"
fi
# An override changes one field and keeps the rest of the catalog entry.
if grep -q 'appName: "Python 3"' <<<"$out" \
   && [[ "$(yq -r 'select(.kind=="AppDefinition" and .metadata.name=="python-latest") | .spec.image' <<<"$out" | grep -v '^---$')" == ghcr.io/eduide/eduide/python:* ]]; then
  ok "an apps entry merges over its catalog entry"
else
  bad "an apps entry must merge over its catalog entry, not replace it"
fi
# false has to win over the catalog too, which sprig's mergeOverwrite would drop.
if render --set appDefinitions.apps.python-latest.landingPage.visible=false | grep -A2 'serviceAuthToken: "python-latest"' | grep -q 'visible: false'; then
  ok "an override can set a field to false"
else
  bad "an override setting visible: false was lost"
fi

# null is how every environment removed apps before enabled existed; it must
# keep removing them, or upgrading the chart brings them all back.
out=$(render --set-json 'appDefinitions.apps={"c-latest":null}')
if ! grep -q 'c-latest' <<<"$(app_names <<<"$out") $(offered_names <<<"$out")" \
   && ! preloaded_images <<<"$out" | grep -q '/c:'; then
  ok "apps.<name>: null removes an enabled app everywhere"
else
  bad "apps.<name>: null did not remove the app" "defs=[$(app_names <<<"$out")]"
fi

if err=$(helm template t "$CHART" --set skipPreflight=true --set keycloak.allowUnauthenticated=true \
      --set keycloak.cookieSecret=test-render-secret --set-json 'appDefinitions.enabled=["no-such-app"]' 2>&1 >/dev/null); then
  bad "an unknown name in enabled must fail the render"
elif grep -q 'appDefinitions.enabled lists "no-such-app"' <<<"$err"; then
  ok "an unknown name in enabled fails the render and names it"
else
  bad "an unknown name in enabled failed without saying why" "$err"
fi

# Every catalog entry has to render on its own, or enabling it is the first
# time anyone finds out it is broken.
broken=""
for name in $(yq -r '.appDefinitions.catalog | keys | .[]' "$CHART/values.yaml"); do
  out=$(render --set-json "appDefinitions.enabled=[\"$name\"]")
  [[ "$(app_names <<<"$out")" == "$name " && "$(offered_names <<<"$out")" == "$name " ]] || broken+="$name "
done
if [[ -z "$broken" ]]; then
  ok "every catalog entry renders and is offered alone"
else
  bad "catalog entries that do not render alone" "$broken"
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
for pair in "cloud:eduide-cloud/operator" "landingPage:eduide-landing-page"; do
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

# Eager sessions get their environment from the operator over the data bridge. If
# the NetworkPolicy allows a different port than the app definitions open, the
# default-deny drops the injection and the session starts with no credentials.
rendered=$(render)
policy_port=$(yq -r 'select(.kind == "NetworkPolicy" and .metadata.name == "session-allow-operator") | .spec.ingress[0].ports[0].port' <<<"$rendered" | grep -vE '^(---|null)$')
app_ports=$(yq -r 'select(.kind == "AppDefinition") | .spec.options.dataBridgePort' <<<"$rendered" | grep -vE '^(---|null)$' | sort -u)
if [[ -n "$policy_port" && "$policy_port" == "$app_ports" ]]; then
  ok "data bridge port $policy_port open to the operator"
else
  bad "NetworkPolicy data bridge port does not match the app definitions" "policy=[$policy_port] apps=[$app_ports]"
fi

# One app overriding the port must fail the render, not lose its injection at runtime.
first_app=$(head -n1 <<<"$declared")
if render --set-string "appDefinitions.apps.$first_app.options.dataBridgePort=1234" >/dev/null; then
  bad "an app with a different data bridge port must fail the render" "app=[$first_app]"
else
  ok "an app with a different data bridge port fails the render"
fi

# Only the Minikube provider creates PersistentVolumes, and this rule is always bound cluster-wide.
pv_verbs() { yq -r 'select(.kind == "ClusterRole" and (.metadata.name | test("-cluster-"))) | .rules[] | select(.resources[] == "persistentvolumes") | .verbs[]' | grep -vE '^---$'; }
if ! pv_verbs <<<"$rendered" | grep -qx create && render --set operator.cloudProvider=MINIKUBE | pv_verbs | grep -qx create; then
  ok "PersistentVolume writes are granted only for Minikube"
else
  bad "PersistentVolume writes must be granted only for Minikube" "default=[$(pv_verbs <<<"$rendered" | tr '\n' ' ')]"
fi

# The operator polls this port for activity. A mismatch makes every poll fail.
policy_monitor=$(yq -r 'select(.kind == "NetworkPolicy" and .metadata.name == "session-allow-operator") | .spec.ingress[0].ports[1].port' <<<"$rendered" | grep -vE '^(---|null)$')
app_monitor=$(yq -r 'select(.kind == "AppDefinition") | .spec.monitor.port' <<<"$rendered" | grep -vE '^(---|null)$' | sort -u)
if [[ -n "$policy_monitor" && "$policy_monitor" == "$app_monitor" ]]; then
  ok "monitor port $policy_monitor open to the operator"
else
  bad "NetworkPolicy monitor port does not match the app definitions" "policy=[$policy_monitor] apps=[$app_monitor]"
fi

# The demo app and per-app overrides poll on their own monitor ports.
operator_ports() { yq -r 'select(.kind == "NetworkPolicy" and .metadata.name == "session-allow-operator") | .spec.ingress[0].ports[].port' | grep -vE '^(---|null)$'; }
if helm template t "$CHART" --set skipPreflight=true --set demoApplication.install=true --set keycloak.allowUnauthenticated=true \
    --set keycloak.cookieSecret=test-render-secret 2>/dev/null | operator_ports | grep -qx 3000; then
  ok "the demo app's monitor port is open to the operator"
else
  bad "the demo app's monitor port must be open to the operator"
fi
if render --set "appDefinitions.apps.$first_app.monitor.port=9123" | operator_ports | grep -qx 9123; then
  ok "a per-app monitor port is open to the operator"
else
  bad "a per-app monitor port must be open to the operator"
fi

# A value that expands to nothing must not render an empty cookie secret.
if render --set 'keycloak.cookieSecret={{ "" }}' >/dev/null; then
  bad "a cookie secret that expands to nothing must fail the render"
else
  ok "a cookie secret that expands to nothing fails the render"
fi
if grep -q 'cookie_secure="true"' <<<"$rendered" && render --set oauth2Proxy.cookieSecure=false | grep -q 'cookie_secure="false"'; then
  ok "cookie_secure defaults to true and can be turned off"
else
  bad "cookie_secure must default to true and follow oauth2Proxy.cookieSecure"
fi

# Without this exclusion a session reaches the cluster's own pods and services.
excluded=$(yq -r 'select(.kind == "NetworkPolicy" and .metadata.name == "session-allow-external-egress") | .spec.egress[0].to[0].ipBlock.except[]' <<<"$rendered")
if grep -qx '10.0.0.0/8' <<<"$excluded" && grep -qx '169.254.169.254/32' <<<"$excluded"; then
  ok "session egress excludes private ranges and the metadata endpoint"
else
  bad "session egress must exclude private ranges and the metadata endpoint" "except=[$excluded]"
fi

# The footer version used to be a hand-set string that drifted from the deploy.
footer_version() { render "$@" | grep -m1 -o 'version: "[^"]*"'; }
expect_version() {
  local want=$1; shift
  if [[ "$(footer_version "$@")" == "version: \"$want\"" ]]; then ok "footer version $want"; else bad "footer version should be $want" "got: $(footer_version "$@")"; fi
}
expect_version "v$(yq -r .versions.landingPage "$CHART/values.yaml")"
expect_version "pr-53" --set 'landingPage.image=ghcr.io/eduide/eduide-landing-page:pr-53'
expect_version "Staging" --set landingPage.footerLinks.attribution.version=Staging

echo
[[ $FAILED -eq 0 ]] && echo "ALL PASS" || echo "SOME FAILED"
exit $FAILED
