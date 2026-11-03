# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
{
  homelab.storage = {
    # eMMC module, check `ls /dev/disk/by-id` on the board.
    disks.root = "mmc-CHANGEME_0x00000000";

    # ESP (from 16M, U-Boot sits before it) + btrfs root.
    boot.disks = [ "root" ];
  };
}
