{ ... }:

# MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # homelab.mcp.servers.github.enable = true;   # once github-mcp-token is in secrets/virtual.yaml

  system.stateVersion = "26.05";
}
