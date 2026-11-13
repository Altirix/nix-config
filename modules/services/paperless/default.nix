{ config, lib, pkgs, ... }:

# Paperless-ngx, documents for people and LLMs, published (homelab.publish) for a front door with sign-in
# (docs.peacocks.me). Two ways in, through nginx here: port 80 for the front door, whose sign-in names the user in
# X-Forwarded-User and Paperless trusts it for its web UI (only the `trustedProxies` reach it); `apiPort` for API
# clients with a token of their own (MCP, modules/services/mcp/servers/paperless.nix), that header removed.
# Setting it up, the router rules: README.md.
let
  cfg = config.homelab.paperless;
  paperless = "http://127.0.0.1:${toString config.services.paperless.port}";
  uploads = builtins.replaceStrings [ "@maxBodySize@" ] [ cfg.maxBodySize ] (builtins.readFile ./config/uploads.conf);
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.paperless = {
    enable = lib.mkEnableOption "Paperless-ngx";
    # Where people reach it, e.g. https://docs.example.com (no trailing slash).
    url = lib.mkOption { type = lib.types.str; };
    # The front door's addresses, the only ones whose X-Forwarded-User counts.
    trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; };
    # Token-only API access.
    apiPort = lib.mkOption {
      type = lib.types.port;
      default = 8000;
    };
    # The largest upload.
    maxBodySize = lib.mkOption {
      type = lib.types.str;
      default = "200m";
    };
    # A sops file with paperless-mcp-token (40 hex), shared with the MCP server's host: a view-only mcp user with
    # that token, made and kept here (scripts/mcp-user.py). null makes none.
    mcpTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
  };

  config = lib.mkIf cfg.enable {
    services.paperless = {
      enable = true;
      # 2.20.15 isn't cached: one of its mail tests fails (test_error_skip_rule, 1 != 2), so it builds here and fails
      # the same way. Mail import isn't used. Drop once nixpkgs' build passes again.
      # The module overrides it again (tesseract's languages), so it stays overridable.
      package = lib.makeOverridable (args: (pkgs.paperless-ngx.override args).overridePythonAttrs (old: {
        disabledTests = old.disabledTests ++ [ "test_error_skip_rule" ];
      })) { };
      database.createLocally = true;
      settings = {
        PAPERLESS_URL = cfg.url;
        # The front door signs people in, its user is Paperless' (made on first sign-in, without permissions).
        PAPERLESS_ENABLE_HTTP_REMOTE_USER = true;
        PAPERLESS_HTTP_REMOTE_USER_HEADER_NAME = "HTTP_X_FORWARDED_USER";
        PAPERLESS_LOGOUT_REDIRECT_URL = "/oauth2/sign_out";
        # It's https at the front door, for CSRF checks and links.
        PAPERLESS_PROXY_SSL_HEADER = [ "HTTP_X_FORWARDED_PROTO" "https" ];
        PAPERLESS_OCR_LANGUAGE = "eng";
        # Uploads wait here for the task queue. The module's default /tmp is the task queue's private one, which
        # the web service only shares from its own start: once the queue restarts, uploads land where it can't see
        # them ("Cannot consume /tmp/paperless/...: File not found"). The data directory every service sees.
        PAPERLESS_SCRATCH_DIR = "${config.services.paperless.dataDir}/scratch";
      };
    };

    systemd.tmpfiles.settings."10-paperless-scratch"."${config.services.paperless.dataDir}/scratch".d = {
      inherit (config.services.paperless) user;
      group = config.users.users.${config.services.paperless.user}.group;
      mode = "0700";
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts = {
        # The front door's, which says who's signed in (and that it's https).
        paperless = {
          listen = [{ addr = "0.0.0.0"; port = 80; }];
          locations."/" = {
            proxyPass = paperless;
            proxyWebsockets = true;
            recommendedProxySettings = false;
            extraConfig = builtins.readFile ../web/config/published-headers.conf;
          };
          extraConfig = lib.concatMapStrings (a: "allow ${a};\n") cfg.trustedProxies + "deny all;\n"
            + uploads;
        };
        # Token clients: only the API.
        paperless-api = {
          listen = [{ addr = "0.0.0.0"; port = cfg.apiPort; }];
          locations."/api/" = {
            proxyPass = paperless;
            extraConfig = builtins.readFile ./config/api.conf;
          };
          locations."/".return = "404";
          extraConfig = uploads;
        };
      };
    };

    sops.secrets.paperless-mcp-token = lib.mkIf (cfg.mcpTokenFile != null) {
      sopsFile = cfg.mcpTokenFile;
      owner = config.services.paperless.user;
      restartUnits = [ "paperless-mcp-user.service" ];
    };

    systemd.services.paperless-mcp-user = lib.mkIf (cfg.mcpTokenFile != null) {
      description = "Paperless' mcp user and its token";
      wantedBy = [ "multi-user.target" ];
      # The scheduler migrates the database first.
      requires = [ "paperless-scheduler.service" ];
      after = [ "paperless-scheduler.service" ];
      path = [ config.services.paperless.manage ];
      serviceConfig = {
        Type = "oneshot";
        User = config.services.paperless.user;
      };
      environment.TOKEN_FILE = config.sops.secrets.paperless-mcp-token.path;
      # Django's shell runs what it's given on stdin.
      script = "paperless-manage shell < ${./scripts/mcp-user.py}";
    };

    systemd.timers.paperless-mcp-user = lib.mkIf (cfg.mcpTokenFile != null) {
      wantedBy = [ "timers.target" ];
      timerConfig.OnUnitActiveSec = "15min";
    };

    homelab.publish = {
      upstream.port = 80;
      inherit (cfg) maxBodySize;
    };

    # Only on the labs bridge, the router decides who reaches which.
    networking.firewall.allowedTCPPorts = [ 80 cfg.apiPort ];
  };
}
