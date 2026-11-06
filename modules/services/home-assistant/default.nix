{ config, lib, pkgs, ... }:

# Home Assistant, published (homelab.publish) for a front door with sign-in (ha.peacocks.me), then Home
# Assistant's own login. Octopus Energy's integration compares what the meter's half-hourly readings would have
# cost on other tariffs. Setting it up, the router rule: README.md.
let
  cfg = config.homelab.home-assistant;
in
{
  imports = [ ../web/publish.nix ];

  options.homelab.home-assistant = {
    enable = lib.mkEnableOption "Home Assistant";
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
        http = {
          server_port = 8123;
          use_x_forwarded_for = true;
          trusted_proxies = cfg.trustedProxies;
        };
      };
    };

    homelab.publish.upstream.port = config.services.home-assistant.config.http.server_port;

    # Only on the labs bridge.
    networking.firewall.allowedTCPPorts = [ config.services.home-assistant.config.http.server_port ];
  };
}
