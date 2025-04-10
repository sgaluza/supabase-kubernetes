{{/*
Expand the name of the chart.
*/}}
{{- define "supabase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "supabase.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "supabase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "supabase.labels" -}}
helm.sh/chart: {{ include "supabase.chart" . }}
{{ include "supabase.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "supabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "supabase.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "supabase.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Generic service templates
*/}}
{{- define "supabase.service.name" -}}
{{- $service := index . 0 -}}
{{- $component := index . 1 -}}
{{- $defaultName := $component -}}
{{- $valuesKey := printf "%s.nameOverride" $component -}}
{{- $nameOverride := index $service.Values $component "nameOverride" -}}
{{- default $defaultName $nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "supabase.service.fullname" -}}
{{- $service := index . 0 -}}
{{- $component := index . 1 -}}
{{- $fullnameOverrideKey := printf "%s.fullnameOverride" $component -}}
{{- $fullnameOverride := index $service.Values $component "fullnameOverride" -}}
{{- if $fullnameOverride -}}
{{- $fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $nameKey := printf "%s.nameOverride" $component -}}
{{- $defaultName := $component -}}
{{- $nameOverride := index $service.Values $component "nameOverride" -}}
{{- $name := default $defaultName $nameOverride -}}
{{- if contains $name $service.Release.Name -}}
{{- $service.Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" $service.Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "supabase.service.selectorLabels" -}}
{{- $service := index . 0 -}}
{{- $component := index . 1 -}}
app.kubernetes.io/name: {{ include "supabase.service.name" (list $service $component) }}
app.kubernetes.io/instance: {{ $service.Release.Name }}
{{- end -}}

{{- define "supabase.service.serviceAccountName" -}}
{{- $service := index . 0 -}}
{{- $component := index . 1 -}}
{{- $createKey := printf "%s.serviceAccount.create" $component -}}
{{- $nameKey := printf "%s.serviceAccount.name" $component -}}
{{- $createValue := index $service.Values $component "serviceAccount" "create" -}}
{{- $nameValue := index $service.Values $component "serviceAccount" "name" -}}
{{- if $createValue -}}
{{- default (include "supabase.service.fullname" (list $service $component)) $nameValue -}}
{{- else -}}
{{- default "default" $nameValue -}}
{{- end -}}
{{- end -}}


{{/*
Secret templates
*/}}
{{- define "supabase.secret.jwt" -}}
{{- default (printf "%s-jwt" (include "supabase.fullname" .)) .Values.secret.jwt.secretRef }}
{{- end }}

{{- define "supabase.secret.db" -}}
{{- default (printf "%s-db" (include "supabase.fullname" .)) .Values.secret.db.secretRef }}
{{- end }}

{{- define "supabase.secret.analytics" -}}
{{- default (printf "%s-analytics" (include "supabase.fullname" .)) .Values.secret.analytics.secretRef }}
{{- end }}

{{- define "supabase.secret.smtp" -}}
{{- default (printf "%s-smtp" (include "supabase.fullname" .)) .Values.secret.smtp.secretRef }}
{{- end }}

{{- define "supabase.secret.dashboard" -}}
{{- default (printf "%s-dashboard" (include "supabase.fullname" .)) .Values.secret.dashboard.secretRef }}
{{- end }}
{{- define "supabase.secret.s3" -}}
{{- default (printf "%s-s3" (include "supabase.fullname" .)) .Values.secret.s3.secretRef }}
{{- end }}

{{- define "supabase.secret.s3.isValid" -}}
{{- if or .Values.secret.s3.secretRef (and .Values.secret.s3.keyId .Values.secret.s3.accessKey) -}}
true
{{- else -}}
false
{{- end -}}
{{- end -}}
