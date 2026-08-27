{{/*
Expand the name of the chart.
*/}}
{{- define "template.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "template.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used in the chart label.
*/}}
{{- define "template.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "template.labels" -}}
helm.sh/chart: {{ include "template.chart" . }}
{{ include "template.selectorLabels" . }}
app.kubernetes.io/version: {{ include "template.appVersionCurrent" . | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — stable across ArgoCD release naming (aligns with practice_RKE2).
*/}}
{{- define "template.selectorLabels" -}}
app.kubernetes.io/name: {{ include "template.name" . }}
app.kubernetes.io/instance: {{ .Values.nameOverride | default .Release.Name }}
{{- end }}

{{/*
Image repository / tag for this release (values come from merged app/*.yaml).
*/}}
{{- define "template.imageRepositoryCurrent" -}}
{{- $svcName := .Values.currentService | default "" -}}
{{- $svc := (index .Values $svcName) | default dict -}}
{{- $i := $svc.image | default dict -}}
{{- $i.repository | default .Values.image.repository -}}
{{- end }}

{{- define "template.imageTagCurrent" -}}
{{- $svcName := .Values.currentService | default "" -}}
{{- $svc := (index .Values $svcName) | default dict -}}
{{- $i := $svc.image | default dict -}}
{{- $i.tag | default .Values.image.tag | default .Chart.AppVersion -}}
{{- end }}

{{- define "template.appVersionCurrent" -}}
{{- $svcName := .Values.currentService | default "" -}}
{{- $svc := (index .Values $svcName) | default dict -}}
{{- $i := $svc.image | default dict -}}
{{- $i.tag | default .Values.image.tag | default .Chart.AppVersion -}}
{{- end }}

{{/*
Root key in Values for ESO secret blocks (product-db -> product, notification-db -> noti).
*/}}
{{- define "template.esoRootName" -}}
{{- $cs := .Values.currentService | default "" -}}
{{- if eq $cs "notification-db" -}}
noti
{{- else if hasSuffix "-db" $cs -}}
{{- trimSuffix "-db" $cs -}}
{{- else -}}
{{- $cs -}}
{{- end -}}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "template.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "template.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Pod template (metadata + spec) shared by Deployment, Rollout, and StatefulSet.
*/}}
{{- define "template.workloadPodSpec" -}}
{{- $cs := .Values.currentService | default "" }}
{{- $root := include "template.esoRootName" . }}
{{- $rootCfg := dict }}
{{- if $root }}
{{- $rootCfg = index .Values $root | default dict }}
{{- end }}
{{- $isDatabasePod := hasSuffix "-db" $cs }}
{{- $hasDbSecret := false }}
{{- $secretName := "" }}
{{- if and (not $isDatabasePod) $rootCfg (hasKey $rootCfg "secrets") (hasKey $rootCfg.secrets "target") (hasKey $rootCfg.secrets.target "name") }}
{{- $hasDbSecret = true }}
{{- $secretName = $rootCfg.secrets.target.name }}
{{- end }}
{{- $isDbBackedService := or (eq $cs "product") (eq $cs "inventory") (eq $cs "order") (eq $cs "payment") (eq $cs "noti") }}
{{- $dbServiceName := printf "%s-db" $cs }}
{{- if eq $cs "noti" }}
{{- $dbServiceName = "notification-db" }}
{{- end }}
{{- $dbNamespace := printf "databases-%s" (default "dev" .Values.env) }}
{{- $cur := $cs }}
{{- $svcForCfg := dict }}
{{- if $cur }}
{{- $svcForCfg = index .Values $cur | default dict }}
{{- end }}
{{- $cfgFiles := ($svcForCfg.configs | default dict).files | default list }}
{{- $hasCfgFiles := gt (len $cfgFiles) 0 }}
{{- $filesMount := ($svcForCfg.configs | default dict).filesMountPath | default "/config/files" }}
{{- $containerEnv := .Values.containerEnv | default list }}
{{- $hasContainerEnv := and (kindIs "slice" $containerEnv) (gt (len $containerEnv) 0) }}
{{- $extraEnv := .Values.extraEnv | default list }}
{{- $hasExtraEnv := and (kindIs "slice" $extraEnv) (gt (len $extraEnv) 0) }}
{{- $containerEnvFrom := .Values.containerEnvFrom | default list }}
{{- $hasContainerEnvFrom := and (kindIs "slice" $containerEnvFrom) (gt (len $containerEnvFrom) 0) -}}
metadata:
  {{- with .Values.podAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  labels:
    {{- include "template.labels" . | nindent 4 }}
    {{- with .Values.podLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
spec:
  {{- with .Values.imagePullSecrets }}
  imagePullSecrets:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  serviceAccountName: {{ include "template.serviceAccountName" . }}
  {{- with .Values.podSecurityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  containers:
    - name: {{ .Chart.Name }}
      {{- with .Values.securityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      image: "{{ include "template.imageRepositoryCurrent" . }}:{{ include "template.imageTagCurrent" . }}"
      imagePullPolicy: {{ .Values.image.pullPolicy }}
      ports:
        - name: {{ .Values.service.portName | default "http" }}
          containerPort: {{ .Values.service.containerPort | default .Values.service.port }}
          protocol: TCP
      {{- with .Values.livenessProbe }}
      livenessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.readinessProbe }}
      readinessProbe:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.resources }}
      resources:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- if or $isDbBackedService $hasContainerEnv $hasExtraEnv }}
      env:
        {{- if $isDbBackedService }}
        - name: DB_HOST
          value: "{{ $dbServiceName }}.{{ $dbNamespace }}.svc.cluster.local"
        - name: DB_PORT
          value: "5432"
        {{- end }}
        {{- if $hasContainerEnv }}
        {{- toYaml $containerEnv | nindent 8 }}
        {{- end }}
        {{- if $hasExtraEnv }}
        {{- toYaml $extraEnv | nindent 8 }}
        {{- end }}
      {{- end }}
      {{- if or $hasDbSecret $hasContainerEnvFrom }}
      envFrom:
        {{- if $hasDbSecret }}
        - secretRef:
            name: "{{ $secretName }}"
        {{- end }}
        {{- if $hasContainerEnvFrom }}
        {{- toYaml $containerEnvFrom | nindent 8 }}
        {{- end }}
      {{- end }}
      {{- if or .Values.volumeMounts (and .Values.runtimeConfig.enabled .Values.runtimeConfig.data) $hasCfgFiles }}
      volumeMounts:
        {{- with .Values.volumeMounts }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
        {{- if and .Values.runtimeConfig.enabled .Values.runtimeConfig.data }}
        - name: app-config
          mountPath: {{ .Values.runtimeConfig.mountPath | default "/app/config" }}
          readOnly: true
        {{- end }}
        {{- if $hasCfgFiles }}
        {{- range $f := $cfgFiles }}
        - name: svc-config-files
          mountPath: {{ $filesMount }}/{{ $f.name }}
          subPath: {{ $f.name }}
          readOnly: true
        {{- end }}
        {{- end }}
      {{- end }}
  {{- if or .Values.volumes (and .Values.runtimeConfig.enabled .Values.runtimeConfig.data) $hasCfgFiles }}
  volumes:
    {{- with .Values.volumes }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
    {{- if and .Values.runtimeConfig.enabled .Values.runtimeConfig.data }}
    - name: app-config
      configMap:
        name: {{ include "template.fullname" . }}-config
    {{- end }}
    {{- if $hasCfgFiles }}
    - name: svc-config-files
      configMap:
        name: {{ include "template.fullname" . }}-files
    {{- end }}
  {{- end }}
  {{- with .Values.nodeSelector }}
  nodeSelector:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.affinity }}
  affinity:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.tolerations }}
  tolerations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
