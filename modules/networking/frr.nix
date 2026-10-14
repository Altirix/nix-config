{ config, lib, ... }:

# OpenFabric over the mesh links, config/frr.conf is filled in from these options.
let
  cfg = config.homelab.frr;
  mesh = config.homelab.mesh;
  inherit (lib) mkOption types;

  netId = lib.fixedWidthString 4 "0" (toString mesh.nodeId);

  timer = mkOption { type = types.ints.positive; };

  interfaceConfig = interface: builtins.replaceStrings
    [ "@interface@" "@tag@" "@helloInterval@" "@helloMultiplier@" ]
    [ interface cfg.tag (toString cfg.helloInterval) (toString cfg.helloMultiplier) ]
    (builtins.readFile ./config/frr-interface.conf);
in
{
  options.homelab.frr = {
    enable = lib.mkEnableOption "OpenFabric routing over homelab.mesh";

    tag = mkOption {
      type = types.str;
      default = "1";
      description = "OpenFabric instance name.";
    };

    # The system id comes from homelab.mesh.nodeId.
    area = mkOption {
      type = types.str;
      example = "49.0000";
    };

    helloInterval = timer;
    helloMultiplier = timer;
    lspGenInterval = timer;
    maxLspLifetime = timer;
    lspRefreshInterval = timer;
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = mesh.enable;
      message = "frr: needs homelab.mesh";
    }];

    # Needed for traffic to go through a third node when a direct link is down.
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = 1;
      "net.ipv4.conf.default.forwarding" = 1;
    };

    # Fallback paths are asymmetric, strict rpfilter would drop them.
    networking.firewall.checkReversePath = "loose";

    services.frr = {
      # The NixOS module already writes hostname, log syslog and the service lines.
      config = builtins.replaceStrings
        [ "@tag@" "@net@" "@interfaces@" "@lspGenInterval@" "@maxLspLifetime@" "@lspRefreshInterval@" ]
        [
          cfg.tag
          "${cfg.area}.0000.0000.${netId}.00"
          (lib.concatMapStrings interfaceConfig mesh.interfaces)
          (toString cfg.lspGenInterval)
          (toString cfg.maxLspLifetime)
          (toString cfg.lspRefreshInterval)
        ]
        (builtins.readFile ./config/frr.conf);

      fabricd.enable = true;
    };
  };
}
