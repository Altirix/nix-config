{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
  homelab.mcp.servers.nixos.enable = true;
  homelab.mcp.servers.github.enable = true;
  homelab.mcp.servers.fetch.enable = true;
  homelab.mcp.servers.time.enable = true;

  system.stateVersion = "26.05";
}
