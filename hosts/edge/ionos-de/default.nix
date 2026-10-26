{ ... }:

# IONOS VPS, replaces the Ubuntu WireGuard + nginx box. Tunnel home, egress NAT, static sites.
{
  imports = [
    ../../../modules/edge.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
    ./services.nix
    ./auth.nix  # needs auth.peacocks.me pointed here
    ./mcp.nix   # needs kanidm-mcp-secret, oauth2-proxy-cookie-secret in secrets.yaml and mcp.peacocks.me pointed here
  ];

  system.stateVersion = "26.05";
}
