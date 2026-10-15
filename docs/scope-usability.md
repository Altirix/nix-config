# Usability scope: host-driven config

Goal: a host directory fully describes the machine (disks, networks, host type, extras).
Modules expose `homelab.*` options and only hardcode what never needs adjusting.

## Done

| Area | Change |
|---|---|
| Flake | Hosts discovered from `hosts/<group>/<name>/default.nix`; no `tags`, `extraModules` or hardcoded `system`; `hostId` is `mkDefault`; host `secrets.yaml` picked up automatically |
| Modules | Building blocks in `modules/{system,disks,networking,services}`, gated by `enable`, no site values in their defaults; `modules/default.nix` is what every host gets |
| Storage | `homelab.storage` builds disko from disks, boot disks (ext4 by default, zfs for mirrors), ceph disks and pools (data, log, special, dedup, cache, spare vdevs for HDD nodes); same partition labels as before |
| Boot | Grub mirror enables itself from the boot disk count, ESP paths come from storage |
| Ceph | Hypervisors only; `monitors`, `publicNetwork`/`clusterNetwork`, `address`, `osdIdBase`, `keyringFile` options set by `compute.nix`; OSDs from `homelab.storage.ceph` |
| Incus | Cluster address/members/seed, networks, pools, projects, profiles, certs are options; per-host keys in `homelab.incus.members` (no more zpool prefix matching); nftables isolation derived from the networks; rbd only with a ceph pool |
| LAN | Generic VLAN trunk (`homelab.lan.vlans.<ifname>`); VLAN ids and addressing set per host, the compute profile only marks mgmt as admin and declares labs-uplink |
| Mesh/FRR | Mesh `prefix`, `mtu`, opt-in VXLAN overlay; FRR has its own `enable`, `area`, `tag` and timers (null keeps FRR defaults) |
| ZFS | `arcMax` (unset by default), `scrubInterval`; enables itself when disko has zpools |
| Users/SSH | Admin user in `modules/default.nix`, key-only SSH from `modules/system/keys/admin/*.pub` (`system/ssh.nix`); the root password login (`homelab.debug`) is gone |
| Host types | `modules/{compute,storage,virtual,edge}.nix` import the blocks they need and hold the shared values, hosts import one; `compute.nix` is only the three hypervisors (mesh/FRR/ceph/incus values, ARC cap) |
| Config files | `frr.conf` and the incus nftables table are `config/` files filled with `builtins.replaceStrings`; FRR timers are required options |
| Onboarding | `hosts/_template/` (an incus VM: ext4 root, DHCP), README rewritten |

Verified against the pre-refactor tree with the same inputs: disko scripts identical on
all hosts; system closures differ only in `system-path` package order, `VLAN=` line
order in `lan.network` and one blank line in `frr.conf`. The admin keys change then drops the empty `""` authorized key.

## Remaining

| Item | Why | Effort |
|---|---|---|
| Commit `flake.lock` | Inputs float on every eval, builds aren't reproducible | `nix flake lock` |
| `devShells.default` (sops, age, ssh-to-age, nixos-anywhere, nixfmt) | One command to get tooling | small |
| `checks` evaluating every host + diskoScript drvPath snapshot | Catch partition label drift in CI | small |
| `apps.deploy` / `apps.install` wrappers | Fewer hand-typed commands | small |
| Generate `.sops.yaml` host rules from `hosts/` | Adding a host touches three places in `.sops.yaml` | medium |
| `modules/desktop*` | Not imported; references missing `secrets/desktop.yaml` and a home-manager file without the home-manager input | decide: fix or delete |
| Edge host (`ionos-de`) | Written with the old box's peers, NAT and sites; install with nixos-anywhere, copy `/var/www` over until the blog moves to the lab (`upstream`) | small |
| `homelab.hardware.amd` | amd_pstate/governor/realtek blacklist repeated in 3 hosts | small, optional |
