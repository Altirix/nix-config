{ config, lib, pkgs, ... }:

# Home Assistant, published (homelab.publish) for a front door with sign-in (ha.peacocks.me), then Home
# Assistant's own login. Octopus Energy's integration compares what the meter's half-hourly readings would have
# cost on other tariffs. Setting it up, the router rule: README.md.
let
  cfg = config.homelab.home-assistant;
  port = 8123;
  # What the UI editors save, included so they load.
  uiFiles = [ "automations" "scenes" "scripts" ];
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";
    # Where it's reached, for links and callbacks built without a request.
    url = lib.mkOption { type = lib.types.str; };
    # The front door's address: only its X-Forwarded-For is believed, anything else sending one is refused.
    trustedProxies = lib.mkOption { type = lib.types.listOf lib.types.str; };
  };

  config = lib.mkIf cfg.enable {
    services.home-assistant = {
      enable = true;
      customComponents = [ pkgs.home-assistant-custom-components.octopus_energy ];
      # Integrations (Octopus Energy's API key and tariffs among them) are added in the UI, kept in its .storage.
      config = {
        default_config = { };
        homeassistant.external_url = cfg.url;
        http = {
          server_port = port;
          use_x_forwarded_for = true;
          trusted_proxies = cfg.trustedProxies;
        };
        "automation ui" = "!include automations.yaml";
        "scene ui" = "!include scenes.yaml";
        "script ui" = "!include scripts.yaml";
      };
    };

    # The includes fail to load while their files are missing.
    systemd.tmpfiles.rules = map (f: "f ${config.services.home-assistant.configDir}/${f}.yaml 0644 hass hass") uiFiles;

    homelab.publish.upstream.port = port;

    # Only on the labs bridge.
    networking.firewall.allowedTCPPorts = [ port ];
  };
}
