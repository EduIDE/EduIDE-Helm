{{/*
  Fail early and legibly when the cluster has not been bootstrapped.

  Without this the first symptom of a missing eduide-cluster release is the
  operator crash-looping because the AppDefinition CRD does not exist, which is
  a considerably worse way to find out.

  lookup returns nothing under `helm template`, so this only fires against a
  real cluster; rendering and diffing still work offline.
*/}}
{{- define "eduide.preflight" -}}
{{- if not .Values.skipPreflight }}
{{- if .Capabilities.APIVersions.Has "theia.cloud/v1beta11" }}
{{- /* CRDs are present, so the cluster chart is installed. */ -}}
{{- else if .Capabilities.APIVersions.Has "v1" }}
{{- $cm := lookup "v1" "ConfigMap" "eduide-system" "eduide-cluster-version" -}}
{{- if and (not $cm) (not (empty .Release.IsInstall)) }}
{{- fail "eduide-cluster is not installed on this cluster. Run the Bootstrap cluster workflow first, or set skipPreflight=true if you know better." }}
{{- end }}
{{- end }}
{{- end }}
{{- end -}}
