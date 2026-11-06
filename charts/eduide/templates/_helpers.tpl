{{/*
Hostname composition.

Every hostname in this chart derives from hosts.configuration. Before these
helpers existed the same two-line printf was re-derived inline in roughly a
dozen places across seven files, each wrapping every value in
`tpl (X | toString) .`. Call these instead and get a plain string back.

  theia-cloud.host.base       artemis.cit.tum.de
  theia-cloud.host.landing    theia.artemis.cit.tum.de
  theia-cloud.host.service    service.theia.artemis.cit.tum.de
  theia-cloud.host.instance   instance.theia.artemis.cit.tum.de
  theia-cloud.url.service     https://service.theia.artemis.cit.tum.de

`tpl` is kept here - and only here - because environment values legitimately
use template expressions in hostnames.
*/}}

{{- define "theia-cloud.host.base" -}}
{{- tpl (.Values.hosts.configuration.baseHost | toString) . -}}
{{- end -}}

{{- define "theia-cloud.host.landing" -}}
{{- printf "%s.%s" (tpl (.Values.hosts.configuration.landing | toString) .) (include "theia-cloud.host.base" .) -}}
{{- end -}}

{{- define "theia-cloud.host.service" -}}
{{- printf "%s.%s" (tpl (.Values.hosts.configuration.service | toString) .) (include "theia-cloud.host.base" .) -}}
{{- end -}}

{{- define "theia-cloud.host.instance" -}}
{{- printf "%s.%s" (tpl (.Values.hosts.configuration.instance | toString) .) (include "theia-cloud.host.base" .) -}}
{{- end -}}

{{- define "theia-cloud.url.service" -}}
{{- printf "%s://%s" (tpl (.Values.service.protocol | toString) .) (include "theia-cloud.host.service" .) -}}
{{- end -}}

{{/*
Wildcard instance hostnames, e.g. "*.webview." -> "*.webview.instance.<base>".

Emits a YAML list, so callers can `include ... | nindent N` directly.
*/}}
{{- define "theia-cloud.host.wildcardInstances" -}}
{{- $root := . -}}
{{- range .Values.hosts.allWildcardInstances }}
- {{ printf "%s%s" (tpl . $root) (include "theia-cloud.host.instance" $root) | quote }}
{{- end }}
{{- end -}}

{{/*
Gateway listener name for a wildcard hostname. Must be a valid Gateway API
section name, so non-alphanumerics collapse to hyphens and it is capped at 63.
*/}}
{{- define "theia-cloud.gateway.wildcardListenerName" -}}
{{- printf "https-%s" (regexReplaceAll "[^a-zA-Z0-9-]" .wildcard "-") | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The tag every IDE image carries. versions.ide wins if set, otherwise the
chart's appVersion, so `helm install --version 2.0.0` with no overrides pins
every IDE image to the tag that release published.
*/}}
{{- define "eduide.ideTag" -}}
{{- .Values.versions.ide | default .Chart.AppVersion -}}
{{- end -}}

{{/*
One app's fully qualified image. `image` is a bare repository; a value that
already carries a tag or a digest is passed through untouched so an environment
can pin one app without restructuring anything.
Call with (dict "app" $app "ctx" $).
*/}}
{{- define "eduide.appImage" -}}
{{- $app := .app -}}
{{- $ctx := .ctx -}}
{{- $repo := $app.image | toString -}}
{{- if or (contains "@sha256:" $repo) (regexMatch ".*:[^/]+$" $repo) -}}
{{- $repo -}}
{{- else -}}
{{- $tag := $app.imageTag | default (include "eduide.ideTag" $ctx) -}}
{{- if contains "/" $repo -}}
{{- if hasPrefix $ctx.Values.imageRegistry $repo -}}
{{- printf "%s:%s" $repo $tag -}}
{{- else -}}
{{- printf "%s/%s:%s" $ctx.Values.imageRegistry $repo $tag -}}
{{- end -}}
{{- else -}}
{{- printf "%s/%s:%s" $ctx.Values.imageRegistry $repo $tag -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
The apps this installation renders, as JSON: every catalog entry named in
appDefinitions.enabled, plus every key in appDefinitions.apps merged over its
catalog entry. `apps.<name>: null` removes one. Every consumer reads this one
map, so the AppDefinitions, the landing page and preloading cannot disagree.
defaults are not merged in here; each consumer falls back to them per field.
*/}}
{{- define "eduide.apps" -}}
{{- $ad := .Values.appDefinitions | default dict -}}
{{- $catalog := $ad.catalog | default dict -}}
{{- $out := dict -}}
{{- range $name := ($ad.enabled | default list) -}}
{{- if not (hasKey $catalog $name) -}}
{{- fail (printf "appDefinitions.enabled lists %q, which is not in appDefinitions.catalog. Define it under appDefinitions.apps instead" $name) -}}
{{- end -}}
{{- $_ := set $out $name (index $catalog $name | default dict) -}}
{{- end -}}
{{- range $name, $app := ($ad.apps | default dict) -}}
{{- if kindIs "invalid" $app -}}
{{- $_ := unset $out $name -}}
{{- else -}}
{{- $base := get $out $name | default (get $catalog $name) | default dict -}}
{{- $_ := set $out $name (include "eduide.deepMerge" (dict "base" $base "over" $app) | fromJson) -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
`over` merged into `base`, map by map, as JSON. Not sprig's mergeOverwrite: it
skips false and 0, so `visible: false` could not override a catalog entry.
*/}}
{{- define "eduide.deepMerge" -}}
{{- $out := deepCopy .base -}}
{{- range $k, $v := .over -}}
{{- $cur := get $out $k -}}
{{- if and (kindIs "map" $v) (kindIs "map" $cur) -}}
{{- $_ := set $out $k (include "eduide.deepMerge" (dict "base" $cur "over" $v) | fromJson) -}}
{{- else -}}
{{- $_ := set $out $k $v -}}
{{- end -}}
{{- end -}}
{{- toJson $out -}}
{{- end -}}

{{/*
Every image this installation needs on every node: one per app, one per
sidecar, plus the landing page. Derived rather than listed, so it cannot
disagree with what the installation offers.
*/}}
{{- define "eduide.preloadImages" -}}
{{- $out := list -}}
{{- if .Values.preloading.deriveFromApps -}}
{{- if .Values.landingPage.enabled -}}
{{- $out = append $out (tpl (.Values.landingPage.image | toString) .) -}}
{{- end -}}
{{- $ctx := . -}}
{{- $apps := include "eduide.apps" . | fromJson -}}
{{- range $name := ($apps | keys | sortAlpha) -}}
{{- $app := index $apps $name -}}
{{- $out = append $out (include "eduide.appImage" (dict "app" $app "ctx" $ctx)) -}}
{{- range $sc := ($app.sidecars | default list) -}}
{{- $out = append $out (include "eduide.appImage" (dict "app" $sc "ctx" $ctx)) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- range $extra := (.Values.preloading.images | default list) -}}
{{- $out = append $out $extra -}}
{{- end -}}
{{- $out | toJson -}}
{{- end -}}

{{/*
Keep serving for a few seconds after the pod is marked for deletion. Envoy only
learns that the endpoint is gone after the Pod is deleted, so without this it
keeps sending requests to a process that is already shutting down.
*/}}
{{- define "eduide.preStopDrain" -}}
preStop:
  exec:
    command: ["sleep", "10"]
{{- end }}

{{/*
Prefer putting the replicas of a Deployment on different nodes, so one node
going away does not take all of them. Soft, so a single-node cluster still
schedules every replica.
*/}}
{{- define "eduide.spreadAcrossNodes" -}}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app: {{ . }}
{{- end }}
