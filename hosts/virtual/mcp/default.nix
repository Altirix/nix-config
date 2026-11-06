{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
  # Who reaches which port is the router's call (modules/services/mcp/README.md): agents on every port, the edge
  # only on the public ones (mcp.peacocks.me). Never make playwright (runs code) or github (holds a token) public.
  homelab.mcp.servers = {
    nixos = { enable = true; public = true; };
    github.enable = true;
    context7 = { enable = true; public = true; };
    fetch = { enable = true; public = true; };
    time = { enable = true; public = true; };
    memory = { enable = true; public = true; };
    playwright.enable = true;
    markitdown = { enable = true; public = true; };
  };

  system.stateVersion = "26.05";
}
