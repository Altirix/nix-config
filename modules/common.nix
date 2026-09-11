{ inputs, ... }:

{
  imports = [
    inputs.disko.nixosModules.disko
    inputs.sops-nix.nixosModules.sops
    ./common/base.nix
    ./common/users.nix
    ./common/debug.nix
  ];

  sops.secrets = {
  "common-hello" = {
    sopsFile = ../secrets/common.yaml;
    key= "hello";
  };
};
}