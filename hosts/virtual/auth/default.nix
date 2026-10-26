{ config, pkgs, ... }:

# Kanidm, SSO for the lab at https://auth.peacocks.me (through the edge, hosts/edge/ionos-de/auth.nix). Groups,
# persons and OAuth2 clients are provisioned from here, credentials are each person's own (README.md).
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  services.kanidm = {
    package = pkgs.kanidm_1_11;

    server = {
      enable = true;
      settings = {
        # Never change these once installed: passkeys and names (user@auth.peacocks.me) are bound to the domain.
        domain = "auth.peacocks.me";
        origin = "https://auth.peacocks.me";
        bindaddress = "0.0.0.0:8443";
        tls_chain = "/var/lib/kanidm-cert/chain.pem";
        tls_key = "/var/lib/kanidm-cert/key.pem";
        # The edge's tunnel address, so logs and rate limits see the client instead.
        http_client_address_info.x-forward-for = [ "10.0.0.1" ];
        # /var/lib/kanidm/backups, nightly.
        online_backup.versions = 7;
      };
    };

    provision = {
      enable = true;

      # Who may sign in to the MCP servers (hosts/edge/ionos-de/mcp.nix).
      groups.mcp_users = { };

      persons.altirix = {
        displayName = "Altirix";
        groups = [ "mcp_users" ];
      };

      systems.oauth2 = {
        # Claude's connectors (claude.ai, the apps). Its secret is Kanidm's own, see README.md.
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

  # kanidmd won't start without TLS. Its own CA and a certificate for the origin's name, made once; the edge
  # doesn't check them.
  systemd.services.kanidm-cert = {
    requiredBy = [ "kanidm.service" ];
    before = [ "kanidm.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "kanidm";
      Group = "kanidm";
      StateDirectory = "kanidm-cert";
      StateDirectoryMode = "0700";
      ExecStart = "${config.services.kanidm.package}/bin/kanidmd cert-generate -c /etc/kanidm/server.toml";
    };
  };

  # Only on the labs bridge, the router lets the edge in.
  networking.firewall.allowedTCPPorts = [ 8443 ];
}
