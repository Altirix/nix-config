{ config, lib, nodes, ... }:

let
  cfg = config.mesh;

  prefix = "10.255.0";

  # Every host in the flake that imports this module.
  meshNodes = lib.filterAttrs (_: node: node.config ? mesh) nodes;
in
{
  options.mesh = {
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    nodeId = lib.mkOption {
      type = lib.types.ints.between 1 254;
    };

    routerIp = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${prefix}.${toString cfg.nodeId}";
    };

    network = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${prefix}.0/24";
    };

    addresses = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (_: node: node.config.mesh.routerIp) meshNodes;
    };
  };

  config = {
    assertions = [{
      assertion = lib.allUnique (lib.attrValues cfg.addresses);
      message = "mesh: nodeId must be unique across hosts";
    }];

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
