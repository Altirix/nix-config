{
  homelab.storage = {
    disks = {
      boot1 = "ata-SAMSUNG_SSD_830_Series_S0VXNYAC205069"; # 64GB
      boot2 = "ata-SAMSUNG_SSD_830_Series_S0VXNYAC205093"; # 64GB
      sata1 = "ata-MK000960GWUGH_192622B49820"; # 960GB
      sata2 = "ata-MK000960GWUGH_192622B49C10"; # 960GB
      nvme1 = "nvme-7335943:ICDPC5ED2ORA6.4T_PHLE812600EP6P4BGN-1"; # 3.2TB P4608 namespace 1
      nvme2 = "nvme-7335943:ICDPC5ED2ORA6.4T_PHLE812600EP6P4BGN-2"; # 3.2TB P4608 namespace 2
      usb1 = "usb-JMicron_Generic_DD56419003944-0:0"; # 512GB BC711/BC511
      usb2 = "usb-JMicron_Generic_DD56419003945-0:0"; # 512GB BC711/BC511
      slog1 = "nvme-INTEL_MEMPEK1J016GAD_PHBT83710WLT016N"; # 16GB M10 Optane
    };

    # Durable for one disk lost.
    boot = {
      disks = [ "boot1" "boot2" ];
      filesystem = "zfs";
    };

    ceph.disks = [ "sata1" "sata2" ];

    pools = {
      # Durable for one disk lost. Oracle Intel P4608, no TRIM in firmware,
      # so the unpartitioned space stays as overprovisioning.
      "nvme-zfs-mirror2" = {
        mode = "mirror";
        members = [ "nvme1" "nvme2" ];
        size = "2700G";
        options.autotrim = "off";
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

  # Incus takes over these datasets.
  homelab.incus.members.storagePools = {
    nvme.source = "nvme-zfs-mirror2/vm";
    bulk.source = "usb-zfs-mirror2-slog/bulk";
  };
}
