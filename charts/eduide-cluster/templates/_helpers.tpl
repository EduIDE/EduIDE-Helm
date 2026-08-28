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
