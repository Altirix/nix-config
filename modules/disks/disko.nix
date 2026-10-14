{ config, lib, ... }:

# Builds disko.devices from a short per-host description.
#
# Partition labels are disko's `disk-<disk>-<partition>` and zpool members resolve
# through them, so renaming a disk, member or boot slot makes an installed host unbootable.
let
  cfg = config.homelab.storage;
  inherit (lib) mkOption types;

  # SSDs and USB bridges here report 512B physical sectors, they are 4K.
  defaultPoolOptions = {
    ashift = "12";
    autotrim = "on";
  };

  defaultRootFsOptions = {
    compression = "lz4";
    atime = "off";
    xattr = "sa";
    acltype = "posixacl";
    mountpoint = "none";
  };

  # Legacy mounts, so systemd owns the mount ordering.
  dataset = types.submodule {
    options = {
      mountpoint = mkOption { type = types.str; };
      mountOptions = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
      };
      options = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };

  vdev = types.submodule {
    options = {
      mode = mkOption {
        type = types.str;
        default = "";
      };
      members = mkOption { type = types.listOf types.str; };
    };
  };

  pool = types.submodule {
    options = {
      # Members are a disk name (partition `zfs`) or `<disk>-<slice>` (partition `<slice>-zfs`)
      # for disks split between vdevs.
      mode = mkOption {
        type = types.str;
        default = "";
        description = "Layout over `members` when `vdevs` is empty.";
      };
      members = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      vdevs = mkOption {
        type = types.listOf vdev;
        default = [ ];
      };
      # Support vdevs, e.g. for HDD pools: special (metadata on SSD), cache (L2ARC), hot spares.
      log = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      special = mkOption {
        type = types.listOf vdev;
        default = [ ];
      };
      dedup = mkOption {
        type = types.listOf vdev;
        default = [ ];
      };
      cache = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      spare = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      size = mkOption {
        type = types.str;
        default = "100%";
        description = "Partition size for every member.";
      };
      options = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Merged over ashift 12 and autotrim on.";
      };
      rootFsOptions = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Merged over lz4, atime off, xattr sa, posixacl.";
      };
      datasets = mkOption {
        type = types.attrsOf dataset;
        default = { };
      };
    };
  };

  mkDataset = ds: {
    type = "zfs_fs";
    inherit (ds) mountpoint;
    options = { mountpoint = "legacy"; } // ds.options;
  } // lib.optionalAttrs (ds.mountOptions != null) { inherit (ds) mountOptions; };

  supportVdevs = p: p.log != [ ] || p.special != [ ] || p.dedup != [ ] || p.cache != [ ] || p.spare != [ ];

  mkPool = p: {
    type = "zpool";
    mode =
      if p.vdevs == [ ] && !supportVdevs p then p.mode
      else {
        topology = {
          type = "topology";
          vdev = map (v: { inherit (v) mode members; })
            (if p.vdevs != [ ] then p.vdevs else [ { inherit (p) mode members; } ]);
        }
        // lib.optionalAttrs (p.log != [ ]) { log = [ { members = p.log; } ]; }
        // lib.optionalAttrs (p.special != [ ]) { special = map (v: { inherit (v) mode members; }) p.special; }
        // lib.optionalAttrs (p.dedup != [ ]) { dedup = map (v: { inherit (v) mode members; }) p.dedup; }
        // lib.optionalAttrs (p.cache != [ ]) { inherit (p) cache; }
        // lib.optionalAttrs (p.spare != [ ]) { inherit (p) spare; };
      };
    options = defaultPoolOptions // p.options;
    rootFsOptions = defaultRootFsOptions // p.rootFsOptions;
    datasets = lib.mapAttrs (_: mkDataset) p.datasets;
  };

  diskOf = member: lib.findSingle (disk: member == disk || lib.hasPrefix "${disk}-" member)
    (throw "storage: zpool member ${member} matches no disk")
    (throw "storage: zpool member ${member} matches more than one disk")
    (lib.attrNames cfg.disks);

  zfsPartitions = lib.concatLists (lib.mapAttrsToList (name: p:
    map (member: rec {
      inherit member;
      disk = diskOf member;
      partition = if member == disk then "zfs" else "${lib.removePrefix "${disk}-" member}-zfs";
      value = {
        inherit (p) size;
        content = {
          type = "zfs";
          pool = name;
        };
      };
    }) (p.members ++ lib.concatMap (v: v.members) (p.vdevs ++ p.special ++ p.dedup) ++ p.log ++ p.cache ++ p.spare)) cfg.pools);

  # Slot 1 mounts /boot, slot N mounts /boot-N.
  bootSlots = lib.imap1 (i: disk: {
    inherit disk;
    index = toString i;
    mountpoint = if i == 1 then "/boot" else "/boot-${toString i}";
  }) cfg.boot.disks;

  partitionsFor = disk:
    lib.listToAttrs (lib.concatMap (slot: lib.optionals (slot.disk == disk) [
      (lib.nameValuePair "ESP${slot.index}" {
        size = cfg.boot.espSize;
        type = "EF00";
        content = {
          type = "filesystem";
          format = "vfat";
          inherit (slot) mountpoint;
          mountOptions = [ "umask=0077" ];
        };
      })
      (if cfg.boot.filesystem == "zfs" then
        lib.nameValuePair "zfs${slot.index}" {
          size = "100%";
          content = {
            type = "zfs";
            pool = cfg.boot.pool;
          };
        }
      else
        lib.nameValuePair "root${slot.index}" {
          size = "100%";
          content = {
            type = "filesystem";
            format = cfg.boot.filesystem;
            mountpoint = "/";
          };
        })
    ]) bootSlots)
    # Left unformatted, ceph-volume claims it.
    // lib.optionalAttrs (lib.elem disk cfg.ceph.disks) {
      ceph = {
        size = "100%";
        type = "8300";
      };
    }
    // lib.listToAttrs (map (p: lib.nameValuePair p.partition p.value)
      (lib.filter (p: p.disk == disk) zfsPartitions));

  usedDisks = cfg.boot.disks ++ cfg.ceph.disks ++ map (p: p.disk) zfsPartitions;
in
{
  options.homelab.storage = {
    # Name -> /dev/disk/by-id entry (or an absolute path). Names end up in partition labels, never rename them.
    disks = mkOption {
      type = types.attrsOf types.str;
      default = { };
    };

    boot = {
      disks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Each gets an ESP and the root, more than one mirrors both (zfs only).";
      };
      filesystem = mkOption {
        type = types.enum [ "ext4" "zfs" ];
        default = "ext4";
      };
      # The rest only applies to a zfs root.
      pool = mkOption {
        type = types.str;
        default = "boot-zfs-mirror";
      };
      espSize = mkOption {
        type = types.str;
        default = "1G";
      };
      options = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      rootFsOptions = mkOption {
        type = types.attrsOf types.str;
        default."com.sun:auto-snapshot" = "false";
      };
      datasets = mkOption {
        type = types.attrsOf dataset;
        default = {
          root.mountpoint = "/";
          nix = {
            mountpoint = "/nix";
            options.compression = "zstd";
          };
          var.mountpoint = "/var";
        };
      };
      espMountpoints = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        default = map (slot: slot.mountpoint) bootSlots;
      };
    };

    ceph = {
      # Order sets the OSD ids, only ever append.
      disks = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      devices = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        default = map (disk: config.disko.devices.disk.${disk}.content.partitions.ceph.device) cfg.ceph.disks;
      };
    };

    pools = mkOption {
      type = types.attrsOf pool;
      default = { };
    };
  };

  config = lib.mkIf (cfg.disks != { }) {
    assertions = [
      {
        assertion = lib.all (disk: cfg.disks ? ${disk}) (cfg.boot.disks ++ cfg.ceph.disks);
        message = "storage: boot and ceph disks must be listed in homelab.storage.disks";
      }
      {
        assertion = lib.all (disk: lib.elem disk usedDisks) (lib.attrNames cfg.disks);
        message = "storage: every disk in homelab.storage.disks must be used";
      }
      {
        assertion = cfg.boot.filesystem == "zfs" || lib.length cfg.boot.disks <= 1;
        message = "storage: only a zfs root can be mirrored across boot disks";
      }
      {
        assertion = lib.allUnique (map (p: p.member) zfsPartitions);
        message = "storage: a zpool member is listed twice";
      }
      {
        assertion = lib.all (disk: lib.count (p: p.size == "100%") (lib.attrValues (partitionsFor disk)) <= 1)
          (lib.attrNames cfg.disks);
        message = "storage: a disk split between members needs a fixed `size` on the pools using it";
      }
    ];

    disko.devices = {
      disk = lib.mapAttrs (name: id: {
        type = "disk";
        device = if lib.hasPrefix "/" id then id else "/dev/disk/by-id/${id}";
        content = {
          type = "gpt";
          partitions = partitionsFor name;
        };
      }) cfg.disks;

      zpool = lib.optionalAttrs (cfg.boot.disks != [ ] && cfg.boot.filesystem == "zfs") {
        # Members are the zfsN boot partitions, disko finds them by pool name.
        ${cfg.boot.pool} = mkPool (lib.genAttrs [ "members" "vdevs" "log" "special" "dedup" "cache" "spare" ] (_: [ ]) // {
          mode = if lib.length cfg.boot.disks > 1 then "mirror" else "";
          inherit (cfg.boot) options rootFsOptions datasets;
        });
      } // lib.mapAttrs (_: mkPool) cfg.pools;
    };
  };
}
