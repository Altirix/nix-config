{ config, lib, nodes, ... }:

# The front door to an SSO server (server.nix on `server`): serves it at https://<domain> over the tunnel, accepting
# only its own certificate, and runs oauth2-proxy (modules/services/web) signing browsers in with its `web` client for
# this host's `sso` sites. Sites attach by setting `sso = true`, the server picks up their callbacks.
let
  cfg = config.homelab.sso.gateway;
  server = nodes.${cfg.server}.config;
  inherit (server.homelab.sso.server) domain;
in
{
  options.homelab.sso.gateway = {
    enable = lib.mkEnableOption "the front door to an SSO server";
    # The host running it.
    server = lib.mkOption { type = lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    homelab.web.sites.auth = {
      domains = [ domain ];
      https = true;
      from = [ cfg.server ];
    };

    warnings = lib.optional (server.homelab.sso.server.certificate == null)
      "sso: ${cfg.server} has no certificate set yet, ${domain} proxies to whatever answers at ${server.homelab.labs.address}";

    # Clients look up an issuer with a path (https://<domain>/oauth2/openid/<client>) at
    # /.well-known/<document>/oauth2/openid/<client> (RFC 8414), Kanidm only serves it under the issuer.
    services.nginx.virtualHosts.auth.extraConfig = ''
      rewrite ^/\.well-known/(oauth-authorization-server|openid-configuration)(/oauth2/openid/[^/]+)$ $2/.well-known/$1 last;
    '';

    # Its secrets come from this host's secrets.yaml (sops.defaultSopsFile), only it can read them.
    homelab.web.oauth = {
      issuer = "https://${domain}/oauth2/openid/web";
      clientId = "web";
      clientSecretFile = config.sops.secrets.kanidm-web-secret.path;
      cookieSecretFile = config.sops.secrets.oauth2-proxy-cookie-secret.path;
    };

    sops.secrets = lib.genAttrs [ "kanidm-web-secret" "oauth2-proxy-cookie-secret" ] (_: {
      restartUnits = [ "oauth2-proxy.service" ];
    });

    # oauth2-proxy reads the issuer through this host's own nginx, not out and back in.
    networking.hosts."127.0.0.1" = [ domain ];
  };
}
