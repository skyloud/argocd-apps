
CREATE SCHEMA IF NOT EXISTS storage AUTHORIZATION supabase_admin;

CREATE USER supabase_storage_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION PASSWORD :'apppass';
ALTER USER supabase_storage_admin SET search_path = "storage";
GRANT CREATE ON DATABASE postgres TO supabase_storage_admin;

-- storage-api impersonates the request's role via set_config('role', ...),
-- which is a real SET ROLE under the hood, not just a GUC - without
-- membership it fails with "permission denied to set role", which
-- storage-api also maps to the same misleading RLS message.
GRANT anon, authenticated, service_role TO supabase_storage_admin;

do $$
begin
  if exists (select from pg_namespace where nspname = 'storage') then
    grant usage on schema storage to postgres, anon, authenticated, service_role;
    alter default privileges in schema storage grant all on tables to postgres, anon, authenticated, service_role;
    alter default privileges in schema storage grant all on functions to postgres, anon, authenticated, service_role;
    alter default privileges in schema storage grant all on sequences to postgres, anon, authenticated, service_role;

    -- The two ALTER DEFAULT PRIVILEGES above only cover objects THIS
    -- session's role (postgres, superuser) creates. storage-api creates its
    -- own tables (buckets, objects, migrations, ...) as
    -- supabase_storage_admin the first time it boots, which is after this
    -- bootstrap already ran - without a "FOR ROLE" default rule targeting
    -- that specific role, anon/authenticated/service_role get zero grants
    -- on them, and every storage request fails with a misleading "new row
    -- violates row-level security policy" (storage-api maps any 42501,
    -- including plain permission-denied, to that message).
    alter default privileges for role supabase_storage_admin in schema storage grant all on tables to postgres, anon, authenticated, service_role;
    alter default privileges for role supabase_storage_admin in schema storage grant all on sequences to postgres, anon, authenticated, service_role;

    grant all on schema storage to supabase_storage_admin with grant option;
  end if;
end $$;

