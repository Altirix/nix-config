{ config, lib, pkgs, nodes, ... }:

# Kanidm, the lab's SSO (README.md). A front door (gateway.nix on the edge) serves it at https://<domain> and signs
# browsers in for its `sso` sites, whose callbacks this server learns from that host's config. Groups, people and
# OAuth2 clients are provisioned from here on every start, credentials are each person's own.
let
  cfg = config.homelab.sso.server;
  inherit (lib) mkOption types;

  # The domains of the sites the gateways sign browsers in for. oauth2-proxy needs the web client even before there
  # is one (oauth sites only), its callback on the server's own domain then goes unused.
  ssoDomains = lib.concatMap (host: map (s: lib.head s.domains)
    (lib.attrValues (lib.filterAttrs (_: s: s.sso) nodes.${host}.config.homelab.web.sites))) cfg.gateways;
  domains = if ssoDomains == [ ] then [ cfg.domain ] else ssoDomains;
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.sso.server = {
    enable = lib.mkEnableOption "Kanidm";

    # Never change it once installed: passkeys and names (user@<domain>) are bound to it.
    domain = mkOption { type = types.str; };

    # The hosts fronting it (gateway.nix), whose `sso` sites get the web client's callbacks.
    gateways = mkOption { type = types.listOf types.str; };

    # Front doors' addresses, whose X-Forwarded-For is trusted so logs and rate limits see the client.
    proxies = mkOption { type = types.listOf types.str; };

    # This server's own certificate, copied back once it made it (README.md), the only one the gateway accepts.
    certificate = mkOption {
      type = types.nullOr types.path;
      default = null;
    };

    # Who may sign in: web_users for the gateway's sso sites, mcp_users for MCP (with `mcp`).
    people = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          displayName = mkOption { type = types.str; };
          groups = mkOption {
            type = types.listOf types.str;
            default = [ "web_users" ];
          };
        };
      });
      default = { };
    };

    # The clients MCP's OAuth sign-in needs (modules/services/mcp/README.md), ready before mcp.peacocks.me switches
    # from bearer tokens.
    mcp = lib.mkEnableOption "Kanidm's clients for MCP: mcp (Claude's connectors) and mcp-cli (Claude Code)";
  };

  config = lib.mkIf cfg.enable {
    services.kanidm = {
      package = pkgs.kanidm_1_11;

      server = {
        enable = true;
        settings = {
          inherit (cfg) domain;
          origin = "https://${cfg.domain}";
          bindaddress = "0.0.0.0:8443";
          tls_chain = "/var/lib/kanidm-cert/chain.pem";
          tls_key = "/var/lib/kanidm-cert/key.pem";
          http_client_address_info.x-forward-for = cfg.proxies;
          # /var/lib/kanidm/backups, nightly.
          online_backup.versions = 7;
        };
      };

      provision = {
        enable = true;

        groups = { web_users = { }; } // lib.optionalAttrs cfg.mcp { mcp_users = { }; };

        persons = lib.mapAttrs (_: p: { inherit (p) displayName groups; }) cfg.people;

        systems.oauth2 = {
          # oauth2-proxy on the gateway, signing browsers in for every `sso` site there (one callback each). Its
          # secret is Kanidm's own, README.md.
          web = {
            displayName = "Lab sites";
            originUrl = map (d: "https://${d}/oauth2/callback") domains;
            originLanding = "https://${lib.head domains}/";
            scopeMaps.web_users = [ "openid" "profile" ];
            # preferred_username "<name>" instead of "<name>@<domain>", it names the user in the gateway's logs.
            preferShortUsername = true;
          };
        } // lib.optionalAttrs cfg.mcp {
          # Claude's connectors (claude.ai, the apps). Its secret is Kanidm's own, README.md.
          mcp = {
            displayName = "MCP";
            originUrl = [ "https://claude.ai/api/mcp/auth_callback" "https://claude.com/api/mcp/auth_callback" ];
            originLanding = "https://claude.ai/";
            scopeMaps.mcp_users = [ "openid" ];
          };
          # Claude Code, PKCE without a secret and a callback on any localhost port.
          mcp-cli = {
            displayName = "MCP (Claude Code)";
            public = true;
            enableLocalhostRedirects = true;
            originUrl = "http://localhost/callback";
            originLanding = "http://localhost/";
            scopeMaps.mcp_users = [ "openid" ];
          };
        };
      };
    };

    # kanidmd won't start without TLS: a self-signed certificate for the origin's name, good for ten years and
    # remade only within 30 days of expiring (or if it's missing). The gateway accepts only this one (`certificate`),
    # so a new one needs copying again. Not `kanidmd cert-generate`, its certificate expires after five days. A leaf
    # (CA:FALSE, serverAuth): Rust clients like the kanidm CLI refuse a CA certificate as the server's.
    systemd.services.kanidm-cert = {
      requiredBy = [ "kanidm.service" ];
      before = [ "kanidm.service" ];
      path = [ pkgs.openssl ];
      script = ''
        [ -e key.pem ] && [ -e chain.pem ] && openssl x509 -checkend 2592000 -noout -in chain.pem && exit 0
        openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 3650 \
          -subj /CN=${cfg.domain} -addext subjectAltName=DNS:${cfg.domain} \
          -addext basicConstraints=critical,CA:FALSE -addext keyUsage=critical,digitalSignature \
          -addext extendedKeyUsage=serverAuth -keyout key.pem -out chain.pem
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "kanidm";
        Group = "kanidm";
        UMask = "0077";
        StateDirectory = "kanidm-cert";
        StateDirectoryMode = "0700";
        WorkingDirectory = "/var/lib/kanidm-cert";
      };
    };

    # kanidmd for recovering accounts (README.md), the module only runs it from its unit.
    environment.systemPackages = [ config.services.kanidm.package ];

    homelab.publish.upstream = {
      port = 8443;
      https = true;
      inherit (cfg) certificate;
    };

    # Only on the labs bridge, the router lets the gateway in.
    networking.firewall.allowedTCPPorts = [ 8443 ];
  };
}
