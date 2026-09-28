{ config, lib, pkgs, ... }:

{
  options.mesh = {
    interfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
    };

    nodeId = lib.mkOption {
      type = lib.types.ints.between 1 254;
    };
  };

  config = {
    networking.nftables.enable = true;

    networking.firewall = {
      enable = true;
      allowedTCPPorts = [ ];
    };

    networking.useDHCP = false;
    networking.useNetworkd = true;
    systemd.network.enable = true;

    systemd.network.netdevs."incus-br0" = {
      netdevConfig = {
        Kind = "bridge";
        Name = "incus-br0";
      };
    };

    systemd.network.netdevs."mgmt-vlan" = {
      netdevConfig = {
        Kind = "vlan";
        Name = "mgmt-vlan";
      };
      vlanConfig.Id = 90;
    };

    systemd.network.networks =
      {
        "incus-br0" = {
          matchConfig.Name = "incus-br0";
          address = [ "192.168.88.11/24" ];
          routes = [{ Gateway = "192.168.88.1"; }];
          dns = [ "192.168.88.1" ];
          networkConfig.DHCP = "no";
        };

        "lan" = {
          matchConfig.Name = "enp7s0";
          networkConfig.Bridge = "incus-br0";
        };

        "mgmt-vlan" = {
          matchConfig.Name = "mgmt-vlan";
          address = [ "10.90.0.10/24" ];
          networkConfig.DHCP = "no";
        };

        "mgmt" = {
          matchConfig.Name = "enp8s0f1";
          networkConfig.VLAN = [ "mgmt-vlan" ];
        };

        "lo" = {
          matchConfig.Name = "lo";
          address = [
            "10.255.0.${toString config.mesh.nodeId}/32"
          ];
        };
      }
      // lib.listToAttrs (lib.imap0 (i: ifname: {
        name = "mesh-${toString i}";
        value = {
          matchConfig.Name = ifname;
          networkConfig.DHCP = "no";
          linkConfig.MTUBytes = 9000;
        };
      }) config.mesh.interfaces);
  };
}