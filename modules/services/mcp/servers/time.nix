{ config, lib, pkgs, ... }:

# Current time and timezone conversion, "local" is the host's time.timeZone.
{
  homelab.mcp.servers.time = {
    command = lib.mkDefault (lib.getExe pkgs.mcp-server-time);
    args = lib.mkDefault (lib.optionals (config.time.timeZone != null)
      [ "--local-timezone" config.time.timeZone ]);
    port = lib.mkDefault 8106;
  };
}
