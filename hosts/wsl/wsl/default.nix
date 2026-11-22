# The NixOS-WSL distro, see hosts/README.md (Install a WSL distro).
{ ... }:

{
  imports = [ ../../../modules/wsl.nix ];

  # No hardware-configuration.nix, WSL has no hardware to describe.
  nixpkgs.hostPlatform = "x86_64-linux";

  # Keep what the distro was first installed with, /etc/nixos/configuration.nix in the stock image has it.
  system.stateVersion = "26.05";
}
