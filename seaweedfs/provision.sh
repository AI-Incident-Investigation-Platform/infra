set -eu
weed_shell() { echo "$1" | weed shell -master=seaweedfs:9333 2>&1; }
out=$(weed_shell "s3.bucket.create -name $SERVICE") || true
case "$out" in
	*"already exists"*) ;;
	*rror*) echo "$out"; exit 1 ;;
esac
weed_shell "s3.configure -user=$SERVICE -access_key=$SERVICE -secret_key=$PASSWORD -buckets=$SERVICE -actions=Read,Write,List,Tagging -apply" >/dev/null
echo "s3: $SERVICE готов"
