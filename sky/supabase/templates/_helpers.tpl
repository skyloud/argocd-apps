{{/*
Naming helpers.
*/}}
{{- define "supabase.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

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

{{- define "supabase.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "supabase.labels" -}}
helm.sh/chart: {{ include "supabase.chart" . }}
{{ include "supabase.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "supabase.selectorLabels" -}}
app.kubernetes.io/name: {{ include "supabase.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* ==========================================================================
     Postgres (CloudNativePG) naming.
     ----------------------------------------------------------------------
     Single source of truth for the CNPG Cluster name; the Service and
     Secret names CNPG generates all derive from it by convention.
     ========================================================================= */}}
{{- define "supabase.cnpgClusterName" -}}
{{- default (printf "%s-postgres" .Release.Name) .Values.cnpg.name -}}
{{- end }}

{{/* ==========================================================================
     Postgres namespace — normally the same namespace as everything else in
     this release. Set `postgres.namespace` to place the CNPG Cluster (and
     nothing else) in a different namespace; the chart then also renders
     that Namespace and a Job that mirrors the CNPG-generated app/superuser
     Secrets into this release's own namespace (Kubernetes Secrets can't be
     referenced across namespaces directly).
     ========================================================================= */}}
{{- define "supabase.postgresNamespace" -}}
{{- default .Release.Namespace .Values.postgres.namespace -}}
{{- end }}

{{/* Non-empty only when postgres.namespace is set AND differs from this release's namespace. */}}
{{- define "supabase.postgresNamespaceIsSeparate" -}}
{{- if and .Values.postgres.namespace (ne .Values.postgres.namespace .Release.Namespace) -}}1{{- end -}}
{{- end }}

{{/* Read/write (primary) Service — CNPG convention `{cluster}-rw`. Includes
     the namespace segment when Postgres lives in a separate namespace
     (K8s Service DNS resolves `<svc>.<namespace>` from any namespace). */}}
{{- define "supabase.cnpgRwService" -}}
{{- $svc := printf "%s-rw" (include "supabase.cnpgClusterName" .) -}}
{{- if include "supabase.postgresNamespaceIsSeparate" . -}}
{{- printf "%s.%s" $svc (include "supabase.postgresNamespace" .) -}}
{{- else -}}
{{- $svc -}}
{{- end -}}
{{- end }}

{{/* Read-only (any replica) Service — CNPG convention `{cluster}-ro`. */}}
{{- define "supabase.cnpgRoService" -}}
{{- $svc := printf "%s-ro" (include "supabase.cnpgClusterName" .) -}}
{{- if include "supabase.postgresNamespaceIsSeparate" . -}}
{{- printf "%s.%s" $svc (include "supabase.postgresNamespace" .) -}}
{{- else -}}
{{- $svc -}}
{{- end -}}
{{- end }}

{{/* App role Secret (basic-auth: username/password) — CNPG convention `{cluster}-app`,
     overridable via `postgres.appSecret.name` (e.g. to point at a pre-existing Secret). */}}
{{- define "supabase.cnpgAppSecretName" -}}
{{- default (printf "%s-app" (include "supabase.cnpgClusterName" .)) .Values.postgres.appSecret.name -}}
{{- end }}

{{/* Superuser Secret — CNPG convention `{cluster}-superuser`, overridable via
     `cnpg.superuserSecret.name`. Used by the migrations Job (DDL/role creation)
     and the PgDog users.toml init container. */}}
{{- define "supabase.cnpgSuperuserSecretName" -}}
{{- default (printf "%s-superuser" (include "supabase.cnpgClusterName" .)) .Values.cnpg.superuserSecret.name -}}
{{- end }}

{{/* Application database name. Fixed to Supabase's own convention (`postgres`)
     unless explicitly overridden — every official Supabase service assumes
     this database by default. */}}
{{- define "supabase.dbName" -}}
{{- default "postgres" .Values.postgres.database -}}
{{- end }}

{{/* ==========================================================================
     Generic per-service helpers.
     ----------------------------------------------------------------------
     Usage: {{ include "supabase.svcFullname" (dict "root" . "svc" "rest") }}
     ========================================================================= */}}
{{- define "supabase.svcFullname" -}}
{{- printf "%s-%s" .root.Release.Name .svc | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* ==========================================================================
     Per-service container names - single source of truth for each
     templates/deployments/<svc>.yaml container `name:` field AND Vector's
     log router (templates/deployments/vector.yaml, matches `.appname`
     against these) - ported from the official supabase-community/
     supabase-kubernetes chart's per-service `.name` helpers (each service's
     own templates/<svc>/_helpers.tpl there), which its own deployment
     templates and vector config both reference for exactly this reason.
     `<svc>.nameOverride` follows this chart's existing top-level
     nameOverride convention (see supabase.name/supabase.fullname above).
     No `supabase.db.name` override - CNPG's operator hardcodes its
     container name to "postgres" regardless of what this chart does.
     ========================================================================= */}}
{{- define "supabase.kong.name" -}}
{{- default (print .Chart.Name "-kong") .Values.kong.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.auth.name" -}}
{{- default (print .Chart.Name "-auth") .Values.auth.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.rest.name" -}}
{{- default (print .Chart.Name "-rest") .Values.rest.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.realtime.name" -}}
{{- default (print .Chart.Name "-realtime") .Values.realtime.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.storage.name" -}}
{{- default (print .Chart.Name "-storage") .Values.storage.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.functions.name" -}}
{{- default (print .Chart.Name "-functions") .Values.functions.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "supabase.db.name" -}}
postgres
{{- end -}}

{{- define "supabase.svcSelectorLabels" -}}
app.kubernetes.io/name: {{ .svc }}
app.kubernetes.io/instance: {{ .root.Release.Name }}
{{- end -}}

{{- define "supabase.svcLabels" -}}
helm.sh/chart: {{ include "supabase.chart" .root }}
{{ include "supabase.svcSelectorLabels" . }}
app.kubernetes.io/managed-by: {{ .root.Release.Service }}
{{- end -}}

{{/* ServiceAccount name for a service: `<svcFullname>` if `<svc>.serviceAccount.create`,
     else `<svc>.serviceAccount.name` (or "default"). */}}
{{- define "supabase.svcServiceAccountName" -}}
{{- $sa := index .root.Values .svc "serviceAccount" | default dict -}}
{{- if $sa.create -}}
{{- default (include "supabase.svcFullname" .) $sa.name -}}
{{- else -}}
{{- default "default" $sa.name -}}
{{- end -}}
{{- end -}}

{{/* ==========================================================================
     Generic auto-generatable Secret helper — `{ name, keys: {...} }` pattern.
     ----------------------------------------------------------------------
       {{ include "supabase.secret.name" (dict "root" . "cfg" .Values.meta.encryptionSecret "auto" "meta") }}
       {{- if include "supabase.secret.autoGenerated" (dict "cfg" .Values.meta.encryptionSecret) -}}
     ========================================================================= */}}
{{- define "supabase.secret.name" -}}
{{- $cfg := .cfg | default dict -}}
{{- if $cfg.name -}}
{{- $cfg.name -}}
{{- else -}}
{{- printf "%s-%s" .root.Release.Name .auto | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "supabase.secret.autoGenerated" -}}
{{- $cfg := .cfg | default dict -}}
{{- if $cfg.name -}}{{- else -}}1{{- end -}}
{{- end -}}

{{/* ==========================================================================
     Internal (in-cluster) URLs — used by services/Jobs that call each other
     directly instead of through Kong.
     ========================================================================= */}}
{{- define "supabase.internalKongUrl" -}}
{{- $port := default 8000 .Values.kong.service.port -}}
{{- printf "http://%s:%v" (include "supabase.svcFullname" (dict "root" . "svc" "kong")) $port -}}
{{- end -}}

{{- define "supabase.internalFunctionsUrl" -}}
{{- $port := default 9000 .Values.functions.service.port -}}
{{- printf "http://%s:%v" (include "supabase.svcFullname" (dict "root" . "svc" "functions")) $port -}}
{{- end -}}

{{- define "supabase.internalMetaUrl" -}}
{{- $port := default 8080 .Values.meta.service.port -}}
{{- printf "http://%s:%v" (include "supabase.svcFullname" (dict "root" . "svc" "meta")) $port -}}
{{- end -}}

{{- define "supabase.internalAnalyticsUrl" -}}
{{- $port := default 4000 .Values.analytics.service.port -}}
{{- printf "http://%s:%v" (include "supabase.svcFullname" (dict "root" . "svc" "analytics")) $port -}}
{{- end -}}

{{/* Secret holding Logflare (analytics) tenant tokens: `publicAccessToken` /
     `privateAccessToken`. Plain UUID v4, auto-generated by
     templates/secrets/analytics.yaml and persisted via `lookup` across
     upgrades — regenerating them would orphan Logflare's self-created
     tenant. Override with `analytics.tokensSecret.name` to supply them
     externally instead (required under ArgoCD, where `lookup` cannot
     persist anything — see that template). */}}
{{- define "supabase.analyticsTokensName" -}}
{{- default (printf "%s-analytics-tokens" .Release.Name) .Values.analytics.tokensSecret.name -}}
{{- end -}}

{{/* ==========================================================================
     JWT secret — externally supplied (bring-your-own). See values.yaml `jwt.*`.
     Fixed key names: `secret` (HMAC signing secret), `anonKey`, `serviceKey`.
     ========================================================================= */}}
{{- define "supabase.jwtSecretName" -}}
{{- required "jwt.secretName is required (pre-create a Secret with keys `secret`/`anonKey`/`serviceKey`, or point External Secrets / Sealed Secrets at it)" .Values.jwt.secretName -}}
{{- end -}}
