# Modules

```
default.nix              every host: disko, sops, generic blocks, packages, locale, nix, admin user
compute.nix              the three incus + ceph hypervisors: mesh, frr, ceph, incus and their values
compute/                 incus certificates
storage.nix              HDD storage nodes
virtual.nix              incus VMs
edge.nix                 public-facing hosts: wireguard, egress NAT, port forwards, static sites, ssh
printer.nix              3D printers: klipper, moonraker, mainsail, mDNS
desktop.nix, desktop/    not wired up yet
system/                  ssh (admin keys in keys/admin/*.pub), console (opt-in per-host admin password), secrets,
                         boot (grub across mirrored ESPs, cmdline editing locked)
hardware/                rock5c.nix (U-Boot + RK3582 unlock patches from Armbian, extlinux, panthor shader mask, AIC8800 wifi)
disks/                   disko.nix (homelab.storage -> disko.devices), zfs.nix
networking/              lan (VLAN trunk), mesh, frr, wifi (wpa_supplicant, SSID/PSK from sops),
                         labs (an incus VM's address on VLAN 100, pinned by the hypervisors), labs-mesh (its static address on the overlay)
services/                ceph/, incus/ (+ unattended Windows VMs), wireguard/ (+ egress NAT, port forwards),
                         web/ (nginx: static or proxied sites, optional ACME), klipper/ (config/mainsail.cfg),
                         vgpu/ (NVIDIA vGPU: host.nix on compute, guest.nix on virtual, releases.nix pins both)
*/config/                real config files (frr.conf, nftables tables, autounattend.xml) with @name@ placeholders
*/scripts/               bootstrap scripts, wrapped with writeShellApplication (shellcheck at build), and the
                         PowerShell that runs inside Windows VMs
```

Details: [networking/README.md](networking/README.md), [services/incus/README.md](services/incus/README.md),
[disks/README.md](disks/README.md).
