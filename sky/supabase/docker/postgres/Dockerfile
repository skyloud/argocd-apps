# renovate: datasource=docker depName=supabase/postgres
FROM supabase/postgres:17.6.1.160

# CloudNativePG's instance manager runs initdb/postgres as uid 26 (the
# Debian/PGDG "postgres" user convention baked into CNPG's own official
# images). This image ships its postgres user as uid 100 instead, which
# makes CNPG's initdb fail immediately with:
#   initdb: could not look up effective user ID 26: user does not exist
#
# Verified empirically (throwaway CNPG cluster, 2 instances, streaming
# replication) that this one-line fix is sufficient - nothing in the image
# is owned by the old uid, so no chown is needed. All target extensions
# (pg_cron, pg_net, supabase_vault, pgmq) confirmed present and installable
# after the fix. See ast/terraform staging apps/supabase for the consuming
# Cluster config (cnpg.image, sharedPreloadLibraries).
RUN usermod -u 26 postgres
