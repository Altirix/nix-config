# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
{
  homelab.storage = {
    # KVM disk without a by-id serial, check `lsblk` on the VPS.
    disks.root = "/dev/vda";

    # ESP + ext4 root, plus a BIOS boot partition since IONOS VPSes boot SeaBIOS.
    boot.disks = [ "root" ];
    boot.bios = true;
  };
}
