# Replace with `nixos-generate-config --show-hardware-config` from the board.
{ lib, ... }:

{
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
