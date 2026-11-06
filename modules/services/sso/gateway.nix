{ config, lib, nodes, ... }:

# The front door to an SSO server (server.nix on `server`): serves it at https://<domain> over the tunnel, accepting
# only its own certificate, and signs browsers in for this host's `sso` sites (modules/services/web), each with a
# client of its own. Sites attach by setting `sso`, the server makes their clients from this host's config.
let
  cfg = config.homelab.sso.gateway;
  server = nodes.${cfg.server}.config;
  inherit (server.homelab.sso.server) domain;
  # Named after the server, out of the way of the host's own sites.
  site = "sso-${cfg.server}";
in
{
  options.homelab.sso.gateway = {
    enable = lib.mkEnableOption "the front door to an SSO server";
    # The host running it.
    server = lib.mkOption { type = lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = lib.elem config.networking.hostName server.homelab.sso.server.gateways;
      message = "sso: ${cfg.server}'s homelab.sso.server.gateways doesn't list ${config.networking.hostName}, its sites would get no clients";
    }];

    homelab.web.sites.${site} = {
      domains = [ domain ];
      https = true;
      from = [ cfg.server ];
    };

    warnings = lib.optional (server.homelab.sso.server.certificate == null)
      "sso: ${cfg.server} has no certificate set yet, ${domain} proxies to whatever answers at ${server.homelab.labs.address}";

    # Clients look up an issuer with a path (https://<domain>/oauth2/openid/<client>) at
    # /.well-known/<document>/oauth2/openid/<client> (RFC 8414), Kanidm only serves it under the issuer.
    services.nginx.virtualHosts.${site}.extraConfig = ''
      rewrite ^/\.well-known/(oauth-authorization-server|openid-configuration)(/oauth2/openid/[^/]+)$ $2/.well-known/$1 last;
    '';

    homelab.web.sso.issuer = "https://${domain}/oauth2/openid/";

    # oauth2-proxy reads the issuer through this host's own nginx, not out and back in.
    networking.hosts."127.0.0.1" = [ domain ];
  };
}
