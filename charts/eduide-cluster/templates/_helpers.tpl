{{/*
A RE2 alternation of the namespaces this cluster monitors, anchored, for use in
a PromQL label matcher and in Grafana variable queries.

The dashboards used to carry a hand-written list of namespaces. It went stale
the moment the environments were renamed - the picker still offered `theia`,
`theia-staging` and `test1`, none of which exist any more, so every panel was
empty whatever you selected. Deriving it from the same list the PodMonitors use
means it cannot drift again.

An empty list yields `^$`, which matches nothing. That is deliberate: a cluster
where every environment opted out of monitoring should show an empty picker,
not silently fall back to `.*` and start graphing other tenants' namespaces.
*/}}
{{- define "eduide.monitoredNamespaceRegex" -}}
{{- $ns := .Values.monitoring.targetNamespaces | default list -}}
{{- if $ns -}}
^({{ join "|" $ns }})$
{{- else -}}
^$
{{- end -}}
{{- end -}}

{{/*
Alerting depends on monitoring, and saying so beats rendering nothing.

Both the PrometheusRule and the AlertmanagerConfig are gated on
`monitoring.enabled` as well as `monitoring.alerting.enabled`, because alerts
built on metrics nobody scrapes are decoration. Asking for alerting with
monitoring off used to render neither resource and succeed, which is the worst
outcome: the install reports fine and the feature is absent.
*/}}
{{- define "eduide.checkAlertingPrerequisites" -}}
{{- if and .Values.monitoring.alerting.enabled (not .Values.monitoring.enabled) -}}
{{- fail "monitoring.alerting.enabled is true but monitoring.enabled is false - alerting needs the PodMonitors and the metrics they collect, so this would install nothing at all" -}}
{{- end -}}
{{- end -}}

{{/*
The labels every EduIDE alert carries.

`namespace` is a routing label and is NOT the environment the alert is about.
The Prometheus Operator defaults `alertmanagerConfigMatcherStrategy` to
`OnNamespace`, which prepends `namespace = <the AlertmanagerConfig's own
namespace>` to every route it generates. Our AlertmanagerConfig lives in one
namespace, so alerts have to claim that namespace or they reach no receiver at
all.

The environment an alert is actually about is `eduide_namespace`, templated
from the series. Silences and inhibition rules must match on that one;
`namespace` is the same string on every EduIDE alert and matching it would
silence all of them at once.
*/}}
{{- define "eduide.alertRoutingLabels" -}}
namespace: {{ .Values.monitoring.alerting.namespace }}
eduide_namespace: '{{ "{{" }} $labels.namespace {{ "}}" }}'
{{- end -}}

{{/*
The receiver bodies for a set of channels.

Shared between the catch-all receiver and each environment-scoped one, so a
change to the message format cannot apply to one and not the other. Lives here
rather than in the template because a `define` may not sit inside an `if`, and
the whole AlertmanagerConfig is guarded by one.
*/}}
{{- define "eduide.receiverConfigs" }}
{{- $ctx := .ctx }}
{{- $a := $ctx.Values.monitoring.alerting }}
{{- $slack := list }}
{{- $discord := list }}
{{- range .channels }}
  {{- if eq (.type | toString) "slack" }}{{ $slack = append $slack . }}{{ else }}{{ $discord = append $discord . }}{{ end }}
{{- end }}
{{- if $slack }}
      slackConfigs:
  {{- range $slack }}
        - apiURL:
            name: {{ $a.webhookSecret.name }}
            key: {{ .secretKey }}
          {{- if .channel }}
          channel: {{ .channel | quote }}
          {{- end }}
          sendResolved: true
          username: EduIDE
          title: {{ $.title | quote }}
          text: {{ $.text | quote }}
  {{- end }}
{{- end }}
{{- if $discord }}
      discordConfigs:
  {{- range $discord }}
        - apiURL:
            name: {{ $a.webhookSecret.name }}
            key: {{ .secretKey }}
          sendResolved: true
          title: {{ $.title | quote }}
          message: {{ $.text | quote }}
  {{- end }}
{{- end }}
{{- end }}
