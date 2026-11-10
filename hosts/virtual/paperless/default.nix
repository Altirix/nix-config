{ ... }:

# Paperless-ngx (modules/services/paperless), at docs.peacocks.me through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.paperless = {
    enable = true;
    url = "https://docs.peacocks.me";
    # The edge's tunnel address.
    trustedProxies = [ "10.0.0.1" ];
    # Shared with the mcp VM, its Paperless MCP server uses it.
    mcpTokenFile = ../../../secrets/paperless.yaml;
  };
}
