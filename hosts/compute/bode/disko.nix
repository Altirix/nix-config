{
  disko.devices = {
    disk = {

      # SATA BOOT

      # 64GB - All to zfs mirror
      disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_SSD_830_Series_S0VXNYAC205069";
        content = {
          type = "gpt";
          partitions = {
            ESP1 = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs1 = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "boot-zfs-mirror";
              };
            };
          };
        };
      };

      # 64GB - All to zfs mirror
      disk2 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_SSD_830_Series_S0VXNYAC205093";
        content = {
          type = "gpt";
          partitions = {
            ESP2 = {
              size = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot-2";
                mountOptions = [ "umask=0077" ];
              };
            };
            zfs2 = {
              size = "100%";
              content = {
                type = "zfs";
                pool = "boot-zfs-mirror";
              };
            };
          };
        };
      };

      # SATA STORAGE

      # 960GB - Ceph OSD
      disk3 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-MK000960GWUGH_192622B49820";
        content = {
          type = "gpt";
          partitions.ceph = {
            size = "100%";
            type = "8300"; # left unformatted, ceph-volume claims it
          };
        };
      };

      # 960GB - Ceph OSD
      disk4 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-MK000960GWUGH_192622B49C10";
        content = {
          type = "gpt";
          partitions.ceph = {
            size = "100%";
            type = "8300";
          };
        };
      };

      # OPTANE SLOG

      # 16GB slog for the USB drives
      disk5 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-INTEL_MEMPEK1J016GAD_PHBT83710WLT016N";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "usb-zfs-mirror2-slog";
            };
          };
        };
      };

      # NVME STORAGE

      # 3.2TB - ZFS mirror member (one of two 3.2TB drives on the Oracle Intel P4608, no TRIM in firmware, so the unpartitioned space stays as overprovisioning)
      disk6 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-7335943:ICDPC5ED2ORA6.4T_PHLE812600EP6P4BGN-1";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "2700G";
            content = {
              type = "zfs";
              pool = "nvme-zfs-mirror2";
            };
          };
        };
      };

      # 3.2TB - ZFS mirror member (second drive on the P4608, same overprovisioning)
      disk7 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-7335943:ICDPC5ED2ORA6.4T_PHLE812600EP6P4BGN-2";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "2700G";
            content = {
              type = "zfs";
              pool = "nvme-zfs-mirror2";
            };
          };
        };
      };

      # USB NVMEs

      # 512GB - All to zfs mirror
      disk8 = {
        type = "disk";
        device = "/dev/disk/by-id/usb-JMicron_Generic_DD56419003944-0:0";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "usb-zfs-mirror2-slog";
            };
          };
        };
      };

      # 512GB - All to zfs mirror
      disk9 = {
        type = "disk";
        device = "/dev/disk/by-id/usb-JMicron_Generic_DD56419003945-0:0";
        content = {
          type = "gpt";
          partitions.zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "usb-zfs-mirror2-slog";
            };
          };
        };
      };
    };

    zpool = {
      # Durable for one disk lost. 2x Samsung 830 64GB
      "boot-zfs-mirror" = {
        type = "zpool";
        mode = "mirror";
        options = {
          ashift = "12"; # reports a physical sector size is 512B, but its lying.
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          "com.sun:auto-snapshot" = "false";
          mountpoint = "none";
        };

        datasets = {
          "root" = {
            type = "zfs_fs";
            mountpoint = "/";
            options.mountpoint = "legacy";
          };
          "nix" = {
            type = "zfs_fs";
            mountpoint = "/nix";
            options = {
              mountpoint = "legacy";
              compression = "zstd";
            };
          };
          "var" = {
            type = "zfs_fs";
            mountpoint = "/var";
            options.mountpoint = "legacy";
          };
        };
      };

      # Durable for one disk lost. 2x 3.2TB P4608 namespaces
      "nvme-zfs-mirror2" = {
        type = "zpool";
        mode = "mirror";
        options = {
          ashift = "12";
          autotrim = "off"; # P4608 firmware has no TRIM
        };
        rootFsOptions = {
          compression = "lz4";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          dnodesize = "auto";
          mountpoint = "none";
        };
        datasets = {
          vm = {
            type = "zfs_fs";
            mountpoint = "/mnt/vm";
            options = {
              mountpoint = "legacy";
              recordsize = "16K";
            };
          };
        };
      };

      # Durable for one disk lost. Slog is single vdev. 2x 512GB BC711/BC511 + 16GB M10 Optane
      "usb-zfs-mirror2-slog" = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "mirror";
                members = [ "disk8" "disk9" ];
              }
            ];
            log = [
              {
                members = [ "disk5" ];
              }
            ];
          };
        };
        options = {
          ashift = "12"; # JMS583 reports a physical sector size is 512B, but its also lying.
          autotrim = "on";
        };
        rootFsOptions = {
          compression = "zstd";
          atime = "off";
          xattr = "sa";
          acltype = "posixacl";
          "com.sun:auto-snapshot" = "false";
          mountpoint = "none";
        };
        datasets = {
          bulk = {
            type = "zfs_fs";
            mountpoint = "/mnt/bulk";
            mountOptions = [ "nofail" ];
            options = {
              mountpoint = "legacy";
              recordsize = "1M";
              logbias = "throughput";
            };
          };
        };
      };
    };
  };
}