{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
  # Who reaches which port is the router's call (modules/services/mcp/README.md): agents on every port, the edge
  # (hosts/edge/ionos-de/mcp.nix) only on the low-risk ones. Never let the edge at playwright (runs code) or
  # github (holds a token).
  homelab.mcp.servers.nixos.enable = true;
  homelab.mcp.servers.github.enable = true;
  homelab.mcp.servers.context7.enable = true;
  homelab.mcp.servers.fetch.enable = true;
  homelab.mcp.servers.time.enable = true;
  homelab.mcp.servers.memory.enable = true;
  homelab.mcp.servers.playwright.enable = true;
  homelab.mcp.servers.markitdown.enable = true;

  system.stateVersion = "26.05";
}
