{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "26.05";

  sops.defaultSopsFile = ./secrets.yaml;

  # High-speed interconnects
  mesh = {
    interfaces = [ "enp12s0f0np0" "enp12s0f1np1" ];
    nodeId = 1;
  };
}