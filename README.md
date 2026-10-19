# NixOS Homelab

Flake for the homelab hosts.

- `modules/<category>/` hold the building blocks (system, disks, networking, services).
  Each is inert until enabled through `homelab.*` options and has no site values baked in.
  Real config files live next to them in `config/`, not inside the `.nix` files.
- `modules/default.nix` is what every host gets: the generic blocks plus the baseline config.
- `modules/{compute,storage,virtual,edge,printer}.nix` compose the blocks for a type of host, import
  the extra blocks it needs and hold the values shared by every host of that type.
- `hosts/` say what is specific to one machine and import one of those type modules.

## Layout

```
flake.nix      discovers hosts/<group>/<name>/default.nix, adds modules/default.nix
modules/       building blocks and host types
hosts/         one directory per machine, grouped by type
secrets/       sops files shared by a host type (common.yaml by every host)
docs/          design notes
```

| Read | For |
|---|---|
| [hosts/README.md](hosts/README.md) | the hosts, adding one, installing a VM |
| [modules/README.md](modules/README.md) | what each module does |
| [modules/networking/README.md](modules/networking/README.md) | labs (VLAN 100), address pinning, labs-mesh, the router |
| [modules/services/incus/README.md](modules/services/incus/README.md) | ssh into VMs, Windows VMs, vGPU |
| [modules/disks/README.md](modules/disks/README.md) | `homelab.storage`, partition labels |
| [hosts/printer/README.md](hosts/printer/README.md) | the ROCK 5C Klipper hosts |
| [docs/scope-usability.md](docs/scope-usability.md) | what host-driven config covers |

## Secrets

```sh
ssh-keyscan -t ed25519 <host> | nix run nixpkgs#ssh-to-age   # add to .sops.yaml keys, groups and a host rule
sops updatekeys secrets/*.yaml hosts/*/*/secrets.yaml
sops hosts/<group>/<name>/secrets.yaml
```

Login is key-only as `admin`, every `modules/system/keys/admin/*.pub` is authorized on every
host and no host builds without one. There is no root or console password.

## Install and deploy

```sh
nix run github:nix-community/nixos-anywhere -- --flake .#<name> root@<ip>
nixos-rebuild switch --flake .#<name> --target-host admin@<name> --sudo
```

VMs and the printers install differently, see [hosts/README.md](hosts/README.md) and
[hosts/printer/README.md](hosts/printer/README.md).
