set -eu
export REDISCLI_AUTH="$DFLY_requirepass"
redis-cli --scan --pattern "$SERVICE:*" | xargs -r redis-cli DEL >/dev/null
echo "кэш: ключи $SERVICE:* удалены"
