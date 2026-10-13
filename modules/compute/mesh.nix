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

    # VXLAN between loopbacks, instances bridge onto this and never see the underlay.
    labsMeshUplink = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "labs-mesh-vx"; # IFNAMSIZ caps names at 15 chars
    };

    labsMeshMtu = lib.mkOption {
      type = lib.types.int;
      readOnly = true;
      default = 9000 - 50; # VXLAN over IPv4 overhead
    };
  };

  config = {
    assertions = [{
      assertion = lib.allUnique (lib.attrValues cfg.addresses);
      message = "mesh: nodeId must be unique across hosts";
    }];

    networking.firewall.trustedInterfaces = cfg.interfaces;

    systemd.network.netdevs.${cfg.labsMeshUplink} = {
      netdevConfig = {
        Kind = "vxlan";
        Name = cfg.labsMeshUplink;
        MTUBytes = cfg.labsMeshMtu;
      };
      vxlanConfig = {
        VNI = 1;
        Local = cfg.routerIp;
        DestinationPort = 4789;
        Independent = true;
        MacLearning = true;
      };
    };

    systemd.network.networks =
      {
        "lo" = {
          matchConfig.Name = "lo";
          address = [ "${cfg.routerIp}/32" ];
        };

        # Head-end replication: floods go out once per peer, never back into the overlay.
        ${cfg.labsMeshUplink} = {
          matchConfig.Name = cfg.labsMeshUplink;
          networkConfig.LinkLocalAddressing = "no";
          bridgeFDBs = map (peer: {
            MACAddress = "00:00:00:00:00:00";
            Destination = peer;
          }) (lib.filter (ip: ip != cfg.routerIp) (lib.attrValues cfg.addresses));
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
