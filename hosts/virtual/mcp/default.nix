# MCP servers for agents in the lab, each on its own port on the labs bridge.
# Presets are in modules/services/mcp/servers/, enable them here.
{ ... }:

{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.mcp.servers.rea.enable = true;
  homelab.mcp.servers.nixos.enable = true;
  # homelab.mcp.servers.github.enable = true;   # once github-mcp-token is in secrets/virtual.yaml
  homelab.mcp.servers.context7.enable = true;
  homelab.mcp.servers.fetch.enable = true;
  homelab.mcp.servers.time.enable = true;
  homelab.mcp.servers.memory.enable = true;
  homelab.mcp.servers.playwright.enable = true;
  homelab.mcp.servers.markitdown.enable = true;

  system.stateVersion = "26.05";
}
