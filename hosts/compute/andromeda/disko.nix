{
  disko.devices = {
    disk = {

      # SATA BOOT

      # 64GB - All to zfs mirror
      disk1 = {
        type = "disk";
        device = "/dev/disk/by-id/ata-SAMSUNG_SSD_830_Series_S0VXNYAC205325";
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
        device = "/dev/disk/by-id/ata-SAMSUNG_SSD_830_Series_S0VXNYAC205402";
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
        device = "/dev/disk/by-id/ata-MZ7L3960HBLTAD3_S6M4NE0T800320";
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
        device = "/dev/disk/by-id/ata-MZ7L3960HBLTAD3_S6M4NE0T800473";
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
        device = "/dev/disk/by-id/nvme-INTEL_MEMPEK1J016GAD_PHBT837207F0016N";
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

      # 4TB - ZFS Raid10 VDev 1
      disk6 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-INTEL_SSDPEDKE040T7_PHLE729000B84P0KGN";
        content = {
          type = "gpt";
          partitions = {
            zfs-v1 = {
              size = "3550G";
              content = {
                type = "zfs";
                pool = "nvme-zfs-raid10";
              };
            };
          };
        };
      };

      # 7.68TB - ZFS Raid10 VDev 1 and VDev 2
      disk7 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-INTEL_SSDPF2KX076TZO_BTAC146101BZ7P6CGN";
        content = {
          type = "gpt";
          partitions = {
            zfs-v1 = {
              size = "3550G";
              content = {
                type = "zfs";
                pool = "nvme-zfs-raid10";
              };
            };
            zfs-v2 = {
              size = "3550G";
              content = {
                type = "zfs";
                pool = "nvme-zfs-raid10";
              };
            };
          };
        };
      };

      # 4TB - ZFS Raid10 VDev 2
      disk8 = {
        type = "disk";
        device = "/dev/disk/by-id/nvme-Predator_SSD_GM7000_4TB_PSAG64431202058";
        content = {
          type = "gpt";
          partitions = {
            zfs-v2 = {
              size = "3550G";
              content = {
                type = "zfs";
                pool = "nvme-zfs-raid10";
              };
            };
          };
        };
      };

      # USB NVMEs

      # 512GB - All to zfs mirror
      disk9 = {
        type = "disk";
        device = "/dev/disk/by-id/usb-JMicron_Generic_DD56419003943-0:0";
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
      disk10 = {
        type = "disk";
        device = "/dev/disk/by-id/usb-JMicron_Generic_DD56419003948-0:0";
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

      # P5510 splits into two vdevs, P4600 + GM7000 are in either one of the vdevs
      "nvme-zfs-raid10" = {
        type = "zpool";
        mode.topology = {
          type = "topology";
          vdev = [
            { mode = "mirror"; members = [ "disk6-zfs-v1" "disk7-zfs-v1" ]; }
            { mode = "mirror"; members = [ "disk8-zfs-v2" "disk7-zfs-v2" ]; }
          ];
        };
        options = {
          ashift = "12";
          autotrim = "on";
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

      # Durable for one disk lost. Slog is single vdev. 2x 512GB PM991 + 16GB M10 Optane
      "usb-zfs-mirror2-slog" = {
        type = "zpool";
        mode = {
          topology = {
            type = "topology";
            vdev = [
              {
                mode = "mirror";
                members = [ "disk9" "disk10" ];
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