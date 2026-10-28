{ config, lib, ... }:

# nginx sites, each either serves files from `root` or proxies to an `upstream` (usually across the tunnel),
# with neither `/` is a 404 and only `locations` answer.
# Files in `root` aren't managed by nix, they're copied in (rsync as admin).
let
  cfg = config.homelab.web;
  inherit (lib) mkOption types;

  # http://10.100.1.11:8106/mcp -> { server = "10.100.1.11:8106"; path = "/mcp"; }, for upstream blocks with keepalive.
  parse = url:
    let m = builtins.match "http://([^/]+)(/.*)" url;
    in { server = lib.elemAt m 0; path = lib.elemAt m 1; };
  upstreamName = name: prefix: "${name}${lib.replaceStrings [ "/" "." ] [ "_" "_" ] (lib.removeSuffix "/" prefix)}";

  # config/<file> with @name@ placeholders filled in.
  snippet = file: vars: builtins.replaceStrings (map (n: "@${n}@") (lib.attrNames vars)) (lib.attrValues vars)
    (builtins.readFile ./config/${file});

  # What every proxied location carries in place of nixpkgs' recommended headers.
  proxied = {
    recommendedProxySettings = false;
    extraConfig = builtins.readFile ./config/proxy-headers.conf;
  };

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
      # An https `upstream`'s own (self-signed) certificate, the only one accepted, issued for the site's first
      # domain. null doesn't check it.
      upstreamCertificate = mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      # More path prefixes, each proxied to its own upstream with the prefix swapped for the upstream's path:
      # "/time/mcp" = "http://10.100.1.11:8106/mcp". Unbuffered with long timeouts so streams pass straight
      # through (uploads too), redirects to the upstream's path are pointed back under the prefix.
      locations = mkOption {
        type = types.attrsOf (types.strMatching "http://[^/]+/.*");
        default = { };
      };
      # `locations` are an OAuth protected resource (MCP authorization): 401 without an access token from one of
      # `oauth`'s issuers, pointing at /.well-known/oauth-protected-resource/<path> (RFC 9728) for where to get
      # one. oauth2-proxy checks the token, the upstream never sees it and the access log names the user.
      oauth = mkOption {
        type = types.bool;
        default = false;
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
  oauth = lib.any (s: s.oauth) (lib.attrValues cfg.sites);
in
{
  options.homelab.web = {
    enable = lib.mkEnableOption "nginx sites";

    sites = mkOption {
      type = types.attrsOf site;
      default = { };
    };

    # oauth2-proxy on loopback, checking the bearer tokens of sites with `oauth`: signature, issuer, audience
    # (the client id) and expiry, offline against the issuer's keys. Who gets a token is the issuer's call.
    oauth = {
      # The issuer sites advertise, and its client, e.g. Kanidm's https://auth.example.com/oauth2/openid/<client>.
      issuer = mkOption { type = types.str; };
      clientId = mkOption { type = types.str; };
      # Scopes clients ask for.
      scopes = mkOption {
        type = types.listOf types.str;
        default = [ "openid" ];
      };
      # More clients whose tokens count, issuer -> client id.
      extraIssuers = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
      # sops secrets: the client's secret and a 32 character cookie secret. Neither is used (no cookie logins),
      # oauth2-proxy won't start without them.
      clientSecretFile = mkOption { type = types.str; };
      cookieSecretFile = mkOption { type = types.str; };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: s: {
      assertion = (s.root == null || s.upstream == null) && (s.https -> s.domains != [ ] && s.address == null)
        && (s.oauth -> s.https) && (s.upstreamCertificate != null -> s.upstream != null && s.domains != [ ]);
      message = "web: site ${name} has both root and upstream, https without domains on every address, oauth without https, or upstreamCertificate without an upstream and domains";
    }) cfg.sites;

    # No account email: Let's Encrypt no longer sends expiry mail, and it would end up in the nix store.
    security.acme.acceptTerms = lib.mkIf https true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
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
          "/" = if s.upstream != null then lib.recursiveUpdate proxied {
            proxyPass = s.upstream;
            proxyWebsockets = true;
            extraConfig = proxied.extraConfig + lib.optionalString (s.upstreamCertificate != null)
              (snippet "upstream-tls.conf" { certificate = "${s.upstreamCertificate}"; domain = lib.head s.domains; });
          } else if s.root != null then {
            tryFiles = "$uri $uri/ =404";
          } else {
            return = "404";
          };
        } // lib.mapAttrs (prefix: url: proxied // {
          proxyPass = "http://${upstreamName name prefix}${(parse url).path}";
          extraConfig = proxied.extraConfig
            + lib.optionalString s.oauth (snippet "oauth-check.conf" { inherit prefix; })
            + snippet "proxy-location.conf" { inherit prefix; inherit (parse url) path; };
        }) s.locations
        # Each location's RFC 9728 metadata, the resource is the location itself.
        // lib.optionalAttrs s.oauth (lib.mapAttrs' (prefix: _:
          lib.nameValuePair "= /.well-known/oauth-protected-resource${prefix}" {
            extraConfig = ''
              default_type application/json;
              return 200 '${builtins.toJSON {
                resource = "https://${lib.head s.domains}${prefix}";
                authorization_servers = [ cfg.oauth.issuer ];
                scopes_supported = cfg.oauth.scopes;
                bearer_methods_supported = [ "header" ];
              }}';
            '';
          }) s.locations);
        extraConfig = lib.optionalString s.oauth ("access_log /var/log/nginx/access.log oauth;\n"
            + snippet "oauth-server.conf" {
              proxy = config.services.oauth2-proxy.httpAddress;
              domain = lib.head s.domains;
              scopes = lib.concatStringsSep " " cfg.oauth.scopes;
            })
          + lib.optionalString (s.maxBodySize != null) "client_max_body_size ${s.maxBodySize};\n";
      }) cfg.sites;

      upstreams = lib.mkMerge (lib.mapAttrsToList (name: s: lib.mapAttrs' (prefix: url:
        lib.nameValuePair (upstreamName name prefix) {
          servers.${(parse url).server} = { };
          extraConfig = "keepalive 8;";
        }) s.locations) cfg.sites);

      # Access log lines of oauth sites name the user (the token's sub).
      commonHttpConfig = lib.optionalString oauth ''
        log_format oauth '$remote_addr $oauth_user [$time_local] "$request" $status $body_bytes_sent $request_time';
      '';
    };

    # Into the journal and on to the logs VM (modules/system/logs.nix).
    homelab.logs.files.nginx-access = { path = "/var/log/nginx/access.log"; group = "nginx"; };

    services.oauth2-proxy = lib.mkIf oauth {
      enable = true;
      provider = "oidc";
      oidcIssuerUrl = cfg.oauth.issuer;
      clientID = cfg.oauth.clientId;
      inherit (cfg.oauth) clientSecretFile;
      cookie.secretFile = cfg.oauth.cookieSecretFile;
      email.domains = [ "*" ];
      setXauthrequest = true;
      reverseProxy = true;
      trustedProxyIP = [ "127.0.0.1" ];
      extraConfig = {
        skip-jwt-bearer-tokens = true;
        # A bad or expired token is a 401 (clients refresh on it), not a 403.
        bearer-token-login-fallback = true;
        extra-jwt-issuers = lib.mapAttrsToList (issuer: client: "${issuer}=${client}") cfg.oauth.extraIssuers;
        # Access tokens carry no email, without this it asks the userinfo endpoint and fails.
        skip-claims-from-profile-url = true;
      };
    };

    # It exits while the issuer is unreachable (discovery at start), don't hit the start limit waiting for it.
    systemd.services.oauth2-proxy.serviceConfig.RestartSec = lib.mkIf oauth 5;

    systemd.tmpfiles.rules = lib.mapAttrsToList (_: s: "d ${s.root} 0755 admin users -")
      (lib.filterAttrs (_: s: s.root != null) cfg.sites);

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional https 443;
  };
}
