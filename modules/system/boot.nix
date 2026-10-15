{ config, lib, ... }:

let
  cfg = config.homelab.boot.grubMirror;
  inherit (config.homelab.storage.boot) bios devices;
  esps = config.homelab.storage.boot.espMountpoints;

  # nodev only installs to the ESP, a disk also gets grub in its BIOS boot partition.
  installTo = i: if bios then lib.elemAt devices i else "nodev";
in
{
  # systemd-boot only installs to one ESP and can't boot BIOS, grub keeps every mirrored ESP bootable.
  options.homelab.boot.grubMirror.enable = lib.mkOption {
    type = lib.types.bool;
    default = lib.length esps > 1 || bios;
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
      device = installTo 0;

      # Really "additionalBoots", the first ESP is covered by `device` above.
      mirroredBoots = lib.imap1 (i: esp: {
        devices = [ (installTo i) ];
        path = esp;
        efiSysMountPoint = esp;
      }) (lib.tail esps);
    };
  };
}
