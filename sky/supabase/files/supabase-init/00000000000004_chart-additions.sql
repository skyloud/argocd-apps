-- Chart-specific additions on top of the official supabase/postgres init
-- scripts (files 0000-0003 in this directory). Everything here is
-- defensive: it checks pg_available_extensions before creating anything
-- extension-dependent, so this bootstrap works unmodified whether the
-- consumer points cnpg.image at the bundled ghcr.io/skyloud/supabase-postgres
-- image (has pg_cron/pg_net/vault/pgmq) or at a vanilla
-- ghcr.io/cloudnative-pg/postgresql image (has neither) - it just skips
-- what isn't available instead of failing the whole migrations Job.

-- ============================================================
-- Realtime admin role - not part of upstream's init scripts. This chart's
-- Realtime Deployment requires it by name (DB_USER_REALTIME) for its
-- internal maintenance connection, with REPLICATION for the logical
-- replication slot on the "supabase_realtime" publication. Made superuser
-- to avoid grant-by-grant guessing for an internal-only service credential
-- never exposed to a client - see templates/deployments/realtime.yaml.
-- ============================================================
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'supabase_realtime_admin') then
    create role supabase_realtime_admin with login superuser replication password :'apppass';
  end if;
end
$$;

create schema if not exists _realtime authorization supabase_admin;

-- ============================================================
-- pg_cron - scheduled jobs. Needs "pg_cron" in shared_preload_libraries
-- (cnpg.postgresql.sharedPreloadLibraries) or CREATE EXTENSION succeeds but
-- the background worker never starts.
-- ============================================================
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    grant usage on schema cron to postgres;
  else
    raise notice 'pg_cron not available on this Postgres image - skipping (scheduled jobs will not run)';
  end if;
end
$$;

-- ============================================================
-- pg_net - async HTTP calls from triggers/functions (net.http_get/post).
-- Also needs its own entry in shared_preload_libraries.
-- ============================================================
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net with schema extensions;
    grant usage on schema net to postgres, anon, authenticated, service_role;
  else
    raise notice 'pg_net not available on this Postgres image - skipping (net.http_* calls will fail)';
  end if;
end
$$;

-- ============================================================
-- supabase_vault - encrypted secrets storage (vault.create_secret /
-- vault.decrypted_secrets), used to keep API keys out of trigger source
-- code. CASCADE pulls in pgsodium (its crypto dependency) automatically.
-- ============================================================
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'supabase_vault') then
    create extension if not exists supabase_vault cascade;
  else
    raise notice 'supabase_vault not available on this Postgres image - skipping (vault.* calls will fail)';
  end if;
end
$$;

-- ============================================================
-- pgmq - lightweight SQL message queues (used by this project's email
-- queue: enqueue_email/read_email_batch/delete_email/move_to_dlq wrappers).
-- ============================================================
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pgmq') then
    create extension if not exists pgmq;
  else
    raise notice 'pgmq not available on this Postgres image - skipping (email queue RPCs will fail)';
  end if;
end
$$;

-- ============================================================
-- pg_graphql - optional. PostgREST is configured to expose graphql_public
-- (dbSchemas includes it) whether or not this extension is present; without
-- it the schema is just empty (no GraphQL RPC endpoint).
-- ============================================================
create schema if not exists graphql_public;
grant usage on schema graphql_public to postgres, anon, authenticated, service_role;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_graphql') then
    create extension if not exists pg_graphql;
  else
    raise notice 'pg_graphql not available on this Postgres image - skipping (graphql_public stays empty)';
  end if;
end
$$;
