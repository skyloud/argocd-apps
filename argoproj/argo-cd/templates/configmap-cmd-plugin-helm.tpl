apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cmp-plugin-helm
  namespace: {{ .Values.namespace }}
  labels:
    {{- include "skyloudApps.labels" . | nindent 4 }}
data:
  sops-helm.yaml: |
    ---
    apiVersion: argoproj.io/v1alpha1
    kind: ConfigManagementPlugin
    metadata:
      name: argocd-sops-plugin-helm
    spec:
      # Note: this command is run _before_ any Helm templating is done, therefore the logic is to check
      # if this looks like a Helm chart
      discover:
        fileName: "Chart.yaml"
      init:
        command:
          - "/home/argocd/cmp-server/config/plugin.sh" 
          - "init"
      generate:
        command:
          - "/home/argocd/cmp-server/config/plugin.sh" 
          - "generate"
      lockRepo: true
  sops-helm.sh: |
    #!/usr/bin/bash

    set -e

    main () {

      if [[ "$1" == "init" ]] ; then
        helm repo add $HELM_REPO_NAME $HELM_REPO_URL --username $HELM_REPO_USERNAME --password $HELM_REPO_PASSWORD
        helm dependency build
        return 0
      fi

      if [[ "$1" == "generate" ]] ; then
        export HELM_CHART_PATH="$(git rev-parse --show-toplevel)/values/${ARGOCD_ENV_CLUSTER_NAME}/${ARGOCD_APP_NAMESPACE}/${ARGOCD_APP_NAME}/"
        find $HELM_CHART_PATH -type f -name '*values.enc.yaml' | xargs -I {} sops -i -d {}
        cmd="helm template ${ARGOCD_ENV_HELM_RELEASE_NAME:-$ARGOCD_APP_NAME} -n $ARGOCD_APP_NAMESPACE"
        for i_values in $(find $HELM_CHART_PATH -type f -name '*values.*yaml')
          do
            cmd+=" -f ${i_values}"
          done 
        cmd+=" ${ARGOCD_ENV_HELM_EXTRA_ARGS} ."
        ${cmd}
        return 0
      fi

      return 1
    }

    main "$@"
