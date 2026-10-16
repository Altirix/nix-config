{ config, lib, ... }:

# Public-facing hosts outside the lab: a WireGuard tunnel home with NAT and port forwards, web sites in front.
{
  imports = [
    ./services/wireguard
    ./services/web
  ];

  homelab = {
    secrets.groupFile = ../secrets/edge.yaml;

    wireguard.enable = lib.mkDefault true;

    web.enable = lib.mkDefault true;

    # Scraped through the tunnel, never on the public address.
    monitoring = {
      address = lib.head (lib.splitString "/" (lib.head config.homelab.wireguard.address));
      interfaces = [ config.homelab.wireguard.interface ];
    };
  };

  networking.nftables.enable = true;
  networking.firewall.enable = true;
  networking.useNetworkd = true;

  # Key-only (system/ssh.nix), reachable from anywhere.
  networking.firewall.allowedTCPPorts = [ 22 ];

  sops.secrets = {
    "edge-hello" = {
      sopsFile = config.homelab.secrets.groupFile;
      key = "hello";
    };
  };
}
