set -eu
api() { curl -s "localhost:8500/v1/$1"; }
for name in $(api catalog/services | jq -r 'keys[] | select(. != "consul")'); do
	api "health/service/$name" | jq -r '.[] | [
		.Service.Service,
		.Service.ID,
		"\(.Service.Address):\(.Service.Port)",
		([.Checks[] | select(.ServiceID != "") | .Status] | join(",") | if . == "" then "без проверки" else . end)
	] | @tsv'
done | while IFS="$(printf '\t')" read -r service id address status; do
	printf '%-12s %-20s %-32s %s\n' "$service" "$id" "$address" "$status"
done
