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

      # Same reason as systemd-boot.editor in default.nix: a superuser locks editing and the grub shell.
      # The hash is of a thrown away random password, so nobody can edit, every generation still boots.
      users.root.hashedPassword = "grub.pbkdf2.sha512.10000.C54008A9DF7568CE8E066CEAB2E704F7DA6BF870E714798671FCA46E24E0CB7FE77484DB8C6942246CCE1DA0A1CA1AB9620FBF9DFD9249E64D5007499029723C.22858FB3787FCD8E45A1DF5C8882A9F47A06289B138A9035D038AE4BC7F0F66D0A07D82A9A046B73CAA58D624491E9177288BC0CC0D263961E946DB0CE77EE3B";
      subEntryOptions = "--class nixos --unrestricted";
    };
  };
}
