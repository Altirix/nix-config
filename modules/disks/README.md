# Disks

`homelab.storage` writes disko config. Disk names, zpool members and boot slots become
partition labels (`disk-<disk>-<partition>`). **Renaming one on an installed host makes
it unbootable.**

| Member | Partition |
|---|---|
| `nvme1` | `disk-nvme1-zfs` |
| `nvme2-v1` | `disk-nvme2-v1-zfs` (disk split between vdevs) |
| boot slot N | `disk-<disk>-ESPN`, `disk-<disk>-zfsN` (`disk-<disk>-biosN` with `boot.bios`) |
| ceph disk | `disk-<disk>-ceph` |

An HDD pool with SSD metadata, L2ARC and a hot spare. `size` applies to every member of a
pool, so only split a disk between members when the pool has a fixed `size`:

```nix
homelab.storage.pools.tank = {
  vdevs = [ { mode = "raidz2"; members = [ "hdd1" "hdd2" "hdd3" "hdd4" "hdd5" "hdd6" ]; } ];
  special = [ { mode = "mirror"; members = [ "ssd1" "ssd2" ]; } ];
  cache = [ "nvme1" ];
  spare = [ "hdd7" ];
  datasets.bulk = { mountpoint = "/mnt/tank"; options.recordsize = "1M"; };
};
```

Check a change against the current disko script before deploying:

```sh
nix eval --raw .#nixosConfigurations.<name>.config.system.build.diskoScript.drvPath
```

