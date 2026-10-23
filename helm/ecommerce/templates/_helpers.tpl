{{- define "ecommerce.fullname" -}}
{{- printf "%s-%s" .Release.Name .Chart.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "ecommerce.selectorLabels" -}}
app.kubernetes.io/name: nexvion-store
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ecommerce.labels" -}}
{{ include "ecommerce.selectorLabels" . }}
app.kubernetes.io/version: {{ .Values.image.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: ai-ecommerce-devops
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "ecommerce.secretName" -}}
{{- default (include "ecommerce.fullname" .) .Values.secret.existingSecret -}}
{{- end -}}
