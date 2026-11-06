# Hosts

Every `hosts/<group>/<name>/default.nix` is a host. The group directory (`compute/`, `edge/`,
`virtual/`, `sbc/`) is only for layout, and a host with an empty `default.nix` is a placeholder and not built.

```
_template/                 a VM, copy this for a new host
compute/<name>/            the three incus + ceph hypervisors
  default.nix              imports ../../../modules/compute.nix + host-only tweaks
  storage.nix              disks, boot, ceph disks, zpools
  networking.nix           trunk interface, VLAN ids/addresses, mesh links/nodeId
  hardware-configuration.nix
  secrets.yaml
edge/ionos-de/             public-facing VPS
  networking.nix           wireguard interface + peers, port forwards
  services.nix             web sites: static ones, and the lab services it fronts (`from`): mcp.peacocks.me
                           (bearer tokens)
sbc/{alluvium,basidium}/   Klipper on ROCK 5C Lites, see sbc/rock5c.md
sbc/colluvium/               headless MT8195 Tomato, USB installer -> eMMC (see sbc/tomato.md)
virtual/dls/               FastAPI-DLS, licenses vGPU guests over labs (shared zone)
virtual/logs/              VictoriaLogs, every host's journal (see modules/services/logs/README.md)
virtual/mcp/               MCP servers for agents (labs, low-risk ones via the edge, see modules/services/mcp/README.md)
virtual/partdb/            Part-DB, electronic parts inventory (labs only, no SSO yet)
virtual/rea-dynamic/       REA per project and session, dynamic analysis, no egress, reset from a snapshot (see modules/services/mcp/README.md)
```

The template is an incus VM (`modules/virtual.nix`, one ext4 disk, a pinned labs address). `modules/compute.nix`
is only for the three hypervisors; their `storage.nix`/`networking.nix` show zfs
roots, ceph disks, VLAN trunks and the mesh.

## Add a VM

```sh
cp -r hosts/_template hosts/virtual/<name>
nixos-generate-config --show-hardware-config > hosts/virtual/<name>/hardware-configuration.nix
ls -l /dev/disk/by-id/   # fill in storage.nix
```

Pick its address in a zone ([modules/networking/README.md](../modules/networking/README.md)) and set it in
`networking.nix`, then deploy the hypervisors. They make its pin profile; an instance without a pin can't send
anything on labs. They only add pins to instances that already exist, so create it with the profile, booting the
installer ISO (import it once, under its own name per build):

```sh
incus storage volume import ceph <installer>.iso <installer> --type=iso
incus init <name> --empty --vm -p default -p <name>
incus config device add <name> install disk pool=ceph source=<installer> boot.priority=10
incus start <name>
```

Install it from the hypervisor it runs on, over vsock (works before it has a network, see
[modules/services/incus/README.md](../modules/services/incus/README.md)). The installer doesn't know its address,
give it the same one by hand first so it can fetch what it needs:

```sh
ssh root@incus-<name> 'ip addr add <address>/32 dev enp5s0 && ip route add 10.100.0.1 dev enp5s0 && ip route add default via 10.100.0.1'
nixos-anywhere --flake .#<name> --target-host root@incus-<name> --extra-files <dir with etc/ssh/ssh_host_ed25519_key>
```

Then detach the ISO, so it boots its own disk:

```sh
incus config device remove <name> install
```
