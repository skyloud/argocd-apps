-- Matches official supabase self-host (docker/volumes/db/logs.sql): a
-- dedicated `_supabase` database holds internal-only state (currently just
-- Analytics), kept separate from the application database everything else
-- in this chart uses. `CREATE DATABASE` can't run inside a transaction or
-- take "IF NOT EXISTS" - the \gexec trick is the standard workaround.
--
-- Without this, Analytics (see templates/deployments/analytics.yaml, which
-- connects with DB_DATABASE=_supabase / DB_SCHEMA=_analytics) crashes on
-- every boot: its own Ecto migrator can create its schema_migrations
-- tracking TABLE, but never the schema itself, so it fails with "no schema
-- has been selected to create in" (Postgres error 3F000) the moment the
-- target database/schema don't already exist. Harmless to always run even
-- when analytics.enabled=false: an unused, near-empty database.
SELECT 'CREATE DATABASE _supabase' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '_supabase')\gexec

\c _supabase
CREATE SCHEMA IF NOT EXISTS _analytics AUTHORIZATION supabase_admin;
