{ config, lib, ... }:

{

  boot.loader.systemd-boot.enable = false;
  boot.loader.efi.canTouchEfiVariables = false;

  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true; 
    device = "nodev";

    mirroredBoots = [ # this is really just "additionalBoots" the above "device" becomes "/boot" like below. without grub.device, it will atempt to install as i386
      #{
      #  devices = [ "nodev" ];
      #  path = "/boot";
      #  efiSysMountPoint = "/boot";
      #}
      {
        devices = [ "nodev" ];
        path = "/boot-2";
        efiSysMountPoint = "/boot-2";
      }
    ];
  };
}
