{ config, pkgs, ... }:

{
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 ]; # per-service ports get added in each service's own module
  };
  
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.network.enable = true;
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "en*"; # tighten to the real ifname once known, e.g. "enp1s0"
    address = [ "192.168.88.50/24" ];
    routes = [ { Gateway = "192.168.88.1"; } ];
    dns = [ "192.168.88.1" ];
  };

  # If this host sits under Incus/Proxmox as a guest, qemu-guest-agent
  # is worth having so the hypervisor can see IP/status:
  services.qemuGuest.enable = true;
}