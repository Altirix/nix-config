{ config, pkgs, ... }:

{
  imports = [
  ];

  networking.hostName = "homelab-server";
  networking.hostId = "8425e349"; # unique id `head -c4 /dev/urandom | od -A none -t x4 | tr -d ' '`

  system.stateVersion = "25.11";
}