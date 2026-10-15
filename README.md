# NixOS Homelab

Flake for the homelab hosts.

- `modules/<category>/` hold the building blocks (system, disks, networking, services).
  Each is inert until enabled through `homelab.*` options and has no site values baked in.
  Real config files live next to them in `config/`, not inside the `.nix` files.
- `modules/default.nix` is what every host gets: the generic blocks plus the baseline config.
- `modules/{compute,storage,virtual,edge}.nix` compose the blocks for a type of host, import
  the extra blocks it needs and hold the values shared by every host of that type.
- `hosts/` say what is specific to one machine and import one of those type modules.

## Layout

```
flake.nix                  discovers hosts/<group>/<name>/default.nix, adds modules/default.nix
modules/
  default.nix              every host: disko, sops, generic blocks, packages, locale, nix, admin user
  compute.nix              the three incus + ceph hypervisors: mesh, frr, ceph, incus and their values
  compute/                 incus certificates
  storage.nix              HDD storage nodes
  virtual.nix              incus VMs
  edge.nix                 public-facing hosts: wireguard, egress NAT, port forwards, static sites, ssh
  desktop.nix              not wired up yet
  system/                  ssh (admin keys in keys/admin/*.pub), secrets, boot (grub across mirrored ESPs)
  disks/                   disko.nix (homelab.storage -> disko.devices), zfs.nix
  networking/              lan (VLAN trunk), mesh, frr
  services/                ceph/, incus/, wireguard/ (+ egress NAT, port forwards), web/ (nginx: static or proxied sites, optional ACME), minecraft/
  */config/                real config files (frr.conf, nftables tables) with @name@ placeholders
  */scripts/               bootstrap scripts, wrapped with writeShellApplication (shellcheck at build)
hosts/
  _template/               a VM, copy this for a new host
  compute/<name>/
    default.nix            imports ../../../modules/compute.nix + host-only tweaks
    storage.nix            disks, boot, ceph disks, zpools
    networking.nix         trunk interface, VLAN ids/addresses, mesh links/nodeId
    hardware-configuration.nix
    secrets.yaml
  edge/ionos-de/
    networking.nix         wireguard interface + peers, port forwards
    services.nix           web sites
  virtual/minecraft/       incus VM running homelab.minecraft, forwarded on ionos-de
```

The group directory (`compute/`, `edge/`) is only for layout, and a host with an empty
`default.nix` is a placeholder and not built.

## Add a host

```sh
cp -r hosts/_template hosts/virtual/<name>
nixos-generate-config --show-hardware-config > hosts/virtual/<name>/hardware-configuration.nix
ls -l /dev/disk/by-id/   # fill in storage.nix
```

The template is an incus VM (`modules/virtual.nix`, one ext4 disk, DHCP). `modules/compute.nix`
is only for the three hypervisors; their `storage.nix`/`networking.nix` show zfs
roots, ceph disks, VLAN trunks and the mesh.

Secrets:

```sh
ssh-keyscan <host> | ssh-to-age      # add to .sops.yaml keys, groups and a host rule
sops updatekeys secrets/common.yaml secrets/compute.yaml
sops hosts/<group>/<name>/secrets.yaml
```

Login is key-only as `admin`, every `modules/system/keys/admin/*.pub` is authorized on every
host and no host builds without one. There is no root or console password.

Install and deploy:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#<name> root@<ip>
nixos-rebuild switch --flake .#<name> --target-host admin@<name> --sudo
```

## Storage

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
