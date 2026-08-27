{{/*
  Fail early and legibly when the cluster has not been bootstrapped.

  Without this the first symptom of a missing eduide-cluster release is the
  operator crash-looping because the AppDefinition CRD does not exist, which is
  a considerably worse way to find out.

  This has to stay silent offline, or it breaks `helm template`, the render
  diff and CI. lookup returns empty in both cases - offline and genuinely
  missing - so it cannot tell them apart on its own. Looking up the kube-system
  namespace first can: every cluster has one, so an empty result means there is
  no cluster to talk to and there is nothing to check.

  The earlier version keyed off .Release.IsInstall, which is true under
  `helm template` as well, so it failed every offline render. It was also never
  invoked from any template, which is the only reason that went unnoticed.
*/}}
{{- define "eduide.preflight" -}}
{{- if not .Values.skipPreflight }}
{{- if .Capabilities.APIVersions.Has "theia.cloud/v1beta11" }}
{{- /* CRDs are present, so the cluster chart is installed. */ -}}
{{- else if (lookup "v1" "Namespace" "" "kube-system") }}
{{- /* A real cluster, and it does not have the CRDs. */ -}}
{{- if not (lookup "v1" "ConfigMap" "eduide-system" "eduide-cluster-version") }}
{{- fail "eduide-cluster is not installed on this cluster. Run the Bootstrap cluster workflow first, or set skipPreflight=true if you know better." }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
  Refuse to install with the chart's placeholder Keycloak values.

  The oauth2-proxy ConfigMaps render unconditionally - the operator mounts them
  into every session pod by literal name, so they are not gated on
  keycloak.enable. With the defaults left in place that means a live oauth2
  proxy pointed at `https://keycloak.url/auth/realms/TheiaCloud`, a host that
  does not exist. Sessions fail at the proxy rather than starting without
  authentication, which is the worst of both outcomes and gives no clue why.

  An installation that genuinely has no identity provider yet sets
  keycloak.allowUnauthenticated: true and says so out loud.
*/}}
{{- define "eduide.preflightKeycloak" -}}
{{- $kc := .Values.keycloak -}}
{{- /*
All three, not any one. A realm legitimately called TheiaCloud or a client
legitimately called theia-cloud is a natural choice - the chart suggests both -
so failing on a single match rejects valid configurations.

Only checked when Keycloak is enabled: `keycloak.enable: false` is already an
explicit statement that there is no identity provider.
*/}}
{{- $placeholder := and (eq ($kc.authUrl | toString) "https://keycloak.url/auth/")
                        (eq ($kc.realm | toString) "TheiaCloud")
                        (eq ($kc.clientId | toString) "theia-cloud") -}}
{{- if and $kc.enable $placeholder (not $kc.allowUnauthenticated) }}
{{- fail (printf "keycloak is left at the chart's placeholder values (authUrl=%s realm=%s clientId=%s). Configure them, or set keycloak.allowUnauthenticated=true to install without a working identity provider." $kc.authUrl $kc.realm $kc.clientId) }}
{{- end }}
{{- end -}}
