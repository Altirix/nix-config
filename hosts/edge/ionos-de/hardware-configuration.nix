# Replace with `nixos-generate-config --show-hardware-config` from the VPS
# (nixos-anywhere --generate-hardware-config does it during install).
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "virtio_blk" "sd_mod" "sr_mod" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
