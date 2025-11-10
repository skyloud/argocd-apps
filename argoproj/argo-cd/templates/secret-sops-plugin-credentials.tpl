apiVersion: v1
kind: Secret
metadata:
  name: argocd-sops-plugin-credentials
  namespace: {{ .Values.app.namespaceOverride | default "argocd" }}
  labels:
    {{- include "skyloudApps.labels" . | nindent 4 }}
type: Opaque
data:
  {{- with .Values.sops.aws }}
  AWS_DEFAULT_REGION: {{ .defaultRegion | b64enc }}
  {{- if and .accessKeyId .secretAccessKey }}
  AWS_ACCESS_KEY_ID: {{ .accessKeyId | b64enc }}
  AWS_SECRET_ACCESS_KEY: {{ .secretAccessKey | b64enc }}
  {{- end }}
  {{- end }}
