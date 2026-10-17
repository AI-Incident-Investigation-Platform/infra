set -eu
curl -s localhost:8500/v1/agent/services \
	| jq -r --arg name "$SERVICE" '.[] | select(.Service == $name) | .ID' \
	| while read -r id; do curl -s -X PUT "localhost:8500/v1/agent/service/deregister/$id"; done
echo "consul: $SERVICE снят с регистрации"
