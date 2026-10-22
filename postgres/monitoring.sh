set -eu
psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v password="$PASSWORD" <<'SQL'
SET client_min_messages = warning;
SELECT 'CREATE ROLE monitoring LOGIN'
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitoring') \gexec
ALTER ROLE monitoring WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE CONNECTION LIMIT 5 PASSWORD :'password';
GRANT pg_monitor TO monitoring;
GRANT CONNECT ON DATABASE postgres TO monitoring;
SQL
echo "postgres: роль monitoring готова"
