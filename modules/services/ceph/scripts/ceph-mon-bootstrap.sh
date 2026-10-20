# Creates this node's mon store from the shared keyrings, once.
# Env: MON_ID, FSID, MONS ("name=ip ..."), MON_KEYRING, ADMIN_KEYRING
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

# The auth database starts with both, so client.admin can log in. One import per call, a second flag replaces the first.
ceph-authtool --create-keyring "$tmp/keyring" --import-keyring "$MON_KEYRING"
ceph-authtool "$tmp/keyring" --import-keyring "$ADMIN_KEYRING"

# Build in a scratch dir so a failed mkfs never leaves a half-made store.
ceph-mon --mkfs -i "$MON_ID" --mon-data "$dir.new" --monmap "$tmp/monmap" --keyring "$tmp/keyring"
chown -R ceph:ceph "$dir.new"
rm -rf "$dir"
mv "$dir.new" "$dir"
