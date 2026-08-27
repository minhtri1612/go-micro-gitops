{{/*
Suffix for generated K8s Secret names by environment.
*/}}
{{- define "external-secrets.k8sSecretSuffix" -}}
{{- if eq .Values.env "dev" -}}
-dev
{{- else if eq .Values.env "staging" -}}
-staging
{{- end -}}
{{- end -}}
