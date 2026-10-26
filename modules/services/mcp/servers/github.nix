{ config, lib, pkgs, ... }:

# GitHub's MCP server, read-only. The token is held by the server, every client acts as its owner.
# Widen the toolsets in the host, --read-only still applies: environment.GITHUB_TOOLSETS = "default,actions";
let
  enable = config.homelab.mcp.servers.github.enable;
in
{
  homelab.mcp.servers.github = {
    command = lib.mkDefault (lib.getExe pkgs.github-mcp-server);
    args = lib.mkDefault [ "stdio" "--read-only" ];
    port = lib.mkDefault 8103;
    environment.GITHUB_TOOLSETS = lib.mkDefault "context,repos,issues,pull_requests,users";
    environmentFile = lib.mkIf enable (lib.mkDefault config.sops.templates."mcp-github.env".path);
  };

  sops = lib.mkIf enable {
    # From the host's secrets.yaml (sops.defaultSopsFile), only that host can read it.
    secrets."github-mcp-token".key = "github-mcp-token";

    templates."mcp-github.env" = {
      content = "GITHUB_PERSONAL_ACCESS_TOKEN=${config.sops.placeholder."github-mcp-token"}\n";
      restartUnits = [ "mcp-github.service" ];
    };
  };
}
