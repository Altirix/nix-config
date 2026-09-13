{ config, lib, ... }:

{
  assertions = [
    {
      assertion = config.disko.devices.disk ? disk1 && config.disko.devices.disk ? disk2;
      message = ''
        grub-mirrored-boot.nix requires both `disk1` and `disk2` to be
        defined in this host's disko.nix. 
        '';
    }
  ];

  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true; 
    device = "nodev";

    mirroredBoots = [
      {
        devices = [ config.disko.devices.disk.disk1.device ];
        path = "/boot1";
        efiSysMountPoint = "/boot1";
      }
      {
        devices = [ config.disko.devices.disk.disk2.device ];
        path = "/boot2";
        efiSysMountPoint = "/boot2";
      }
    ];
  };
}
