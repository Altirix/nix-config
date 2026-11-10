{ ... }:

# KiCad projects with their MCP servers and pages (modules/services/pcb), at pcb.peacocks.me and
# mcp.peacocks.me/kicad/<project>/mcp through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  # KiCad renders and checks.
  homelab.vm = {
    cpus = 4;
    memory = "4GiB";
  };

  homelab.pcb = {
    enable = true;
    # One per line of work: agents on different projects never share a server or files.
    projects = [ "scratch" "palmremote" ];
    # The edge's tunnel address.
    trustedProxies = [ "10.0.0.1" ];
  };
}
