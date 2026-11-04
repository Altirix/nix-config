# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
# See hosts/compute/*/storage.nix for zfs roots, mirrors, ceph disks and pools.
{
  homelab.storage = {
    # Incus VM root disk, check `ls /dev/disk/by-id` on other hardware.
    disks.root = "scsi-0QEMU_QEMU_HARDDISK_incus_root";

    # ESP + ext4 root.
    boot.disks = [ "root" ];
  };

  # VictoriaLogs' data on the logs-data volume (README.md), formatted by hand. nofail so the VM still boots for
  # ssh, VictoriaLogs won't start without it.
  fileSystems."/var/lib/private/victorialogs" = {
    device = "/dev/disk/by-label/logs-data";
    fsType = "ext4";
    options = [ "nofail" "nodev" "nosuid" "noexec" ];
  };
}
