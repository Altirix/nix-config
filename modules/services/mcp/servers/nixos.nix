{ lib, pkgs, ... }:

# Searches NixOS/home-manager/darwin options, nixpkgs packages and versions, noogle and nix.dev.
{
  homelab.mcp.servers.nixos = {
    command = lib.mkDefault (lib.getExe pkgs.mcp-nixos);
    port = lib.mkDefault 8102;
    # The FastMCP banner also checks PyPI for updates on start.
    environment.FASTMCP_SHOW_SERVER_BANNER = lib.mkDefault "false";
  };
}
