# Hosts

Every `hosts/<group>/<name>/default.nix` is a host. The group directory (`compute/`, `edge/`, `printer/`,
`virtual/`) is only for layout, and a host with an empty `default.nix` is a placeholder and not built.

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
  services.nix             web sites
  auth.nix                 auth.peacocks.me, proxy to the auth VM
  mcp.nix                  mcp.peacocks.me, OAuth-gated proxy to the mcp VM
  logs.nix                 logs.peacocks.me, the logs VM's UI behind Kanidm sign-in
  partdb.nix               parts.peacocks.me, Part-DB behind Kanidm sign-in
printer/<name>/            Klipper on ROCK 5C Lites, see printer/README.md
virtual/auth/              Kanidm, SSO at auth.peacocks.me via the edge (see virtual/auth/README.md)
virtual/dls/               FastAPI-DLS, licenses vGPU guests over labs-mesh
virtual/logs/              VictoriaLogs, every host's journal (see virtual/logs/README.md)
virtual/mcp/               MCP servers for agents (labs, low-risk ones via the edge, see modules/services/mcp/README.md)
virtual/partdb/            Part-DB, electronic parts inventory (parts.peacocks.me, behind Kanidm sign-in)
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
`networking.nix`, deploy the hypervisors so they pin it (an instance without a pin can't send anything on labs).
Install it from the hypervisor it runs on, over vsock (works before it has a network, see
[modules/services/incus/README.md](../modules/services/incus/README.md)). The installer doesn't know its address,
give it the same one by hand first so it can fetch what it needs:

```sh
ssh root@incus-<name> 'ip addr add <address>/32 dev enp5s0 && ip route add 10.100.0.1 dev enp5s0 && ip route add default via 10.100.0.1'
nixos-anywhere --flake .#<name> --target-host root@incus-<name> --extra-files <dir with etc/ssh/ssh_host_ed25519_key>
```

A VM that serves something sets `homelab.labs.address`, deploy the VM, then the hypervisors so they pin it
([modules/networking/README.md](../modules/networking/README.md)).
