set -eu
case "$SERVICE" in
	"$RABBITMQ_DEFAULT_USER"|guest) echo "rabbitmq: $SERVICE — служебное имя, не трогаю"; exit 1 ;;
esac
if rabbitmqctl -q list_users | cut -f1 | grep -qx "$SERVICE"; then
	rabbitmqctl -q change_password "$SERVICE" "$PASSWORD"
else
	rabbitmqctl -q add_user "$SERVICE" "$PASSWORD"
fi
rabbitmqctl -q set_permissions -p "$RABBITMQ_DEFAULT_VHOST" "$SERVICE" '.*' '.*' '.*'
echo "rabbitmq: $SERVICE готов"
