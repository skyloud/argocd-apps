---
paths: [".github/**", "cliff.toml"]
---

# GitHub workflows

- Actions: Marketplace "Verified creator" only, plus `orhun/git-cliff-action`. Pin the latest exact tag (`@v7.0.1`).
- No script: one command per `run:`, loops are matrices, options go in action inputs, `.github/cr.yaml` or `cliff.toml`.
- No `${{ }}` in `run:`: pass values through `env:`.
- `permissions: {}` at the top, the minimum per job. Every job sets `timeout-minutes`.
- One job per target with a job-level `if:`, no per-step `if:`.
- No commit or push from CI.
- Releases: only `main`, only on a `version:` bump in `Chart.yaml`. Never overwrite a published version.
- `next` branch: only `charts/<name>:<version>-<short sha>`. No tag, no Release.
- A failed release: "Re-run failed jobs". Catch-up: `workflow_dispatch` on `main`.
