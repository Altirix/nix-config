{ config, lib, pkgs, nodes, ... }:

# Paperless-ngx over MCP (packages/paperless-mcp.nix): search, read and file documents on `host`
# (modules/services/paperless), through its token-only API port, with the token that host makes its view-only mcp
# user with (its mcpTokenFile). Every client acts as that user: the server itself can edit and delete, the user
# can only read.
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
      # Shared with `host`, which gives its mcp user the same token.
      secrets."paperless-mcp-token".sopsFile = paperless.homelab.paperless.mcpTokenFile;

      templates."mcp-paperless.env" = {
        content = "PAPERLESS_API_KEY=${config.sops.placeholder."paperless-mcp-token"}\n";
        restartUnits = [ "mcp-paperless.service" ];
      };
    };
  };
}
