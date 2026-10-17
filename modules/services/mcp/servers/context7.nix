{ config, lib, pkgs, ... }:

# Library docs from context7.com. Its own stateless HTTP transport listens on every address, so no
# mcp-proxy and no /sse. An API key (higher rate limits) is sent per client as a header, not set here.
let
  cfg = config.homelab.mcp.servers.context7;
in
{
  homelab.mcp.servers.context7 = {
    command = lib.mkDefault (lib.getExe pkgs.context7-mcp);
    args = lib.mkDefault [ "--transport" "http" "--port" (toString cfg.port) ];
    transport = lib.mkDefault "http";
    port = lib.mkDefault 8104;
  };
}
