{ ... }:

# Home Assistant (modules/services/home-assistant), at ha.peacocks.me through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.home-assistant = {
    enable = true;
    url = "https://ha.peacocks.me";
    # The edge's tunnel address.
    trustedProxies = [ "10.0.0.1" ];
  };
}
