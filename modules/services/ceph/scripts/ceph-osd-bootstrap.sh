# Creates an OSD on its partition, once quorum allows.
# Env: OSD_ID, OSD_DEVICE
ceph-volume lvm list "$OSD_ID" > /dev/null 2>&1 && exit 0

ceph --connect-timeout 10 -s > /dev/null # fails until quorum, the unit retries

install -d -o ceph -g ceph /var/lib/ceph/bootstrap-osd
# The mon creates this key at mkfs, get-or-create with other caps fails with EINVAL.
ceph auth get client.bootstrap-osd -o /var/lib/ceph/bootstrap-osd/ceph.keyring

ceph-volume lvm create --bluestore --no-systemd --osd-id "$OSD_ID" --data "$OSD_DEVICE"
