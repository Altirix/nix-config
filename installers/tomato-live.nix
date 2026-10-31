{ config, lib, pkgs, modulesPath, ... }:

# Shared by the Tomato USB installer and the eMMC recovery system: a text
# console and key-only SSH as admin, booting a prebuilt ext4 root.
let
  cfg = config.tomatoLive;
in
{
  imports = [
    "${modulesPath}/profiles/installation-device.nix"
    ../modules/hardware/tomato.nix
    ../modules/system/ssh.nix
  ];

  options.tomatoLive.rootLabel = lib.mkOption {
    type = lib.types.str;
    description = "Filesystem label of the live root.";
  };

  config = {
    homelab.hardware.tomato = {
      enable = true;
      wifi = true;
    };
    # Text console on a connected display; no graphical installer or desktop.
    services.xserver.enable = false;
    services.getty.autologinUser = "nixos";
    boot.consoleLogLevel = 7;
    # The installation profile uses NetworkManager, including wired DHCP.
    networking.firewall.allowedTCPPorts = [ 22 ];
    users.users.admin = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
    };
    services.openssh.settings.PermitRootLogin = "no";
    services.openssh.settings.PasswordAuthentication = false;
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
    environment.systemPackages = [ pkgs.vboot-utils pkgs.gptfdisk pkgs.parted pkgs.e2fsprogs ];
    fileSystems."/" = {
      device = "/dev/disk/by-label/${cfg.rootLabel}";
      fsType = "ext4";
    };
    # Live systems are written as images; never let one rewrite the eMMC kernel slots.
    boot.loader.external.installHook = lib.mkForce (pkgs.writeShellScript "tomato-live-no-install" ''
      echo 'Tomato live system: no bootloader installation' >&2
      exit 1
    '');

    # make-ext4-fs carries closure registrations, loaded once before Nix starts.
    systemd.services.register-nix-paths = {
      description = "Register the Tomato live Nix store";
      wantedBy = [ "sysinit.target" ];
      before = [ "sysinit.target" "nix-daemon.service" "nix-daemon.socket" "shutdown.target" ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        ${config.nix.package}/bin/nix-store --load-db < /nix-path-registration
        touch /etc/NIXOS
        ${config.nix.package}/bin/nix-env -p /nix/var/nix/profiles/system --set /run/current-system
        rm /nix-path-registration
      '';
    };

    system.build.tomatoRootfs = pkgs.buildPackages.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
      storePaths = [ config.system.build.toplevel ];
      volumeLabel = cfg.rootLabel;
      populateImageCommands = ''
        mkdir -p ./files/sbin
        ln -s ${config.system.build.toplevel}/init ./files/sbin/init
      '';
    };
    system.stateVersion = "26.05";
  };
}
