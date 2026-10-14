# Copy to hosts/<group>/<name>/, the directory name becomes the hostname.
# Add `nixos-generate-config --show-hardware-config` output as hardware-configuration.nix,
# and a secrets.yaml (with a .sops.yaml rule) if the host has its own secrets.
#
# Defaults to an incus VM. modules/compute.nix is only for the hypervisors in hosts/compute/.
{ ... }:

{
  imports = [
    ../../../modules/virtual.nix # adjust ../ to the host's depth
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";
}
