{ config, pkgs, ... }:

{
  services.frr = {
    zebra.enable = true;
    fabricd.enable = true;
  };
}
