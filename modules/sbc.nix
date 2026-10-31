{ lib, ... }:

# Shared SBC defaults. Board hardware and optional services are selected by each host.
{
  homelab.secrets.groupFile = ../secrets/sbc.yaml;
  homelab.wifi.enable = lib.mkDefault true;

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
