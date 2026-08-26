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
{{- range $name := (.Values.appDefinitions.apps | default dict | keys | sortAlpha) -}}
{{- $app := index $ctx.Values.appDefinitions.apps $name -}}
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
