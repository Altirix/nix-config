{ config, lib, nodes, ... }:

# Routed full mesh between hosts over direct links, plus a VXLAN overlay for instances.
let
  cfg = config.homelab.mesh;
  inherit (lib) mkOption types;

  # Every host in the flake with the mesh enabled, hosts without the module are skipped.
  meshNodes = lib.filterAttrs (_: node: node.config.homelab.mesh.enable or false) nodes;
in
{
  options.homelab.mesh = {
    enable = lib.mkEnableOption "routed mesh between hosts";

    interfaces = mkOption {
      type = types.listOf types.str;
      default = [ ];
    };

    nodeId = mkOption {
      type = types.ints.between 1 254;
    };

    # /24 the loopbacks live in, nodeId is the last octet.
    prefix = mkOption {
      type = types.str;
      example = "10.255.0";
    };

    mtu = mkOption {
      type = types.ints.positive;
      default = 1500;
    };

    routerIp = mkOption {
      type = types.str;
      readOnly = true;
      default = "${cfg.prefix}.${toString cfg.nodeId}";
    };

    network = mkOption {
      type = types.str;
      readOnly = true;
      default = "${cfg.prefix}.0/24";
    };

    addresses = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      default = lib.mapAttrs (_: node: node.config.homelab.mesh.routerIp) meshNodes;
    };

    # VXLAN between loopbacks, instances bridge onto this and never see the underlay.
    overlay = {
      enable = lib.mkEnableOption "the VXLAN overlay";

      interface = mkOption {
        type = types.str;
        default = "mesh-vx"; # IFNAMSIZ caps names at 15 chars
      };

      vni = mkOption {
        type = types.ints.unsigned;
        default = 1;
      };

      port = mkOption {
        type = types.port;
        default = 4789;
      };

      mtu = mkOption {
        type = types.ints.positive;
        readOnly = true;
        default = cfg.mtu - 50; # VXLAN over IPv4 overhead
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
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
            linkConfig.MTUBytes = cfg.mtu;
          };
        }) cfg.interfaces);
    }

    (lib.mkIf cfg.overlay.enable {
      systemd.network.netdevs.${cfg.overlay.interface} = {
        netdevConfig = {
          Kind = "vxlan";
          Name = cfg.overlay.interface;
          MTUBytes = cfg.overlay.mtu;
        };
        vxlanConfig = {
          VNI = cfg.overlay.vni;
          Local = cfg.routerIp;
          DestinationPort = cfg.overlay.port;
          Independent = true;
          MacLearning = true;
        };
      };

      # Head-end replication: floods go out once per peer, never back into the overlay.
      systemd.network.networks.${cfg.overlay.interface} = {
        matchConfig.Name = cfg.overlay.interface;
        networkConfig.LinkLocalAddressing = "no";
        bridgeFDBs = map (peer: {
          MACAddress = "00:00:00:00:00:00";
          Destination = peer;
        }) (lib.filter (ip: ip != cfg.routerIp) (lib.attrValues cfg.addresses));
      };
    })
  ]);
}
