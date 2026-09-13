{ config, pkgs, ... }:

{
  networking.interfaces.lo.ipv4.addresses = [
    {
      address = "10.255.0.10";
      prefixLength = 32;
    }
  ];

  networking.nftables.enable = true;

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
  };

  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # Incus bridge / Lan
  systemd.network.netdevs."incus-br0" = {
    netdevConfig = {
      Kind = "bridge";
      Name = "incus-br0";
    };
  };

  systemd.network.networks."incus-br0" = {
    matchConfig.Name = "incus-br0";
    address = [
      "192.168.88.11/24"
    ];
    routes = [
      {
        Gateway = "192.168.88.1";
      }
    ];
    dns = [
      "192.168.88.1"
    ];
    networkConfig = {
      DHCP = "no";
    };
  };

  # Physical NIC -> Incus bridge
  systemd.network.networks."lan" = {
    matchConfig.Name = "enp7s0";
    networkConfig = {
      Bridge = "incus-br0";
    };
  };

  # Management VLAN 90
  systemd.network.netdevs."mgmt-vlan" = {
    netdevConfig = {
      Kind = "vlan";
      Name = "mgmt-vlan";
    };
    vlanConfig.Id = 90;
  };

  systemd.network.networks."mgmt-vlan" = {
    matchConfig.Name = "mgmt-vlan";
    address = [
      "10.90.0.10/24"
    ];
    networkConfig = {
      DHCP = "no";
    };
  };

  # Physical NIC -> VLAN 90
  systemd.network.networks."mgmt" = {
    matchConfig.Name = "enp8s0f1";
    networkConfig = {
      VLAN = [
        "mgmt-vlan"
      ];
    };
  };

  # High-speed interconnects

  systemd.network.networks."mesh-a" = {
    matchConfig.Name = "enp12s0f0np0";
    networkConfig.DHCP = "no";
    linkConfig.MTUBytes = 9000;
  };

  systemd.network.networks."mesh-b" = {
    matchConfig.Name = "enp12s0f0np1";
    networkConfig.DHCP = "no";
    linkConfig.MTUBytes = 9000;
  };

  # FRR
  services.frr.config = builtins.readFile ./config/frr.config;
}