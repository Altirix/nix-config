{ ... }:

# MCP servers for agents, each on its own port. Presets are in modules/services/mcp/servers/, enable them here.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  # Once incus-mcp-key is in secrets/virtual.yaml and the cluster trusts incus-mcp.crt (modules/services/mcp/README.md).
  # homelab.mcp.servers.incus = {
  #   enable = true;
  #   environment.INCUS_SERVER_CERT = "${../../../modules/compute/incus-cluster.crt}";
  # };

  system.stateVersion = "26.05";
}
