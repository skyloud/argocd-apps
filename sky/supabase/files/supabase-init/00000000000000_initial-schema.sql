-- Adapted from the official supabase/postgres init scripts
-- (github.com/supabase/postgres/tree/develop/migrations/db/init-scripts),
-- referenced by this project's own README ("Bootstrapping Supabase roles").
--
-- Only functional change from upstream: `supabase_admin` is CREATEd here
-- instead of ALTERed. Upstream assumes it already exists (their base image's
-- own entrypoint creates it) - CNPG always performs a genuinely fresh
-- `initdb` regardless of which Postgres image is used, so it never
-- pre-exists here.
--
-- Passwords use psql's `:'apppass'` variable substitution (never written to
-- this file or committed anywhere) - the migrations Job passes it via
-- `-v apppass=...` sourced from the CNPG "app" Secret, the same password
-- every Supabase service already authenticates with.

-- Set up realtime
-- defaults to empty publication
create publication supabase_realtime;

-- Supabase super admin
create role supabase_admin with login superuser createdb createrole replication bypassrls password :'apppass';

-- Supabase replication user
create user supabase_replication_admin with login replication;

-- Supabase etl user
create user supabase_etl_admin with login replication bypassrls;
grant pg_read_all_data to supabase_etl_admin;
grant create on database postgres to supabase_etl_admin;

-- Supabase read-only user
create role supabase_read_only_user with login bypassrls;
grant pg_read_all_data to supabase_read_only_user;

-- Extension namespacing
create schema if not exists extensions;
create extension if not exists "uuid-ossp"      with schema extensions;
create extension if not exists pgcrypto         with schema extensions;


-- Set up auth roles for the developer
create role anon                nologin noinherit;
create role authenticated       nologin noinherit; -- "logged in" user: web_user, app_user, etc
create role service_role        nologin noinherit bypassrls; -- allow developers to create JWT's that bypass their policies

create user authenticator noinherit password :'apppass';
grant anon              to authenticator;
grant authenticated     to authenticator;
grant service_role      to authenticator;
grant supabase_admin    to authenticator;

grant usage                     on schema public to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- Allow Extensions to be used in the API
grant usage                     on schema extensions to postgres, anon, authenticated, service_role;

-- Set up namespacing
alter user supabase_admin SET search_path TO public, extensions; -- don't include the "auth" schema

-- These are required so that the users receive grants whenever "supabase_admin" creates tables/function
alter default privileges for user supabase_admin in schema public grant all
    on sequences to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on tables to postgres, anon, authenticated, service_role;
alter default privileges for user supabase_admin in schema public grant all
    on functions to postgres, anon, authenticated, service_role;

-- Set short statement/query timeouts for API roles
alter role anon set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';
