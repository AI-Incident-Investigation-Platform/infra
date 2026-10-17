set -eu
case "$SERVICE" in
	"$POSTGRES_USER"|"$POSTGRES_DB"|postgres|template0|template1) echo "postgres: $SERVICE — служебное имя, не трогаю"; exit 1 ;;
esac
psql -v ON_ERROR_STOP=1 -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v name="$SERVICE" <<'SQL'
DROP DATABASE IF EXISTS :"name" WITH (FORCE);
DROP ROLE IF EXISTS :"name";
SQL
echo "postgres: $SERVICE удалён"
