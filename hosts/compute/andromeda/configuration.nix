{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "25.11";

  sops.defaultSopsFile = ./secrets.yaml;
}