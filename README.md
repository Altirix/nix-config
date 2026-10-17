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
  virtual.nix              incus VMs: mcp servers
  edge.nix                 public-facing hosts: wireguard, egress NAT, port forwards, static sites, ssh
  printer.nix              3D printers: klipper, moonraker, mainsail, mDNS
  desktop.nix              not wired up yet
  system/                  ssh (admin keys in keys/admin/*.pub), secrets, boot (grub across mirrored ESPs)
  hardware/                rock5c.nix (U-Boot + RK3582 unlock patches from Armbian, extlinux, panthor shader mask, AIC8800 wifi)
  disks/                   disko.nix (homelab.storage -> disko.devices), zfs.nix
  networking/              lan (VLAN trunk), mesh, frr
  services/                ceph/, incus/, wireguard/ (+ egress NAT, port forwards), web/ (nginx: static or proxied sites, optional ACME), klipper/ (config/mainsail.cfg), mcp/ (servers/: presets)
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
  virtual/mcp/             incus VM serving the MCP servers
  edge/ionos-de/
    networking.nix         wireguard interface + peers, port forwards
    services.nix           web sites
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

## Printer (ROCK 5C / 5C Lite)

`hosts/printer/alluvium` and `hosts/printer/basidium` are Klipper hosts on ROCK 5C Lites (RK3582). With
`homelab.hardware.rock5c.unlocked`, U-Boot only fails what the chip's OTP marks bad, not the
vendor's fixed 2x A76 / no GPU. Usually most of the chip comes back, rarely all of it.

From Armbian with a mainline kernel (nixos-anywhere kexecs with its device tree), install to the
eMMC, building on the board, keeping Armbian's host key (the age key in `.sops.yaml`), then write
U-Boot to the eMMC's raw sectors. Erase an old loader in SPI flash first if `/dev/mtd0` exists,
the board boots SPI before eMMC:

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#alluvium --build-on remote --copy-host-keys root@<ip>
ssh admin@alluvium sudo rock5c-install-uboot /dev/mmcblk0   # the eMMC, check lsblk
```

The host key's age key, for `.sops.yaml`: `ssh-keyscan -t ed25519 <ip> | nix run nixpkgs#ssh-to-age`.

Rerun `rock5c-install-uboot` after changing `unlocked`. Check what is enabled now and stress the big cores:

```sh
nproc; ls /sys/class/devfreq
stress-ng --cpu 0 --taskset 4-7 --timeout 30m
```

A GPU with one bad core is kept with `homelab.hardware.rock5c.gpuShaderMask`: U-Boot leaves
the GPU enabled and a patched `panthor.ko` (only the module, the kernel stays 6.18) masks the
core out. The fuse bit doesn't say which `shader_present` bit it is, so probe one core at a time
with `gpuShaderMask = "0x1"` deployed (a full G610 MP4 is `0x50005`):

```sh
hexdump -C -s 0x1d -n 3 /sys/bus/nvmem/devices/rockchip-otp0/nvmem   # ip-state, byte 2 & 0x1e = bad GPU core
for m in 0x1 0x4 0x10000 0x40000; do
  modprobe -r panthor; modprobe panthor shader_mask=$m
  glmark2-es2-drm --off-screen --run-forever & sleep 300; kill $!
  dmesg | grep -i -E "panthor.*(fault|timeout|reset)"
done
```

Set `gpuShaderMask` to `0x50005` without the core that faults.

Mainsail is on `http://alluvium.local`. `printer.cfg` only seeds
`/var/lib/moonraker/config/printer.cfg` on first start, edit the live copy from Mainsail.

## MCP

`hosts/virtual/mcp` runs MCP servers on the labs bridge, each as its own `mcp-<name>` unit and
port. stdio servers sit behind mcp-proxy: streamable HTTP on `http://mcp:<port>/mcp`, SSE on
`/sse`. Nothing authenticates, so they stay off the edge and `homelab.mcp.clients` limits them to
the machines agents run on. stdio servers share one process, and with it any state, between
clients. Presets in `modules/services/mcp/servers/` only need enabling in the host, anything else
is added directly:

```nix
homelab.mcp.servers.time = {
  enable = true;
  command = lib.getExe pkgs.mcp-server-time;
  port = 8100;
};
```

Add it to a client:

```sh
claude mcp add --transport http time http://mcp:8100/mcp
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

The on-board AIC8800D80 (USB Wi-Fi 6 / BT 5.4) has no mainline driver, `homelab.hardware.rock5c.wifi`
builds Radxa's out of tree with its firmware. Check with `ip link` and `bluetoothctl list`.
