{ config, ... }:

# MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
let
  # The low-risk servers the edge puts on the internet (nginx with tokens, hosts/edge/ionos-de/mcp.nix) also let
  # in its tunnel address. Never playwright (runs code), github or incus (hold credentials).
  edge = config.homelab.mcp.clients ++ [ "10.0.0.1" ];
in
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # Machines agents run on in the lab, e.g. "10.10.0.20" (and the router rule, modules/services/mcp/README.md).
  homelab.mcp.clients = [ ];

  homelab.mcp.servers.rea = { enable = true; clients = edge; };
  homelab.mcp.servers.nixos = { enable = true; clients = edge; };
  # homelab.mcp.servers.github.enable = true;   # once github-mcp-token is in secrets/virtual.yaml
  homelab.mcp.servers.context7 = { enable = true; clients = edge; };
  homelab.mcp.servers.fetch = { enable = true; clients = edge; };
  homelab.mcp.servers.time = { enable = true; clients = edge; };
  homelab.mcp.servers.memory = { enable = true; clients = edge; };
  homelab.mcp.servers.playwright.enable = true;
  homelab.mcp.servers.markitdown = { enable = true; clients = edge; };
  # Once incus-mcp-key is in secrets/virtual.yaml and the cluster trusts incus-mcp.crt (modules/services/mcp/README.md).
  # homelab.mcp.servers.incus = {
  #   enable = true;
  #   environment.INCUS_SERVER_CERT = "${../../../modules/compute/incus-cluster.crt}";
  # };

  system.stateVersion = "26.05";
}
