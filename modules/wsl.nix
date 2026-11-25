{ config, inputs, lib, pkgs, ... }:

# NixOS-WSL distros: Windows owns the kernel, boot, disks and network, NixOS only the userland.
# The WSL distro is where deploys run from (README.md, Install and deploy) and takes Windows' identity: its
# hostname, its ssh agent, keys and config, and its git config.
let
  cfg = config.homelab.wsl;
  user = config.wsl.defaultUser;
  profile = "${config.wsl.wslConf.automount.root}/c/Users/${cfg.windowsUser}";
in
{
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];

  options.homelab.wsl = {
    windowsUser = lib.mkOption {
      type = lib.types.str;
      description = "Windows account whose %USERPROFILE%\\.ssh and .gitconfig the default user takes.";
      example = "User";
    };
    gitCredentialManager = lib.mkOption {
      type = lib.types.str;
      default = "${config.wsl.wslConf.automount.root}/c/Program Files/Git/mingw64/bin/git-credential-manager.exe";
      description = "Git for Windows' credential manager, for https remotes.";
    };
  };

  config = {
    wsl = {
      enable = true;
      # The shell `wsl -d <distro>` opens, passwordless sudo like every host (modules/default.nix).
      defaultUser = "admin";
      # Keys stay in Windows' OpenSSH agent, ssh in WSL asks it over interop (SSH_AUTH_SOCK).
      ssh-agent.enable = true;
      # ssh refuses a config or known_hosts others can write: Windows files on the drives are the default user's,
      # 0755, metadata keeps what Linux chmods.
      wslConf.automount.options = lib.concatStringsSep "," [
        "metadata"
        "uid=${toString config.users.users.${user}.uid}"
        "gid=${toString config.users.groups.users.gid}"
        "umask=022"
      ];
    };

    # No hostname of its own: wsl.conf leaves it out and WSL uses the Windows computer name. The flake output keeps
    # the directory name, so rebuild with `#<name>`.
    networking.hostName = lib.mkForce "";

    # One ~/.ssh for Windows and WSL: config and known_hosts, the keys' .pub pick them in the agent. `L` leaves an
    # existing ~/.ssh alone.
    systemd.tmpfiles.rules = [
      "L /home/${user}/.ssh - - - - ${profile}/.ssh"
    ];

    # Windows' git config (name, email, aliases), then what has to differ in Linux: no CRLF checkouts for repos without
    # an eol in .gitattributes, Linux ssh (through the agent) and Git for Windows' credential manager in place of
    # Windows-only helpers.
    programs.git = {
      enable = true;
      config = [
        { include.path = "${profile}/.gitconfig"; }
        {
          core.autocrlf = "input";
          core.sshCommand = "ssh";
          # The empty helper drops the ones the Windows config set.
          credential.helper = [ "" cfg.gitCredentialManager ];
        }
      ];
    };

    # What deploying and installing the other hosts takes, nixos-rebuild comes with NixOS. openssl makes the secrets
    # the READMEs generate (openssl rand).
    environment.systemPackages = with pkgs; [
      nixos-anywhere
      sops
      age
      openssl
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
