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
  # port, the edge only on the public ones (mcp.peacocks.me).
  homelab.mcp.servers = {
    nixos = { enable = true; public = true; };
    context7 = { enable = true; public = true; };
    time = { enable = true; public = true; };
    memory = { enable = true; public = true; };
    fdfdb = { enable = true; public = true; };
    paperless = { enable = true; public = true; };
  };

  # A KiCad MCP server per project (modules/services/mcp/servers/kicad.nix), at mcp.peacocks.me/kicad/<project>/mcp.
  # One per line of work: agents on different projects never share a server or files.
  # Those with a source follow its repo, agents' commits go back up with its deploy key (README.md, KiCad).
  homelab.mcp.kicad = {
    projects = [ "palmremote" "polaris11" "navi14" ];
    sources = {
      palmremote.url = "git@github.com:Altirix/A1990-A2141-PalmRemote.git";
      polaris11.url = "git@github.com:Altirix/Polaris11.git";
      navi14.url = "git@github.com:Altirix/Navi14.git";
    };
  };

  system.stateVersion = "26.05";
}
