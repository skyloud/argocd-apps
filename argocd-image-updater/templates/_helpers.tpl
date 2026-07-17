{{/*
Compute the fullname of the dependency chart aliased as `app`.

Why: When a dependency is aliased, its `.Chart.Name` becomes the alias during
rendering, so resources created by the dependency chart are typically named
`<release>-<alias>` (e.g. `argocd-image-updater-app`). Wrapper templates must
match that name when referencing the Service.

This mirrors the upstream `argocd-image-updater.fullname` helper, but reads from
`.Values.app.*` (dependency values) and uses the aliased chart name default
(`app`) when `app.nameOverride` is unset.
*/}}
{{- define "argocd-image-updater.appDependencyFullname" -}}
{{- $vals := (index .Values "app") | default dict -}}
{{- if (index $vals "fullnameOverride") -}}
{{- (index $vals "fullnameOverride") | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := (index $vals "nameOverride") | default "app" -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

