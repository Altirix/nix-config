{ config, pkgs, ... }:

{
  imports = [
  ];

  networking.hostName = "homelab-server";

  system.stateVersion = "25.11";
}