{ config, pkgs, ... }:

{
  networking.interfaces.lo.ipv4.addresses = [
    { address = "10.99.0.1"; prefixLength = 32; }
  ];

  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ]; # ports enabled on service's own module
  };

  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;

  # --- incus-br0: bridge device + its config ---
  systemd.network.netdevs."incus-br0".netdevConfig = {
    Kind = "bridge";
    Name = "incus-br0";
  };
  systemd.network.networks."incus-br0" = {
    matchConfig.Name = "incus-br0";
    address = [ "192.168.88.50/24" ];
    routes = [ { Gateway = "192.168.88.1"; } ];
    dns = [ "192.168.88.1" ];
    networkConfig.DHCP = "no";
  };

  # --- mgmt-vlan: VLAN device + its config ---
  systemd.network.netdevs."mgmt-vlan" = {
    netdevConfig = {
      Kind = "vlan";
      Name = "mgmt-vlan";
    };
    vlanConfig.Id = 90;
  };
  systemd.network.networks."mgmt-vlan" = {
    matchConfig.Name = "mgmt-vlan";
    address = [ "10.90.0.100/24" ];
    networkConfig.DHCP = "no";
  };

  # --- ens18: physical NIC, sorts traffic to the two devices above ---
  systemd.network.networks."lan" = {
    matchConfig.Name = "ens18";
    networkConfig = {
      Bridge = "incus-br0";
      VLAN = [ "mgmt-vlan" ];
    };
  };

  networking.interfaces.enp1s0.mtu = 9000;
  networking.interfaces.enp2s0.mtu = 9000;

  services.frr.config = builtins.readFile ./config/frr.config;
}