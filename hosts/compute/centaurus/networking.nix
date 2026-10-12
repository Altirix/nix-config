{ config, lib, pkgs, ... }:

{
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

    systemd.network.networks = {
      "incus-br0" = {
        matchConfig.Name = "incus-br0";
        address = [ "192.168.88.19/24" ];
        routes = [{ Gateway = "192.168.88.1"; }];
        dns = [ "192.168.88.1" ];
        networkConfig.DHCP = "no";
      };

      "lan" = {
        matchConfig.Name = "enp8s0";
        networkConfig.Bridge = "incus-br0";
      };
    };
  };
}