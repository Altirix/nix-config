{ config, ... }:

# Storage nodes, HDD pools are described per host in storage.nix.
{
  homelab.secrets.groupFile = ../secrets/storage.yaml;

  # Hosts on a VLAN trunk should use homelab.lan admin VLANs instead.
  networking.firewall.allowedTCPPorts = [ 22 ];

  sops.secrets = {
    "storage-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
