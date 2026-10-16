{ config, lib, nodes, ... }:

# Every host: node exporter (zfs, systemd), smartctl on hardware, the journal shipped to Loki.
# Modules add their own endpoints to `targets`, the server scrapes every host's targets.
let
  cfg = config.homelab.monitoring;
  inherit (lib) mkOption types;

  target = types.submodule {
    options = {
      port = mkOption { type = types.port; };
      path = mkOption {
        type = types.str;
        default = "/metrics";
      };
      # https targets are scraped without verifying their certificate.
      scheme = mkOption {
        type = types.enum [ "http" "https" ];
        default = "http";
      };
      # Extra labels on every series of this target.
      labels = mkOption {
        type = types.attrsOf types.str;
        default = { };
      };
    };
  };

  servers = lib.filterAttrs (_: node: node.config.homelab.monitoring.server.enable or false) nodes;
  server = lib.head (lib.attrValues servers);
  ports = map (t: t.port) (lib.attrValues cfg.targets);
in
{
  options.homelab.monitoring = {
    enable = mkOption {
      type = types.bool;
      default = true;
    };

    # Where the server reaches this host, host types set it to their admin address.
    address = mkOption {
      type = types.str;
      default = config.networking.hostName;
    };

    # Exporter ports only open on these, null opens them everywhere.
    interfaces = mkOption {
      type = types.nullOr (types.listOf types.str);
      default = null;
    };

    # Name -> metrics endpoint on this host, the name becomes the Prometheus job.
    targets = mkOption {
      type = types.attrsOf target;
      default = { };
    };

    smartctl.enable = lib.mkEnableOption "the smartctl exporter";

    # Loki on the monitoring server, null ships no logs.
    lokiUrl = mkOption {
      type = types.nullOr types.str;
      default =
        if servers == { } then null
        else "http://${server.config.homelab.monitoring.address}:${toString server.config.homelab.monitoring.server.lokiPort}/loki/api/v1/push";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = lib.length (lib.attrNames servers) <= 1;
      message = "monitoring: more than one host has homelab.monitoring.server.enable";
    }];

    services.prometheus.exporters.node = {
      enable = true;
      enabledCollectors = [ "systemd" ];
    };

    services.prometheus.exporters.smartctl.enable = cfg.smartctl.enable;

    homelab.monitoring.targets = {
      node.port = config.services.prometheus.exporters.node.port;
      smartctl = lib.mkIf cfg.smartctl.enable { port = config.services.prometheus.exporters.smartctl.port; };
    };

    networking.firewall = if cfg.interfaces == null then {
      allowedTCPPorts = ports;
    } else {
      interfaces = lib.genAttrs cfg.interfaces (_: { allowedTCPPorts = ports; });
    };

    services.alloy.enable = cfg.lokiUrl != null;
    environment.etc."alloy/journal.alloy" = lib.mkIf (cfg.lokiUrl != null) {
      text = builtins.replaceStrings
        [ "@host@" "@lokiUrl@" ]
        [ config.networking.hostName cfg.lokiUrl ]
        (builtins.readFile ./config/journal.alloy);
    };
  };
}
