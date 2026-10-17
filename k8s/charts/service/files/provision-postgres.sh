set -eu
psql -v ON_ERROR_STOP=1 -q -v name="$SERVICE" -v password="$PASSWORD" <<'SQL'
SELECT format('CREATE ROLE %I LOGIN', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'name') \gexec
ALTER ROLE :"name" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'password';
SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'name') \gexec
REVOKE ALL ON DATABASE :"name" FROM PUBLIC;
SQL
echo "postgres: $SERVICE готов"
