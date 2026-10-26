{ config, lib, ... }:

# nginx sites, each either serves files from `root` or proxies to an `upstream` (usually across the tunnel),
# with neither `/` is a 404 and only `locations` answer.
# Files in `root` aren't managed by nix, they're copied in (rsync as admin).
let
  cfg = config.homelab.web;
  inherit (lib) mkOption types;

  # nginx variable holding the client a site's token belongs to.
  clientVar = name: "web_client_${lib.replaceStrings [ "-" ] [ "_" ] name}";

  # http://10.100.1.11:8106/mcp -> { server = "10.100.1.11:8106"; path = "/mcp"; }, for upstream blocks with keepalive.
  parse = url:
    let m = builtins.match "http://([^/]+)(/.*)" url;
    in { server = lib.elemAt m 0; path = lib.elemAt m 1; };
  upstreamName = name: prefix: "${name}${lib.replaceStrings [ "/" "." ] [ "_" "_" ] (lib.removeSuffix "/" prefix)}";

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
      # More path prefixes, each proxied to its own upstream with the prefix swapped for the upstream's path:
      # "/time/mcp" = "http://10.100.1.11:8106/mcp". Unbuffered with long timeouts so streams pass straight
      # through (uploads too), redirects to the upstream's path are pointed back under the prefix.
      locations = mkOption {
        type = types.attrsOf (types.strMatching "http://[^/]+/.*");
        default = { };
      };
      # File of nginx map lines, `"Bearer <token>" <client>;` (a sops template, never the nix store). `locations`
      # then answer 401 without a listed token, the upstream never sees it and the access log names the client.
      # nginx matches them case-insensitively, so use hex tokens. A missing file stops nginx, an empty one is all 401.
      tokens = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      # nginx's client_max_body_size for the site, e.g. "1g" for `locations` that take uploads.
      maxBodySize = mkOption {
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
      assertion = (s.root == null || s.upstream == null) && (s.https -> s.domains != [ ] && s.address == null);
      message = "web: site ${name} has both root and upstream, or https without domains on every address";
    }) cfg.sites;

    # No account email: Let's Encrypt no longer sends expiry mail, and it would end up in the nix store.
    security.acme.acceptTerms = lib.mkIf https true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;

      virtualHosts = lib.mapAttrs (name: s: {
        inherit (s) root default;
        serverName = if s.domains == [ ] then "_" else lib.head s.domains;
        serverAliases = lib.drop 1 s.domains;
        listen = lib.optional (s.address != null) {
          addr = s.address;
          port = 80;
        };
        enableACME = s.https;
        forceSSL = s.https;
        locations = {
          "/" = if s.upstream != null then {
            proxyPass = s.upstream;
            proxyWebsockets = true;
          } else if s.root != null then {
            tryFiles = "$uri $uri/ =404";
          } else {
            return = "404";
          };
        } // lib.mapAttrs (prefix: url: {
          proxyPass = "http://${upstreamName name prefix}${(parse url).path}";
          extraConfig = lib.optionalString (s.tokens != null)
            (builtins.replaceStrings [ "@client@" ] [ (clientVar name) ] (builtins.readFile ./config/token-check.conf))
            + builtins.replaceStrings [ "@path@" "@prefix@" ] [ (parse url).path prefix ]
              (builtins.readFile ./config/proxy-location.conf);
        }) s.locations;
        extraConfig = lib.optionalString (s.tokens != null) "access_log /var/log/nginx/access.log ${clientVar name};\n"
          + lib.optionalString (s.maxBodySize != null) "client_max_body_size ${s.maxBodySize};\n";
      }) cfg.sites;

      upstreams = lib.mkMerge (lib.mapAttrsToList (name: s: lib.mapAttrs' (prefix: url:
        lib.nameValuePair (upstreamName name prefix) {
          servers.${(parse url).server} = { };
          extraConfig = "keepalive 8;";
        }) s.locations) cfg.sites);

      # A "Bearer <64 hex>" key is past the 64 byte default bucket, nginx refuses to start.
      mapHashBucketSize = lib.mkIf (lib.any (s: s.tokens != null) (lib.attrValues cfg.sites)) 128;

      commonHttpConfig = lib.concatStrings (lib.mapAttrsToList (name: s:
        builtins.replaceStrings [ "@client@" "@tokens@" ] [ (clientVar name) s.tokens ] (builtins.readFile ./config/token-map.conf))
        (lib.filterAttrs (_: s: s.tokens != null) cfg.sites));
    };

    systemd.tmpfiles.rules = lib.mapAttrsToList (_: s: "d ${s.root} 0755 admin users -")
      (lib.filterAttrs (_: s: s.root != null) cfg.sites);

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional https 443;
  };
}
