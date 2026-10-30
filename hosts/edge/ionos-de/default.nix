{ ... }:

# IONOS VPS, replaces the Ubuntu WireGuard + nginx box. Tunnel home, egress NAT, static sites.
{
  imports = [
    ../../../modules/edge.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
    ./services.nix
    ./auth.nix  # needs kanidm-web-secret, oauth2-proxy-cookie-secret in secrets.yaml and auth.peacocks.me pointed here
    ./mcp.nix   # needs mcp.peacocks.me pointed here
    ./logs.nix  # needs logs.peacocks.me pointed here
    ./partdb.nix  # needs parts.peacocks.me pointed here
  ];

  system.stateVersion = "26.05";
}
