{ config, lib, pkgs, modulesPath, ... }:

let
  rootfs = pkgs.buildPackages.callPackage "${modulesPath}/../lib/make-ext4-fs.nix" {
    storePaths = [ config.system.build.toplevel ];
    volumeLabel = "TOMATO-USB";
    populateImageCommands = ''
      mkdir -p ./files/sbin
      ln -s ${config.system.build.toplevel}/init ./files/sbin/init
    '';
  };
in
{
  imports = [
    "${modulesPath}/profiles/installation-device.nix"
    ../modules/hardware/tomato.nix
    ../modules/system/ssh.nix
  ];

  homelab.hardware.tomato = {
    enable = true;
    wifi = true;
  };
  networking.hostName = "tomato-installer";
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
  services.getty.helpLine = lib.mkForce "Tomato installer: SSH as admin with the repository's admin key.";
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  environment.systemPackages = [ pkgs.vboot-utils pkgs.gptfdisk pkgs.parted pkgs.e2fsprogs ];
  fileSystems."/" = {
    device = "/dev/disk/by-label/TOMATO-USB";
    fsType = "ext4";
  };

  # make-ext4-fs carries closure registrations, loaded once before Nix starts.
  systemd.services.register-nix-paths = {
    description = "Register the Tomato installer Nix store";
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

  system.build.tomatoDepthchargeImage = import ../modules/hardware/tomato/usb-image.nix {
    pkgs = pkgs.buildPackages;
    kernelImage = config.system.build.tomatoKernel;
    rootfsImage = rootfs;
  };
  system.stateVersion = "26.05";
}
