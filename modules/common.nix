{ disko }:
[
  disko.nixosModules.disko
  ./common/base.nix
  ./common/home.nix
  ./common/services.nix
  ./common/users.nix
]