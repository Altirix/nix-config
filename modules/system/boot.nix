{ config, lib, ... }:

let
  cfg = config.homelab.boot.grubMirror;
  esps = config.homelab.storage.boot.espMountpoints;
in
{
  # systemd-boot only installs to one ESP, grub keeps every mirrored ESP bootable.
  options.homelab.boot.grubMirror.enable = lib.mkOption {
    type = lib.types.bool;
    default = lib.length esps > 1;
  };

  config = lib.mkIf cfg.enable {
    boot.loader.systemd-boot.enable = false;
    boot.loader.efi.canTouchEfiVariables = false;

    boot.loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      zfsSupport = config.homelab.storage.boot.filesystem == "zfs";
      copyKernels = true;
      # Installs to /boot, without it grub falls back to an i386 install.
      device = "nodev";

      # Really "additionalBoots", the first ESP is covered by `device` above.
      mirroredBoots = map (esp: {
        devices = [ "nodev" ];
        path = esp;
        efiSysMountPoint = esp;
      }) (lib.tail esps);
    };
  };
}
