# Hosts

Every `hosts/<group>/<name>/default.nix` is a host. The group directory (`compute/`, `edge/`,
`virtual/`, `sbc/`, `wsl/`) is only for layout, and a host with an empty `default.nix` is a placeholder and not built.

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
wsl/wsl/                   NixOS-WSL distro on Windows (modules/wsl.nix), see Install a WSL distro below
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

Install it from the hypervisor it runs on, over vsock: the installer has no network (labs has no DHCP), so this is
the one place `<name>.incus` is the way in, afterwards it's `<name>.labs.internal` (see
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

## Install a WSL distro

`modules/wsl.nix` is a NixOS-WSL distro: Windows owns the kernel, disks and network, so there is no
hardware-configuration.nix, storage.nix or labs address, and it ships no logs. The default user is `admin`.
It's where deploys run from, with `nixos-rebuild`, `nixos-anywhere`, `sops` and `age`.

It takes the Windows host's identity, `homelab.wsl.windowsUser` names the account:

- hostname: none of its own, WSL uses the Windows computer name. The flake output is still the directory name, so
  rebuild with `#wsl`, not a bare `--flake .`.
- ssh: keys stay in Windows' OpenSSH agent, WSL's ssh asks it (`wsl.ssh-agent`, wsl2-ssh-agent). `~/.ssh` is a link
  to `C:\Users\<user>\.ssh`, so `config` and `known_hosts` are shared and each key's `.pub` picks it in the agent.
  `IdentityFile` and `Include` paths need to be `~/.ssh/...`, not `C:\...`, and a `ProxyCommand` running a `.exe`
  only works on Windows. The Windows drives mount as `admin`'s at 0755, ssh refuses a config others can write.
- git: `C:\Users\<user>\.gitconfig` is included (name, email, aliases), then checkouts are LF
  (`core.autocrlf=input`), ssh remotes go through the agent and https ones through Git for Windows' credential
  manager. Keep the checkout you deploy from in WSL (`~/nix-config`): a flake on `/mnt/c` is slow to copy into the
  store, and the drives' 0755 makes git there see every file as changed.

The agent has to be running with the keys in it, from an admin PowerShell on Windows:

```powershell
Set-Service ssh-agent -StartupType Automatic
Start-Service ssh-agent
ssh-add
```

Import the stock NixOS-WSL image ([releases](https://github.com/nix-community/NixOS-WSL/releases)) and switch it
to this flake from inside the distro. Keep `system.stateVersion` at the image's own, check it first:

```sh
grep stateVersion /etc/nixos/configuration.nix
nix-shell -p git --run 'git clone https://github.com/Altirix/nix-config ~/nix-config'
sudo nixos-rebuild boot --flake ~/nix-config#wsl
```

The stock image's user is `nixos`, changing it only takes after WSL starts the distro as root once, and the drive
mount options only after WSL shuts down. From Windows:

```powershell
wsl --shutdown
wsl -d NixOS --user root exit
wsl --shutdown
```

After that, `wsl -d NixOS` opens as `admin`, update it like any host with `sudo nixos-rebuild switch --flake ~/nix-config#wsl`.
