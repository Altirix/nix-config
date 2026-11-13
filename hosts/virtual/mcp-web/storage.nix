# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
# See hosts/compute/*/storage.nix for zfs roots, mirrors, ceph disks and pools.
{
  homelab.storage = {
    # Incus VM root disk, check `ls /dev/disk/by-id` on other hardware.
    disks.root = "scsi-0QEMU_QEMU_HARDDISK_incus_root";

    # ESP + ext4 root.
    boot.disks = [ "root" ];
  };
}
