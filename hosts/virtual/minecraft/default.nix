{ ... }:

# Incus VM running the Minecraft server, published on ionos-de (hosts/edge/ionos-de/networking.nix).
{
  imports = [
    ../../../modules/virtual.nix
    ../../../modules/services/minecraft
    ./hardware-configuration.nix
    ./storage.nix
    ./networking.nix
  ];

  homelab.minecraft = {
    enable = true;
    memory = "4G";
    properties = {
      motd = "homelab";
      difficulty = "normal";
      max-players = 10;
      view-distance = 12;
    };
    # whitelist.<player> = "<uuid>";
  };

  system.stateVersion = "26.05";
}
