{
  homelab.storage = {
    disks = {
      boot1 = "ata-SAMSUNG_SSD_830_Series_S0VXNYAC205325"; # 64GB
      boot2 = "ata-SAMSUNG_SSD_830_Series_S0VXNYAC205402"; # 64GB
      sata1 = "ata-MZ7L3960HBLTAD3_S6M4NE0T800320"; # 960GB
      sata2 = "ata-MZ7L3960HBLTAD3_S6M4NE0T800473"; # 960GB
      nvme1 = "nvme-INTEL_SSDPEDKE040T7_PHLE729000B84P0KGN"; # 4TB P4600
      nvme2 = "nvme-INTEL_SSDPF2KX076TZO_BTAC146101BZ7P6CGN"; # 7.68TB P5510
      nvme3 = "nvme-Predator_SSD_GM7000_4TB_PSAG64431202058"; # 4TB
      usb1 = "usb-JMicron_Generic_DD56419003943-0:0"; # 512GB PM991
      usb2 = "usb-JMicron_Generic_DD56419003948-0:0"; # 512GB PM991
      slog1 = "nvme-INTEL_MEMPEK1J016GAD_PHBT837207F0016N"; # 16GB M10 Optane
    };

    # Durable for one disk lost.
    boot = {
      disks = [ "boot1" "boot2" ];
      filesystem = "zfs";
    };

    ceph.disks = [ "sata1" "sata2" ];

    pools = {
      # P5510 splits into two vdevs, P4600 + GM7000 are in either one of the vdevs
      "nvme-zfs-raid10" = {
        vdevs = [
          { mode = "mirror"; members = [ "nvme1-v1" "nvme2-v1" ]; }
          { mode = "mirror"; members = [ "nvme3-v2" "nvme2-v2" ]; }
        ];
        size = "3550G";
        rootFsOptions.dnodesize = "auto";
        datasets.vm = {
          mountpoint = "/mnt/vm";
          options.recordsize = "16K";
        };
      };

      # Durable for one disk lost. Slog is single vdev.
      "usb-zfs-mirror2-slog" = {
        mode = "mirror";
        members = [ "usb1" "usb2" ];
        log = [ "slog1" ];
        rootFsOptions = {
          compression = "zstd";
          "com.sun:auto-snapshot" = "false";
        };
        datasets.bulk = {
          mountpoint = "/mnt/bulk";
          mountOptions = [ "nofail" ];
          options = {
            recordsize = "1M";
            logbias = "throughput";
          };
        };
      };
    };
  };
}
