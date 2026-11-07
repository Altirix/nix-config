{ config, lib, ... }:

# InvenTree, parts inventory (next to Part-DB, modules/services/partdb, to compare), published (homelab.publish) for
# a front door with sign-in. There's no second login: the front door names the user in X-Forwarded-User and
# InvenTree's remote login takes it, only the `trustedProxies` reach it. Setting it up, the router rule: README.md.
let
  cfg = config.homelab.inventree;
  host = lib.removePrefix "https://" cfg.url;
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.inventree = {
    enable = lib.mkEnableOption "InvenTree";
    # Where people reach it, e.g. https://inventree.example.com (no trailing slash).
    url = lib.mkOption { type = lib.types.str; };
    # The front door's addresses, the only ones whose X-Forwarded-User counts.
    trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    services.inventree = {
      enable = true;
      # nginx's server name, and with the url ALLOWED_HOSTS and CSRF's trusted origin.
      domain = host;
      settings = {
        INVENTREE_SITE_URL = cfg.url;
        # The front door signs people in, its user is InvenTree's (made on first sign-in, without permissions).
        INVENTREE_REMOTE_LOGIN = "true";
        INVENTREE_REMOTE_LOGIN_HEADER = "HTTP_X_FORWARDED_USER";
        INVENTREE_LOGOUT_REDIRECT_URL = "/oauth2/sign_out";
        # It's https at the front door, for CSRF checks, links and Secure cookies.
        INVENTREE_USE_X_FORWARDED_PROTO = "true";
        INVENTREE_SESSION_COOKIE_SECURE = "true";
      };
    };

    # The module's site, on every address for the front door, which says who's signed in (and that it's https).
    services.nginx.virtualHosts.${host} = {
      listen = [{ addr = "0.0.0.0"; port = 80; }];
      locations."/" = {
        # The front door's view of the request, not this hop's (the module's own lines are kept).
        recommendedProxySettings = lib.mkForce false;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $http_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
          proxy_set_header X-Forwarded-User $http_x_forwarded_user;
        '';
      };
      extraConfig = ''
        ${lib.concatMapStrings (a: "allow ${a};\n") cfg.trustedProxies}deny all;
      '';
    };

    homelab.publish = {
      upstream.port = 80;
      # The module's nginx takes 100M.
      maxBodySize = "100m";
    };

    # Only on the labs bridge, the router lets the front door in.
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
}
