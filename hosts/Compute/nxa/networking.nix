{ config, pkgs, ... }:

{
  networking.interfaces.lo.ipv4.addresses = [
    { address = "10.99.0.1"; prefixLength = 32; }
  ];

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # per-service ports get added in each service's own module
  };
  
  networking.useDHCP = false;
  networking.useNetworkd = true;
  systemd.network.enable = true;

  systemd.network.networks."10-lan" = {
    matchConfig.Name = "ens18";
    address = [ "192.168.88.50/24" ];
    routes = [ { Gateway = "192.168.88.1"; } ];
    dns = [ "192.168.88.1" ];
  };

  networking.interfaces.enp1s0.mtu = 9000;
  networking.interfaces.enp2s0.mtu = 9000;

  services.frr.config = builtins.readFile ./config/frr.config;
}