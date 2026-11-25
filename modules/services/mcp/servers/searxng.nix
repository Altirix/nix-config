{ config, lib, pkgs, ... }:

# Web search (packages/mcp-searxng.nix) through a SearXNG of its own on loopback, which asks Google, Bing, DuckDuckGo,
# Brave and the rest from this VM and merges what they return. An agent picks engines per search, with `engines` or
# a bang in the query (!go, !bi, !ddg, !br). web_url_read also reads any page, private addresses refused, so it
# goes on mcp-web beside fetch.
let
  cfg = config.homelab.mcp.servers.searxng;
  inherit (config.homelab.mcp.searxng) port;
in
{
  # SearXNG's own port, loopback only, the one local port the MCP server may reach (localPorts).
  options.homelab.mcp.searxng.port = lib.mkOption {
    type = lib.types.port;
    default = 8888;
  };

  config = {
    homelab.mcp.servers.searxng = {
      command = lib.mkDefault (lib.getExe (pkgs.callPackage ../packages/mcp-searxng.nix { }));
      port = lib.mkDefault 8113;
      localPorts = [ port ];
      environment = {
        SEARXNG_URL = "http://127.0.0.1:${toString port}";
        # Enough for an agent to choose from without filling its context.
        SEARXNG_MAX_RESULTS = "10";
      };
    };

    services.searx = lib.mkIf cfg.enable {
      enable = true;
      # SEARX_SECRET_KEY, made once on the VM (searx-secret below): it only signs SearXNG's own cookies.
      environmentFile = "/var/lib/searx-secret/env";
      settings = {
        server = {
          bind_address = "127.0.0.1";
          inherit port;
          secret_key = "$SEARX_SECRET_KEY";
          # Only the MCP server asks it, no bots to keep out.
          limiter = false;
          public_instance = false;
          image_proxy = false;
        };
        # The MCP server reads JSON.
        search = {
          formats = [ "html" "json" ];
          safe_search = 0;
        };
        # Merged by name into SearXNG's own list. DuckDuckGo and Startpage answer it with CAPTCHAs, so they're off;
        # Bing, Mojeek and Qwant, which mostly don't, are on beside Google and Brave. An engine that throttles or
        # challenges anyway is suspended for a while by SearXNG itself, the rest still answer.
        engines = map (name: { inherit name; disabled = false; }) [ "bing" "mojeek" "qwant" "google" "brave" ]
          ++ map (name: { inherit name; disabled = true; }) [ "duckduckgo" "startpage" ];
      };
    };

    systemd.services.searx-secret = lib.mkIf cfg.enable {
      description = "SearXNG's secret key";
      requiredBy = [ "searx-init.service" ];
      before = [ "searx-init.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "searx-secret";
        StateDirectoryMode = "0700";
        UMask = "0077";
      };
      script = ''
        [ -s "$STATE_DIRECTORY/env" ] || echo "SEARX_SECRET_KEY=$(${lib.getExe pkgs.openssl} rand -hex 32)" > "$STATE_DIRECTORY/env"
      '';
    };

    systemd.services.mcp-searxng = lib.mkIf cfg.enable {
      wants = [ "searx.service" ];
      after = [ "searx.service" ];
    };
  };
}
