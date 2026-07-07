# Node Gate

DaemonSet that polls node-local readiness checks and unblocks freshly provisioned nodes (remove Karpenter startup taints, set labels).

See `values.example.yaml` for a Pod Identity gate example.

## Gate types

**Checks:** `http`, `tcp`, `exec`

**Actions:** `removeTaint`, `setLabel`, `removeLabel`

**Failsafe:** `onTimeout: removeTaint` removes startup taints after `timeoutSeconds` to avoid wedging a NodePool.

## Deploy

Via `iac-modules/k8s/node-gate` terraform module (ArgoCD Application) or directly with Helm into `kube-system`.
