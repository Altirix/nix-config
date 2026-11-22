{ config, inputs, lib, pkgs, ... }:

# NixOS-WSL distros: Windows owns the kernel, boot, disks and network, NixOS only the userland.
# The WSL distro is where deploys run from (README.md, Install and deploy), with Windows' ssh keys and config.
let
  cfg = config.homelab.wsl;
  user = config.wsl.defaultUser;
in
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  options.homelab.wsl.windowsUser = lib.mkOption {
    type = lib.types.str;
    description = "Windows account whose %USERPROFILE%\\.ssh becomes the default user's ~/.ssh.";
    example = "User";
  };

  config = {
    wsl = {
      enable = true;
      # The shell `wsl -d <distro>` opens, passwordless sudo like every host (modules/default.nix).
      defaultUser = "admin";
      # ssh refuses keys and config others can read or write: Windows files on the drives are the default user's
      # and 0700 (directories 0755), metadata keeps what Linux chmods.
      wslConf.automount.options = lib.concatStringsSep "," [
        "metadata"
        "uid=${toString config.users.users.${user}.uid}"
        "gid=${toString config.users.groups.users.gid}"
        "umask=022"
        "fmask=077"
      ];
    };

    # One ~/.ssh for Windows and WSL: keys, config and known_hosts. `L` leaves an existing ~/.ssh alone.
    systemd.tmpfiles.rules = [
      "L /home/${user}/.ssh - - - - ${config.wsl.wslConf.automount.root}/c/Users/${cfg.windowsUser}/.ssh"
    ];

    # What deploying and installing the other hosts takes, nixos-rebuild comes with NixOS.
    environment.systemPackages = with pkgs; [
      nixos-anywhere
      sops
      age
    ];

    # WSL boots its own kernel, there is no bootloader to install.
    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;

    # Behind Windows' NAT, not on labs: no address for the logs VM to take its journal from.
    homelab.logs.shipTo = null;

    # Only reachable from Windows itself, open nothing.
    networking.firewall.enable = true;
  };
}
