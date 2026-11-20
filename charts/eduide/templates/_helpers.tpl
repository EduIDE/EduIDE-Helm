
{{/* Hosts as a dict: service, instance, webview. Derived once, used by Gateway and checks. */}}
{{- define "eduide.hosts" -}}
{{- $h := (index .Values "eduide-control-plane").config.hosts -}}
service: {{ $h.service | quote }}
instance: {{ $h.instance | quote }}
webview: {{ $h.webview | default (printf "webview.%s" $h.instance) | quote }}
{{- end }}

{{- define "eduide.gatewayName" -}}{{ (index .Values "eduide-control-plane").config.gateway.name }}{{- end }}

{{/* issuer name and kind for the cert-manager annotation of the Gateway */}}
{{- define "eduide.issuerAnnotations" -}}
{{- if .Values.issuer.create -}}
cert-manager.io/issuer: {{ .Values.issuer.name }}
cert-manager.io/issuer-kind: Issuer
cert-manager.io/issuer-group: cert-manager.io
{{- else if eq (.Values.certManager.issuerRef.kind | default "ClusterIssuer") "ClusterIssuer" -}}
cert-manager.io/cluster-issuer: {{ required "certManager.issuerRef.name or issuer.create is required" .Values.certManager.issuerRef.name }}
{{- else -}}
cert-manager.io/issuer: {{ required "certManager.issuerRef.name is required" .Values.certManager.issuerRef.name }}
cert-manager.io/issuer-kind: {{ .Values.certManager.issuerRef.kind }}
cert-manager.io/issuer-group: cert-manager.io
{{- end }}
{{- end }}
