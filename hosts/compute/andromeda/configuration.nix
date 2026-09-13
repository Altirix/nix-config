{ config, pkgs, inputs, ... }:

{
  imports = [
    inputs.sops-nix.nixosModules.sops
  ];

  system.stateVersion = "25.11";

  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.forceImportRoot = false;

  sops.defaultSopsFile = ./secrets.yaml;
}