# Disk names end up in partition labels (disk-<name>-<partition>), never rename them once installed.
{
  homelab.storage = {
    disks = {
      root = "mmc-A3A551_0xf23d65d1"; # 32GB eMMC module
      nvme1 = "nvme-eui.002538a741b44aaa"; # 256GB PM9C1a
      usb1 = "ata-BadApple_MZ-KPV_AY2026W38SN0037"; # 236GB, SM2246EN bridge UMI20190804E
      usb2 = "ata-BadApple_MZ-KPV_AY2026W38SN0035"; # 236GB, SM2246EN bridge UMI20190804F
    };

    # ESP (from 16M, U-Boot sits before it) + btrfs root.
    boot.disks = [ "root" ];

    # Not durable, one disk. G-code uploads only, klipper's config and calibration stay on the
    # eMMC. Without it the board boots and prints fine, there are just no uploaded files.
    btrfs.nvme1.subvolumes."@gcodes" = {
      mountpoint = "/var/lib/moonraker/gcodes";
      mountOptions = [ "nofail" ];
    };

    pools = {
      # Durable for one disk lost. USB, so the board still boots without it.
      "usb-zfs-mirror2" = {
        mode = "mirror";
        members = [ "usb1" "usb2" ];
        rootFsOptions.compression = "zstd";
        datasets.bulk = {
          mountpoint = "/mnt/bulk";
          mountOptions = [ "nofail" ];
          options.recordsize = "1M";
        };
      };
    };
  };

  # 4GB board, ZFS would take up to half for ARC. Leaves ~3GB for klipper, moonraker and nginx.
  homelab.zfs.arcMax = 1024 * 1024 * 1024;
}
