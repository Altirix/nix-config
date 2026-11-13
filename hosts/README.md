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
  services.nix             web sites: static ones, and the lab services it fronts (`from`): the SSO gateway
                           (auth.peacocks.me), mcp.peacocks.me (bearer tokens), logs and parts (Kanidm sign-in)
sbc/{alluvium,basidium}/   Klipper on ROCK 5C Lites, see sbc/rock5c.md
sbc/colluvium/               headless MT8195 Tomato, USB installer -> eMMC (see sbc/tomato.md)
virtual/auth/              Kanidm, SSO at auth.peacocks.me via the edge (see modules/services/sso/README.md)
virtual/dls/               FastAPI-DLS, licenses vGPU guests over labs (shared zone)
virtual/inventree/         InvenTree, parts inventory next to Part-DB to compare (inventree.peacocks.me, behind Kanidm sign-in)
virtual/logs/              VictoriaLogs, every host's journal (see modules/services/logs/README.md)
virtual/mcp/               MCP servers for agents holding tokens or data, KiCad projects too (labs, via the edge, see modules/services/mcp/README.md)
virtual/mcp-web/           MCP servers that read the open web: fetch, markitdown, playwright (see modules/services/mcp/README.md)
virtual/paperless/         Paperless-ngx, documents for people and LLMs (docs.peacocks.me, behind Kanidm sign-in)
virtual/partdb/            Part-DB, electronic parts inventory (parts.peacocks.me, behind Kanidm sign-in)
virtual/rea/               REA per project and session, dynamic analysis, no egress, reset from a snapshot (see modules/services/mcp/README.md)
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

Install it from the hypervisor it runs on, over vsock, so it needs no network (see
[modules/services/incus/README.md](../modules/services/incus/README.md)). The stock installer has no key: set a root
password from its console first (`incus console <name> --type=vga`, `sudo passwd root`). Everything comes from the
hypervisor over vsock, the installer downloads nothing; with 1 GiB, give it zram so what's copied fits:

```sh
ssh root@<name>.incus 'modprobe zram && zramctl /dev/zram0 --size 2G --algorithm zstd && mkswap /dev/zram0 && swapon /dev/zram0 && mount -o remount,size=2G /nix/.rw-store'
nixos-anywhere --flake .#<name> --target-host root@<name>.incus --no-substitute-on-destination \
  --extra-files <dir with etc/ssh/ssh_host_ed25519_key>
```

Then detach the ISO, so it boots its own disk:

```sh
incus config device remove <name> install
```
