{ lib, ... }:

# What a host serves for a front door to put on the internet: a homelab.web site on the edge names this host in
# `from` and gets these, the edge adds the name, TLS and who may get in. Service modules fill it in (mcp, rea, logs,
# partdb, sso), the host only decides which of them to publish.
let
  inherit (lib) mkOption types;
in
{
  options.homelab.publish = {
    # Path prefixes, each proxied to its own URL on this host, as homelab.web.sites.<name>.locations.
    locations = mkOption {
      type = types.attrsOf (types.strMatching "http://[^/]+/.*");
      default = { };
    };
    # Or the whole site, as homelab.web.sites.<name>.upstream (with its upstreamCertificate).
    upstream = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
    upstreamCertificate = mkOption {
      type = types.nullOr types.path;
      default = null;
    };
    # The largest request body it takes, e.g. "1g" for uploads.
    maxBodySize = mkOption {
      type = types.nullOr types.str;
      default = null;
    };
  };
}
