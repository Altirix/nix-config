{ config, lib, pkgs, nodes, ... }:

# Paperless-ngx over MCP (packages/paperless-mcp.nix): search, read and file documents on `host`
# (modules/services/paperless), through its token-only API port. Every client acts as the token's Paperless user,
# so its permissions are what the tools can do (README.md): the server itself can edit and delete.
let
  cfg = config.homelab.mcp.paperless;
  enable = config.homelab.mcp.servers.paperless.enable;
  paperless = nodes.${cfg.host}.config;
in
{
  options.homelab.mcp.paperless.host = lib.mkOption {
    type = lib.types.str;
    default = "paperless";
  };

  config = {
    homelab.mcp.servers.paperless = {
      command = lib.mkDefault (lib.getExe (pkgs.callPackage ../packages/paperless-mcp.nix { }));
      port = lib.mkDefault 8111;
      environment = lib.mkIf enable {
        PAPERLESS_URL = "http://${paperless.homelab.labs.address}:${toString paperless.homelab.paperless.apiPort}";
        # Document links point at the site.
        PAPERLESS_PUBLIC_URL = paperless.homelab.paperless.url;
        # post_document's file_path reads nothing off this VM, uploads come as content.
        PAPERLESS_MCP_UPLOAD_PATHS = "/var/empty";
      };
      environmentFile = lib.mkIf enable (lib.mkDefault config.sops.templates."mcp-paperless.env".path);
    };

    sops = lib.mkIf enable {
      # From the host's secrets.yaml (sops.defaultSopsFile), only that host can read it.
      secrets."paperless-mcp-token".key = "paperless-mcp-token";

      templates."mcp-paperless.env" = {
        content = "PAPERLESS_API_KEY=${config.sops.placeholder."paperless-mcp-token"}\n";
        restartUnits = [ "mcp-paperless.service" ];
      };
    };
  };
}
