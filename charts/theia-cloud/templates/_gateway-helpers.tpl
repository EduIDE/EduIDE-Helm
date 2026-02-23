{{/*
Render Gateway API parentRefs for Theia HTTPRoutes.
If no explicit parentRefs are configured, default to a local Gateway by name.
*/}}
{{- define "theia-cloud.gateway.parentRefs" -}}
{{- $root := . -}}
{{- if .Values.gateway.parentRefs }}
{{- range $ref := .Values.gateway.parentRefs }}
- name: {{ tpl ($ref.name | toString) $root | quote }}
  {{- if $ref.namespace }}
  namespace: {{ tpl ($ref.namespace | toString) $root | quote }}
  {{- end }}
  {{- if $ref.sectionName }}
  sectionName: {{ tpl ($ref.sectionName | toString) $root | quote }}
  {{- end }}
{{- end }}
{{- else }}
- name: {{ tpl (.Values.gateway.name | toString) . | quote }}
{{- end }}
{{- end }}
