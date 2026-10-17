{ lib, ... }:

# 3D printer hosts: Klipper, Moonraker and Mainsail on a board next to the printer.
# Hosts set the board and their printer.cfg.
{
  imports = [
    ./services/klipper
  ];

  homelab.secrets.groupFile = ../secrets/printer.yaml;

  homelab.klipper = {
    enable = true;
    trustedClients = [ "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" "fe80::/10" ];
  };

  # eMMC / SD roots: compressed, checksummed, no out-of-tree module.
  homelab.storage.boot.filesystem = lib.mkDefault "btrfs";

  networking.useDHCP = true;
  # Plain LAN, no admin VLAN.
  networking.firewall.allowedTCPPorts = [ 22 ];
  # Reachable as <hostname>.local.
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
}
