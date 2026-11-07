{ ... }:

# InvenTree (modules/services/inventree), at inventree.peacocks.me through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.inventree = {
    enable = true;
    url = "https://inventree.peacocks.me";
    # The edge's tunnel address.
    trustedProxies = [ "10.0.0.1" ];
  };
}
