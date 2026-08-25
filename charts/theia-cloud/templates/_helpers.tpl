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
