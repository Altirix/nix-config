# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
# See hosts/compute/*/storage.nix for zfs roots, mirrors, ceph disks and pools.
{
  homelab.storage = {
    # Incus VM root disk, check `ls /dev/disk/by-id` on other hardware.
    disks.root = "scsi-0QEMU_QEMU_HARDDISK_incus_root";

    # ESP + ext4 root.
    boot.disks = [ "root" ];
  };

  # Samples, what projects share and their state (DynamicUser keeps it in /var/lib/private) on the rea-data
  # volume, which restoring the VM's snapshot leaves alone. Formatted by hand (modules/services/mcp/README.md),
  # REA and nginx won't start without it, nofail so the VM still boots for ssh.
  fileSystems."/srv/rea" = {
    device = "/dev/disk/by-label/rea-data";
    fsType = "ext4";
    options = [ "nofail" "nodev" "nosuid" ];
  };
  fileSystems."/var/lib/private" = {
    device = "/srv/rea/private";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/srv/rea" ];
  };
  fileSystems."/var/lib/rea-samples" = {
    device = "/srv/rea/samples";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/srv/rea" ];
  };
  fileSystems."/var/lib/rea-shared" = {
    device = "/srv/rea/shared";
    fsType = "none";
    options = [ "bind" "nofail" ];
    depends = [ "/srv/rea" ];
  };
}
