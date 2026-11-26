{{/*
A RE2 alternation of the namespaces whose certificates EduIDE alerts on: the
monitored environments plus the release and alerting namespaces.

cert-manager exports every Certificate on the cluster. On a shared cluster that
includes other installations' broken ones, which must not page as EduIDE alerts.
*/}}
{{- define "eduide.certificateNamespaceRegex" -}}
{{- $ns := concat (.Values.monitoring.targetNamespaces | default list) (list .Release.Namespace .Values.monitoring.alerting.namespace) | uniq | compact -}}
^({{ join "|" $ns }})$
{{- end -}}

{{/*
Alerting depends on monitoring and cert-manager scraping, and saying so beats rendering nothing.

Both the PrometheusRule and the AlertmanagerConfig are gated on
`monitoring.enabled` as well as `monitoring.alerting.enabled`, because alerts
built on metrics nobody scrapes are decoration. Rendering nothing and
succeeding would be the worst outcome: the install reports fine and the
feature is absent.
*/}}
{{- define "eduide.checkAlertingPrerequisites" -}}
{{- if and .Values.monitoring.alerting.enabled (not (and .Values.monitoring.enabled .Values.monitoring.certManager.enabled)) -}}
{{- fail "monitoring.alerting.enabled needs monitoring.enabled and monitoring.certManager.enabled, otherwise there are no metrics to alert on" -}}
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

{{/*
Fails when the cluster still has the Theia Cloud CRDs and nobody allowed removing them.
Called by theia-guard.yaml with the lookup result; split out so the test can feed it a value.
*/}}
{{- define "eduide-cluster.theiaGuard" -}}
{{- if and .found (not .allow) -}}
{{- fail "this cluster still has the CRD appdefinitions.theia.cloud, so it runs a Theia Cloud (EduIDE 2.x) installation. Upgrading eduide-cluster to 3.x removes the Theia CRDs and with them every session and workspace. Install the 3.x charts on a separate cluster or after migrating, then set allowRemovingTheiaCloud=true to proceed." -}}
{{- end -}}
{{- end -}}
