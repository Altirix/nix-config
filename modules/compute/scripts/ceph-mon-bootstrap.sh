# Creates this node's mon store from the shared keyring, once.
# Env: MON_ID, FSID, MONS ("name=ip ..."), KEYRING
dir="/var/lib/ceph/mon/ceph-$MON_ID"
[[ -e "$dir/keyring" ]] && exit 0

tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "$dir.new"' EXIT

addrs=()
for mon in $MONS; do
  name=${mon%%=*}
  ip=${mon#*=}
  addrs+=(--addv "$name" "[v2:$ip:3300,v1:$ip:6789]")
done
monmaptool --create --fsid "$FSID" "${addrs[@]}" "$tmp/monmap"

# Build in a scratch dir so a failed mkfs never leaves a half-made store.
ceph-mon --mkfs -i "$MON_ID" --mon-data "$dir.new" --monmap "$tmp/monmap" --keyring "$KEYRING"
chown -R ceph:ceph "$dir.new"
rm -rf "$dir"
mv "$dir.new" "$dir"
