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
- Releases: only `main`, for each chart with a changed file. The version is only the tag: `<name>-1.0.0` first (`workflow_dispatch`), then the last tag bumped by git-cliff from the chart's commits. `Chart.yaml` `version:` is never read nor edited. Never overwrite a published version.
- `next` branch: only `charts/<name>:0.0.0-<github.sha>`. No tag, no Release.
- A failed release: "Re-run failed jobs". Catch-up: `workflow_dispatch` on `main`.
