{ lib, pkgs, ... }:

# Fetches a URL and returns it as markdown, honouring robots.txt.
# It reaches whatever the VM reaches, the labs network included.
{
  homelab.mcp.servers.fetch = {
    command = lib.mkDefault (lib.getExe pkgs.mcp-server-fetch);
    port = lib.mkDefault 8105;
    # readabilipy strips nav and footers with Readability.js when node is on PATH.
    path = lib.mkDefault [ pkgs.nodejs ];
  };
}
