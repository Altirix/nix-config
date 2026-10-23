{ ... }:

# MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.mcp.servers.rea.enable = true;
  homelab.mcp.servers.nixos.enable = true;

  system.stateVersion = "26.05";
}
