# Node Gate

DaemonSet that polls node-local readiness checks and unblocks freshly provisioned nodes (remove Karpenter startup taints, set labels).

See `values.example.yaml` for a Pod Identity gate example.

## Gate types

**Checks:** `http`, `tcp`, `exec`

**Actions:** `removeTaint`, `setLabel`, `removeLabel`

**Failsafe:** `onTimeout: removeTaint` removes startup taints after `timeoutSeconds` to avoid wedging a NodePool.

The failsafe is fail-open, so a node can become schedulable without its check ever passing.
The two outcomes are therefore labelled differently: `setLabel` applies `value` when the
check passes and `failsafeValue` (default `failsafe`) when the failsafe fires. A label must
record the outcome, not readiness — otherwise a timed-out node is indistinguishable from a
verified one.

```bash
kubectl get nodes -l node.node-gate.io/pod-identity-ready=failsafe   # nodes that never passed
```

Any other `onTimeout` value leaves the taint in place and runs no actions.

## Deploy

Via `iac-modules/k8s/node-gate` terraform module (ArgoCD Application) or directly with Helm into `kube-system`.
