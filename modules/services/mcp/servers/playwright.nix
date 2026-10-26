{ config, lib, pkgs, ... }:

# Headless chromium (from nixpkgs, nothing downloaded) driven over its own HTTP transport, so no
# mcp-proxy. --isolated gives every client a fresh in-memory context in one shared browser, closed
# when the client goes away, so clients never see each other's tabs or cookies.
# file:// is blocked and uploads stay in roots the client declares, but browser_run_code runs any
# Node in the server (its vm is no sandbox) and can't be turned off. So the unit is the boundary:
# what the dynamic user reads (the store, world-readable /etc) can go wherever the VM reaches.
let
  cfg = config.homelab.mcp.servers.playwright;
  state = "/var/lib/mcp-playwright";
in
{
  homelab.mcp.servers.playwright = {
    command = lib.mkDefault (lib.getExe pkgs.playwright-mcp);
    args = lib.mkDefault [
      "--headless"
      "--isolated"
      "--host" "0.0.0.0"
      "--port" (toString cfg.port)
      # Only Host: localhost is allowed otherwise, which rejects http://mcp:<port>.
      "--allowed-hosts" "*"
      "--output-dir" "${state}/output"
    ];
    transport = lib.mkDefault "http";
    port = lib.mkDefault 8108;
  };

  # Every navigation leaves a snapshot and console log here, screenshots too.
  systemd.tmpfiles.rules = lib.mkIf cfg.enable [ "e ${state}/output - - - 7d" ];
}
