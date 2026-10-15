{ ... }:

# IONOS VPS, replaces the Ubuntu WireGuard + nginx box. Tunnel home, egress NAT, static sites.
{
  imports = [
    ../../../modules/edge.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
    ./services.nix
  ];

  system.stateVersion = "26.05";
}
