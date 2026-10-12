{ config, lib, ... }:

let
  cfg = config.mesh;

  prefix = "10.255.0";

  # Every mesh node and its id, the single source of truth for addressing.
  nodes = {
    andromeda = 1;
    bode = 2;
    centaurus = 3;
  };
in
{
  options.mesh = {
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    nodeId = lib.mkOption {
      type = lib.types.ints.between 1 254;
      readOnly = true;
      default = nodes.${config.networking.hostName};
    };

    routerIp = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = cfg.addresses.${config.networking.hostName};
    };

    network = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${prefix}.0/24";
    };

    addresses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (_: id: "${prefix}.${toString id}") nodes;
    };
  };

  config = {
    networking.firewall.trustedInterfaces = cfg.interfaces;

    systemd.network.networks =
      {
        "lo" = {
          matchConfig.Name = "lo";
          address = [ "${cfg.routerIp}/32" ];
        };
      }
      # Unnumbered links: reuse the loopback /32 on every mesh interface so
      # hellos carry an IPv4 address and FRR has a next hop to install.
      // lib.listToAttrs (lib.imap0 (i: ifname: {
        name = "mesh-${toString i}";
        value = {
          matchConfig.Name = ifname;
          address = [ "${cfg.routerIp}/32" ];
          networkConfig.DHCP = "no";
          linkConfig.MTUBytes = 9000;
        };
      }) cfg.interfaces);
  };
}
