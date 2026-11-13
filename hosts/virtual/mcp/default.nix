{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # MCP servers for agents, each on its own port: the ones holding tokens, keys or data, and the low-risk ones. Those
  # taking untrusted web input are on mcp-web (modules/services/mcp/README.md, Where servers run). Presets are in
  # modules/services/mcp/servers/, enable them here. Who reaches which port is the router's call: agents on every
  # port, the edge only on the public ones (mcp.peacocks.me). Never make github (holds a token) public.
  homelab.mcp.servers = {
    nixos = { enable = true; public = true; };
    github.enable = true;
    context7 = { enable = true; public = true; };
    time = { enable = true; public = true; };
    memory = { enable = true; public = true; };
    fdfdb = { enable = true; public = true; };
    paperless = { enable = true; public = true; };
  };

  # A KiCad MCP server per project (modules/services/mcp/servers/kicad.nix), at mcp.peacocks.me/kicad/<project>/mcp.
  # One per line of work: agents on different projects never share a server or files.
  homelab.mcp.kicad.projects = [ "scratch" "palmremote" ];

  system.stateVersion = "26.05";
}
