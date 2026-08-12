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

This chart does **not** embed Supabase's own Postgres bootstrap SQL (schemas,
roles, extensions, grants) — that would silently drift from upstream Supabase
over time if hardcoded into the chart. Instead, the first migration in your
`migrationsCode` image must create the standard Supabase roles/schemas that
every service here assumes exist:

- Schemas: `auth`, `storage`, `graphql_public`, `extensions`, `supabase_migrations` (created automatically), `_realtime` / `realtime`.
- Roles: `anon`, `authenticated`, `service_role`, `authenticator`,
  `supabase_admin`, `supabase_auth_admin`, `supabase_storage_admin`,
  `supabase_realtime_admin` (needs `REPLICATION`) — all sharing the same
  password as the CNPG app Secret (`postgres.appSecret`), since that's the
  only password this chart wires through to PgDog/Realtime/Storage/etc.
- Extensions: at minimum `pgcrypto`, `uuid-ossp`; add `pgjwt`, `pg_graphql`,
  `pgsodium` etc. depending on which Supabase features you use.

Reference: [supabase/postgres init scripts](https://github.com/supabase/postgres/tree/develop/migrations/db/init-scripts)
publish this exact SQL — copy what you need as `<migrationsCode>/0000_supabase_init.sql`
(or similar) so it runs first (files apply in lexicographic order).

## 3. Functions & migrations images

Both are just OCI images built with `COPY` — no entrypoint, no running
process required, only the filesystem is used (mounted via ImageVolume):

```dockerfile
# supabase-functions image
FROM scratch
COPY functions/ /
# Layout: /<function-name>/index.ts for each function
```

```dockerfile
# supabase-migrations image
FROM scratch
COPY migrations/ /
# Layout: flat directory of <version>_<name>.sql files, e.g.
#   0000_supabase_init.sql
#   20240115120000_add_profiles_table.sql
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

The migrations Job tracks applied versions in
`supabase_migrations.schema_migrations` (same convention as the Supabase
CLI), so re-running `helm upgrade` with new migration files only applies the
new ones.

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

## Verifying locally

```bash
helm lint .
helm template test-release . \
  --set jwt.secretName=dummy \
  --set functionsCode.image.reference=registry.example.com/dummy/functions:latest \
  --set migrationsCode.image.reference=registry.example.com/dummy/migrations:latest
```
