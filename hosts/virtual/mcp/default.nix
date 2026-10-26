{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.

  system.stateVersion = "26.05";
}
