# Creates this node's mgr keyring, once quorum allows.
# Env: MGR_ID
dir="/var/lib/ceph/mgr/ceph-$MGR_ID"
[[ -e "$dir/keyring" ]] && exit 0

ceph --connect-timeout 10 -s > /dev/null # fails until quorum, the unit retries

install -d -o ceph -g ceph "$dir"
ceph auth get-or-create "mgr.$MGR_ID" \
  mon 'allow profile mgr' osd 'allow *' mds 'allow *' \
  -o "$dir/keyring.new"
chown ceph:ceph "$dir/keyring.new"
mv "$dir/keyring.new" "$dir/keyring"
