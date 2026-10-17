{{- define "service.name" -}}
{{- if not (regexMatch "^[a-z][a-z0-9-]{0,40}$" .Release.Name) }}{{ fail "имя релиза: [a-z][a-z0-9-]*" }}{{ end -}}
{{ .Release.Name }}
{{- end }}

{{- define "service.labels" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
app.kubernetes.io/part-of: AIIP
{{- end }}

{{- define "service.selector" -}}
app.kubernetes.io/name: {{ include "service.name" . }}
{{- end }}

{{- define "service.hook" -}}
helm.sh/hook: pre-install,pre-upgrade
helm.sh/hook-weight: {{ . | quote }}
{{- end }}
