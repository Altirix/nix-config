{ config, lib, pkgs, nodes, ... }:

# nginx sites, each either serves files from `root` or proxies to an `upstream` (usually across the tunnel),
# with neither `/` is a 404 and only `locations` answer. A site can instead take what other hosts publish (`from`,
# publish.nix), the way a forward names its peer: they say what they serve, the site says where and who gets in.
# Files in `root` aren't managed by nix, they're copied in (rsync as admin).
let
  cfg = config.homelab.web;
  inherit (lib) mkOption types;

  # http://10.100.1.11:8106/mcp -> { server = "10.100.1.11:8106"; path = "/mcp"; }, for upstream blocks with keepalive.
  parse = url:
    let m = builtins.match "http://([^/]+)(/.*)" url;
    in { server = lib.elemAt m 0; path = lib.elemAt m 1; };
  upstreamName = name: prefix: "${name}${lib.replaceStrings [ "/" "." ] [ "_" "_" ] (lib.removeSuffix "/" prefix)}";

  accessLog = "syslog:server=unix:/dev/log,tag=nginx_access,nohostname";

  # nginx variable holding the client a site's token belongs to.
  clientVar = name: "web_client_${lib.replaceStrings [ "-" ] [ "_" ] name}";

  # config/<file> with @name@ placeholders filled in.
  snippet = file: vars: builtins.replaceStrings (map (n: "@${n}@") (lib.attrNames vars)) (lib.attrValues vars)
    (builtins.readFile ./config/${file});

  ssoCheck = s: lib.optionalString (s.sso != null) (builtins.readFile ./config/sso-check.conf);

  # The site's access log, naming the client or user where there is one.
  siteLog = s: "access_log ${accessLog}${lib.optionalString (s.oauth || s.sso != null || s.tokens != null) " user"};\n";

  # What every proxied location carries in place of nixpkgs' recommended headers (the http-level rest of
  # recommendedProxySettings, HTTP/1.1 to upstreams and timeouts, still applies).
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
      # Hosts whose homelab.publish this site serves: their locations, and their upstream, certificate and body
      # size for whatever the site doesn't set itself.
      from = mkOption {
        type = types.listOf types.str;
        default = [ ];
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
      # Clients with a bearer token each, read from <site>-token-<client> in the host's secrets.yaml (hex: nginx
      # matches them case-insensitively). `locations` answer 401 without one, the upstream never sees it and the
      # access log names the client. Drop a client (and its secret) to revoke it, edit the secret to rotate it.
      tokens = mkOption {
        type = types.nullOr (types.listOf types.str);
        default = null;
      };
      # `locations` are an OAuth protected resource (MCP authorization): 401 without an access token from one of
      # `oauth`'s issuers, pointing at /.well-known/oauth-protected-resource/<path> (RFC 9728) for where to get
      # one. oauth2-proxy checks the token, the upstream never sees it and the access log names the user. Ready
      # for MCP to switch to from `tokens`, unused until then.
      oauth = mkOption {
        type = types.bool;
        default = false;
      };
      # Browser sign-in in front of the whole site (`/` and `locations`), for sites without their own login: no
      # session, the browser is sent to the issuer (`oauth.issuer`) and back. Who may sign in is the issuer's call.
      # Only the session cookie counts, bearer tokens don't. The access log names the user.
      # `true` or { title; groups; }: its own OIDC client at `homelab.web.sso.issuer` (ssoClients), named
      # <host>-<site>, signing in members of `groups`. The issuer lists it as `title` (the first domain).
      sso = mkOption {
        type = types.coercedTo types.bool (on: if on then { } else null) (types.nullOr (types.submodule {
          options = {
            title = mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            groups = mkOption {
              type = types.listOf types.str;
              default = [ "web_users" ];
            };
          };
        }));
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

  # A site's `from` hosts: their labs address and what they publish (hosts without the options have neither).
  publishedBy = s: map (host: {
    inherit host;
    address = nodes.${host}.config.homelab.labs.address or null;
    p = nodes.${host}.config.homelab.publish or { locations = { }; upstream = null; maxBodySize = null; };
  }) s.from;

  # A site with what its `from` hosts publish filled in, at their labs address.
  resolve = s:
    let
      published = publishedBy s;
      upstreams = lib.filter (x: x.p.upstream != null) published;
      upstreamUrl = x: let u = x.p.upstream; in
        "${if u.https then "https" else "http"}://${x.address}${lib.optionalString (u.port != (if u.https then 443 else 80)) ":${toString u.port}"}";
      first = f: list: if list == [ ] then null else f (lib.head list);
    in
    s // {
      locations = lib.foldl' (all: x: all // lib.mapAttrs (_: l: "http://${x.address}:${toString l.port}${l.path}")
        x.p.locations) { } published // s.locations;
      upstream = if s.upstream != null then s.upstream else first upstreamUrl upstreams;
      upstreamCertificate = if s.upstreamCertificate != null then s.upstreamCertificate
        else first (x: x.p.upstream.certificate) upstreams;
      maxBodySize = lib.findFirst (v: v != null) null ([ s.maxBodySize ] ++ map (x: x.p.maxBodySize) published);
    };
  sites = lib.mapAttrs (_: resolve) cfg.sites;

  # What's wrong with a site's `from`: a host without a labs address or that publishes nothing, a prefix two of them
  # publish, more than one whole site, or body sizes they disagree on.
  fromProblems = name: s:
    let
      published = publishedBy s;
      prefixes = lib.concatMap (x: lib.attrNames x.p.locations) published;
    in
    map (x: "web: site ${name} takes from ${x.host}, which has no homelab.labs.address")
      (lib.filter (x: x.address == null) published)
    ++ map (x: "web: site ${name} takes from ${x.host}, which publishes nothing")
      (lib.filter (x: x.p.locations == { } && x.p.upstream == null) published)
    ++ map (pre: "web: site ${name}'s hosts all publish ${pre}")
      (lib.unique (lib.filter (pre: lib.count (q: q == pre) prefixes > 1) prefixes))
    ++ lib.optional (lib.length (lib.filter (x: x.p.upstream != null) published) > 1)
      "web: site ${name}'s hosts each publish a whole site"
    ++ lib.optional (lib.length (lib.unique (lib.filter (v: v != null) (map (x: x.p.maxBodySize) published))) > 1)
      "web: site ${name}'s hosts disagree on maxBodySize";
  tokenSites = lib.filterAttrs (_: s: s.tokens != null) sites;
  tokenSecret = name: client: "${name}-token-${client}";

  https = lib.any (s: s.https) (lib.attrValues sites);
  oauth = lib.any (s: s.oauth) (lib.attrValues sites);
  ssoSites = lib.filterAttrs (_: s: s.sso != null) sites;
  tokens = tokenSites != { };
  logsUser = oauth || ssoSites != { } || tokens;

  # oauth2-proxy instances on loopback, one per sso site (its own client and sessions) and one checking the bearer
  # tokens of oauth sites, a port each from 4180.
  proxies = lib.attrNames ssoSites ++ lib.optional oauth "oauth";
  proxyAddress = name: "http://127.0.0.1:${toString (4180 + lib.lists.findFirstIndex (n: n == name) 0 proxies)}";
  proxyUnit = name: "oauth2-proxy-${name}";
  ssoClient = name: "${config.networking.hostName}-${name}";
  ssoSecret = name: "sso-${name}-secret";

  # What every instance shares.
  proxyArgs = name: [
    "--provider=oidc"
    "--http-address=${proxyAddress name}"
    "--upstream=static://202"
    "--cookie-secret-file=%d/cookie-secret"
    "--email-domain=*"
    "--set-xauthrequest=true"
    # Its request log would carry the callback's authorization codes into the journal and the logs VM, nginx logs
    # requests already (without /oauth2/, sso-server.conf). Sign-ins still log as auth lines.
    "--request-logging=false"
    "--reverse-proxy=true"
    "--trusted-proxy-ip=127.0.0.1"
    # Access tokens carry no email, without this it asks the userinfo endpoint and fails.
    "--skip-claims-from-profile-url=true"
    # Kanidm sends no email for people without one, the session is named after the user instead.
    "--oidc-email-claim=preferred_username"
    # Kanidm requires PKCE.
    "--code-challenge-method=S256"
    "--cookie-samesite=lax"
  ];

  # Signing browsers in for one sso site.
  ssoArgs = name: [
    "--oidc-issuer-url=${cfg.sso.issuer}${ssoClient name}"
    "--client-id=${ssoClient name}"
    "--client-secret-file=%d/client-secret"
    "--scope=openid profile"
    # Kanidm asks for consent itself, once per client.
    "--approval-prompt=auto"
    # Sessions are renewed with the refresh token this often, someone removed from the issuer's group (or signed
    # out there) loses theirs at the next renewal instead of when the cookie runs out.
    "--cookie-refresh=15m"
  ];

  # Checking oauth sites' bearer tokens: signature, issuer, audience (the client id) and expiry, offline against the
  # issuers' keys. It never signs a browser in, so its client secret is never used.
  oauthArgs = [
    "--oidc-issuer-url=${cfg.oauth.issuer}"
    "--client-id=${cfg.oauth.clientId}"
    "--client-secret=unused"
    "--skip-jwt-bearer-tokens=true"
    # A bad or expired token is a 401 (clients refresh on it), not a 403.
    "--bearer-token-login-fallback=true"
  ] ++ lib.mapAttrsToList (issuer: client: "--extra-jwt-issuers=${issuer}=${client}") cfg.oauth.extraIssuers;
in
{
  options.homelab.web = {
    enable = lib.mkEnableOption "nginx sites";

    sites = mkOption {
      type = types.attrsOf site;
      default = { };
    };

    # Sign-in for `sso` sites, an oauth2-proxy each with its own client. Their secrets are sso-<site>-secret in the
    # host's secrets.yaml, and every instance seals its cookies with oauth2-proxy-cookie-secret there (32 bytes).
    sso = {
      # A client's issuer without the client, e.g. Kanidm's https://auth.example.com/oauth2/openid/.
      issuer = mkOption { type = types.str; };
    };

    # The clients `sso` sites sign in with, client -> { title; groups; domain; }, for the issuer to provide.
    ssoClients = mkOption {
      readOnly = true;
      default = lib.mapAttrs' (name: s: lib.nameValuePair (ssoClient name) {
        title = if s.sso.title != null then s.sso.title else lib.head s.domains;
        inherit (s.sso) groups;
        domain = lib.head s.domains;
      }) ssoSites;
    };

    # The client whose access tokens open `oauth` sites. Who gets a token is the issuer's call.
    oauth = {
      # e.g. Kanidm's https://auth.example.com/oauth2/openid/<client>, also where `oauth` sites send clients
      # (RFC 9728) with the scopes they ask for.
      issuer = mkOption { type = types.str; };
      clientId = mkOption { type = types.str; };
      scopes = mkOption {
        type = types.listOf types.str;
        default = [ "openid" ];
      };
      # More clients whose bearer tokens count, issuer -> client id.
      extraIssuers = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (name: s: {
      assertion = (s.root == null || s.upstream == null) && (s.https -> s.domains != [ ] && s.address == null)
        && (s.oauth || s.sso != null -> s.https) && lib.count lib.id [ s.oauth (s.sso != null) (s.tokens != null) ] <= 1
        && (s.upstreamCertificate != null -> s.upstream != null && lib.hasPrefix "https://" s.upstream && s.domains != [ ]);
      message = "web: site ${name} has both root and upstream, https without domains on every address, oauth or sso without https, more than one of tokens/oauth/sso, or upstreamCertificate without an https upstream and domains";
    }) sites ++ [{
      assertion = lib.allUnique proxies;
      message = "web: an sso site named oauth clashes with the oauth sites' oauth2-proxy";
    }] ++ lib.mapAttrsToList (name: s: {
      assertion = fromProblems name s == [ ];
      message = lib.concatStringsSep "\n" (fromProblems name s);
    }) cfg.sites;

    # No account email: Let's Encrypt no longer sends expiry mail, and it would end up in the nix store.
    security.acme.acceptTerms = lib.mkIf https true;

    services.nginx = {
      enable = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;
      recommendedTlsSettings = true;
      recommendedProxySettings = true;

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
          "/" = if s.upstream != null then proxied // {
            proxyPass = s.upstream;
            proxyWebsockets = true;
            extraConfig = proxied.extraConfig + ssoCheck s + lib.optionalString (s.upstreamCertificate != null)
              (snippet "upstream-tls.conf" { certificate = "${s.upstreamCertificate}"; domain = lib.head s.domains; });
          } else if s.root != null then {
            tryFiles = "$uri $uri/ =404";
          } else {
            return = "404";
          };
        } // lib.mapAttrs (prefix: url: proxied // {
          proxyPass = "http://${upstreamName name prefix}${(parse url).path}";
          extraConfig = proxied.extraConfig + ssoCheck s
            + lib.optionalString (s.tokens != null) (snippet "token-check.conf" { client = clientVar name; })
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
        extraConfig = lib.optionalString (s.oauth || s.sso != null || s.tokens != null) (siteLog s)
          + lib.optionalString s.oauth (snippet "oauth-server.conf" {
              proxy = proxyAddress "oauth";
              domain = lib.head s.domains;
              scopes = lib.concatStringsSep " " cfg.oauth.scopes;
            })
          + lib.optionalString (s.sso != null) (snippet "sso-server.conf" { proxy = proxyAddress name; })
          + lib.optionalString (s.maxBodySize != null) "client_max_body_size ${s.maxBodySize};\n";
      }) sites;

      upstreams = lib.mkMerge (lib.mapAttrsToList (name: s: lib.mapAttrs' (prefix: url:
        lib.nameValuePair (upstreamName name prefix) {
          servers.${(parse url).server} = { };
          extraConfig = "keepalive 8;";
        }) s.locations) sites);

      # Access logs go to the journal (SYSLOG_IDENTIFIER=nginx_access) and on to the logs VM, not a file. On tokens,
      # oauth and sso sites they name the client or user (the token's client, its sub, the session's username).
      commonHttpConfig = ''
        access_log ${accessLog};
      '' + lib.optionalString logsUser ''
        log_format user '$remote_addr $web_user [$time_local] "$request" $status $body_bytes_sent $request_time';
      '' + lib.concatStrings (lib.mapAttrsToList (name: _:
        snippet "token-map.conf" { client = clientVar name; tokens = config.sops.templates."${name}-tokens".path; }) tokenSites);

      # A "Bearer <64 hex>" key is past the 64 byte default bucket, nginx refuses to start.
      mapHashBucketSize = lib.mkIf tokens 128;
    };

    # From the host's secrets.yaml (sops.defaultSopsFile), only this host can read them.
    sops.secrets = lib.mkMerge (lib.mapAttrsToList (name: s:
      lib.genAttrs (map (tokenSecret name) s.tokens) (key: { inherit key; })) tokenSites
      ++ lib.mapAttrsToList (name: _: { ${ssoSecret name}.restartUnits = [ "${proxyUnit name}.service" ]; }) ssoSites
      ++ lib.optional (proxies != [ ]) {
        oauth2-proxy-cookie-secret.restartUnits = map (name: "${proxyUnit name}.service") proxies;
      });

    sops.templates = lib.mapAttrs' (name: s: lib.nameValuePair "${name}-tokens" {
      content = lib.concatMapStrings (client: ''
        "Bearer ${config.sops.placeholder.${tokenSecret name client}}" ${client};
      '') s.tokens;
      owner = "nginx";
      reloadUnits = [ "nginx.service" ];
    }) tokenSites;

    systemd.services = lib.listToAttrs (map (name: lib.nameValuePair (proxyUnit name) {
      description = "oauth2-proxy for ${name}";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.oauth2-proxy} ${lib.escapeShellArgs
          (proxyArgs name ++ (if ssoSites ? ${name} then ssoArgs name else oauthArgs))}";
        DynamicUser = true;
        LoadCredential = [ "cookie-secret:${config.sops.secrets.oauth2-proxy-cookie-secret.path}" ]
          ++ lib.optional (ssoSites ? ${name}) "client-secret:${config.sops.secrets.${ssoSecret name}.path}";
        # It exits while the issuer is unreachable (discovery at start), don't hit the start limit waiting for it.
        Restart = "always";
        RestartSec = 5;
      };
    }) proxies);

    systemd.tmpfiles.rules = lib.mapAttrsToList (_: s: "d ${s.root} 0755 admin users -")
      (lib.filterAttrs (_: s: s.root != null) sites);

    networking.firewall.allowedTCPPorts = [ 80 ] ++ lib.optional https 443;
  };
}
