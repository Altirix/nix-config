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
printer/<name>/            Klipper on ROCK 5C Lites, see printer/README.md
virtual/dls/               FastAPI-DLS, licenses vGPU guests over labs-mesh
virtual/partdb/            Part-DB, electronic parts inventory (labs only, no SSO yet)
```

The template is an incus VM (`modules/virtual.nix`, one ext4 disk, DHCP). `modules/compute.nix`
is only for the three hypervisors; their `storage.nix`/`networking.nix` show zfs
roots, ceph disks, VLAN trunks and the mesh.

## Add a VM

```sh
cp -r hosts/_template hosts/virtual/<name>
nixos-generate-config --show-hardware-config > hosts/virtual/<name>/hardware-configuration.nix
ls -l /dev/disk/by-id/   # fill in storage.nix
```

Install it from the hypervisor it runs on, over vsock (works before it has a network, see
[modules/services/incus/README.md](../modules/services/incus/README.md)):

```sh
nixos-anywhere --flake .#<name> --target-host root@incus-<name> --extra-files <dir with etc/ssh/ssh_host_ed25519_key>
```

A VM that serves something sets `homelab.labs.address`, deploy the VM, then the hypervisors so they pin it
([modules/networking/README.md](../modules/networking/README.md)).
