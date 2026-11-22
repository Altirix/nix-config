{ inputs, lib, ... }:

# NixOS-WSL distros: Windows owns the kernel, boot, disks and network, NixOS only the userland.
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  wsl = {
    enable = true;
    # The shell `wsl -d <distro>` opens, passwordless sudo like every host (modules/default.nix).
    defaultUser = "admin";
  };

  # WSL boots its own kernel, there is no bootloader to install.
  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;

  # Behind Windows' NAT, not on labs: no address for the logs VM to take its journal from.
  homelab.logs.shipTo = null;

  # Only reachable from Windows itself, open nothing.
  networking.firewall.enable = true;
}
