# Incus VM defaults, replace with `nixos-generate-config --show-hardware-config` from the VM.
{ lib, modulesPath, ... }:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" "xhci_pci" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
