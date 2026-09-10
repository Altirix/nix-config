{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];
  
  networking.hostId = "8425e349"; # unique id `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '`

  system.stateVersion = "25.11";

  sops.defaultSopsFile = ./secrets.yaml;
}