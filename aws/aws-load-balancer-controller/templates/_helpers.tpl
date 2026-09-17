{{/* vim: set filetype=mustache: */}}
{{/*
Expand the name used for the TargetGroupBinding resources rendered by this
wrapper chart. Deliberately NOT prefixed "aws-load-balancer-controller" -
that name is already used by the aliased upstream chart's own helpers, and
Helm's named-template namespace is global across a parent chart and its
subcharts, so reusing it here would collide.
*/}}
{{- define "target-group-binding.name" }}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "target-group-binding.chart" }}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "target-group-binding.labels" }}
helm.sh/chart: {{ include "target-group-binding.chart" . }}
{{- include "target-group-binding.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "target-group-binding.selectorLabels" }}
app.kubernetes.io/name: {{ include "target-group-binding.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
