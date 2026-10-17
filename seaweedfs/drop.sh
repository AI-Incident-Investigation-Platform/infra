set -eu
weed_shell() { echo "$1" | weed shell -master=seaweedfs:9333 2>&1; }
out=$(weed_shell "s3.bucket.delete -name $SERVICE") || true
case "$out" in
	*"not found"*) ;;
	*rror*) echo "$out"; exit 1 ;;
esac
weed_shell "s3.configure -user=$SERVICE -delete -apply" >/dev/null || true
echo "s3: $SERVICE удалён"
