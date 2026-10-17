set -eu
case "$SERVICE" in
	"$POSTGRES_USER"|"$POSTGRES_DB"|postgres|template0|template1) echo "postgres: $SERVICE — служебное имя, не трогаю"; exit 1 ;;
esac
psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v name="$SERVICE" -v password="$PASSWORD" -v maindb="$POSTGRES_DB" <<'SQL'
REVOKE CONNECT ON DATABASE :"maindb" FROM PUBLIC;
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;
REVOKE CONNECT ON DATABASE template1 FROM PUBLIC;
SELECT format('CREATE ROLE %I LOGIN', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'name') \gexec
ALTER ROLE :"name" WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'password';
SELECT format('CREATE DATABASE %I OWNER %I', :'name', :'name')
 WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'name') \gexec
REVOKE ALL ON DATABASE :"name" FROM PUBLIC;
SQL
echo "postgres: $SERVICE готов"
