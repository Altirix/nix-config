# Replace with `nixos-generate-config --show-hardware-config` from the VM
# (nixos-anywhere --generate-hardware-config does it during install).
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
