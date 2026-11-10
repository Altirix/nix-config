{ config, lib, pkgs, nodes, ... }:

# Kanidm, the lab's SSO (README.md). A front door (gateway.nix on the edge) serves it at https://<domain> and signs
# browsers in for its `sso` sites, a client each, made from that host's config. Groups, people and OAuth2 clients are
# provisioned from here on every start, credentials are each person's own.
let
  cfg = config.homelab.sso.server;
  inherit (lib) mkOption types;

  # The gateways' sso sites, client -> { title; groups; domain; }.
  siteClients = lib.foldl' (all: host: all // nodes.${host}.config.homelab.web.ssoClients) { } cfg.gateways;
  # The groups sites and `mcp` use, and web_users (sso sites' default) even before one does. Kanidm's module
  # refuses people in any other, a typo fails the build.
  groups = lib.unique ([ "web_users" ] ++ lib.concatMap (c: c.groups) (lib.attrValues siteClients)
    ++ lib.optional cfg.mcp "mcp_users");
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

    # Its certificate, the only one the gateways accept: a self-signed leaf for `domain` (README.md), its key
    # kanidm-tls-key in the host's secrets.yaml. Change both and deploy this host and its gateways.
    certificate = mkOption { type = types.path; };

    # The site clients' secrets, keyed by client (<gateway>-<site>), set in Kanidm from here and read by the
    # gateways: one sops file for this server and its gateways (README.md).
    secretsFile = mkOption { type = types.path; };

    # Who may sign in: the groups the gateway's sso sites name (web_users unless they say), mcp_users for MCP (with
    # `mcp`).
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
      # Its secret-provisioning patches take idm_admin's password from a file.
      package = pkgs.kanidm_1_11.withSecretProvisioning;

      server = {
        enable = true;
        settings = {
          inherit (cfg) domain;
          origin = "https://${cfg.domain}";
          bindaddress = "0.0.0.0:8443";
          # Its module wants it outside the store, it's public all the same.
          tls_chain = "/etc/kanidm/chain.pem";
          tls_key = config.sops.secrets.kanidm-tls-key.path;
          http_client_address_info.x-forward-for = cfg.proxies;
          # /var/lib/kanidm/backups, nightly.
          online_backup.versions = 7;
        };
      };

      provision = {
        enable = true;
        # Set on every start, otherwise provisioning resets it to a random one each time.
        idmAdminPasswordFile = config.sops.secrets.kanidm-idm-admin-password.path;

        groups = lib.genAttrs groups (_: { });

        persons = lib.mapAttrs (_: p: { inherit (p) displayName groups; }) cfg.people;

        # Each sso site's oauth2-proxy on the gateway, the site's tile in Kanidm's app list, with its secret from
        # `secretsFile`.
        systems.oauth2 = lib.mapAttrs (client: c: {
          basicSecretFile = config.sops.secrets."kanidm-client-${client}".path;
          displayName = c.title;
          originUrl = "https://${c.domain}/oauth2/callback";
          originLanding = "https://${c.domain}/";
          scopeMaps = lib.genAttrs c.groups (_: [ "openid" "profile" ]);
          # preferred_username "<name>" instead of "<name>@<domain>", it names the user in the gateway's logs.
          preferShortUsername = true;
        }) siteClients // lib.optionalAttrs cfg.mcp {
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

    environment.etc."kanidm/chain.pem".source = cfg.certificate;
    # A new certificate restarts it, as a new key does (sops).
    systemd.services.kanidm.restartTriggers = [ cfg.certificate ];

    # From the host's secrets.yaml (sops.defaultSopsFile), README.md, and the clients' from `secretsFile`.
    sops.secrets = {
      kanidm-idm-admin-password = {
        owner = "kanidm";
        restartUnits = [ "kanidm.service" ];
      };
      kanidm-tls-key = {
        owner = "kanidm";
        restartUnits = [ "kanidm.service" ];
      };
    } // lib.mapAttrs' (client: _: lib.nameValuePair "kanidm-client-${client}" {
      sopsFile = cfg.secretsFile;
      key = client;
      owner = "kanidm";
      restartUnits = [ "kanidm.service" ];
    }) siteClients;

    homelab.publish.upstream = {
      port = 8443;
      https = true;
      inherit (cfg) certificate;
    };

    # Only on the labs bridge, the router lets the gateway in.
    networking.firewall.allowedTCPPorts = [ 8443 ];
  };
}
