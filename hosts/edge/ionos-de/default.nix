{ ... }:

# IONOS VPS, replaces the Ubuntu WireGuard + nginx box. Tunnel home, egress NAT, static sites.
{
  imports = [
    ../../../modules/edge.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
    ./services.nix
    ./mcp.nix   # once mcp-token-* are in this host's secrets.yaml and mcp.peacocks.me points here
  ];

  system.stateVersion = "26.05";
}
