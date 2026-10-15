{ config, lib, ... }:

# nginx sites, each either serves files from `root` or proxies to an `upstream` (usually across the tunnel).
# Files in `root` aren't managed by nix, they're copied in (rsync as admin).
let
  cfg = config.homelab.web;
  inherit (lib) mkOption types;

  site = types.submodule {
    options = {
      root = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      # e.g. http://10.100.0.20:8080
      upstream = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      # First is the server name, the rest aliases. Empty answers any name.
      domains = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      # ACME certificate for `domains`, plain HTTP redirects to it.
      https = mkOption {
        type = types.bool;
        default = false;
      };

      # Only answer on this address (e.g. the tunnel), null answers on every address.
      address = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      # Answers requests no other site claims.
      default = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  https = lib.any (s: s.https) (lib.attrValues cfg.sites);
in
{
  options.homelab.web = {
    enable = lib.mkEnableOption "nginx sites";

    sites = mkOption {
      type = types.attrsOf site;
      default = { };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: s: {
      assertion = (s.root == null) != (s.upstream == null) && (s.https -> s.domains != [ ] && s.address == null);
      message = "web: site ${name} needs exactly one of root or upstream, and https needs domains on every address";
    }) cfg.sites;

    # No account email: Let's Encrypt no longer sends expiry mail, and it would end up in the nix store.
    security.acme.acceptTerms = lib.mkIf https true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts = lib.mapAttrs (_: s: {
        inherit (s) root default;
        serverName = if s.domains == [ ] then "_" else lib.head s.domains;
        serverAliases = lib.drop 1 s.domains;
        listen = lib.optional (s.address != null) {
          addr = s.address;
          port = 80;
        };
        enableACME = s.https;
        forceSSL = s.https;
        locations."/" = if s.upstream != null then {
          proxyPass = s.upstream;
          proxyWebsockets = true;
        } else {
          tryFiles = "$uri $uri/ =404";
        };
      }) cfg.sites;
    };

    systemd.tmpfiles.rules = lib.mapAttrsToList (_: s: "d ${s.root} 0755 admin users -")
      (lib.filterAttrs (_: s: s.root != null) cfg.sites);

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional https 443;
  };
}
