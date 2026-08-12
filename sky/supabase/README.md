# supabase

Generic, self-contained Helm chart for self-hosting [Supabase](https://supabase.com)
on Kubernetes. Not tied to any particular application — deploys the standard
Supabase stack behind PgDog and CloudNativePG, and lets you plug in your own
Edge Functions code and SQL migrations as OCI images.

## What this deploys

| Component | Image (default) | Role |
|---|---|---|
| Postgres | `ghcr.io/cloudnative-pg/postgresql` (via CNPG `Cluster` CR) | 1 primary + N read replicas |
| PgDog | `ghcr.io/pgdogdev/pgdog` | Pooler + automatic read/write split |
| PostgREST (`rest`) | `postgrest/postgrest` | REST API from the Postgres schema |
| GoTrue (`auth`) | `supabase/gotrue` | Authentication |
| Realtime | `supabase/realtime` | WebSocket change feeds (logical replication) |
| Storage API (`storage`) | `supabase/storage-api` | File storage (local disk or S3-compatible) |
| postgres-meta (`meta`) | `supabase/postgres-meta` | Schema admin API (used by Studio) |
| Studio | `supabase/studio` | Admin dashboard |
| Kong | `kong` | Single HTTP entrypoint |
| imgproxy | `darthsim/imgproxy` | On-the-fly image transforms |
| Edge Functions (`functions`) | `supabase/edge-runtime` | Deno function runtime |
| Migrations | `postgres` (any image with `psql`) | Generic SQL migration runner |
| Analytics | `supabase/logflare` | Log backend for Studio's Logs Explorer |
| Vector | `timberio/vector` | Ships every other service's logs into Analytics |

Everything is toggleable via `<service>.enabled`. Analytics/Vector are off by
default (`analytics.enabled` / `vector.enabled`) — every other service works
fine without them, just with Studio's Logs Explorer pages empty.

## Prerequisites

1. **CloudNativePG operator** installed cluster-wide (CRD `postgresql.cnpg.io/v1`).
   This chart only renders a `Cluster` CR — it does not install the operator.
2. **Kubernetes ImageVolume** (KEP-4639) available on the target cluster —
   used to mount your Edge Functions code and SQL migrations as read-only OCI
   image filesystems, no PVC or custom application image needed. Check your
   Kubernetes version's feature-gate status before relying on this in
   production; it graduated through alpha/beta over recent releases.
3. Two things this chart deliberately does **not** generate for you:
   - A JWT secret (see below).
   - Your Edge Functions / migrations OCI images (see below).

## 1. JWT secret

Generate an HMAC secret plus `anon`/`service_role` JWTs signed with it, using
any standard Supabase self-host JWT generator (the official self-hosting
guide documents this). Store the result as a Secret:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: supabase-jwt
stringData:
  secret: <HMAC signing secret>
  anonKey: <JWT signed with role=anon>
  serviceKey: <JWT signed with role=service_role>
```

Point `jwt.secretName: supabase-jwt` at it. Manage it however you already
manage secrets (External Secrets, Sealed Secrets, plain `kubectl apply` —
this chart doesn't care).

## 2. Bootstrapping Supabase roles

Handled for you: `migrations.builtinInit.enabled` (default `true`) bakes the
Supabase role/schema/extension bootstrap in `files/supabase-init/` into a
chart-owned ConfigMap, and the migrations Job applies it before any of your
own migrations. It creates the schemas (`auth`, `storage`, `graphql_public`,
`extensions`, `_realtime`), the roles every service here authenticates as
(`anon`, `authenticated`, `service_role`, `authenticator`, `supabase_admin`,
`supabase_auth_admin`, `supabase_storage_admin`, and
`supabase_realtime_admin` with `REPLICATION`) all sharing the CNPG app
password, and the extensions — each one guarded by a
`pg_available_extensions` check, so the same SQL works against the bundled
`ghcr.io/skyloud/supabase-postgres` image and against a vanilla
`ghcr.io/cloudnative-pg/postgresql` one, just with fewer extensions on the
latter.

Adapted from the upstream
[supabase/postgres init scripts](https://github.com/supabase/postgres/tree/develop/migrations/db/init-scripts).
Set `migrations.builtinInit.enabled: false` to bring your own bootstrap via
`migrationsCode` instead.

### Two migration ledgers

The builtin bootstrap is tracked in `supabase_migrations.chart_bootstrap`;
**your** migrations are tracked in `supabase_migrations.schema_migrations`,
created with the exact column layout the Supabase CLI uses
(`version` / `statements` / `name`). Two reasons:

- `supabase migration list`, `db push` and `db pull` keep working against
  this database, and see exactly the migrations in your repo — no chart-owned
  rows to explain away.
- A builtin file can never shadow one of yours. Both ledgers are keyed by the
  `<version>` filename prefix, and a `supabase db dump` baseline is commonly
  numbered `00000000000000_*.sql` — the same as the first builtin file.

Installs created before this split are migrated automatically: the builtin
rows are moved out of `schema_migrations` on the next run rather than
re-applying a bootstrap that isn't idempotent.

## 3. Functions & migrations images

Both are just OCI images built with `COPY` — no entrypoint, no running
process required, only the filesystem is used (mounted via ImageVolume). Build
them from your Supabase project repo, whose `supabase/functions/` and
`supabase/migrations/` directories already have the layout the chart expects:

```dockerfile
FROM scratch
COPY supabase/functions/ /     # -> <mountPath>/<function-name>/index.ts
```

```dockerfile
FROM scratch
COPY supabase/migrations/ /    # -> <mountPath>/<version>_<name>.sql (flat)
```

Push them anywhere the cluster can pull from, then set:

```yaml
functionsCode:
  image:
    reference: registry.example.com/myorg/supabase-functions:1.0.0
migrationsCode:
  image:
    reference: registry.example.com/myorg/supabase-migrations:1.0.0
```

Three things to know about the migrations image:

- The runner reads the mount with `-maxdepth 1`, so keep the `.sql` files
  flat — subdirectories are ignored.
- Files are recorded by `<version>` (everything before the first underscore),
  so re-running only applies what's new. Editing a `.sql` file that already
  ran changes nothing on that database; add a new migration instead.
- Pin a real tag rather than `:latest` on both images. The chart mounts by
  reference, so with a moving tag "which code is running" depends on when each
  pod last pulled.

## Deploying via ArgoCD

ArgoCD does not run `helm upgrade` — it renders the chart with
`helm template` and applies the result. Two chart behaviours depend on real
Helm and silently misbehave otherwise, so **both of these are required**:

```yaml
migrations:
  # .Release.Revision is always 1 under `helm template`, so the
  # revision-suffixed Job name never changes, the completed Job is never
  # replaced, and new migrations are silently never applied. This annotates
  # the Job as an ArgoCD Sync hook (delete-before-create) instead.
  argocdHook: true

# `lookup` returns nothing under `helm template`, so any secret the chart
# auto-generates is re-randomised on every render — and `selfHeal` applies it.
# Supply them from outside instead.
realtime:
  encryptionSecret: { name: supabase-realtime-encryption }  # key: secretKeyBase
meta:
  encryptionSecret: { name: supabase-meta-encryption }      # key: cryptoKey
analytics:
  tokensSecret: { name: supabase-analytics-tokens }         # keys: publicAccessToken, privateAccessToken
```

Left unset, Realtime invalidates every session on each sync, postgres-meta
loses the key it encrypted Studio's stored credentials with, and Logflare's
tenant is orphaned.

The `k8s/supabase` Terraform module in `iac-modules` sets all four for you and
generates the three Secrets alongside the Postgres credentials it already
owns.

## Migrating an existing project off Supabase Cloud

The chart consumes a CLI-shaped project as-is (`supabase/migrations/*.sql`,
`supabase/functions/<name>/index.ts`), but four things do not travel with a
`git clone`:

1. **Load-time extensions.** `CREATE EXTENSION pg_cron` *fails* unless
   `pg_cron` is in `cnpg.postgresql.sharedPreloadLibraries`, and `pg_net`
   creates cleanly but never sends a request without it. Both are preloaded by
   default here — leave them unless you also replace `cnpg.image`.
2. **Per-function JWT verification.** Cloud reads `verify_jwt` from
   `supabase/config.toml`; nothing in the repo is read at deploy time here.
   Transcribe it into `functions.verifyJwt`, keeping in mind that a function
   *absent* from config.toml defaults to verified:

   ```yaml
   functions:
     verifyJwtDefault: true       # matches Cloud's default
     verifyJwt:
       stripe-webhook: false      # mirror each [functions.<name>] block
   ```

   This router is the only thing in front of your functions — Kong
   deliberately puts no `key-auth` on `/functions/v1` so webhook callers can
   reach it.
3. **Vault secrets.** SQL that calls an Edge Function from the database
   (`net.http_post` in a trigger or cron job) reads its URL and key out of
   `vault.decrypted_secrets`. On Cloud those rows were created through the
   dashboard or Management API, so they are *not* in your migrations and a
   self-hosted database starts without them. Enable
   `migrations.vaultBootstrap` to have the chart upsert `SUPABASE_URL`,
   `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` after migrations, plus
   any project-specific names via `vaultBootstrap.extra`.
4. **Scheduled jobs.** `cron.schedule(...)` calls made through the Cloud
   dashboard aren't in your migrations either. Add them as a new migration now
   that pg_cron works — that's the only way they'll exist here.

Function code itself needs no changes: `npm:`, `jsr:`, `https://esm.sh/...`
and `https://deno.land/...` specifiers all resolve at runtime, so the
functions pod needs egress to those registries (or a pull-through mirror). A
per-function `deno.json` is detected and used as its import map, matching
`supabase functions deploy`.

## Postgres / PgDog topology

`cnpg.instances` = 1 primary + `(instances - 1)` read replicas (default `3`
→ 1 primary + 2 replicas). PgDog inspects each transaction
(`BEGIN READ ONLY` vs `BEGIN READ WRITE`, as PostgREST sends based on
function volatility) and routes accordingly. This chart adds no
cluster-autoscaling logic itself — replica pods simply request the same
resources as any other pod, so a node autoscaler (e.g. Karpenter) provisions
capacity for them the same way it would for any other workload. Scale reads
by raising `cnpg.instances` and/or `pgdog.replicaCount`.

### Postgres in its own namespace

By default the CNPG `Cluster` lives in this release's own namespace, same as
every other resource. Set `postgres.namespace` to place it in a different
namespace instead — the chart then also renders that `Namespace` and a Job
(`templates/jobs/secret-sync.yaml`) that mirrors the CNPG-generated app/
superuser Secrets into this release's namespace under the same names, since
Kubernetes has no cross-namespace `secretKeyRef`. That Job re-runs on every
`helm upgrade` so a later credential rotation eventually propagates; it's
scoped via RBAC to read only those two specific Secrets by name in the
Postgres namespace, and to write only those same two names in this
release's namespace.

Not everything goes through PgDog — some services need a direct connection
to the primary:

| Service | Path | Why |
|---|---|---|
| PostgREST, Storage, postgres-meta | via PgDog | Stateless, safe under transaction pooling |
| GoTrue (auth) | direct to primary | Known pgx/transaction-pooling incompatibility |
| Realtime | direct to primary | Owns a logical replication slot |
| Edge Functions | direct to primary | May hold long-lived transactions |
| Migrations | direct to primary (superuser) | DDL / role creation |

## Known limitations

- **Storage local-disk backend** (`storage.s3.enabled: false`, the default)
  uses a single RWO PVC — fine for `storage.replicaCount: 1` (the default),
  but doesn't support multiple Storage replicas unless you switch to
  `storage.s3.enabled: true` with a real S3-compatible backend.
- **Studio's Edge Functions tab** (`studio.functionsCodeVolume.enabled`) is
  off by default — it's a convenience mount so Studio can list your
  functions, not required for functions to actually run.
- Image tags in `values.yaml` are illustrative placeholders — pin them to
  tested releases (Renovate or similar) before running this in production.
- **Vector's Logflare source names are fixed** (`postgres.logs`,
  `postgREST.logs.prod`, `cloudflare.logs.prod`, etc.) — they're hardcoded in
  Studio's Logs Explorer, not this chart's convention. Don't rename them in
  `templates/deployments/vector.yaml` or Studio's log pages go back to empty.
- Vector is a DaemonSet — set `vector.tolerations` to cover every node pool
  you want logs from, or it simply won't schedule (and won't collect logs)
  there.
- **Ingress controllers impose their own limits in front of Kong**, and their
  defaults are well below what Supabase needs — ingress-nginx caps request
  bodies at 1MB, so uploads fail with a 413 regardless of
  `storage.fileSizeLimit`. The chart stays controller-agnostic and sets no
  annotations for you; see the comment on `kong.ingress.annotations`.
- **The Edge Functions router only verifies HS256 tokens.** In `jwtApiKeys`
  (asymmetric) mode, Kong translates publishable/secret keys into RS256/ES256
  JWTs for the other routes, but the functions router is only given the HMAC
  secret and rejects anything else. Set `functions.verifyJwt.<name>: false`
  and verify inside the function if you need asymmetric tokens there.
- **Autoscaling requires a metrics target.** `<svc>.autoscaling.enabled: true`
  with neither `targetCPUUtilizationPercentage` nor
  `targetMemoryUtilizationPercentage` fails template rendering rather than
  producing an HPA the API server would reject.

## Verifying locally

```bash
helm lint .
helm template test-release . \
  --set jwt.secretName=dummy \
  --set functionsCode.image.reference=registry.example.com/dummy/functions:latest \
  --set migrationsCode.image.reference=registry.example.com/dummy/migrations:latest
```
