{ config, lib, pkgs, modulesPath, ... }:

# Shared by the Chromebook USB installer and the recovery system: a text console
# and key-only SSH as admin, booting a prebuilt ext4 root. The flake adds the board module.
let
  cfg = config.chromebookLive;
in
{
  imports = [
    "${modulesPath}/profiles/installation-device.nix"
    ../../modules/hardware/chromebook
    ../../modules/system/ssh.nix
  ];

  options.chromebookLive.rootLabel = lib.mkOption {
    type = lib.types.str;
    description = "Filesystem label of the live root.";
  };

  config = {
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
    environment.systemPackages = [
      pkgs.vboot-utils pkgs.gptfdisk pkgs.parted pkgs.e2fsprogs
      config.system.build.chromebookTools.partition
    ];
    fileSystems."/" = {
      device = "/dev/disk/by-label/${cfg.rootLabel}";
      fsType = "ext4";
    };
    # Live systems are written as images: never rewrite or confirm the internal kernel slots.
    boot.loader.external.installHook = lib.mkForce (pkgs.writeShellScript "chromebook-live-no-install" ''
      echo 'Chromebook live system: no bootloader installation' >&2
      exit 1
    '');
    systemd.services.chromebook-mark-good.enable = false;

    # make-ext4-fs carries closure registrations, loaded once before Nix starts.
    systemd.services.register-nix-paths = {
      description = "Register the live Nix store";
      wantedBy = [ "sysinit.target" ];
      before = [ "sysinit.target" "nix-daemon.service" "nix-daemon.socket" "shutdown.target" ];
      after = [ "local-fs.target" ];
      conflicts = [ "shutdown.target" ];
      unitConfig = {
        DefaultDependencies = false;
        ConditionPathExists = "/nix-path-registration";
      };
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      path = [ config.nix.package ];
      script = builtins.readFile ./register-nix-paths.sh;
    };

    system.build.chromebookRootfs = pkgs.buildPackages.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
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
