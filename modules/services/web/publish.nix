{ lib, ... }:

# What a host serves for a front door to put on the internet: a homelab.web site on the edge names this host in
# `from`, adds its labs address, the name, TLS and who may get in. Service modules fill it in (mcp, rea, logs,
# partdb, sso), the host only decides which of them to publish.
let
  inherit (lib) mkOption types;
in
{
  options.homelab.publish = {
    # Path prefix -> port and path on this host: "/time/mcp" = { port = 8106; path = "/mcp"; }.
    locations = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          port = mkOption { type = types.port; };
          path = mkOption {
            type = types.str;
            default = "/";
          };
        };
      });
      default = { };
    };
    # Or the whole site on one port, with its own certificate when it serves https.
    upstream = mkOption {
      type = types.nullOr (types.submodule {
        options = {
          port = mkOption { type = types.port; };
          https = mkOption {
            type = types.bool;
            default = false;
          };
          certificate = mkOption {
            type = types.nullOr types.path;
            default = null;
          };
        };
      });
      default = null;
    };
    # The largest request body it takes, e.g. "1g" for uploads.
    maxBodySize = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
  };
}
