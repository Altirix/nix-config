{ ... }:

# The lab's logs (modules/services/logs), at logs.peacocks.me through the edge.
{
  imports = [
    ../../../modules/virtual.nix
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  system.stateVersion = "26.05";

  homelab.logs.collector.enable = true;
}
